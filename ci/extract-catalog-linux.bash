#!/usr/bin/env bash
#
# ci/extract-catalog-linux.bash — extract update-id/URL pairs from wsusscn2.cab (Linux)
#
# Usage: bash ci/extract-catalog-linux.bash <work-dir> [--download]
#
# Linux counterpart of ci/extract-catalog.bash: cabextract + xsltproc instead of
# expand.exe + cscript/XSLT.vbs. Produces the same
# <work-dir>/update-ids-and-locations-all.txt ("<id>,<url>" pairs).
#
# The final sort is guarded like the Windows variant (extract-catalog.bash:81-85)
# and ids-and-locations-unsorted.txt is only deleted AFTER the sort succeeded
# AND the extraction is proven non-empty - a failed or empty stage keeps the
# minutes of XSLT output available for diagnosis (CISC-05, findings WR-13
# and WR-03).

# ===== Configuration =====
readonly script_version="1.1"

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

# Guarded sort, parity with the Windows variant's gsort -T: a failed sort must
# never fall through to the rm below (WR-13 - the intermediate is minutes of
# XSLT and is not replayable without re-downloading the catalog)
sort -u -T "${work_dir}" -o "${work_dir}/update-ids-and-locations-all.txt" "${work_dir}/ids-and-locations-unsorted.txt" \
  || { echo "extract-catalog-linux: sort failed" >&2; exit 1; }

# Diagnose BEFORE destroying the intermediate: count and abort FIRST (WR-03 —
# the rm used to run before this check, so the "sort succeeded but empty"
# case destroyed the minutes of XSLT output it exists to diagnose), then
# remove the intermediate only once the extraction is proven non-empty
lines="$(grep -c . "${work_dir}/update-ids-and-locations-all.txt" || true)"
[ "${lines}" -gt 0 ] || { echo "extract-catalog-linux: empty extraction — intermediate kept for diagnosis: ${work_dir}/ids-and-locations-unsorted.txt" >&2; exit 1; }
echo "extract-catalog-linux: done — ${lines} id/url pairs in ${work_dir}/update-ids-and-locations-all.txt"
rm -f "${work_dir}/ids-and-locations-unsorted.txt"
exit 0
