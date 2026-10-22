#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Build Site Propagation Tool (Linux Bash Engine)
# File: sh/generate-build-sites.bash
#
# Propagates build definitions from static/builds.ini into:
#   1. UpdateGenerator.au3
#   2. cmd/DownloadUpdates.cmd
#   3. sh/download-updates-tasks/60-main-updates.bash
#   4. sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
#   5. client/UpdateInstaller.au3
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
    # Site 1: UpdateGenerator.au3
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
    w11_v_str = ""
    w11_d_str = ""
    w11_def_str = ""
    w11_space_str = ""
    for (i = 1; i <= n_w11; i++) {
        if (i > 1) {
            w11_v_str = w11_v_str ","
            w11_d_str = w11_d_str ","
            w11_def_str = w11_def_str ","
            w11_space_str = w11_space_str " "
        }
        w11_v_str = w11_v_str w11_builds[i]
        w11_d_str = w11_d_str w11_names[i]
        w11_def_str = w11_def_str w11_defs[i]
        w11_space_str = w11_space_str w11_builds[i]
    }

    f1 = tmp_dir "/block1.txt"
    printf "Dim Const $win11_vmax                   = %d\n", n_w11 > f1
    printf "Dim Const $win11_versions               = \"%s\"\n", w11_v_str > f1
    printf "Dim Const $win11_displayversions        = \"%s\"\n", w11_d_str > f1
    printf "Dim Const $win11_defaults               = \"%s\"\n", w11_def_str > f1
    close(f1)

    # -------------------------------------------------------------------
    # Site 2: cmd/DownloadUpdates.cmd
    # -------------------------------------------------------------------
    f2 = tmp_dir "/block2.txt"
    printf "  set TMP_BUILDS_ALL_WIN11=%s\n", w11_space_str > f2
    close(f2)

    # -------------------------------------------------------------------
    # Site 3: sh/download-updates-tasks/60-main-updates.bash
    # -------------------------------------------------------------------
    f3 = tmp_dir "/block3.txt"
    x86_list = "10240 14393 17763 19041"
    x64_list = "10240 14393 17763 19041 20348 " w11_space_str
    printf "w100_x86_all_versions=( %s )\n", x86_list > f3
    printf "w100_x64_all_versions=( %s )\n", x64_list > f3
    close(f3)

    # -------------------------------------------------------------------
    # Site 4: sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
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
    # Site 5: client/UpdateInstaller.au3
    # -------------------------------------------------------------------
    f5 = tmp_dir "/block5.txt"
    printf "; Format: [build, arch, os_family, servicing_branch, status, ekb_source_build, ekb_kb, ekb_prereq_kb, ekb_min_revision, is_enforced]\n" > f5
    printf "Global Const $aBuildRegistry[12][10] = [ _\n" > f5
    reg_secs = "w100-x86-19041 w100-x64-19041 w100-x86-19042 w100-x64-19042 w100-x86-19044 w100-x64-19044 w100-x86-19045 w100-x64-19045 w100-x64-26100 w100-x64-26200 w100-x64-26300 w100-x64-28000"
    n_rs = split(reg_secs, arr_rs, " ")
    for (i = 1; i <= n_rs; i++) {
        sec = arr_rs[i]
        bld = data[sec, "build"]
        arch = data[sec, "arch"]
        os_f = data[sec, "os_family"]
        br = data[sec, "servicing_branch"]
        st = data[sec, "status"]
        src = data[sec, "ekb_source_build"]
        kb = data[sec, "ekb_kb"]
        pre = data[sec, "ekb_prereq_kb"]
        rev = data[sec, "ekb_min_revision"]
        enf = (bld == "19042" ? 1 : 0)
        cont = (i < n_rs ? ", _" : " _")

        c_st = sprintf("\"%s\",", st)
        c_src = sprintf("\"%s\",", src)
        c_kb = sprintf("\"%s\",", kb)
        c_pre = sprintf("\"%s\",", pre)
        c_rev = sprintf("\"%s\",", rev)

        if (st == "ineligible") {
            p_st = sprintf("%-14s", c_st)
            p_src = sprintf("%-4s", c_src)
        } else {
            p_st = sprintf("%-10s", c_st)
            p_src = sprintf("%-8s", c_src)
        }
        p_kb = sprintf("%-13s", c_kb)
        p_pre = sprintf("%-13s", c_pre)
        p_rev = sprintf("%-8s", c_rev)

        printf "  [\"%s\", \"%s\", \"%s\", \"%s\", %s %s %s %s %s %d]%s\n", bld, arch, os_f, br, p_st, p_src, p_kb, p_pre, p_rev, enf, cont > f5
    }
    printf "]\n" > f5
    close(f5)

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
    local tmp_out="$tmp_dir/out_$(basename "$rel_path").tmp"

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

# 1. UpdateGenerator.au3
process_site "UpdateGenerator.au3" "; -- BEGIN GENERATED BUILDS WIN11 --" "; -- END GENERATED BUILDS WIN11 --" "$tmp_dir/block1.txt"

# 2. cmd/DownloadUpdates.cmd
process_site "cmd/DownloadUpdates.cmd" "REM -- BEGIN GENERATED BUILDS WIN11 --" "REM -- END GENERATED BUILDS WIN11 --" "$tmp_dir/block2.txt"

# 3. sh/download-updates-tasks/60-main-updates.bash
process_site "sh/download-updates-tasks/60-main-updates.bash" "# -- BEGIN GENERATED BUILDS --" "# -- END GENERATED BUILDS --" "$tmp_dir/block3.txt"

# 4. sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash
process_site "sh/update-generator-tasks/10-show-selection-dialogs-with-dialog.bash" "# -- BEGIN GENERATED BUILDS --" "# -- END GENERATED BUILDS --" "$tmp_dir/block4.txt"

# 5. client/UpdateInstaller.au3
process_site "client/UpdateInstaller.au3" "; -- BEGIN GENERATED BUILDS TABLE --" "; -- END GENERATED BUILDS TABLE --" "$tmp_dir/block5.txt"

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
        echo "All 5 build sites are in sync with static/builds.ini."
        exit 0
    fi
else
    echo "Successfully updated 5 build sites from static/builds.ini."
    exit 0
fi
