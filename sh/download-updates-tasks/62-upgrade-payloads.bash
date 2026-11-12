# This file will be sourced by the shell bash.
#
# Filename: 62-upgrade-payloads.bash
#
# This task acquires the UUP upgrade payloads for the selected full
# feature-update target (plan 33-03, ACQ-02 + the sha256 half of ACQ-04).
# The CMD twin lives in cmd/UpgradePayloads.cmd + the Phase-33 region of
# cmd/DownloadUpdates.cmd - parity of BEHAVIOR, not bytes.
#
# Gate (DEC-33-09): with NO selection, an invalid selection, or no
# selected build_arch key whose upgrades.txt row carries fu_media=1, this
# task is an ABSOLUTE no-op - zero output, zero side effects, the engine
# run stays byte-identical to the pre-33 behavior. With one qualifying
# target, the task resolves the payload manifest via the coupled one-shot
# resolver twin (uup_resolve), prints the media budget (ACQ-05, DEC-33-07:
# a warning, never a block), downloads the spool resume-tuned (aria2 for
# payloads >= 104857600 bytes with the uup option array, wget -c below,
# size-descending big-first ordering - the spike-proven token-TTL shape),
# and runs the fail-closed hash gate over the whole spool BEFORE anything
# could stage. The verified spool then becomes the staged raw set (plan
# 33-04, DEC-33-05): client/upgrade/<cible>-<arche>/<langue>/set/ + the
# acquisition manifest + the media integrity class, the loud
# Windows-generator-only note, and the post-success revision purge.
# Assembly itself never happens on this side.
#
# Hygiene (T-33-09): the url map and the downloader list files carry
# token URL material and are deleted on EVERY exit path - success,
# failure, or abort. The downloader run logs (aria2 echoes the full URI
# of every attempt, wget -nv echoes the full URL of every transfer) land
# in the SPOOL SCRATCH (aria2-run.log / wget-run.log beside the audited
# files/ dir), never in the persistent download log (ACQ-01, live-UAT 33
# finding #5: the 2026-11-12 15:29 run leaked glued token URIs into
# log/download.log through the wget -a channel). A downloader list shape
# pin (can-fail) validates the written lists BEFORE any downloader runs:
# every URI line must match the frozen scheme+charset grammar and every
# output path must be an indented out= continuation - a glued or
# multi-token line refuses the acquisition fail-closed with nothing
# downloaded.
#
# Failure discipline: recoverable failures log + increment_error_count
# and abort the SECTION (the engine continues, the error tally reports
# it). This mirrors the bash-side integrity discipline
# (verify_integrity_database); the CMD twin terminates the engine run via
# the :UpgradeError label instead - the run-continuation asymmetry is the
# two engines' established idiom difference. A multi-GiB payload is
# NEVER downgraded to a non-resumable download: when aria2c is
# unavailable the section aborts loudly.
#
# Test seams (DEC-33-12 family): WOU_UUP_FIXTURE routes the resolver at a
# fixture file, WOU_UPGRADE_LANG (default en-us), WOU_UPGRADE_SPOOL
# (default ${TMPDIR:-/tmp}/wou-upgrade-spool), UUP_UPGRADES_TABLE
# (default ../client/UpdateTable/upgrades.txt), UUP_ARIA2_BIN /
# UUP_WGET_BIN (binary overrides for the sandbox batteries).

# ========== Global variables =============================================

# The section's TEMP runtime artifacts (T-33-09) - all initialized empty
# so the cleanup helper is nounset-safe and idempotent
uup_section_urlmap=""
uup_section_join=""
uup_section_join_sorted=""
uup_section_aria=""
uup_section_aria_http=""
uup_section_wget=""

# ========== Functions ====================================================

# Delete the section's token-bearing TEMP artifacts on every exit path

function uup_section_cleanup ()
{
    local artifact=""
    for artifact in "${uup_section_urlmap}" "${uup_section_join}" \
                    "${uup_section_join_sorted}" "${uup_section_aria}" \
                    "${uup_section_aria_http}" "${uup_section_wget}"
    do
        if [[ -n "${artifact}" && -f "${artifact}" ]]
        then
            rm -f "${artifact}"
        fi
    done
    return 0
}

# The coupled download + fail-closed verification for an already-resolved
# manifest. Split out of the section function so the battery can drive
# the download mechanics directly with fixture artifacts (the section
# resolve is one-shot and fixture mode emits no url map).
#
# Usage: uup_download_and_verify <manifest> <url_map> <files_dir>
#
# Returns 0 when the whole spool verified; 1 after logging + counting
# the failure (the caller's staging decisions see the nonzero exit).

function uup_download_and_verify ()
{
    local manifest="$1" urlmap="$2" files_dir="$3"
    local name="" sha256="" size="" url="" line=""
    local sorted_pad="" sorted_url="" sorted_name="" http_url=""
    local wname="" wurl="" wurl_http=""
    local total_mib="" total_bytes="" build_meta="" lang_meta=""
    local row_count=0 aria_rows=0 wget_rows=0
    local aria_bin="" aria_opts=()
    local wget_bin="" wget_opts=()
    local spool_scratch="" aria_run_log="" wget_run_log=""
    local pin_bad=0 pin_total=0 pin_match=0 pin_expect=0

    if [[ ! -s "${manifest}" ]]
    then
        log_error_message "The upgrade payload manifest is missing or empty: ${manifest}"
        increment_error_count
        return 1
    fi
    mkdir -p "${files_dir}"

    # The url map becomes a section-owned artifact: the cleanup helper
    # deletes it on every exit path, whether this stage was reached from
    # the section (global preset) or directly by the battery (argument)
    uup_section_urlmap="${urlmap}"
    uup_section_join="${files_dir}/../join.tmp"
    uup_section_join_sorted="${files_dir}/../join-sorted.tmp"
    uup_section_aria="${files_dir}/../aria2-list.tmp"
    uup_section_aria_http="${files_dir}/../aria2-list-http.tmp"
    uup_section_wget="${files_dir}/../wget-list.tmp"
    : > "${uup_section_join}"
    : > "${uup_section_join_sorted}"
    : > "${uup_section_aria}"
    : > "${uup_section_aria_http}"
    : > "${uup_section_wget}"

    # The downloader run logs live in the SPOOL SCRATCH (the audited
    # files/ dir's parent), truncated per acquisition: the LAST run's
    # downloader output stays available for post-mortem there while the
    # persistent download log never receives token URL material (ACQ-01,
    # live-UAT 33 finding #5)
    spool_scratch="$(dirname "${files_dir}")"
    aria_run_log="${spool_scratch}/aria2-run.log"
    wget_run_log="${spool_scratch}/wget-run.log"
    : > "${aria_run_log}"
    : > "${wget_run_log}"

    # The media budget precedes ANY download (ACQ-05, DEC-33-07: warn
    # only). The figures come verbatim from the manifest meta rows -
    # computed twin-side in double precision only (DEC-33-02), never
    # re-summed here.
    total_mib="$(awk -F'|' '$1 == "total_mib" { print $2; exit }' "${manifest}")"
    total_bytes="$(awk -F'|' '$1 == "total_bytes" { print $2; exit }' "${manifest}")"
    build_meta="$(awk -F'|' '$1 == "build" { print $2; exit }' "${manifest}")"
    lang_meta="$(awk -F'|' '$1 == "lang" { print $2; exit }' "${manifest}")"
    if [[ -z "${total_mib}" ]]
    then
        uup_section_cleanup
        log_error_message "The manifest carries no total_mib meta row: ${manifest}"
        increment_error_count
        return 1
    fi
    row_count="$(awk -F'|' 'NF == 3 { n += 1 } END { print n + 0 }' "${manifest}")"
    log_info_message "BUDGET: ${row_count} files, ${total_bytes} bytes, ${total_mib} MiB (target ${build_meta} ${lang_meta})"

    # The url map must be present once the budget is named - the budget
    # is the FIRST observable output of the download stage, and the map
    # check precedes every downloader invocation.
    if [[ ! -s "${urlmap}" ]]
    then
        uup_section_cleanup
        log_error_message "The UUP url map is missing or empty: ${urlmap}"
        increment_error_count
        return 1
    fi

    # Join the manifest sizes with the url map and classify. An empty url
    # for any manifest row aborts the whole download (fail-closed, never
    # a partially mapped set).
    while IFS='|' read -r name sha256 size
    do
        [[ -n "${size}" ]] || continue
        url="$(awk -F'\t' -v n="${name}" '$1 == n { print $2; exit }' "${urlmap}")"
        if [[ -z "${url}" ]]
        then
            uup_section_cleanup
            log_error_message "No URL in the url map for payload ${name} - refusing a partially mapped set"
            increment_error_count
            return 1
        fi
        if [[ "$(uup_classify_size "${size}")" == "aria2" ]]
        then
            # size-descending big-first ordering: the 12-digit zero pad
            # sorts the join lexicographically (= numeric order for every
            # byte count up to 999 GB) and the reverse field sort turns
            # it descending. The big payloads start first, minimizing the
            # token expiry window (the spike-proven coupled-resolve
            # shape).
            printf '%012d|%s|%s\n' "${size}" "${url}" "${name}" >> "${uup_section_join}"
        else
            printf '%s\t%s\n' "${name}" "${url}" >> "${uup_section_wget}"
        fi
    done < "${manifest}"

    aria_rows="$(grep -c '|' "${uup_section_join}" || true)"
    if (( aria_rows > 0 ))
    then
        LC_ALL=C sort -t'|' -k1,1r "${uup_section_join}" > "${uup_section_join_sorted}"
        while IFS='|' read -r sorted_pad sorted_url sorted_name
        do
            printf '%s\n  out=%s\n' "${sorted_url}" "${sorted_name}" >> "${uup_section_aria}"
            # The DEC-33-15 http twin list: same order, original scheme
            http_url="${sorted_url/https:\/\//http://}"
            printf '%s\n  out=%s\n' "${http_url}" "${sorted_name}" >> "${uup_section_aria_http}"
        done < "${uup_section_join_sorted}"

        # The downloader list shape pin (live-UAT 33 finding #5, can-fail):
        # the written lists are validated BEFORE any downloader runs. The
        # aria lists must carry exactly 2 lines per payload - a URI line
        # matching the frozen scheme+charset grammar (no whitespace, no
        # backslash, no second token riding the line) and an indented
        # out= continuation; the wget list exactly 1 name-TAB-URI line per
        # payload. Any other line shape (a glued mega-URI fragment, a bare
        # local path) refuses the acquisition fail-closed with NOTHING
        # downloaded. Diagnostics carry counts only, never line content
        # (ACQ-01).
        pin_bad=0
        pin_expect=$(( aria_rows * 2 ))
        pin_total="$(wc -l < "${uup_section_aria}")"
        pin_match="$(grep -cE '^https?://[A-Za-z0-9._~:/?&=%+-]+$' "${uup_section_aria}" || true)"
        if (( pin_total != pin_expect )) || (( pin_match != aria_rows ))
        then
            pin_bad=1
        fi
        pin_total="$(wc -l < "${uup_section_aria_http}")"
        pin_match="$(grep -cE '^https?://[A-Za-z0-9._~:/?&=%+-]+$' "${uup_section_aria_http}" || true)"
        if (( pin_total != pin_expect )) || (( pin_match != aria_rows ))
        then
            pin_bad=1
        fi
        pin_match="$(grep -cE '^  out=[A-Za-z0-9._-]+$' "${uup_section_aria}" || true)"
        if (( pin_match != aria_rows ))
        then
            pin_bad=1
        fi
        pin_match="$(grep -cE '^  out=[A-Za-z0-9._-]+$' "${uup_section_aria_http}" || true)"
        if (( pin_match != aria_rows ))
        then
            pin_bad=1
        fi
        if (( pin_bad == 1 ))
        then
            uup_section_cleanup
            log_error_message "The downloader list shape pin refused the acquisition - a download list carries a line outside the frozen URI/continuation grammar (glued token, bare path, or second URI on one line). Nothing was downloaded."
            increment_error_count
            return 1
        fi

        # The big payloads download resume-tuned via aria2 (ACQ-02). The
        # binary must exist: the bash engine's aria2 arrives through the
        # package check (30-check-needed-applications) - there is no
        # runtime fetch on this side, so an unavailable binary aborts the
        # section loudly. A multi-GiB payload is NEVER downgraded to a
        # non-resumable download.
        aria_bin="${UUP_ARIA2_BIN:-}"
        if [[ -z "${aria_bin}" ]] && type -P aria2c > /dev/null
        then
            aria_bin="aria2c"
        fi
        if [[ -z "${aria_bin}" ]] || ! command -v "${aria_bin}" > /dev/null
        then
            uup_section_cleanup
            log_error_message "aria2c is required for the big UUP payloads and is not available - refusing to download a multi-GiB payload non-resumably (no wget downgrade)"
            increment_error_count
            return 1
        fi
        aria_opts=( "${aria2c_uup_options[@]}" )
        log_info_message "Downloading ${aria_rows} big upgrade payload(s) resume-tuned via aria2..."
        if ! "${aria_bin}" "${aria_opts[@]}" -i "${uup_section_aria}" -d "${files_dir}" > "${aria_run_log}" 2>&1
        then
            # https-first, one bounded http fallback (DEC-33-15,
            # legitimized by the end-to-end sha256 audit below)
            log_info_message "https token URLs failed - falling back to the original http URLs once (DEC-33-15, legitimized by the end-to-end sha256 audit)"
            if ! "${aria_bin}" "${aria_opts[@]}" -i "${uup_section_aria_http}" -d "${files_dir}" >> "${aria_run_log}" 2>&1
            then
                uup_section_cleanup
                log_error_message "The big UUP payload download failed on both schemes - acquisition aborted"
                increment_error_count
                return 1
            fi
        fi
    fi

    # The small payloads download with wget -c (resumable). The wget list
    # gets its own shape pin (same grammar; runs before THIS downloader -
    # a wget-only set still validates) and wget's console output (-nv
    # echoes the full token URL of every transfer) is confined to the
    # spool scratch run log, never the persistent download log (ACQ-01,
    # live-UAT 33 finding #5)
    wget_rows="$(grep -c . "${uup_section_wget}" || true)"
    if (( wget_rows > 0 ))
    then
        pin_total="$(wc -l < "${uup_section_wget}")"
        pin_match="$(grep -cE $'^[A-Za-z0-9._-]+\thttps?://[A-Za-z0-9._~:/?&=%+-]+$' "${uup_section_wget}" || true)"
        if (( pin_total != wget_rows )) || (( pin_match != wget_rows ))
        then
            uup_section_cleanup
            log_error_message "The downloader list shape pin refused the acquisition - the wget list carries a line outside the frozen name-TAB-URI grammar. Nothing was downloaded."
            increment_error_count
            return 1
        fi
        wget_bin="${UUP_WGET_BIN:-wget}"
        wget_opts=( "${wget_uup_options[@]}" )
        while IFS=$'\t' read -r wname wurl
        do
            if ! "${wget_bin}" "${wget_opts[@]}" -O "${files_dir}/${wname}" "${wurl}" >> "${wget_run_log}" 2>&1
            then
                wurl_http="${wurl/https:\/\//http://}"
                log_info_message "https failed for ${wname} - http fallback (DEC-33-15)"
                if ! "${wget_bin}" "${wget_opts[@]}" -O "${files_dir}/${wname}" "${wurl_http}" >> "${wget_run_log}" 2>&1
                then
                    uup_section_cleanup
                    log_error_message "The download of ${wname} failed on both schemes - acquisition aborted"
                    increment_error_count
                    return 1
                fi
            fi
        done < "${uup_section_wget}"
    fi

    # The fail-closed hash gate runs AFTER download completion
    # unconditionally - a truncated or modified payload cannot pass even
    # though a resume "succeeded" (T-33-08)
    log_info_message "Running the fail-closed hash gate over the whole spool..."
    if ! uup_hash_gate "${manifest}" "${files_dir}"
    then
        uup_section_cleanup
        log_error_message "The upgrade payload integrity verification FAILED - the spool is refused, nothing staged"
        increment_error_count
        return 1
    fi

    uup_section_cleanup
    log_info_message "UUP upgrade payload acquisition complete - spool verified fail-closed, no token material persisted"
    return 0
}

# Stage the verified raw set (plan 33-04, DEC-33-05): the verified spool
# payload set moves into client/upgrade/<cible>-<arche>/<langue>/set/ with
# the acquisition manifest beside it and its integrity class created
# through the existing create_integrity_database machinery (ACQ-04).
#
# Usage: uup_stage_raw_set <cible> <arche> <langue> <spool_manifest>
#
# Contract (parity with the CMD :UpgStageMedia staging half):
#   - the whole-spool sha256 gate has ALREADY passed upstream (the section
#     runs it before calling this stage) - nothing unverified can reach
#     this point;
#   - on a revision change (existing target dir whose manifest uuid
#     differs from the staged uuid) the old target moves aside INTO THE
#     SPOOL first and the aside is removed ONLY after the new set is
#     staged and its manifest reads back (delete-after-success, T-33-12);
#   - the loud Windows-generator-only note fires on every staging: the
#     verified raw set under set/ is the input for the Windows generator's
#     media assembly, never assembled on this side;
#   - the post-success spool purge runs LAST (uup_purge_revisions).
#
# The client tree root is cwd-relative for the engine (the task runs from
# the sh/ directory) with the UUP_CLIENT_ROOT seam for the sandbox battery.
#
# Returns 0 on success; 1 after logging + counting on any refusal (nothing
# staged, any moved-aside old revision restored).

function uup_stage_raw_set ()
{
    local cible="$1" arche="$2" langue="$3" spool_manifest="$4"
    local client_root="${UUP_CLIENT_ROOT:-../client}"
    local spool_root=""
    local target="${client_root}/upgrade/${cible}-${arche}/${langue}"
    local staged_uuid="" target_uuid="" readback_uuid="" aside=""

    # The spool root is the staged manifest's directory (the DEC-33-14
    # working layout: <spool>/manifest.txt + <spool>/files/) - the same
    # derivation the CMD :UpgStageMedia applies to its manifest argument
    spool_root="$(cd "$(dirname "${spool_manifest}")" && pwd)"

    staged_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${spool_manifest}")"
    if [[ -z "${staged_uuid}" ]]
    then
        log_error_message "The spool manifest carries no uuid meta row - staging refused: ${spool_manifest}"
        increment_error_count
        return 1
    fi

    # Revision replacement: move an existing target aside INTO THE SPOOL
    if [[ -d "${target}" ]]
    then
        target_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${target}/manifest.txt" 2> /dev/null)"
        if [[ "${target_uuid}" != "${staged_uuid}" ]]
        then
            aside="${spool_root}/replaced-${staged_uuid}-$$"
            mkdir -p "${spool_root}"
            log_info_message "Existing media found - moving the old tree aside (delete-after-success): ${aside}"
            mv "${target}" "${aside}"
            if [[ $? -ne 0 ]]
            then
                log_error_message "Could not move the existing media aside - staging refused, the old revision stays untouched"
                increment_error_count
                return 1
            fi
        fi
    fi

    mkdir -p "${target}"
    if ! mv "${spool_root}/files" "${target}/set"
    then
        log_error_message "Staging the verified raw set failed - nothing staged"
        increment_error_count
        if [[ -n "${aside}" ]]
        then
            mv "${aside}" "${target}"
        fi
        return 1
    fi

    # The acquisition manifest lands beside the set
    if ! cp "${spool_manifest}" "${target}/manifest.txt"
    then
        log_error_message "Staging the manifest beside the set failed"
        increment_error_count
        if [[ -n "${aside}" ]]
        then
            mv "${aside}" "${target}"
        fi
        return 1
    fi

    # Delete-after-success: the new set must be staged AND its manifest
    # must read back with the staged uuid before the old revision dies
    readback_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${target}/manifest.txt")"
    if [[ "${readback_uuid}" != "${staged_uuid}" ]]
    then
        log_error_message "The staged manifest does not read back with uuid ${staged_uuid} - the old revision is kept for recovery"
        increment_error_count
        return 1
    fi
    if [[ -n "${aside}" ]]
    then
        rm -rf "${aside}"
        log_info_message "Old revision media deleted after successful staging (delete-after-success)"
    fi

    # The media integrity class through the existing machinery (ACQ-04)
    create_integrity_database "${target}" \
        "${client_root}/md/hashes-upgrade-${cible}-${arche}-${langue}.txt"

    # The loud Windows-generator-only note (DEC-33-05): the verified raw
    # set under set/ is the input for the Windows generator to assemble
    log_warning_message "Assembly is Windows-generator-only: the verified raw set is staged under set/ for the Windows generator to assemble"

    # Post-success spool purge (uuid keep-list, ACQ-06)
    uup_purge_revisions "${cible}" "${arche}" "${langue}" "${target}/manifest.txt"
    return 0
}

# The acquisition section (plan 33-03): selection gate, one-shot resolve,
# coupled download + verification; the plan 33-04 staging tail

function acquire_upgrade_payloads ()
{
    local selection_output="" selection_key=""
    local cand_build="" cand_arch="" fu_media=""
    local target_build="" target_arch=""
    local table_file="${UUP_UPGRADES_TABLE:-../client/UpdateTable/upgrades.txt}"
    local lang="${WOU_UPGRADE_LANG:-en-us}"
    local spool_root="${WOU_UPGRADE_SPOOL:-${TMPDIR:-/tmp}/wou-upgrade-spool}"
    local manifest="" files_dir=""

    # No selection = absolute no-op (DEC-33-09 statu quo): zero output,
    # zero side effects. The reader is all-or-nothing - an invalid
    # selection file yields no output and lands here too.
    selection_output="$(read_upgrade_selection "os-upgrades.ini")"
    if [[ -z "${selection_output}" ]]
    then
        return 0
    fi

    # First selected build_arch key whose upgrades.txt row carries
    # fu_media=1 (DEC-33-09). The awk -F'|' field walk keeps empty-field
    # semantics (a for-style split would drop them). One full-FU target
    # per medium: the first qualifying key wins.
    while IFS= read -r selection_key
    do
        [[ -n "${selection_key}" ]] || continue
        cand_build="${selection_key%%_*}"
        cand_arch="${selection_key##*_}"
        fu_media="$(awk -F'|' -v b="${cand_build}" -v a="${cand_arch}" \
            '$1 == b && $2 == a { print $11; exit }' "${table_file}")"
        if [[ "${fu_media}" == "1" ]]
        then
            target_build="${cand_build}"
            target_arch="${cand_arch}"
            break
        fi
    done <<< "${selection_output}"

    if [[ -z "${target_build}" ]]
    then
        return 0
    fi

    log_info_message "UUP upgrade payload acquisition target: ${target_build}-${target_arch} lang ${lang} (fu_media=1)"
    manifest="${spool_root}/manifest.txt"
    files_dir="${spool_root}/files"
    uup_section_urlmap="${spool_root}/url-map.tmp"
    mkdir -p "${spool_root}" "${files_dir}"

    # One-shot resolve (DEC-33-03: exactly 2 API calls, no retry). The
    # WOU_UUP_FIXTURE seam is honored inside the twin. A failed resolve
    # aborts the section loudly - no token material persisted.
    if ! uup_resolve "${target_build}" "${target_arch}" "${lang}" "${manifest}" \
        --urlmap "${uup_section_urlmap}"
    then
        uup_section_cleanup
        log_error_message "The UUP payload resolve failed - acquisition aborted, no token material persisted"
        increment_error_count
        return 0
    fi

    if ! uup_download_and_verify "${manifest}" "${uup_section_urlmap}" "${files_dir}"
    then
        # The download/verify stage already logged + counted + cleaned up
        return 0
    fi

    # The verified spool becomes the staged raw set (plan 33-04): set/ +
    # manifest + integrity class + the loud Windows-only note, then the
    # post-success purge. The staging stage already logged + counted on a
    # refusal.
    uup_stage_raw_set "${target_build}" "${target_arch}" "${lang}" "${manifest}"
    return 0
}

# ========== Commands =====================================================

# No trailing blank line on purpose: with no qualifying selection this
# task must be byte-invisible in the engine run (DEC-33-09 statu quo).
acquire_upgrade_payloads
return 0
