using System;
using System.Diagnostics;
using System.Drawing;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace WsusOfflineNext.SelfUpdate
{
    /// <summary>
    /// One accepted update offer: the channel version plus the two real
    /// download URLs already validated by SelfUpdateChannel.ParseLinksFile
    /// (https-only, pinned suffixes) during the check slice.
    /// </summary>
    public sealed record UpdateOffer(string ChannelVersion, string ZipUrl, string HashesUrl);

    /// <summary>
    /// Host-side accept path, shared by both .NET hosts (compiled alongside
    /// UpdateCheck.cs). Downloads the release zip and its hashes file to a
    /// %TEMP% staging folder, verifies the zip fail-closed against the
    /// published SHA256, extracts with a zip-slip guard, asserts the staged
    /// tree is complete, then launches WsusOfflineUpdater.exe with the frozen
    /// CLI contract. The swap itself never runs here: the host stays alive
    /// until its natural exit and the updater does the file work.
    /// </summary>
    public static class UpdateInstall
    {
        // Small text fetch (hashes file) mirrors the check slice's client;
        // the zip needs its own client because a 10s timeout cannot carry a
        // multi-hundred-megabyte download on slow links.
        private static readonly HttpClient HttpQuick = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(10)
        };
        private static readonly HttpClient HttpDownload = new HttpClient
        {
            Timeout = TimeSpan.FromMinutes(30)
        };

        // Published _hashes.txt SHA256 field: exactly 64 lowercase hex chars.
        private static readonly Regex Sha256Pattern =
            new Regex("^[0-9a-f]{64}$", RegexOptions.Compiled);

        /// <summary>
        /// Parse the published hashes file as MEASURED from the release
        /// pipeline (hashdeep -c md5,sha1,sha256 -b): data lines are
        /// "size,md5,sha1,sha256,filename", comma-separated, lowercase hex,
        /// filename last (and naming the PRE-rename zip). Lines that are
        /// empty, start with "%%%%" or start with "##" are headers. Exactly
        /// one data line is required; field POSITION decides (never the
        /// filename): field 0 = size (&gt; 0), field 3 = SHA256. Anything
        /// else returns null.
        /// </summary>
        public static (long Size, string Sha256)? ParseHashesFile(string? text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            string? dataLine = null;
            foreach (string rawLine in text.Split('\n'))
            {
                string line = rawLine.Trim('\r').Trim();
                if (line.Length == 0) continue;
                if (line.StartsWith("%%%%", StringComparison.Ordinal)) continue;
                if (line.StartsWith("##", StringComparison.Ordinal)) continue;
                if (dataLine != null) return null; // more than one data line
                dataLine = line;
            }
            if (dataLine == null) return null;
            string[] fields = dataLine.Split(',');
            if (fields.Length < 4) return null;
            foreach (string field in fields)
            {
                if (field.Length == 0) return null;
            }
            if (!long.TryParse(fields[0], NumberStyles.Integer,
                    CultureInfo.InvariantCulture, out long size) || size <= 0)
            {
                return null;
            }
            if (!Sha256Pattern.IsMatch(fields[3])) return null;
            return (size, fields[3]);
        }

        /// <summary>
        /// FAIL-CLOSED verification - the only gate between the download and
        /// the extraction. True only when the hashes text parses, the file
        /// length matches the published size AND the SHA256 of the file bytes
        /// equals the published digest. Anything else (unreadable hashes,
        /// wrong size, wrong digest, unreadable zip) is false.
        /// </summary>
        public static bool VerifyZipAgainstHashes(string zipPath, string? hashesText)
        {
            (long Size, string Sha256)? parsed = ParseHashesFile(hashesText);
            if (parsed == null) return false;
            try
            {
                using FileStream stream = File.OpenRead(zipPath);
                if (stream.Length != parsed.Value.Size) return false;
                string hex = Convert.ToHexString(SHA256.HashData(stream))
                    .ToLowerInvariant();
                return string.Equals(hex, parsed.Value.Sha256, StringComparison.Ordinal);
            }
            catch
            {
                return false; // unreadable zip fails closed, never throws
            }
        }

        /// <summary>
        /// The accept continuation, always entered from the UI thread (the
        /// offer dialog marshals there). Every failure path logs a named
        /// event with the host's actor, leaves the application running and
        /// changes nothing on disk outside %TEMP%.
        /// </summary>
        public static async Task RunAsync(SelfUpdateOptions options, UpdateOffer offer)
        {
            string actor = options.Actor;
            try
            {
                string stagingRoot = Path.Combine(Path.GetTempPath(), "WsusOfflineNext-Update");
                Directory.CreateDirectory(stagingRoot);
                string stamp = Guid.NewGuid().ToString("N");
                string zipPath = Path.Combine(stagingRoot, "update-" + stamp + ".zip");
                string stageDir = Path.Combine(stagingRoot, "stage-" + stamp);
                Form? owner = options.OwnerFormProvider?.Invoke();

                // Modeless status form for the download duration only.
                string hashesText = "";
                using var status = new DownloadStatusForm();
                status.Show(owner);
                try
                {
                    SelfUpdateLog.Append(actor, "download-start");
                    hashesText = await HttpQuick.GetStringAsync(offer.HashesUrl)
                        .ConfigureAwait(true);
                    await DownloadZipAsync(offer.ZipUrl, zipPath).ConfigureAwait(true);
                    SelfUpdateLog.Append(actor, "download-complete");
                }
                finally
                {
                    status.Close();
                }

                // Fail-closed verification: nothing is extracted, the zip is
                // deleted and the app continues normally.
                if (!VerifyZipAgainstHashes(zipPath, hashesText))
                {
                    SelfUpdateLog.Append(actor, "hash-mismatch");
                    TryDelete(zipPath);
                    MessageBox.Show(owner,
                        "Verification of the downloaded update failed.\n" +
                        "Nothing was changed - the application continues normally.",
                        "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                SelfUpdateLog.Append(actor, "hash-verified");

                // Guarded extraction: enumerate every entry FIRST and refuse
                // the whole archive when any destination would resolve
                // outside the staging directory (zip-slip, T-28-05).
                if (!TryExtractGuarded(zipPath, stageDir))
                {
                    SelfUpdateLog.Append(actor, "extraction-rejected");
                    TryDelete(zipPath);
                    MessageBox.Show(owner,
                        "The downloaded update was rejected.\n" +
                        "Nothing was changed - the application continues normally.",
                        "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                // Staging completeness: the new tree must carry all three
                // application executables before anything is applied.
                string stagedRoot = Path.Combine(stageDir, "wsusoffline");
                if (!File.Exists(Path.Combine(stagedRoot, "UpdateGeneratorModern.exe"))
                    || !File.Exists(Path.Combine(stagedRoot, "client", "UpdateInstallerModern.exe"))
                    || !File.Exists(Path.Combine(stagedRoot, "WsusOfflineUpdater.exe")))
                {
                    SelfUpdateLog.Append(actor, "incomplete-staging-tree");
                    TryDelete(zipPath);
                    TryDeleteDirectory(stageDir);
                    MessageBox.Show(owner,
                        "The downloaded update is incomplete.\n" +
                        "Nothing was changed - the application continues normally.",
                        "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                SelfUpdateLog.Append(actor, "staged");
                TryDelete(zipPath); // the staged tree is now the source of truth

                // Healthy-marker path is MINTED here; the marker file itself
                // is only written by the relaunched app after its window
                // opens (Plan 03 wires that side).
                string markerPath = Path.Combine(SelfUpdatePaths.StateRoot,
                    "launch-" + Guid.NewGuid().ToString() + ".ok");

                string updaterPath = Path.Combine(options.InstallRoot, "WsusOfflineUpdater.exe");
                if (!File.Exists(updaterPath))
                {
                    SelfUpdateLog.Append(actor, "updater-missing");
                    MessageBox.Show(owner,
                        "The updater component is missing from this installation.\n" +
                        "Nothing was changed - the application continues normally.",
                        "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                string rootTrimmed = options.InstallRoot.TrimEnd(
                    Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
                string rootName = Path.GetFileName(rootTrimmed);
                string? rootParent = Path.GetDirectoryName(rootTrimmed);
                string backupDir = !string.IsNullOrEmpty(rootName) && !string.IsNullOrEmpty(rootParent)
                    ? Path.Combine(rootParent, rootName + ".bak-"
                        + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture))
                    : Path.Combine(stagingRoot, "backup-"
                        + DateTime.Now.ToString("yyyyMMdd-HHmmss", CultureInfo.InvariantCulture));

                var psi = new ProcessStartInfo(updaterPath)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                psi.ArgumentList.Add("--pid");
                psi.ArgumentList.Add(Environment.ProcessId.ToString(CultureInfo.InvariantCulture));
                psi.ArgumentList.Add("--staging");
                psi.ArgumentList.Add(stageDir);
                psi.ArgumentList.Add("--backup");
                psi.ArgumentList.Add(backupDir);
                psi.ArgumentList.Add("--relaunch");
                psi.ArgumentList.Add(string.IsNullOrEmpty(options.HostExePath)
                    ? Environment.ProcessPath ?? Application.ExecutablePath
                    : options.HostExePath);
                psi.ArgumentList.Add("--marker");
                psi.ArgumentList.Add(markerPath);
                using (Process.Start(psi))
                {
                }
                SelfUpdateLog.Append(actor, "updater-launched");

                DialogResult restart = MessageBox.Show(owner,
                    "Update downloaded and verified.\n" +
                    "It will be applied when this application closes.\n\nRestart now?",
                    "WSUS Offline Next", MessageBoxButtons.YesNo, MessageBoxIcon.Information);
                if (restart == DialogResult.Yes)
                {
                    // Closing the main form makes Application.Run return and
                    // the process exit - the waiting updater then proceeds.
                    owner?.Close();
                }
            }
            catch
            {
                // Same silent-failure discipline as the check slice: a named
                // error event, the app keeps running, nothing was applied.
                SelfUpdateLog.Append(actor, "install-error");
                Form? owner = options.OwnerFormProvider?.Invoke();
                MessageBox.Show(owner,
                    "The update could not be completed.\n" +
                    "Nothing was changed - the application continues normally.",
                    "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private static async Task DownloadZipAsync(string zipUrl, string zipPath)
        {
            using HttpResponseMessage response = await HttpDownload
                .GetAsync(zipUrl, HttpCompletionOption.ResponseHeadersRead)
                .ConfigureAwait(true);
            response.EnsureSuccessStatusCode();
            await using Stream source = await response.Content.ReadAsStreamAsync()
                .ConfigureAwait(true);
            await using FileStream target = File.Create(zipPath);
            await source.CopyToAsync(target).ConfigureAwait(true);
        }

        /// <summary>
        /// Extract the archive only when EVERY entry destination resolves
        /// inside the staging directory (Path.GetFullPath comparison,
        /// OrdinalIgnoreCase). The whole archive refuses, never single
        /// entries - a rejected archive extracts nothing.
        /// </summary>
        private static bool TryExtractGuarded(string zipPath, string stageDir)
        {
            try
            {
                string stageFull = Path.GetFullPath(stageDir);
                using ZipArchive archive = ZipFile.OpenRead(zipPath);
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    string destination = Path.GetFullPath(Path.Combine(stageDir, entry.FullName));
                    bool inside = destination.Equals(stageFull, StringComparison.OrdinalIgnoreCase)
                        || destination.StartsWith(
                            stageFull + Path.DirectorySeparatorChar,
                            StringComparison.OrdinalIgnoreCase);
                    if (!inside) return false;
                }
                Directory.CreateDirectory(stageDir);
                foreach (ZipArchiveEntry entry in archive.Entries)
                {
                    if (entry.FullName.EndsWith("/", StringComparison.Ordinal)) continue;
                    string destination = Path.Combine(stageDir, entry.FullName);
                    string? directory = Path.GetDirectoryName(destination);
                    if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
                    entry.ExtractToFile(destination, overwrite: true);
                }
                return true;
            }
            catch
            {
                return false; // unreadable archive extracts nothing
            }
        }

        private static void TryDelete(string path)
        {
            try { File.Delete(path); } catch { /* temp cleanup is best-effort */ }
        }

        private static void TryDeleteDirectory(string path)
        {
            try { Directory.Delete(path, recursive: true); } catch { /* best-effort */ }
        }

        /// <summary>Label-only modeless native status form, topmost over its owner.</summary>
        private sealed class DownloadStatusForm : Form
        {
            public DownloadStatusForm()
            {
                Text = "WSUS Offline Next";
                FormBorderStyle = FormBorderStyle.FixedToolWindow;
                StartPosition = FormStartPosition.CenterScreen;
                TopMost = true;
                ShowInTaskbar = false;
                AutoScaleMode = AutoScaleMode.Dpi;
                ClientSize = new Size(340, 80);
                Controls.Add(new Label
                {
                    Text = "Downloading update...",
                    Dock = DockStyle.Fill,
                    TextAlign = ContentAlignment.MiddleCenter
                });
            }
        }
    }
}
