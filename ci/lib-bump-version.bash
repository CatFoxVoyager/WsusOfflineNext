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
#
# SemVer extension (phase 19, decision D-01): the locked format is
# MAJOR.MINOR.PATCH+YYYY.MM. The matrix occurrences (22 since Phase 25
# plan 01; 26 after Phase 24; 32 before it) split into two disjoint
# contexts: 16 full-form sites (source of truth, headers, captions, marker,
# <Version>, package.json, App.tsx) carry the whole M.m.p+YYYY.MM token,
# and 6 numeric-only build contexts (csproj <FileVersion>/
# <AssemblyVersion> "X.Y.Z.0", AutoIt "#pragma compile(..., X.Y.Z)") MUST
# carry the bare core - a '+' metadata there breaks CompileModernApps.cmd
# and Aut2Exe. The engine therefore runs TWO LANES (see ci/bump-version.bash).

# ===== Functions =====

# Old version from the single source of truth. Uses the caller's repo_root
# global and sets the caller's old_version global (ci/bump-version.bash).
# The optional +YYYY.MM metadata is part of the captured token: the value is
# the full form when metadata is present, the bare core when it is not
# (grep -o stops before the space that precedes the build tag).
function read_old_version ()
{
  old_version="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]{4}\.[0-9]{2})?' "${repo_root}/cmd/DownloadUpdates.cmd" \
    | head -1 | cut -d'=' -f2)"
  if [ -z "${old_version}" ]; then
    echo "bump-version: cannot read current version from cmd/DownloadUpdates.cmd" >&2
    exit 1
  fi
  return 0
}

# Validate a bump-version argv token: the locked full form M.m.p+YYYY.MM
# (year exactly 4 digits, month exactly 2) or the bare core M.m.p accepted
# for manual/collision-loop paths. 5.0.0+26.1, 5.0.0+2026.11.0 and
# 5.0.0+2026.1 are refused. PREDICATE: returns the grep status itself —
# no trailing "return 0" here, that would discard the verdict and accept
# everything.
function is_valid_version_arg ()
{
  printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]{4}\.[0-9]{2})?$'
}

# Print the bare core of a version token: everything before the '+' metadata,
# or the token itself when it carries none.
function strip_version_metadata ()
{
  printf '%s\n' "${1%%+*}"
  return 0
}

# Escape a version token for use inside a POSIX ERE: '.' and '+' are literal
# there. Plain groups only - '(?:...)' is invalid ERE ("Invalid preceding
# regular expression" under sed -E).
function escape_ere ()
{
  local token="$1"
  token="${token//./\\.}"
  token="${token//+/\\+}"
  printf '%s\n' "${token}"
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
# matches inside 2026.10.20. <old-escaped> must come from escape_ere().
function substitute_bounded ()
{
  local old_escaped="$1"
  local new_value="$2"
  local target="$3"
  sed -E -i "s/(^|[^0-9])${old_escaped}([^0-9]|\$)/\1${new_value}\2/g" "${target}"
  return 0
}

# Count the NUMERIC-CONTEXT anchors of an escaped source token in one matrix
# file: csproj "<FileVersion>core.0</FileVersion>" / "<AssemblyVersion>" and
# AutoIt "#pragma compile(FileVersion|ProductVersion, core)" lines. Anchors
# are tied to the closing tag/paren, never to bare version text (T-19-03).
# Non-numeric files count 0.
function count_numeric_anchored ()
{
  local src_escaped="$1"
  local target="$2"
  case "${target}" in
    *.csproj) count_occurrences "${src_escaped}\.0</(FileVersion|AssemblyVersion)>" "${target}" ;;
    *.au3)    count_occurrences "${src_escaped}\)" "${target}" ;;
    *)        printf '0\n' ;;
  esac
  return 0
}

# Numeric-anchored lane: rewrite the build-context anchors of <src-escaped>
# to the bare core <dst-core> in one matrix file, in place. The anchors are
# tied to the closing tag/paren (T-19-03) and the selection is by filename
# suffix: a csproj pass only ever runs on .csproj paths, a pragma pass only
# on .au3 paths - never a scan of the whole matrix. <dst-core> is a bare
# M.m.p core, so the replacement text puts digits only BEFORE the \1
# backref; a digit AFTER a backref is the broken parse shape ("\\15" reads
# as backref 15).
function substitute_numeric_versions ()
{
  local src_escaped="$1"
  local dst_core="$2"
  local target="$3"
  case "${target}" in
    *.csproj)
      sed -E -i "s/${src_escaped}\.0(<\/(FileVersion|AssemblyVersion)>)/${dst_core}.0\1/g" "${target}"
      ;;
    *.au3)
      sed -E -i "s/${src_escaped}\)/${dst_core})/g" "${target}"
      ;;
  esac
  return 0
}

# Classify the next bump class from a conventional-commit log TEXT (the full
# "git log --format=%s%n%b" output as ONE argument — pure function, the
# caller shells git). Precedence is deliberate: MAJOR wins over everything,
# MINOR wins over PATCH. An empty log resolves PATCH — a train with no
# commits since the tag still bumps PATCH (pinned edge).
function classify_next_version ()
{
  local log_text="$1"
  if printf '%s\n' "${log_text}" | grep -qE 'BREAKING[ -]CHANGE[[:space:]]*:'; then
    printf 'MAJOR\n'
  elif printf '%s\n' "${log_text}" | grep -qE '^[A-Za-z]+(\([^)]*\))?!:'; then
    printf 'MAJOR\n'
  elif printf '%s\n' "${log_text}" | grep -qE '^feat(\([^)]*\))?(!)?:'; then
    printf 'MINOR\n'
  else
    printf 'PATCH\n'
  fi
  return 0
}

# Bump a bare M.m.p core by one class. Non-integer components or an unknown
# class return 1 without printing.
function bump_core ()
{
  local core="$1"
  local class="$2"
  local major="" minor="" patch=""
  IFS="." read -r major minor patch <<< "${core}"
  case "${class}" in
    MAJOR) major=$(( major + 1 )); minor=0; patch=0 ;;
    MINOR) minor=$(( minor + 1 )); patch=0 ;;
    PATCH) patch=$(( patch + 1 )) ;;
    *)
      echo "bump-version: unknown bump class '${class}'" >&2
      return 1
      ;;
  esac
  printf '%s.%s.%s\n' "${major}" "${minor}" "${patch}"
  return 0
}

# Resolve the next full version from the last tag, the train month and the
# conventional-commit log text. A legacy CalVer tag (YYYY.M.P) resolves to
# 5.0.0+<month> — the one-time migration branch: the schema change IS the
# MAJOR (D-01 first migration). A SemVer tag resolves to
# <classified-core>+<month>: the calendar metadata is regenerated from the
# train month on every resolution and never classified.
function next_full_version ()
{
  local last_tag="$1"
  local month="$2"
  local log_text="$3"
  local core="${last_tag#v}"
  if printf '%s' "${core}" | grep -qE '^20[0-9]{2}\.[0-9]{1,2}\.[0-9]+$'; then
    printf '5.0.0+%s\n' "${month}"
    return 0
  fi
  if printf '%s' "${core}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    printf '%s+%s\n' "$(bump_core "${core}" "$(classify_next_version "${log_text}")")" "${month}"
    return 0
  fi
  echo "bump-version: cannot resolve next version from tag '${last_tag}'" >&2
  return 1
}
