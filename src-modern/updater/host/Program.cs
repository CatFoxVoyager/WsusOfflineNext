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
//   --marker <file>          healthy-launch marker path the relaunched app
//                            writes after its window opens (the path is
//                            minted by the host; the watchdog that consumes
//                            it arrives in Plan 03)
//   --watchdog-seconds <int> parsed and carried but NOT acted on in v1 -
//                            part of the frozen contract, consumed by the
//                            Plan 03 watchdog without architectural change
//
// The install root is the updater's own directory (the updater ships inside
// the installation it maintains). The swap is ZIP-MANIFEST-DRIVEN: only
// files present in the staged tree are archived and replaced; the
// installation's user payload (downloaded updates under client\ and
// siblings) is never touched.
//
// Exit codes: 0 updated (swap done, relaunch started); 2 bad or incomplete
// arguments / incomplete staging tree; 3 swap failure (backup restored, old
// binary relaunched); 5 restore failure (manual restore path documented in
// the log - rename the backup folder).

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

        private sealed class UpdaterArgs
        {
            public int Pid = -1;
            public string Staging = "";
            public string Backup = "";
            public string Relaunch = "";
            public string Marker = "";
            public int WatchdogSeconds = 30;
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
            // scripts, no shells - T-28-06). v1 exits right after the launch;
            // the healthy-launch watchdog is Plan 03.
            Relaunch(args.Relaunch, args.Marker);
            SelfUpdateLog.Append("updater", "relaunch-start");
            Console.WriteLine($"updater: relaunched {args.Relaunch}");
            return 0;
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
            Relaunch(args.Relaunch, args.Marker);
            SelfUpdateLog.Append("updater", "relaunch-start");
            Console.WriteLine($"updater: restored and relaunched the previous version ({args.Relaunch})");
            return 3;
        }

        private static void Relaunch(string exePath, string markerPath)
        {
            var psi = new ProcessStartInfo(exePath)
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            psi.ArgumentList.Add("--healthy-marker");
            psi.ArgumentList.Add(markerPath);
            using Process? process = Process.Start(psi);
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
