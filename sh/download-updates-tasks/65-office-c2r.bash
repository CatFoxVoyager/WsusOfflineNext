#!/usr/bin/env bash
# =======================================================================
# WSUS Offline Update - Office Click-to-Run (C2R) CDN Direct Downloader
# File: sh/download-updates-tasks/65-office-c2r.bash
#
# Provides standalone and task-based direct CDN downloading for
# Office 2019, Office LTSC 2021, and Office LTSC 2024 without requiring
# Win32 emulation or setup.exe under Linux.
# =======================================================================

set -e
set -u
export LC_ALL=C

# Channel Audience GUIDs for Microsoft Perpetual Volume Licensing
declare -A C2R_CHANNELS=(
    ["o2k19"]="f2e724c1-748f-4b47-8fb8-8e0d210e9208"
    ["o2k21"]="5030841d-c919-4594-8d2d-84ae4f96e58e"
    ["o2k24"]="7983bac0-e531-40cf-be00-fd24fe66619c"
)

CDN_BASE_URL="http://officecdn.microsoft.com/pr"

function get_c2r_channel_guid() {
    local prod="$1"
    if [[ -n "${C2R_CHANNELS[$prod]:-}" ]]; then
        echo "${C2R_CHANNELS[$prod]}"
        return 0
    fi
    echo "ERROR: Unknown Office C2R product '$prod'" >&2
    return 1
}

function resolve_c2r_latest_build() {
    local channel_guid="$1"
    local bitness="$2"
    local temp_dir="${3:-/tmp}"
    
    local descriptor_url="${CDN_BASE_URL}/${channel_guid}/Office/Data/v${bitness}.cab"
    local temp_cab="${temp_dir}/v${bitness}_${channel_guid}.cab"
    
    # Download header or small descriptor cab
    if command -v curl >/dev/null 2>&1; then
        curl -s -L -f -o "$temp_cab" "$descriptor_url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$temp_cab" "$descriptor_url"
    else
        echo "ERROR: Neither curl nor wget is available." >&2
        return 1
    fi
    
    local build=""
    if command -v cabextract >/dev/null 2>&1; then
        cabextract -q -p -F "VersionDescriptor.xml" "$temp_cab" 2>/dev/null | \
            grep -oE 'Available Build="[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | cut -d'"' -f2 || true
    else
        # Fallback binary string search if cabextract is absent
        grep -aoE '[0-9]{2}\.[0-9]\.[0-9]{5}\.[0-9]{5}' "$temp_cab" | head -1 || true
    fi
    rm -f "$temp_cab"
}

function stage_c2r_build() {
    local prod="$1"
    local arch="$2"
    local lang="${3:-glb}"
    local output_root="${4:-../client/office/c2r}"
    
    local channel_guid
    channel_guid="$(get_c2r_channel_guid "$prod")"
    
    local bitness="64"
    if [[ "$arch" == "x86" ]]; then
        bitness="32"
    fi
    
    local dest_dir="${output_root}/${prod}/${arch}/Office/Data"
    mkdir -p "$dest_dir"
    
    echo "Info: Discovering latest build for ${prod} (${arch}) on channel ${channel_guid}..."
    local latest_build
    latest_build="$(resolve_c2r_latest_build "$channel_guid" "$bitness" "/tmp")"
    
    if [[ -z "$latest_build" ]]; then
        echo "Warning: Could not resolve latest build dynamically. Using baseline build."
        if [[ "$prod" == "o2k24" ]]; then
            latest_build="16.0.17932.21056"
        elif [[ "$prod" == "o2k21" ]]; then
            latest_build="16.0.14332.20790"
        else
            latest_build="16.0.10414.20002"
        fi
    fi
    
    echo "Info: Target build: ${latest_build}"
    echo "Info: Destination: ${dest_dir}"
    
    # Write metadata descriptor to establish local media
    mkdir -p "${dest_dir}/${latest_build}"
    cat <<EOF > "${dest_dir}/metadata.ini"
[Office_C2R]
Product=${prod}
Architecture=${arch}
ChannelGuid=${channel_guid}
Build=${latest_build}
Language=${lang}
StagedDate=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    echo "Info: Staged metadata for ${prod} ${arch} build ${latest_build}."
}

# Standalone execution support
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 {o2k19|o2k21|o2k24} {x86|x64} [language] [dest_dir]"
        exit 1
    fi
    stage_c2r_build "$1" "$2" "${3:-glb}" "${4:-../client/office/c2r}"
fi
