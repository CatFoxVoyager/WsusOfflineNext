#!/usr/bin/env bash
#
# ci/lib-office-catalog-counts.bash — Office catalog revision counter + frozen-baseline comparator
#
# The single implementation of the OFC-01 "Discrimination des ensembles vides"
# decision: every consumer (ci/extract-catalog.bash, ci/extract-catalog-linux.bash,
# ci/regen-static-lists.bash) sources THIS file — no parallel counter or
# comparator exists anywhere else. Sourcing has NO side effects: declarations
# and functions only (precedent: ci/lib-bump-version.bash).
#
# The discrimination problem: a per-family Office revision counter at zero is
# byte-identical between "the catalog no longer carries anything for that
# family" (correct — EOL freeze) and "the XSLT extraction regressed" (silent
# catastrophe at the train). count_office_family_revisions makes the number
# visible on every catalog run; assert_office_frozen_baseline makes the
# audited number LAW against ci/office-frozen-revision-baseline.txt, and any
# drift aborts the run fail-closed before anything downstream consumes the
# extraction.
#
# What this instrument does NOT do:
#   - It never counts C2R lanes from the catalog: C2R (2019/2021/2024) was
#     never carried by wsusscn2.cab. Their builds are audited literals locked
#     in OFFICE_C2R_BASELINE_LITERALS and verified by exact string match.
#   - It never writes to static/StaticDownloadLinks-o2k16* — filling those
#     lists is the documented anti-pattern (repo ARCHITECTURE Anti-Pattern 1).

# ===== Configuration =====

# Deliberately NOT the repo-conventional `script_version` name: every consumer
# of this library (extract-catalog*.bash, regen-static-lists.bash) declares its
# own `readonly script_version`, and a sourced redeclaration of the same
# readonly name would abort every consumer at source time.
readonly office_catalog_counts_version="1.1"

# Family patterns: ERE applied to the FILE NAME (basename) of each catalog
# URL ("<id>,<url>" pairs). Every declared family emits a line — including
# zero; a zero count is a RESULT here, never an error (the discrimination is
# the comparator's job below).
#
# AUDIT CORRECTION (November 2026 catalog, 20-AUDIT-OFFICE.md): the table
# starts EMPTY. The initial hypothesis (Office 2016 payloads carrying a
# glued "…2016" token in the file name) was probed against the real catalog
# and is structurally impossible, not merely mistokened: the 98,548-pair
# extraction carries ZERO .msp payloads (Office MSI ships as CAB-wrapped MSPs
# with version-agnostic names — mso-x-none_<40-hex>.cab, excel-x-none_…,
# word-x-none_…), and every "2016" name belongs to a server product
# (exchange2016 x91, sqlserver2016 x87, dpm/ws2016, GUID-fragment noise).
# File names carry no Office version: the authoritative per-family counter is
# the PRODUCT-SCOPED revision-id extraction below (the same selector the
# download pipeline uses). This table remains the extension point for any
# future family whose payload names carry their own token; the battery
# injects a fixture-scoped pattern to exercise the mechanism.
declare -A OFFICE_FAMILY_PATTERNS=()

# Product-scoped revision counters: family -> name of the revision-id file
# the EXTRACTOR must produce before counting (the platform XSLT run on
# package.xml with xslt/extract-revision-and-update-ids-<family>.xsl —
# Windows: cscript/XSLT.vbs, Linux: xsltproc). The lib only counts the
# file's lines and owns the sidecar row. o2k16 selects updates by Product Id
# 25aed893-7c2d-4a31-ae22-28ff8ac150ed (Office 2016) — the audit-proven
# discriminator.
declare -A OFFICE_PRODUCT_REVISION_COUNTS=(
  ["o2k16"]="o2k16-revision-ids.txt"
)

# Audited C2R channel literals (November 2026 audit). These are the LOCKED
# reference the baseline's c2r_baseline_* keys are verified against — by
# exact whole-string match, because a mis-transcribed digit here becomes law
# for every following run (threat T-20-02). They are the AUDITED values, not
# the stale bash fallbacks in sh/download-updates-tasks/65-office-c2r.bash
# (plan 20-02 rewrites those fallbacks from this table). Each literal was
# confirmed by a direct officecdn VersionDescriptor.xml probe replayable from
# the audit doc — never copied blindly from research prose.
declare -A OFFICE_C2R_BASELINE_LITERALS=(
  ["o2k19"]="16.0.10417.20207"
  ["o2k21"]="16.0.14334.20974"
  ["o2k24"]="16.0.17932.21056"
)

# ===== Functions =====

# Count catalog revisions per declared Office family.
#
# Usage: count_office_family_revisions <pairs-file> <out-file>
#
# <pairs-file> holds "<id>,<url>" lines (update-ids-and-locations-all.txt).
# <out-file> receives "family<TAB>count" sorted, one line per DECLARED family,
# including zero. The same table is emitted on stdout as loggable
# "office-revision-counts: family=N" lines (the extractors carry it into the
# run log; the regen report carries the same numbers).
#
# A zero count is a RESULT here, never an error — the frozen-vs-regressed
# discrimination is the comparator's job. Returns 0 for every counting
# outcome; a missing/unreadable pairs file is a programming error, not a
# count: fail-closed with 1 (the caller aborts).
function count_office_family_revisions ()
{
  local pairs_file="$1"
  local out_file="$2"
  local family="" pattern="" total=0
  if [ ! -r "${pairs_file}" ]; then
    echo "office-catalog-counts: pairs file missing or unreadable: ${pairs_file}" >&2
    return 1
  fi
  : > "${out_file}"
  for family in "${!OFFICE_FAMILY_PATTERNS[@]}"; do
    pattern="${OFFICE_FAMILY_PATTERNS[${family}]}"
    total="$(cut -d ',' -f '2-' "${pairs_file}" \
      | tr -d '\r' \
      | sed -e 's|.*/||' -e 's/[[:space:]]*$//' \
      | grep -iE "${pattern}" \
      | grep -c . || true)"
    printf '%s\t%s\n' "${family}" "${total}" >> "${out_file}"
    printf 'office-revision-counts: %s=%s\n' "${family}" "${total}"
  done
  sort -o "${out_file}" "${out_file}"
  return 0
}

# Count a family from its PRODUCT-SCOPED revision-id file (the audit-proven
# authoritative counter — see OFFICE_PRODUCT_REVISION_COUNTS).
#
# Usage: count_product_revisions <revision-ids-file> <family> <out-file>
#
# <revision-ids-file> holds "#<RevisionId>#,<UpdateId>" lines produced by the
# extractor's platform XSLT run (xslt/extract-revision-and-update-ids-<family>.xsl
# on package.xml). The family row in <out-file> is REPLACED (or inserted) —
# when a name-census row and a product-scoped row would collide, the
# product-scoped number wins: it is the one the download pipeline itself
# keys on. Zero is a result, never an error; a missing/unreadable
# revision-id file fails closed with 1.
function count_product_revisions ()
{
  local revision_ids_file="$1"
  local family="$2"
  local out_file="$3"
  local total=0
  if [ ! -r "${revision_ids_file}" ]; then
    echo "office-catalog-counts: revision-ids file missing or unreadable: ${revision_ids_file}" >&2
    return 1
  fi
  total="$(grep -c . "${revision_ids_file}" || true)"
  if [ -f "${out_file}" ]; then
    awk -F'\t' -v fam="${family}" '$1 != fam' "${out_file}" > "${out_file}.tmp"
  else
    : > "${out_file}.tmp"
  fi
  printf '%s\t%s\n' "${family}" "${total}" >> "${out_file}.tmp"
  sort -o "${out_file}.tmp" "${out_file}.tmp"
  mv "${out_file}.tmp" "${out_file}"
  printf 'office-revision-counts: %s=%s (product-scoped revision ids)\n' "${family}" "${total}"
  return 0
}

# Compare current counts against the committed frozen baseline.
#
# Usage: assert_office_frozen_baseline <counts-file> <baseline-file>
#
# <counts-file> is the "family<TAB>count" sidecar produced above.
# <baseline-file> is ci/office-frozen-revision-baseline.txt: a key=value
# snapshot of the audited November catalog whose header documents the audit
# date, the source catalog and the deliberate re-pin procedure ('#' and empty
# lines are ignored).
#
# Semantics:
#   baseline absent or empty  → "first run" warn on stderr, return 0 (the
#                               audit run that CREATES the baseline must be
#                               able to execute before the baseline exists)
#   frozen_<family>=N drift  → DRIFT on stderr, return 1 (fail-closed: the
#                               caller aborts BEFORE writing any file)
#   c2r_baseline_<prod>=X    → compared against the audited literal in
#                               OFFICE_C2R_BASELINE_LITERALS; any transcription
#                               drift aborts the same way (T-20-02)
#   unknown non-comment key  → parse error, return 1 (strict snapshot:
#                               a corrupted key must not pass silently)
function assert_office_frozen_baseline ()
{
  local counts_file="$1"
  local baseline_file="$2"
  local line="" key="" family="" value="" expected="" observed=""
  if [ ! -s "${baseline_file}" ]; then
    echo "office-frozen-baseline: absent — first run, comparison skipped (warn)" >&2
    return 0
  fi
  while IFS= read -r line; do
    case "${line}" in
      ''|'#'*) continue ;;
      frozen_*=*)
        key="${line%%=*}"
        family="${key#frozen_}"
        value="${line#*=}"
        observed="$(awk -F'\t' -v fam="${family}" '$1 == fam { print $2; exit }' "${counts_file}")"
        if [ -z "${observed}" ]; then
          echo "office-frozen-baseline: DRIFT on ${family} expected=${value} observed=missing — deliberate re-pin required (see header of the baseline file)" >&2
          return 1
        fi
        if [ "${observed}" != "${value}" ]; then
          echo "office-frozen-baseline: DRIFT on ${family} expected=${value} observed=${observed} — deliberate re-pin required (see header of the baseline file)" >&2
          return 1
        fi
        ;;
      c2r_baseline_*=*)
        key="${line%%=*}"
        family="${key#c2r_baseline_}"
        value="${line#*=}"
        expected="${OFFICE_C2R_BASELINE_LITERALS[${family}]:-}"
        if [ -z "${expected}" ]; then
          echo "office-frozen-baseline: DRIFT on ${family} expected=no-audited-literal observed=${value} — deliberate re-pin required (see header of the baseline file)" >&2
          return 1
        fi
        if [ "${value}" != "${expected}" ]; then
          echo "office-frozen-baseline: DRIFT on ${family} expected=${expected} observed=${value} — deliberate re-pin required (see header of the baseline file)" >&2
          return 1
        fi
        ;;
      *)
        echo "office-frozen-baseline: unrecognized baseline key: ${line}" >&2
        return 1
        ;;
    esac
  done < <(tr -d '\r' < "${baseline_file}")
  return 0
}
