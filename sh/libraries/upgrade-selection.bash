# This file will be sourced by the shell bash.
#
# Filename: upgrade-selection.bash
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
#     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#     General Public License for more details.
#
#     You should have received a copy of the GNU General
#     Public License along with this program.  If not, see
#     <http://www.gnu.org/licenses/>.
#
# Description
#
#     This library reads the chosen EKB upgrade targets from the flat
#     selection file sh/os-upgrades.ini (the "flat twin" written by the
#     .NET generator host next to the sectioned INI; this reader never
#     parses the sectioned INI itself - DEC-32-08).
#
#     The file contains one "<build>_<arch>=on" line per chosen target,
#     exactly like the CMD reader in cmd/DownloadUpdates.cmd
#     (DEC-32-04/DEC-32-05). The grammar is frozen as:
#
#         ^[0-9]+_[A-Za-z0-9]+$   for the key, with the state "on"
#
#     Semantics (identical to the CMD reader, proven by
#     sh/tests/verify-shield-filter.bash):
#
#     - An absent file is a valid "no selection": nothing is printed and
#       the caller keeps the statu-quo behavior. This is also the
#       fresh-clone case (sh/os-upgrades.ini is gitignored runtime
#       state), so the reader never crashes on a missing file (T-32-04).
#     - Any non-empty line that does not match the frozen grammar with
#       the state "on" voids the WHOLE selection (all-or-nothing,
#       DEC-32-08): nothing is printed - never a partial selection
#       (T-32-03). Empty lines are skipped.
#     - Trailing carriage returns are stripped explicitly (the .NET
#       flat-twin writer emits CRLF on Windows hosts): a CRLF-written
#       selection reads as a valid selection instead of silently
#       voiding to no-selection on every Windows-generated medium.
#
#     This library is functions-only: sourcing it has no side effects
#     (the library contract shared by all files in sh/libraries), which
#     is what lets the test battery execute the real reader in a
#     sandbox (DEC-32-09).

# ========== Functions ====================================================

# Read the chosen EKB upgrade targets
#
# Usage: read_upgrade_selection <selection-file>
#
# Prints one grammar-valid "<build>_<arch>" key per line, in file
# order. An absent file (or an empty one) prints nothing and returns
# 0 - "no selection". Any rejected non-empty line voids the whole
# selection: nothing is printed and 0 is returned (all-or-nothing,
# fail-closed to the statu quo - the caller cannot distinguish "no
# selection" from "invalid selection", and both keep today's feed).

function read_upgrade_selection ()
{
    local selection_file="$1"
    local key=""
    local state=""
    local selected_keys_text=""
    local -a selected_keys=()

    # Absent file = no selection: print nothing and stay silent, so a
    # fresh clone or a cleared selection keeps the statu-quo feed
    # (T-32-04: no crash, no unbound variable on the bash side).
    if [[ ! -f "${selection_file}" ]]
    then
        return 0
    fi

    while IFS='=' read -r key state
    do
        # The .NET flat-twin writer (File.WriteAllLines) emits CRLF on
        # Windows hosts: strip the trailing carriage return from both
        # fields, or every Windows-written selection would silently
        # void to no-selection (the state token carries the trailing
        # CR of a well-formed line; the key carries it only on lines
        # without an "=" separator, like CRLF blank lines). The strip
        # is an assignment, so the expansion is not word-split.
        state=${state%$'\r'}
        key=${key%$'\r'}

        # Empty lines (LF or CRLF form) are skipped, not rejected
        if [[ -z "${key}" ]]
        then
            continue
        fi

        # All-or-nothing (DEC-32-08): one grammar-violating or
        # not-enabled line voids the WHOLE selection - a hand-edited or
        # corrupted twin must never yield a partial selection
        # (T-32-03). The frozen grammar matches the CMD reader and the
        # host writer's IsUpgradeKeyShape.
        if ! [[ "${key}" =~ ^[0-9]+_[A-Za-z0-9]+$ ]] || [[ "${state}" != "on" ]]
        then
            return 0
        fi

        selected_keys+=( "${key}" )
    done < "${selection_file}"

    # Keys are printed only after the whole file validated, so a
    # rejected line really leaves the output empty (all-or-nothing):
    # the keys join into one text block and go out in a single write
    if (( "${#selected_keys[@]}" > 0 ))
    then
        printf -v selected_keys_text '%s\n' "${selected_keys[@]}"
        printf '%s' "${selected_keys_text}"
    fi
    return 0
}

return 0
