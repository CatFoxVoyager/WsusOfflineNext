using System;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using WsusOfflineNext.SelfUpdate;

// Console harness driving the shared self-update engine for
// ci/tests/test-selfupdate-check.sh and test-selfupdate-updater.sh. Each
// subcommand prints exactly one verdict line so the battery can assert on
// it:
//   decide <channel-file> <links-file> <local-version>  -> OFFER <v> | NO-OFFER
//   cache <today|yesterday|garbage|empty> <temp-path>   -> CHECK-TODAY | CHECK-NEEDED
//   ini <ini-file>                                      -> DISABLED | ENABLED
//   hashes <hashes-file>                                -> SHA256 <hex> SIZE <n> | REJECT
//   sha256 <file>                                       -> <hex> (the file's digest)
// Fixture CONTENT reaches the engine through files (never argv) so CRLF
// bytes arrive intact.
internal static class Program
{
    private static int Main(string[] args)
    {
        try
        {
            if (args.Length >= 1 && args[0] == "decide" && args.Length == 4)
            {
                Console.WriteLine(Decide(args[1], args[2], args[3]));
                return 0;
            }
            if (args.Length >= 1 && args[0] == "cache" && args.Length == 3)
            {
                Console.WriteLine(Cache(args[1], args[2]));
                return 0;
            }
            if (args.Length >= 1 && args[0] == "ini" && args.Length == 2)
            {
                Console.WriteLine(SelfUpdateIni.IsSelfUpdateDisabled(args[1]) ? "DISABLED" : "ENABLED");
                return 0;
            }
            if (args.Length >= 1 && args[0] == "hashes" && args.Length == 2)
            {
                Console.WriteLine(Hashes(args[1]));
                return 0;
            }
            if (args.Length >= 1 && args[0] == "sha256" && args.Length == 2)
            {
                Console.WriteLine(FileDigest(args[1]));
                return 0;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("PROBE-ERROR " + ex.Message);
            return 1;
        }
        Console.WriteLine("PROBE-ERROR usage: decide <channel> <links> <local> | cache <kind> <path> | ini <path> | hashes <path> | sha256 <path>");
        return 1;
    }

    private static string Hashes(string path)
    {
        (long Size, string Sha256)? parsed =
            UpdateInstall.ParseHashesFile(File.ReadAllText(path));
        return parsed == null
            ? "REJECT"
            : "SHA256 " + parsed.Value.Sha256 + " SIZE " + parsed.Value.Size;
    }

    private static string FileDigest(string path)
    {
        using FileStream stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
    }

    private static string Decide(string channelPath, string linksPath, string localVersion)
    {
        string? channel = SelfUpdateChannel.ParseChannelVersion(File.ReadAllText(channelPath));
        if (channel == null) return "NO-OFFER";
        if (SelfUpdateChannel.ParseLinksFile(File.ReadAllText(linksPath)) == null) return "NO-OFFER";
        // The exact two-call strict-newer expression the hosts inject, over
        // a minimal mirror of the WebView2Compat strip/numeric semantics
        // (the hosts' class is unreachable from this project; the battery's
        // decision table cross-checks the mirror against the documented
        // comparator behavior - equal-with-metadata must read NO-OFFER).
        bool newer = IsVersionAtLeastMirror(channel, localVersion)
                     && !IsVersionAtLeastMirror(localVersion, channel);
        return newer ? "OFFER " + channel : "NO-OFFER";
    }

    private static string Cache(string kind, string tempPath)
    {
        string content;
        switch (kind)
        {
            case "today":
                content = DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                break;
            case "yesterday":
                content = DateTime.Today.AddDays(-1).ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
                break;
            case "garbage":
                content = "not-a-date";
                break;
            case "empty":
                content = "";
                break;
            default:
                throw new ArgumentException("unknown cache kind: " + kind);
        }
        File.WriteAllText(tempPath, content);
        return SelfUpdateCache.IsCheckedToday(tempPath) ? "CHECK-TODAY" : "CHECK-NEEDED";
    }

    // Minimal mirror of WebView2Compat.IsVersionAtLeast (both hosts):
    // strip any '+'/'-' suffix, then numeric compare over dot-separated
    // parts with missing/non-numeric parts counting as 0.
    private static bool IsVersionAtLeastMirror(string? version, string minimum)
    {
        if (string.IsNullOrEmpty(version) || string.IsNullOrEmpty(minimum)) return false;
        string[] v = StripSuffix(version).Split('.');
        string[] m = StripSuffix(minimum).Split('.');
        int count = Math.Max(v.Length, m.Length);
        for (int i = 0; i < count; i++)
        {
            int vv = i < v.Length && int.TryParse(v[i], out int x) ? x : 0;
            int mm = i < m.Length && int.TryParse(m[i], out int y) ? y : 0;
            if (vv != mm) return vv > mm;
        }
        return true;
    }

    private static string StripSuffix(string version)
    {
        int cut = version.IndexOfAny(new[] { '+', '-' });
        return cut >= 0 ? version.Substring(0, cut) : version;
    }
}
