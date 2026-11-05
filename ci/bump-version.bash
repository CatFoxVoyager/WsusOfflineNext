#!/usr/bin/env bash
#
# ci/bump-version.bash — substitute the application version across the repo
#
# Usage: bash ci/bump-version.bash <new-version>   (e.g. 5.0.0+2026.11)
#        bash ci/bump-version.bash --print-files
#
# The old version is read from the single source of truth
# (cmd/DownloadUpdates.cmd, "set WSUSOFFLINE_VERSION=X.Y.Z" — with or without
# the "+YYYY.MM" metadata). The 14-file matrix is the one committed in
# 339f600, retargeted in Phase 24 plan 02 (pure-.cmd launchers replaced the
# AutoIt launcher twins), in Phase 25 plan 01 (generator GUI source deleted)
# and in Phase 26 plan 03 (the last au3 left; the native installer's .lpi
# VersionInfo block joined as the new site family - one file out, one file
# in, so the count stays 14; measured by the live bump run, never
# narrated). The build tag
# "(b2026.10)" is version-independent and must not move. Exits 1 unless
# exactly 22 version-token sites land in exactly 14 files.
#
# The engine runs TWO LANES over the 22 matrix occurrences (phase 19, D-01):
# a bounded full-form lane (15 sites: source of truth, headers, captions,
# marker, <Version>, package.json, App.tsx, the .lpi ProductVersion string)
# and a numeric-anchored core lane (7 build contexts: csproj
# <FileVersion>/<AssemblyVersion> "X.Y.Z.0" plus the .lpi MajorVersionNr/
# MinorVersionNr/RevisionNr fields — a '+' metadata there is impossible by
# construction, the fields are integers).
#
# The before-accounting is SHAPE-CONDITIONAL — the binding invariant in BOTH
# shapes is TOTAL version-token sites = 22 across the 14 files, never a
# per-lane number alone:
#   STEADY STATE (old carries "+YYYY.MM"): the two before-motifs enumerate
#     DISJOINT site sets (16 full-form + 6 numeric); the before gate asserts
#     sum(before_full) + sum(before_num) = 22.
#   MIGRATION (old is a bare core): the bounded bare-core motif matches ALL
#     22 sites, so the full-form lane already enumerates every site; the
#     before gate asserts sum(before_full) = 22 and sum(before_num) is
#     INFORMATIVE only (printed, never gate-binding) — those 7 are the
#     numeric subset of the 22 that the numeric lane re-repairs after the
#     full lane carried the "+YYYY.MM" form there.
#   The shape branch is selected by whether the old version carries '+' —
#   picking the wrong branch produces a wrong TOTAL and aborts, so the gate
#   stays fail-closed in both shapes. The after-gates (15 full-form + 7
#   numeric = 22 sites, of which 19 carry the literal core substring and 3
#   are the .lpi VersionInfo integer fields - Major/Minor/Revision are
#   separate integers that never contain the "X.Y.Z" substring) are binding
#   in both shapes because the after-state is identical whichever shape
#   produced it.
#
# Counting/substitution logic lives in ci/lib-bump-version.bash: occurrences
# are COUNTED and the pattern is bounded at digit boundaries (CISC-08).

# ===== Configuration =====
readonly script_version="1.4"
VERSION_FILES="
cmd/DownloadUpdates.cmd
client/cmd/DoUpdate.cmd
src-native/installer/installer.lpi
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

. "${repo_root}/ci/lib-bump-version.bash"

# ===== Functions =====

# ===== Main program =====

# --print-files: the workflow consumes the single matrix definition from
# here (phase 19 plan 03). Prints and exits before any validation or
# mutation — exactly one matrix definition exists in the repo.
if [ "${1:-}" = "--print-files" ]; then
  printf '%s\n' ${VERSION_FILES}
  exit 0
fi

if [ $# -ne 1 ] || ! is_valid_version_arg "$1"; then
  echo "usage: bash ci/bump-version.bash <new-version>   (e.g. 5.0.0+2026.11)" >&2
  exit 1
fi
new_version="$1"

read_old_version
if [ "${old_version}" = "${new_version}" ]; then
  if [ "${DRY_RUN:-}" = "true" ]; then
    # Dry-run idempotency: a re-dispatched dry-run train against a tree that
    # already carries the target version (e.g. after deleting a broken
    # release whose bump commit landed on main) is a successful no-op —
    # the subsequent gates still run and prove the shipped shape.
    echo "bump-version: version already ${new_version} (dry run - no-op ok)"
    exit 0
  fi
  echo "bump-version: version already ${new_version}" >&2
  exit 1
fi

cd "${repo_root}" || exit 1
old_esc="$(escape_ere "${old_version}")"
new_esc="$(escape_ere "${new_version}")"
new_core="$(strip_version_metadata "${new_version}")"
new_core_esc="$(escape_ere "${new_core}")"
old_core="$(strip_version_metadata "${old_version}")"
old_core_esc="$(escape_ere "${old_core}")"

# Engine shape (see header). The numeric lane's SUBSTITUTION source differs:
# the old core in steady state (the anchors already carry the bare core),
# the new FULL form in migration (lane B re-repairs the 12 numeric sites
# that lane A just carried the '+' form into).
if printf '%s' "${old_version}" | grep -q '+'; then
  bump_shape="steady"
  numeric_src_esc="${old_core_esc}"
else
  bump_shape="migration"
  numeric_src_esc="${new_esc}"
fi

full_before_total=0
num_before_total=0
full_after_total=0
num_after_total=0
core_after_total=0
lpi_after_total=0
files_touched=0

printf '%-55s %s -> %s\n' "file" "${old_version}" "${new_version}"
for f in ${VERSION_FILES}; do
  if [ ! -f "${f}" ]; then
    echo "bump-version: MISSING file in version matrix: ${f}" >&2
    exit 1
  fi
  before_full="$(count_occurrences "(^|[^0-9])${old_esc}([^0-9]|\$)" "${f}")"
  before_num="$(count_numeric_anchored "${old_core_esc}" "${f}")"
  if [ "${before_full}" -gt 0 ]; then
    substitute_bounded "${old_esc}" "${new_version}" "${f}"
  fi
  substitute_numeric_versions "${numeric_src_esc}" "${new_core}" "${f}"
  after_full="$(count_occurrences "(^|[^0-9])${new_esc}([^0-9]|\$)" "${f}")"
  after_num="$(count_numeric_anchored "${new_core_esc}" "${f}")"
  core_after="$(count_occurrences "(^|[^0-9])${new_core_esc}([^0-9]|\$)" "${f}")"
  full_before_total=$(( full_before_total + before_full ))
  num_before_total=$(( num_before_total + before_num ))
  full_after_total=$(( full_after_total + after_full ))
  num_after_total=$(( num_after_total + after_num ))
  core_after_total=$(( core_after_total + core_after ))
  case "${f}" in
    *.lpi) lpi_after_total=$(( lpi_after_total + after_num )) ;;
  esac
  if [ "${before_full}" -gt 0 ] || [ "${before_num}" -gt 0 ]; then
    files_touched=$(( files_touched + 1 ))
  fi
  printf '%-55s %4d -> %4d\n' "${f}" "$(( before_full + before_num ))" "$(( after_full + after_num ))"
done

# Shape-conditional before-accounting: the invariant is TOTAL sites = 22.
if [ "${bump_shape}" = "steady" ]; then
  before_gate_total=$(( full_before_total + num_before_total ))
else
  before_gate_total="${full_before_total}"
fi
echo "TOTAL: ${before_gate_total} -> $(( full_after_total + num_after_total )) substitutions in ${files_touched} files"
echo "shape: ${bump_shape} | before lanes full/num: ${full_before_total}/${num_before_total} | after: full ${full_after_total}, numeric ${num_after_total}, core ${core_after_total}"

if [ "${before_gate_total}" -ne 22 ] || [ "${files_touched}" -ne 14 ]; then
  echo "bump-version: EXPECTED 22 version-token sites across 14 files — aborting (tree modified, run git checkout -- .)" >&2
  exit 1
fi
# After-gates — binding in BOTH shapes (the after-state is identical
# whichever shape produced it): 15 full-form + 7 numeric = 22 sites; the
# literal-core substring lands in 19 of them (the 3 .lpi integer fields
# never contain the core substring), so the reconciliation gate is
# core + lpi sites == full + numeric.
if [ "${full_after_total}" -ne 15 ] || [ "${num_after_total}" -ne 7 ] \
   || [ "${core_after_total}" -ne 19 ]; then
  echo "bump-version: EXPECTED after-state 15 full-form + 7 numeric = 22 sites (19 literal-core + 3 .lpi integer fields) — aborting (tree modified, run git checkout -- .)" >&2
  exit 1
fi
if [ $(( core_after_total + lpi_after_total )) -ne $(( full_after_total + num_after_total )) ]; then
  echo "bump-version: lane split ${full_after_total}+${num_after_total} disagrees with core ${core_after_total} + .lpi fields ${lpi_after_total} — aborting (tree modified, run git checkout -- .)" >&2
  exit 1
fi
echo "bump-version: OK — version ${old_version} -> ${new_version} (${bump_shape})"
exit 0
