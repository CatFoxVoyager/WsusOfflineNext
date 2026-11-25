#!/usr/bin/env bash
# Battery for the generator download-console buffer (issue #47) — run from
# repo root; requires node + src-modern/generator/node_modules/.bin/rolldown
# (transitive dependency of the frontend, guaranteed by the generator npm ci).
# CI home: the dotnet-build job of .github/workflows/ci.yml, after both
# frontend npm ci steps.
#
# Sections:
#   a. real module behavior: compile src-modern/generator/src/logBuffer.ts
#      with the vendored rolldown into the sandbox and drive appendLogLines
#      from node — the 1000-entry rolling cap under a 50k-line burst, a
#      5000-line wget progress run coalescing into one (x5000) row,
#      ERROR/WARN/success preservation inside a mixed batch, and coalescing
#      across successive calls (flush boundaries)
#   b. App.tsx consumption pin: the real component imports the module and
#      calls the reducer, and carries none of the historical unbounded
#      append shape (negative gate)
#   c. can-fail controls: a cap-disabled module copy must red the cap
#      runner, an always-false progress predicate must red the coalesce
#      runner, and an import-stripped App.tsx copy must red the consumption
#      gate (a silent re-inline turns CI red)
#
# Native-path rule: every path handed to rolldown or node (native binaries)
# is absolutized to Windows-native form via cygpath -m when available
# (NATIVE/NROOT prefixes); POSIX absolute paths pass through on Linux CI.
# Relative entry paths are refused by the rolldown resolver (UNRESOLVED_ENTRY,
# probed on the Windows host this battery was authored on), so module inputs
# are absolutized exactly like the outputs.
set -u

MODULE="src-modern/generator/src/logBuffer.ts"
APP_TSX="src-modern/generator/src/App.tsx"
ROL="src-modern/generator/node_modules/.bin/rolldown"

FAILED_CASES=0

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

# Absolute native form of a path, for the native binaries (rolldown, node).
to_native () {
    command -v cygpath >/dev/null 2>&1 && cygpath -m "$1" || echo "$1"
}

[ -f "${MODULE}" ] || { echo "FAIL: module missing: ${MODULE}"; exit 1; }
[ -f "${APP_TSX}" ] || { echo "FAIL: App.tsx missing: ${APP_TSX}"; exit 1; }
if [ ! -x "${ROL}" ]; then
    echo "FAIL: rolldown not found at ${ROL} — run 'npm ci' in src-modern/generator first (the battery compiles the module with the frontend's transitive rolldown)"
    exit 1
fi

SANDBOX="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "${SANDBOX}"' EXIT

NATIVE="$(command -v cygpath >/dev/null 2>&1 && cygpath -m "${SANDBOX}" || echo "${SANDBOX}")"
NROOT="$(to_native "${PWD}")"
NMODULE="${NROOT}/${MODULE}"
NAPP="${NROOT}/${APP_TSX}"

# --- Section a: real module behavior --------------------------------------
echo "--- section a: real module behavior (compiled + driven from node) ---"

"$ROL" "${NMODULE}" --format cjs --platform node --file "${NATIVE}/logBuffer.cjs" > "${SANDBOX}/compile.log" 2>&1
COMPILE_RC=$?
if [ "${COMPILE_RC}" -ne 0 ] || [ ! -s "${SANDBOX}/logBuffer.cjs" ]; then
    fail_case "section a: real module compile failed (rc=${COMPILE_RC}, output empty or missing)"
    sed 's/^/    /' "${SANDBOX}/compile.log"
fi

cat > "${SANDBOX}/runner.cjs" <<'RUNNER_EOF'
const { appendLogLines, MAX_LOG_ENTRIES } = require(process.argv[2]);

const assert = (name, cond, detail) => {
  if (!cond) {
    console.log('FAIL: ' + name + (detail ? ' — ' + detail : ''));
    process.exit(1);
  }
};

// cap-50000: 50 calls x 1000 plain lines -> exactly the newest 1000 kept.
let logs = [];
for (let call = 0; call < 50; call++) {
  const batch = [];
  for (let n = call * 1000 + 1; n <= (call + 1) * 1000; n++) {
    batch.push('line ' + n + ' of 50000');
  }
  logs = appendLogLines(logs, batch);
}
assert('cap-50000 length', logs.length === MAX_LOG_ENTRIES, 'length=' + logs.length);
assert('cap-50000 last text', logs[logs.length - 1].text === 'line 50000 of 50000', 'last=' + logs[logs.length - 1].text);
assert('cap-50000 eviction', logs.every(e => e.text !== 'line 1 of 50000'), 'the oldest line survived');

// coalesce-burst: seed + one 5000-line progress burst in ONE call -> 2 rows.
const burst = ['Starting download of wsusscn2.cab'];
for (let i = 0; i < 5000; i++) {
  burst.push(' ' + (12000 + i * 50) + 'K .......... ' + (1 + i) + '% 96.4M 1s');
}
logs = appendLogLines([], burst);
assert('coalesce-burst length', logs.length === 2, 'length=' + logs.length);
assert('coalesce-burst count', logs[1].repeatCount === 5000, 'repeatCount=' + logs[1].repeatCount);
assert('coalesce-burst text', logs[1].text === ' 261950K .......... 5000% 96.4M 1s', 'text=' + logs[1].text);
assert('coalesce-burst seed kept', logs[0].text === 'Starting download of wsusscn2.cab', 'text=' + logs[0].text);

// mixed-preserved: success / progress pair / ERROR / progress / WARN.
logs = appendLogLines([], [
  'Downloaded/validated wsusscn2.cab',
  ' 4600K .......... 10% 1.16M 37s',
  ' 4700K .......... 20% 1.16M 36s',
  'ERROR: download failed for msxml4.cab',
  ' 4800K .......... 30% 1.16M 35s',
  'Warning: retrying in 5 seconds'
]);
assert('mixed length', logs.length === 5, 'length=' + logs.length);
assert('mixed success intact', logs[0].level === 'success' && logs[0].repeatCount === 1, JSON.stringify(logs[0]));
assert('mixed coalesced pair', logs[1].repeatCount === 2 && logs[1].text === ' 4700K .......... 20% 1.16M 36s', JSON.stringify(logs[1]));
assert('mixed error once', logs[2].level === 'error' && logs[2].repeatCount === 1, JSON.stringify(logs[2]));
assert('mixed progress after error', logs[3].text === ' 4800K .......... 30% 1.16M 35s' && logs[3].repeatCount === 1, JSON.stringify(logs[3]));
assert('mixed warn once', logs[4].level === 'warn' && logs[4].repeatCount === 1, JSON.stringify(logs[4]));
const mixedErrors = logs.filter(e => e.level === 'error').length;
const mixedWarns = logs.filter(e => e.level === 'warn').length;
assert('mixed never merged', mixedErrors === 1 && mixedWarns === 1, 'error=' + mixedErrors + ' warn=' + mixedWarns);

// cross-flush: seed call, then progress, then progress -> one coalesced row.
logs = appendLogLines([], ['Starting download of wsusscn2.cab']);
logs = appendLogLines(logs, [' 4600K .......... 10% 1.16M 37s']);
logs = appendLogLines(logs, [' 4700K .......... 20% 1.16M 36s']);
assert('cross-flush length', logs.length === 2, 'length=' + logs.length);
assert('cross-flush count', logs[1].repeatCount === 2, 'repeatCount=' + logs[1].repeatCount);
assert('cross-flush text', logs[1].text === ' 4700K .......... 20% 1.16M 36s', 'text=' + logs[1].text);

// wget-unspecified-length: wget without % (Length: unspecified) coalesces.
logs = appendLogLines([], [
  "Saving to: '../client/dotnet/aspnetcore-runtime-8.0.32-win-x86.exe'",
  '     0K .......... .......... .......... .......... .......... 44.1M',
  '    50K .......... .......... .......... .......... ..........  103K',
  '  9450K .......... .......... ...                               396M=15s',
  "2026-11-24 10:25:16 (639 KB/s) - '../client/dotnet/aspnetcore-runtime-8.0.32-win-x86.exe' saved [9700760]"
]);
assert('wget-unspec length', logs.length === 3, 'length=' + logs.length);
assert('wget-unspec count', logs[1].repeatCount === 3, 'repeatCount=' + logs[1].repeatCount);
assert('wget-unspec last text', logs[1].text.includes('9450K'), 'text=' + logs[1].text);

// mkisofs-progress: mkisofs "% done, estimate finish" lines coalesce.
const isoLines = ['Creating ISO image...'];
for (let i = 0; i < 500; i++) {
  const pct = (i * 0.2).toFixed(2);
  isoLines.push(' ' + pct + '% done, estimate finish Tue Nov 24 23:24:10 2026');
}
isoLines.push('Total translation table size: 0');
logs = appendLogLines([], isoLines);
assert('mkisofs length', logs.length === 3, 'length=' + logs.length);
assert('mkisofs count', logs[1].repeatCount === 500, 'repeatCount=' + logs[1].repeatCount);
assert('mkisofs tail', logs[2].text === 'Total translation table size: 0', 'text=' + logs[2].text);

console.log('SECTION-A-PASS');
process.exit(0);
RUNNER_EOF

RUN_RC=0
node "${NATIVE}/runner.cjs" "${NATIVE}/logBuffer.cjs" > "${SANDBOX}/runner.log" 2>&1 || RUN_RC=$?
if [ "${RUN_RC}" -ne 0 ]; then
    fail_case "section a: real-module runner red (rc=${RUN_RC})"
    sed 's/^/    /' "${SANDBOX}/runner.log"
elif ! grep -qF 'SECTION-A-PASS' "${SANDBOX}/runner.log"; then
    fail_case "section a: runner exited 0 without the SECTION-A-PASS sentinel"
else
    cat "${SANDBOX}/runner.log"
fi

# --- Section b: App.tsx consumption pin ------------------------------------
echo "--- section b: App.tsx consumption pin ---"

# Comment-stripped line census over an App.tsx-shaped file. The historical
# unbounded append shape is banned outright; import and reducer-use counts
# must stay at floor.
consumption_ok () {
    local file="$1"
    local stripped
    stripped="$(grep -vE '^[[:space:]]*(//|\*|\{/\*)' "${file}" || true)"
    local imp calls banned
    imp="$(printf '%s\n' "${stripped}" | grep -cF "from './logBuffer'")"
    calls="$(printf '%s\n' "${stripped}" | grep -cF 'appendLogLines')"
    banned="$(printf '%s\n' "${stripped}" | grep -cF 'setLogs(prev => [...prev, parseLogLine')"
    [ "${imp}" -ge 1 ] || { echo "FAIL: consumption: the logBuffer import is missing (count=${imp})"; return 1; }
    [ "${calls}" -ge 2 ] || { echo "FAIL: consumption: module use too low (${calls} < 2: import + call sites)"; return 1; }
    [ "${banned}" -eq 0 ] || { echo "FAIL: consumption: unbounded append shape present (count=${banned})"; return 1; }
    return 0
}

if consumption_ok "${APP_TSX}"; then
    echo "  ok: App.tsx imports the module and drives the reducer; no unbounded append"
else
    fail_case "section b: App.tsx consumption pin red"
fi

# --- Section c: can-fail controls ------------------------------------------
echo "--- section c: can-fail controls ---"

# Control 1: cap bite. A copy with the rolling cap raised past the burst
# size must red the cap runner (length > 1000 after 50k lines).
sed 's/MAX_LOG_ENTRIES = 1000/MAX_LOG_ENTRIES = 100000/' "${MODULE}" > "${SANDBOX}/capBite.ts"
CAP_LANDED="$(grep -cF 'MAX_LOG_ENTRIES = 100000' "${SANDBOX}/capBite.ts")"
[ "${CAP_LANDED}" -eq 1 ] || fail_case "control 1: cap mutation did not land (count=${CAP_LANDED}, expected 1)"

cat > "${SANDBOX}/capRunner.cjs" <<'CAPRUN_EOF'
const { appendLogLines } = require(process.argv[2]);
let logs = [];
for (let call = 0; call < 50; call++) {
  const batch = [];
  for (let n = call * 1000 + 1; n <= (call + 1) * 1000; n++) {
    batch.push('line ' + n + ' of 50000');
  }
  logs = appendLogLines(logs, batch);
}
if (logs.length > 1000) {
  console.log('FAIL: cap runner: length ' + logs.length + ' > 1000');
  process.exit(1);
}
console.log('CAP-RUNNER-PASS (length=' + logs.length + ')');
process.exit(0);
CAPRUN_EOF

if "$ROL" "${NATIVE}/capBite.ts" --format cjs --platform node --file "${NATIVE}/capBite.cjs" > "${SANDBOX}/capCompile.log" 2>&1; then
    CAP_RC=0
    node "${NATIVE}/capRunner.cjs" "${NATIVE}/capBite.cjs" > "${SANDBOX}/capRunner.log" 2>&1 || CAP_RC=$?
    if [ "${CAP_RC}" -eq 0 ]; then
        fail_case "control 1 does not bite: cap-disabled module passed the cap runner ($(tail -n 1 "${SANDBOX}/capRunner.log"))"
    else
        echo "  control ok: cap bite bites (runner red rc=${CAP_RC}: $(tail -n 1 "${SANDBOX}/capRunner.log"))"
    fi
else
    fail_case "control 1: mutated module failed to compile (the mutation must stay valid)"
    sed 's/^/    /' "${SANDBOX}/capCompile.log"
fi

# Control 2: coalesce bite. The progress predicate is the module's only
# boolean arrow; forcing it always-false in a copy must red the coalesce
# runner (200 progress lines would otherwise stay 200 rows).
sed 's/: boolean =>/: boolean => false \&\&/' "${MODULE}" > "${SANDBOX}/coBite.ts"
CO_LANDED="$(grep -cF 'false &&' "${SANDBOX}/coBite.ts")"
[ "${CO_LANDED}" -eq 1 ] || fail_case "control 2: predicate mutation did not land (count=${CO_LANDED}, expected 1)"

cat > "${SANDBOX}/coRunner.cjs" <<'CORUN_EOF'
const { appendLogLines } = require(process.argv[2]);
const batch = [];
for (let i = 0; i < 200; i++) {
  batch.push(' ' + (12000 + i * 50) + 'K .......... ' + (1 + i) + '% 96.4M 1s');
}
const logs = appendLogLines([], batch);
if (logs.length > 2) {
  console.log('FAIL: coalesce runner: length ' + logs.length + ' > 2');
  process.exit(1);
}
console.log('CO-RUNNER-PASS (length=' + logs.length + ')');
process.exit(0);
CORUN_EOF

if "$ROL" "${NATIVE}/coBite.ts" --format cjs --platform node --file "${NATIVE}/coBite.cjs" > "${SANDBOX}/coCompile.log" 2>&1; then
    CO_RC=0
    node "${NATIVE}/coRunner.cjs" "${NATIVE}/coBite.cjs" > "${SANDBOX}/coRunner.log" 2>&1 || CO_RC=$?
    if [ "${CO_RC}" -eq 0 ]; then
        fail_case "control 2 does not bite: always-false predicate passed the coalesce runner ($(tail -n 1 "${SANDBOX}/coRunner.log"))"
    else
        echo "  control ok: coalesce bite bites (runner red rc=${CO_RC}: $(tail -n 1 "${SANDBOX}/coRunner.log"))"
    fi
else
    fail_case "control 2: mutated module failed to compile (the mutation must stay valid)"
    sed 's/^/    /' "${SANDBOX}/coCompile.log"
fi

# Control 3: re-inline bite. An App.tsx copy stripped of the module import
# must red the consumption gate — a silent re-inline turns CI red.
sed "s|from './logBuffer'||" "${APP_TSX}" > "${SANDBOX}/AppInline.tsx"
INLINE_LANDED="$(grep -cF "from './logBuffer'" "${SANDBOX}/AppInline.tsx")"
[ "${INLINE_LANDED}" -eq 0 ] || fail_case "control 3: import removal did not land (count=${INLINE_LANDED}, expected 0)"

if consumption_ok "${SANDBOX}/AppInline.tsx"; then
    fail_case "control 3 does not bite: the consumption gate accepts an import-stripped copy"
else
    echo "  control ok: the consumption gate rejects an import-stripped App.tsx"
fi

# --- Verdict (the counter comparison is the final instruction) -------------
if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "CONSOLE-BUFFER-BATTERY-PASS"
    exit 0
fi
echo "CONSOLE-BUFFER-BATTERY-FAIL (${FAILED_CASES} failed case(s))"
exit 1
