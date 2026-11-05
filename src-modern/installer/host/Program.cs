using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using WsusOfflineNext.SelfUpdate;

namespace WSUSOffline.Installer
{
    public class MainWindow : Form
    {
        private WebView2? _webView;
        private Process? _activeProcess;
        private CancellationTokenSource? _cts;

        // Static instance for the self-update check's owner-form provider:
        // set first in the ctor so the offer dialog can find the window as
        // soon as it exists (the check starts before Application.Run).
        public static MainWindow? Instance { get; private set; }

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        private static string GetDisplayVersion()
        {
            var info = typeof(MainWindow).Assembly
                .GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion;
            if (string.IsNullOrEmpty(info))
            {
                info = typeof(MainWindow).Assembly
                    .GetCustomAttribute<AssemblyFileVersionAttribute>()?.Version;
            }
            if (string.IsNullOrEmpty(info)) return "unknown";
            int plus = info.IndexOf('+');
            return plus >= 0 ? info.Substring(0, plus) : info;
        }

        public MainWindow()
        {
            Instance = this;
            this.Text = $"WSUS Offline Next {GetDisplayVersion()} - Client Installer";
            this.Width = 1040;
            this.Height = 720;
            this.MinimumSize = new System.Drawing.Size(850, 600);
            this.StartPosition = FormStartPosition.CenterScreen;
            this.BackColor = System.Drawing.Color.FromArgb(9, 9, 11);

            // Windows 11 Immersive Dark Titlebar
            try
            {
                int darkMode = 1;
                DwmSetWindowAttribute(this.Handle, DWMWA_USE_IMMERSIVE_DARK_MODE, ref darkMode, sizeof(int));
            }
            catch { }

            // wson.ico is embedded in the exe via the ApplicationIcon csproj
            // setting; mirror the same icon into the window title bar and
            // the taskbar at runtime (no design-time .Icon assignment exists).
            try
            {
                this.Icon = System.Drawing.Icon.ExtractAssociatedIcon(Application.ExecutablePath);
            }
            catch { }

            InitializeWebView();
        }

        private static bool IsWebView2RuntimeMissing(Exception ex)
        {
            return ex is WebView2RuntimeNotFoundException
                || ex.Message.Contains("Unable to find", StringComparison.OrdinalIgnoreCase);
        }

        // Classify broadly, never narrowly: any member of the
        // E_NOINTERFACE / 0x80004002 family (the exact failure the SDK
        // bump in 261102-aci targeted, and the dead-RCW getter crash of
        // issue #21) must read as "runtime too old", not as an opaque
        // crash. Shared by the init catch and the global exception net.
        private static bool IsWebView2FailureFamily(Exception ex)
        {
            return IsWebView2RuntimeMissing(ex)
                || ex is InvalidCastException
                || ex.Message.Contains("not compatible", StringComparison.OrdinalIgnoreCase)
                || ex.Message.Contains("too old", StringComparison.OrdinalIgnoreCase)
                || ex.Message.Contains("E_NOINTERFACE", StringComparison.OrdinalIgnoreCase)
                || ex.Message.Contains("0x80004002", StringComparison.OrdinalIgnoreCase);
        }

        private static string DescribeWebView2Failure(Exception ex)
        {
            string rootCause;
            if (IsWebView2RuntimeMissing(ex))
            {
                rootCause = "The Microsoft Edge WebView2 Runtime was not found on this computer.";
            }
            else if (IsWebView2FailureFamily(ex))
            {
                rootCause = "The installed Microsoft Edge WebView2 Runtime is too old for this application.";
            }
            else
            {
                rootCause = "The modern interface failed to start.\n" + ex.Message;
            }
            return rootCause
                + "\n\nInstall or update the Microsoft Edge WebView2 Runtime (Evergreen)."
                + "\nOffline machines: run the installer shipped in this package:"
                + "\nedge\\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
                + "\n\nYou can also use the classic interface.";
        }

        // --- Round-3 WebView2 defenses (issue #21): startup gate before any
        // WebView2 call, global exception net so the JIT/Watson dialog can
        // never appear, and a fail-safe Legacy hand-off shared by both. ---

        // Startup gate: an absent or too-old runtime is diagnosed here,
        // before anything can crash mid-flight.
        private static void EnsureWebView2RuntimeOrFallback()
        {
            string? detected = null;
            try
            {
                detected = CoreWebView2Environment.GetAvailableBrowserVersionString();
            }
            catch { }

            bool gatePassed = !string.IsNullOrEmpty(detected)
                && WebView2Compat.IsVersionAtLeast(detected, WebView2Compat.MinWebView2Version);

            // Unconditional diagnostics, before any branch or exit path.
            WriteStartupDiagnostics(detected, gatePassed);
            if (gatePassed)
            {
                return;
            }

            string message =
                "Le composant Microsoft Edge WebView2 est absent ou trop ancien.\n"
                + "Version détectée : " + (string.IsNullOrEmpty(detected) ? "absente" : detected) + "\n"
                + "Requis : " + WebView2Compat.MinWebView2Version + " ou plus récent.\n\n"
                + "Journal de diagnostic : " + GetStartupDiagnosticsLogPath() + "\n\n"
                + "Installez le WebView2 Evergreen Runtime :\n"
                + EvergreenUrl + "\n\n"
                + "Ouvrir l'interface classique (Legacy) à la place ?";
            if (MessageBox.Show(message, "WSUS Offline Next Installer",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
            {
                StartLegacyInterfaceOrExplain();
                Environment.Exit(0);
            }
            Environment.Exit(1);
        }

        // Single sink of the global exception net. A second fatal while the
        // dialog is up exits immediately; the dialog owner performs the
        // Legacy hand-off before the exit so the AppDomain event's
        // cannot-continue semantics stay best-effort but never silent.
        private static int _fatalInProgress;

        internal static void HandleFatal(Exception ex)
        {
            if (Interlocked.Exchange(ref _fatalInProgress, 1) != 0)
            {
                Environment.Exit(1);
            }
            try
            {
                if (IsWebView2FailureFamily(ex))
                {
                    if (MessageBox.Show(
                            DescribeWebView2Failure(ex) + "\n\nDiagnostic log: " + GetStartupDiagnosticsLogPath() + "\n\nOuvrir l'interface classique (Legacy) ?",
                            "WSUS Offline Next Installer",
                            MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
                    {
                        StartLegacyInterfaceOrExplain();
                    }
                }
                else
                {
                    MessageBox.Show(
                        "Une erreur inattendue a interrompu l'application.\n" + ex.Message + "\n\nJournal de diagnostic : " + GetStartupDiagnosticsLogPath(),
                        "WSUS Offline Next Installer", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            }
            catch { }
            LogFatal(ex);
            Environment.Exit(1);
        }

        private static void InstallGlobalExceptionNet()
        {
            // CatchException routes UI-thread exceptions to ThreadException
            // instead of the JIT dialog; the AppDomain event covers worker
            // threads (the process cannot continue after it, hence the
            // dialog-then-exit order in HandleFatal).
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
            Application.ThreadException += (s, e) => HandleFatal(e.Exception);
            AppDomain.CurrentDomain.UnhandledException += (s, e) =>
                HandleFatal(e.ExceptionObject as Exception
                    ?? new Exception(e.ExceptionObject?.ToString() ?? "unknown"));
        }

        private static string? ResolveLegacyExe()
        {
            // Probe order matches the init catch above: the .orig.exe name
            // kept for local setups first, then the name actually shipped
            // by the native lazbuild lane (CompileModernApps.cmd step 3)
            // in every release tree.
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            foreach (string name in new[] { "UpdateInstaller.orig.exe", "UpdateInstallerLegacy.exe" })
            {
                string candidate = Path.Combine(baseDir, name);
                if (File.Exists(candidate)) return candidate;
            }
            return null;
        }

        // Compile-time constant: the official Microsoft Evergreen page.
        // NEVER derived from user input (argv, INI, registry content) —
        // the dialog is the first surface a stranded user reads and its
        // URL must not be spoofable.
        private const string EvergreenUrl =
            "https://developer.microsoft.com/microsoft-edge/webview2/";

        // Evergreen-offer dialog for the paths where the classic interface
        // cannot be started: explains that the WebView2 Runtime requirement
        // (version MinWebView2Version or newer) was not met and offers the
        // Evergreen runtime — the bundled offline bootstrapper when it
        // ships in the tree, the official Microsoft page otherwise. Does
        // not change the caller's exit flow.
        private static void ShowWebView2EvergreenOffer(string? failureDetail)
        {
            string bootstrapperPath = Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory, "edge",
                "MicrosoftEdgeWebView2RuntimeInstallerX64.exe");
            bool bootstrapperPresent = File.Exists(bootstrapperPath);
            string message =
                "The classic AutoIt installer interface is not available in this"
                + " deployment, and the Microsoft Edge WebView2 Runtime requirement"
                + " (version " + WebView2Compat.MinWebView2Version
                + " or newer) was not met.\n";
            if (!string.IsNullOrEmpty(failureDetail))
            {
                message += failureDetail + "\n";
            }
            message += "\nInstall the Evergreen WebView2 Runtime:\n" + EvergreenUrl + "\n";
            if (bootstrapperPresent)
            {
                message += "\nAn offline installer is bundled with this package:\n"
                    + bootstrapperPath + "\n";
            }
            message += "\nInstall it now?";
            if (MessageBox.Show(message, "WSUS Offline Next Installer",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
            {
                try
                {
                    if (bootstrapperPresent)
                    {
                        Process.Start(new ProcessStartInfo(bootstrapperPath) { UseShellExecute = true });
                    }
                    else
                    {
                        Process.Start(new ProcessStartInfo(EvergreenUrl) { UseShellExecute = true });
                    }
                }
                catch { }
            }
        }

        // Hand off to the sibling legacy exe; when neither probe finds one
        // (bare dev build, trimmed deployment), degrade to the Evergreen
        // offer dialog — never a crash, never a dead-end message.
        private static void StartLegacyInterfaceOrExplain()
        {
            string? legacyPath = ResolveLegacyExe();
            try
            {
                if (legacyPath != null)
                {
                    Process.Start(new ProcessStartInfo(legacyPath) { UseShellExecute = true });
                    return;
                }
            }
            catch { }
            ShowWebView2EvergreenOffer(null);
        }

        private static void LogFatal(Exception ex)
        {
            try
            {
                string logDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "WSUSOfflineNext", "Installer");
                Directory.CreateDirectory(logDir);
                File.AppendAllText(
                    Path.Combine(logDir, "host-crash.log"),
                    "[" + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "] " + ex + "\r\n\r\n");
            }
            catch { }
        }

        // Path of the unconditional startup diagnostics log — same folder
        // family as LogFatal's host-crash.log so both artifacts are found
        // together and attached to a report.
        private static string GetStartupDiagnosticsLogPath()
        {
            return Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "WSUSOfflineNext", "Installer", "startup-diagnostics.log");
        }

        // Written on EVERY startup (gate pass or fail), not only on crash:
        // issue #21 reproduces only on the reporter's machine, so each
        // environment fact below is captured independently — one failing
        // capture never drops the other lines nor the write itself.
        private static void WriteStartupDiagnostics(string? detectedVersion, bool gatePassed)
        {
            List<string> lines = new List<string>
            {
                "=== Startup diagnostics " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " ==="
            };

            string appVersionLabel = "App version: ";
            try { lines.Add(appVersionLabel + GetDisplayVersion()); }
            catch (Exception ex) { lines.Add(appVersionLabel + "<error: " + ex.Message + ">"); }

            string detectedVersionLabel = "WebView2 detected version: ";
            try { lines.Add(detectedVersionLabel + (string.IsNullOrEmpty(detectedVersion) ? "<none>" : detectedVersion)); }
            catch (Exception ex) { lines.Add(detectedVersionLabel + "<error: " + ex.Message + ">"); }

            string minVersionLabel = "WebView2 minimum required: ";
            try { lines.Add(minVersionLabel + WebView2Compat.MinWebView2Version); }
            catch (Exception ex) { lines.Add(minVersionLabel + "<error: " + ex.Message + ">"); }

            string gateResultLabel = "WebView2 gate result: ";
            try { lines.Add(gateResultLabel + (gatePassed ? "PASS" : "FAIL")); }
            catch (Exception ex) { lines.Add(gateResultLabel + "<error: " + ex.Message + ">"); }

            string processArchLabel = "Process architecture: ";
            try { lines.Add(processArchLabel + RuntimeInformation.ProcessArchitecture); }
            catch (Exception ex) { lines.Add(processArchLabel + "<error: " + ex.Message + ">"); }

            string osVersionLabel = "OS version: ";
            try { lines.Add(osVersionLabel + RuntimeInformation.OSDescription); }
            catch (Exception ex) { lines.Add(osVersionLabel + "<error: " + ex.Message + ">"); }

            string? loaderPath = null;
            string? loaderVersion = null;
            try
            {
                // GetAvailableBrowserVersionString() has already run by the
                // time this fires, so the module list shows the loader the
                // process ACTUALLY resolved, not the one merely hoped for.
                foreach (ProcessModule module in Process.GetCurrentProcess().Modules)
                {
                    try
                    {
                        if (string.Equals(
                                Path.GetFileName(module.FileName), "WebView2Loader.dll",
                                StringComparison.OrdinalIgnoreCase))
                        {
                            loaderPath = module.FileName;
                            try
                            {
                                loaderVersion = module.FileVersionInfo.FileVersion;
                            }
                            catch { }
                            break;
                        }
                    }
                    catch { }
                }
            }
            catch { }

            string loaderPathLabel = "WebView2Loader.dll path: ";
            try { lines.Add(loaderPathLabel + (loaderPath ?? "<not loaded>")); }
            catch (Exception ex) { lines.Add(loaderPathLabel + "<error: " + ex.Message + ">"); }

            string loaderVersionLabel = "WebView2Loader.dll file version: ";
            try { lines.Add(loaderVersionLabel + (loaderVersion ?? "<unknown>")); }
            catch (Exception ex) { lines.Add(loaderVersionLabel + "<error: " + ex.Message + ">"); }

            string userDataLabel = "WebView2 user-data folder: ";
            try
            {
                lines.Add(userDataLabel + Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "WSUSOfflineNext", "Installer"));
            }
            catch (Exception ex) { lines.Add(userDataLabel + "<error: " + ex.Message + ">"); }

            string envVarsLabel = "WEBVIEW2_* environment variables: ";
            try
            {
                List<string> vars = new List<string>();
                foreach (System.Collections.DictionaryEntry entry in Environment.GetEnvironmentVariables())
                {
                    if (entry.Key is string key
                        && key.StartsWith("WEBVIEW2_", StringComparison.OrdinalIgnoreCase))
                    {
                        vars.Add(key + "=" + entry.Value);
                    }
                }
                lines.Add(envVarsLabel + (vars.Count > 0 ? string.Join(", ", vars) : "<none>"));
            }
            catch (Exception ex) { lines.Add(envVarsLabel + "<error: " + ex.Message + ">"); }

            try
            {
                string logPath = GetStartupDiagnosticsLogPath();
                Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
                lines.Add("");
                File.AppendAllLines(logPath, lines);
            }
            catch { }
        }

        private async void InitializeWebView()
        {
            _webView = new WebView2 { Dock = DockStyle.Fill };
            this.Controls.Add(_webView);

            try
            {
                string userDataFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WSUSOfflineNext", "Installer");
                Directory.CreateDirectory(userDataFolder);
                var env = await CoreWebView2Environment.CreateAsync(null, userDataFolder);
                await _webView.EnsureCoreWebView2Async(env);

                _webView.CoreWebView2.Settings.AreDefaultContextMenusEnabled = true;
                _webView.CoreWebView2.Settings.IsZoomControlEnabled = false;
                _webView.CoreWebView2.Settings.AreDevToolsEnabled = true;

                // Resolve frontend directory
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string wwwrootDir = Path.Combine(baseDir, "wwwroot");

                if (!Directory.Exists(wwwrootDir) || !File.Exists(Path.Combine(wwwrootDir, "index.html")))
                {
                    string devDir = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "src-modern", "installer", "dist"));
                    if (Directory.Exists(devDir) && File.Exists(Path.Combine(devDir, "index.html")))
                    {
                        wwwrootDir = devDir;
                    }
                    else
                    {
                        // Extract embedded resources
                        string extractedDir = Path.Combine(userDataFolder, "embedded_wwwroot");
                        Directory.CreateDirectory(extractedDir);

                        var asm = typeof(MainWindow).Assembly;
                        foreach (string resName in asm.GetManifestResourceNames())
                        {
                            if (resName.StartsWith("wwwroot."))
                            {
                                string relPath = resName.Substring("wwwroot.".Length)
                                    .Replace('\\', Path.DirectorySeparatorChar)
                                    .Replace('/', Path.DirectorySeparatorChar);

                                string destFile = Path.Combine(extractedDir, relPath);
                                string? destSubDir = Path.GetDirectoryName(destFile);
                                if (!string.IsNullOrEmpty(destSubDir))
                                {
                                    Directory.CreateDirectory(destSubDir);
                                }

                                using var stream = asm.GetManifestResourceStream(resName);
                                if (stream != null)
                                {
                                    using var fs = new FileStream(destFile, FileMode.Create, FileAccess.Write);
                                    stream.CopyTo(fs);
                                }
                            }
                        }

                        if (File.Exists(Path.Combine(extractedDir, "index.html")))
                        {
                            wwwrootDir = extractedDir;
                        }
                    }
                }

                if (Directory.Exists(wwwrootDir) && File.Exists(Path.Combine(wwwrootDir, "index.html")))
                {
                    _webView.CoreWebView2.SetVirtualHostNameToFolderMapping(
                        "installer.local",
                        wwwrootDir,
                        CoreWebView2HostResourceAccessKind.Allow
                    );
                    _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
                    _webView.CoreWebView2.Navigate("https://installer.local/index.html");
                }
            }
            catch (Exception ex)
            {
                // Fallback for air-gapped machines without a usable WebView2
                // runtime: hand off to the shipped legacy interface when it
                // is present, else offer the Evergreen runtime.
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string fallbackExe = Path.Combine(baseDir, "UpdateInstaller.orig.exe");
                if (File.Exists(fallbackExe))
                {
                    Process.Start(new ProcessStartInfo(fallbackExe) { UseShellExecute = true });
                    Application.Exit();
                    return;
                }
                // The name actually shipped by the native lazbuild lane —
                // the vestigial probe above is kept first for local setups
                // that still rely on it.
                fallbackExe = Path.Combine(baseDir, "UpdateInstallerLegacy.exe");
                if (File.Exists(fallbackExe))
                {
                    Process.Start(new ProcessStartInfo(fallbackExe) { UseShellExecute = true });
                    Application.Exit();
                    return;
                }

                ShowWebView2EvergreenOffer(DescribeWebView2Failure(ex));
            }
        }

        private void SendToWeb(object message)
        {
            // Issue #21: worker threads (download pipeline logs) call this; the
            // CoreWebView2 getter is a COM QI that must stay on the UI thread --
            // cross-thread it throws InvalidCastException E_NOINTERFACE (the
            // exact reported stack). Marshal EVERYTHING inside BeginInvoke; the
            // outer try/catch also swallows BeginInvoke itself throwing on a
            // dead/disposed control.
            try
            {
                string json = JsonSerializer.Serialize(message);
                this.BeginInvoke(new Action(() =>
                {
                    try
                    {
                        if (_webView?.CoreWebView2 == null) return;
                        _webView.CoreWebView2.PostWebMessageAsString(json);
                    }
                    catch { }
                }));
            }
            catch { return; }
        }

        private void LogToWeb(string text)
        {
            SendToWeb(new { type = "log", text = text });
        }

        private string GetClientDirectory()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            if (File.Exists(Path.Combine(baseDir, "UpdateInstaller.ini")))
            {
                return baseDir;
            }
            string clientSub = Path.Combine(baseDir, "client");
            if (File.Exists(Path.Combine(clientSub, "UpdateInstaller.ini")))
            {
                return clientSub;
            }
            string devClient = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "..", "client"));
            if (File.Exists(Path.Combine(devClient, "UpdateInstaller.ini")))
            {
                return devClient;
            }
            return baseDir;
        }

        private void OnWebMessageReceived(object? sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                string json = e.TryGetWebMessageAsString();
                using var doc = JsonDocument.Parse(json);
                string action = doc.RootElement.GetProperty("action").GetString() ?? "";

                // Safely clone payload to avoid disposed JsonDocument issues
                JsonElement payload = default;
                if (doc.RootElement.TryGetProperty("payload", out var p))
                {
                    payload = p.Clone();
                }

                switch (action)
                {
                    case "init":
                        HandleInit();
                        break;
                    case "exit":
                        Application.Exit();
                        break;
                    case "start":
                        HandleStart(payload);
                        break;
                    case "cancel":
                        HandleCancel();
                        break;
                }
            }
            catch (Exception ex)
            {
                LogToWeb("[ERROR] " + ex.Message);
            }
        }

        private void HandleInit()
        {
            // 1. Detect System Specs
            string osName = "Windows";
            string osBuild = "Build " + Environment.OSVersion.Version.Build;
            string osArch = Environment.Is64BitOperatingSystem ? "64-bit (x64)" : "32-bit (x86)";
            bool officeDetected = false;
            string officeName = "Microsoft Office";

            try
            {
                using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Windows NT\CurrentVersion");
                if (key != null)
                {
                    osName = key.GetValue("ProductName")?.ToString() ?? osName;
                    string displayVer = key.GetValue("DisplayVersion")?.ToString() ?? "";
                    string currentBuild = key.GetValue("CurrentBuild")?.ToString() ?? "";
                    if (!string.IsNullOrEmpty(currentBuild))
                    {
                        osBuild = $"Build {currentBuild} ({displayVer})";
                    }

                    // Windows 11 detection: Microsoft deliberately retains ProductName as "Windows 10 ..."
                    // in HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion for backward compatibility.
                    // For client editions, any build >= 22000 is Windows 11.
                    int buildNum = 0;
                    if (!int.TryParse(currentBuild, out buildNum))
                    {
                        int.TryParse(key.GetValue("CurrentBuildNumber")?.ToString(), out buildNum);
                    }
                    if (buildNum == 0)
                    {
                        buildNum = Environment.OSVersion.Version.Build;
                    }

                    string installType = key.GetValue("InstallationType")?.ToString() ?? "Client";
                    if (buildNum >= 22000 && !installType.Equals("Server", StringComparison.OrdinalIgnoreCase))
                    {
                        if (osName.StartsWith("Windows 10", StringComparison.OrdinalIgnoreCase))
                        {
                            osName = "Windows 11" + osName.Substring("Windows 10".Length);
                        }
                        else if (osName.Contains("Windows 10"))
                        {
                            osName = osName.Replace("Windows 10", "Windows 11");
                        }
                    }
                }
            }
            catch { }

            try
            {
                using var offKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Office\ClickToRun\Configuration");
                if (offKey != null)
                {
                    officeDetected = true;
                    officeName = offKey.GetValue("ProductReleaseIds")?.ToString() ?? "Office Click-to-Run";
                }
                else
                {
                    using var msiKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Office\16.0\Common\InstallRoot");
                    if (msiKey != null)
                    {
                        officeDetected = true;
                        officeName = "Microsoft Office 2016";
                    }
                }
            }
            catch { }

            // 2. Read UpdateInstaller.ini
            string clientDir = GetClientDirectory();
            string iniPath = Path.Combine(clientDir, "UpdateInstaller.ini");

            var opts = new Dictionary<string, bool>();

            if (File.Exists(iniPath))
            {
                string[] lines = File.ReadAllLines(iniPath);
                foreach (string line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed.Contains("="))
                    {
                        var parts = trimmed.Split('=', 2);
                        string k = parts[0].Trim();
                        bool v = parts[1].Trim().Equals("Enabled", StringComparison.OrdinalIgnoreCase);
                        opts[k] = v;
                    }
                }
            }

            SendToWeb(new
            {
                type = "state",
                specs = new
                {
                    osName,
                    osBuild,
                    osArch,
                    officeDetected,
                    officeName,
                    dotnetVersion = ".NET 4.8 / .NET 8.0"
                },
                options = opts
            });
        }

        private void HandleCancel()
        {
            try
            {
                _cts?.Cancel();
                if (_activeProcess != null && !_activeProcess.HasExited)
                {
                    _activeProcess.Kill(true);
                }
            }
            catch { }
            SendToWeb(new { type = "status", running = false });
        }

        private async void HandleStart(JsonElement payload)
        {
            _cts = new CancellationTokenSource();
            var ct = _cts.Token;

            SendToWeb(new { type = "status", running = true });

            string clientDir = GetClientDirectory();
            string cmdDir = Path.Combine(clientDir, "cmd");

            // Extract switches synchronously before entering background task
            var switches = new List<string>();
            if (payload.TryGetProperty("options", out var opts))
            {
                string[] boolKeys = {
                    "upgradebuilds", "updatercerts", "updatecpp", "updatedotnet5",
                    "instdotnet4", "instdotnet35", "instedge", "instwebview2",
                    "instoffice", "verify", "seconly", "autoreboot", "shutdown", "auditonly"
                };

                foreach (var k in boolKeys)
                {
                    if (opts.TryGetProperty(k, out var prop) && prop.GetBoolean())
                    {
                        if (k == "instoffice") switches.Add("/updateoffice");
                        else switches.Add($"/{k}");
                    }
                }
            }

            string switchStr = string.Join(" ", switches);

            // Save settings to UpdateInstaller.ini synchronously
            try
            {
                string iniPath = Path.Combine(clientDir, "UpdateInstaller.ini");
                if (File.Exists(iniPath) && payload.TryGetProperty("options", out var saveOpts))
                {
                    var lines = new List<string>(File.ReadAllLines(iniPath));
                    // Update key values if present
                    for (int i = 0; i < lines.Count; i++)
                    {
                        if (lines[i].Contains("="))
                        {
                            var parts = lines[i].Split('=', 2);
                            string k = parts[0].Trim();
                            if (saveOpts.TryGetProperty(k, out var bVal))
                            {
                                lines[i] = $"{k}={(bVal.GetBoolean() ? "Enabled" : "Disabled")}";
                            }
                        }
                    }
                    File.WriteAllLines(iniPath, lines);
                }
            }
            catch { }

            // Run execution in background Task
            await Task.Run(async () =>
            {
                try
                {
                    LogToWeb($"[CMD] Executing DoUpdate.cmd {switchStr}".Trim());

                    var psi = new ProcessStartInfo
                    {
                        FileName = "cmd.exe",
                        Arguments = $"/D /C \"DoUpdate.cmd {switchStr}\"",
                        WorkingDirectory = cmdDir,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        UseShellExecute = false,
                        CreateNoWindow = true
                    };

                    using var process = new Process { StartInfo = psi };
                    _activeProcess = process;

                    process.OutputDataReceived += (s, e) =>
                    {
                        if (e.Data != null) LogToWeb(e.Data);
                    };
                    process.ErrorDataReceived += (s, e) =>
                    {
                        if (string.IsNullOrWhiteSpace(e.Data)) return;

                        if (e.Data.Contains("ERROR", StringComparison.OrdinalIgnoreCase) ||
                            e.Data.Contains("failed", StringComparison.OrdinalIgnoreCase))
                        {
                            LogToWeb($"[ERROR] {e.Data}");
                        }
                        else if (e.Data.Contains("WARNING", StringComparison.OrdinalIgnoreCase))
                        {
                            LogToWeb($"[WARN] {e.Data}");
                        }
                        else
                        {
                            LogToWeb(e.Data);
                        }
                    };

                    process.Start();
                    process.BeginOutputReadLine();
                    process.BeginErrorReadLine();

                    await process.WaitForExitAsync(ct);

                    if (!ct.IsCancellationRequested)
                    {
                        LogToWeb("[SUCCESS] Installation process completed.");
                    }
                }
                catch (OperationCanceledException)
                {
                    LogToWeb("[ABORT] Installation cancelled by user.");
                }
                catch (Exception ex)
                {
                    LogToWeb($"[ERROR] Error during installation: {ex.Message}");
                }
                finally
                {
                    _activeProcess = null;
                    SendToWeb(new { type = "status", running = false });
                }
            }, ct);
        }

        private static bool IsAdministrator()
        {
            using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }

        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            // Net before gate so the startup gate itself is covered; gate
            // before the elevation relaunch so a broken runtime is
            // diagnosed without a UAC prompt first, and the elevated
            // instance re-runs this same silent check harmlessly.
            InstallGlobalExceptionNet();
            EnsureWebView2RuntimeOrFallback();
            if (!IsAdministrator())
            {
                try
                {
                    var exePath = Environment.ProcessPath ?? Application.ExecutablePath;
                    var psi = new ProcessStartInfo(exePath)
                    {
                        UseShellExecute = true,
                        Verb = "runas",
                        Arguments = JoinArgumentsQuoted(args)
                    };
                    Process.Start(psi);
                    return;
                }
                catch
                {
                    // User dismissed UAC prompt
                    return;
                }
            }

            // Self-update check starts ONLY in the surviving elevated
            // instance, after the elevation gate and before the window:
            // fire-and-forget, never delays launch, any offer appears only
            // over the already-open main window. InstallRoot is the parent
            // of the exe directory because this host ships inside client\.
            // Strict-newer decision is the existing WebView2Compat
            // comparator in both directions.
            _ = SelfUpdateCheck.RunAsync(new SelfUpdateOptions
            {
                LocalVersion = GetDisplayVersion(),
                InstallRoot = System.IO.Path.GetFullPath(
                    System.IO.Path.Combine(AppContext.BaseDirectory, "..")),
                Actor = "installer",
                HostExePath = Environment.ProcessPath ?? Application.ExecutablePath,
                IsChannelNewer = (channel, local) =>
                    WebView2Compat.IsVersionAtLeast(channel, local)
                    && !WebView2Compat.IsVersionAtLeast(local, channel),
                OwnerFormProvider = () => Instance,
            });
            // Healthy-first-launch marker (Phase 28), parsed only in the
            // surviving elevated instance - the argument already rode the
            // elevation re-pass above. When present, the file is written
            // only after the main window has opened successfully - never in
            // Main. A normal launch ignores the whole mechanism.
            string? healthyMarkerPath = ParseHealthyMarkerArg(args);
            MainWindow mainWindow = new MainWindow();
            if (healthyMarkerPath != null)
            {
                mainWindow.Shown += (sender, e) => WriteHealthyMarker(healthyMarkerPath);
            }
            Application.Run(mainWindow);
        }

        /// <summary>
        /// Re-pass the arguments through the elevation relaunch. A single
        /// argument carrying whitespace is quoted: the healthy-marker path
        /// lives under %LOCALAPPDATA%, which contains spaces whenever the
        /// Windows user name does - an unquoted join would split it into two
        /// arguments and the marker would never be written (a healthy update
        /// would roll back).
        /// </summary>
        private static string JoinArgumentsQuoted(string[] args)
        {
            var quoted = new List<string>(args.Length);
            foreach (string argument in args)
            {
                quoted.Add(argument.Contains(' ')
                    ? "\"" + argument + "\"" : argument);
            }
            return string.Join(" ", quoted);
        }

        /// <summary>
        /// Parse the updater's --healthy-marker argument; null on every
        /// normal launch.
        /// </summary>
        private static string? ParseHealthyMarkerArg(string[] args)
        {
            for (int i = 0; i + 1 < args.Length; i++)
            {
                if (string.Equals(args[i], "--healthy-marker", StringComparison.Ordinal))
                {
                    return args[i + 1];
                }
            }
            return null;
        }

        /// <summary>
        /// Write the healthy-launch proof: the display version plus a
        /// timestamp line. Never crashes the app - the updater's watchdog
        /// treats an absent marker as an unhealthy launch.
        /// </summary>
        private static void WriteHealthyMarker(string path)
        {
            try
            {
                File.WriteAllText(path,
                    GetDisplayVersion() + Environment.NewLine
                    + DateTime.UtcNow.ToString("o") + Environment.NewLine);
                SelfUpdateLog.Append("installer", "marker-written");
            }
            catch
            {
                // Marker write failure = unhealthy launch by contract; the
                // app itself keeps running either way.
            }
        }
    }

    // Pure WebView2 version logic, callable without a WebView2 runtime
    // (exercised by ci/tests/test-webview2-version-gate.sh).
    public static class WebView2Compat
    {
        // Keep in sync with MIN_WEBVIEW2_VERSION in
        // client/UpdateInstaller.cmd (the launcher-side twin of the in-host
        // gate since Phase 24): the runtime version paired with the pinned
        // WebView2 SDK. The battery cross-checks the const against the
        // launcher literal, so a drift fails the build instead of the users.
        public const string MinWebView2Version = "156.0.4314.35";

        // 4-part numeric comparison with launcher-parity semantics: any
        // '+'/'-' suffix is stripped first, then missing or non-numeric
        // parts count as 0 (fail-safe: an unparsable runtime never passes).
        public static bool IsVersionAtLeast(string? version, string minimum)
        {
            if (string.IsNullOrEmpty(version) || string.IsNullOrEmpty(minimum)) return false;
            string[] versionParts = StripSuffix(version).Split('.');
            string[] minimumParts = StripSuffix(minimum).Split('.');
            int count = Math.Max(versionParts.Length, minimumParts.Length);
            for (int i = 0; i < count; i++)
            {
                int v = i < versionParts.Length ? ParseNumericPart(versionParts[i]) : 0;
                int m = i < minimumParts.Length ? ParseNumericPart(minimumParts[i]) : 0;
                if (v != m) return v > m;
            }
            return true;
        }

        private static string StripSuffix(string version)
        {
            int cut = version.IndexOfAny(new[] { '+', '-' });
            return cut >= 0 ? version.Substring(0, cut) : version;
        }

        private static int ParseNumericPart(string part)
        {
            return int.TryParse(part, out int value) ? value : 0;
        }
    }
}
