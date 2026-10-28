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

# ===== Configuration =====
readonly script_version="1.1"
MKISOFS_URL="https://gitlab.com/wsusoffline/wsusoffline-sdd/-/raw/master/mkisofs.exe"

# ===== Global variables =====
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wget_bin=""
unzip_bin=""

# ===== Functions =====

function resolve_tools ()
{
  if [ -x "${repo_root}/bin/wget64.exe" ]; then wget_bin="${repo_root}/bin/wget64.exe";
  else wget_bin="$(command -v wget || true)"; fi
  if [ -x "${repo_root}/bin/unzip.exe" ]; then unzip_bin="${repo_root}/bin/unzip.exe";
  else unzip_bin="$(command -v unzip || true)"; fi
  [ -n "${wget_bin}" ] || { echo "fetch-release-helpers: no wget found" >&2; exit 1; }
  [ -n "${unzip_bin}" ] || { echo "fetch-release-helpers: no unzip found" >&2; exit 1; }
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
  case "${zip_name}" in
    AutoLogon.zip) dest="client/bin" ;;
    *)             dest="bin" ;;
  esac
  "${unzip_bin}" -o -q "bin/${zip_name}" -x "Eula.txt" -d "${dest}" \
    || { echo "fetch-release-helpers: unzip failed: ${zip_name}" >&2; exit 1; }
done < <(grep -E '^https?://' static/StaticDownloadLinks-sysinternals.txt | cut -d',' -f1)

# The client installer unpacks zip-packaged updates with its own unzip copy
if [ -f bin/unzip.exe ] && [ ! -f client/bin/unzip.exe ]; then
  cp bin/unzip.exe client/bin/unzip.exe
  echo "fetch-release-helpers: bin/unzip.exe -> client/bin/unzip.exe"
fi

if [ ! -f bin/mkisofs.exe ]; then
  echo "fetch-release-helpers: mkisofs.exe"
  "${wget_bin}" -q -O bin/mkisofs.exe "${MKISOFS_URL}" \
    || { echo "fetch-release-helpers: mkisofs download failed" >&2; exit 1; }
fi

echo "fetch-release-helpers: done — client/bin/Autologon.exe: $([ -f client/bin/Autologon.exe ] && echo OK || echo MISSING), client/bin/unzip.exe: $([ -f client/bin/unzip.exe ] && echo OK || echo MISSING), bin/mkisofs.exe: $([ -f bin/mkisofs.exe ] && echo OK || echo MISSING)"
[ -f client/bin/Autologon.exe ] && [ -f client/bin/unzip.exe ] && [ -f bin/mkisofs.exe ]
