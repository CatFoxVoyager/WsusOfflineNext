import { useState, useEffect, useRef } from 'react';
import {
  Folder,
  Disc,
  Usb,
  Cpu,
  Layers,
  Globe,
  Terminal,
  Play,
  Square,
  Copy,
  Trash2,
  ChevronDown,
  ChevronUp,
  Server,
  Monitor,
  PackageCheck,
  Loader2
} from 'lucide-react';

import logo from './assets/logo.png';

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

interface WinBuild {
  key: string;
  label: string;
  sublabel: string;
  version: string;
  arch: 'x64' | 'x86';
  enabled: boolean;
  status: 'current' | 'supported' | 'esu' | 'eol' | 'insider';
}

export default function App() {
  const urlParams = typeof window !== 'undefined' ? new URLSearchParams(window.location.search) : null;
  const initialTab = (urlParams?.get('tab') as any) || 'win11';
  const initialConsole = urlParams?.get('console') === 'true';

  const [activeTab, setActiveTab] = useState<'win11' | 'win10' | 'office' | 'legacy' | 'options' | 'network'>(initialTab);
  const [isRunning, setIsRunning] = useState(false);
  const [isTerminalOpen, setIsTerminalOpen] = useState(initialConsole);
  const [logs, setLogs] = useState<LogEntry[]>([
    parseLogLine('[INIT] WSUS Offline Next initialized.'),
    parseLogLine('[READY] Select products and options, then click Start download.')
  ]);
  const [autoScroll, setAutoScroll] = useState(true);
  const logContainerRef = useRef<HTMLDivElement>(null);

  // Repository metadata
  const [catalogDate, setCatalogDate] = useState('15/10/2026');
  const [lastDownload, setLastDownload] = useState('21/10/2026 11:27');

  // Options
  const [options, setOptions] = useState({
    includedotnet: true,
    includewddefs: true,
    includeedge: true,
    includewebview2: true,
    seconly: false,
    verifydownloads: true,
    createIso: false,
    copyUsb: true,
    usbPath: 'E:\\Windows Update',
    usbClean: false,
    imageOnly: false,
    proxy: '',
    proxyPwd: '',
    wsusUrl: '',
    wsusOnly: false
  });

  // Windows 11 Builds
  const [win11Builds, setWin11Builds] = useState<WinBuild[]>([
    { key: '26300_x64', label: 'Windows 11 26H2', sublabel: 'Current Release', version: 'Build 26300', arch: 'x64', enabled: true, status: 'current' },
    { key: '26200_x64', label: 'Windows 11 25H2', sublabel: 'Active support', version: 'Build 26200', arch: 'x64', enabled: true, status: 'supported' },
    { key: '26100_x64', label: 'Windows 11 24H2', sublabel: 'LTSC 2024 / Active support', version: 'Build 26100', arch: 'x64', enabled: true, status: 'supported' },
    { key: '22631_x64', label: 'Windows 11 23H2', sublabel: 'Legacy entry', version: 'Build 22631', arch: 'x64', enabled: false, status: 'supported' },
    { key: '22621_x64', label: 'Windows 11 22H2', sublabel: 'Legacy entry', version: 'Build 22621', arch: 'x64', enabled: false, status: 'supported' },
    { key: '22000_x64', label: 'Windows 11 21H2', sublabel: 'End of support (EOL)', version: 'Build 22000', arch: 'x64', enabled: false, status: 'eol' },
  ]);

  // Windows 10 & Server Builds
  const [win10Builds, setWin10Builds] = useState<WinBuild[]>([
    { key: '20348_x64', label: 'Windows Server 2022', sublabel: 'LTSC 64-bit', version: 'Build 20348', arch: 'x64', enabled: true, status: 'supported' },
    { key: '19041_x64', label: 'Windows 10 (22H2/21H2)', sublabel: 'Client 64-bit (ESU)', version: 'Build 19041-19045', arch: 'x64', enabled: true, status: 'esu' },
    { key: '17763_x64', label: 'Windows Server 2019 / 1809', sublabel: 'LTSC 64-bit', version: 'Build 17763', arch: 'x64', enabled: true, status: 'supported' },
    { key: '14393_x64', label: 'Windows Server 2016 / 1607', sublabel: 'LTSC 64-bit', version: 'Build 14393', arch: 'x64', enabled: true, status: 'supported' },
    { key: '10240_x64', label: 'Windows 10 Enterprise 2015', sublabel: 'LTSB 64-bit', version: 'Build 10240', arch: 'x64', enabled: false, status: 'eol' },
    { key: '19041_x86', label: 'Windows 10 (22H2/21H2) x86', sublabel: 'Client 32-bit (ESU)', version: 'Build 19041-19045', arch: 'x86', enabled: true, status: 'esu' },
    { key: '17763_x86', label: 'Windows 10 (1809) x86', sublabel: 'Client 32-bit', version: 'Build 17763', arch: 'x86', enabled: false, status: 'eol' },
    { key: '14393_x86', label: 'Windows 10 (1607) x86', sublabel: 'Client 32-bit', version: 'Build 14393', arch: 'x86', enabled: false, status: 'eol' },
    { key: '10240_x86', label: 'Windows 10 (1507) x86', sublabel: 'Client 32-bit', version: 'Build 10240', arch: 'x86', enabled: false, status: 'eol' },
  ]);

  // Office Builds
  const [officeBuilds, setOfficeBuilds] = useState({
    o2k24_x64: false,
    o2k24_x86: false,
    o2k21_x64: false,
    o2k21_x86: false,
    o2k19_x64: false,
    o2k19_x86: false,
    o2k16_x64: false,
    o2k16_x86: false,
  });

  // Legacy Builds
  const [legacyBuilds, setLegacyBuilds] = useState<Record<string, boolean>>({
    w61_x64: false, // Win 7 x64 / Server 2008 R2
    w61_x86: false, // Win 7 x86
    w60_x64: false, // Win Vista x64 / Server 2008
    w60_x86: false, // Win Vista x86 / Server 2008
    w63_x64: false, // Server 2012 R2
    w63_x86: false, // Win 8.1
    w62_x64: false, // Server 2012
    wxp_x86: false  // Win XP / Server 2003
  });

  // Native message sender
  const sendNative = (action: string, payload: any = {}) => {
    if (typeof window !== 'undefined' && (window as any).chrome?.webview?.postMessage) {
      (window as any).chrome.webview.postMessage(JSON.stringify({ action, payload }));
    } else {
      console.log('[NativeBridge Mock]', action, payload);
    }
  };

  // Listen to C# messages
  useEffect(() => {
    const handleNativeMessage = (event: any) => {
      try {
        const data = typeof event.data === 'string' ? JSON.parse(event.data) : event.data;
        if (data.type === 'log') {
          setLogs(prev => [...prev, parseLogLine(data.text)]);
        } else if (data.type === 'state') {
          if (data.win11) {
            setWin11Builds(prev => prev.map(b => ({ ...b, enabled: data.win11[b.key] ?? b.enabled })));
          }
          if (data.win10) {
            setWin10Builds(prev => prev.map(b => ({ ...b, enabled: data.win10[b.key] ?? b.enabled })));
          }
          if (data.options) {
            setOptions(prev => ({ ...prev, ...data.options }));
          }
          if (data.office) {
            setOfficeBuilds(prev => ({ ...prev, ...data.office }));
          }
          if (data.legacy) {
            setLegacyBuilds(prev => ({ ...prev, ...data.legacy }));
          }
          if (data.catalogDate) setCatalogDate(data.catalogDate);
          if (data.lastDownload) setLastDownload(data.lastDownload);
        } else if (data.type === 'status') {
          setIsRunning(data.running);
        } else if (data.type === 'folder_selected') {
          setOptions(prev => ({ ...prev, usbPath: data.path }));
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

  // Auto scroll logs
  useEffect(() => {
    if (autoScroll && logContainerRef.current) {
      logContainerRef.current.scrollTop = logContainerRef.current.scrollHeight;
    }
  }, [logs, autoScroll]);

  // Selected count calculation
  const totalSelectedCount =
    win11Builds.filter(b => b.enabled).length +
    win10Builds.filter(b => b.enabled).length +
    Object.values(officeBuilds).filter(Boolean).length +
    Object.values(legacyBuilds).filter(Boolean).length;

  const handleStart = () => {
    setIsRunning(true);
    setIsTerminalOpen(true);
    setLogs(prev => [...prev, parseLogLine(`[START] Starting the download pipeline (${totalSelectedCount} product(s) selected)...`)]);

    sendNative('start', {
      win11: win11Builds.reduce((acc, b) => ({ ...acc, [b.key]: b.enabled }), {}),
      win10: win10Builds.reduce((acc, b) => ({ ...acc, [b.key]: b.enabled }), {}),
      office: officeBuilds,
      legacy: legacyBuilds,
      options
    });
  };

  const handleStop = () => {
    sendNative('cancel', {});
    setIsRunning(false);
    setLogs(prev => [...prev, parseLogLine('[WARN] Download cancellation requested.')]);
  };

  const browseFolder = () => {
    sendNative('browse_folder', {});
  };

  const renderStatusBadge = (status: 'current' | 'supported' | 'esu' | 'eol' | 'insider') => {
    switch (status) {
      case 'current':
        return (
          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-semibold bg-cyan-500/15 text-cyan-300 border border-cyan-500/30">
            Current Release
          </span>
        );
      case 'supported':
        return (
          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
            Listed
          </span>
        );
      case 'esu':
        return (
          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium bg-amber-500/10 text-amber-400 border border-amber-500/20">
            ESU
          </span>
        );
      case 'insider':
        return (
          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium bg-purple-500/10 text-purple-400 border border-purple-500/20">
            Canary / Dev
          </span>
        );
      case 'eol':
      default:
        return (
          <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium bg-zinc-800 text-zinc-500 border border-dark-700">
            End of support
          </span>
        );
    }
  };

  return (
    <div className="flex flex-col h-screen w-screen bg-dark-950 text-zinc-100 font-sans select-none overflow-hidden">
      {/* 1. Header Bar */}
      <header className="h-14 border-b border-dark-800 bg-dark-900 px-5 flex items-center justify-between shrink-0">
        <div className="flex items-center gap-3">
          <img src={logo} alt="WSUS Offline Next" className="w-9 h-9" draggable={false} />
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-sm font-semibold text-zinc-100 tracking-tight">WSUS Offline Next</h1>
              <span className="text-[11px] px-2 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700 font-mono font-medium">
                v2026.10.1 • Local repository
              </span>
            </div>
            <p className="text-[11px] text-zinc-400">Offline update repository for Windows and Office</p>
          </div>
        </div>

        {/* Repository Metadata */}
        <div className="flex items-center gap-3 text-xs">
          <div className="flex items-center gap-2 px-3 py-1.5 rounded-md bg-dark-850 border border-dark-800 text-zinc-300">
            <Layers className="w-3.5 h-3.5 text-zinc-400" />
            <span>Catalog: <span className="font-mono text-zinc-100">{catalogDate}</span></span>
            <span className="text-zinc-600">|</span>
            <span>Last run: <span className="font-mono text-zinc-100">{lastDownload}</span></span>
          </div>

          <button
            onClick={() => sendNative('open_folder', { path: 'client' })}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-md bg-dark-850 hover:bg-dark-800 border border-dark-800 text-zinc-300 transition-colors text-xs"
            title="Open the client update directory"
          >
            <Folder className="w-3.5 h-3.5" />
            <span>Client folder</span>
          </button>
        </div>
      </header>

      {/* 2. Navigation Tabs */}
      <nav className="h-11 border-b border-dark-800 bg-dark-900/40 px-5 flex items-center gap-2 shrink-0">
        {[
          { id: 'win11', label: 'Windows 11', icon: Monitor, count: win11Builds.filter(b => b.enabled).length },
          { id: 'win10', label: 'Windows 10 & Server', icon: Server, count: win10Builds.filter(b => b.enabled).length },
          { id: 'office', label: 'Microsoft Office', icon: PackageCheck, count: Object.values(officeBuilds).filter(Boolean).length },
          { id: 'legacy', label: 'Legacy Windows', icon: Cpu, count: Object.values(legacyBuilds).filter(Boolean).length },
          { id: 'options', label: 'Options & Media', icon: Disc, badge: options.copyUsb ? 'USB' : (options.createIso ? 'ISO' : undefined) },
          { id: 'network', label: 'Network & Proxy', icon: Globe }
        ].map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id as any)}
              className={`flex items-center gap-2 px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
                isActive
                  ? 'bg-dark-800 text-accent-400 border border-accent-600/40'
                  : 'text-zinc-400 hover:text-zinc-200 hover:bg-dark-850 border border-transparent'
              }`}
            >
              <Icon className="w-3.5 h-3.5" />
              <span>{tab.label}</span>
              {typeof tab.count === 'number' && tab.count > 0 && (
                <span className="w-4 h-4 rounded-full bg-accent-600 text-white font-medium text-[10px] flex items-center justify-center">
                  {tab.count}
                </span>
              )}
              {tab.badge && (
                <span className="px-1.5 py-0.2 rounded text-[10px] bg-dark-800 text-zinc-300 border border-dark-700">
                  {tab.badge}
                </span>
              )}
            </button>
          );
        })}
      </nav>

      {/* 3. Main Content Area */}
      <main className="flex-1 overflow-y-auto p-5 bg-dark-950/60">
        {/* TAB 1: WINDOWS 11 */}
        {activeTab === 'win11' && (
          <div className="space-y-4 max-w-5xl mx-auto">
            {/* Toolbar */}
            <div className="flex items-center justify-between pb-3 border-b border-dark-800">
              <div>
                <h2 className="text-sm font-semibold text-zinc-100">Windows 11 updates (64-bit)</h2>
                <p className="text-xs text-zinc-400">Download cumulative updates (LCU), servicing stack updates (SSU), and catalog updates.</p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setWin11Builds(prev => prev.map(b => ({ ...b, enabled: b.status === 'supported' || b.status === 'current' })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Supported versions
                </button>
                <button
                  onClick={() => setWin11Builds(prev => prev.map(b => ({ ...b, enabled: true })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Select all
                </button>
                <button
                  onClick={() => setWin11Builds(prev => prev.map(b => ({ ...b, enabled: false })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-400 border border-dark-800 transition-colors"
                >
                  Clear selection
                </button>
              </div>
            </div>

            {/* Dense Tabular List */}
            <div className="border border-dark-800 rounded-lg overflow-hidden bg-dark-900">
              <div className="flex items-center px-4 py-2 bg-dark-850/80 border-b border-dark-800 text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">
                <div className="w-8 text-center"></div>
                <div className="flex-1">Edition / Version</div>
                <div className="w-20 text-center">Arch</div>
                <div className="w-28 text-center">Build</div>
                <div className="w-36 text-center">Repository status</div>
                <div className="w-28 text-right font-mono">Target</div>
              </div>

              <div className="divide-y divide-dark-800/60">
                {win11Builds.map((b) => (
                  <div
                    key={b.key}
                    onClick={() => setWin11Builds(prev => prev.map(x => x.key === b.key ? { ...x, enabled: !x.enabled } : x))}
                    className={`flex items-center px-4 py-2.5 hover:bg-dark-850/70 transition-colors cursor-pointer ${
                      b.enabled ? 'bg-accent-600/5' : ''
                    }`}
                  >
                    <div className="w-8 flex items-center justify-center">
                      <input
                        type="checkbox"
                        checked={b.enabled}
                        onChange={() => {}}
                        className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer pointer-events-none"
                      />
                    </div>
                    <div className="flex-1 min-w-0 pr-3">
                      <span className="text-xs font-semibold text-zinc-100">{b.label}</span>
                      <span className="text-[11px] text-zinc-400 ml-2 hidden sm:inline">{b.sublabel}</span>
                    </div>
                    <div className="w-20 text-center">
                      <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700">
                        {b.arch}
                      </span>
                    </div>
                    <div className="w-28 text-center text-xs font-mono text-zinc-300">
                      {b.version}
                    </div>
                    <div className="w-36 text-center">
                      {renderStatusBadge(b.status)}
                    </div>
                    <div className="w-28 text-right text-[11px] font-mono text-zinc-500">
                      w100-x64 glb
                    </div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* TAB 2: WINDOWS 10 & SERVERS */}
        {activeTab === 'win10' && (
          <div className="space-y-6 max-w-5xl mx-auto">
            {/* Toolbar */}
            <div className="flex items-center justify-between pb-3 border-b border-dark-800">
              <div>
                <h2 className="text-sm font-semibold text-zinc-100">Windows 10 & Windows Server</h2>
                <p className="text-xs text-zinc-400">Prepare updates for Windows 10 x64/x86 and Windows Server 2016, 2019, and 2022.</p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setWin10Builds(prev => prev.map(b => ({
                    ...b,
                    enabled: b.arch === 'x64' && (b.key.includes('20348') || b.key.includes('17763') || b.key.includes('14393'))
                  })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Serveurs uniquement
                </button>
                <button
                  onClick={() => setWin10Builds(prev => prev.map(b => ({
                    ...b,
                    enabled: b.status === 'supported' || b.status === 'esu'
                  })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Supported & ESU
                </button>
                <button
                  onClick={() => setWin10Builds(prev => prev.map(b => ({ ...b, enabled: true })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Select all
                </button>
                <button
                  onClick={() => setWin10Builds(prev => prev.map(b => ({ ...b, enabled: false })))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-400 border border-dark-800 transition-colors"
                >
                  Clear selection
                </button>
              </div>
            </div>

            {/* Section 1: 64-bit Builds & Windows Server */}
            <div className="space-y-2">
              <h3 className="text-xs font-semibold text-zinc-300 uppercase tracking-wide flex items-center gap-2">
                <Server className="w-3.5 h-3.5 text-accent-400" />
                <span>Windows Server & 64-bit clients (x64)</span>
              </h3>

              <div className="border border-dark-800 rounded-lg overflow-hidden bg-dark-900">
                <div className="flex items-center px-4 py-2 bg-dark-850/80 border-b border-dark-800 text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">
                  <div className="w-8 text-center"></div>
                  <div className="flex-1">Edition / Version</div>
                  <div className="w-20 text-center">Arch</div>
                  <div className="w-32 text-center">Build</div>
                  <div className="w-36 text-center">Repository status</div>
                  <div className="w-28 text-right font-mono">Target</div>
                </div>

                <div className="divide-y divide-dark-800/60">
                  {win10Builds.filter(b => b.arch === 'x64').map((b) => (
                    <div
                      key={b.key}
                      onClick={() => setWin10Builds(prev => prev.map(x => x.key === b.key ? { ...x, enabled: !x.enabled } : x))}
                      className={`flex items-center px-4 py-2.5 hover:bg-dark-850/70 transition-colors cursor-pointer ${
                        b.enabled ? 'bg-accent-600/5' : ''
                      }`}
                    >
                      <div className="w-8 flex items-center justify-center">
                        <input
                          type="checkbox"
                          checked={b.enabled}
                          onChange={() => {}}
                          className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer pointer-events-none"
                        />
                      </div>
                      <div className="flex-1 min-w-0 pr-3">
                        <span className="text-xs font-semibold text-zinc-100">{b.label}</span>
                        <span className="text-[11px] text-zinc-400 ml-2 hidden sm:inline">{b.sublabel}</span>
                      </div>
                      <div className="w-20 text-center">
                        <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700">
                          x64
                        </span>
                      </div>
                      <div className="w-32 text-center text-xs font-mono text-zinc-300">
                        {b.version}
                      </div>
                      <div className="w-36 text-center">
                        {renderStatusBadge(b.status)}
                      </div>
                      <div className="w-28 text-right text-[11px] font-mono text-zinc-500">
                        w100-x64
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            {/* Section 2: 32-bit (x86) Legacy Client Builds */}
            <div className="space-y-2">
              <h3 className="text-xs font-semibold text-zinc-300 uppercase tracking-wide flex items-center gap-2">
                <Monitor className="w-3.5 h-3.5 text-zinc-400" />
                <span>Windows 10 32-bit clients (x86)</span>
              </h3>

              <div className="border border-dark-800 rounded-lg overflow-hidden bg-dark-900">
                <div className="flex items-center px-4 py-2 bg-dark-850/80 border-b border-dark-800 text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">
                  <div className="w-8 text-center"></div>
                  <div className="flex-1">Edition / Version</div>
                  <div className="w-20 text-center">Arch</div>
                  <div className="w-32 text-center">Build</div>
                  <div className="w-36 text-center">Repository status</div>
                  <div className="w-28 text-right font-mono">Target</div>
                </div>

                <div className="divide-y divide-dark-800/60">
                  {win10Builds.filter(b => b.arch === 'x86').map((b) => (
                    <div
                      key={b.key}
                      onClick={() => setWin10Builds(prev => prev.map(x => x.key === b.key ? { ...x, enabled: !x.enabled } : x))}
                      className={`flex items-center px-4 py-2.5 hover:bg-dark-850/70 transition-colors cursor-pointer ${
                        b.enabled ? 'bg-accent-600/5' : ''
                      }`}
                    >
                      <div className="w-8 flex items-center justify-center">
                        <input
                          type="checkbox"
                          checked={b.enabled}
                          onChange={() => {}}
                          className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer pointer-events-none"
                        />
                      </div>
                      <div className="flex-1 min-w-0 pr-3">
                        <span className="text-xs font-semibold text-zinc-100">{b.label}</span>
                        <span className="text-[11px] text-zinc-400 ml-2 hidden sm:inline">{b.sublabel}</span>
                      </div>
                      <div className="w-20 text-center">
                        <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700">
                          x86
                        </span>
                      </div>
                      <div className="w-32 text-center text-xs font-mono text-zinc-300">
                        {b.version}
                      </div>
                      <div className="w-36 text-center">
                        {renderStatusBadge(b.status)}
                      </div>
                      <div className="w-28 text-right text-[11px] font-mono text-zinc-500">
                        w100-glb
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 3: OFFICE */}
        {activeTab === 'office' && (
          <div className="space-y-4 max-w-5xl mx-auto">
            {/* Toolbar */}
            <div className="flex items-center justify-between pb-3 border-b border-dark-800">
              <div>
                <h2 className="text-sm font-semibold text-zinc-100">Microsoft Office (ODT Click-to-Run & MSI)</h2>
                <p className="text-xs text-zinc-400">Prepare Office update packages and Click-to-Run installation media.</p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setOfficeBuilds(prev => ({ ...prev, o2k24_x64: true, o2k21_x64: true }))}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  LTSC 64-bit (2024 & 2021)
                </button>
                <button
                  onClick={() => setOfficeBuilds({
                    o2k24_x64: true,
                    o2k24_x86: true,
                    o2k21_x64: true,
                    o2k21_x86: true,
                    o2k19_x64: true,
                    o2k19_x86: true,
                    o2k16_x64: true,
                    o2k16_x86: true
                  })}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Select all
                </button>
                <button
                  onClick={() => setOfficeBuilds({
                    o2k24_x64: false,
                    o2k24_x86: false,
                    o2k21_x64: false,
                    o2k21_x86: false,
                    o2k19_x64: false,
                    o2k19_x86: false,
                    o2k16_x64: false,
                    o2k16_x86: false
                  })}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-400 border border-dark-800 transition-colors"
                >
                  Clear selection
                </button>
              </div>
            </div>

            {/* Matrix Table */}
            <div className="border border-dark-800 rounded-lg overflow-hidden bg-dark-900">
              <div className="flex items-center px-4 py-2 bg-dark-850/80 border-b border-dark-800 text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">
                <div className="flex-1">Office suite</div>
                <div className="w-44 text-left">Technology</div>
                <div className="w-36 text-center">Channel / Status</div>
                <div className="w-28 text-center">64-bit</div>
                <div className="w-28 text-center">32-bit</div>
              </div>

              <div className="divide-y divide-dark-800/60">
                {[
                  {
                    id64: 'o2k24_x64',
                    id86: 'o2k24_x86',
                    name: 'Microsoft Office LTSC 2024',
                    tech: 'ODT Click-to-Run (C2R)',
                    channel: 'LTSC 2024 channel',
                    status: 'supported'
                  },
                  {
                    id64: 'o2k21_x64',
                    id86: 'o2k21_x86',
                    name: 'Microsoft Office LTSC 2021',
                    tech: 'ODT Click-to-Run (C2R)',
                    channel: 'LTSC 2021 channel',
                    status: 'supported'
                  },
                  {
                    id64: 'o2k19_x64',
                    id86: 'o2k19_x86',
                    name: 'Microsoft Office 2019',
                    tech: 'ODT Click-to-Run (C2R)',
                    channel: 'Standard channel',
                    status: 'supported'
                  },
                  {
                    id64: 'o2k16_x64',
                    id86: 'o2k16_x86',
                    name: 'Microsoft Office 2016 (MSI)',
                    tech: 'Windows Installer (MSI)',
                    channel: 'Security updates',
                    status: 'esu'
                  }
                ].map(row => {
                  const is64 = (officeBuilds as any)[row.id64];
                  const is86 = (officeBuilds as any)[row.id86];
                  return (
                    <div
                      key={row.name}
                      className={`flex items-center px-4 py-3 hover:bg-dark-850/60 transition-colors ${
                        is64 || is86 ? 'bg-accent-600/5' : ''
                      }`}
                    >
                      <div className="flex-1 min-w-0 pr-3">
                        <span className="text-xs font-semibold text-zinc-100">{row.name}</span>
                      </div>
                      <div className="w-44 text-xs text-zinc-400">
                        {row.tech}
                      </div>
                      <div className="w-36 text-center">
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium bg-dark-800 text-zinc-300 border border-dark-700">
                          {row.channel}
                        </span>
                      </div>
                      <div className="w-28 flex items-center justify-center">
                        <label className="flex items-center gap-1.5 cursor-pointer text-xs font-mono text-zinc-200">
                          <input
                            type="checkbox"
                            checked={is64}
                            onChange={(e) => setOfficeBuilds(prev => ({ ...prev, [row.id64]: e.target.checked }))}
                            className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer"
                          />
                          <span>x64</span>
                        </label>
                      </div>
                      <div className="w-28 flex items-center justify-center">
                        <label className="flex items-center gap-1.5 cursor-pointer text-xs font-mono text-zinc-200">
                          <input
                            type="checkbox"
                            checked={is86}
                            onChange={(e) => setOfficeBuilds(prev => ({ ...prev, [row.id86]: e.target.checked }))}
                            className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer"
                          />
                          <span>x86</span>
                        </label>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        )}

        {/* TAB 4: LEGACY */}
        {activeTab === 'legacy' && (
          <div className="space-y-4 max-w-5xl mx-auto">
            {/* Toolbar */}
            <div className="flex items-center justify-between pb-3 border-b border-dark-800">
              <div>
                <h2 className="text-sm font-semibold text-zinc-100">Legacy operating systems</h2>
                <p className="text-xs text-zinc-400">Legacy product entries. Package availability depends on the update source and existing media.</p>
              </div>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setLegacyBuilds({
                    w61_x64: true,
                    w61_x86: true,
                    w60_x64: true,
                    w60_x86: true,
                    w63_x64: true,
                    w63_x86: true,
                    w62_x64: true,
                    wxp_x86: true
                  })}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-200 border border-dark-800 transition-colors"
                >
                  Select all
                </button>
                <button
                  onClick={() => setLegacyBuilds({
                    w61_x64: false,
                    w61_x86: false,
                    w60_x64: false,
                    w60_x86: false,
                    w63_x64: false,
                    w63_x86: false,
                    w62_x64: false,
                    wxp_x86: false
                  })}
                  className="px-2.5 py-1 text-xs font-medium rounded bg-dark-850 hover:bg-dark-800 text-zinc-400 border border-dark-800 transition-colors"
                >
                  Clear selection
                </button>
              </div>
            </div>

            {/* Table */}
            <div className="border border-dark-800 rounded-lg overflow-hidden bg-dark-900">
              <div className="flex items-center px-4 py-2 bg-dark-850/80 border-b border-dark-800 text-[11px] font-semibold text-zinc-400 uppercase tracking-wider">
                <div className="w-8 text-center"></div>
                <div className="flex-1">Operating system</div>
                <div className="w-24 text-center">Architecture</div>
                <div className="w-36 text-center">Status</div>
                <div className="w-32 text-center">End of support</div>
                <div className="w-28 text-right font-mono">Target</div>
              </div>

              <div className="divide-y divide-dark-800/60">
                {[
                  { id: 'w61_x64', name: 'Windows 7 SP1 / Windows Server 2008 R2', arch: 'x64', eol: 'January 2020 / ESU 2023', target: 'w61-x64' },
                  { id: 'w61_x86', name: 'Windows 7 SP1 Client', arch: 'x86', eol: 'January 2020 / ESU 2023', target: 'w61' },
                  { id: 'w60_x64', name: 'Windows Vista SP2 / Windows Server 2008', arch: 'x64', eol: 'April 2017 / January 2020', target: 'w60-x64' },
                  { id: 'w60_x86', name: 'Windows Vista SP2 / Windows Server 2008', arch: 'x86', eol: 'April 2017 / January 2020', target: 'w60' },
                  { id: 'w63_x64', name: 'Windows Server 2012 R2', arch: 'x64', eol: 'October 2023', target: 'w63-x64' },
                  { id: 'w63_x86', name: 'Windows 8.1', arch: 'x86 / x64', eol: 'January 2023', target: 'w63' },
                  { id: 'w62_x64', name: 'Windows Server 2012', arch: 'x64', eol: 'October 2023', target: 'w62-x64' },
                  { id: 'wxp_x86', name: 'Windows XP SP3 / Windows Server 2003', arch: 'x86', eol: 'April 2014 / July 2015', target: 'wxp' }
                ].map(item => {
                  const isChecked = (legacyBuilds as any)[item.id];
                  return (
                    <div
                      key={item.id}
                      onClick={() => setLegacyBuilds(prev => ({ ...prev, [item.id]: !isChecked }))}
                      className={`flex items-center px-4 py-2.5 hover:bg-dark-850/70 transition-colors cursor-pointer ${
                        isChecked ? 'bg-accent-600/5' : ''
                      }`}
                    >
                      <div className="w-8 flex items-center justify-center">
                        <input
                          type="checkbox"
                          checked={isChecked}
                          onChange={() => {}}
                          className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer pointer-events-none"
                        />
                      </div>
                      <div className="flex-1 min-w-0 pr-3">
                        <span className="text-xs font-semibold text-zinc-100">{item.name}</span>
                      </div>
                      <div className="w-24 text-center">
                        <span className="text-[10px] font-mono px-1.5 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700">
                          {item.arch}
                        </span>
                      </div>
                      <div className="w-36 text-center">
                        <span className="inline-flex items-center px-2 py-0.5 rounded text-[10px] font-medium bg-zinc-800 text-zinc-500 border border-dark-700">
                          Legacy / EOL
                        </span>
                      </div>
                      <div className="w-32 text-center text-xs text-zinc-400">
                        {item.eol}
                      </div>
                      <div className="w-28 text-right text-[11px] font-mono text-zinc-500">
                        {item.target}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        )}

        {/* TAB 5: OPTIONS & MEDIA */}
        {activeTab === 'options' && (
          <div className="space-y-6 max-w-5xl mx-auto">
            {/* Additional Components */}
            <div>
              <div className="pb-2 border-b border-dark-800 mb-3">
                <h2 className="text-sm font-semibold text-zinc-100">Additional components</h2>
                <p className="text-xs text-zinc-400">Include runtimes and optional components for your target computers.</p>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 gap-2.5">
                {[
                  { key: 'includedotnet', label: 'Visual C++ & .NET runtimes', desc: 'Visual C++ redistributables, .NET Framework, and modern .NET runtimes' },
                  { key: 'includewddefs', label: 'Microsoft Defender definitions', desc: 'Download antivirus and antimalware definitions' },
                  { key: 'includeedge', label: 'Microsoft Edge Chromium', desc: 'Microsoft Edge Enterprise offline installer' },
                  { key: 'includewebview2', label: 'Edge WebView2 Runtime', desc: 'Runtime required by applications that use WebView2' },
                  { key: 'verifydownloads', label: 'Verify downloaded files', desc: 'Check package integrity against the hash database' },
                  { key: 'seconly', label: 'Security-only updates', desc: 'Request security-only updates where available' }
                ].map(opt => (
                  <label
                    key={opt.key}
                    className="p-3 rounded-lg bg-dark-900 border border-dark-800 flex items-start gap-3 cursor-pointer hover:bg-dark-850/60 hover:border-dark-700 transition-colors"
                  >
                    <input
                      type="checkbox"
                      checked={(options as any)[opt.key]}
                      onChange={(e) => setOptions(prev => ({ ...prev, [opt.key]: e.target.checked }))}
                      className="mt-0.5 w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0"
                    />
                    <div className="min-w-0 flex-1">
                      <span className="text-xs font-semibold text-zinc-100">{opt.label}</span>
                      <p className="text-[11px] text-zinc-400 mt-0.5 leading-snug">{opt.desc}</p>
                    </div>
                  </label>
                ))}
              </div>
            </div>

            {/* Target Media & Export */}
            <div>
              <div className="pb-2 border-b border-dark-800 mb-3">
                <h2 className="text-sm font-semibold text-zinc-100">Update media & Export</h2>
                <p className="text-xs text-zinc-400">Create ISO images and prepare update media for offline computers.</p>
              </div>

              <div className="space-y-3">
                {/* ISO Image Option */}
                <label className="p-3.5 rounded-lg bg-dark-900 border border-dark-800 flex items-center justify-between cursor-pointer hover:bg-dark-850/60 hover:border-dark-700 transition-colors">
                  <div className="flex items-center gap-3">
                    <div className="w-8 h-8 rounded-md bg-dark-850 border border-dark-800 flex items-center justify-center text-accent-400">
                      <Disc className="w-4 h-4" />
                    </div>
                    <div>
                      <span className="text-xs font-semibold text-zinc-100">Create ISO images</span>
                      <p className="text-[11px] text-zinc-400">Write disc image files to the <code>iso/</code> subfolder</p>
                    </div>
                  </div>
                  <input
                    type="checkbox"
                    checked={options.createIso}
                    onChange={(e) => setOptions(prev => ({ ...prev, createIso: e.target.checked }))}
                    className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer"
                  />
                </label>

                {/* USB / Target Folder Option */}
                <div className="p-3.5 rounded-lg bg-dark-900 border border-dark-800 space-y-3">
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-3">
                      <div className="w-8 h-8 rounded-md bg-dark-850 border border-dark-800 flex items-center justify-center text-accent-400">
                        <Usb className="w-4 h-4" />
                      </div>
                      <div>
                        <span className="text-xs font-semibold text-zinc-100">Copy updates to a USB drive or folder</span>
                        <p className="text-[11px] text-zinc-400">Prepare the client directory for computers without Internet access</p>
                      </div>
                    </div>
                    <input
                      type="checkbox"
                      checked={options.copyUsb}
                      aria-label="Copy updates to a USB drive or folder"
                      onChange={(e) => setOptions(prev => ({ ...prev, copyUsb: e.target.checked }))}
                      className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0 cursor-pointer"
                    />
                  </div>

                  {options.copyUsb && (
                    <div className="pt-3 border-t border-dark-800 flex items-center gap-2">
                      <div className="relative flex-1">
                        <input
                          type="text"
                          value={options.usbPath}
                          onChange={(e) => setOptions(prev => ({ ...prev, usbPath: e.target.value }))}
                          className="w-full bg-dark-950 border border-dark-700 rounded-md px-3 py-1.5 text-xs font-mono text-zinc-200 focus:outline-none focus:border-accent-500 placeholder-zinc-600"
                          placeholder="e.g. E:\Windows Update or \\server\updates"
                        />
                      </div>
                      <button
                        onClick={browseFolder}
                        className="px-3 py-1.5 rounded-md bg-dark-850 hover:bg-dark-800 text-zinc-200 text-xs font-medium border border-dark-700 flex items-center gap-1.5 transition-colors"
                      >
                        <Folder className="w-3.5 h-3.5" />
                        <span>Browse...</span>
                      </button>
                    </div>
                  )}
                </div>
              </div>
            </div>
          </div>
        )}

        {/* TAB 6: NETWORK */}
        {activeTab === 'network' && (
          <div className="space-y-4 max-w-3xl mx-auto">
            <div className="pb-2 border-b border-dark-800">
              <h2 className="text-sm font-semibold text-zinc-100">Network, proxy & local WSUS server</h2>
              <p className="text-xs text-zinc-400">Configure a corporate proxy or an internal WSUS update source.</p>
            </div>

            <div className="space-y-4 bg-dark-900 border border-dark-800 p-5 rounded-lg">
              <div>
                <label className="block text-xs font-medium text-zinc-300 mb-1.5">HTTP / HTTPS proxy server</label>
                <input
                  type="text"
                  value={options.proxy}
                  onChange={(e) => setOptions(prev => ({ ...prev, proxy: e.target.value }))}
                  placeholder="e.g. http://proxy.corporate.lan:8080"
                  className="w-full bg-dark-950 border border-dark-700 rounded-md px-3 py-1.5 text-xs font-mono text-zinc-200 focus:outline-none focus:border-accent-500 placeholder-zinc-600"
                />
              </div>

              <div>
                <label className="block text-xs font-medium text-zinc-300 mb-1.5">Local WSUS server URL (optional)</label>
                <input
                  type="text"
                  value={options.wsusUrl}
                  onChange={(e) => setOptions(prev => ({ ...prev, wsusUrl: e.target.value }))}
                  placeholder="e.g. http://wsus01.lan:8530"
                  className="w-full bg-dark-950 border border-dark-700 rounded-md px-3 py-1.5 text-xs font-mono text-zinc-200 focus:outline-none focus:border-accent-500 placeholder-zinc-600"
                />
              </div>

              <label className="flex items-center gap-2.5 cursor-pointer text-xs text-zinc-300 pt-1">
                <input
                  type="checkbox"
                  checked={options.wsusOnly}
                  onChange={(e) => setOptions(prev => ({ ...prev, wsusOnly: e.target.checked }))}
                  className="w-4 h-4 rounded bg-dark-800 border-dark-700 text-accent-600 focus:ring-0"
                />
                <span>Download only from this WSUS server (do not contact Microsoft Update)</span>
              </label>
            </div>
          </div>
        )}
      </main>

      {/* 4. Integrated Live Terminal Drawer */}
      {isTerminalOpen && (
        <div className="h-64 border-t border-dark-800 bg-dark-950 flex flex-col shrink-0">
          <div className="h-8 border-b border-dark-800 bg-dark-900 px-4 flex items-center justify-between text-xs">
            <div className="flex items-center gap-3 font-mono text-zinc-300">
              <div className="flex items-center gap-1.5">
                <Terminal className="w-3.5 h-3.5 text-accent-400" />
                <span className="font-semibold text-zinc-200">Download console</span>
              </div>
              {isRunning ? (
                <span className="flex items-center gap-1.5 text-[11px] text-amber-400 font-sans font-medium">
                  <Loader2 className="w-3.5 h-3.5 animate-spin text-amber-400" />
                  Downloading...
                </span>
              ) : (
                <span className="text-[11px] text-zinc-500 font-sans">Ready</span>
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
                title="Hide console"
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
            <span><strong className="text-zinc-100">{totalSelectedCount}</strong> product(s) selected</span>
          </div>

          {options.copyUsb && (
            <span className="text-zinc-400 text-xs hidden sm:inline">
              Target: <span className="font-mono text-zinc-200">{options.usbPath}</span>
            </span>
          )}

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
              <span>Stop download</span>
            </button>
          ) : (
            <button
              onClick={handleStart}
              disabled={totalSelectedCount === 0}
              className={`flex items-center gap-2 px-5 py-2.5 rounded-md font-medium text-xs transition-colors ${
                totalSelectedCount > 0
                  ? 'bg-accent-600 hover:bg-accent-700 text-white active:bg-accent-800'
                  : 'bg-dark-800 text-zinc-500 cursor-not-allowed border border-dark-700'
              }`}
            >
              <Play className="w-3.5 h-3.5 fill-current" />
              <span>Start download</span>
            </button>
          )}
        </div>
      </footer>
    </div>
  );
}
