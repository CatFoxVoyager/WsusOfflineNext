#!/usr/bin/env bash
# Offline battery for ci/lib-office-catalog-counts.bash — run from repo root.
# Zero network by construction: fixtures are synthetic "<id>,<url>" pairs.
# Double-faced bites: the comparator must be green at the good state and red
# (exit 1) on each planted bad state. Each bite asserts its planted state
# LANDED before reading the instrument's verdict.
set -u
LIB="ci/lib-office-catalog-counts.bash"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

bash -n "$LIB" || { echo "FAIL: lib fails bash -n"; exit 1; }
# shellcheck source=lib-office-catalog-counts.bash disable=SC1091
source "$LIB"

# --- fixture: 3 plausible Office 2016 catalog payloads + 3 non-Office ones
# (windows msu, sql server 2016, sharepoint 2016 — the bare-2016 decoys the
# glued-token pattern must NOT count as o2k16)
{
  printf 'g1,http://download.microsoft.com/download/A/B/office2016-kb5002700-x64-none_11111111-1111-1111-1111-111111111111.msp\n'
  printf 'g2,http://download.microsoft.com/download/A/B/mso2016-kb5002627-x86-none_22222222-2222-2222-2222-222222222222.msp\n'
  printf 'g3,http://download.microsoft.com/download/A/B/word2016-kb4011234-x86-none_33333333-3333-3333-3333-333333333333.exe\n'
  printf 'w1,http://download.microsoft.com/download/A/B/windows10.0-kb4012215-x64.msu\n'
  printf 'w2,http://download.microsoft.com/download/A/B/sqlserver2016-kb4535041-x64.exe\n'
  printf 'w3,http://download.microsoft.com/download/A/B/sharepoint2016-kb5002700-x64.msp\n'
} > "$T/pairs.txt"
out="$T/counts.txt"

# --- counting: exact per-family table + loggable stdout lines
table="$(count_office_family_revisions "$T/pairs.txt" "$out")"
rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: counter exited $rc"; exit 1; }
awk -F'\t' '$1 == "o2k16" && $2 == "3" { ok=1 } END { exit ok ? 0 : 1 }' "$out" \
  || { echo "FAIL: o2k16 count != 3 (got: $(awk -F'\t' '$1=="o2k16"{print $2}' "$out"))"; exit 1; }
[ "$(wc -l < "$out" | tr -d ' ')" -eq "${#OFFICE_FAMILY_PATTERNS[@]}" ] \
  || { echo "FAIL: counts file does not carry one line per declared family"; exit 1; }
printf '%s\n' "$table" | grep -qF "office-revision-counts: o2k16=3" \
  || { echo "FAIL: stdout table missing or wrong (o2k16)"; exit 1; }

# --- zero is a RESULT: an all-non-Office fixture still emits the family at 0
printf 'w1,http://download.microsoft.com/download/A/B/windows10.0-kb4012215-x64.msu\n' > "$T/pairs-zero.txt"
outzero="$T/counts-zero.txt"
count_office_family_revisions "$T/pairs-zero.txt" "$outzero" > /dev/null
awk -F'\t' '$1 == "o2k16" && $2 == "0" { ok=1 } END { exit ok ? 0 : 1 }' "$outzero" \
  || { echo "FAIL: zero-count family line missing (y compris zéro contract)"; exit 1; }

# --- input guard: missing pairs file fails closed
count_office_family_revisions "$T/does-not-exist.txt" "$T/x.txt" > /dev/null 2>&1
rc_missing=$?
[ "$rc_missing" -eq 1 ] || { echo "FAIL: missing pairs file must return 1 (got $rc_missing)"; exit 1; }

# --- good baseline (counts + audited c2r literals from the lib itself)
good="$T/base-good.txt"
{
  printf '# planted good baseline\n'
  printf 'frozen_o2k16=3\n'
  for prod in "${!OFFICE_C2R_BASELINE_LITERALS[@]}"; do
    printf 'c2r_baseline_%s=%s\n' "$prod" "${OFFICE_C2R_BASELINE_LITERALS[${prod}]}"
  done
} > "$good"
grep -qxF 'frozen_o2k16=3' "$good" || { echo "FAIL: planted good baseline did not land"; exit 1; }
assert_office_frozen_baseline "$out" "$good" 2> "$T/err-good.txt"
rc_good=$?
[ "$rc_good" -eq 0 ] || { echo "FAIL: good baseline must pass (got $rc_good)"; cat "$T/err-good.txt"; exit 1; }

# --- bite 1: frozen count drift aborts
drift="$T/base-drift.txt"
{
  printf '# planted drift baseline\n'
  printf 'frozen_o2k16=4\n'
  for prod in "${!OFFICE_C2R_BASELINE_LITERALS[@]}"; do
    printf 'c2r_baseline_%s=%s\n' "$prod" "${OFFICE_C2R_BASELINE_LITERALS[${prod}]}"
  done
} > "$drift"
grep -qxF 'frozen_o2k16=4' "$drift" || { echo "FAIL: bite 1 baseline did not land"; exit 1; }
assert_office_frozen_baseline "$out" "$drift" 2> "$T/err-b1.txt"
rc_b1=$?
[ "$rc_b1" -eq 1 ] || { echo "FAIL: bite 1 — frozen drift must abort (exit 1, got $rc_b1)"; exit 1; }
grep -qF 'DRIFT on o2k16 expected=4 observed=3' "$T/err-b1.txt" \
  || { echo "FAIL: bite 1 — drift message wrong"; cat "$T/err-b1.txt"; exit 1; }
grep -qF 'deliberate re-pin required' "$T/err-b1.txt" \
  || { echo "FAIL: bite 1 — re-pin procedure not cited in the message"; exit 1; }

# --- bite 2: absent baseline = first run (warn, NOT an abort)
assert_office_frozen_baseline "$out" "$T/no-such-baseline.txt" 2> "$T/err-b2.txt"
rc_b2=$?
[ "$rc_b2" -eq 0 ] || { echo "FAIL: bite 2 — absent baseline must NOT abort (got $rc_b2)"; exit 1; }
grep -qF 'office-frozen-baseline: absent — first run, comparison skipped (warn)' "$T/err-b2.txt" \
  || { echo "FAIL: bite 2 — first-run warn missing"; cat "$T/err-b2.txt"; exit 1; }
# empty-file variant follows the same first-run semantics
: > "$T/empty-baseline.txt"
assert_office_frozen_baseline "$out" "$T/empty-baseline.txt" 2> /dev/null
rc_b2b=$?
[ "$rc_b2b" -eq 0 ] || { echo "FAIL: bite 2b — empty baseline must NOT abort (got $rc_b2b)"; exit 1; }

# --- bite 3: c2r literal transcription drift aborts (T-20-02)
c2rdrift="$T/base-c2r-drift.txt"
sed 's/^c2r_baseline_o2k21=.*/c2r_baseline_o2k21=16.0.14332.20790/' "$good" > "$c2rdrift"
grep -qxF 'c2r_baseline_o2k21=16.0.14332.20790' "$c2rdrift" \
  || { echo "FAIL: bite 3 planted literal did not land"; exit 1; }
assert_office_frozen_baseline "$out" "$c2rdrift" 2> "$T/err-b3.txt"
rc_b3=$?
[ "$rc_b3" -eq 1 ] || { echo "FAIL: bite 3 — c2r transcription drift must abort (got $rc_b3)"; exit 1; }
grep -qF 'DRIFT on o2k21 expected=16.0.14334.20974 observed=16.0.14332.20790' "$T/err-b3.txt" \
  || { echo "FAIL: bite 3 — c2r drift message wrong"; cat "$T/err-b3.txt"; exit 1; }

# --- bite 4: unknown non-comment key is a parse error (strict snapshot)
printf 'frozen_o2k16=3\nfrozen_o2k99=7\n' > "$T/base-unknown.txt"
assert_office_frozen_baseline "$out" "$T/base-unknown.txt" 2> "$T/err-b4.txt"
rc_b4=$?
[ "$rc_b4" -eq 1 ] || { echo "FAIL: bite 4 — unknown frozen family must abort (got $rc_b4)"; exit 1; }
grep -qF 'observed=missing' "$T/err-b4.txt" \
  || { echo "FAIL: bite 4 — missing-family message wrong"; cat "$T/err-b4.txt"; exit 1; }

echo "PASS office catalog counts battery (counter/comparator/frozen drift/first-run/c2r transcription/strict keys)"
