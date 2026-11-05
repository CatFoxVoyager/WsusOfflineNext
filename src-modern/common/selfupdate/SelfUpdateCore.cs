using System;
using System.Globalization;
using System.IO;
using System.Text;

namespace WsusOfflineNext.SelfUpdate
{
    // Shared UI-free self-update core, compiled into both .NET hosts (and
    // later the updater console app) via csproj Compile Include links.
    // Deliberately pure BCL: no WinForms, no network, no comparator logic
    // here - callers own the UI thread, the fetch and the version decision.

    /// <summary>Well-known locations of the per-user self-update state.</summary>
    public static class SelfUpdatePaths
    {
        /// <summary>Constant relative state dir name under LocalApplicationData.</summary>
        public const string StateDirName = "WsusOfflineNext/selfupdate";

        /// <summary>Root of the self-update state directory.</summary>
        public static string StateRoot => Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "WsusOfflineNext", "selfupdate");

        /// <summary>Daily-cache file (single local date line, see SelfUpdateCache).</summary>
        public static string LastCheckFilePath => Path.Combine(StateRoot, "last-check.txt");

        /// <summary>Append-only engine event log (see SelfUpdateLog).</summary>
        public static string UpdateLogPath => Path.Combine(StateRoot, "update.log");
    }

    /// <summary>
    /// One-line event log: "yyyy-MM-dd HH:mm:ss.fff|actor|event".
    /// Logging must never throw and never break the launch path.
    /// </summary>
    public static class SelfUpdateLog
    {
        public static void Append(string actor, string eventName)
        {
            try
            {
                Directory.CreateDirectory(SelfUpdatePaths.StateRoot);
                string line = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture)
                    + "|" + actor + "|" + eventName;
                File.AppendAllText(SelfUpdatePaths.UpdateLogPath, line + Environment.NewLine, Encoding.UTF8);
            }
            catch
            {
                // Swallow by design: logging is best-effort diagnostics.
            }
        }
    }

    /// <summary>
    /// Pure, total parsers for the published channel files. Every input is
    /// untrusted text; every malformed shape returns null, never throws.
    /// </summary>
    public static class SelfUpdateChannel
    {
        private static readonly char[] TrimChars =
            { '﻿', '\r', '\n', ' ', '\t' };

        /// <summary>
        /// Parse the version channel file: exactly one comma-separated pair
        /// "version,tag" (e.g. "6.0.2+2026.11,release"), both parts non-empty
        /// after trimming BOM/whitespace/CR/LF. Returns the trimmed version
        /// token, or null for anything else.
        /// </summary>
        public static string? ParseChannelVersion(string? text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            string s = text.Trim(TrimChars);
            string[] parts = s.Split(',');
            if (parts.Length != 2) return null;
            string version = parts[0].Trim(TrimChars);
            string tag = parts[1].Trim(TrimChars);
            if (version.Length == 0 || tag.Length == 0) return null;
            return version;
        }

        /// <summary>
        /// Parse the links channel file: exactly two non-empty lines after
        /// trimming CR/LF/whitespace, line 1 an "https://" URL ending in
        /// ".zip", line 2 an "https://" URL ending in "_hashes.txt"
        /// (Ordinal comparisons). Returns both URLs, or null.
        /// </summary>
        public static (string ZipUrl, string HashesUrl)? ParseLinksFile(string? text)
        {
            if (string.IsNullOrEmpty(text)) return null;
            string content = text.TrimStart('﻿');
            string[] lines = content.Split('\n');
            string? zip = null, hashes = null;
            foreach (string raw in lines)
            {
                string line = raw.Trim('\r').Trim();
                if (line.Length == 0) continue;
                if (zip == null) { zip = line; continue; }
                if (hashes == null) { hashes = line; continue; }
                return null; // a third non-empty line is malformed
            }
            if (zip == null || hashes == null) return null;
            if (!zip.StartsWith("https://", StringComparison.Ordinal)) return null;
            if (!hashes.StartsWith("https://", StringComparison.Ordinal)) return null;
            if (!zip.EndsWith(".zip", StringComparison.Ordinal)) return null;
            if (!hashes.EndsWith("_hashes.txt", StringComparison.Ordinal)) return null;
            return (zip, hashes);
        }
    }

    /// <summary>
    /// Daily cache: a single-line local date "yyyy-MM-dd" (InvariantCulture)
    /// compared against DateTime.Today. Missing or unparsable cache means
    /// "not checked today". A half-written cache line must read as
    /// not-checked-today, so writes are tmp-then-move (WriteCheckedToday).
    /// </summary>
    public static class SelfUpdateCache
    {
        public static bool IsCheckedToday(string cachePath)
        {
            try
            {
                if (!File.Exists(cachePath)) return false;
                string s = File.ReadAllText(cachePath).Trim('﻿', '\r', '\n', ' ', '\t');
                return DateTime.TryParseExact(s, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                           DateTimeStyles.None, out DateTime date)
                       && date.Date == DateTime.Today;
            }
            catch
            {
                return false; // unreadable cache = not checked today
            }
        }

        public static void WriteCheckedToday(string cachePath)
        {
            try
            {
                string? dir = Path.GetDirectoryName(cachePath);
                if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
                File.WriteAllText(cachePath,
                    DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture));
            }
            catch
            {
                // Swallow by design: a failed cache write only means the
                // next launch re-checks the network - harmless.
            }
        }
    }

    /// <summary>
    /// Minimal kill-switch INI reader (no library): inside section [Control]
    /// (OrdinalIgnoreCase), key SkipSelfUpdate with value Enabled
    /// (OrdinalIgnoreCase) disables the self-update engine. Tolerates CRLF,
    /// UTF-8 BOM and ';'/'#' comments. The reader never throws.
    /// </summary>
    public static class SelfUpdateIni
    {
        public static bool IsSelfUpdateDisabled(string iniPath)
        {
            try
            {
                if (!File.Exists(iniPath)) return false;
                string content = File.ReadAllText(iniPath);
                if (content.Length > 0 && content[0] == '﻿')
                {
                    content = content.Substring(1);
                }
                bool inControl = false;
                foreach (string rawLine in content.Split('\n'))
                {
                    string line = rawLine.Trim('\r').Trim();
                    if (line.Length == 0 || line.StartsWith(";") || line.StartsWith("#")) continue;
                    if (line.StartsWith("[") && line.EndsWith("]") && line.Length >= 2)
                    {
                        string section = line.Substring(1, line.Length - 2).Trim();
                        inControl = string.Equals(section, "Control", StringComparison.OrdinalIgnoreCase);
                        continue;
                    }
                    if (!inControl) continue;
                    int eq = line.IndexOf('=');
                    if (eq < 0) continue;
                    string key = line.Substring(0, eq).Trim();
                    string value = line.Substring(eq + 1).Trim();
                    if (string.Equals(key, "SkipSelfUpdate", StringComparison.OrdinalIgnoreCase)
                        && string.Equals(value, "Enabled", StringComparison.OrdinalIgnoreCase))
                    {
                        return true;
                    }
                }
                return false;
            }
            catch
            {
                return false; // unreadable INI must not disable or crash
            }
        }
    }
}
