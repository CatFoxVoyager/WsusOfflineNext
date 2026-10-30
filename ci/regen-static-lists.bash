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
#            --add only after product/language scoping exists. A family is the
#            file name minus its extension minus its final digit-run
#            (last-version-block semantics); an all-digit file name has no
#            family and matches nothing.
#   REMOVE — a URL proven dead (dead-file from ci/validate-links.bash) is removed,
#            even when the catalog still lists it
#
#   PRESERVE — non-URL lines (comments, blank lines) pass through the rewrite
#   verbatim: the hand-curated lists carry inline documentation a rewrite must
#   not raze (client/static files carry ~192 non-URL lines each).
#
#   The dead-file is CR-normalised before use (one cat_dos site, after work_dir):
#   .gitattributes materialises *.txt as CRLF on a fresh checkout and a strict
#   awk keeps that CR in the record, which silently disabled REMOVE and lied to
#   the report (ubuntu-latest, run 40991443841).
#
#   The report only exists in the tree on a real run: it is written to the
#   work dir and moved to ${static_dir}/../.regen-report.md at the end, so a
#   --dry-run leaves no file behind (the work dir dies with the EXIT trap).
#
# <staging-dir> must hold update-ids-and-locations-all.txt ("<id>,<url>" pairs),
# produced by the catalog XSLT chain (see ExtractDownloadLinks-all.cmd). A
# missing or implausibly small staging file aborts before any write.

# ===== Configuration =====
readonly script_version="1.2"
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

# Family of a URL: the file name with its extension removed, then its final
# digit-run removed — last-version-block semantics (IN-07 settled here: the
# truncation is anchored at the END of the name, not at its first digit, so
# windows6.1-kb4012215-v2 and windows6.1-kb4012218-v2 are DIFFERENT families
# while prod-v1.0 and prod-v2.0 are the same one). A name that becomes empty
# (all-digit file name) has NO family and emits nothing: an empty family must
# never join the matching set (CISC-07). Reads stdin, writes stdout — the one
# implementation of the family semantics, used on both matching sides (CISC-06).
function family_of ()
{
  sed -e 's|.*/||' -e 's/\.[^.]*$//' -e 's/[0-9][0-9.]*$//' -e '/^$/d'
}

# ===== Main program =====

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)   dry_run="enabled" ;;
    --add)       add_policy="enabled" ;;
    --min-lines) [ $# -ge 2 ] || { echo "regen-static-lists: --min-lines requires a numeric argument" >&2; exit 1; }
                 shift; min_lines="$1" ;;
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
case "${min_lines}" in
  ''|*[!0-9]*)
    echo "regen-static-lists: --min-lines must be a non-negative integer (got ${min_lines})" >&2
    exit 1
    ;;
esac
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
# static-dir guard: no list to fuse — abort before any write (CISC-09, mirror
# of the validate-links list_count check); the fusion loop is fail-open by
# construction (glob + continue) so the empty case must be caught here
list_count=0
for list_file in "${static_dir}"/*.txt; do
  [ -e "${list_file}" ] && list_count=$(( list_count + 1 ))
done
if [ "${list_count}" -eq 0 ]; then
  echo "regen-static-lists: no lists under ${static_dir}" >&2
  exit 1
fi

. "${repo_root}/sh/libraries/dos-files.bash"

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

# The dead file is read exactly once, here, CR-normalised: every reader below
# consumes the clean copy, never the raw file.
cat_dos "${dead_file}" > "${work_dir}/dead-clean.txt"

# Catalog URL set (column 2 of "<id>,<url>"), deduplicated
cut -d ',' -f '2' "${catalog_file}" | grep -E '^https?://' | sed 's/[[:space:]]*$//' | sort -u > "${work_dir}/catalog-urls.txt"
catalog_total="$(grep -c . "${work_dir}/catalog-urls.txt" || true)"
if [ "${catalog_total}" -eq 0 ]; then
  echo "regen-static-lists: no URLs in staging catalog" >&2
  exit 1
fi

# Catalog families, precomputed once: "<family>\t<url>" for every catalog URL,
# entries with no family omitted — the ADD side of the family matching (CISC-06)
if [ "${add_policy}" = "enabled" ]; then
  family_of < "${work_dir}/catalog-urls.txt" > "${work_dir}/catalog-family-names.txt"
  paste "${work_dir}/catalog-family-names.txt" "${work_dir}/catalog-urls.txt" \
    | awk -F'\t' '$1 != ""' > "${work_dir}/catalog-families.txt" \
    || { echo "regen-static-lists: catalog family precompute failed" >&2; exit 1; }
fi

# ===== Fusion, one list at a time =====

report_file="${work_dir}/regen-report.md"
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
  # full lines ("url" or "url,alias", plus any non-URL line: comments and
  # blank lines must survive the rewrite verbatim), and the URL field of the
  # URL lines only — familles and disposition must never see a non-URL line
  cat_dos "${list_file}" | sed 's/[[:space:]]*$//' > "${list_lines_file}"
  grep -E '^https?://' "${list_lines_file}" | cut -d',' -f1 | sort -u > "${list_urls_file}"

  # REMOVE: lines whose URL is proven dead
  awk -F',' 'FILENAME==ARGV[1] { dead[$1]=1; next } ($1 in dead)' \
    "${work_dir}/dead-clean.txt" "${list_lines_file}" > "${work_dir}/removed.txt" || true
  # KEEP: the other lines, alias field preserved
  awk -F',' 'FILENAME==ARGV[1] { dead[$1]=1; next } !($1 in dead)' \
    "${work_dir}/dead-clean.txt" "${list_lines_file}" > "${work_dir}/kept.txt" || true

  # ADD: catalog URLs of a live family of this list, unknown to the list,
  # never a URL from the dead set — the list side of the family matching
  # (families of this list via the one family_of implementation), matched
  # against the precomputed catalog families with the FILENAME==ARGV[1]
  # idiom: an empty families file can no longer match everything
  family_of < "${list_urls_file}" | sort -u > "${work_dir}/families.txt"
  if [ "${add_policy}" = "disabled" ]; then
    : > "${work_dir}/candidates.txt"
  elif [ -s "${work_dir}/families.txt" ]; then
    awk -F'\t' 'FILENAME==ARGV[1] { fam[$1]=1; next } ($1 in fam) { print $2 }' \
      "${work_dir}/families.txt" "${work_dir}/catalog-families.txt" \
      | grep -Fx -v -f "${list_urls_file}" \
      | grep -Fx -v -f "${work_dir}/dead-clean.txt" \
      | sort -u > "${work_dir}/candidates.txt" || true
  else
    : > "${work_dir}/candidates.txt"
  fi

  # kept counts EVERY preserved line, non-URL lines included (CISC-01): a
  # blank line is kept content, not an absence
  kept_n="$(wc -l < "${work_dir}/kept.txt" | tr -d ' ')"
  added_n="$(wc -l < "${work_dir}/candidates.txt" | tr -d ' ')"
  removed_n="$(wc -l < "${work_dir}/removed.txt" | tr -d ' ')"
  total_added=$(( total_added + added_n ))
  total_removed=$(( total_removed + removed_n ))
  cat "${work_dir}/candidates.txt" >> "${added_urls_file}"

  printf '| %s | %d | %d | %d |\n' "${name}" "${kept_n}" "${added_n}" "${removed_n}" >> "${report_file}"

  if [ "${dry_run}" = "enabled" ]; then
    continue
  fi

  if [ "${added_n}" -gt 0 ] || [ "${removed_n}" -gt 0 ]; then
    cat "${work_dir}/kept.txt" "${work_dir}/candidates.txt" | unix_to_dos > "${list_file}"
  fi
done

# Disposition of catalog URLs: added / already listed somewhere / dead-excluded / no matching family
cat "${work_dir}"/urls-*.txt > "${work_dir}/all-listed.txt" || true
sort -u "${work_dir}/all-listed.txt" -o "${work_dir}/all-listed.txt"
added_unique="$(sort -u "${added_urls_file}" | grep -c . || true)"
already_n="$(grep -Fx -f "${work_dir}/all-listed.txt" "${work_dir}/catalog-urls.txt" | grep -c . || true)"
dead_excl_n="$(grep -Fx -f "${work_dir}/dead-clean.txt" "${work_dir}/catalog-urls.txt" | grep -c . || true)"
ignored=$(( catalog_total - added_unique - already_n - dead_excl_n ))
[ "${ignored}" -lt 0 ] && ignored=0
{
  printf '\n**Total:** %d added, %d removed. Catalog disposition: %d already listed, %d dead-excluded, %d no matching family.\n' "${total_added}" "${total_removed}" "${already_n}" "${dead_excl_n}" "${ignored}"
} >> "${report_file}"

# CISC-03: the report only reaches the tree on a real run — in dry-run it
# stays in the work dir and dies with the EXIT trap.
if [ "${dry_run}" != "enabled" ]; then
  mv "${report_file}" "${static_dir}/../.regen-report.md"
  report_file="${static_dir}/../.regen-report.md"
fi

echo "regen-static-lists: ${total_added} added, ${total_removed} removed, ${ignored} no-family — report: ${report_file}"
[ "${dry_run}" = "enabled" ] && echo "regen-static-lists: dry-run — no list was written"
exit 0
