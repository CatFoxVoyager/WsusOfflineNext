#!/usr/bin/env bash
#
# ci/regen-static-lists.bash — bounded regeneration of the static download lists
#
# Usage: bash ci/regen-static-lists.bash <staging-dir> <static-dir> <dead-file> [--dry-run] [--add] [--min-lines N]
#
# Fusion policy (protects the hand-curated lists):
#   KEEP   — a live URL stays, even when the catalog extraction does not produce it
#   ADD    — OFF by default (calibration proved name-family matching floods the
#            lists with every catalog variant: 237k candidates). Enable with
#            --add only after product/language scoping exists.
#   REMOVE — a URL proven dead (dead-file from ci/validate-links.bash) is removed,
#            even when the catalog still lists it
#
# <staging-dir> must hold update-ids-and-locations-all.txt ("<id>,<url>" pairs),
# produced by the catalog XSLT chain (see ExtractDownloadLinks-all.cmd). A
# missing or implausibly small staging file aborts before any write.

# ===== Configuration =====
readonly script_version="1.0"
min_lines="1000"
dry_run="disabled"
add_policy="disabled"

# ===== Global variables =====
staging_dir=""
static_dir=""
dead_file=""
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
catalog_urls_file=""
report_file=""

# ===== Functions =====

# Family of a URL: file name truncated at its first version digit-run
function url_family ()
{
  local url="$1"
  local name
  name="$(printf '%s\n' "${url}" | sed 's/^.+\///')"
  printf '%s\n' "${name}" | sed 's/[0-9][0-9.].*$//'
}

# ===== Main program =====

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   dry_run="enabled" ;;
    --add)       add_policy="enabled" ;;
    --min-lines) shift; min_lines="$1" ;;
    -*)          echo "regen-static-lists: unknown option $1" >&2; exit 1 ;;
    *)           if [ -z "${staging_dir}" ]; then staging_dir="$1"
                 elif [ -z "${static_dir}" ]; then static_dir="$1"
                 elif [ -z "${dead_file}" ]; then dead_file="$1"
                 fi ;;
  esac
  shift
done

if [ -z "${staging_dir}" ] || [ -z "${static_dir}" ] || [ -z "${dead_file}" ]; then
  echo "usage: bash ci/regen-static-lists.bash <staging-dir> <static-dir> <dead-file> [--dry-run] [--add] [--min-lines N]" >&2
  exit 1
fi

# Fail-closed guards BEFORE any write
catalog_file="${staging_dir}/update-ids-and-locations-all.txt"
if [ ! -f "${catalog_file}" ]; then
  echo "regen-static-lists: staging file missing: ${catalog_file}" >&2
  exit 1
fi
catalog_lines="$(grep -c . "${catalog_file}" || true)"
if [ "${catalog_lines}" -lt "${min_lines}" ]; then
  echo "regen-static-lists: staging implausibly small (${catalog_lines} lines < ${min_lines})" >&2
  exit 1
fi
if [ ! -f "${dead_file}" ]; then
  echo "regen-static-lists: dead file missing: ${dead_file}" >&2
  exit 1
fi

. "${repo_root}/sh/libraries/dos-files.bash"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# Catalog URL set (column 2 of "<id>,<url>"), deduplicated
cut -d ',' -f '2' "${catalog_file}" | grep -E '^https?://' | sed 's/[[:space:]]*$//' | sort -u > "${work_dir}/catalog-urls.txt"
catalog_total="$(grep -c . "${work_dir}/catalog-urls.txt" || true)"
if [ "${catalog_total}" -eq 0 ]; then
  echo "regen-static-lists: no URLs in staging catalog" >&2
  exit 1
fi

# ===== Fusion, one list at a time =====

report_file="${static_dir}/../.regen-report.md"
{
  printf '# Static lists regeneration report\n\n'
  if [ "${add_policy}" = "enabled" ]; then
    printf 'Catalog: %d URLs. Policy: KEEP live, ADD same-family, REMOVE dead.\n\n' "${catalog_total}"
  else
    printf 'Catalog: %d URLs. Policy: KEEP live, REMOVE dead (ADD disabled — use --add).\n\n' "${catalog_total}"
  fi
  printf '| list | kept | added | removed |\n'
  printf '| :--- | ---: | ---: | ---: |\n'
} > "${report_file}"

total_added=0
total_removed=0
added_urls_file="${work_dir}/added-all.txt"
: > "${added_urls_file}"

for list_file in "${static_dir}"/*.txt; do
  [ -e "${list_file}" ] || continue
  name="$(basename "${list_file}")"
  list_lines_file="${work_dir}/lines-${name}"
  list_urls_file="${work_dir}/urls-${name}"
  # full lines ("url" or "url,alias"), and the URL field of each
  cat_dos "${list_file}" | grep -E '^https?://' | sed 's/[[:space:]]*$//' > "${list_lines_file}"
  cut -d',' -f1 "${list_lines_file}" | sort -u > "${list_urls_file}"

  # REMOVE: lines whose URL is proven dead
  awk -F',' 'FILENAME==ARGV[1] { dead[$1]=1; next } ($1 in dead)' \
    "${dead_file}" "${list_lines_file}" > "${work_dir}/removed.txt" || true
  # KEEP: the other lines, alias field preserved
  awk -F',' 'FILENAME==ARGV[1] { dead[$1]=1; next } !($1 in dead)' \
    "${dead_file}" "${list_lines_file}" > "${work_dir}/kept.txt" || true

  # ADD: catalog URLs of a live family of this list, unknown to the list,
  # never a URL from the dead set
  awk -F/ '{ print $NF }' "${list_urls_file}" \
    | sed 's/[0-9][0-9.].*$//' | sort -u > "${work_dir}/families.txt"
  if [ "${add_policy}" = "disabled" ]; then
    : > "${work_dir}/candidates.txt"
  elif [ -s "${work_dir}/families.txt" ]; then
    awk -F/ '{ print $NF "\t" $0 }' "${work_dir}/catalog-urls.txt" \
      | awk -F'\t' 'NR==FNR { fam[$1]=1; next } { n=$1; sub(/[0-9][0-9.].*$/, "", n); if (n in fam) print $2 }' \
        "${work_dir}/families.txt" - \
      | grep -Fx -v -f "${list_urls_file}" \
      | grep -Fx -v -f "${dead_file}" \
      | sort -u > "${work_dir}/candidates.txt" || true
  else
    : > "${work_dir}/candidates.txt"
  fi

  kept_n="$(grep -c . "${work_dir}/kept.txt" || true)"
  added_n="$(grep -c . "${work_dir}/candidates.txt" || true)"
  removed_n="$(grep -c . "${work_dir}/removed.txt" || true)"
  total_added=$(( total_added + added_n ))
  total_removed=$(( total_removed + removed_n ))
  cat "${work_dir}/candidates.txt" >> "${added_urls_file}"

  printf '| %s | %d | %d | %d |\n' "${name}" "${kept_n}" "${added_n}" "${removed_n}" >> "${report_file}"

  if [ "${dry_run}" = "enabled" ]; then
    continue
  fi

  if [ "${added_n}" -gt 0 ] || [ "${removed_n}" -gt 0 ]; then
    cat "${work_dir}/kept.txt" "${work_dir}/candidates.txt" | awk '{ printf "%s\r\n", $0 }' > "${list_file}"
  fi
done

# Disposition of catalog URLs: added / already listed somewhere / dead-excluded / no matching family
cat "${work_dir}"/urls-*.txt > "${work_dir}/all-listed.txt" || true
sort -u "${work_dir}/all-listed.txt" -o "${work_dir}/all-listed.txt"
added_unique="$(sort -u "${added_urls_file}" | grep -c . || true)"
already_n="$(grep -Fx -f "${work_dir}/all-listed.txt" "${work_dir}/catalog-urls.txt" | grep -c . || true)"
dead_excl_n="$(grep -Fx -f "${dead_file}" "${work_dir}/catalog-urls.txt" | grep -c . || true)"
ignored=$(( catalog_total - added_unique - already_n - dead_excl_n ))
[ "${ignored}" -lt 0 ] && ignored=0
{
  printf '\n**Total:** %d added, %d removed. Catalog disposition: %d already listed, %d dead-excluded, %d no matching family.\n' "${total_added}" "${total_removed}" "${already_n}" "${dead_excl_n}" "${ignored}"
} >> "${report_file}"

echo "regen-static-lists: ${total_added} added, ${total_removed} removed, ${ignored} no-family — report: ${report_file}"
[ "${dry_run}" = "enabled" ] && echo "regen-static-lists: dry-run — no list was written"
exit 0
