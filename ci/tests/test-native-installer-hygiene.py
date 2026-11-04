#!/usr/bin/env python3
"""Binary-hygiene inspection battery for the native installer GUI (INST-06).

Inspects BOTH shipped client-slot binaries (client/UpdateInstallerLegacy.exe
i386, client/UpdateInstallerLegacy64.exe x64) with pefile and asserts, per
binary:

1. VERSIONINFO completeness: every StringFileInfo field below is present and
   non-empty; the numeric FileVersion and ProductVersion equal 5.2.0.
2. Manifest (RT_MANIFEST resource) completeness: the comctl v6 dependency
   literal, all five supportedOS GUIDs (Vista/7/8/8.1/10), a dpiAware
   True/PM_V2 element with the PerMonitorV2 awareness list, the
   requireAdministrator requestedExecutionLevel, and longPathAware enabled.
3. Never-UPX: no section named UPX0/UPX1/UPX2 and no UPX stub signature
   anywhere in the image (permanent never-UPX rule).

Exit 0 printing HYGIENE-PASS only when every assertion passes on both
binaries; exit 1 naming the first failing assertion otherwise.

Run: python -I ci/tests/test-native-installer-hygiene.py
(The -I flag is authoritative: the pefile dependency is located from the
Phase 23 analysis venv via an explicit sys.path fallback below, never from
ambient environment paths.)
"""
import os
import sys

repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(repo_root)

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
    "client/UpdateInstallerLegacy.exe",
    "client/UpdateInstallerLegacy64.exe",
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


def check_binary(binary):
    print(f"== Inspecting {binary}")
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
    if fv[:3] != (5, 2, 0):
        fail(binary, f"numeric FileVersion {fv} != (5, 2, 0, build)")
    # The StringTable ProductVersion carries the LOCKED full form
    # "5.2.0+YYYY.MM" (the plan-mandated bump-matrix site); the IDE projects
    # that string into the numeric ProductVersion's build slot, so the build
    # component there is a function of the mandated string - the MAJOR.MINOR.
    # REVISION components stay the gate.
    if pv[:3] != (5, 2, 0):
        fail(binary, f"numeric ProductVersion {pv} does not start with (5, 2, 0)")
    print(f"   numeric FileVersion={fv} ProductVersion={pv} (build slot from the full-form string)")

    # --- 2. Manifest completeness ---
    manifest = get_manifest_xml(pe, binary)
    if 'name="Microsoft.Windows.Common-Controls"' not in manifest \
            or 'publicKeyToken="6595b64144ccf1df"' not in manifest:
        fail(binary, "comctl v6 dependency literal missing from the manifest")
    for guid in SUPPORTED_OS_GUIDS:
        if guid not in manifest:
            fail(binary, f"supportedOS GUID missing from the manifest: {guid}")
    if "<dpiAware>True/PM_V2</dpiAware>" not in manifest:
        fail(binary, "dpiAware True/PM_V2 element missing from the manifest")
    if "<dpiAwareness>PerMonitorV2, PerMonitor</dpiAwareness>" not in manifest:
        fail(binary, "PerMonitorV2 dpiAwareness element missing from the manifest")
    if 'level="requireAdministrator"' not in manifest:
        fail(binary, 'requestedExecutionLevel level="requireAdministrator" missing from the manifest')
    if "<longPathAware>true</longPathAware>" not in manifest:
        fail(binary, "longPathAware element missing from the manifest")
    print(f"   manifest: comctl v6 + 5 supportedOS GUIDs + True/PM_V2 + PerMonitorV2 "
          f"+ requireAdministrator + longPathAware ({len(manifest)} chars)")

    # --- 3. Never-UPX ---
    bad_sections = [s.Name.decode("utf-8", errors="replace").rstrip("\x00")
                    for s in pe.sections if s.Name.startswith(b"UPX")]
    if bad_sections:
        fail(binary, f"packed sections found: {bad_sections}")
    stub_at = raw.find(b"UPX!")
    if stub_at != -1:
        fail(binary, f"UPX stub signature found at offset {stub_at}")
    print(f"   no-UPX: {len(pe.sections)} sections, none packed, no stub signature")

    print(f"[PASS] {binary}")
    return len(REQUIRED_STRINGFILEINFO_FIELDS), len(manifest), len(pe.sections)


def main():
    print("=" * 71)
    print("WSUS Offline Next - Native Installer Binary-Hygiene Battery")
    print("=" * 71)
    total_fields = total_manifest = total_sections = 0
    for binary in BINARIES:
        fields, manifest_len, sections = check_binary(binary)
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
