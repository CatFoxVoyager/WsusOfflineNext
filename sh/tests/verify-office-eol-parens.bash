#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Office EOL paren regression gate (Linux / Bash)
# File: sh/tests/verify-office-eol-parens.bash
#
# Issue #29: client/cmd/DoUpdate.cmd aborted with ") was unexpected at
# this time." (exit 255) on every machine where an Office 2016-family
# product was detected. The Office-info echo sat inside a parenthesized
# if block and expanded %O2K16_EOL_STATUS% at parse time;
# DetermineSystemProperties.vbs assigns that variable values containing
# ")" (e.g. "EOL (End of Life - Oct 2025)", "Channel Managed (C2R)"),
# and O2K16_PRODUCT_NAME can be "Office 2016 (MSI)". The inner ")"
# closed the block early -> parse error -> exit 255 before any update.
#
# This gate extracts the REAL Office-info lines from
# client/cmd/DoUpdate.cmd (path overridable via WOU_DOUPDATE_SOURCE,
# used for bite proofs against a pre-fix copy), replays them inside a
# temp sandbox script against the paren-bearing values, and requires:
#   - exit code 0
#   - the O2K16-PARENS-SENTINEL echoed AFTER the block (parse lived
#     past the block)
#   - a rendered "Found Microsoft Office" line (the echo executed -
#     non-vacuous pass)
#
# Fix convention (issue #29): the echo must stay OUTSIDE any
# parenthesized block (single-line if form, like the MSEDGE echoes).
#
# Every failure prints a FAIL: line and exits 1; success prints
# OFFICE-EOL-PARENS-PASS. Fixtures are self-created in a temp sandbox.
# =======================================================================

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source_file="${WOU_DOUPDATE_SOURCE:-$script_dir/../../client/cmd/DoUpdate.cmd}"

fail_count=0
fail () {
  printf 'FAIL: %s\n' "$1"
  fail_count=$(( fail_count + 1 ))
}

[ -f "$source_file" ] || { fail "source not found: $source_file"; exit 1; }

# --- extract the real Office-info lines --------------------------------
# The anchor is the Office echo line itself (the "version:" colon form
# occurs exactly once; the other O2K16_VER_MAJOR blocks in the file are
# parse-safe: quoted :Log, or delayed expansion inside). Two accepted
# shapes, decided from the anchor's own context:
#   single: if "%O2K16_VER_MAJOR%" NEQ "" echo Found Microsoft ... (fix form)
#   block:  if "%O2K16_VER_MAJOR%" NEQ "" ( / echo Found Microsoft ... / )
anchor='Found Microsoft %O2K16_PRODUCT_NAME% version:'
n_anchor=$(grep -cF "$anchor" "$source_file")
if [ "$n_anchor" -ne 1 ]; then
  fail "Office-info echo anchor found $n_anchor times (expected exactly 1) in $source_file"
  exit 1
fi
anchor_line="$(grep -nF "$anchor" "$source_file" | cut -d: -f1)"
prev_line="$(sed -n "$((anchor_line - 1))p" "$source_file")"
next_line="$(sed -n "$((anchor_line + 1))p" "$source_file")"
block_opener='if "%O2K16_VER_MAJOR%" NEQ "" ('
single_prefix='if "%O2K16_VER_MAJOR%" NEQ "" echo Found Microsoft'
anchor_text="$(sed -n "${anchor_line}p" "$source_file")"

if [[ "$anchor_text" == "$single_prefix"* ]]; then
  # single-line if...echo form (the fix)
  extracted="$(sed -n "${anchor_line}p" "$source_file")"
elif [ "$prev_line" = "$block_opener" ] && [ "$next_line" = ")" ]; then
  # 3-line parenthesized block (the pre-fix shape)
  extracted="$(sed -n "$((anchor_line - 1)),$((anchor_line + 1))p" "$source_file")"
  [ "$(printf '%s\n' "$extracted" | wc -l)" -eq 3 ] || fail "extracted block is not 3 lines"
else
  fail "Office-info echo at line $anchor_line is neither single-line form nor a clean if(...) block (prev='$prev_line' next='$next_line')"
  exit 1
fi

# --- sandbox runner -----------------------------------------------------
sandbox_dir="$(mktemp -d "${TMPDIR:-/tmp}/office-eol-parens.XXXXXX")"
trap 'rm -rf "$sandbox_dir"' EXIT

run_scenario () {
  local product="$1" eol="$2" scratch_rc render
  {
    printf '@echo off\r\n'
    printf 'set O2K16_VER_MAJOR=16\r\n'
    printf 'set O2K16_VER_MINOR=0\r\n'
    printf 'set O2K16_VER_BUILD=1234\r\n'
    printf 'set O2K16_VER_REVIS=5678\r\n'
    printf 'set O2K16_ARCH=x64\r\n'
    printf 'set O2K16_LANG=enu\r\n'
    printf 'set O2K16_PRODUCT_NAME=%s\r\n' "$product"
    printf 'set O2K16_EOL_STATUS=%s\r\n' "$eol"
    printf '%s\r\n' "$extracted" | sed 's/$/\r/'
    printf 'echo O2K16-PARENS-SENTINEL\r\n'
    printf 'exit /b 0\r\n'
  } > "$sandbox_dir/scratch.cmd"

  scratch_rc=0
  cmd //c "$(cygpath -w "$sandbox_dir/scratch.cmd")" > "$sandbox_dir/out.txt" 2>&1 || scratch_rc=$?

  if [ "$scratch_rc" -ne 0 ]; then
    fail "scenario [$product / $eol]: exit code $scratch_rc (expected 0)"
  fi
  grep -qF "O2K16-PARENS-SENTINEL" "$sandbox_dir/out.txt" \
    || fail "scenario [$product / $eol]: sentinel missing (parse died before end of script)"
  render="$(grep -F "Found Microsoft" "$sandbox_dir/out.txt")"
  printf '%s' "$render" | grep -qF "Found Microsoft $product" \
    || fail "scenario [$product / $eol]: Office echo did not render (vacuous pass)"
}

for eol in "EOL (End of Life - Oct 2025)" "EOL (End of Life - Oct 2026)" \
           "Active (Supported until Oct 2029)" "Channel Managed (C2R)"; do
  run_scenario "Office 2016 (MSI)" "$eol"
  run_scenario "Office LTSC 2024" "$eol"
done

if [ "$fail_count" -gt 0 ]; then
  exit 1
fi
printf 'OFFICE-EOL-PARENS-PASS\n'
exit 0
