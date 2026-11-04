#!/usr/bin/env bash
#
# ci/bump-webview2-dep.bash — bump the WebView2 SDK PackageReference to the
# latest stable NuGet release, before the train builds
#
# Usage: bash ci/bump-webview2-dep.bash             (bump; stdout = the resolved SDK version)
#        bash ci/bump-webview2-dep.bash --print-files
#
# The application version matrix (ci/bump-version.bash) and the SDK version
# live in DISJOINT namespaces: the SDK lane rewrites ONLY the 4-part
# 1.0.x PackageReference token, never the 3-part app version (<Version>,
# <FileVersion>, <AssemblyVersion>, #pragma). The monthly train used to pin
# the SDK by hand — 1.0.2792.45 stood for a year while evergreen runtimes
# moved on, until the stale pin itself started producing E_NOINTERFACE
# failures on recent runtimes. This step runs between "Bump version" and
# the build steps so every train ships on the current SDK.
#
# MIN_WEBVIEW2_VERSION single-sourcing (Phase 24, plan 02): the floor lives
# in exactly ONE place — the MIN_WEBVIEW2_FLOOR constant below. On every run
# (bump or no-op day) the lane rewrites it into all four consumer sites:
# the MinWebView2Version const of BOTH C# hosts and the MIN_WEBVIEW2_VERSION
# set-line of BOTH pure-.cmd launchers. A consumer carrying a stale or
# drifted floor is healed by the same run. The stale-const class behind the
# E_NOINTERFACE hotfix is closed structurally: no consumer may recopy the
# literal.
#
# Fail-closed policy (deliberate): an unreachable NuGet index, a csproj
# divergence, an unparseable index, a would-be downgrade, a stale floor
# (floor build below the resolved SDK build), or a missing/duplicated
# consumer floor site all exit 1 — publishing a release while knowingly
# carrying a stale SDK or floor is exactly the bug class this step exists
# to prevent, so the step MUST fail the train. The stale-floor invariant is
# checked BEFORE any write so a stale floor blocks the whole lane with
# nothing half-written. SDK equality is the daily no-op for the csproj:
# only the floor rewrite may touch the tree, exit 0.
#
# WEBVIEW2_INDEX_FILE (path to a JSON document) replaces the curl call —
# the offline mode the fixture battery uses; it shares the same downstream
# code path as a live index response.

# ===== Configuration =====
readonly script_version="1.1"
readonly PACKAGE_ID="Microsoft.Web.WebView2"
readonly NUGET_INDEX_URL="https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json"
readonly CURL_MAX_TIME=30
readonly GENERATOR_CSPROJ="src-modern/generator/host/UpdateGenerator.csproj"
readonly INSTALLER_CSPROJ="src-modern/installer/host/UpdateInstaller.csproj"
# THE single source of the WebView2 runtime floor. The four consumers below
# are rewritten to it on every run; never recopy the literal elsewhere.
readonly MIN_WEBVIEW2_FLOOR="156.0.4314.35"
# The floor consumers, newline-separated (bump-version.bash VERSION_FILES
# house pattern): both C# host consts and both pure-.cmd launcher set-lines.
readonly MIN_FLOOR_CONSUMERS="src-modern/generator/host/Program.cs
src-modern/installer/host/Program.cs
UpdateGenerator.cmd
client/UpdateInstaller.cmd"

# ===== Global variables =====
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
current_version=""
installer_version=""
latest_version=""

# ===== Functions =====

# escape ERE metacharacters of a version/package token
escape_ere_literal () {
    printf '%s' "$1" | sed 's/[][\.*^$+?(){}|]/\\&/g'
}

# true when $1 sorts strictly before $2 (4-part numeric, sort -V)
version_lt () {
    [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n 1)" = "$1" ] && [ "$1" != "$2" ]
}

# print the Version attribute of the single WebView2 PackageReference line
get_package_reference_version () {
    local file="$1"
    local count line version
    count="$(grep -cF "Include=\"${PACKAGE_ID}\"" "${file}" 2>/dev/null)"
    count="${count:-0}"
    if [ "${count}" -ne 1 ]; then
        echo "FAIL: ${file} should carry exactly 1 ${PACKAGE_ID} PackageReference, found ${count}" >&2
        return 1
    fi
    line="$(grep -F "Include=\"${PACKAGE_ID}\"" "${file}" | head -n 1 | tr -d '\r')"
    local pkg_esc
    pkg_esc="$(escape_ere_literal "${PACKAGE_ID}")"
    version="$(printf '%s\n' "${line}" | sed -n -E "s@.*Include=\"${pkg_esc}\" Version=\"([^\"]+)\".*@\1@p")"
    if [ -z "${version}" ]; then
        echo "FAIL: no Version attribute found on the ${PACKAGE_ID} PackageReference of ${file}" >&2
        return 1
    fi
    printf '%s\n' "${version}"
}

# bounded rewrite of the PackageReference version in one csproj.
# Anchored on the Include attribute and the exact current version — never
# end-of-line (csproj may be CRLF). Atomic: sibling tmp + mv, tmp removed
# on every failure branch.
bump_csproj () {
    local file="$1" old_esc="$2" new_esc="$3"
    local tmp="${file}.bump-webview2-dep.tmp"
    local new_count old_count
    sed -E "s@(Include=\"${PACKAGE_ID_ESC}\" Version=\")${old_esc}(\")@\\1${new_esc}\\2@" \
        "${file}" > "${tmp}" || { rm -f "${tmp}"; echo "FAIL: sed rewrite failed on ${file}" >&2; return 1; }
    new_count="$(grep -cE "Include=\"${PACKAGE_ID_ESC}\" Version=\"${new_esc}\"" "${tmp}")"
    new_count="${new_count:-0}"
    old_count="$(grep -cE "Include=\"${PACKAGE_ID_ESC}\" Version=\"${old_esc}\"" "${tmp}")"
    old_count="${old_count:-0}"
    if [ "${new_count}" -ne 1 ] || [ "${old_count}" -ne 0 ]; then
        rm -f "${tmp}"
        echo "FAIL: substitution did not land exactly once on ${file} (new=${new_count} old=${old_count})" >&2
        return 1
    fi
    mv -f "${tmp}" "${file}" || { rm -f "${tmp}"; echo "FAIL: atomic move failed on ${file}" >&2; return 1; }
    return 0
}

# ---- floor single-sourcing helpers (Phase 24 plan 02) ----------------------

# count the C# const-line floor site shape (line-start anchored; never
# end-of-line anchored — the consumer files may be CRLF)
count_cs_floor_shape () {
    grep -cE '^[[:space:]]*public const string MinWebView2Version = "[0-9.]+"' "$1"
}

# count the .cmd set-line floor site shape (line-start anchored)
count_cmd_floor_shape () {
    grep -cE '^set "MIN_WEBVIEW2_VERSION=[0-9.]+"' "$1"
}

# read the floor literal carried by a consumer's site shape
get_cs_floor () {
    grep -E '^[[:space:]]*public const string MinWebView2Version = "[0-9.]+"' "$1" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

get_cmd_floor () {
    grep -E '^set "MIN_WEBVIEW2_VERSION=[0-9.]+"' "$1" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'
}

# pre-write validation: every consumer must carry exactly one floor site of
# its shape. A missing or duplicated site breaks single-sourcing and fails
# the lane BEFORE any write is kept.
validate_floor_consumers () {
    local f shape
    for f in ${MIN_FLOOR_CONSUMERS}; do
        if [ ! -f "${f}" ]; then
            echo "FAIL: floor consumer missing: ${f}" >&2
            return 1
        fi
        case "${f}" in
            *.cs)  shape="$(count_cs_floor_shape "${f}")" ;;
            *.cmd) shape="$(count_cmd_floor_shape "${f}")" ;;
            *)
                echo "FAIL: unknown floor consumer shape: ${f}" >&2
                return 1
                ;;
        esac
        if [ "${shape}" -ne 1 ]; then
            echo "FAIL: ${f} must carry exactly 1 floor site, found ${shape} — exactly one site per consumer keeps MIN_WEBVIEW2_FLOOR single-sourced; fix the consumer before training" >&2
            return 1
        fi
    done
    return 0
}

# bounded floor rewrite of the C# const site. Anchored at line start —
# never end-of-line (Program.cs may be CRLF). Atomic: sibling tmp + mv,
# tmp removed on every failure branch. Exact-once verification after the
# rewrite: the new-shape count is 1 and no stray site shape remains.
rewrite_cs_floor () {
    local file="$1" new_esc="$2"
    local tmp="${file}.bump-webview2-dep.tmp"
    local new_count stray_count
    sed -E "s@^([[:space:]]*public const string MinWebView2Version = \")[0-9.]+(\")@\\1${new_esc}\\2@" \
        "${file}" > "${tmp}" || { rm -f "${tmp}"; echo "FAIL: floor rewrite failed on ${file}" >&2; return 1; }
    new_count="$(grep -cE "^([[:space:]]*public const string MinWebView2Version = \")${new_esc}(\")" "${tmp}")"
    new_count="${new_count:-0}"
    stray_count="$(grep -E '^[[:space:]]*public const string MinWebView2Version = "' "${tmp}" | grep -vcE "= \"${new_esc}\"")"
    stray_count="${stray_count:-0}"
    if [ "${new_count}" -ne 1 ] || [ "${stray_count}" -ne 0 ]; then
        rm -f "${tmp}"
        echo "FAIL: floor rewrite did not land exactly once on ${file} (new=${new_count} stray=${stray_count})" >&2
        return 1
    fi
    mv -f "${tmp}" "${file}" || { rm -f "${tmp}"; echo "FAIL: atomic move failed on ${file}" >&2; return 1; }
    return 0
}

# bounded floor rewrite of the .cmd set-line site. $2 is the RAW floor
# value (the pattern side needs no user data). Anchored at line start —
# never end-of-line (the launcher files are CRLF). Atomic: sibling tmp +
# mv, tmp removed on every failure branch. Exact-once verification after
# the rewrite.
rewrite_cmd_floor () {
    local file="$1" raw_new="$2"
    local tmp="${file}.bump-webview2-dep.tmp"
    local new_count shape_count
    sed -E 's@^set "MIN_WEBVIEW2_VERSION=[0-9.]+"@set "MIN_WEBVIEW2_VERSION='"${raw_new}"'"@' \
        "${file}" > "${tmp}" || { rm -f "${tmp}"; echo "FAIL: floor rewrite failed on ${file}" >&2; return 1; }
    new_count="$(grep -cF "set \"MIN_WEBVIEW2_VERSION=${raw_new}\"" "${tmp}")"
    new_count="${new_count:-0}"
    shape_count="$(grep -cE '^set "MIN_WEBVIEW2_VERSION=' "${tmp}")"
    shape_count="${shape_count:-0}"
    if [ "${new_count}" -ne 1 ] || [ "${shape_count}" -ne 1 ]; then
        rm -f "${tmp}"
        echo "FAIL: floor rewrite did not land exactly once on ${file} (new=${new_count} shape=${shape_count})" >&2
        return 1
    fi
    mv -f "${tmp}" "${file}" || { rm -f "${tmp}"; echo "FAIL: atomic move failed on ${file}" >&2; return 1; }
    return 0
}

# third dot-part (build) of a 4-part version
version_build () {
    printf '%s\n' "$1" | cut -d. -f3
}

# Fail-closed stale-floor invariant: a floor whose build lags the resolved
# SDK build would let a runtime the SDK itself cannot support route Modern.
# Called BEFORE any write so a stale floor blocks the whole lane.
assert_floor_not_stale () {
    local sdk_build floor_build
    sdk_build="$(version_build "$1")"
    floor_build="$(version_build "${MIN_WEBVIEW2_FLOOR}")"
    if [ "$(( 10#${floor_build} ))" -lt "$(( 10#${sdk_build} ))" ]; then
        echo "FAIL: MIN_WEBVIEW2_FLOOR build (${floor_build}) is older than the resolved WebView2 SDK build (${sdk_build}) — raise MIN_WEBVIEW2_FLOOR in ci/bump-webview2-dep.bash before training" >&2
        return 1
    fi
    return 0
}

# index body: fixture file (offline) or the live NuGet flatcontainer index
fetch_index () {
    if [ -n "${WEBVIEW2_INDEX_FILE:-}" ]; then
        cat "${WEBVIEW2_INDEX_FILE}"
    else
        curl -s --fail --max-time "${CURL_MAX_TIME}" "${NUGET_INDEX_URL}"
    fi
}

# ===== Main program =====

# --print-files: the workflow consumes the file list from here. Prints and
# exits before any validation or mutation. Two csproj (SDK lane) followed
# by the four floor consumers (floor lane) — everything the lane may touch.
if [ "${1:-}" = "--print-files" ]; then
  printf '%s\n' "${GENERATOR_CSPROJ}"
  printf '%s\n' "${INSTALLER_CSPROJ}"
  printf '%s\n' ${MIN_FLOOR_CONSUMERS}
  exit 0
fi

PACKAGE_ID_ESC="$(escape_ere_literal "${PACKAGE_ID}")"

cd "${repo_root}" || exit 1

# The two csproj carry the SAME SDK version — the symmetry is the invariant.
current_version="$(get_package_reference_version "${GENERATOR_CSPROJ}")" || exit 1
installer_version="$(get_package_reference_version "${INSTALLER_CSPROJ}")" || exit 1
if [ "${current_version}" != "${installer_version}" ]; then
  echo "FAIL: WebView2 SDK divergence between the two csproj (generator ${current_version} vs installer ${installer_version}) — fix the pin before training" >&2
  exit 1
fi

raw_index="$(fetch_index)" || {
  echo "FAIL: NuGet flatcontainer index unreachable (${NUGET_INDEX_URL}) — publishing on a known-stale SDK is exactly the bug class this step prevents" >&2
  exit 1
}

# Stable versions only: drop prerelease entries (they carry '-'), then take
# the 4-part numeric maximum.
latest_version="$(printf '%s\n' "${raw_index}" \
  | grep -oE '"[0-9]+(\.[0-9]+)*"' \
  | tr -d '"' \
  | grep -v -- '-' \
  | sort -V \
  | tail -n 1)"
if [ -z "${latest_version}" ]; then
  echo "FAIL: no stable version parsed from the NuGet index" >&2
  exit 1
fi

if version_lt "${latest_version}" "${current_version}"; then
  echo "FAIL: latest stable NuGet version (${latest_version}) is OLDER than the pinned SDK (${current_version}) — never downgrade" >&2
  exit 1
fi

# Fail-closed stale-floor invariant, BEFORE any write (see header): a floor
# build below the resolved SDK build blocks the whole lane.
assert_floor_not_stale "${latest_version}" || exit 1

# Floor single-sourcing: every run (bump or no-op day) rewrites all four
# consumers to MIN_WEBVIEW2_FLOOR — idempotent on the current value, heals
# a drifted consumer. Site shapes are validated first so a missing or
# duplicated site fails the lane before any write is kept.
validate_floor_consumers || exit 1
floor_esc="$(escape_ere_literal "${MIN_WEBVIEW2_FLOOR}")"
for consumer in ${MIN_FLOOR_CONSUMERS}; do
  case "${consumer}" in
    *.cs)  rewrite_cs_floor "${consumer}" "${floor_esc}" || exit 1 ;;
    *.cmd) rewrite_cmd_floor "${consumer}" "${MIN_WEBVIEW2_FLOOR}" || exit 1 ;;
  esac
done

if [ "${latest_version}" = "${current_version}" ]; then
  echo "bump-webview2-dep: WebView2 SDK already current (${current_version})" >&2
  printf '%s\n' "${current_version}"
  exit 0
fi

old_esc="$(escape_ere_literal "${current_version}")"
new_esc="$(escape_ere_literal "${latest_version}")"
for csproj in "${GENERATOR_CSPROJ}" "${INSTALLER_CSPROJ}"; do
  bump_csproj "${csproj}" "${old_esc}" "${new_esc}" || exit 1
  echo "bump-webview2-dep: ${csproj} ${current_version} -> ${latest_version}" >&2
done

# post-verify: both csproj now carry the resolved version
gen_after="$(get_package_reference_version "${GENERATOR_CSPROJ}")" || exit 1
inst_after="$(get_package_reference_version "${INSTALLER_CSPROJ}")" || exit 1
if [ "${gen_after}" != "${latest_version}" ] || [ "${inst_after}" != "${latest_version}" ]; then
  echo "FAIL: post-bump verification failed (generator ${gen_after} / installer ${inst_after}, expected ${latest_version})" >&2
  exit 1
fi

# post-verify: all four consumers carry exactly one floor site equal to the
# single-source constant
for consumer in ${MIN_FLOOR_CONSUMERS}; do
  case "${consumer}" in
    *.cs)  f_sites="$(count_cs_floor_shape "${consumer}")"; f_val="$(get_cs_floor "${consumer}")" ;;
    *.cmd) f_sites="$(count_cmd_floor_shape "${consumer}")"; f_val="$(get_cmd_floor "${consumer}")" ;;
  esac
  if [ "${f_sites}" -ne 1 ] || [ "${f_val}" != "${MIN_WEBVIEW2_FLOOR}" ]; then
    echo "FAIL: post-bump floor verification failed on ${consumer} (sites=${f_sites} value=${f_val:-none}, expected ${MIN_WEBVIEW2_FLOOR})" >&2
    exit 1
  fi
done

printf '%s\n' "${latest_version}"
exit 0
