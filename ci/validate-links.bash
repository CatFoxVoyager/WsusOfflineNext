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
# persist between runs to make the two-pass contract meaningful.
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
    --cache)  shift; cache_file="$1" ;;
    -*)       echo "validate-links: unknown option $1" >&2; exit 1 ;;
    *)        if [ -z "${static_dir}" ]; then static_dir="$1"
              elif [ -z "${report_file}" ]; then report_file="$1"
              elif [ -z "${dead_file}" ]; then dead_file="$1"
              fi ;;
  esac
  shift
done

if [ -z "${static_dir}" ] || [ -z "${report_file}" ] || [ -z "${dead_file}" ]; then
  echo "usage: bash ci/validate-links.bash <static-dir> <report-file> <dead-file> [--strict]" >&2
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
if [ -n "${cache_file}" ]; then
  touch "${cache_file}"
  grep -Fx -f "${cache_file}" "${work_dir}/dead-now.txt" > "${dead_file}" || true
  cp "${work_dir}/dead-now.txt" "${cache_file}"
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
  dead_total=$(( dead_total + list_dead ))
  printf '| %s | %d | %d |\n' "${name}" "${list_ok}" "${list_dead}" >> "${report_file}"
done

{
  printf '\n**Total:** %d URLs, %d dead.\n' "${total_urls}" "${dead_total}"
} >> "${report_file}"

echo "validate-links: ${dead_total} dead of ${total_urls} URLs — report: ${report_file}"

if [ "${strict}" = "enabled" ] && [ "${dead_total}" -gt 0 ]; then
  exit 1
fi
exit 0
