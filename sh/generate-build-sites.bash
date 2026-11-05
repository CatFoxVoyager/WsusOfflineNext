#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Build Site Propagation Tool (Linux Bash Engine)
# File: sh/generate-build-sites.bash
#
# Propagates build definitions from static/builds.ini into:
#   1. cmd/DownloadUpdates.cmd
#   2. sh/download-updates-tasks/60-main-updates.bash
#   3. sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
#   4. client/UpdateTable/builds.txt (whole-file emission - the native
#      installer's Enablement-Package data file, consumed at GUI runtime
#      by src-native/installer/buildsupgrade.pas)
#
# Preserves CRLF line endings and Windows-1252 bytes.
# =======================================================================

set -e
set -u
export LC_ALL=C

if [ -d "/usr/bin" ] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
builds_ini="${repo_root}/static/builds.ini"

check_only=false
for arg in "$@"; do
    case "$arg" in
        --check|-check)
            check_only=true
            ;;
    esac
done

if [[ ! -f "$builds_ini" ]]; then
    echo "ERROR: static/builds.ini not found at $builds_ini" >&2
    exit 1
fi

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_build_sites')"
trap 'rm -rf "$tmp_dir"' EXIT

# -----------------------------------------------------------------------
# Parse static/builds.ini and generate replacement blocks using awk
# -----------------------------------------------------------------------
awk -v tmp_dir="$tmp_dir" '
BEGIN {
    n_sec = 0
}
/^\[.*\]/ {
    line = $0
    sub(/\r$/, "", line)
    sec = substr(line, 2, length(line) - 2)
    sections[++n_sec] = sec
    next
}
/^[a-zA-Z0-9_]+=/ {
    line = $0
    sub(/\r$/, "", line)
    eq = index(line, "=")
    k = substr(line, 1, eq - 1)
    v = substr(line, eq + 1)
    data[sec, k] = v
    next
}
END {
    # -------------------------------------------------------------------
    # WIN11 build selection data (shared by the sites below; the former
    # generator-GUI site that consumed block1.txt was removed in Phase 25
    # together with its target file)
    # -------------------------------------------------------------------
    n_w11 = 0
    for (i = 1; i <= n_sec; i++) {
        s = sections[i]
        if (data[s, "os_family"] == "win11" && data[s, "arch"] == "x64" && data[s, "status"] != "ineligible") {
            idx = ++n_w11
            w11_builds[idx] = data[s, "build"] + 0
            w11_names[idx] = data[s, "marketing_name"]
            w11_defs[idx] = data[s, "default_enabled"]
        }
    }
    # Sort ascending
    for (i = 1; i <= n_w11 - 1; i++) {
        for (j = i + 1; j <= n_w11; j++) {
            if (w11_builds[i] > w11_builds[j]) {
                t = w11_builds[i]; w11_builds[i] = w11_builds[j]; w11_builds[j] = t
                t = w11_names[i]; w11_names[i] = w11_names[j]; w11_names[j] = t
                t = w11_defs[i]; w11_defs[i] = w11_defs[j]; w11_defs[j] = t
            }
        }
    }
    w11_space_str = ""
    for (i = 1; i <= n_w11; i++) {
        if (i > 1) {
            w11_space_str = w11_space_str " "
        }
        w11_space_str = w11_space_str w11_builds[i]
    }

    # -------------------------------------------------------------------
    # Site 1: cmd/DownloadUpdates.cmd
    # -------------------------------------------------------------------
    f2 = tmp_dir "/block2.txt"
    printf "  set TMP_BUILDS_ALL_WIN11=%s\n", w11_space_str > f2
    close(f2)

    # -------------------------------------------------------------------
    # Site 2: sh/download-updates-tasks/60-main-updates.bash
    # -------------------------------------------------------------------
    f3 = tmp_dir "/block3.txt"
    x86_list = "10240 14393 17763 19041"
    x64_list = "10240 14393 17763 19041 20348 " w11_space_str
    printf "w100_x86_all_versions=( %s )\n", x86_list > f3
    printf "w100_x64_all_versions=( %s )\n", x64_list > f3
    close(f3)

    # -------------------------------------------------------------------
    # Site 3: sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
    # -------------------------------------------------------------------
    f4 = tmp_dir "/block4.txt"
    printf "w100_keys=(\n" > f4
    printf "    \"10240_x86\"  \"10240_x64\"\n" > f4
    printf "    \"14393_x86\"  \"14393_x64\"\n" > f4
    printf "    \"17763_x86\"  \"17763_x64\"\n" > f4
    printf "    \"19041_x86\"  \"19041_x64\"\n" > f4
    printf "                 \"20348_x64\"\n" > f4
    printf "                 \"22000_x64\"\n" > f4
    printf "                 \"22621_x64\"\n" > f4
    printf "                 \"22631_x64\"\n" > f4
    printf "                 \"26100_x64\"\n" > f4
    printf "                 \"26200_x64\"\n" > f4
    printf "                 \"26300_x64\"\n" > f4
    printf ")\n\n" > f4

    keys_str = "10240_x86 10240_x64 14393_x86 14393_x64 17763_x86 17763_x64 19041_x86 19041_x64 20348_x64 22000_x64 22621_x64 22631_x64 26100_x64 26200_x64 26300_x64"
    n_k = split(keys_str, arr_k, " ")
    printf "declare -A w100_labels=(\n" > f4
    for (i = 1; i <= n_k; i++) {
        k = arr_k[i]
        split(k, parts, "_")
        s = "w100-" parts[2] "-" parts[1]
        printf "    [%s]=\"%s\"\n", k, data[s, "dialog_label"] > f4
    }
    printf ")\n\n" > f4

    printf "declare -A w100_values=(\n" > f4
    printf "    [10240_x86]=\"%s\"  [10240_x64]=\"%s\"\n", data["w100-x86-10240", "dialog_value"], data["w100-x64-10240", "dialog_value"] > f4
    printf "    [14393_x86]=\"%s\"   [14393_x64]=\"%s\"\n", data["w100-x86-14393", "dialog_value"], data["w100-x64-14393", "dialog_value"] > f4
    printf "    [17763_x86]=\"%s\"   [17763_x64]=\"%s\"\n", data["w100-x86-17763", "dialog_value"], data["w100-x64-17763", "dialog_value"] > f4
    printf "    [19041_x86]=\"%s\"   [19041_x64]=\"%s\"\n", data["w100-x86-19041", "dialog_value"], data["w100-x64-19041", "dialog_value"] > f4
    printf "                       [20348_x64]=\"%s\"\n", data["w100-x64-20348", "dialog_value"] > f4
    printf "                       [22000_x64]=\"%s\"\n", data["w100-x64-22000", "dialog_value"] > f4
    printf "                       [22621_x64]=\"%s\"\n", data["w100-x64-22621", "dialog_value"] > f4
    printf "                       [22631_x64]=\"%s\"\n", data["w100-x64-22631", "dialog_value"] > f4
    printf "                       [26100_x64]=\"%s\"\n", data["w100-x64-26100", "dialog_value"] > f4
    printf "                       [26200_x64]=\"%s\"\n", data["w100-x64-26200", "dialog_value"] > f4
    printf "                       [26300_x64]=\"%s\"\n", data["w100-x64-26300", "dialog_value"] > f4
    printf ")\n" > f4
    close(f4)

    # -------------------------------------------------------------------
    # Shared 12-row census (reg_secs/arr_rs) for client/UpdateTable/
    # builds.txt below - the retired registry-table site introduced the
    # list; the data-file emission still iterates it.
    # -------------------------------------------------------------------
    reg_secs = "w100-x86-19041 w100-x64-19041 w100-x86-19042 w100-x64-19042 w100-x86-19044 w100-x64-19044 w100-x86-19045 w100-x64-19045 w100-x64-26100 w100-x64-26200 w100-x64-26300 w100-x64-28000"
    n_rs = split(reg_secs, arr_rs, " ")

    # -------------------------------------------------------------------
    # client/UpdateTable/builds.txt - the native installer Enablement
    # data file (plan 26-02). Pipe-delimited rows, hash-comment lines,
    # CRLF. 12-row census and is_enforced formula identical to the
    # retired registry table (the au3 site left at plan 03 - sites 3).
    # -------------------------------------------------------------------
    f6 = tmp_dir "/builds_txt_data.txt"
    printf "# client/UpdateTable/builds.txt - GENERATED from static/builds.ini by generate-build-sites (bash+vbs twins); DO NOT EDIT\n" > f6
    printf "# Format: build|arch|os_family|servicing_branch|status|ekb_source_build|ekb_kb|ekb_prereq_kb|ekb_min_revision|is_enforced\n" > f6
    printf "# Consumed at GUI runtime by src-native/installer/buildsupgrade.pas\n" > f6
    for (i = 1; i <= n_rs; i++) {
        sec = arr_rs[i]
        printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%d\n", \
            data[sec, "build"], data[sec, "arch"], data[sec, "os_family"], \
            data[sec, "servicing_branch"], data[sec, "status"], \
            data[sec, "ekb_source_build"], data[sec, "ekb_kb"], \
            data[sec, "ekb_prereq_kb"], data[sec, "ekb_min_revision"], \
            (data[sec, "build"] == "19042" ? 1 : 0) > f6
    }
    close(f6)

    # -------------------------------------------------------------------
    # Synchronize client/static/StaticUpdateIds-BuildUpgrades.txt
    # -------------------------------------------------------------------
    f_upg = tmp_dir "/static_upgrades.txt"
    rev44 = data["w100-x64-19044", "ekb_min_revision"]
    pre44 = data["w100-x64-19044", "ekb_prereq_kb"]
    kb44 = data["w100-x64-19044", "ekb_kb"]
    rev45 = data["w100-x64-19045", "ekb_min_revision"]
    pre45 = data["w100-x64-19045", "ekb_prereq_kb"]
    kb45 = data["w100-x64-19045", "ekb_kb"]
    rev200 = data["w100-x64-26200", "ekb_min_revision"]
    pre200 = data["w100-x64-26200", "ekb_prereq_kb"]
    kb200 = data["w100-x64-26200", "ekb_kb"]

    printf "19041,%s,%s,19044,%s\n", rev44, pre44, kb44 > f_upg
    printf "19042,%s,%s,19044,%s\n", rev44, pre44, kb44 > f_upg
    printf "19042,%s,%s,19045,%s\n", rev45, pre45, kb45 > f_upg
    printf "19043,%s,%s,19045,%s\n", rev45, pre45, kb45 > f_upg
    printf "19044,%s,%s,19045,%s\n", rev45, pre45, kb45 > f_upg
    printf "26100,%s,%s,26200,%s\n", rev200, pre200, kb200 > f_upg
    for (i = 1; i <= n_sec; i++) {
        s = sections[i]
        if (data[s, "os_family"] == "win11" && data[s, "arch"] == "x64") {
            b = data[s, "build"]
            if (b != "26200" && data[s, "ekb_kb"] != "" && data[s, "ekb_prereq_kb"] != "" && data[s, "ekb_min_revision"] != "") {
                printf "%s,%s,%s,%s,%s\n", data[s, "ekb_source_build"], data[s, "ekb_min_revision"], data[s, "ekb_prereq_kb"], b, data[s, "ekb_kb"] > f_upg
            }
        }
    }
    close(f_upg)

    # -------------------------------------------------------------------
    # Synchronize client/static/StaticUpdateIds-Checkpoints.txt
    # -------------------------------------------------------------------
    f_chk = tmp_dir "/static_checkpoints.txt"
    delete seen_chk
    for (i = 1; i <= n_sec; i++) {
        s = sections[i]
        kb = data[s, "checkpoint_kbs"]
        rev = data[s, "checkpoint_min_revision"]
        if (kb != "" && rev != "") {
            br = data[s, "servicing_branch"]
            k_chk = br "," kb
            if (!(k_chk in seen_chk)) {
                seen_chk[k_chk] = 1
                printf "%s,%s,%s,%s\n", br, kb, br, rev > f_chk
            }
        }
    }
    close(f_chk)
}
' "$builds_ini"

# -----------------------------------------------------------------------
# Helper: replace_between_markers
# Arguments: target_file start_marker end_marker block_file output_file
# -----------------------------------------------------------------------
replace_between_markers() {
    local target="$1"
    local sm="$2"
    local em="$3"
    local rep="$4"
    local out="$5"

    awk -v sm="$sm" -v em="$em" -v rep="$rep" '
    BEGIN {
        in_block = 0
        found_start = 0
        found_end = 0
    }
    {
        sub(/\r$/, "", $0)
        if (!in_block && index($0, sm) > 0) {
            found_start = 1
            in_block = 1
            print $0
            while ((getline rline < rep) > 0) {
                sub(/\r$/, "", rline)
                print rline
            }
            close(rep)
            next
        }
        if (in_block && index($0, em) > 0) {
            found_end = 1
            in_block = 0
            print $0
            next
        }
        if (!in_block) {
            print $0
        }
    }
    END {
        if (found_start != 1 || found_end != 1) {
            exit 2
        }
    }
    ' "$target" | sed 's/\r*$/\r/' > "$out"
}

drift_detected=false

process_site() {
    local rel_path="$1"
    local full_path="${repo_root}/${rel_path}"
    local sm="$2"
    local em="$3"
    local block="$4"
    local tmp_out
    tmp_out="${tmp_dir}/out_$(basename "$rel_path").tmp"

    if ! replace_between_markers "$full_path" "$sm" "$em" "$block" "$tmp_out"; then
        echo "ERROR: Marker processing failed for $rel_path" >&2
        exit 1
    fi

    if ! cmp -s "$full_path" "$tmp_out"; then
        drift_detected=true
        if [ "$check_only" = true ]; then
            echo "ERROR: File $rel_path is out of sync with static/builds.ini."
        fi
    fi

    if [ "$check_only" = false ]; then
        cp -f "$tmp_out" "$full_path"
    fi
}

# 1. cmd/DownloadUpdates.cmd
process_site "cmd/DownloadUpdates.cmd" "REM -- BEGIN GENERATED BUILDS WIN11 --" "REM -- END GENERATED BUILDS WIN11 --" "$tmp_dir/block2.txt"

# 2. sh/download-updates-tasks/60-main-updates.bash
process_site "sh/download-updates-tasks/60-main-updates.bash" "# -- BEGIN GENERATED BUILDS --" "# -- END GENERATED BUILDS --" "$tmp_dir/block3.txt"

# 3. sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
process_site "sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash" "# -- BEGIN GENERATED BUILDS --" "# -- END GENERATED BUILDS --" "$tmp_dir/block4.txt"

# Synchronize client/UpdateTable/builds.txt - whole-file emission (NOT a
# process_site marker rewrite; the three process_site calls above are the
# code sites, the data file rides along)
builds_txt="${repo_root}/client/UpdateTable/builds.txt"
tmp_builds_txt="$tmp_dir/builds_txt_crlf.txt"
sed 's/\r*$//' "$tmp_dir/builds_txt_data.txt" | sed 's/$/\r/' > "$tmp_builds_txt"

if [ ! -f "$builds_txt" ] || ! cmp -s "$builds_txt" "$tmp_builds_txt"; then
    drift_detected=true
    if [ "$check_only" = true ]; then
        echo "ERROR: File client/UpdateTable/builds.txt is out of sync with static/builds.ini."
    fi
fi

if [ "$check_only" = false ]; then
    mkdir -p "$(dirname "$builds_txt")"
    cp -f "$tmp_builds_txt" "$builds_txt"
fi

# Synchronize client/static/StaticUpdateIds-BuildUpgrades.txt
static_upgrades_file="${repo_root}/client/static/StaticUpdateIds-BuildUpgrades.txt"
tmp_upgrades_crlf="$tmp_dir/static_upgrades_crlf.txt"
sed 's/\r*$//' "$tmp_dir/static_upgrades.txt" | sed 's/$/\r/' > "$tmp_upgrades_crlf"

if ! cmp -s "$static_upgrades_file" "$tmp_upgrades_crlf"; then
    drift_detected=true
    if [ "$check_only" = true ]; then
        echo "ERROR: File client/static/StaticUpdateIds-BuildUpgrades.txt is out of sync with static/builds.ini."
    fi
fi

if [ "$check_only" = false ]; then
    cp -f "$tmp_upgrades_crlf" "$static_upgrades_file"
fi

# Synchronize client/static/StaticUpdateIds-Checkpoints.txt
static_checkpoints_file="${repo_root}/client/static/StaticUpdateIds-Checkpoints.txt"
tmp_checkpoints_crlf="$tmp_dir/static_checkpoints_crlf.txt"
sed 's/\r*$//' "$tmp_dir/static_checkpoints.txt" | sed 's/$/\r/' > "$tmp_checkpoints_crlf"

if [ ! -f "$static_checkpoints_file" ] || ! cmp -s "$static_checkpoints_file" "$tmp_checkpoints_crlf"; then
    drift_detected=true
    if [ "$check_only" = true ]; then
        echo "ERROR: File client/static/StaticUpdateIds-Checkpoints.txt is out of sync with static/builds.ini."
    fi
fi

if [ "$check_only" = false ]; then
    cp -f "$tmp_checkpoints_crlf" "$static_checkpoints_file"
fi

if [ "$check_only" = true ]; then
    if [ "$drift_detected" = true ]; then
        exit 1
    else
        echo "All 3 build sites are in sync with static/builds.ini."
        exit 0
    fi
else
    echo "Successfully updated 3 build sites from static/builds.ini."
    exit 0
fi
