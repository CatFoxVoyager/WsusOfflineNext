using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace WSUSOffline.Installer
{
    public class MainWindow : Form
    {
        private WebView2? _webView;
        private Process? _activeProcess;
        private CancellationTokenSource? _cts;

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        public MainWindow()
        {
            this.Text = "WSUS Offline Next 2026.10.0 - Client Installer";
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

            InitializeWebView();
        }

        private async void InitializeWebView()
        {
            _webView = new WebView2 { Dock = DockStyle.Fill };
            this.Controls.Add(_webView);

            try
            {
                string userDataFolder = Path.Combine(Path.GetTempPath(), "WSUSInstaller_Cache");
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
                // Fallback for air-gapped machines without WebView2 runtime
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string fallbackExe = Path.Combine(baseDir, "UpdateInstaller.orig.exe");
                if (File.Exists(fallbackExe))
                {
                    Process.Start(new ProcessStartInfo(fallbackExe) { UseShellExecute = true });
                    Application.Exit();
                    return;
                }

                MessageBox.Show("WebView2 Error: " + ex.Message + "\nWebView2 runtime is required for the modern interface.", "WSUS Offline Next Installer", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        private void SendToWeb(object message)
        {
            if (_webView?.CoreWebView2 == null) return;
            string json = JsonSerializer.Serialize(message);
            this.BeginInvoke(new Action(() =>
            {
                try { _webView.CoreWebView2.PostWebMessageAsString(json); } catch { }
            }));
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
            if (!IsAdministrator())
            {
                try
                {
                    var exePath = Environment.ProcessPath ?? Application.ExecutablePath;
                    var psi = new ProcessStartInfo(exePath)
                    {
                        UseShellExecute = true,
                        Verb = "runas",
                        Arguments = string.Join(" ", args)
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

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainWindow());
        }
    }
}
