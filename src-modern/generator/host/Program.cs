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
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;
using WsusOfflineNext.SelfUpdate;

namespace WSUSOffline.Generator
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
            this.Text = $"WSUS Offline Next {GetDisplayVersion()} - Generator";
            this.Width = 1180;
            this.Height = 780;
            this.MinimumSize = new System.Drawing.Size(950, 650);
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
                + "\nclient\\edge\\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"
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
            if (MessageBox.Show(message, "WSUS Offline Next",
                MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
            {
                ShowEvergreenFallbackOrExit();
                Environment.Exit(0);
            }
            Environment.Exit(1);
        }

        // Single sink of the global exception net. A second fatal while the
        // dialog is up exits immediately; the dialog owner performs the
        // Evergreen fallback offer before the exit so the AppDomain event's
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
                            "WSUS Offline Next",
                            MessageBoxButtons.YesNo, MessageBoxIcon.Warning) == DialogResult.Yes)
                    {
                        ShowEvergreenFallbackOrExit();
                    }
                }
                else
                {
                    MessageBox.Show(
                        "Une erreur inattendue a interrompu l'application.\n" + ex.Message + "\n\nJournal de diagnostic : " + GetStartupDiagnosticsLogPath(),
                        "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Error);
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

        // Compile-time constant: the official Microsoft Evergreen page.
        // NEVER derived from user input (argv, INI, registry content) —
        // the dialog is the first surface a stranded user reads and its
        // URL must not be spoofable.
        private const string EvergreenUrl =
            "https://developer.microsoft.com/microsoft-edge/webview2/";

        // The classic AutoIt generator interface was retired as part of the
        // anti-false-positive migration: when the WebView2 Runtime
        // requirement is not met there is no legacy exe to hand off to, so
        // this dialog offers the Evergreen runtime instead — the bundled
        // offline bootstrapper when it ships in the tree, the official
        // Microsoft page otherwise. Does not change the caller's exit flow.
        private static void ShowWebView2EvergreenOffer(string? failureDetail)
        {
            string bootstrapperPath = Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory, "client", "edge",
                "MicrosoftEdgeWebView2RuntimeInstallerX64.exe");
            bool bootstrapperPresent = File.Exists(bootstrapperPath);
            string message =
                "The classic AutoIt generator interface was retired as part of the"
                + " anti-false-positive migration, and the Microsoft Edge WebView2"
                + " Runtime requirement (version " + WebView2Compat.MinWebView2Version
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
            if (MessageBox.Show(message, "WSUS Offline Next",
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

        // Failure path shared by the startup gate and the global exception
        // net: no legacy exe exists anymore, so the fallback IS the
        // Evergreen offer dialog.
        private static void ShowEvergreenFallbackOrExit()
        {
            ShowWebView2EvergreenOffer(null);
        }

        private static void LogFatal(Exception ex)
        {
            try
            {
                string logDir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "WSUSOfflineNext", "Generator");
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
                "WSUSOfflineNext", "Generator", "startup-diagnostics.log");
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
                    "WSUSOfflineNext", "Generator"));
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
                string userDataFolder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WSUSOfflineNext", "Generator");
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
                    string devDir = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", "src-modern", "generator", "dist"));
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
                        "generator.local",
                        wwwrootDir,
                        CoreWebView2HostResourceAccessKind.Allow
                    );
                    _webView.CoreWebView2.WebMessageReceived += OnWebMessageReceived;
                    _webView.CoreWebView2.Navigate("https://generator.local/index.html");
                }
            }
            catch (Exception ex)
            {
                // WebView2 startup failed: the classic AutoIt generator is
                // retired, so there is no legacy exe to hand off to —
                // offer the Evergreen runtime instead.
                ShowWebView2EvergreenOffer(DescribeWebView2Failure(ex));
            }
        }

        private void SendToWeb(object message)
        {
            // Issue #21: the download pipeline calls this from Task.Run worker
            // threads (progress logs). The CoreWebView2 getter is a COM QI that
            // must only run on the UI thread -- accessed cross-thread it throws
            // InvalidCastException E_NOINTERFACE (the exact reported stack).
            // Marshal EVERYTHING, including the null-check, inside BeginInvoke;
            // the outer try/catch also swallows BeginInvoke itself throwing on
            // a dead/disposed control.
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

        private string GetRootDirectory()
        {
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            if (File.Exists(Path.Combine(baseDir, "UpdateGenerator.ini")))
            {
                return baseDir;
            }
            string devRoot = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", "..", ".."));
            if (File.Exists(Path.Combine(devRoot, "UpdateGenerator.ini")))
            {
                return devRoot;
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

                // Safely extract payload as standalone cloned element
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
                    case "browse_folder":
                        HandleBrowseFolder();
                        break;
                    case "open_folder":
                        HandleOpenFolder(payload);
                        break;
                    case "start":
                        HandleStartDownload(payload);
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
            string root = GetRootDirectory();
            string genIni = Path.Combine(root, "UpdateGenerator.ini");
            string win10Ini = Path.Combine(root, "Windows10Versions.ini");

            var win11Dict = new Dictionary<string, bool>();
            var win10Dict = new Dictionary<string, bool>();

            if (File.Exists(win10Ini))
            {
                string[] lines = File.ReadAllLines(win10Ini);
                string currentSection = "";
                foreach (string line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                    {
                        currentSection = trimmed.Substring(1, trimmed.Length - 2).Trim();
                    }
                    else if (trimmed.Contains("="))
                    {
                        var parts = trimmed.Split('=', 2);
                        string k = parts[0].Trim();
                        bool v = parts[1].Trim().Equals("Enabled", StringComparison.OrdinalIgnoreCase);
                        if (currentSection == "Windows 11") win11Dict[k] = v;
                        if (currentSection == "Windows 10") win10Dict[k] = v;
                    }
                }
            }

            var opts = new Dictionary<string, object>();
            string usbPath = "E:\\Windows Update";
            bool copyUsb = true;

            var legacyDict = new Dictionary<string, bool>
            {
                { "w61_x64", false },
                { "w61_x86", false },
                { "w60_x64", false },
                { "w60_x86", false },
                { "w63_x64", false },
                { "w63_x86", false },
                { "w62_x64", false },
                { "wxp_x86", false }
            };

            if (File.Exists(genIni))
            {
                string[] lines = File.ReadAllLines(genIni);
                string currentSection = "";
                foreach (string line in lines)
                {
                    string trimmed = line.Trim();
                    if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                    {
                        currentSection = trimmed.Substring(1, trimmed.Length - 2).Trim();
                    }
                    else if (trimmed.Contains("="))
                    {
                        var parts = trimmed.Split('=', 2);
                        string k = parts[0].Trim();
                        string v = parts[1].Trim();
                        bool isEnabled = v.Equals("Enabled", StringComparison.OrdinalIgnoreCase);

                        if (currentSection == "Windows 7 x64" && k == "glb") legacyDict["w61_x64"] = isEnabled;
                        if (currentSection == "Windows 7" && k == "glb") legacyDict["w61_x86"] = isEnabled;
                        if (currentSection == "Windows Vista x64" && k == "glb") legacyDict["w60_x64"] = isEnabled;
                        if (currentSection == "Windows Vista" && k == "glb") legacyDict["w60_x86"] = isEnabled;
                        if (currentSection == "Windows Server 2012 R2" && k == "glb") legacyDict["w63_x64"] = isEnabled;
                        if (currentSection == "Windows 8.1" && k == "glb") legacyDict["w63_x86"] = isEnabled;
                        if (currentSection == "Windows Server 2012" && k == "glb") legacyDict["w62_x64"] = isEnabled;
                        if (currentSection == "Windows XP" && k == "glb") legacyDict["wxp_x86"] = isEnabled;

                        if (currentSection == "USB Images")
                        {
                            if (k == "copy") copyUsb = isEnabled;
                            if (k == "path") usbPath = v;
                        }
                        if (currentSection == "Options")
                        {
                            opts[k] = isEnabled;
                        }
                    }
                }
            }

            opts["usbPath"] = usbPath;
            opts["copyUsb"] = copyUsb;

            SendToWeb(new
            {
                type = "state",
                win11 = win11Dict,
                win10 = win10Dict,
                legacy = legacyDict,
                options = opts
            });
        }

        private void HandleBrowseFolder()
        {
            this.Invoke(new Action(() =>
            {
                using var dlg = new FolderBrowserDialog
                {
                    Description = "Select target folder or USB drive:",
                    UseDescriptionForTitle = true
                };
                if (dlg.ShowDialog() == DialogResult.OK)
                {
                    SendToWeb(new { type = "folder_selected", path = dlg.SelectedPath });
                }
            }));
        }

        private void HandleOpenFolder(JsonElement payload)
        {
            string relPath = payload.TryGetProperty("path", out var p) ? p.GetString() ?? "" : "";
            string fullPath = Path.Combine(GetRootDirectory(), relPath);
            if (Directory.Exists(fullPath))
            {
                Process.Start(new ProcessStartInfo("explorer.exe", fullPath) { UseShellExecute = true });
            }
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

        // Strongly typed POCO data extracted synchronously before async execution
        private class ExecutionJob
        {
            public bool HasWin11Or10x64 { get; set; }
            public bool HasWin10x86 { get; set; }
            public List<string> OfficeC2RTasks { get; set; } = new();
            public List<string> LegacyTasks { get; set; } = new();
            public bool CopyUsb { get; set; }
            public string UsbPath { get; set; } = "";
            public bool CreateIso { get; set; }
            public string Switches { get; set; } = "";
        }

        private async void HandleStartDownload(JsonElement payload)
        {
            _cts = new CancellationTokenSource();
            var ct = _cts.Token;

            SendToWeb(new { type = "status", running = true });

            string root = GetRootDirectory();
            string cmdDir = Path.Combine(root, "cmd");

            // Extract all data synchronously to avoid any disposed JsonDocument errors
            var job = new ExecutionJob();
            var switches = new List<string>();

            if (payload.TryGetProperty("options", out var opts))
            {
                if (opts.TryGetProperty("includedotnet", out var d) && d.GetBoolean()) switches.Add("/includedotnet");
                if (opts.TryGetProperty("includewddefs", out var wd) && wd.GetBoolean()) switches.Add("/includewddefs");
                if (opts.TryGetProperty("includeedge", out var ed) && ed.GetBoolean()) switches.Add("/includeedge");
                if (opts.TryGetProperty("includewebview2", out var wv) && wv.GetBoolean()) switches.Add("/includewebview2");
                if (opts.TryGetProperty("seconly", out var so) && so.GetBoolean()) switches.Add("/seconly");
                if (opts.TryGetProperty("verifydownloads", out var vd) && vd.GetBoolean()) switches.Add("/verify");

                if (opts.TryGetProperty("copyUsb", out var cUsb) && cUsb.GetBoolean()) job.CopyUsb = true;
                if (opts.TryGetProperty("usbPath", out var up)) job.UsbPath = up.GetString() ?? "";
                if (opts.TryGetProperty("createIso", out var ci) && ci.GetBoolean()) job.CreateIso = true;
            }

            job.Switches = string.Join(" ", switches);

            if (payload.TryGetProperty("win11", out var w11))
            {
                foreach (var prop in w11.EnumerateObject())
                {
                    if (prop.Value.GetBoolean()) { job.HasWin11Or10x64 = true; break; }
                }
            }
            if (!job.HasWin11Or10x64 && payload.TryGetProperty("win10", out var w10))
            {
                foreach (var prop in w10.EnumerateObject())
                {
                    if (prop.Name.EndsWith("_x64") && prop.Value.GetBoolean()) { job.HasWin11Or10x64 = true; break; }
                }
            }

            if (payload.TryGetProperty("win10", out var w10x86))
            {
                foreach (var prop in w10x86.EnumerateObject())
                {
                    if (prop.Name.EndsWith("_x86") && prop.Value.GetBoolean()) { job.HasWin10x86 = true; break; }
                }
            }

            if (payload.TryGetProperty("office", out var off))
            {
                string[] offVersions = { "o2k19", "o2k21", "o2k24" };
                foreach (var ver in offVersions)
                {
                    if (off.TryGetProperty($"{ver}_x64", out var o64) && o64.GetBoolean())
                    {
                        job.OfficeC2RTasks.Add($"{ver} x64");
                    }
                    if (off.TryGetProperty($"{ver}_x86", out var o86) && o86.GetBoolean())
                    {
                        job.OfficeC2RTasks.Add($"{ver} x86");
                    }
                }
            }

            if (payload.TryGetProperty("legacy", out var leg))
            {
                var legacyTargets = new (string Key, string Target)[]
                {
                    ("w61_x64", "w61-x64"),
                    ("w61_x86", "w61"),
                    ("w60_x64", "w60-x64"),
                    ("w60_x86", "w60"),
                    ("w63_x64", "w63-x64"),
                    ("w63_x86", "w63"),
                    ("w62_x64", "w62-x64"),
                    ("wxp_x86", "wxp")
                };

                foreach (var (k, target) in legacyTargets)
                {
                    if (leg.TryGetProperty(k, out var val) && val.GetBoolean())
                    {
                        job.LegacyTasks.Add(target);
                    }
                }
            }

            // Save INI files synchronously
            try
            {
                SaveIniFiles(root, payload);
            }
            catch (Exception ex)
            {
                LogToWeb($"[WARN] Could not update INI files: {ex.Message}");
            }

            // Run execution in background Task with pure strongly-typed job
            await Task.Run(async () =>
            {
                try
                {
                    // 1. Download Updates
                    if (job.HasWin11Or10x64 && !ct.IsCancellationRequested)
                    {
                        await RunCommandAsync("DownloadUpdates.cmd", $"w100-x64 glb {job.Switches}".Trim(), cmdDir, ct);
                    }

                    if (job.HasWin10x86 && !ct.IsCancellationRequested)
                    {
                        await RunCommandAsync("DownloadUpdates.cmd", $"w100 glb {job.Switches}".Trim(), cmdDir, ct);
                    }

                    // Legacy targets (Windows 7, Windows Vista, 8.1, Server 2008/2012, XP)
                    foreach (var legTarget in job.LegacyTasks)
                    {
                        if (ct.IsCancellationRequested) break;
                        await RunCommandAsync("DownloadUpdates.cmd", $"{legTarget} glb {job.Switches}".Trim(), cmdDir, ct);
                    }

                    // 2. Download Office C2R
                    foreach (var offTask in job.OfficeC2RTasks)
                    {
                        if (ct.IsCancellationRequested) break;
                        await RunCommandAsync("DownloadOfficeC2R.cmd", offTask, cmdDir, ct);
                    }

                    // 3. Create ISO if requested
                    if (job.CreateIso && !ct.IsCancellationRequested)
                    {
                        LogToWeb("[ISO] Creating ISO images...");
                        if (job.HasWin11Or10x64)
                        {
                            await RunCommandAsync("CreateISOImage.cmd", $"w100-x64 glb", cmdDir, ct);
                        }
                        if (job.HasWin10x86)
                        {
                            await RunCommandAsync("CreateISOImage.cmd", $"w100 glb", cmdDir, ct);
                        }
                        foreach (var legTarget in job.LegacyTasks)
                        {
                            if (ct.IsCancellationRequested) break;
                            await RunCommandAsync("CreateISOImage.cmd", $"{legTarget} glb", cmdDir, ct);
                        }
                    }

                    // 4. Copy to USB if requested
                    if (job.CopyUsb && !string.IsNullOrEmpty(job.UsbPath) && !ct.IsCancellationRequested)
                    {
                        LogToWeb($"[USB] Copying updates to target media: {job.UsbPath}...");
                        if (job.HasWin11Or10x64)
                        {
                            await RunCommandAsync("CopyToTarget.cmd", $"w100-x64 \"{job.UsbPath}\"", cmdDir, ct);
                        }
                        if (job.HasWin10x86)
                        {
                            await RunCommandAsync("CopyToTarget.cmd", $"w100 \"{job.UsbPath}\"", cmdDir, ct);
                        }
                        foreach (var legTarget in job.LegacyTasks)
                        {
                            if (ct.IsCancellationRequested) break;
                            await RunCommandAsync("CopyToTarget.cmd", $"{legTarget} \"{job.UsbPath}\"", cmdDir, ct);
                        }
                    }

                    if (!ct.IsCancellationRequested)
                    {
                        LogToWeb("[SUCCESS] Download pipeline completed successfully!");
                    }
                }
                catch (OperationCanceledException)
                {
                    LogToWeb("[ABORT] Download cancelled by user.");
                }
                catch (Exception ex)
                {
                    LogToWeb($"[ERROR] Error during execution: {ex.Message}");
                }
                finally
                {
                    SendToWeb(new { type = "status", running = false });
                }
            }, ct);
        }

        private void SaveIniFiles(string root, JsonElement payload)
        {
            string win10Ini = Path.Combine(root, "Windows10Versions.ini");
            if (File.Exists(win10Ini))
            {
                var lines = new List<string>();
                lines.Add("[Windows 10]");
                if (payload.TryGetProperty("win10", out var w10))
                {
                    foreach (var prop in w10.EnumerateObject())
                    {
                        lines.Add($"{prop.Name}={(prop.Value.GetBoolean() ? "Enabled" : "Disabled")}");
                    }
                }
                lines.Add("[Windows 11]");
                if (payload.TryGetProperty("win11", out var w11))
                {
                    foreach (var prop in w11.EnumerateObject())
                    {
                        lines.Add($"{prop.Name}={(prop.Value.GetBoolean() ? "Enabled" : "Disabled")}");
                    }
                }
                File.WriteAllLines(win10Ini, lines);
            }

            string genIni = Path.Combine(root, "UpdateGenerator.ini");
            if (File.Exists(genIni) && payload.TryGetProperty("legacy", out var leg))
            {
                var sectionMap = new Dictionary<string, string>
                {
                    { "w61_x64", "Windows 7 x64" },
                    { "w61_x86", "Windows 7" },
                    { "w60_x64", "Windows Vista x64" },
                    { "w60_x86", "Windows Vista" },
                    { "w63_x64", "Windows Server 2012 R2" },
                    { "w63_x86", "Windows 8.1" },
                    { "w62_x64", "Windows Server 2012" },
                    { "wxp_x86", "Windows XP" }
                };

                var lines = new List<string>(File.ReadAllLines(genIni));
                foreach (var kvp in sectionMap)
                {
                    if (leg.TryGetProperty(kvp.Key, out var val))
                    {
                        string status = val.GetBoolean() ? "Enabled" : "Disabled";
                        int secIdx = lines.FindIndex(l => l.Trim().Equals($"[{kvp.Value}]", StringComparison.OrdinalIgnoreCase));
                        if (secIdx >= 0 && secIdx + 1 < lines.Count && lines[secIdx + 1].StartsWith("glb="))
                        {
                            lines[secIdx + 1] = $"glb={status}";
                        }
                    }
                }
                File.WriteAllLines(genIni, lines);
            }
        }

        private async Task RunCommandAsync(string script, string arguments, string workingDir, CancellationToken ct)
        {
            LogToWeb($"[CMD] {script} {arguments}");

            var psi = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/D /C \"{script} {arguments}\"",
                WorkingDirectory = workingDir,
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

            try
            {
                await process.WaitForExitAsync(ct);
            }
            finally
            {
                _activeProcess = null;
            }
        }

        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            // Net before gate so the startup gate itself is covered; gate
            // before Run so no WebView2 call precedes the runtime check.
            InstallGlobalExceptionNet();
            EnsureWebView2RuntimeOrFallback();
            // Fire-and-forget self-update check: started before the window
            // exists, never delays the launch; any offer can only appear
            // over the already-open main window. Strict-newer decision is
            // the existing WebView2Compat comparator in both directions.
            _ = SelfUpdateCheck.RunAsync(new SelfUpdateOptions
            {
                LocalVersion = GetDisplayVersion(),
                InstallRoot = AppContext.BaseDirectory,
                Actor = "generator",
                IsChannelNewer = (channel, local) =>
                    WebView2Compat.IsVersionAtLeast(channel, local)
                    && !WebView2Compat.IsVersionAtLeast(local, channel),
                OwnerFormProvider = () => Instance,
            });
            Application.Run(new MainWindow());
        }
    }

    // Pure WebView2 version logic, callable without a WebView2 runtime
    // (exercised by ci/tests/test-webview2-version-gate.sh).
    public static class WebView2Compat
    {
        // Keep in sync with MIN_WEBVIEW2_VERSION in UpdateGenerator.cmd
        // (the launcher-side twin of the in-host gate since Phase 24): the
        // runtime version paired with the pinned WebView2 SDK. The battery
        // cross-checks the const against the launcher literal, so a drift
        // fails the build instead of the users.
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
