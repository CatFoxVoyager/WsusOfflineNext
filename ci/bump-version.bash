#!/usr/bin/env bash
#
# ci/bump-version.bash — substitute the application version across the repo
#
# Usage: bash ci/bump-version.bash <new-version>   (e.g. 2026.11.0)
#
# The old version is read from the single source of truth
# (cmd/DownloadUpdates.cmd, "set WSUSOFFLINE_VERSION=X.Y.Z (b...)"). The
# 17-file matrix is the one committed in 339f600. The build tag "(b2026.10)"
# is version-independent and must not move. Exits 1 unless exactly 32
# substitutions land in exactly 17 files.

# ===== Configuration =====
readonly script_version="1.0"
VERSION_FILES="
cmd/DownloadUpdates.cmd
client/cmd/DoUpdate.cmd
client/UpdateInstaller.au3
client/UpdateInstallerLauncher.au3
UpdateGenerator.au3
UpdateGeneratorLauncher.au3
CompileModernApps.cmd
README.md
sh/download-updates.bash
sh/update-generator.bash
src-modern/generator/host/UpdateGenerator.csproj
src-modern/installer/host/UpdateInstaller.csproj
src-modern/generator/package.json
src-modern/installer/package.json
src-modern/generator/src/App.tsx
src-modern/installer/src/App.tsx
static/SelfUpdateVersion-this.txt
"

# ===== Global variables =====
new_version=""
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
old_version=""

# ===== Functions =====

# Old version from the single source of truth
function read_old_version ()
{
  old_version="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+' "${repo_root}/cmd/DownloadUpdates.cmd" \
    | head -1 | cut -d'=' -f2)"
  if [ -z "${old_version}" ]; then
    echo "bump-version: cannot read current version from cmd/DownloadUpdates.cmd" >&2
    exit 1
  fi
}

# ===== Main program =====

if [ $# -ne 1 ] || ! printf '%s' "$1" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "usage: bash ci/bump-version.bash <new-version>   (e.g. 2026.11.0)" >&2
  exit 1
fi
new_version="$1"

read_old_version
if [ "${old_version}" = "${new_version}" ]; then
  echo "bump-version: version already ${new_version}" >&2
  exit 1
fi

cd "${repo_root}" || exit 1
old_re="${old_version//./\\.}"
total_before=0
total_after=0
files_touched=0

printf '%-55s %s -> %s\n' "file" "${old_version}" "${new_version}"
for f in ${VERSION_FILES}; do
  if [ ! -f "${f}" ]; then
    echo "bump-version: MISSING file in version matrix: ${f}" >&2
    exit 1
  fi
  before="$(grep -c "${old_re}" "${f}" || true)"
  if [ "${before}" -gt 0 ]; then
    sed -i "s/${old_re}/${new_version}/g" "${f}"
  fi
  after="$(grep -c "${new_version}" "${f}" || true)"
  total_before=$(( total_before + before ))
  total_after=$(( total_after + after ))
  if [ "${before}" -gt 0 ]; then
    files_touched=$(( files_touched + 1 ))
  fi
  printf '%-55s %4d -> %4d\n' "${f}" "${before}" "${after}"
done

echo "TOTAL: ${total_before} -> ${total_after} substitutions in ${files_touched} files"
if [ "${total_before}" -ne 32 ] || [ "${total_after}" -ne 32 ] || [ "${files_touched}" -ne 17 ]; then
  echo "bump-version: EXPECTED 32 substitutions across 17 files — aborting (tree modified, run git checkout -- .)" >&2
  exit 1
fi
echo "bump-version: OK — version ${old_version} -> ${new_version}"
exit 0
