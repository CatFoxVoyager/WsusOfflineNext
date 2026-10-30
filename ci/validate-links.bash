#!/usr/bin/env bash
#
# ci/validate-links.bash — HEAD-probe every URL of the static download lists
#
# Usage: bash ci/validate-links.bash <static-dir> <report-file> <dead-file> [--strict] [--cache <file>]
#
# Writes a per-list markdown report and a plain dead-URLs file (one per line).
# With --cache <file>, removal requires two consecutive dead passes: a URL dead
# now but absent from the cache is only recorded as a candidate (dead-file stays
# empty for it); a URL dead in this pass AND already in the cache lands in the
# dead-file. A cached URL found alive leaves the cache. The cache file must
# persist between runs to make the two-pass contract meaningful. An unusable
# cache path aborts fail-closed (WR-02); an absent cache warns (first run or
# lost persistence) and defers the confirmation by one pass.
# Exits 1 with --strict if at least one URL is dead. Non-strict always exits 0
# unless the inputs are unusable (missing directory, no URLs found at all).

# ===== Configuration =====
readonly script_version="1.1"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) WSUSOfflineNext-linkcheck"
PROBES_IN_PARALLEL=10
PROBE_TIMEOUT=20
PROBE_TRIES=2

# ===== Global variables =====
static_dir=""
report_file=""
dead_file=""
cache_file=""
strict="disabled"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
wget_bin=""

# ===== Functions =====

# Resolve the downloader: vendored wget64 first, then any wget on PATH
function resolve_wget ()
{
  if [ -x "${repo_root}/bin/wget64.exe" ]; then
    wget_bin="${repo_root}/bin/wget64.exe"
  elif [ -x "${repo_root}/bin/wget.exe" ]; then
    wget_bin="${repo_root}/bin/wget.exe"
  else
    wget_bin="$(command -v wget || true)"
  fi
  if [ -z "${wget_bin}" ]; then
    echo "validate-links: no wget found (bin/ or PATH)" >&2
    exit 1
  fi
}

# Print the clean URL list of one list file (CRLF, ",alias" suffix and
# trailing spaces removed — some lists carry "url,target-name" lines)
function list_urls ()
{
  local file="$1"
  cat_dos "${file}" | grep -E '^https?://' | cut -d',' -f1 | sed 's/[[:space:]]*$//'
}

# ===== Main program =====

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) strict="enabled" ;;
    --cache)  [ $# -ge 2 ] || { echo "validate-links: --cache requires a file argument" >&2; exit 1; }
              shift; cache_file="$1" ;;
    -*)       echo "validate-links: unknown option $1" >&2; exit 1 ;;
    *)        if [ -z "${static_dir}" ]; then static_dir="$1"
              elif [ -z "${report_file}" ]; then report_file="$1"
              elif [ -z "${dead_file}" ]; then dead_file="$1"
              fi ;;
  esac
  shift
done

if [ -z "${static_dir}" ] || [ -z "${report_file}" ] || [ -z "${dead_file}" ]; then
  echo "usage: bash ci/validate-links.bash <static-dir> <report-file> <dead-file> [--strict] [--cache <file>]" >&2
  exit 1
fi
if [ ! -d "${static_dir}" ]; then
  echo "validate-links: directory not found: ${static_dir}" >&2
  exit 1
fi

. "${repo_root}/sh/libraries/dos-files.bash"
resolve_wget

work_dir="$(mktemp -d)"
trap 'rm -rf "${work_dir}"' EXIT

: > "${work_dir}/all-urls.txt"
list_count=0
for list_file in "${static_dir}"/*.txt; do
  [ -e "${list_file}" ] || continue
  list_count=$(( list_count + 1 ))
  name="$(basename "${list_file}")"
  list_urls "${list_file}" > "${work_dir}/urls-${name}"
  cat "${work_dir}/urls-${name}" >> "${work_dir}/all-urls.txt"
done

total_urls="$(grep -c . "${work_dir}/all-urls.txt" || true)"
if [ "${list_count}" -eq 0 ] || [ "${total_urls}" -eq 0 ]; then
  echo "validate-links: no URLs found under ${static_dir}" >&2
  exit 1
fi

# Expected probe set: the DEDUPLICATED url count, i.e. what the pipeline
# below actually probes. Deliberately distinct from the raw all-urls line
# count above (inter-list duplicates are probed once, not once per list).
unique_expected="$(sort -u "${work_dir}/all-urls.txt" | grep -c . || true)"

# Parallel probes; a probe prints the URL back only when dead. Every
# attempted URL appends one mark, dead or alive, so a broken stage
# (sort/xargs/inner sh) can be told apart from "everything is alive".
PROBED_MARKS="${work_dir}/probed-marks.txt"
: > "${PROBED_MARKS}"
WGET_BIN="${wget_bin}"
export WGET_BIN PROBE_TIMEOUT PROBE_TRIES UA PROBED_MARKS
set -o pipefail
sort -u "${work_dir}/all-urls.txt" | xargs -P "${PROBES_IN_PARALLEL}" -I '{}' sh -c '
  "${WGET_BIN}" --spider -S -T "${PROBE_TIMEOUT}" -t "${PROBE_TRIES}" -U "${UA}" -q "$1" 2>/dev/null || echo "$1"
  printf "p\n" >> "${PROBED_MARKS}"
' _ '{}' > "${work_dir}/dead-urls.txt"
probe_rc=$?
set +o pipefail
if [ "${probe_rc}" -ne 0 ]; then
  echo "validate-links: probe pipeline failed (rc ${probe_rc}) — refusing to write a dead-file from a broken stage" >&2
  exit 1
fi
probed_total="$(grep -c . "${PROBED_MARKS}" || true)"
if [ "${probed_total}" -ne "${unique_expected}" ]; then
  echo "validate-links: probe stage incomplete (${probed_total}/${unique_expected} URLs probed)" >&2
  exit 1
fi
sort -u "${work_dir}/dead-urls.txt" -o "${work_dir}/dead-now.txt"

# Two-pass removal: with a cache, only URLs dead now AND already cached are
# confirmed dead; the cache always converges to this pass's dead set.
# WR-02: every cache stage is fail-closed — an unusable cache path must abort
# with a named message, never degrade into a silent "0 dead" that disables
# REMOVE. A cache ABSENT at run start is not an abort: it is the legitimate
# first-run state (and the lost-persistence symptom, WR-01) — warn loudly and
# defer the confirmation by one pass.
if [ -n "${cache_file}" ]; then
  if [ -f "${cache_file}" ]; then
    cache_preexisting="yes"
  else
    cache_preexisting="no"
    echo "validate-links: cache absent at run start: ${cache_file} — no two-pass confirmation this pass (check cache persistence)" >&2
  fi
  touch "${cache_file}" || { echo "validate-links: cache unusable: ${cache_file}" >&2; exit 1; }
  # The cache is operator-materialized (editor may write CRLF): normalize CR
  # at one site so the two-pass confirmation cannot be silently disabled.
  cat_dos "${cache_file}" > "${work_dir}/cache-clean.txt"
  # cat_dos swallows a cat failure (the pipeline's rc is tr's, which always
  # succeeds): a pre-existing NON-EMPTY cache must yield a non-empty clean
  # copy — an empty one means the read failed, and confirmation must not
  # proceed on a silently emptied cache (WR-02). A genuinely empty cache
  # (first pass) stays legitimate.
  if [ "${cache_preexisting}" = "yes" ] && [ -s "${cache_file}" ] && [ ! -s "${work_dir}/cache-clean.txt" ]; then
    echo "validate-links: cache unreadable: ${cache_file}" >&2
    exit 1
  fi
  grep -Fx -f "${work_dir}/cache-clean.txt" "${work_dir}/dead-now.txt" > "${dead_file}" || true
  cp "${work_dir}/dead-now.txt" "${cache_file}" || { echo "validate-links: cache write-back failed: ${cache_file}" >&2; exit 1; }
else
  cp "${work_dir}/dead-now.txt" "${dead_file}"
fi

# ===== Report =====

{
  printf '# Static links validation\n\n'
  printf '| list | ok | dead |\n'
  printf '| :--- | ---: | ---: |\n'
} > "${report_file}"

dead_total=0
lists_entries=0
for list_file in "${static_dir}"/*.txt; do
  [ -e "${list_file}" ] || continue
  name="$(basename "${list_file}")"
  list_total="$(grep -c . "${work_dir}/urls-${name}" || true)"
  list_dead=0
  while IFS= read -r url; do
    [ -n "${url}" ] || continue
    if grep -qxF "${url}" "${dead_file}"; then
      list_dead=$(( list_dead + 1 ))
    fi
  done < "${work_dir}/urls-${name}"
  list_ok=$(( list_total - list_dead ))
  lists_entries=$(( lists_entries + list_total ))
  dead_total=$(( dead_total + list_dead ))
  printf '| %s | %d | %d |\n' "${name}" "${list_ok}" "${list_dead}" >> "${report_file}"
done

# Two denominators, labeled: the deduplicated probe set vs the per-list sum.
unique_dead="$(grep -c . "${dead_file}" || true)"
{
  printf '\n**Total (unique):** %d URLs probed (unique), %d dead (unique).\n' "${unique_expected}" "${unique_dead}"
  printf '**Somme des listes:** %d entrées, %d dead.\n' "${lists_entries}" "${dead_total}"
  if [ "${lists_entries}" -ne "${unique_expected}" ]; then
    printf '%d doublon(s) inter-listes.\n' "$(( lists_entries - unique_expected ))"
  fi
} >> "${report_file}"

echo "validate-links: ${unique_dead} dead of ${unique_expected} unique URLs (${dead_total} dead of ${lists_entries} list entries) — report: ${report_file}"

if [ "${strict}" = "enabled" ] && [ "${dead_total}" -gt 0 ]; then
  exit 1
fi
exit 0
