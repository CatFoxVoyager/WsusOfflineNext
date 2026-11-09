#!/usr/bin/env python3
"""Binary-hygiene inspection battery for the shipped executables (INST-06).

Inspects the shipped exe surface with pefile - the two native client-slot
binaries (client/UpdateInstallerLegacy.exe i386,
client/UpdateInstallerLegacy64.exe x64) and the repo-root self-update
updater (WsusOfflineUpdater.exe) - and asserts, per binary:

1. VERSIONINFO completeness: every StringFileInfo field below is present and
   non-empty. Family "native" additionally pins the numeric FileVersion and
   ProductVersion cores to the WSUSOFFLINE_VERSION core from
   cmd/DownloadUpdates.cmd (the native .lpi VersionInfo is a bump-matrix
   site - the pair tracks the app release). Family "dotnet"
   asserts the numeric FileVersion equals the StringTable FileVersion
   components and the StringTable ProductVersion carries the locked full
   form M.m.p+YYYY.MM (the bump-matrix token, no SourceRevisionId suffix).
2. Manifest (RT_MANIFEST resource) completeness: the per-exe
   requestedExecutionLevel (native pair: requireAdministrator; updater:
   asInvoker - it NEVER requires admin), all five supportedOS GUIDs
   (Vista/7/8/8.1/10), and longPathAware enabled. Family "native"
   additionally requires the comctl v6 dependency literal, dpiAware
   True/PM_V2 and the PerMonitorV2 awareness list (Lazarus specifics).
3. Never-UPX: no section named UPX0/UPX1/UPX2 and no UPX stub signature
   anywhere in the image (permanent never-UPX rule).
4. Family "native" only: icon entries DIB-encoded (LCL startup crash guard).

Exit 0 printing HYGIENE-PASS only when every assertion passes on every
binary; exit 1 naming the first failing assertion otherwise.

Run: python -I ci/tests/test-native-installer-hygiene.py
(The -I flag is authoritative: the pefile dependency is located from the
Phase 23 analysis venv via an explicit sys.path fallback below, never from
ambient environment paths. The updater exe is a publish output - run
CompileModernApps.cmd lane 4 or dotnet publish the updater to the repo root
first.)
"""
import os
import re
import struct
import sys

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(repo_root)


def expected_core_version():
    """Core M.m.p the native pair must carry, read from the single source of
    truth (cmd/DownloadUpdates.cmd WSUSOFFLINE_VERSION, the bump matrix's
    own anchor). The native .lpi VersionInfo joined the bump matrix in the
    6.x line - the numeric version tracks the app release; the historical
    frozen (5, 2, 0) pin predated that absorption and could never pass on
    any 6.x build."""
    with open(os.path.join("cmd", "DownloadUpdates.cmd"), "r", encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    m = re.search(r"WSUSOFFLINE_VERSION=(\d+)\.(\d+)\.(\d+)", text)
    if not m:
        raise SystemExit("[FAIL] cannot derive the expected core version from cmd/DownloadUpdates.cmd")
    return tuple(int(part) for part in m.groups())


EXPECTED_CORE = expected_core_version()

# Environment adaptation (recorded in 26-03 SUMMARY): `python -I` ignores
# PYTHONPATH but keeps its own global site-packages. The owner-approved
# pefile lives in the Phase 23 analysis venv; resolve it by explicit path,
# scoped to the import only.
try:
    import pefile
except ModuleNotFoundError:
    _venv_site = os.path.join(repo_root, ".planning", "tmp", "23-tools", "venv", "Lib", "site-packages")
    if not os.path.isdir(_venv_site):
        print(f"[FAIL] pefile unavailable and analysis venv missing at {_venv_site}")
        sys.exit(1)
    sys.path.insert(0, _venv_site)
    import pefile

BINARIES = [
    # (path, expected requestedExecutionLevel, family)
    # family "native": the Lazarus GUI pair - full native assertion set
    # (comctl v6, dpiAware True/PM_V2 + PerMonitorV2, source-of-truth numeric
    # pins, DIB-decodable MAINICON).
    # family "dotnet": the .NET single-file updater - the generic set
    # (resource directory, StringFileInfo, VS_FIXEDFILEINFO, manifest with
    # per-exe execution level + longPathAware, never-UPX).
    ("client/UpdateInstallerLegacy.exe", "requireAdministrator", "native"),
    ("client/UpdateInstallerLegacy64.exe", "requireAdministrator", "native"),
    ("WsusOfflineUpdater.exe", "asInvoker", "dotnet"),
]

REQUIRED_STRINGFILEINFO_FIELDS = [
    "CompanyName",
    "FileDescription",
    "InternalName",
    "LegalCopyright",
    "OriginalFilename",
    "ProductName",
    "ProductVersion",
]

SUPPORTED_OS_GUIDS = [
    "e2011457-1546-43c5-a5fe-008deee3d3f0",  # Windows Vista
    "35138b9a-5d96-4fbd-8e2d-a2440225f93a",  # Windows 7
    "4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38",  # Windows 8
    "1f676c76-80e1-4239-95bb-83d0f6d0da78",  # Windows 8.1
    "8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a",  # Windows 10
]

RT_MANIFEST_ID = 24  # Windows resource type RT_MANIFEST (RT_VERSION is 16)


def fail(binary, message):
    print(f"[FAIL] {binary}: {message}")
    sys.exit(1)


def get_manifest_xml(pe, binary):
    try:
        rtree = pe.DIRECTORY_ENTRY_RESOURCE
    except AttributeError:
        fail(binary, "no resource directory - the manifest/VERSIONINFO resources are missing")
    for rtype in rtree.entries:
        if rtype.struct.Id == RT_MANIFEST_ID:
            rname = rtype.directory.entries[0]
            rlang = rname.directory.entries[0]
            data = rlang.data.struct
            offset = data.OffsetToData
            size = data.Size
            return pe.get_data(offset, size).decode("utf-8", errors="replace")
    fail(binary, "RT_MANIFEST resource not found")


def get_string_table(pe, binary):
    for blocklist in getattr(pe, "FileInfo", []):
        for entry in blocklist:
            if getattr(entry, "Key", None) == b"StringFileInfo":
                for table in entry.StringTable:
                    return {k.decode() if isinstance(k, bytes) else k:
                            v.decode() if isinstance(v, bytes) else v
                            for k, v in table.entries.items()}
    fail(binary, "no StringFileInfo table in VERSIONINFO")


def fixed_version(pe, binary):
    try:
        vs = pe.VS_FIXEDFILEINFO[0]
    except (AttributeError, IndexError):
        fail(binary, "no VS_FIXEDFILEINFO (numeric version block missing)")
    return (
        vs.FileVersionMS >> 16, vs.FileVersionMS & 0xFFFF,
        vs.FileVersionLS >> 16, vs.FileVersionLS & 0xFFFF,
    ), (
        vs.ProductVersionMS >> 16, vs.ProductVersionMS & 0xFFFF,
        vs.ProductVersionLS >> 16, vs.ProductVersionLS & 0xFFFF,
    )


def check_binary(binary, expected_level, family):
    print(f"== Inspecting {binary} (family {family}, level {expected_level})")
    if not os.path.isfile(binary):
        fail(binary, "binary missing - run the native compile lane first")
    with open(binary, "rb") as f:
        raw = f.read()
    pe = pefile.PE(data=raw)

    # --- 1. VERSIONINFO completeness ---
    table = get_string_table(pe, binary)
    for field in REQUIRED_STRINGFILEINFO_FIELDS:
        value = table.get(field, "")
        if not value.strip():
            fail(binary, f"VERSIONINFO field {field} is empty (fields present: {sorted(table)})")
    print(f"   VERSIONINFO: {len(REQUIRED_STRINGFILEINFO_FIELDS)} StringFileInfo fields non-empty")
    fv, pv = fixed_version(pe, binary)
    if family == "native":
        # The native pair tracks the app version: the .lpi VersionInfo is a
        # bump-matrix site, so the numeric core must equal the WSUSOFFLINE_VERSION
        # core (single source of truth) - not a frozen constant.
        if fv[:3] != EXPECTED_CORE:
            fail(binary, f"numeric FileVersion {fv} != source-of-truth core {EXPECTED_CORE}")
        # The StringTable ProductVersion carries the full bump-matrix form
        # "M.m.p+YYYY.MM"; the IDE projects that string into the numeric
        # ProductVersion's build slot, so the MAJOR.MINOR.REVISION components
        # stay the gate.
        if pv[:3] != EXPECTED_CORE:
            fail(binary, f"numeric ProductVersion {pv} does not start with {EXPECTED_CORE}")
        print(f"   numeric FileVersion={fv} ProductVersion={pv} (core {EXPECTED_CORE} from cmd/DownloadUpdates.cmd)")
    else:
        # dotnet: the numeric FileVersion must equal the StringTable
        # FileVersion components (the bump-matrix <FileVersion> token); the
        # StringTable ProductVersion must carry the locked full form
        # M.m.p+YYYY.MM with no SourceRevisionId suffix.
        string_fv = tuple(int(part) for part in table.get("FileVersion", "x").split("."))
        if fv != string_fv:
            fail(binary, f"numeric FileVersion {fv} != StringTable FileVersion {string_fv}")
        if not re.fullmatch(r"\d+\.\d+\.\d+\+\d{4}\.\d{2}", table.get("ProductVersion", "")):
            fail(binary, f"StringTable ProductVersion '{table.get('ProductVersion', '')}' "
                         "does not carry the locked full form M.m.p+YYYY.MM")
        print(f"   numeric FileVersion={fv} matches StringTable; "
              f"ProductVersion='{table.get('ProductVersion', '')}' full form")

    # --- 2. Manifest completeness ---
    manifest = get_manifest_xml(pe, binary)
    if family == "native":
        if 'name="Microsoft.Windows.Common-Controls"' not in manifest \
                or 'publicKeyToken="6595b64144ccf1df"' not in manifest:
            fail(binary, "comctl v6 dependency literal missing from the manifest")
    for guid in SUPPORTED_OS_GUIDS:
        if guid not in manifest:
            fail(binary, f"supportedOS GUID missing from the manifest: {guid}")
    if family == "native":
        if "<dpiAware>True/PM_V2</dpiAware>" not in manifest:
            fail(binary, "dpiAware True/PM_V2 element missing from the manifest")
        if "<dpiAwareness>PerMonitorV2, PerMonitor</dpiAwareness>" not in manifest:
            fail(binary, "PerMonitorV2 dpiAwareness element missing from the manifest")
    if f'level="{expected_level}"' not in manifest:
        fail(binary, f'requestedExecutionLevel level="{expected_level}" missing from the manifest')
    # longPathAware: the canonical Microsoft form carries the SMI namespace
    # on the setting element itself (<longPathAware xmlns="...">true</...>),
    # so the check tolerates attributes on the opener but still requires
    # the enabled value.
    if not re.search(r"<longPathAware[^>]*>\s*true\s*</longPathAware>", manifest):
        fail(binary, "longPathAware element missing or not enabled in the manifest")
    print(f"   manifest: 5 supportedOS GUIDs + {expected_level} + longPathAware"
          + (" + comctl v6 + True/PM_V2 + PerMonitorV2" if family == "native" else "")
          + f" ({len(manifest)} chars)")

    # --- 3. Never-UPX ---
    bad_sections = [s.Name.decode("utf-8", errors="replace").rstrip("\x00")
                    for s in pe.sections if s.Name.startswith(b"UPX")]
    if bad_sections:
        fail(binary, f"packed sections found: {bad_sections}")
    stub_at = raw.find(b"UPX!")
    if stub_at != -1:
        fail(binary, f"UPX stub signature found at offset {stub_at}")
    print(f"   no-UPX: {len(pe.sections)} sections, none packed, no stub signature")

    # --- 4. Icon entries DIB-encoded (plan 26-04 launch defect) ---
    # Native family only: the LCL startup crash guard. A PNG-compressed ICO
    # entry passes every byte check above yet KILLS the
    # process at startup: LCL's TApplication.Initialize decodes MAINICON with
    # the pure-Pascal TLazReaderIconDib (intfgraphics.pas), which supports
    # only DIB entries - measured on the 26-04 Win7 validation run as
    # FPImageException "Bitmap with unknown compression" -> unhandled
    # exception -> rc 217 on every OS. Assert every RT_ICON entry in the
    # binary is a DIB whose biCompression the reader accepts, and that a
    # MAINICON group exists. The .NET SDK icon embedding is a different
    # mechanism and is not covered by this assertion.
    if family != "native":
        print(f"[PASS] {binary}")
        return len(REQUIRED_STRINGFILEINFO_FIELDS), len(manifest), len(pe.sections)
    try:
        icon_entries = {}
        group_names = []
        for rt in pe.DIRECTORY_ENTRY_RESOURCE.entries:
            if rt.struct.Id == 3:  # RT_ICON
                for eid in rt.directory.entries:
                    lang = eid.directory.entries[0]
                    icon_entries[eid.struct.Id] = pe.get_data(
                        lang.data.struct.OffsetToData, lang.data.struct.Size)
            elif rt.struct.Id == 14:  # RT_GROUP_ICON
                group_names.extend(str(e.name) if e.name else e.struct.Id
                                   for e in rt.directory.entries)
    except AttributeError:
        fail(binary, "no resource directory (icon not embedded)")
    if "MAINICON" not in group_names:
        fail(binary, f"MAINICON group missing (groups: {group_names})")
    if not icon_entries:
        fail(binary, "no RT_ICON entries behind MAINICON")
    for icon_id, blob in sorted(icon_entries.items()):
        if blob[:8] == b"\x89PNG\r\n\x1a\n":
            fail(binary, f"RT_ICON #{icon_id} is PNG-compressed "
                         "(LCL icon reader cannot decode it - startup crash)")
        if len(blob) < 40:
            fail(binary, f"RT_ICON #{icon_id} smaller than a BITMAPINFOHEADER")
        bi_compression, = struct.unpack_from("<I", blob, 30)
        if bi_compression not in (0, 3):  # BI_RGB or BI_BITFIELDS
            fail(binary, f"RT_ICON #{icon_id} DIB compression {bi_compression} "
                         "unsupported by the LCL icon reader")
    print(f"   icon: MAINICON group + {len(icon_entries)} RT_ICON entries, "
          "all DIB-encoded (LCL-decodable)")

    print(f"[PASS] {binary}")
    return len(REQUIRED_STRINGFILEINFO_FIELDS), len(manifest), len(pe.sections)


def main():
    print("=" * 71)
    print("WSUS Offline Next - Native Installer Binary-Hygiene Battery")
    print("=" * 71)
    total_fields = total_manifest = total_sections = 0
    for binary, expected_level, family in BINARIES:
        fields, manifest_len, sections = check_binary(binary, expected_level, family)
        total_fields += fields
        total_manifest += manifest_len
        total_sections += sections
    print("-" * 71)
    print(f"binaries inspected: {len(BINARIES)}; string fields: {total_fields}; "
          f"manifest bytes: {total_manifest}; sections: {total_sections}")
    print("HYGIENE-PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
