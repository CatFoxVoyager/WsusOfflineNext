#!/usr/bin/env bash
#
# ci/fetch-release-helpers.bash — fetch the runtime helpers a fresh checkout lacks
#
# Usage: bash ci/fetch-release-helpers.bash [--skip-if-present]
#
# A git checkout ships the tracked tools (client/bin/*, vendored bin/ tools) but
# NOT the runtime-downloaded extras of bin/: the Sysinternals zips with their
# extracted exes (AutoLogon, Sigcheck, Streams — the client installer needs them)
# and mkisofs.exe (ISO creation). This script fetches exactly those, from the same
# sources the pipeline itself uses (static/StaticDownloadLinks-sysinternals.txt,
# the wsusoffline-sdd GitLab mirror), so a CI-built release zip matches a
# dev-machine-built one.

# ===== Configuration =====
readonly script_version="1.0"
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
mkdir -p bin

# Sysinternals zips -> bin/, then extract next to them (the names the pipeline uses)
while IFS= read -r url; do
  [ -n "${url}" ] || continue
  zip_name="$(basename "${url}")"
  echo "fetch-release-helpers: ${url} -> bin/${zip_name}"
  "${wget_bin}" -N -q -P bin "${url}" \
    || { echo "fetch-release-helpers: download failed: ${url}" >&2; exit 1; }
  "${unzip_bin}" -o -q "bin/${zip_name}" -d bin \
    || { echo "fetch-release-helpers: unzip failed: ${zip_name}" >&2; exit 1; }
done < <(grep -E '^https?://' static/StaticDownloadLinks-sysinternals.txt | cut -d',' -f1)

if [ ! -f bin/mkisofs.exe ]; then
  echo "fetch-release-helpers: mkisofs.exe"
  "${wget_bin}" -q -O bin/mkisofs.exe "${MKISOFS_URL}" \
    || { echo "fetch-release-helpers: mkisofs download failed" >&2; exit 1; }
fi

echo "fetch-release-helpers: bin/ helpers ready ($(ls bin | wc -l) files)"
exit 0
