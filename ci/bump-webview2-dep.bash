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
# Fail-closed policy (deliberate): an unreachable NuGet index, a csproj
# divergence, an unparseable index, or a would-be downgrade all exit 1 —
# publishing a release while knowingly carrying a stale SDK is exactly the
# bug class this step exists to prevent, so the step MUST fail the train.
# Equality is the daily no-op: nothing is written, exit 0.
#
# WEBVIEW2_INDEX_FILE (path to a JSON document) replaces the curl call —
# the offline mode the fixture battery uses; it shares the same downstream
# code path as a live index response.

# ===== Configuration =====
readonly script_version="1.0"
readonly PACKAGE_ID="Microsoft.Web.WebView2"
readonly NUGET_INDEX_URL="https://api.nuget.org/v3-flatcontainer/microsoft.web.webview2/index.json"
readonly CURL_MAX_TIME=30
readonly GENERATOR_CSPROJ="src-modern/generator/host/UpdateGenerator.csproj"
readonly INSTALLER_CSPROJ="src-modern/installer/host/UpdateInstaller.csproj"

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
# exits before any validation or mutation.
if [ "${1:-}" = "--print-files" ]; then
  printf '%s\n' "${GENERATOR_CSPROJ}"
  printf '%s\n' "${INSTALLER_CSPROJ}"
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

printf '%s\n' "${latest_version}"
exit 0
