#!/usr/bin/env bash
#
# ci/fetch-release-helpers.bash — fetch the runtime helpers a fresh checkout lacks
#
# Usage: bash ci/fetch-release-helpers.bash
#
# A git checkout ships the tracked tools (client/bin/hashdeep*, IfAdmin*,
# vendored bin/ tools) but NOT the runtime-downloaded extras: the Sysinternals
# zips with their extracted exes and mkisofs.exe. This script fetches exactly
# those, from the same sources the pipeline itself uses, so a CI-built release
# zip matches a dev-machine-built one.
#
# Canonical layout (mirrors sh/download-updates-tasks/20-get-sysinternals-helpers.bash):
#   bin/AutoLogon.zip, Sigcheck.zip, Streams.zip   — the archives
#   bin/sigcheck*.exe, bin/streams*.exe            — client-side signature checks
#   client/bin/Autologon*.exe                      — automatic post-reboot relaunch
#   client/bin/unzip.exe                           — client-side zip unpacking
#   bin/mkisofs.exe                                — ISO creation
#
# Known parity divergence (accepted): bin/odt/setup.exe is NOT fetched here —
# cmd/DownloadOfficeC2R.cmd downloads it on first use, so the release zip ships
# without it and the client pipeline self-heals exactly as on a dev machine.
#
# Integrity (CIWF-06, finding IN-04): every downloaded helper is verified
# against the pinned SHA256 list in ci/release-helper-hashes.sha256
# (sha256sum format: 64 hex chars, two spaces, basename) BEFORE anything is
# unpacked or integrated. The pins were seeded from fresh upstream downloads
# (2026-10-29); the mkisofs pin was cross-checked with certutil.
#
# Atomic download (CISC-04, finding WR-12): bin/mkisofs.exe is fetched into a
# temp file and moved into place only after the transfer succeeded - a
# mid-transfer failure never leaves a partial that the existence guard would
# bless on the next run.
#
# Refresh procedure: when verification fails the script exits 1 and prints
# both the expected pin and the observed digest. Verify the new build's
# provenance from the official source (download.sysinternals.com for the
# Sysinternals archives, gitlab.com/wsusoffline/wsusoffline-sdd for
# mkisofs.exe), then update the pin in a dedicated commit. Until then the
# release stays red: the workflow's Fetch runtime helpers step
# (monthly-updates.yml) fails before MakeRelease runs, so a modified,
# corrupted or unpinned helper never enters the published zip.

# ===== Configuration =====
readonly script_version="1.3"
MKISOFS_URL="https://gitlab.com/wsusoffline/wsusoffline-sdd/-/raw/master/mkisofs.exe"
readonly hashes_file="ci/release-helper-hashes.sha256"

# ===== Global variables =====
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wget_bin=""
unzip_bin=""
sha256_bin=""

# ===== Functions =====

function resolve_tools ()
{
  if [ -x "${repo_root}/bin/wget64.exe" ]; then wget_bin="${repo_root}/bin/wget64.exe";
  else wget_bin="$(command -v wget || true)"; fi
  if [ -x "${repo_root}/bin/unzip.exe" ]; then unzip_bin="${repo_root}/bin/unzip.exe";
  else unzip_bin="$(command -v unzip || true)"; fi
  [ -n "${wget_bin}" ] || { echo "fetch-release-helpers: no wget found" >&2; exit 1; }
  [ -n "${unzip_bin}" ] || { echo "fetch-release-helpers: no unzip found" >&2; exit 1; }
  sha256_bin="$(command -v sha256sum || true)"
  [ -n "${sha256_bin}" ] || { echo "fetch-release-helpers: no sha256sum found" >&2; exit 1; }
}

# CIWF-06: fail-closed integrity gate. One argument: the artifact basename as
# pinned in the sidecar. A missing sidecar and a missing pin take the same
# failure path: the helper is refused, never shipped unverified.
function verify_helper_hash ()
{
  local artifact_name="$1"
  local hashes_path="${repo_root}/${hashes_file}"
  local expected_pin=""
  local observed_hash=""

  if [ -f "${hashes_path}" ]; then
    expected_pin="$(tr -d '\r' < "${hashes_path}" | grep -E "^[0-9a-f]{64}  ${artifact_name}\$" | cut -d' ' -f1)"
  fi
  if [ -z "${expected_pin}" ]; then
    echo "fetch-release-helpers: no SHA256 pin for ${artifact_name} - refusing an unpinned helper" >&2
    exit 1
  fi
  observed_hash="$("${sha256_bin}" "bin/${artifact_name}" | cut -d' ' -f1)"
  if [ "${observed_hash}" != "${expected_pin}" ]; then
    echo "fetch-release-helpers: SHA256 MISMATCH for ${artifact_name}" >&2
    echo "  expected: ${expected_pin}" >&2
    echo "  observed: ${observed_hash}" >&2
    echo "  if upstream rotated this helper, verify the new build's provenance from the official source, then update the pin in a dedicated commit" >&2
    exit 1
  fi
  echo "fetch-release-helpers: SHA256 OK ${artifact_name}"
}

# ===== Main program =====

resolve_tools
cd "${repo_root}" || exit 1
mkdir -p bin client/bin

# Sysinternals zips -> bin/; AutoLogon unpacks into client/bin (canonical),
# Sigcheck and Streams unpack into bin/
while IFS= read -r url; do
  [ -n "${url}" ] || continue
  zip_name="$(basename "${url}")"
  echo "fetch-release-helpers: ${url} -> bin/${zip_name}"
  "${wget_bin}" -N -q -P bin "${url}" \
    || { echo "fetch-release-helpers: download failed: ${url}" >&2; exit 1; }
  # CIWF-06: a tampered archive must never be unpacked - gate before the unzip
  verify_helper_hash "${zip_name}"
  case "${zip_name}" in
    AutoLogon.zip) dest="client/bin" ;;
    *)             dest="bin" ;;
  esac
  "${unzip_bin}" -o -q "bin/${zip_name}" -x "Eula.txt" -d "${dest}" \
    || { echo "fetch-release-helpers: unzip failed: ${zip_name}" >&2; exit 1; }
# The URL list is read CR-normalised at this one site: .gitattributes
# materialises *.txt as CRLF on a fresh checkout, and a CR surviving in the
# URL corrupts zip_name (the download would even land as a CR-named file in
# bin/) and silently misses every SHA256 pin ("refusing an unpinned helper")
# under a strict (Linux) grep - ubuntu-latest, run 41012438351.
done < <(tr -d '\r' < static/StaticDownloadLinks-sysinternals.txt | grep -E '^https?://' | cut -d',' -f1)

# The client installer unpacks zip-packaged updates with its own unzip copy
if [ -f bin/unzip.exe ] && [ ! -f client/bin/unzip.exe ]; then
  cp bin/unzip.exe client/bin/unzip.exe
  echo "fetch-release-helpers: bin/unzip.exe -> client/bin/unzip.exe"
fi

if [ ! -f bin/mkisofs.exe ]; then
  echo "fetch-release-helpers: mkisofs.exe"
  # CISC-04 (WR-12): wget -O truncates the target BEFORE the transfer, so a
  # mid-transfer failure used to leave a partial that the [ ! -f ] guard would
  # bless forever. Download into a sibling temp file and move atomically; every
  # failure path removes the temp BEFORE exiting (fail-closed).
  tmp_bin="$(mktemp "${repo_root}/bin/mkisofs.exe.XXXXXX")" \
    || { echo "fetch-release-helpers: mkisofs: cannot create temp file" >&2; exit 1; }
  "${wget_bin}" -q -O "${tmp_bin}" "${MKISOFS_URL}" \
    || { rm -f "${tmp_bin}"; echo "fetch-release-helpers: mkisofs download failed" >&2; exit 1; }
  # early-detection net: an empty or non-PE stream is refused before the move.
  # The SHA256 pin below stays the integrity authority (CIWF-06) - these checks
  # catch a dead or wrong-content stream before it is ever installed.
  if [ ! -s "${tmp_bin}" ]; then
    rm -f "${tmp_bin}"
    echo "fetch-release-helpers: mkisofs: empty download" >&2
    exit 1
  fi
  if [ "$(head -c 2 "${tmp_bin}")" != "MZ" ]; then
    rm -f "${tmp_bin}"
    echo "fetch-release-helpers: mkisofs: not a PE binary (missing MZ header)" >&2
    exit 1
  fi
  mv -f "${tmp_bin}" bin/mkisofs.exe
fi

# CIWF-06: hash-gate mkisofs.exe in BOTH cases - freshly downloaded above or
# previously cached (the existence-only guard would otherwise bless the cache).
verify_helper_hash "mkisofs.exe"

echo "fetch-release-helpers: done — client/bin/Autologon.exe: $([ -f client/bin/Autologon.exe ] && echo OK || echo MISSING), client/bin/unzip.exe: $([ -f client/bin/unzip.exe ] && echo OK || echo MISSING), bin/mkisofs.exe: $([ -f bin/mkisofs.exe ] && echo OK || echo MISSING)"
[ -f client/bin/Autologon.exe ] && [ -f client/bin/unzip.exe ] && [ -f bin/mkisofs.exe ]
