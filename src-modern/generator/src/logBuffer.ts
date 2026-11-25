// Pure console-log buffer for the generator download console (issue #47).
//
// The C# host forwards one 'log' message per child-process output line; a
// downloading wget emits a dot-progress line per ~50 KB, so tens of
// thousands of lines can arrive in a burst. App.tsx used to append every
// line to an unbounded array and render every entry as a DOM row, which
// saturated the WebView2 renderer mid-download. This module owns the
// bounded shape: a rolling cap keeping the newest entries, coalescing of
// consecutive wget dot-progress lines into one row carrying an (xN) repeat
// counter, and verbatim append for everything else (ERROR/WARN are never
// merged). Extracted as a pure module with no DOM and no side effects so
// the ci/tests battery can compile it with the vendored rolldown and drive
// it from node, outside the browser.
export const MAX_LOG_ENTRIES = 1000;

export interface LogEntry {
  id: string;
  time: string;
  level: 'info' | 'warn' | 'error' | 'success' | 'start';
  text: string;
  repeatCount: number;
}

export const parseLogLine = (raw: string): LogEntry => {
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
    text: text.replace(/^\[(INFO|WARN|ERROR|ERR|SUCCESS|START)\]\s*/i, ''),
    repeatCount: 1
  };
};

// Progress-line shapes that should coalesce into a single (xN) row:
// 1. wget dot-progress, e.g. " 4600K .......... 23% 1.16M 37s" or when
//    Content-Length is unspecified: "    50K .......... ..........  103K".
//    The final wget summary line ("100%  107M=2m1s", no dots) and "saved [...]"
//    are not progress-shaped and render as their own rows.
// 2. mkisofs ISO-build progress, e.g. " 57.53% done, estimate finish Tue Nov 24 23:24:10 2026".
// NOTE: the battery's coalesce-bite control anchors on this arrow's
// boolean return-type annotation - the module's only boolean arrow.
export const isProgressLine = (text: string): boolean =>
  /^\s*\d+(\.\d+)?[KMG]?\s+\.{2,}/.test(text) ||
  /^\s*\d+(\.\d+)?%\s+done,\s+estimate finish\b/i.test(text);

export const isWgetProgressLine = isProgressLine;

// Pure reducer: fold a batch of raw console lines into the bounded log
// state. Returns a new array; the caller's array is never mutated.
//
// 1. Consecutive progress lines coalesce: when the batch's entry is
//    info-level and progress-shaped AND the current last entry is too, the
//    last entry is replaced in place (stable id, latest text and time,
//    repeatCount incremented) - one DOM row advances instead of thousands
//    of rows being appended.
// 2. Everything else (ERROR/WARN/success/start, any non-progress line,
//    the very first line of a run) appends verbatim and is never merged.
// 3. The rolling cap is applied once per batch, evicting the OLDEST
//    entries and keeping the newest ones.
export const appendLogLines = (prev: LogEntry[], raw: string[]): LogEntry[] => {
  const next = prev.slice();
  const parsed = raw.map(parseLogLine);

  for (const entry of parsed) {
    const last = next.length > 0 ? next[next.length - 1] : null;
    if (
      next.length === 0 ||
      entry.level !== 'info' ||
      !isProgressLine(entry.text) ||
      last === null ||
      last.level !== 'info' ||
      !isProgressLine(last.text)
    ) {
      next.push(entry);
    } else {
      next[next.length - 1] = {
        ...last,
        time: entry.time,
        text: entry.text,
        repeatCount: last.repeatCount + 1
      };
    }
  }

  if (next.length > MAX_LOG_ENTRIES) {
    return next.slice(next.length - MAX_LOG_ENTRIES);
  }
  return next;
};
