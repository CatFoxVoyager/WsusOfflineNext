// WsusOfflineUpdater.exe - the dedicated self-update updater (Phase 28).
//
// Launched by the host's accept path (UpdateInstall.RunAsync) with the
// frozen CLI contract:
//   --pid <int>              process id of the host that launched us; the
//                            swap waits for its natural exit
//   --staging <dir>          staging directory whose wsusoffline\ subtree
//                            carries the VERIFIED new application tree
//   --backup <dir>           archive target for the replaced files
//                            (sibling of the install root, .bak-timestamp)
//   --relaunch <exe path>    the application binary to relaunch after the
//                            swap (the host's own exe)
//   --marker <file>          healthy-launch marker path: the relaunched app
//                            writes the file after its main window opens;
//                            the watchdog below consumes it
//   --watchdog-seconds <int> bounded healthy-launch watchdog window in
//                            seconds (default 30). A new version that has
//                            not written the marker within the window is
//                            killed, the installation is restored from the
//                            backup and the previous version is relaunched
//
// The install root is the updater's own directory (the updater ships inside
// the installation it maintains). The swap is ZIP-MANIFEST-DRIVEN: only
// files present in the staged tree are archived and replaced; the
// installation's user payload (downloaded updates under client\ and
// siblings) is never touched.
//
// Exit codes: 0 updated (swap done, healthy launch confirmed); 2 bad or
// incomplete arguments / incomplete staging tree; 3 swap failure (backup
// restored, old binary relaunched); 4 unhealthy first launch of the new
// version (marker absent within the watchdog window or the relaunch never
// started: rolled back, previous version relaunched); 5 restore failure
// (manual restore path documented in the log - rename the backup folder).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using WsusOfflineNext.SelfUpdate;

namespace WsusOfflineNext.Updater
{
    internal static class Program
    {
        private const int RetryAttempts = 10;
        private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(1);
        private static readonly TimeSpan PollDelay = TimeSpan.FromMilliseconds(500);

        // Watchdog default (Phase 28 context decision): framework-dependent
        // single-file exes start in seconds even on slow HDDs under AV
        // scanning, so 30 seconds bounds the user-visible stall while
        // comfortably covering cold starts. The window is bounded by design
        // (T-28-09): a hung new version is killed only inside it, and only
        // when the updater itself launched it.
        private const int WatchdogDefaultSeconds = 30;

        private sealed class UpdaterArgs
        {
            public int Pid = -1;
            public string Staging = "";
            public string Backup = "";
            public string Relaunch = "";
            public string Marker = "";
            public int WatchdogSeconds = WatchdogDefaultSeconds;
        }

        private static int Main(string[] arguments)
        {
            UpdaterArgs? args = ParseArgs(arguments);
            if (args == null)
            {
                Console.WriteLine(
                    "usage: WsusOfflineUpdater.exe --pid <int> --staging <dir> " +
                    "--backup <dir> --relaunch <exe> --marker <file> " +
                    "[--watchdog-seconds <int>]");
                return 2;
            }

            Console.WriteLine(
                $"updater start: pid={args.Pid} staging={args.Staging} " +
                $"backup={args.Backup} relaunch={args.Relaunch} " +
                $"marker={args.Marker} watchdog-seconds={args.WatchdogSeconds}");
            SelfUpdateLog.Append("updater", "updater-start");

            // The staged tree root as published by the release zip: every
            // entry lives under a top-level wsusoffline\ directory.
            string stagedTree = Path.Combine(args.Staging, "wsusoffline");
            if (!IsStagedTreeComplete(stagedTree))
            {
                SelfUpdateLog.Append("updater", "staging-incomplete");
                Console.WriteLine(
                    "updater: staged tree is incomplete - expected " +
                    "UpdateGeneratorModern.exe, client\\UpdateInstallerModern.exe " +
                    "and WsusOfflineUpdater.exe under " + stagedTree);
                Console.WriteLine("updater: nothing was changed.");
                return 2;
            }

            // ---- Wait phase: no timeout by design (the updater is launched
            // to wait); a 2-second settle covers the launcher .cmd teardown
            // after the host process itself has exited.
            Console.WriteLine($"updater: waiting for process {args.Pid} to exit...");
            while (IsProcessAlive(args.Pid))
            {
                Thread.Sleep(PollDelay);
            }
            SelfUpdateLog.Append("updater", "wait-exit");
            Console.WriteLine("updater: caller exited, settling 2s...");
            Thread.Sleep(TimeSpan.FromSeconds(2));

            // ---- Backup directory: prefer the host's sibling-of-root path;
            // fall back to %TEMP% when the sibling cannot be created.
            string backupDir = args.Backup;
            try
            {
                Directory.CreateDirectory(backupDir);
            }
            catch (Exception ex)
            {
                backupDir = Path.Combine(Path.GetTempPath(), "WsusOfflineNext-Update",
                    "backup-" + DateTime.Now.ToString("yyyyMMdd-HHmmss"));
                Directory.CreateDirectory(backupDir);
                SelfUpdateLog.Append("updater", "backup-fallback");
                Console.WriteLine($"updater: backup path fallback to {backupDir} ({ex.Message})");
            }

            string installRoot = AppContext.BaseDirectory;
            List<string> manifest = EnumerateManifest(stagedTree);
            List<string> archived = new List<string>();

            // ---- Swap phase, zip-manifest-driven. Pass 1 replaces files the
            // installation already carries (archive-move first, staged copy
            // immediately after - the archive is what the restore path uses);
            // pass 2 lands files the new release adds. Anything in the
            // install root that is NOT in the manifest is never touched.
            SelfUpdateLog.Append("updater", "archive-start");
            foreach (string relative in manifest)
            {
                string target = Path.Combine(installRoot, relative);
                if (!File.Exists(target)) continue;
                string backupCopy = Path.Combine(backupDir, relative);
                if (!TryWithRetry(() =>
                    {
                        string? dir = Path.GetDirectoryName(backupCopy);
                        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                        File.Move(target, backupCopy);
                    }, $"archive-move {relative}")
                    || !TryWithRetry(() =>
                    {
                        string? dir = Path.GetDirectoryName(target);
                        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                        File.Copy(Path.Combine(stagedTree, relative), target, overwrite: true);
                    }, $"swap-copy {relative}"))
                {
                    return FailSwap(args, backupDir, archived);
                }
                archived.Add(relative);
            }
            SelfUpdateLog.Append("updater", "archive-complete");

            foreach (string relative in manifest)
            {
                string target = Path.Combine(installRoot, relative);
                if (File.Exists(target)) continue; // already replaced in pass 1
                if (!TryWithRetry(() =>
                    {
                        string? dir = Path.GetDirectoryName(target);
                        if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                        File.Copy(Path.Combine(stagedTree, relative), target, overwrite: true);
                    }, $"add-copy {relative}"))
                {
                    return FailSwap(args, backupDir, archived);
                }
            }
            SelfUpdateLog.Append("updater", "swap-complete");
            Console.WriteLine($"updater: swap complete - {archived.Count} replaced, " +
                              $"{manifest.Count - archived.Count} added, backup at {backupDir}");

            // ---- Relaunch phase: the ONLY process the updater ever starts
            // is the verified application binary itself (no helpers, no
            // scripts, no shells - T-28-06).
            Process? relaunched;
            try
            {
                relaunched = RelaunchNew(args.Relaunch, args.Marker);
            }
            catch (Exception ex)
            {
                // A new exe that cannot even start never writes the marker:
                // relaunch failure converges on the same unhealthy path as a
                // marker timeout (rollback, exit 4).
                SelfUpdateLog.Append("updater", "relaunch-failed");
                Console.WriteLine($"updater: relaunch failed ({ex.Message})");
                return Rollback(args, backupDir, archived, relaunched: null);
            }
            SelfUpdateLog.Append("updater", "relaunch-start");
            Console.WriteLine($"updater: relaunched {args.Relaunch}");

            // ---- Watchdog phase: poll for the healthy-launch marker that
            // the NEW app writes after its main window opens. Bounded window
            // (WatchdogDefaultSeconds, CLI-tunable), 500ms polling (T-28-09).
            DateTime deadline = DateTime.UtcNow +
                TimeSpan.FromSeconds(args.WatchdogSeconds);
            while (DateTime.UtcNow < deadline && !File.Exists(args.Marker))
            {
                Thread.Sleep(PollDelay);
            }
            if (File.Exists(args.Marker))
            {
                SelfUpdateLog.Append("updater", "marker-received");
                Console.WriteLine("updater: healthy-launch marker received");
                TryDeleteStaging(args.Staging);
                PruneOldBackups(backupDir);
                return 0;
            }

            SelfUpdateLog.Append("updater", "marker-timeout");
            Console.WriteLine(
                $"updater: marker absent after {args.WatchdogSeconds}s - " +
                "the new version is unhealthy, rolling back");
            return Rollback(args, backupDir, archived, relaunched);
        }

        /// <summary>
        /// Fail-closed staging validation BEFORE any mutation (T-28-04): the
        /// three application executables must be present in the staged tree.
        /// </summary>
        private static bool IsStagedTreeComplete(string stagedTree)
        {
            return File.Exists(Path.Combine(stagedTree, "UpdateGeneratorModern.exe"))
                && File.Exists(Path.Combine(stagedTree, "client", "UpdateInstallerModern.exe"))
                && File.Exists(Path.Combine(stagedTree, "WsusOfflineUpdater.exe"));
        }

        private static bool IsProcessAlive(int pid)
        {
            try
            {
                return !Process.GetProcessById(pid).HasExited;
            }
            catch
            {
                return false; // pid gone: ArgumentException, or not accessible
            }
        }

        private static List<string> EnumerateManifest(string stagedTree)
        {
            List<string> manifest = new List<string>();
            foreach (string path in Directory.EnumerateFiles(
                         stagedTree, "*", SearchOption.AllDirectories))
            {
                manifest.Add(path.Substring(stagedTree.Length + 1));
            }
            manifest.Sort(StringComparer.OrdinalIgnoreCase);
            return manifest;
        }

        /// <summary>
        /// Per-file retry on IOException/UnauthorizedAccessException (locked
        /// .cmd launchers, AV scanners). Up to 10 attempts, 1s apart.
        /// </summary>
        private static bool TryWithRetry(Action action, string description)
        {
            for (int attempt = 1; attempt <= RetryAttempts; attempt++)
            {
                try
                {
                    action();
                    return true;
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
                {
                    Console.WriteLine($"updater: {description} failed " +
                                      $"({attempt}/{RetryAttempts}): {ex.Message}");
                    if (attempt < RetryAttempts) Thread.Sleep(RetryDelay);
                }
            }
            return false;
        }

        /// <summary>
        /// Swap failure path: restore every already-archived file from the
        /// backup, relaunch the OLD binary (it was restored), exit 3. When
        /// the restore itself fails: exit 5 and name the manual path.
        /// </summary>
        private static int FailSwap(UpdaterArgs args, string backupDir, List<string> archived)
        {
            SelfUpdateLog.Append("updater", "swap-failed");
            Console.WriteLine("updater: swap failed - restoring from backup...");
            int outcome = RestoreAndRelaunchOld(args, backupDir, archived);
            return outcome == 0 ? 3 : outcome;
        }

        /// <summary>
        /// Unhealthy-first-launch rollback (watchdog timeout or a relaunch
        /// that never started): kill the relaunched process when it is still
        /// alive (the updater owns it - a hung new version is exactly this
        /// case), settle 2s so its file handles close, then restore and
        /// relaunch the OLD binary. Exit 4 on rollback, 5 when the restore
        /// itself fails.
        /// </summary>
        private static int Rollback(
            UpdaterArgs args, string backupDir, List<string> archived, Process? relaunched)
        {
            if (relaunched != null)
            {
                try
                {
                    relaunched.Refresh();
                    if (!relaunched.HasExited)
                    {
                        Console.WriteLine(
                            $"updater: killing the hung relaunched process (pid {relaunched.Id})");
                        relaunched.Kill(entireProcessTree: true);
                    }
                }
                catch (Exception ex)
                {
                    Console.WriteLine(
                        $"updater: kill of the hung process failed ({ex.Message})" +
                        " - continuing rollback");
                }
            }
            Thread.Sleep(TimeSpan.FromSeconds(2));
            int outcome = RestoreAndRelaunchOld(args, backupDir, archived);
            return outcome == 0 ? 4 : outcome;
        }

        /// <summary>
        /// Shared restore tail: copy every archived file back from the
        /// backup, then relaunch the OLD binary at the same path WITHOUT the
        /// marker argument (a pre-28 version does not know the flag, and the
        /// restored app is known-good: it is never watchdogged - no second
        /// failure loop fighting the user). Returns 0 when the restore
        /// succeeded, 5 when it failed (manual restore path named in the
        /// log and on the console).
        /// </summary>
        private static int RestoreAndRelaunchOld(
            UpdaterArgs args, string backupDir, List<string> archived)
        {
            string installRoot = AppContext.BaseDirectory;
            bool restored = true;
            foreach (string relative in archived)
            {
                string backupCopy = Path.Combine(backupDir, relative);
                string target = Path.Combine(installRoot, relative);
                if (!TryWithRetry(() =>
                        File.Copy(backupCopy, target, overwrite: true),
                        $"restore {relative}"))
                {
                    restored = false;
                }
            }
            if (!restored)
            {
                SelfUpdateLog.Append("updater", "updater-restore-failed");
                Console.WriteLine(
                    "updater: RESTORE FAILED - manual restore path: rename " +
                    $"{backupDir} back over the installation directory.");
                return 5;
            }
            RelaunchOld(args.Relaunch);
            SelfUpdateLog.Append("updater", "relaunch-start");
            SelfUpdateLog.Append("updater", "rollback-complete");
            Console.WriteLine(
                $"updater: rollback complete - previous version restored and " +
                $"relaunched ({args.Relaunch})");
            return 0;
        }

        private static Process? RelaunchNew(string exePath, string markerPath)
        {
            var psi = new ProcessStartInfo(exePath)
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            psi.ArgumentList.Add("--healthy-marker");
            psi.ArgumentList.Add(markerPath);
            return Process.Start(psi);
        }

        /// <summary>
        /// The restored previous version never receives the marker argument:
        /// a pre-28 version does not know the flag, and a known-good restore
        /// is never watchdogged (prohibition: no second failure loop).
        /// </summary>
        private static void RelaunchOld(string exePath)
        {
            try
            {
                var psi = new ProcessStartInfo(exePath)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using Process? process = Process.Start(psi);
            }
            catch (Exception ex)
            {
                // The restore already succeeded - a relaunch failure of the
                // old binary must not turn the rollback into exit 5.
                SelfUpdateLog.Append("updater", "relaunch-failed");
                Console.WriteLine(
                    $"updater: relaunch of the restored version failed ({ex.Message})");
            }
        }

        /// <summary>
        /// Best-effort staging cleanup after a healthy update: log on
        /// failure, never fatal (the update itself is complete).
        /// </summary>
        private static void TryDeleteStaging(string stagingDir)
        {
            try
            {
                Directory.Delete(stagingDir, recursive: true);
            }
            catch (Exception ex)
            {
                SelfUpdateLog.Append("updater", "staging-cleanup-failed");
                Console.WriteLine($"updater: staging cleanup failed ({ex.Message})");
            }
        }

        /// <summary>
        /// Backup retention: exactly one backup survives a successful update
        /// - the newest. Older timestamped siblings sharing the current
        /// backup's stem (host-minted root-name.bak-timestamp next to the
        /// install root, or the %TEMP% backup-timestamp fallback) are
        /// pruned; the newest is NEVER deleted (the manual-restore path
        /// renames it back over the installation).
        /// </summary>
        private static void PruneOldBackups(string backupDir)
        {
            try
            {
                string trimmed = Path.TrimEndingDirectorySeparator(backupDir);
                if (TrySplitBackupName(Path.GetFileName(trimmed), out string stem))
                {
                    PruneTimestampedSiblings(Path.GetDirectoryName(trimmed), stem);
                }
                // Stale %TEMP% fallbacks from runs whose sibling backup could
                // not be created: keep the newest there too.
                string tempRoot = Path.Combine(
                    Path.GetTempPath(), "WsusOfflineNext-Update");
                if (!string.Equals(Path.GetDirectoryName(trimmed), tempRoot,
                        StringComparison.OrdinalIgnoreCase))
                {
                    PruneTimestampedSiblings(tempRoot, "backup");
                }
            }
            catch (Exception ex)
            {
                SelfUpdateLog.Append("updater", "backup-prune-failed");
                Console.WriteLine($"updater: backup pruning failed ({ex.Message})");
            }
        }

        /// <summary>
        /// A backup name is "stem + -yyyyMMdd-HHmmss" (16 trailing
        /// characters). Anything else is not ours to prune.
        /// </summary>
        private static bool TrySplitBackupName(string name, out string stem)
        {
            const int SuffixLength = 16; // '-' + 8 digits + '-' + 6 digits
            stem = "";
            if (name.Length <= SuffixLength) return false;
            string suffix = name.Substring(name.Length - SuffixLength);
            if (suffix[0] != '-' || suffix[9] != '-') return false;
            foreach (char c in suffix)
            {
                if (c != '-' && (c < '0' || c > '9')) return false;
            }
            stem = name.Substring(0, name.Length - SuffixLength);
            return stem.Length > 0;
        }

        /// <summary>
        /// Delete every stem-timestamped directory older than the newest
        /// one under parent. The timestamp suffix sorts chronologically, so
        /// index 0 after the descending sort is the kept newest.
        /// </summary>
        private static void PruneTimestampedSiblings(string? parent, string stem)
        {
            if (string.IsNullOrEmpty(parent) || !Directory.Exists(parent)) return;
            List<string> siblings = new List<string>();
            foreach (string dir in Directory.EnumerateDirectories(parent))
            {
                string name = Path.GetFileName(Path.TrimEndingDirectorySeparator(dir));
                if (name.StartsWith(stem + "-", StringComparison.Ordinal)
                    && TrySplitBackupName(name, out string found)
                    && found == stem)
                {
                    siblings.Add(name);
                }
            }
            if (siblings.Count < 2) return; // nothing older than the newest
            siblings.Sort(StringComparer.OrdinalIgnoreCase);
            siblings.Reverse(); // newest first: index 0 is kept
            for (int i = 1; i < siblings.Count; i++)
            {
                try
                {
                    Directory.Delete(Path.Combine(parent, siblings[i]), recursive: true);
                    Console.WriteLine($"updater: pruned old backup {siblings[i]}");
                }
                catch (Exception ex)
                {
                    Console.WriteLine(
                        $"updater: pruning {siblings[i]} failed ({ex.Message})");
                }
            }
        }

        private static UpdaterArgs? ParseArgs(string[] arguments)
        {
            var args = new UpdaterArgs();
            for (int i = 0; i < arguments.Length; i++)
            {
                switch (arguments[i])
                {
                    case "--pid":
                        if (i + 1 >= arguments.Length
                            || !int.TryParse(arguments[++i], out args.Pid)) return null;
                        break;
                    case "--staging":
                        if (i + 1 >= arguments.Length) return null;
                        args.Staging = arguments[++i];
                        break;
                    case "--backup":
                        if (i + 1 >= arguments.Length) return null;
                        args.Backup = arguments[++i];
                        break;
                    case "--relaunch":
                        if (i + 1 >= arguments.Length) return null;
                        args.Relaunch = arguments[++i];
                        break;
                    case "--marker":
                        if (i + 1 >= arguments.Length) return null;
                        args.Marker = arguments[++i];
                        break;
                    case "--watchdog-seconds":
                        if (i + 1 >= arguments.Length
                            || !int.TryParse(arguments[++i], out args.WatchdogSeconds)) return null;
                        break;
                    default:
                        return null;
                }
            }
            if (args.Pid <= 0 || args.Staging.Length == 0 || args.Backup.Length == 0
                || args.Relaunch.Length == 0 || args.Marker.Length == 0)
            {
                return null;
            }
            return args;
        }
    }
}
