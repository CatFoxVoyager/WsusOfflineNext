# This file will be sourced by the shell bash.
#
# Filename: upgrade-payloads.bash
#
# Copyright (C) 2016-2022 Hartmut Buhrmester
#                         <wsusoffline-scripts-xxyh@hartmut-buhrmester.de>
#
# License
#
#     This file is free software: you can redistribute it and/or modify
#     it under the terms of the GNU General Public License as published
#     by the Free Software Foundation, either version 3 of the License,
#     or (at your option) any later version.
#
#     This file is distributed in the hope that it will be useful,
#     but WITHOUT ANY WARRANTY; without even the implied warranty of
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#     GNU General Public License for more details.
#
#     You should have received a copy of the GNU General
#     Public License along with this program.  If not, see
#     <http://www.gnu.org/licenses/>.
#
# Description
#
#     UUP dump payload resolver library - the bash twin of the
#     acquisition resolver (plan 33-02, ACQ-01). The VBS twin lives in
#     cmd/ResolveUpgradePayloads.vbs; both MUST emit byte-identical
#     manifests from the same get.php response (the parity contract:
#     one input, two evaluators - the twin pattern of phases 31/32).
#
#     Frozen JSON shape (get.php response, compact single-line JSON as
#     served live; the committed golden fixture
#     tests/fixtures/uup-get-26200-en-us-multiedition.json is the
#     byte-level contract):
#
#         {"response":{"updateName":"...","arch":"amd64",
#          "build":"26200.9974","sku":48,"hasUpdates":true,
#          "uuid":"<revision uuid>",
#          "files":{"<name>":{"sha1":"<40hex>","sha256":"<64hex>",
#                             "size":"<digits>"}, ...}},
#          "jsonApiVersion":"0.2.x"}
#
#     Each files-map entry carries exactly sha1, sha256, size in this
#     field order (the live response's url/uuid/expire/FileLocations
#     token fields are stripped at fixture authoring and are never
#     parsed - ACQ-01: token URLs are never persisted). The envelope
#     carries a revision-level "uuid" field; the live API does not, so
#     uup_resolve overrides the meta uuid with the listid-resolved
#     revision uuid in API mode and uses the envelope value in fixture
#     mode.
#
#     Frozen manifest grammar (DEC-33-02, byte-identical from both
#     twins): 3 "#" header lines + meta rows "key|value" (updateName,
#     uuid, arch, lang, build, total_bytes, total_mib) + one
#     "name|sha256|size" row per payload file in LC_ALL=C name order,
#     every line CRLF-terminated, totals computed ONLY here in double
#     precision (awk doubles - never shell 32-bit arithmetic; a
#     10902883408-byte sum overflows set /a) and consumed downstream as
#     total_mib.
#
#     All-or-nothing (T-33-04/T-33-05, fail-closed): an error field
#     where files are expected, an absent or empty files map, one
#     hostile file name (dot-dot alias, path separator, reserved device
#     name, any character outside ^[A-Za-z0-9._-]+$), a malformed
#     hash/size, or one entry not matching the frozen shape voids the
#     WHOLE resolve: no manifest is written (a stale one is removed),
#     the exit code is nonzero and the reason goes to stdout.
#
#     API contract (DEC-33-03, one-shot): exactly two API calls per
#     resolve - listid.php?search=<build>&sortByDate=1 (filter: build
#     first component == target, arch match after the x64-to-amd64
#     mapping, title without a KB marker, newest created) then ONE
#     get.php?id=<uuid>&lang=<lang>&edition=0. No retry loop: the API
#     rate-limits rapid calls (USER_RATE_LIMITED observed live after
#     ~8 quick calls), so the resolver is one shot per run and fails
#     loudly instead. The arch mapping applies to the API-facing value
#     only; the manifest meta arch carries the API value (amd64).
#
#     Test seam (DEC-33-12): env WOU_UUP_FIXTURE or the --fixture
#     argument routes the resolve at a local fixture file and skips the
#     network entirely (battery-only; unset in production = the normal
#     API path).
#
#     This library is functions-only: sourcing it has no side effects
#     (the library contract shared by all files in sh/libraries), which
#     is what lets the test battery execute the real resolver in a
#     sandbox (DEC-32-09 pattern).

# ========== Functions ====================================================

# Check a get.php response file for the failure shapes the live API
# produces (Pitfall 2 + UNSUPPORTED_LANG)
#
# Usage: uup_check_error_field <json_file>
#
# Prints the failure reason and returns nonzero when the response
# carries an "error" key, or the files map is absent or empty.
# Returns 0 (prints nothing) when the envelope looks resolvable.

function uup_check_error_field ()
{
    local json_file="$1"
    local error_value=""

    if [[ ! -s "${json_file}" ]]
    then
        printf '%s\n' "response file missing or empty: ${json_file}"
        return 1
    fi

    if grep -q '"error":' "${json_file}"
    then
        error_value="$(sed -n 's/.*"error":"\([^"]*\)".*/\1/p' "${json_file}")"
        if [[ -z "${error_value}" ]]
        then
            error_value="(unreadable error value)"
        fi
        printf '%s\n' "${error_value}"
        return 1
    fi

    if ! grep -q '"files":{' "${json_file}"
    then
        printf '%s\n' "files map absent from the response"
        return 1
    fi

    if grep -q '"files":{}' "${json_file}"
    then
        printf '%s\n' "files map is empty"
        return 1
    fi

    return 0
}

# Split a get.php response's files map into one entry line per file
#
# Usage: uup_split_entries <json_file>
#
# Prints one raw entry line per files-map entry, in document order,
# through a temp FILE (the process-substitution form is unreliable with
# piped content on MSYS hosts - the transport hazard measured live in
# plan 33-02). Shared by both extractors; empty output = unparsable map.
# Returns 1 with a diagnostic on stderr when the map cannot be sliced.

function uup_split_entries ()
{
    local json_file="$1"
    local files_slice=""
    local split_file=""

    # Slice the files map value out of the compact single-line JSON:
    # after the "files":{ opener (the first entry's opening quote stays
    # so every entry line is fully quoted) up to the files/response
    # closing braces + jsonApiVersion tail. The strip keeps the LAST
    # entry's own closing brace (the byte sequence is
    # <size>"}}},"jsonApiVer..." = entry-close, files-close,
    # response-close). A response that does not close the map
    # (truncated JSON) keeps its raw tail and fails the anchored census
    # in the extractors (all-or-nothing).
    files_slice="$(sed -n 's/^.*"files":{//p' "${json_file}" \
        | sed 's/}},"jsonApiVersion".*$//')"

    if [[ -z "${files_slice}" ]]
    then
        printf 'no parsable files map in: %s\n' "${json_file}" >&2
        return 1
    fi

    # One entry per line: split before every ",<name>":{" open. The
    # anchored per-entry match in the extractors then cannot grab a
    # suffix of a hostile name (e.g. "evil/../../evil.esd" keeps its
    # separators on its own line and fails the anchor). The split goes
    # through a temp FILE, not a process substitution: on MSYS hosts a
    # large builtin-printf pipe inside <(...) delivers zero bytes to
    # the reader, while the same pipeline through a file is byte-exact
    # everywhere.
    split_file="$(mktemp "${TMPDIR:-/tmp}/uup-split-XXXXXX")" || return 1
    printf '%s' "${files_slice}" \
        | sed 's/,"\([A-Za-z0-9._-]\{1,\}\)":{"/\n"\1":{"/g' \
        > "${split_file}"

    printf '%s' "${split_file}"
    return 0
}

# Extract the files map from a get.php response
#
# Usage: uup_extract_files_map <json_file>
#
# Prints one TSV line "name<TAB>sha256<TAB>size" per files-map entry,
# in document order. The parse is positional per entry block and
# anchored to the sliced files map: ANY entry not matching the frozen
# shape (name grammar inside the entry key, sha1 40 hex, sha256 64 hex,
# size digits, exact field order) voids the whole extraction - nothing
# is printed and 1 is returned (all-or-nothing).

function uup_extract_files_map ()
{
    local json_file="$1"
    local split_file=""
    local -a entries=()
    local entry_line="" matched=0 field_hits=0 rows_text=""

    split_file="$(uup_split_entries "${json_file}")" || return 1

    entries=()
    while IFS= read -r entry_line || [[ -n "${entry_line}" ]]
    do
        # The || [[ -n ]] guard carries the final unterminated line: the
        # split's last entry line has no trailing newline, and a bare
        # read would fill the variable but skip the body (the last
        # entry would silently vanish from the census)
        [[ -z "${entry_line}" ]] && continue
        entries+=( "${entry_line}" )
        entry_line=""
    done < "${split_file}"
    rm -f "${split_file}"

    if (( "${#entries[@]}" == 0 ))
    then
        printf 'empty files map in: %s\n' "${json_file}" >&2
        return 1
    fi

    # Shape census: the number of whole-shape matches must equal the
    # number of sliced entries AND the raw field counts - a truncated
    # or reordered entry fails here. Every entry line ends with its
    # own closing brace. The tolerated entry tail (plan 33-03, extended
    # by the 33-04 live-chain consignment): the LIVE get.php entries
    # continue after the size field with the token fields
    # url/uuid/expire/debug, which the committed fixtures strip at
    # authoring - the anchored shape accepts zero or more
    # ,"url":"..."/,"uuid":"..."/,"expire":<digits>/,"debug":"..."
    # repetitions before the closing brace and captures NONE of them
    # (ACQ-01: the rows stay name|sha256|size only). The debug field
    # carries the FileLocation XML blob (measured live 2026-11-11). Any
    # OTHER field after the size still fails the census (fail-closed
    # against unknown shapes).
    field_hits="$(grep -o '"sha1":' "${json_file}" | wc -l | tr -d '[:space:]')"
    matched=0
    rows_text=""
    for entry_line in "${entries[@]}"
    do
        if [[ "${entry_line}" =~ ^\"([A-Za-z0-9._-]+)\":\{\"sha1\":\"[0-9a-f]{40}\",\"sha256\":\"([0-9a-f]{64})\",\"size\":\"([0-9]+)\"((,\"url\":\"[^\"]*\")|(,\"uuid\":\"[^\"]*\")|(,\"expire\":[0-9]+)|(,\"debug\":\"[^\"]*\"))*\}$ ]]
        then
            matched=$(( matched + 1 ))
            rows_text+="${BASH_REMATCH[1]}"$'\t'"${BASH_REMATCH[2]}"$'\t'"${BASH_REMATCH[3]}"$'\n'
        fi
    done
    if (( matched == 0 )) || (( matched != ${#entries[@]} )) \
        || (( matched != field_hits ))
    then
        printf 'files map does not match the frozen entry shape (%s/%s entries, %s field hits)\n' \
            "${matched}" "${#entries[@]}" "${field_hits}" >&2
        return 1
    fi

    # name<TAB>sha256<TAB>size, emitted only after the whole map
    # validated (all-or-nothing)
    printf '%s' "${rows_text}"
    return 0
}

# Extract the coupled-download url map from a get.php response
#
# Usage: uup_extract_url_map <json_file>
#
# Prints one line "name<TAB>url" per files-map entry whose url field is
# present (the LIVE response shape). All-or-nothing: every sliced entry
# must carry a non-empty url inside the tolerated entry shape, or the
# whole extraction fails with no output. The output is a TEMP runtime
# artifact for the coupled download - token URL material never lands in
# the manifest or any committed file (T-33-09).

function uup_extract_url_map ()
{
    local json_file="$1"
    local split_file=""
    local -a entries=()
    local entry_line="" matched=0 field_hits=0 rows_text=""

    split_file="$(uup_split_entries "${json_file}")" || return 1

    entries=()
    while IFS= read -r entry_line || [[ -n "${entry_line}" ]]
    do
        [[ -z "${entry_line}" ]] && continue
        entries+=( "${entry_line}" )
        entry_line=""
    done < "${split_file}"
    rm -f "${split_file}"

    if (( ${#entries[@]} == 0 ))
    then
        printf 'empty files map in: %s\n' "${json_file}" >&2
        return 1
    fi

    field_hits="$(grep -o '"sha1":' "${json_file}" | wc -l | tr -d '[:space:]')"
    matched=0
    rows_text=""
    for entry_line in "${entries[@]}"
    do
        if [[ "${entry_line}" =~ ^\"([A-Za-z0-9._-]+)\":\{\"sha1\":\"[0-9a-f]{40}\",\"sha256\":\"[0-9a-f]{64}\",\"size\":\"[0-9]+\",\"url\":\"([^\"]+)\" ]]
        then
            matched=$(( matched + 1 ))
            rows_text+="${BASH_REMATCH[1]}"$'\t'"${BASH_REMATCH[2]}"$'\n'
        fi
    done
    if (( matched == 0 )) || (( matched != ${#entries[@]} )) \
        || (( matched != field_hits ))
    then
        printf 'url map does not cover every files-map entry (%s/%s entries carry a url)\n' \
            "${matched}" "${#entries[@]}" "${field_hits}" >&2
        return 1
    fi

    printf '%s' "${rows_text}"
    return 0
}

# Validate extracted rows (all-or-nothing)
#
# Usage: uup_validate_rows  (name<TAB>sha256<TAB>size rows on stdin,
#                            validated TSV rows on stdout)
#
# Row grammar (T-33-05 path-traversal mitigation): name ^[A-Za-z0-9._-]+$
# AND never "." or ".." (the dot aliases the char class alone would
# accept) AND never a reserved device name (CON/PRN/AUX/NUL/COM1-9/
# LPT1-9, case-insensitive, on the full name or the part before the
# first dot); sha256 ^[0-9a-f]{64}$; size ^[0-9]+$. ANY violation
# voids the whole row set: nothing is printed, 1 is returned.

function uup_validate_rows ()
{
    local name="" sha256="" size="" rest="" line=""
    local base_name="" lowered=""
    local -a rows=()
    local rows_text=""

    while IFS=$'\t' read -r name sha256 size rest
    do
        line="${name}"
        if [[ -n "${rest}" ]] || [[ -z "${name}" ]] \
            || [[ -z "${sha256}" ]] || [[ -z "${size}" ]]
        then
            printf 'rejected row (field count): %s\n' "${line}" >&2
            return 1
        fi

        if ! [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]]
        then
            printf 'rejected row (name grammar): %s\n' "${name}" >&2
            return 1
        fi

        # Dot aliases and reserved device names (ASVS V5): rejected
        # explicitly, they are not covered by the char class alone.
        lowered="$(printf '%s' "${name}" | tr '[:upper:]' '[:lower:]')"
        base_name="${name%%.*}"
        if [[ "${name}" == "." ]] || [[ "${name}" == ".." ]] \
            || [[ "${lowered}" =~ ^(con|prn|aux|nul|com[1-9]|lpt[1-9])$ ]] \
            || [[ "$(printf '%s' "${base_name}" | tr '[:upper:]' '[:lower:]')" =~ ^(con|prn|aux|nul|com[1-9]|lpt[1-9])$ ]]
        then
            printf 'rejected row (hostile name): %s\n' "${name}" >&2
            return 1
        fi

        if ! [[ "${sha256}" =~ ^[0-9a-f]{64}$ ]]
        then
            printf 'rejected row (sha256 grammar): %s\n' "${name}" >&2
            return 1
        fi

        if ! [[ "${size}" =~ ^[0-9]+$ ]]
        then
            printf 'rejected row (size grammar): %s\n' "${name}" >&2
            return 1
        fi

        rows+=( "${name}"$'\t'"${sha256}"$'\t'"${size}" )
    done

    if (( ${#rows[@]} == 0 ))
    then
        printf 'no rows to validate\n' >&2
        return 1
    fi

    # Rows are printed only after the whole set validated
    # (all-or-nothing, T-32-03 pattern)
    rows_text="$(printf '%s\n' "${rows[@]}")"
    printf '%s\n' "${rows_text}"
    return 0
}

# Emit the DEC-33-02 manifest
#
# Usage: uup_emit_manifest <rows_file> <updateName> <uuid> <arch> <lang> <build> <out_file>
#
# Byte contract (identical in the VBS twin): 3 header lines naming both
# twins and the consumers, meta rows key|value, one name|sha256|size
# row per entry sorted with LC_ALL=C sort, CRLF line endings, totals in
# awk double arithmetic. The file is written through a temp file and
# moved into place, so a failed emission never leaves a partial
# manifest.

function uup_emit_manifest ()
{
    local rows_file="$1" update_name="$2" uuid="$3" arch="$4" lang="$5" build="$6" out_file="$7"
    local sorted_rows="" temp_out="" meta_value=""

    if [[ ! -s "${rows_file}" ]]
    then
        printf 'no rows to emit\n' >&2
        return 1
    fi

    # Meta values must be pipe-free and non-empty: a "|" inside any
    # meta value would corrupt the key|value grammar
    for meta_value in "${update_name}" "${uuid}" "${arch}" "${lang}" "${build}"
    do
        if [[ -z "${meta_value}" ]] || [[ "${meta_value}" == *"|"* ]]
        then
            printf 'invalid meta value\n' >&2
            return 1
        fi
    done

    sorted_rows="$(LC_ALL=C sort "${rows_file}")"
    if [[ -z "${sorted_rows}" ]]
    then
        printf 'row sort produced nothing\n' >&2
        return 1
    fi

    temp_out="${out_file}.tmp"
    printf '%s\n' "${sorted_rows}" \
        | LC_ALL=C awk -F'\t' \
            -v update_name="${update_name}" \
            -v uuid="${uuid}" \
            -v arch="${arch}" \
            -v lang="${lang}" \
            -v build="${build}" '
        BEGIN {
            print "# client/upgrade/<cible>-<arche>/<langue>/manifest.txt - GENERATED from the UUP dump API (get.php) by the resolver twins (sh/libraries/upgrade-payloads.bash + cmd/ResolveUpgradePayloads.vbs); DO NOT EDIT\r"
            print "# Format: meta rows key|value (updateName, uuid, arch, lang, build, total_bytes, total_mib) + one name|sha256|size row per payload file in LC_ALL=C name order; CRLF; token URLs never persisted (ACQ-01)\r"
            print "# Consumers: coupled download (plan 33-03) reads the rows; revision purge (plan 33-04) keys on the uuid meta row; budgets consume total_mib (DEC-33-07)\r"
            print "updateName|" update_name "\r"
            print "uuid|" uuid "\r"
            print "arch|" arch "\r"
            print "lang|" lang "\r"
            print "build|" build "\r"
            row_count = 0
        }
        {
            row_count += 1
            rows[row_count] = $1 "|" $2 "|" $3
            total_bytes += $3 + 0
        }
        END {
            # The meta rows stay contiguous (DEC-33-02): the two total
            # rows close the meta block BEFORE the first payload row,
            # so the awk double accumulation must complete first - the
            # row lines are buffered above and flushed here.
            printf "total_bytes|%d\r\n", total_bytes
            printf "total_mib|%d\r\n", int(total_bytes / 1048576)
            for (i = 1; i <= row_count; i += 1)
            {
                print rows[i] "\r"
            }
        }' > "${temp_out}"

    if [[ ! -s "${temp_out}" ]]
    then
        rm -f "${temp_out}"
        printf 'manifest emission produced nothing\n' >&2
        return 1
    fi

    mv -f "${temp_out}" "${out_file}"
    return 0
}

# Extract the revision metadata from a get.php envelope
#
# Usage: uup_extract_meta <json_file>
#
# Prints TSV lines "key<TAB>value" for updateName, uuid, arch, build.
# Any missing field voids the extraction (nonzero, no output).

function uup_extract_meta ()
{
    local json_file="$1"
    local update_name="" uuid="" arch="" build=""

    update_name="$(sed -n 's/.*"updateName":"\([^"]*\)".*/\1/p' "${json_file}")"
    uuid="$(sed -n 's/.*"uuid":"\([0-9a-f-]\{36\}\)".*/\1/p' "${json_file}")"
    arch="$(sed -n 's/.*"arch":"\([A-Za-z0-9_]\{1,\}\)".*/\1/p' "${json_file}")"
    build="$(sed -n 's/.*"build":"\([0-9.]\{1,\}\)".*/\1/p' "${json_file}")"

    if [[ -z "${update_name}" ]] || [[ -z "${uuid}" ]] \
        || [[ -z "${arch}" ]] || [[ -z "${build}" ]]
    then
        printf 'envelope metadata incomplete (updateName/uuid/arch/build)\n' >&2
        return 1
    fi

    printf 'updateName\t%s\n' "${update_name}"
    printf 'uuid\t%s\n' "${uuid}"
    printf 'arch\t%s\n' "${arch}"
    printf 'build\t%s\n' "${build}"
    return 0
}

# The resolve chain (DEC-33-03)
#
# Usage: uup_resolve <target_build> <arch> <lang> <out_manifest> [--fixture <path>] [--urlmap <path>]
#
# Fixture mode (DEC-33-12): --fixture <path> or env WOU_UUP_FIXTURE -
# the local file replaces the network entirely (battery-only seam).
# API mode: listid.php?search=<build>&sortByDate=1, filter (build first
# component == target, arch match after x64-to-amd64, no KB marker in
# the title, newest created), then exactly ONE get.php?id=<uuid>&lang=
# <lang>&edition=0. Exactly 2 API calls, no retry (rate limit, Pitfall
# 2). A stale manifest at <out_manifest> is removed up front: a failed
# resolve never leaves an old manifest looking fresh. Any failure
# prints the reason and returns nonzero with NO manifest written.

function uup_resolve ()
{
    local target_build="$1" arch="$2" lang="$3" out_manifest="$4"
    local fixture_path=""
    local urlmap_path="" urlmap_tmp=""
    local api_arch="" listid_json="" get_json="" resolved_uuid=""
    local candidate_line="" best_created="" best_uuid="" filter_file=""
    local meta_file="" rows_file=""

    # Optional switches after the 4 positional arguments (plan 33-03):
    # --fixture <path> (DEC-33-12 seam) and --urlmap <path> (the coupled-
    # download side map, API mode only). The fixture seam also honors the
    # WOU_UUP_FIXTURE environment variable.
    local switch_index=5
    local next_index=0
    while [[ "${!switch_index:-}" != "" ]]
    do
        next_index=$(( switch_index + 1 ))
        if [[ "${!switch_index}" == "--fixture" ]]
        then
            fixture_path="${!next_index}"
            switch_index=$(( switch_index + 2 ))
        elif [[ "${!switch_index}" == "--urlmap" ]]
        then
            urlmap_path="${!next_index}"
            switch_index=$(( switch_index + 2 ))
        else
            printf 'unknown argument: %s\n' "${!switch_index}" >&2
            return 1
        fi
    done
    if [[ -z "${fixture_path}" && -n "${WOU_UUP_FIXTURE:-}" ]]
    then
        fixture_path="${WOU_UUP_FIXTURE}"
    fi

    if ! [[ "${target_build}" =~ ^[0-9]+$ ]]
    then
        printf 'invalid target build: %s\n' "${target_build}" >&2
        return 1
    fi
    if [[ "${arch}" != "x64" ]] && [[ "${arch}" != "x86" ]]
    then
        printf 'invalid arch (repo-facing x64|x86 expected): %s\n' "${arch}" >&2
        return 1
    fi
    if [[ -z "${lang}" ]] || [[ "${lang}" == *"|"* ]]
    then
        printf 'invalid language parameter\n' >&2
        return 1
    fi
    if [[ -z "${out_manifest}" ]]
    then
        printf 'missing output manifest path\n' >&2
        return 1
    fi

    # Stale-manifest hygiene (fail-closed)
    rm -f "${out_manifest}"

    if [[ -n "${fixture_path}" ]]
    then
        # Fixture mode: local file, zero network calls
        if [[ ! -f "${fixture_path}" ]]
        then
            printf 'fixture file missing: %s\n' "${fixture_path}" >&2
            return 1
        fi
        get_json="${fixture_path}"
    else
        # API mode - exactly two calls, one-shot (no retry loop)
        case "${arch}" in
            x64) api_arch="amd64" ;;
            *)   api_arch="${arch}" ;;
        esac

        listid_json="$(mktemp "${TMPDIR:-/tmp}/uup-listid-XXXXXX")" || return 1
        if ! wget -q -O "${listid_json}" \
            "https://api.uupdump.net/listid.php?search=${target_build}&sortByDate=1"
        then
            rm -f "${listid_json}"
            printf 'listid.php call failed (one-shot resolve, no retry)\n' >&2
            return 1
        fi

        # Filter: build first component == target, arch match, no KB
        # marker in the title, newest created wins. The candidate walk
        # goes through a temp FILE (the process-substitution form is
        # unreliable with piped content on MSYS hosts - same transport
        # hazard as the files-map split). The sed carries ALL FIVE fields
        # through (title, build, arch, created, uuid) - the arch field
        # MUST survive into the TSV or the awk arch filter compares the
        # created timestamp instead and nothing ever matches (measured
        # live by the 33-04 live-chain consignment: the fixture path
        # skips the listid call, so this filter's first real-data run was
        # 33-04's).
        filter_file="$(mktemp "${TMPDIR:-/tmp}/uup-filter-XXXXXX")" || return 1
        grep -oE '"title":"[^"]*","build":"[0-9]+\.[0-9]+","arch":"[A-Za-z0-9_]+","created":[0-9]+,"uuid":"[0-9a-f-]{36}"' "${listid_json}" \
            | sed -E 's/^"title":"([^"]*)","build":"([0-9]+\.[0-9]+)","arch":"([A-Za-z0-9_]+)","created":"?([0-9]+)"?,"uuid":"([0-9a-f-]{36})"$/\1\t\2\t\3\t\4\t\5/' \
            | awk -F'\t' -v want_arch="${api_arch}" '$3 == want_arch' \
            > "${filter_file}"

        best_created=""
        while IFS=$'\t' read -r candidate_title candidate_build candidate_arch candidate_created candidate_uuid
        do
            candidate_line="${candidate_build%%.*}"
            if [[ "${candidate_line}" != "${target_build}" ]]
            then
                continue
            fi
            if printf '%s' "${candidate_title}" | grep -qiE 'kb[0-9]'
            then
                continue
            fi
            if [[ -z "${best_created}" ]] \
                || (( candidate_created > best_created ))
            then
                best_created="${candidate_created}"
                best_uuid="${candidate_uuid}"
            fi
        done < "${filter_file}"
        rm -f "${filter_file}"

        rm -f "${listid_json}"

        if [[ -z "${best_uuid}" ]]
        then
            printf 'no matching update row for build %s arch %s\n' "${target_build}" "${api_arch}" >&2
            return 1
        fi
        resolved_uuid="${best_uuid}"

        get_json="$(mktemp "${TMPDIR:-/tmp}/uup-get-XXXXXX")" || return 1
        if ! wget -q -O "${get_json}" \
            "https://api.uupdump.net/get.php?id=${best_uuid}&lang=${lang}&edition=0"
        then
            rm -f "${get_json}"
            printf 'get.php call failed (one-shot resolve, no retry)\n' >&2
            return 1
        fi
    fi

    meta_file="$(mktemp "${TMPDIR:-/tmp}/uup-meta-XXXXXX")" || return 1
    rows_file="$(mktemp "${TMPDIR:-/tmp}/uup-rows-XXXXXX")" || return 1

    local meta_update_name="" meta_uuid="" meta_arch="" meta_build=""
    local resolve_error=""

    if resolve_error="$(uup_check_error_field "${get_json}")"
    then
        if ! uup_extract_meta "${get_json}" > "${meta_file}"
        then
            resolve_error="envelope metadata extraction failed"
        else
            meta_update_name="$(awk -F'\t' '$1 == "updateName" { print $2 }' "${meta_file}")"
            meta_uuid="$(awk -F'\t' '$1 == "uuid" { print $2 }' "${meta_file}")"
            meta_arch="$(awk -F'\t' '$1 == "arch" { print $2 }' "${meta_file}")"
            meta_build="$(awk -F'\t' '$1 == "build" { print $2 }' "${meta_file}")"
            # API mode: the listid-resolved revision uuid is the meta
            # uuid (the get.php envelope carries no revision-level uuid)
            if [[ -n "${resolved_uuid}" ]]
            then
                meta_uuid="${resolved_uuid}"
            fi
            if uup_extract_files_map "${get_json}" \
                | uup_validate_rows > "${rows_file}"
            then
                if uup_emit_manifest "${rows_file}" \
                    "${meta_update_name}" "${meta_uuid}" "${meta_arch}" \
                    "${lang}" "${meta_build}" "${out_manifest}"
                then
                    rm -f "${meta_file}" "${rows_file}"
                    if [[ -n "${urlmap_path}" ]]
                    then
                        if [[ -n "${fixture_path}" ]]
                        then
                            # Fixture mode: the committed fixtures carry
                            # no url fields (token material stripped at
                            # authoring) - the coupled download against a
                            # fixture-resolved manifest is a battery-side
                            # concern (DEC-33-12), no map is written
                            :
                        else
                            # API mode: write the name-TAB-url side map
                            # for the coupled download through a temp
                            # file and move it into place - a failed
                            # extraction removes the fresh manifest too
                            # (fail-closed whole resolve; T-33-09: the
                            # map is a TEMP runtime artifact consumed by
                            # this run only)
                            urlmap_tmp="${urlmap_path}.part"
                            if uup_extract_url_map "${get_json}" > "${urlmap_tmp}" \
                               && [[ -s "${urlmap_tmp}" ]]
                            then
                                mv -f "${urlmap_tmp}" "${urlmap_path}"
                            else
                                rm -f "${urlmap_tmp}" "${out_manifest}"
                                rm -f "${get_json}"
                                printf 'url map extraction failed\n' >&2
                                return 1
                            fi
                        fi
                    fi
                    [[ -n "${fixture_path}" ]] || rm -f "${get_json}"
                    return 0
                fi
                resolve_error="manifest emission failed"
            else
                resolve_error="row validation failed"
            fi
        fi
    fi

    rm -f "${meta_file}" "${rows_file}" "${out_manifest}"
    [[ -n "${fixture_path}" ]] || rm -f "${get_json}"
    printf 'resolve failed: %s\n' "${resolve_error}" >&2
    return 1
}

# Classify a payload byte size (plan 33-03, ACQ-02)
#
# Usage: uup_classify_size <bytes>
#
# Prints "aria2" for byte counts >= 104857600 (100 MiB - resumable,
# segmented download) and "wget" below. Native 64-bit arithmetic only -
# a 10902883408-byte total must never touch a 32-bit form (DEC-33-02
# extension). Exit 1 on a non-numeric argument.

function uup_classify_size ()
{
    local bytes="$1"

    if ! [[ "${bytes}" =~ ^[0-9]+$ ]]
    then
        printf 'invalid size: %s\n' "${bytes}" >&2
        return 1
    fi
    if (( bytes >= 104857600 ))
    then
        printf 'aria2\n'
    else
        printf 'wget\n'
    fi
    return 0
}

# Resolve the hashdeep binary for the UUP hash gate
#
# Usage: uup_resolve_hashdeep
#
# Prints the binary to use: the UUP_HASHDEEP_BIN override first (battery
# seam), then bare hashdeep (the integrity-database idiom), then the
# vendored client/bin tool. Exit 1 loudly when nothing resolves - the
# fail-closed gate never runs against nothing.

function uup_resolve_hashdeep ()
{
    if [[ -n "${UUP_HASHDEEP_BIN:-}" ]] && [[ -x "${UUP_HASHDEEP_BIN}" ]]
    then
        printf '%s\n' "${UUP_HASHDEEP_BIN}"
        return 0
    fi
    if type -P hashdeep > /dev/null
    then
        printf 'hashdeep\n'
        return 0
    fi
    local candidate=""
    for candidate in "../client/bin/hashdeep64.exe" "../client/bin/hashdeep.exe"
    do
        if [[ -x "${candidate}" ]]
        then
            printf '%s\n' "${candidate}"
            return 0
        fi
    done
    printf 'no hashdeep binary found (checked UUP_HASHDEEP_BIN, PATH, ../client/bin)\n' >&2
    return 1
}

# The fail-closed spool hash gate (plan 33-03, ACQ-02 + the sha256 half
# of ACQ-04)
#
# Usage: uup_hash_gate <manifest> <spool_dir>
#
# Generates a hashdeep-format expectation file in a TEMP directory from
# the manifest rows (size,sha256,name - the unquoted CSV hashdeep writes,
# size always the first column), audits the WHOLE spool with
# hashdeep -a -vv -k -b -r, and returns nonzero on ANY mismatch with
# NOTHING moved (T-33-08: the structural after-resume re-verify - a
# truncated or modified payload cannot stage even though a resume
# "succeeded"). The expectation lives OUTSIDE the audited spool (the -k
# file itself would count as a new file otherwise) and dies with the
# audit. Any malformed manifest row is a loud failure (the manifest is a
# generated contract), never a skipped row.

function uup_hash_gate ()
{
    local manifest="$1" spool_dir="$2"
    local hashdeep_bin="" exp_dir="" exp_file=""
    local name="" hash="" size="" rest=""
    local bad=0 rows=0 audit_rc=0

    if [[ ! -s "${manifest}" ]]
    then
        printf 'manifest missing or empty: %s\n' "${manifest}" >&2
        return 1
    fi
    if [[ ! -d "${spool_dir}" ]]
    then
        printf 'spool directory missing: %s\n' "${spool_dir}" >&2
        return 1
    fi
    hashdeep_bin="$(uup_resolve_hashdeep)" || return 1

    exp_dir="$(mktemp -d "${TMPDIR:-/tmp}/uup-expect-XXXXXX")" || return 1
    exp_file="${exp_dir}/expectation.txt"
    {
        printf '%s\n' '%%%% HASHDEEP-1.0'
        printf '%s\n' '%%%% size,sha256,filename'
        printf '%s\n' '## Generated from the upgrade payload manifest by uup_hash_gate - TEMP runtime artifact, never persisted'
    } > "${exp_file}"

    # Manifest rows -> expectation. Meta rows carry only 2 pipe fields
    # and are skipped by the empty-size guard; comment lines have no
    # pipe-delimited size either. The row grammar mirrors the resolver's
    # frozen contract.
    while IFS='|' read -r name hash size rest
    do
        [[ -n "${size}" ]] || continue
        if [[ -n "${rest}" ]] \
            || ! [[ "${name}" =~ ^[A-Za-z0-9._-]+$ ]] \
            || ! [[ "${hash}" =~ ^[0-9a-f]{64}$ ]] \
            || ! [[ "${size}" =~ ^[0-9]+$ ]]
        then
            printf 'malformed manifest row refused by the hash gate: %s\n' "${name}" >&2
            bad=1
            break
        fi
        printf '%s,%s,%s\n' "${size}" "${hash}" "${name}" >> "${exp_file}"
        rows=$(( rows + 1 ))
    done < "${manifest}"

    if (( bad == 1 )) || (( rows == 0 ))
    then
        rm -rf "${exp_dir}"
        [[ "${bad}" == "1" ]] || printf 'manifest carries no payload rows: %s\n' "${manifest}" >&2
        return 1
    fi

    "${hashdeep_bin}" -a -vv -k "${exp_file}" -b -r "${spool_dir}"
    audit_rc=$?
    rm -rf "${exp_dir}"
    if (( audit_rc != 0 ))
    then
        printf 'upgrade payload integrity verification FAILED - the spool is refused, nothing is staged\n' >&2
        return 1
    fi
    return 0
}

# Purge the spool's revision churn for a target (plan 33-04, ACQ-06,
# DEC-33-08, research Pitfall 6).
#
# Usage: uup_purge_revisions <cible> <arche> <langue> <staged_manifest>
#
# The CMD twin is :UpgPurgeRevisions in cmd/UpgradePayloads.cmd - parity of
# BEHAVIOR, not bytes.
#
# Contract: invoked ONLY after successful staging; reads the STAGED
# manifest's uuid meta row (the keep-list source), archives the current
# working set (the spool root's manifest.txt + files/) under the staged
# uuid when the keep-list revision dir does not exist yet, then removes
# every sibling spool set under
#
#     <spool>/<cible>-<arche>-<langue>/<revision>/ (each with manifest.txt)
#
# whose manifest uuid differs from the staged uuid. Zero matching siblings
# = zero deletions. A missing or unparseable staged manifest refuses
# loudly - a failed or interrupted run removes NOTHING (Pitfall 6). This
# function never touches client/upgrade/ content (staging's
# delete-after-success replacement already handled the old revision there)
# and never registers the subtree with the existing cleanup walk (the walk
# at sh/libraries/cleanup-client-directories.bash iterates explicitly
# passed dirs only).
#
# Spool root resolution mirrors the acquisition section: WOU_UPGRADE_SPOOL
# overridable, default ${TMPDIR:-/tmp}/wou-upgrade-spool (DEC-33-14).
#
# Returns 0 on a completed purge (including 0 removals); 1 after logging +
# counting when the staged manifest is missing or carries no uuid.

function uup_purge_revisions ()
{
    local cible="$1" arche="$2" langue="$3" staged_manifest="$4"
    local spool_root="${WOU_UPGRADE_SPOOL:-${TMPDIR:-/tmp}/wou-upgrade-spool}"
    local sets_dir="" staged_uuid="" working_uuid="" revision=""
    local revision_uuid="" kept=0 removed=0

    if [[ -z "${staged_manifest}" ]] || [[ ! -s "${staged_manifest}" ]]
    then
        log_error_message "The staged manifest is missing or empty - the purge refuses without proof of successful staging: ${staged_manifest}"
        increment_error_count
        return 1
    fi
    staged_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${staged_manifest}")"
    if [[ -z "${staged_uuid}" ]]
    then
        log_error_message "The staged manifest carries no uuid meta row - purge refused: ${staged_manifest}"
        increment_error_count
        return 1
    fi

    sets_dir="${spool_root}/${cible}-${arche}-${langue}"
    mkdir -p "${sets_dir}"

    # Archive the current working set under the staged uuid (the spool
    # keeps exactly the current uuid set per target-lang-arch). Only when
    # the keep-list revision dir does not exist yet and the working
    # manifest matches the staged uuid.
    if [[ ! -d "${sets_dir}/${staged_uuid}" && -s "${spool_root}/manifest.txt" ]]
    then
        working_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${spool_root}/manifest.txt")"
        if [[ "${working_uuid}" == "${staged_uuid}" ]]
        then
            mkdir -p "${sets_dir}/${staged_uuid}"
            mv "${spool_root}/manifest.txt" "${sets_dir}/${staged_uuid}/manifest.txt"
            if [[ -d "${spool_root}/files" ]]
            then
                mv "${spool_root}/files" "${sets_dir}/${staged_uuid}/files"
            fi
            log_info_message "Working set archived under the staged uuid: ${staged_uuid}"
        fi
    fi

    # The keep-list walk: remove every sibling set whose uuid differs
    for revision in "${sets_dir}"/*
    do
        [[ -d "${revision}" ]] || continue
        revision_uuid="$(awk -F'|' '$1 == "uuid" { print $2; exit }' "${revision}/manifest.txt" 2> /dev/null)"
        if [[ "${revision_uuid}" == "${staged_uuid}" ]]
        then
            kept=$(( kept + 1 ))
        else
            rm -rf "${revision}"
            removed=$(( removed + 1 ))
            log_info_message "Purged stale revision set ${revision##*/} (uuid ${revision_uuid})"
        fi
    done

    if (( removed == 0 ))
    then
        log_info_message "PURGE: 0 removals - the spool keeps only the staged revision ${staged_uuid} (${kept} set(s) kept)"
    else
        log_info_message "PURGE: ${removed} stale revision set(s) removed, ${kept} kept - the spool holds only revision ${staged_uuid} for ${cible}-${arche}-${langue}"
    fi
    return 0
}

return 0
