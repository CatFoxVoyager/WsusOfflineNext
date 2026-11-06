using System;
using System.Net.Http;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace WsusOfflineNext.SelfUpdate
{
    /// <summary>Per-process options for the launch-time update check.</summary>
    public sealed class SelfUpdateOptions
    {
        /// <summary>Metadata-stripped local version (e.g. "6.0.2").</summary>
        public string LocalVersion { get; init; } = "unknown";

        /// <summary>
        /// Installation root: the directory containing the "client" folder
        /// (the generator runs from the root, the installer from client\).
        /// </summary>
        public string InstallRoot { get; init; } = "";

        /// <summary>Log actor: "generator", "installer" or "updater".</summary>
        public string Actor { get; init; } = "generator";

        /// <summary>
        /// Full path of the host's own executable - the updater's
        /// --relaunch target after the swap.
        /// </summary>
        public string HostExePath { get; init; } = "";

        /// <summary>
        /// Strict-newer decision, injected by each host - the ONLY version
        /// comparison in the engine is this delegate, bound to the host's
        /// existing WebView2Compat comparator in both directions:
        /// IsVersionAtLeast(channel, local) &amp;&amp; !IsVersionAtLeast(local, channel).
        /// </summary>
        public Func<string?, string, bool>? IsChannelNewer { get; init; }

        /// <summary>Returns the main window once it exists (owner of the offer dialog).</summary>
        public Func<Form?>? OwnerFormProvider { get; init; }

        /// <summary>OfferGuard latch: never more than one offer per process.</summary>
        internal bool OfferShown;
    }

    /// <summary>
    /// Async launch-time update check, shared by both .NET hosts. Started in
    /// Main before Application.Run, fire-and-forget: it never delays app
    /// launch, and every failure path is silent (offline, DNS-dead or an
    /// unreadable channel leaves the app running exactly as before).
    /// </summary>
    public static class SelfUpdateCheck
    {
        // Production channel, published by every release train (https only).
        public const string DefaultChannelUrl =
            "https://raw.githubusercontent.com/CatFoxVoyager/WsusOfflineNext/main/static/SelfUpdateVersion-recent.txt";
        public const string DefaultLinksUrl =
            "https://raw.githubusercontent.com/CatFoxVoyager/WsusOfflineNext/main/ci/StaticDownloadLink-recent.txt";

        // Test hooks (also the Phase 30 live-channel harness): environment
        // overrides for the ci battery. WSON_UPDATE_CHANNEL_URL and
        // WSON_UPDATE_LINKS_URL redirect the two fetches;
        // WSON_UPDATE_LOCAL_VERSION overrides the local version;
        // WSON_UPDATE_AUTO_DECLINE=1 records update-declined in the log
        // without showing any dialog; WSON_UPDATE_AUTO_ACCEPT=1 accepts the
        // offer and runs the install pipeline without any dialog (the
        // closing restart-now dialog auto-answers Yes so the app closes
        // itself and the waiting updater proceeds - a headless harness
        // cannot click MessageBox buttons).
        private static string? Env(string name) => Environment.GetEnvironmentVariable(name);

        private static readonly HttpClient Http = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(10)
        };

        public static async Task RunAsync(SelfUpdateOptions options)
        {
            try
            {
                // Order: kill-switch outranks everything (a disabled machine
                // must not even touch the cache file), then the daily cache,
                // and only then the network.
                string iniPath = System.IO.Path.Combine(
                    options.InstallRoot, "client", "UpdateInstaller.ini");
                if (SelfUpdateIni.IsSelfUpdateDisabled(iniPath))
                {
                    SelfUpdateLog.Append(options.Actor, "check-skip-disabled");
                    return;
                }
                if (SelfUpdateCache.IsCheckedToday(SelfUpdatePaths.LastCheckFilePath))
                {
                    SelfUpdateLog.Append(options.Actor, "check-skip-cache");
                    return;
                }
                SelfUpdateLog.Append(options.Actor, "check-start");

                string channelUrl = Env("WSON_UPDATE_CHANNEL_URL") ?? DefaultChannelUrl;
                string linksUrl = Env("WSON_UPDATE_LINKS_URL") ?? DefaultLinksUrl;
                string localVersion = Env("WSON_UPDATE_LOCAL_VERSION");
                if (string.IsNullOrWhiteSpace(localVersion)) localVersion = options.LocalVersion;

                string channelText = await Http.GetStringAsync(channelUrl).ConfigureAwait(false);
                string? channelVersion = SelfUpdateChannel.ParseChannelVersion(channelText);
                if (channelVersion == null)
                {
                    SelfUpdateLog.Append(options.Actor, "check-error");
                    return;
                }

                // The offer must carry real URLs, so the links file is
                // fetched and validated before any offer decision.
                string linksText = await Http.GetStringAsync(linksUrl).ConfigureAwait(false);
                var parsedLinks = SelfUpdateChannel.ParseLinksFile(linksText);
                if (parsedLinks == null)
                {
                    SelfUpdateLog.Append(options.Actor, "check-error");
                    return;
                }
                (string ZipUrl, string HashesUrl) links = parsedLinks.Value;

                // Cache write happens ONLY on a completed channel read+parse:
                // a failed or corrupt run must retry the network on the next
                // launch the same day (even when the version is not newer).
                SelfUpdateCache.WriteCheckedToday(SelfUpdatePaths.LastCheckFilePath);

                bool isNewer = options.IsChannelNewer != null
                               && options.IsChannelNewer(channelVersion, localVersion);
                if (!isNewer) return; // not newer: silent stop, no log spam

                SelfUpdateLog.Append(options.Actor, "update-offered");

                if (string.Equals(Env("WSON_UPDATE_AUTO_DECLINE"), "1", StringComparison.Ordinal))
                {
                    SelfUpdateLog.Append(options.Actor, "update-declined");
                    return;
                }

                await ShowOfferWhenUiReadyAsync(options, channelVersion, localVersion, links)
                    .ConfigureAwait(false);
            }
            catch
            {
                // Silent-failure discipline: any network or parse error logs
                // check-error and leaves the launch path untouched.
                SelfUpdateLog.Append(options.Actor, "check-error");
            }
        }

        /// <summary>
        /// The offer can only appear over the already-open main window: wait
        /// for the owner form to exist, then marshal the dialog to the UI
        /// thread via BeginInvoke - or, when the handle does not exist yet,
        /// flush the pending offer on the form's Shown event.
        /// </summary>
        private static async Task ShowOfferWhenUiReadyAsync(
            SelfUpdateOptions options, string channelVersion, string localVersion,
            (string ZipUrl, string HashesUrl) links)
        {
            Form? form = null;
            for (int attempt = 0; attempt < 60; attempt++)
            {
                form = options.OwnerFormProvider?.Invoke();
                if (form != null) break;
                await Task.Delay(500).ConfigureAwait(false);
            }
            if (form == null || form.IsDisposed) return;

            if (form.IsHandleCreated)
            {
                BeginInvokeShow(form, options, channelVersion, localVersion, links);
                return;
            }

            // Form not shown yet: hold the pending offer until Shown fires.
            EventHandler? shown = null;
            shown = (sender, e) =>
            {
                form.Shown -= shown!;
                ShowOfferDialog(options, channelVersion, localVersion, links);
            };
            form.Shown += shown;
            // Race guard: if the form was shown between the handle check and
            // the hook, flush directly instead of waiting for a dead event.
            if (form.IsHandleCreated)
            {
                form.Shown -= shown;
                BeginInvokeShow(form, options, channelVersion, localVersion, links);
            }
        }

        private static void BeginInvokeShow(
            Form form, SelfUpdateOptions options, string channelVersion, string localVersion,
            (string ZipUrl, string HashesUrl) links)
        {
            try
            {
                form.BeginInvoke((Action)(() =>
                    ShowOfferDialog(options, channelVersion, localVersion, links)));
            }
            catch (InvalidOperationException)
            {
                // The form's handle died between the check and the marshal:
                // dropping the offer is the safe outcome.
            }
        }

        private static void ShowOfferDialog(
            SelfUpdateOptions options, string channelVersion, string localVersion,
            (string ZipUrl, string HashesUrl) links)
        {
            if (options.OfferShown) return; // OfferGuard: one offer per process
            options.OfferShown = true;
            try
            {
                Form? owner = options.OwnerFormProvider?.Invoke();
                // Test / Phase 30 harness hook, symmetric to
                // WSON_UPDATE_AUTO_DECLINE: accept without showing the
                // offer dialog.
                if (string.Equals(Env("WSON_UPDATE_AUTO_ACCEPT"),
                        "1", StringComparison.Ordinal))
                {
                    SelfUpdateLog.Append(options.Actor, "update-accepted");
                    _ = UpdateInstall.RunAsync(options, new UpdateOffer(
                        channelVersion, links.ZipUrl, links.HashesUrl));
                    return;
                }
                string text =
                    $"Version {channelVersion} is available on the update channel.\n" +
                    $"Installed version: {localVersion}\n\n" +
                    "Download and install the update now?";
                DialogResult result = MessageBox.Show(owner, text, "WSUS Offline Next",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Question);
                if (result == DialogResult.Yes)
                {
                    SelfUpdateLog.Append(options.Actor, "update-accepted");
                    // The accept continuation runs on this UI thread and owns
                    // download, verification, staging and the updater launch.
                    _ = UpdateInstall.RunAsync(options, new UpdateOffer(
                        channelVersion, links.ZipUrl, links.HashesUrl));
                }
                else
                {
                    SelfUpdateLog.Append(options.Actor, "update-declined");
                }
            }
            catch
            {
                // The offer must never crash the app.
            }
        }
    }
}
