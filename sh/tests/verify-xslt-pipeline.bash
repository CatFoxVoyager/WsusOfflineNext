#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - XSLT Pipeline Validation Runner (Linux / Bash)
# File: sh/tests/verify-xslt-pipeline.bash
#
# Modes:
#   verify-xslt-pipeline.bash          Offline synthetic fixture regression suite
#   verify-xslt-pipeline.bash --live   Live Microsoft catalog (wsusscn2.cab) validation
# =======================================================================

set -e
set -u
export LC_ALL=C

if [ -d "/usr/bin" ] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
    export PATH="/usr/bin:$PATH"
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"

mode="fixture"
for arg in "$@"; do
    case "$arg" in
        --live|-live)
            mode="live"
            ;;
    esac
done

# Setup diff command with CRLF tolerance if available
diff_cmd="diff -u"
if diff --strip-trailing-cr /dev/null /dev/null >/dev/null 2>&1; then
    diff_cmd="diff -u --strip-trailing-cr"
fi

to_windows_path() {
    local p="$1"
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$p"
    elif command -v wslpath >/dev/null 2>&1; then
        wslpath -w "$p"
    elif [[ "$p" =~ ^/mnt/([a-zA-Z])/(.*) ]]; then
        local drive="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]//\//\\}"
        echo "${drive^^}:\\${rest}"
    elif [[ "$p" =~ ^/([a-zA-Z])/(.*) ]]; then
        local drive="${BASH_REMATCH[1]}"
        local rest="${BASH_REMATCH[2]//\//\\}"
        echo "${drive^^}:\\${rest}"
    else
        echo "$p"
    fi
}

run_xslt() {
    local xml_path="$1"
    local xsl_path="$2"
    local out_path="$3"

    if command -v xmlstarlet >/dev/null 2>&1; then
        xmlstarlet transform "$xsl_path" "$xml_path" > "$out_path"
    elif command -v xsltproc >/dev/null 2>&1; then
        xsltproc "$xsl_path" "$xml_path" > "$out_path"
    elif command -v cscript.exe >/dev/null 2>&1 || command -v cscript >/dev/null 2>&1; then
        local cscript_bin
        cscript_bin="$(command -v cscript.exe 2>/dev/null || command -v cscript 2>/dev/null)"
        local w_vbs w_xml w_xsl w_out
        w_vbs="$(to_windows_path "$repo_root/cmd/XSLT.vbs")"
        w_xml="$(to_windows_path "$xml_path")"
        w_xsl="$(to_windows_path "$xsl_path")"
        w_out="$(to_windows_path "$out_path")"
        "$cscript_bin" //Nologo //B //E:vbs "$w_vbs" "$w_xml" "$w_xsl" "$w_out"
    else
        echo "ERROR: No XSLT processor found (xmlstarlet, xsltproc, or cscript)." >&2
        return 1
    fi
}

tmp_dir="$(mktemp -d 2>/dev/null || mktemp -d -t 'wou_xslt_test')"
trap 'rm -rf "$tmp_dir"' EXIT

# =======================================================================
# Live Mode Handler
# =======================================================================
if [[ "$mode" == "live" ]]; then
    echo "======================================================================="
    echo "WSUS Offline Update - Live Catalog Verification (--live) (Linux / Bash)"
    echo "======================================================================="

    wsus_dir="${repo_root}/client/wsus"
    wsus_cab="${wsus_dir}/wsusscn2.cab"
    mkdir -p "$wsus_dir"

    if [[ ! -f "$wsus_cab" ]]; then
        echo "wsusscn2.cab not found in cache ($wsus_cab)."
        url_file="${repo_root}/static/StaticDownloadLinks-wsus.txt"
        download_url="http://download.windowsupdate.com/microsoftupdate/v6/wsusscan/wsusscn2.cab"
        if [[ -f "$url_file" ]]; then
            line="$(head -n 1 "$url_file" | tr -d '\r\n')"
            if [[ -n "$line" ]]; then
                download_url="$line"
            fi
        fi
        echo "Downloading wsusscn2.cab from $download_url ..."
        if command -v curl >/dev/null 2>&1; then
            curl -f -L -C - "$download_url" -o "$wsus_cab"
        elif command -v wget >/dev/null 2>&1; then
            wget -c "$download_url" -O "$wsus_cab"
        else
            echo "ERROR: Neither curl nor wget found for catalog download." >&2
            exit 1
        fi
    else
        echo "Using cached catalog: $wsus_cab"
    fi

    if [[ ! -s "$wsus_cab" ]]; then
        echo "ERROR: Catalog file $wsus_cab is empty or missing." >&2
        exit 1
    fi

    echo "Extracting package.cab from wsusscn2.cab..."
    if command -v cabextract >/dev/null 2>&1; then
        cabextract -q -d "$tmp_dir" -F "package.cab" "$wsus_cab"
        echo "Extracting package.xml from package.cab..."
        cabextract -q -d "$tmp_dir" "$tmp_dir/package.cab"
        rm -f "$tmp_dir/package.cab"
    elif [ -f "/c/Windows/System32/expand.exe" ] || [ -f "${WINDIR:-C:\\Windows}/System32/expand.exe" ]; then
        expand_bin="/c/Windows/System32/expand.exe"
        if [ ! -f "$expand_bin" ] && [ -f "${WINDIR:-C:\\Windows}/System32/expand.exe" ]; then
            expand_bin="${WINDIR}/System32/expand.exe"
        fi
        w_cab="$(to_windows_path "$wsus_cab")"
        w_tmp="$(to_windows_path "$tmp_dir")"
        "$expand_bin" "$w_cab" -F:package.cab "$w_tmp" >/dev/null
        echo "Extracting package.xml from package.cab..."
        "$expand_bin" "$w_tmp/package.cab" "$w_tmp/package.xml" >/dev/null
        rm -f "$tmp_dir/package.cab"
    else
        echo "ERROR: Neither cabextract nor Windows expand.exe is available for cabinet extraction." >&2
        exit 1
    fi

    live_xml="${tmp_dir}/package.xml"
    if [[ ! -s "$live_xml" ]]; then
        echo "ERROR: Extracted package.xml is missing or empty." >&2
        exit 1
    fi
    echo "Extracted package.xml size: $(wc -c < "$live_xml") bytes"

    echo
    echo "Running XSLT transforms on live package.xml..."

    echo "[1/3] Transforming xslt/extract-revision-and-update-ids-w100.xsl ..."
    run_xslt "$live_xml" "${repo_root}/xslt/extract-revision-and-update-ids-w100.xsl" "${tmp_dir}/live_w100.txt"
    if [[ ! -s "${tmp_dir}/live_w100.txt" ]]; then
        echo "ERROR: Output live_w100.txt is empty." >&2
        exit 1
    fi

    echo "[2/3] Transforming xslt/extract-revision-and-update-ids-ofc.xsl ..."
    run_xslt "$live_xml" "${repo_root}/xslt/extract-revision-and-update-ids-ofc.xsl" "${tmp_dir}/live_ofc.txt"
    if [[ ! -s "${tmp_dir}/live_ofc.txt" ]]; then
        echo "ERROR: Output live_ofc.txt is empty." >&2
        exit 1
    fi

    echo "[3/3] Transforming xslt/extract-update-cab-exe-ids-and-locations.xsl ..."
    run_xslt "$live_xml" "${repo_root}/xslt/extract-update-cab-exe-ids-and-locations.xsl" "${tmp_dir}/live_locs.txt"
    if [[ ! -s "${tmp_dir}/live_locs.txt" ]]; then
        echo "ERROR: Output live_locs.txt is empty." >&2
        exit 1
    fi

    echo
    echo "Validating output schemas and patterns..."

    w100_count=$(grep -E -c '^#[0-9]+#,[0-9a-fA-F-]+' "${tmp_dir}/live_w100.txt" || true)
    if [[ "$w100_count" -le 0 ]]; then
        echo "ERROR: Zero valid Windows update entries found in live catalog output." >&2
        exit 1
    fi
    echo "  PASS: Found $w100_count valid Windows update entries."

    ofc_count=$(grep -E -c '^#[0-9]+#,[0-9a-fA-F-]+' "${tmp_dir}/live_ofc.txt" || true)
    if [[ "$ofc_count" -le 0 ]]; then
        echo "ERROR: Zero valid Office update entries found in live catalog output." >&2
        exit 1
    fi
    echo "  PASS: Found $ofc_count valid Office update entries."

    locs_count=$(grep -F -c ',http' "${tmp_dir}/live_locs.txt" || true)
    if [[ "$locs_count" -le 0 ]]; then
        echo "ERROR: Zero valid file location URLs found in live catalog output." >&2
        exit 1
    fi
    echo "  PASS: Found $locs_count valid file location URLs."

    echo "Validating presence of Windows 11 Product ID entries..."
    win11_xsl="${repo_root}/tests/fixtures/xslt/extract-win11-only.xsl"
    if [[ ! -f "$win11_xsl" ]]; then
        echo "ERROR: $win11_xsl not found." >&2
        exit 1
    fi

    run_xslt "$live_xml" "$win11_xsl" "${tmp_dir}/live_win11_only.txt"
    win11_count=$(grep -E -c '^#[0-9]+#,[0-9a-fA-F-]+' "${tmp_dir}/live_win11_only.txt" || true)
    if [[ "$win11_count" -le 0 ]]; then
        echo "ERROR: Zero Windows 11 Product ID entries found in live catalog!" >&2
        exit 1
    fi
    echo "  PASS: Verified presence of $win11_count Windows 11 Product ID entries."

    echo
    echo "SUCCESS: Live catalog validation completed successfully."
    exit 0
fi

# =======================================================================
# Fixture Mode Handler
# =======================================================================
fixtures_dir="${repo_root}/tests/fixtures/xslt"
sample_xml="${fixtures_dir}/sample-package.xml"

if [[ ! -f "$sample_xml" ]]; then
    echo "ERROR: Synthetic fixture XML not found at $sample_xml" >&2
    exit 1
fi

echo "======================================================================="
echo "WSUS Offline Update - XSLT Fixture Regression Suite (Linux / Bash)"
echo "======================================================================="
echo "Testing 6 core transforms against $sample_xml..."
echo

test_transform() {
    local xsl_name="$1"
    local expected_name="$2"
    local step="$3"

    local xsl_file="${repo_root}/xslt/${xsl_name}"
    local expected_file="${fixtures_dir}/${expected_name}"
    local base="${xsl_name%.*}"
    local raw_out="${tmp_dir}/raw_${base}.txt"
    local sorted_out="${tmp_dir}/sorted_${base}.txt"

    echo "[$step] Testing ${xsl_name} ..."
    if [[ ! -f "$xsl_file" ]]; then
        echo "ERROR: Stylesheet $xsl_file does not exist." >&2
        return 1
    fi
    if [[ ! -f "$expected_file" ]]; then
        echo "ERROR: Expected fixture $expected_file does not exist." >&2
        return 1
    fi

    if ! run_xslt "$sample_xml" "$xsl_file" "$raw_out"; then
        echo "ERROR: XSLT execution failed for $xsl_name" >&2
        return 1
    fi

    if [[ ! -s "$raw_out" ]]; then
        echo "ERROR: Raw transform output is empty for $xsl_name" >&2
        return 1
    fi

    sort -u "$raw_out" > "$sorted_out"

    if ! $diff_cmd "$sorted_out" "$expected_file" > "${tmp_dir}/diff_${base}.patch"; then
        echo "ERROR: Transformed output for $xsl_name did NOT match expected fixture $expected_name!" >&2
        echo "Diff details:" >&2
        cat "${tmp_dir}/diff_${base}.patch" >&2
        return 1
    fi

    echo "  PASS: Transformed output matched $expected_name byte-for-byte."
    return 0
}

test_transform "extract-revision-and-update-ids-w100.xsl" "expected-revision-and-update-ids-w100.txt" "1/6"
test_transform "extract-revision-and-update-ids-o2k16.xsl" "expected-revision-and-update-ids-o2k16.txt" "2/6"
test_transform "extract-update-revision-and-file-ids.xsl" "expected-update-revision-and-file-ids.txt" "3/6"
test_transform "extract-update-cab-exe-ids-and-locations.xsl" "expected-update-cab-exe-ids-and-locations.txt" "4/6"
test_transform "extract-existing-bundle-revision-ids.xsl" "expected-existing-bundle-revision-ids.txt" "5/6"
test_transform "extract-superseding-and-superseded-revision-ids.xsl" "expected-superseding-and-superseded-revision-ids.txt" "6/6"

echo
echo "SUCCESS: All 6 XSLT fixture transforms matched expected output."
exit 0
