using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace WSUSOffline.Generator
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
            this.Text = "WSUS Offline Next 2026.10.0 - Generator";
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

            InitializeWebView();
        }

        private async void InitializeWebView()
        {
            _webView = new WebView2 { Dock = DockStyle.Fill };
            this.Controls.Add(_webView);

            try
            {
                string userDataFolder = Path.Combine(Path.GetTempPath(), "WSUSGenerator_Cache");
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
                MessageBox.Show("WebView2 Error: " + ex.Message, "WSUS Offline Next", MessageBoxButtons.OK, MessageBoxIcon.Error);
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
            Application.Run(new MainWindow());
        }
    }
}
