#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Upgrade Media Gate (Linux / Bash twin)
# File: sh/tests/verify-upgrade-media.bash
#
# Plan 37-02 (VAL-01c): the bash twin of tests/verify-upgrade-media.cmd
# (plan 33-04). Validates the consigned spike record and the assembled
# media honestly, on the second pipeline - the roadmap criterion demands
# the media gate green "en CMD et bash", and the CMD gate was the only
# media battery without a bash twin.
#
# Ported legs (1:1 with the CMD gate):
#   [MEDIA 1] .planning/tmp/33-spike/33-SPIKE-RECORD.md exists and
#             carries the four [PROBE- markers (measured >= 4)
#   [MEDIA 2] the record is scrub clean of signed-URL token query
#             material (P[1-4]= token lines measured = 0). The count is
#             captured into a variable and compared numerically - never
#             piped into wc -l; leg 1's marker population runs first so
#             the zero cannot pass vacuously.
#   [MEDIA 3] doc/upgrade-media-assembly.md carries the winning-set
#             section, the wimlib GPLv3 note (>= 2 wimlib mentions) and
#             the exFAT/FAT32 guidance (ACQ-05)
#   [MEDIA 4] the staged-media branch (client/upgrade/26200-x64/en-us):
#             sources/setup.exe + sources/boot.wim non-empty (setup.exe
#             refuses a boot.wim-less scaffold with 0x80070002 - the
#             live-UAT 2026-11-11 finding), the vendored wimlib info
#             census reads >= 1 image and the Flags line = 9 (setup.exe
#             refuses a flag-less first image with 0x8030002F - the
#             live-UAT 2026-11-12 finding), the staged manifest meta
#             rows parse (uuid + total_bytes + total_mib), and the
#             integrity class file exists with a hashdeep header
#             (created after staging, ACQ-04).
#             Absence is legitimate ONLY under the consigned contingency:
#             the record must carry the CONSIGN-DISM-FAILURE marker; a
#             missing record always fails.
#
# wimlib note: the census runs the vendored exe directly
# (bin/wimlib/x64/wimlib-imagex.exe) - native PE execution on the MSYS
# bash host, the same direct-execution precedent as the repo's vendored
# wget/unzip tools. A Linux host would need wine; the census leg fails
# closed there, mirroring the CMD gate's Windows-rooted contract.
#
# Red-bite override (bite proofs only; the gui-contracts battery's
# WSON_* env-override idiom): WSON_UPGRADE_MEDIA_RECORD points the
# record path at a scratch copy. Never set in consigned runs.
#
# Clean-MSYS note: this twin joins the phase gate's clean-MSYS
# consignment (plan 37-03); inherited MSYS2_ARG_CONV_EXCL='*' poison
# must not be set in the environment that runs it.
#
# Success sentinel: UPGRADE-MEDIA-PASS. Modeled on the CMD gate (held
# repo root, named-leg FAIL lines, exit-code fail-closed).
# =======================================================================

set -e
set -u
export LC_ALL=C

if [ -d "/usr/bin" ] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "$repo_root"

echo "======================================================================="
echo "WSUS Offline Update - Upgrade Media Gate (Linux / Bash)"
echo "======================================================================="

record="${WSON_UPGRADE_MEDIA_RECORD:-${repo_root}/.planning/tmp/33-spike/33-SPIKE-RECORD.md}"
doc_file="${repo_root}/doc/upgrade-media-assembly.md"
media_dir="${repo_root}/client/upgrade/26200-x64/en-us"
wimlib_exe="${repo_root}/bin/wimlib/x64/wimlib-imagex.exe"
integrity_file="${repo_root}/client/md/hashes-upgrade-26200-x64-en-us.txt"

# Fail-closed named-leg protocol (the CMD gate's :Fail shape): the FAIL
# line names the MEDIA leg, the banner follows, exit 1.
media_gate_fail () {
    echo "FAIL: $1"
    echo ""
    echo "======================================================================="
    echo "FAILURE: the upgrade media gate failed - see the named MEDIA leg above."
    echo "======================================================================="
    exit 1
}

# [MEDIA 1] the consigned probe matrix - four [PROBE- markers
if [ ! -f "$record" ]; then
    media_gate_fail "[MEDIA 1] the consigned spike record is missing: $record"
fi
probe_count="$(grep -c '\[PROBE-' "$record" || true)"
if [ "$probe_count" -lt 4 ]; then
    media_gate_fail "[MEDIA 1] the record carries ${probe_count} PROBE markers, expected at least 4"
fi
echo "[MEDIA 1] PASS (${probe_count} probe markers)"

# [MEDIA 2] the record scrub gate - zero token query material. Leg 1's
# marker population already proved the record was read; the zero here is
# a measured 0 captured into a variable (never a piped wc -l).
token_lines="$(grep -cE 'P[1-4]=' "$record" || true)"
if [ "$token_lines" != "0" ]; then
    media_gate_fail "[MEDIA 2] the record carries ${token_lines} token-material line(s) - scrub before consigning"
fi
echo "[MEDIA 2] PASS (scrub = 0)"

# [MEDIA 3] the assembly doc markers - winning set / wimlib GPLv3 / exFAT
if [ ! -f "$doc_file" ]; then
    media_gate_fail "[MEDIA 3] the assembly doc is missing: $doc_file"
fi
winning_count="$(grep -ci 'winning' "$doc_file" || true)"
if [ "$winning_count" -lt 1 ]; then
    media_gate_fail "[MEDIA 3] the doc carries no winning-set section"
fi
wimlib_count="$(grep -ci 'wimlib' "$doc_file" || true)"
if [ "$wimlib_count" -lt 2 ]; then
    media_gate_fail "[MEDIA 3] the doc names wimlib ${wimlib_count} time(s), expected at least 2"
fi
gpl_count="$(grep -ci 'GPLv3' "$doc_file" || true)"
if [ "$gpl_count" -lt 1 ]; then
    media_gate_fail "[MEDIA 3] the doc carries no GPLv3 license note"
fi
exfat_count="$(grep -ci 'exFAT' "$doc_file" || true)"
if [ "$exfat_count" -lt 1 ]; then
    media_gate_fail "[MEDIA 3] the doc carries no exFAT/FAT32 guidance"
fi
echo "[MEDIA 3] PASS (winning set, wimlib GPLv3 note, exFAT guidance)"

# [MEDIA 4] the staged-media branch
if [ -f "${media_dir}/sources/install.esd" ]; then
    echo "[MEDIA 4] the staged media - setup.exe, manifest meta rows, integrity class..."
    if [ ! -f "${media_dir}/sources/setup.exe" ]; then
        media_gate_fail "[MEDIA 4] the staged media carries no sources/setup.exe"
    fi
    if [ ! -s "${media_dir}/sources/setup.exe" ]; then
        media_gate_fail "[MEDIA 4] sources/setup.exe is empty"
    fi
    # The boot.wim leg (the live-UAT 2026-11-11 finding): setup.exe needs
    # sources/boot.wim - the gate refuses its absence fail-closed and runs
    # the vendored wimlib info census over it (userspace tool, no elevation).
    if [ ! -f "${media_dir}/sources/boot.wim" ]; then
        media_gate_fail "[MEDIA 4] the staged media carries no sources/boot.wim (setup.exe would die with 0x80070002)"
    fi
    if [ ! -s "${media_dir}/sources/boot.wim" ]; then
        media_gate_fail "[MEDIA 4] sources/boot.wim is empty"
    fi
    if [ ! -f "$wimlib_exe" ]; then
        media_gate_fail "[MEDIA 4] the vendored wimlib is missing: $wimlib_exe"
    fi
    if ! wimlib_info="$("$wimlib_exe" info "${media_dir}/sources/boot.wim" 2>/dev/null)"; then
        media_gate_fail "[MEDIA 4] the wimlib info census could not read sources/boot.wim (corrupt or unreadable)"
    fi
    m_bootcount="$(printf '%s\n' "$wimlib_info" | sed -n 's/^Image Count:[[:space:]]*//p' | tail -1)"
    case "$m_bootcount" in
        ''|*[!0-9]*)
            media_gate_fail "[MEDIA 4] the wimlib info census could not read sources/boot.wim (corrupt or unreadable)"
            ;;
    esac
    if [ "$m_bootcount" -lt 1 ]; then
        media_gate_fail "[MEDIA 4] sources/boot.wim carries ${m_bootcount} image(s), expected at least 1"
    fi
    # The boot.wim flag-9 leg (the live-UAT 2026-11-12 0x8030002F finding):
    # setup.exe requires the FIRST image to carry the setup FLAGS metadata;
    # the census reports it as a Flags line (a flag-less image reports
    # none - measured live on the staged 26200 media). The staged census
    # carries a single Flags line (1 image); like the CMD twin's census
    # walk, the last reported line decides.
    m_bootflag="$(printf '%s\n' "$wimlib_info" | sed -n 's/^Flags:[[:space:]]*//p' | tail -1)"
    if [ "$m_bootflag" != "9" ]; then
        media_gate_fail "[MEDIA 4] sources/boot.wim first image reports Flags ${m_bootflag:-none}, expected 9 (setup.exe dies with 0x8030002F)"
    fi
    manifest_file="${media_dir}/manifest.txt"
    m_uuid="$(tr -d '\r' < "$manifest_file" | awk -F'|' '$1=="uuid" {print $2; exit}')"
    m_total_bytes="$(tr -d '\r' < "$manifest_file" | awk -F'|' '$1=="total_bytes" {print $2; exit}')"
    m_total_mib="$(tr -d '\r' < "$manifest_file" | awk -F'|' '$1=="total_mib" {print $2; exit}')"
    if [ -z "$m_uuid" ]; then
        media_gate_fail "[MEDIA 4] the staged manifest carries no uuid meta row"
    fi
    if [ -z "$m_total_bytes" ]; then
        media_gate_fail "[MEDIA 4] the staged manifest carries no total_bytes meta row"
    fi
    if [ -z "$m_total_mib" ]; then
        media_gate_fail "[MEDIA 4] the staged manifest carries no total_mib meta row"
    fi
    if [ ! -f "$integrity_file" ]; then
        media_gate_fail "[MEDIA 4] the media integrity class is missing (created after staging, ACQ-04)"
    fi
    hashdeep_lines="$(grep -c '^%%' "$integrity_file" || true)"
    if [ "$hashdeep_lines" -lt 1 ]; then
        media_gate_fail "[MEDIA 4] the integrity class carries no hashdeep header"
    fi
    echo "[MEDIA 4] PASS (media uuid ${m_uuid}, totals ${m_total_bytes} bytes / ${m_total_mib} MiB, boot.wim ${m_bootcount} image(s) flag ${m_bootflag}, db class present)"
else
    echo "[MEDIA 4] no staged media - the consigned contingency is the only legitimate absence..."
    if ! grep -qF 'CONSIGN-DISM-FAILURE' "$record"; then
        media_gate_fail "[MEDIA 4] no staged media AND no CONSIGN-DISM-FAILURE marker in the record - media absence is unexplained"
    fi
    echo "[MEDIA 4] PASS (absence under the consigned CONSIGN-DISM-FAILURE contingency)"
fi

echo ""
echo "======================================================================="
echo "UPGRADE-MEDIA-PASS: the consigned record and the staged media validate."
echo "======================================================================="
exit 0
