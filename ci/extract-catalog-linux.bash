#!/usr/bin/env bash
#
# ci/extract-catalog-linux.bash — extract update-id/URL pairs from wsusscn2.cab (Linux)
#
# Usage: bash ci/extract-catalog-linux.bash <work-dir> [--download]
#
# Linux counterpart of ci/extract-catalog.bash: cabextract + xsltproc instead of
# expand.exe + cscript/XSLT.vbs. Produces the same
# <work-dir>/update-ids-and-locations-all.txt ("<id>,<url>" pairs).

# ===== Configuration =====
readonly script_version="1.0"

# ===== Global variables =====
work_dir=""
download="disabled"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# ===== Main program =====

while [ $# -gt 0 ]; do
  case "$1" in
    --download) download="enabled" ;;
    -*)         echo "extract-catalog-linux: unknown option $1" >&2; exit 1 ;;
    *)          if [ -z "${work_dir}" ]; then work_dir="$1" ; fi ;;
  esac
  shift
done

if [ -z "${work_dir}" ]; then
  echo "usage: bash ci/extract-catalog-linux.bash <work-dir> [--download]" >&2
  exit 1
fi
mkdir -p "${work_dir}"

cab="${work_dir}/wsusscn2.cab"
if [ "${download}" = "enabled" ] || [ ! -f "${cab}" ]; then
  echo "extract-catalog-linux: downloading wsusscn2.cab ..."
  wget -N -q -P "${work_dir}" -i "${repo_root}/static/StaticDownloadLinks-wsus.txt" \
    || { echo "extract-catalog-linux: catalog download failed" >&2; exit 1; }
fi
[ -f "${cab}" ] || { echo "extract-catalog-linux: cab not found: ${cab}" >&2; exit 1; }

echo "extract-catalog-linux: extracting cab ..."
rm -f "${work_dir}/package.cab" "${work_dir}/package.xml"
cabextract -q -d "${work_dir}" "${cab}" \
  || { echo "extract-catalog-linux: cabextract failed" >&2; exit 1; }
[ -f "${work_dir}/package.cab" ] || { echo "extract-catalog-linux: package.cab not produced" >&2; exit 1; }
cabextract -q -d "${work_dir}" "${work_dir}/package.cab" \
  || { echo "extract-catalog-linux: inner cabextract failed" >&2; exit 1; }
rm -f "${work_dir}/package.cab"
[ -f "${work_dir}/package.xml" ] || { echo "extract-catalog-linux: package.xml not produced" >&2; exit 1; }

echo "extract-catalog-linux: XSLT extraction (several minutes) ..."
xsltproc -o "${work_dir}/ids-and-locations-unsorted.txt" \
  "${repo_root}/xslt/extract-update-cab-exe-ids-and-locations.xsl" \
  "${work_dir}/package.xml" \
  || { echo "extract-catalog-linux: xsltproc failed" >&2; exit 1; }

sort -u -o "${work_dir}/update-ids-and-locations-all.txt" "${work_dir}/ids-and-locations-unsorted.txt"
rm -f "${work_dir}/ids-and-locations-unsorted.txt"

lines="$(grep -c . "${work_dir}/update-ids-and-locations-all.txt" || true)"
echo "extract-catalog-linux: done — ${lines} id/url pairs in ${work_dir}/update-ids-and-locations-all.txt"
[ "${lines}" -gt 0 ] || exit 1
exit 0
