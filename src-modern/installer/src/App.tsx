import { useState, useEffect, useRef } from 'react';
import {
  ShieldCheck,
  Terminal,
  Play,
  Square,
  Copy,
  Trash2,
  ChevronDown,
  ChevronUp,
  Cpu,
  Monitor,
  RotateCcw,
  Power,
  PackageCheck,
  Layers,
  Settings2,
  Loader2
} from 'lucide-react';

interface LogEntry {
  id: string;
  time: string;
  level: 'info' | 'warn' | 'error' | 'success' | 'start';
  text: string;
}

const parseLogLine = (raw: string): LogEntry => {
  const now = new Date();
  const defaultTime = now.toTimeString().split(' ')[0];
  let time = defaultTime;
  let text = raw;

  const match = raw.match(/^\[(\d{2}:\d{2}:\d{2})\]\s*(.*)$/);
  if (match) {
    time = match[1];
    text = match[2];
  }

  let level: LogEntry['level'] = 'info';
  if (/\[ERROR\]|\[ERR\]|\bERROR\b|\bfailed\b/i.test(text)) {
    level = 'error';
  } else if (/\[WARN\]|\bWarning\b/i.test(text)) {
    level = 'warn';
  } else if (/\[SUCCESS\]|\bpassed\b|completed successfully|Downloaded\/validated/i.test(text)) {
    level = 'success';
  } else if (/\[START\]/i.test(text)) {
    level = 'start';
  }

  return {
    id: Math.random().toString(36).substring(2, 9),
    time,
    level,
    text: text.replace(/^\[(INFO|WARN|ERROR|ERR|SUCCESS|START)\]\s*/i, '')
  };
};

interface SystemSpecs {
  osName: string;
  osBuild: string;
  osArch: string;
  officeDetected: boolean;
  officeName: string;
  dotnetVersion: string;
}

export default function App() {
  const urlParams = typeof window !== 'undefined' ? new URLSearchParams(window.location.search) : null;
  const initialConsole = urlParams?.get('console') === 'true';

  const [isRunning, setIsRunning] = useState(false);
  const [isTerminalOpen, setIsTerminalOpen] = useState(initialConsole);
  const [autoScroll, setAutoScroll] = useState(true);
  const [logs, setLogs] = useState<LogEntry[]>([
    parseLogLine('[INIT] WSUS Offline Next Installer initialized.'),
    parseLogLine('[INFO] System information and component options loaded.'),
    parseLogLine('[READY] Select options, then click Start installation.')
  ]);
  const logContainerRef = useRef<HTMLDivElement>(null);

  const [specs, setSpecs] = useState<SystemSpecs>({
    osName: 'Microsoft Windows 11 Pro',
    osBuild: 'Build 26300 (26H2)',
    osArch: '64-bit (x64)',
    officeDetected: true,
    officeName: 'Microsoft Office LTSC 2021',
    dotnetVersion: '4.8.1 / .NET 8.0'
  });

  const [options, setOptions] = useState({
    upgradebuilds: true,
    updatercerts: true,
    updatecpp: true,
    updatedotnet5: true,
    instdotnet4: false,
    instdotnet35: false,
    instedge: false,
    instwebview2: false,
    instoffice: true,
    verify: true,
    seconly: false,
    autoreboot: false,
    shutdown: false,
    auditonly: false
  });

  const sendNative = (action: string, payload: any = {}) => {
    if (typeof window !== 'undefined' && (window as any).chrome?.webview?.postMessage) {
      (window as any).chrome.webview.postMessage(JSON.stringify({ action, payload }));
    } else {
      console.log('[NativeBridge Mock]', action, payload);
    }
  };

  useEffect(() => {
    const handleNativeMessage = (event: any) => {
      try {
        const data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
        if (data.type === 'log') {
          setLogs(prev => [...prev, parseLogLine(data.text)]);
        } else if (data.type === 'state') {
          if (data.specs) setSpecs(data.specs);
          if (data.options) setOptions(prev => ({ ...prev, ...data.options }));
        } else if (data.type === 'status') {
          setIsRunning(data.running);
        }
      } catch (err) {
        console.error('Error parsing native message', err);
      }
    };

    if (typeof window !== 'undefined' && (window as any).chrome?.webview) {
      (window as any).chrome.webview.addEventListener('message', handleNativeMessage);
      sendNative('init', {});
    }

    return () => {
      if (typeof window !== 'undefined' && (window as any).chrome?.webview) {
        (window as any).chrome.webview.removeEventListener('message', handleNativeMessage);
      }
    };
  }, []);

  useEffect(() => {
    if (autoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  const handleStart = () => {
    setIsRunning(true);
    setIsTerminalOpen(true);
    setLogs(prev => [...prev, parseLogLine('[START] Starting offline update installation...')]);
    sendNative('start', { options });
  };

  const handleStop = () => {
    sendNative('cancel', {});
    setIsRunning(false);
    setLogs(prev => [...prev, parseLogLine('[WARN] Installation cancellation requested.')]);
  };

  const handleExit = () => {
    sendNative('exit', {});
  };

  return (
    <div className="flex flex-col h-screen w-screen bg-dark-950 text-zinc-100 font-sans select-none overflow-hidden">
      {/* 1. Header Bar */}
      <header className="h-14 border-b border-dark-800 bg-dark-900 px-5 flex items-center justify-between shrink-0">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-md bg-accent-600/15 border border-accent-600/30 flex items-center justify-center text-accent-400">
            <ShieldCheck className="w-4 h-4" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-sm font-semibold text-zinc-100 tracking-tight">WSUS Offline Next Installer</h1>
              <span className="text-[11px] px-2 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700 font-mono font-medium">
                v2026.10.2 • Administrator access
              </span>
            </div>
            <p className="text-[11px] text-zinc-400">Offline update installer for Windows and Office</p>
          </div>
        </div>

        <div className="flex items-center gap-3">
          <button
            onClick={handleExit}
            className="px-3 py-1.5 rounded-md bg-dark-850 hover:bg-dark-800 border border-dark-800 text-zinc-400 hover:text-zinc-200 transition-colors text-xs font-medium"
          >
            Close
          </button>
        </div>
      </header>

      {/* 2. System Detected Specs Banner */}
      <div className="bg-dark-900 border-b border-dark-800 px-5 py-2.5 flex flex-wrap items-center justify-between gap-3 text-xs shrink-0">
        <div className="flex flex-wrap items-center gap-4">
          <div className="flex items-center gap-2 text-zinc-300">
            <Monitor className="w-3.5 h-3.5 text-accent-400 shrink-0" />
            <span>Target system: <strong className="text-zinc-100">{specs.osName}</strong></span>
            <span className="text-[11px] font-mono px-1.5 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700">
              {specs.osBuild} • {specs.osArch}
            </span>
          </div>

          <div className="hidden md:block h-3.5 w-px bg-dark-800"></div>

          <div className="flex items-center gap-2 text-zinc-300">
            <PackageCheck className="w-3.5 h-3.5 text-accent-400 shrink-0" />
            <span>Office suite: <span className="text-zinc-200 font-medium">{specs.officeDetected ? specs.officeName : 'Not detected'}</span></span>
          </div>
        </div>

        <div className="flex items-center gap-2 text-[11px] text-zinc-400">
          <Layers className="w-3.5 h-3.5 text-zinc-500 shrink-0" />
          <span>Detected runtimes: <span className="font-mono text-zinc-300">{specs.dotnetVersion}</span></span>
        </div>
      </div>

      {/* 3. Main Options Body (3 Compartments) */}
      <main className="flex-1 overflow-y-auto p-5 bg-dark-950 space-y-4">
        <div className="max-w-5xl mx-auto space-y-4">
          {/* Top Row: 2 Main Columns */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {/* Compartment 1: Operating System & Runtimes */}
            <div className="p-4 rounded-xl bg-dark-900 border border-dark-800 space-y-3 flex flex-col">
              <div className="flex items-center justify-between pb-2.5 border-b border-dark-800">
                <div className="flex items-center gap-2 text-xs font-semibold text-zinc-100">
                  <Cpu className="w-4 h-4 text-accent-400" />
                  <span>Operating system & Runtimes</span>
                </div>
                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-dark-850 text-zinc-400 border border-dark-800">
                  System
                </span>
              </div>

              <div className="space-y-1 flex-1">
                {[
                  { key: 'upgradebuilds', label: 'Upgrade build using an enablement package', desc: 'Apply an available enablement package to an eligible Windows build' },
                  { key: 'updatercerts', label: 'Update root certificates', desc: 'Install trusted Windows root certificates' },
                  { key: 'updatecpp', label: 'Update Visual C++ redistributables', desc: 'Microsoft Visual C++ redistributable packages' },
                  { key: 'updatedotnet5', label: 'Update modern .NET runtimes', desc: 'Install the .NET runtime packages available on this media' },
                  { key: 'instdotnet4', label: 'Install / Update .NET Framework 4.8.x', desc: 'Runtime for applications that require .NET Framework 4.8.x' },
                  { key: 'instdotnet35', label: 'Enable / Install .NET Framework 3.5', desc: 'Compatibility runtime for legacy applications' },
                ].map(item => (
                  <label
                    key={item.key}
                    className="flex items-start gap-3 p-2.5 rounded-lg border border-transparent hover:bg-dark-850/70 hover:border-dark-800/80 cursor-pointer transition-colors"
                  >
                    <input
                      type="checkbox"
                      checked={(options as any)[item.key]}
                      onChange={(e) => setOptions(prev => ({ ...prev, [item.key]: e.target.checked }))}
                      className="mt-0.5 w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer"
                    />
                    <div className="min-w-0 flex-1">
                      <span className="text-xs font-medium text-zinc-100">{item.label}</span>
                      <p className="text-[11px] text-zinc-400 mt-0.5 leading-snug">{item.desc}</p>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {/* Compartment 2: Applications & Integrity Controls */}
            <div className="p-4 rounded-xl bg-dark-900 border border-dark-800 space-y-3 flex flex-col">
              <div className="flex items-center justify-between pb-2.5 border-b border-dark-800">
                <div className="flex items-center gap-2 text-xs font-semibold text-zinc-100">
                  <ShieldCheck className="w-4 h-4 text-accent-400" />
                  <span>Applications & Integrity checks</span>
                </div>
                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-dark-850 text-zinc-400 border border-dark-800">
                  Software
                </span>
              </div>

              <div className="space-y-1 flex-1">
                {[
                  { key: 'instoffice', label: 'Update Microsoft Office', desc: 'Apply offline updates to detected Office installations' },
                  { key: 'instedge', label: 'Install / Update Microsoft Edge', desc: 'Microsoft Edge Enterprise offline installer' },
                  { key: 'instwebview2', label: 'Install Edge WebView2 Runtime', desc: 'Runtime required by applications that use WebView2' },
                  { key: 'verify', label: 'Verify package integrity', desc: 'Check update files against the integrity database before installation' },
                  { key: 'seconly', label: 'Security-only updates', desc: 'Request security-only updates where available' }
                ].map(item => (
                  <label
                    key={item.key}
                    className="flex items-start gap-3 p-2.5 rounded-lg border border-transparent hover:bg-dark-850/70 hover:border-dark-800/80 cursor-pointer transition-colors"
                  >
                    <input
                      type="checkbox"
                      checked={(options as any)[item.key]}
                      onChange={(e) => setOptions(prev => ({ ...prev, [item.key]: e.target.checked }))}
                      className="mt-0.5 w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer"
                    />
                    <div className="min-w-0 flex-1">
                      <span className="text-xs font-medium text-zinc-100">{item.label}</span>
                      <p className="text-[11px] text-zinc-400 mt-0.5 leading-snug">{item.desc}</p>
                    </div>
                  </label>
                ))}
              </div>
            </div>
          </div>

          {/* Compartment 3: Post-Installation Sensitive Actions */}
          <div className="p-4 rounded-xl bg-dark-900 border border-dark-800 space-y-3">
            <div className="flex items-center justify-between pb-2.5 border-b border-dark-800">
              <div className="flex items-center gap-2 text-xs font-semibold text-zinc-100">
                <Settings2 className="w-4 h-4 text-accent-400" />
                <span>Restart & Shutdown</span>
              </div>
              <span className="text-[11px] text-zinc-500">Choose what happens after updates are applied</span>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              {/* Auto Reboot Option */}
              <label
                className={`flex items-start gap-3 p-3 rounded-lg border transition-colors cursor-pointer ${
                  options.autoreboot
                    ? 'bg-amber-500/5 border-amber-500/30'
                    : 'bg-dark-950/40 border-dark-800/80 hover:bg-dark-850/70 hover:border-dark-700'
                }`}
              >
                <input
                  type="checkbox"
                  checked={options.autoreboot}
                  onChange={(e) => setOptions(prev => ({ ...prev, autoreboot: e.target.checked }))}
                  className="mt-0.5 w-4 h-4 rounded bg-dark-800 border-dark-700 text-amber-500 focus:ring-0 cursor-pointer"
                />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <RotateCcw className="w-3.5 h-3.5 text-amber-400 shrink-0" />
                    <span className="text-xs font-semibold text-zinc-100">Automatic restart and resume</span>
                  </div>
                  <p className="text-[11px] text-zinc-400 mt-1 leading-snug">
                    Use temporary automatic logon to restart and resume the update process without intervention.
                  </p>
                </div>
              </label>

              {/* Shutdown Option */}
              <label
                className={`flex items-start gap-3 p-3 rounded-lg border transition-colors cursor-pointer ${
                  options.shutdown
                    ? 'bg-rose-500/5 border-rose-500/30'
                    : 'bg-dark-950/40 border-dark-800/80 hover:bg-dark-850/70 hover:border-dark-700'
                }`}
              >
                <input
                  type="checkbox"
                  checked={options.shutdown}
                  onChange={(e) => setOptions(prev => ({ ...prev, shutdown: e.target.checked }))}
                  className="mt-0.5 w-4 h-4 rounded bg-dark-800 border-dark-700 text-rose-500 focus:ring-0 cursor-pointer"
                />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <Power className="w-3.5 h-3.5 text-rose-400 shrink-0" />
                    <span className="text-xs font-semibold text-zinc-100">Shut down when finished</span>
                  </div>
                  <p className="text-[11px] text-zinc-400 mt-1 leading-snug">
                    Shut down the computer after all updates and intermediate restarts are complete.
                  </p>
                </div>
              </label>
            </div>
          </div>
        </div>
      </main>

      {/* 4. Integrated Live Terminal Drawer */}
      {isTerminalOpen && (
        <div className="h-64 border-t border-dark-800 bg-dark-950 flex flex-col shrink-0">
          <div className="h-8 border-b border-dark-800 bg-dark-900 px-4 flex items-center justify-between text-xs">
            <div className="flex items-center gap-3 font-mono text-zinc-300">
              <div className="flex items-center gap-1.5">
                <Terminal className="w-3.5 h-3.5 text-accent-400" />
                <span className="font-semibold text-zinc-200">Installation console (DoUpdate.cmd)</span>
              </div>
              {isRunning && (
                <span className="flex items-center gap-1.5 text-[11px] text-amber-400 font-sans font-medium">
                  <Loader2 className="w-3.5 h-3.5 animate-spin text-amber-400" />
                  Installing...
                </span>
              )}
            </div>

            <div className="flex items-center gap-2">
              <button
                onClick={() => setAutoScroll(!autoScroll)}
                className={`text-[11px] px-2 py-0.5 rounded border transition-colors ${
                  autoScroll ? 'bg-dark-800 border-accent-600/40 text-accent-400 font-medium' : 'bg-dark-850 border-dark-800 text-zinc-400'
                }`}
              >
                Auto-scroll
              </button>
              <button
                onClick={() => navigator.clipboard.writeText(logs.map(l => `[${l.time}] [${l.level.toUpperCase()}] ${l.text}`).join('\n'))}
                className="text-zinc-400 hover:text-zinc-200 p-1 rounded hover:bg-dark-800 transition-colors"
                title="Copy logs"
              >
                <Copy className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={() => setLogs([])}
                className="text-zinc-400 hover:text-zinc-200 p-1 rounded hover:bg-dark-800 transition-colors"
                title="Clear console"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
              <button
                onClick={() => setIsTerminalOpen(false)}
                className="text-zinc-400 hover:text-zinc-200 p-1 rounded hover:bg-dark-800 transition-colors"
                title="Close console"
              >
                <ChevronDown className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          <div
            ref={logContainerRef}
            className="flex-1 p-3 overflow-y-auto font-mono text-xs space-y-1 bg-dark-950 text-zinc-300 select-text"
          >
            {logs.map((log) => {
              const levelStyles = {
                info: 'text-zinc-300',
                warn: 'text-amber-400',
                error: 'text-rose-400',
                success: 'text-emerald-400',
                start: 'text-accent-400 font-medium'
              };

              const badgeStyles = {
                info: 'bg-dark-850 text-zinc-400 border-dark-800',
                warn: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
                error: 'bg-rose-500/10 text-rose-400 border-rose-500/20',
                success: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
                start: 'bg-accent-600/15 text-accent-400 border-accent-600/30'
              };

              return (
                <div key={log.id} className="flex items-start gap-2 py-0.5 leading-relaxed font-mono text-[11px] hover:bg-dark-900/60 rounded px-1 transition-colors">
                  <span className="text-zinc-500 shrink-0 select-none">[{log.time}]</span>
                  <span className={`px-1.5 py-0.2 text-[9px] uppercase font-semibold rounded border shrink-0 ${badgeStyles[log.level]}`}>
                    {log.level}
                  </span>
                  <span className={`flex-1 break-all ${levelStyles[log.level]}`}>
                    {log.text}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* 5. Bottom Action Bar */}
      <footer className="h-16 border-t border-dark-800 bg-dark-900 px-5 flex items-center justify-between shrink-0">
        <div className="flex items-center gap-3 text-xs">
          <div className="px-3 py-1.5 rounded-md bg-dark-850 border border-dark-800 text-zinc-300 flex items-center gap-2">
            <span className="w-2 h-2 rounded-full bg-accent-500"></span>
            <span>Ready to update: <strong className="text-zinc-100">{specs.osName}</strong></span>
          </div>

          <button
            onClick={() => setIsTerminalOpen(!isTerminalOpen)}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-dark-850 hover:bg-dark-800 border border-dark-800 text-zinc-300 transition-colors"
          >
            <Terminal className="w-3.5 h-3.5 text-accent-400" />
            <span>Console</span>
            {isTerminalOpen ? <ChevronDown className="w-3.5 h-3.5" /> : <ChevronUp className="w-3.5 h-3.5" />}
          </button>
        </div>

        <div className="flex items-center gap-3">
          {isRunning ? (
            <button
              onClick={handleStop}
              className="flex items-center gap-2 px-5 py-2.5 rounded-md bg-rose-600 hover:bg-rose-700 text-white font-medium text-xs transition-colors"
            >
              <Square className="w-3.5 h-3.5 fill-current" />
              <span>Stop installation</span>
            </button>
          ) : (
            <button
              onClick={handleStart}
              className="flex items-center gap-2 px-5 py-2.5 rounded-md bg-accent-600 hover:bg-accent-700 text-white font-medium text-xs transition-colors active:bg-accent-800"
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              <span>Start installation</span>
            </button>
          )}
        </div>
      </footer>
    </div>
  );
}
