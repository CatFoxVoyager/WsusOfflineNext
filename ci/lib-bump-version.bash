#!/usr/bin/env bash
#
# ci/lib-bump-version.bash — bump-version logic, testable outside the real tree
#
# Sourced by ci/bump-version.bash (the consumer) and by
# ci/tests/test-bump-version.sh (sandbox probes). This file defines functions
# only: sourcing it has no side effects, so a test can load it without running
# the bump itself.
#
# CISC-08 (finding IN-08): occurrences are COUNTED and the substitution
# pattern is bounded at digit boundaries. grep -c counts LINES while
# sed s///g substitutes OCCURRENCES - the 32-substitution invariant only
# holds if both speak about the same thing. The (^|[^0-9])...([^0-9]|$)
# bound also makes a collision like 2026.10.2 inside 2026.10.20 structurally
# impossible instead of accidentally absent.

# ===== Functions =====

# Old version from the single source of truth. Uses the caller's repo_root
# global and sets the caller's old_version global (ci/bump-version.bash).
function read_old_version ()
{
  old_version="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+' "${repo_root}/cmd/DownloadUpdates.cmd" \
    | head -1 | cut -d'=' -f2)"
  if [ -z "${old_version}" ]; then
    echo "bump-version: cannot read current version from cmd/DownloadUpdates.cmd" >&2
    exit 1
  fi
  return 0
}

# Count OCCURRENCES of an ERE in a file (not lines): grep -o emits one match
# per output line, so counting non-empty output lines counts occurrences.
# A file with two occurrences on one line returns 2 - the same thing
# sed s///g would substitute.
function count_occurrences ()
{
  local pattern="$1"
  local target="$2"
  local found=""
  found="$(grep -oE "${pattern}" "${target}" | grep -c . || true)"
  printf '%s\n' "${found}"
  return 0
}

# Substitute every boundary-safe occurrence of <old-escaped> with <new-version>
# in place. The bound (^|[^0-9])...([^0-9]|$) keeps any bordering non-digit
# and refuses a match whose right neighbour is a digit: 2026.10.2 never
# matches inside 2026.10.20. <old-escaped> must have its dots escaped
# ("${old_version//./\\.}").
function substitute_bounded ()
{
  local old_escaped="$1"
  local new_value="$2"
  local target="$3"
  sed -E -i "s/(^|[^0-9])${old_escaped}([^0-9]|\$)/\1${new_value}\2/g" "${target}"
  return 0
}
