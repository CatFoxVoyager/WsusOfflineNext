#!/usr/bin/env bash
#
# ci/extract-catalog.bash — download the WSUS catalog and extract update-id/URL pairs
#
# Usage: bash ci/extract-catalog.bash <work-dir> [--download]
#
# Produces <work-dir>/update-ids-and-locations-all.txt ("<id>,<url>" pairs) from
# wsusscn2.cab, using the repo's own tools (bin/wget64.exe, expand.exe,
# cmd/XSLT.vbs, xslt/extract-update-cab-exe-ids-and-locations.xsl, bin/gsort.exe).
# NOTE: unlike ExtractDownloadLinks-all.cmd this output is NOT filtered through
# the revision/file-id join chain — it carries superseded URLs too, which only
# affects the disposition counters (ADD is off; REMOVE is dead-file-driven).
# With --download (or when the cab is missing), the catalog is fetched first.

# ===== Configuration =====
readonly script_version="1.0"

# ===== Global variables =====
work_dir=""
download="disabled"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# ===== Functions =====

function resolve_wget ()
{
  if [ -x "${repo_root}/bin/wget64.exe" ]; then
    printf '%s\n' "${repo_root}/bin/wget64.exe"
  elif [ -x "${repo_root}/bin/wget.exe" ]; then
    printf '%s\n' "${repo_root}/bin/wget.exe"
  else
    command -v wget || true
  fi
}

# ===== Main program =====

while [ $# -gt 0 ]; do
  case "$1" in
    --download) download="enabled" ;;
    -*)         echo "extract-catalog: unknown option $1" >&2; exit 1 ;;
    *)          if [ -z "${work_dir}" ]; then work_dir="$1" ; fi ;;
  esac
  shift
done

if [ -z "${work_dir}" ]; then
  echo "usage: bash ci/extract-catalog.bash <work-dir> [--download]" >&2
  exit 1
fi
mkdir -p "${work_dir}"

. "${repo_root}/sh/libraries/dos-files.bash"
WGET="$(resolve_wget)"
[ -n "${WGET}" ] || { echo "extract-catalog: no wget found" >&2; exit 1; }

cab="${work_dir}/wsusscn2.cab"
if [ "${download}" = "enabled" ] || [ ! -f "${cab}" ]; then
  echo "extract-catalog: downloading wsusscn2.cab ..."
  "${WGET}" -N -q -P "${work_dir}" -i "${repo_root}/static/StaticDownloadLinks-wsus.txt" \
    || { echo "extract-catalog: catalog download failed" >&2; exit 1; }
fi
[ -f "${cab}" ] || { echo "extract-catalog: cab not found: ${cab}" >&2; exit 1; }

echo "extract-catalog: expanding cab ..."
rm -f "${work_dir}/package.cab" "${work_dir}/package.xml"
"${SYSTEMROOT}/System32/expand.exe" "${cab}" -F:package.cab "${work_dir}" \
  || { echo "extract-catalog: expand cab failed" >&2; exit 1; }
"${SYSTEMROOT}/System32/expand.exe" "${work_dir}/package.cab" "${work_dir}/package.xml" \
  || { echo "extract-catalog: expand package.cab failed" >&2; exit 1; }
rm -f "${work_dir}/package.cab"

echo "extract-catalog: XSLT extraction (several minutes) ..."
"${SYSTEMROOT}/System32/cscript.exe" //Nologo //B //E:vbs \
  "${repo_root}/cmd/XSLT.vbs" \
  "${work_dir}/package.xml" \
  "${repo_root}/xslt/extract-update-cab-exe-ids-and-locations.xsl" \
  "${work_dir}/ids-and-locations-unsorted.txt" \
  || { echo "extract-catalog: XSLT failed" >&2; exit 1; }

"${repo_root}/bin/gsort.exe" -u -T "${work_dir}" \
  "${work_dir}/ids-and-locations-unsorted.txt" \
  > "${work_dir}/update-ids-and-locations-all.txt" \
  || { echo "extract-catalog: sort failed" >&2; exit 1; }
rm -f "${work_dir}/ids-and-locations-unsorted.txt"

lines="$(grep -c . "${work_dir}/update-ids-and-locations-all.txt" || true)"
echo "extract-catalog: done — ${lines} id/url pairs in ${work_dir}/update-ids-and-locations-all.txt"
[ "${lines}" -gt 0 ] || exit 1
exit 0
