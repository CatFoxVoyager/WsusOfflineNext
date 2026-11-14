import os
import subprocess
import sys

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(repo_root)

print("=" * 71)
print("WSUS Offline Next - GUI Contract Verification Suite (native host)")
print("=" * 71)

# The generator-side INI/argv frozen-contract enforcement was removed with
# the generator itself in Phase 25. The installer-side contracts moved to
# the native Pascal sources in Phase 26; the Windows-1252 ANSI byte test
# retired together with the au3 source (all native sources are UTF-8).

LAZARUS_ROOT = os.environ.get("WO_LAZARUS_ROOT",
                              os.path.join(repo_root, ".planning", "tmp", "23-tools", "lazarus"))
LAZBUILD = os.path.join(LAZARUS_ROOT, "lazbuild.exe")
LPI = os.path.join(repo_root, "src-native", "installer", "installer.lpi")

# Test 1: enginecontracts.pas frozen INI sections/keys
print("[Test 1/6] Verifying enginecontracts.pas frozen INI sections and keys...")
with open(os.path.join("src-native", "installer", "enginecontracts.pas"), "r", encoding="utf-8") as f:
    contracts = f.read()

required_sections = [
    "ENG_INI_SECTION_INSTALLATION", "ENG_INI_SECTION_CONTROL",
    "ENG_INI_SECTION_MESSAGING", "ENG_INI_SECTION_MSI",
]
missing_sections = [t for t in required_sections if t not in contracts]
if missing_sections:
    print(f"[FAIL] Missing INI section constants in enginecontracts.pas: {missing_sections}")
    sys.exit(1)

required_keys = [
    "upgradebuilds", "updatercerts", "instdotnet35", "instdotnet4",
    "instwmf", "updatedotnet5", "updatecpp",
    "instedge", "instwebview2",
    "verify", "autoreboot", "shutdown", "auditonly", "showlog",
    "upgradeos",
]
missing_keys = [t for t in required_keys if f"'{t}'" not in contracts]
if missing_keys:
    print(f"[FAIL] Missing frozen INI keys in enginecontracts.pas: {missing_keys}")
    sys.exit(1)

# Write-back absence check (PATH-03, DEC-10): upgradeos is the SECOND
# never-written key (after upgradebuilds). Per-run consent travels by argv
# only (/upgradeos:<build>); IniCopyAll must never persist it - the client
# INI default stays Disabled (template upgradeos=Disabled).
with open(os.path.join("src-native", "installer", "mainform.pas"), "r", encoding="utf-8") as f:
    mainform_src = f.read()
for line_no, line in enumerate(mainform_src.splitlines(), 1):
    if "WriteString" in line and "upgradeos" in line:
        print(f"[FAIL] mainform.pas:{line_no}: WriteString line names upgradeos - "
              f"write-back contract violation (upgradeos is never written back by "
              f"IniCopyAll; per-run consent travels by argv only, default Disabled).")
        sys.exit(1)
print("[PASS] Test 1: enginecontracts.pas frozen INI sections and keys intact.")

# Test 2: argv contracts (the launcher forwards argv verbatim, so the
# incumbent 'enu'/'deu' language contract and the frozen switch table persist)
print("\n[Test 2/6] Verifying command-line argument handling contracts...")
assert "ENG_SWITCH_COUNT = 25" in contracts, "Installer missing the frozen 25-token switch table"
assert "ENG_INI_DEFAULT_COUNT = 25" in contracts, "Installer missing the frozen 25-row INI defaults table"
for token in ["/auditonly", "/updateoffice", "/autoreboot", "/instmsi", "/upgradeos"]:
    assert f"'{token}'" in contracts, f"Installer missing frozen argv token {token}"
with open(os.path.join("src-native", "installer", "strings_de_en.pas"), "r", encoding="utf-8") as f:
    strings_unit = f.read()
assert "'enu'" in strings_unit and "'deu'" in strings_unit, \
    "Installer missing enu/deu argv language handling"
print("[PASS] Test 2: Command-line contracts verified on the native sources.")

# Test 3: generator host OS-upgrades twin contract (legacy-save
# mirror-sync). The generator GUI has no upgrade picker until Phase 36,
# so a save WITHOUT the "upgrade" payload property must PRESERVE a
# hand-seeded selection: the prior [OS Upgrades] section is carried over
# verbatim and the flat bash twin (sh/os-upgrades.ini, DEC-32-08 - the
# only file the pipelines read) is re-derived from the prior Enabled
# keys. Only an EXPLICIT property rewrites the section; present-but-
# empty keeps the explicit-cleared DELETE contract (no stale twin).
# Source-level pin over the generator host (path overridable for
# scratch-copy bite proofs).
print("\n[Test 3/6] Verifying the generator host OS-upgrades twin contract...")
GENERATOR_HOST_CS = os.environ.get(
    "WSON_GENERATOR_HOST_CS",
    os.path.join("src-modern", "generator", "host", "Program.cs"))
with open(GENERATOR_HOST_CS, "r", encoding="utf-8") as f:
    gen_host_src = f.read()

contract_shapes = [
    # Presence probed ONCE, shared by the section gate and the twin write.
    ("presence-probe guard",
     "GetUpgradePayloadSelection(payload, out bool upgradePayloadPresent)"),
    # The absent-vs-present section gate: present -> emit-side writer.
    ("absent-vs-present section gate",
     "if (upgradePayloadPresent)"),
    # Legacy save (property ABSENT): prior section carried over verbatim
    # (recomputing would collapse every prior key to Disabled).
    ("absent-branch section preservation",
     "lines.AddRange(priorUpgradeSectionLines)"),
    # Prior Enabled keys captured for the twin mirror-sync.
    ("prior Enabled keys capture",
     'priorParts[1].Trim().Equals("Enabled", StringComparison.OrdinalIgnoreCase)'),
    # Legacy mirror-sync guard: absent AND feeding the twin.
    ("absent-branch twin mirror-sync guard",
     "!upgradePayloadPresent"),
    # Present-but-empty (explicit cleared) DELETE contract kept intact.
    ("present-empty stale-twin delete",
     "File.Delete(upgradeFlat)"),
]
missing_shapes = [(name, shape) for (name, shape) in contract_shapes
                  if shape not in gen_host_src]
for name, shape in missing_shapes:
    print(f"[FAIL] generator host {GENERATOR_HOST_CS}: missing {name} literal: {shape}")
if missing_shapes:
    sys.exit(1)
print("[PASS] Test 3: generator host OS-upgrades twin contract verified.")

# Test 4: generator host dev-root discovery contract (bounded parent walk
# over the UpdateGenerator.ini marker). The distance from BaseDirectory to
# the repo root depends on the build layout: 0 levels for the shipped root
# exe, 5 for a plain Debug bin, 7 for a Debug bin with a RuntimeIdentifier
# (win-x64 adds a folder). A fixed-depth jump never finds the marker in the
# RID layout: the host falls back to BaseDirectory and the launched pipeline
# gets a nonexistent WorkingDirectory ("Nom de repertoire non valide").
# Source-level pin over the same overridable path as Test 3.
print("\n[Test 4/6] Verifying the generator host dev-root parent-walk contract...")
walk_shapes = [
    # The walk is rooted at the app's BaseDirectory (level 0 = shipped root).
    ("BaseDirectory-rooted walk", "new DirectoryInfo(baseDir)"),
    # A bounded loop probes EVERY parent level - no fixed-depth jump.
    ("bounded parent-walk loop",
     "for (int levels = 0; levels <= 10 && dir != null; levels++)"),
    # Each level probes the marker and returns on the FIRST hit.
    ("marker existence probe",
     'File.Exists(Path.Combine(dir.FullName, "UpdateGenerator.ini"))'),
    # Parents are walked one level at a time.
    ("parent-level progression", "dir = dir.Parent"),
    # Contract fallback: marker found nowhere -> BaseDirectory (unchanged).
    ("BaseDirectory fallback", "return baseDir;"),
]
missing_walk = [(name, shape) for (name, shape) in walk_shapes
                if shape not in gen_host_src]
for name, shape in missing_walk:
    print(f"[FAIL] generator host {GENERATOR_HOST_CS}: missing {name} literal: {shape}")
if missing_walk:
    sys.exit(1)
# Regression pin: the old fixed 5-level jump literal must be gone.
if '"..", "..", "..", "..", ".."' in gen_host_src:
    print(f"[FAIL] generator host {GENERATOR_HOST_CS}: fixed 5-level '..' jump still present - "
          f"RID layouts add win-x64 and need 7 levels; the walk must probe every parent.")
    sys.exit(1)
print("[PASS] Test 4: generator host dev-root parent-walk contract verified.")

# Test 5: native compile + launcher contracts
print("\n[Test 5/6] Compiling the native installer (both Release modes) and verifying the launcher contract...")
if not os.path.exists(LAZBUILD):
    print(f"[FAIL] lazbuild not found at {LAZBUILD} - set WO_LAZARUS_ROOT "
          f"(CI runner installation is Phase 27's lane)")
    sys.exit(1)
for mode in ["Release-i386", "Release-x64"]:
    res = subprocess.run([LAZBUILD, f"--build-mode={mode}", LPI],
                         cwd=repo_root, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[FAIL] lazbuild {mode} failed on installer.lpi (exit code {res.returncode})")
        print(res.stdout[-2000:])
        print(res.stderr[-2000:])
        sys.exit(1)
    print(f"  lazbuild {mode}: compiled clean.")

launcher_paths = [os.path.join("client", "UpdateInstaller.cmd")]
for lp in launcher_paths:
    if not os.path.exists(lp):
        print(f"[FAIL] Launcher script {lp} does not exist!")
        sys.exit(1)
    with open(lp, "r", encoding="utf-8", errors="replace") as lf:
        l_content = lf.read()
    for token in ["UpdateInstallerLegacy.exe", "UpdateInstallerModern.exe", "TARGET_NAME", "runas"]:
        if token not in l_content:
            print(f"[FAIL] Required adaptive token '{token}' missing from {lp}")
            sys.exit(1)
    print(f"  {lp}: Adaptive contracts verified.")

# The .NET host's WebView2 fallback must keep probing the exact name slots.
with open(os.path.join("src-modern", "installer", "host", "Program.cs"), "r", encoding="utf-8") as f:
    host = f.read()
for name in ["UpdateInstaller.orig.exe", "UpdateInstallerLegacy.exe"]:
    if name not in host:
        print(f"[FAIL] Required exact-name probe '{name}' missing from Program.cs")
        sys.exit(1)
print("  Program.cs exact-name probes verified.")
print("[PASS] Test 5: Native compile and launcher contracts verified.")

# Test 6: Phase 36 picker wiring pins (36-03). The budget line (DEC-36-03
# manifest-first), the media-language select (DEC-36-06), the arch-routed
# /includeupgrade spawn tokens (DEC-08 grammar, DEC-36-01 scope widening)
# and the touched-flag payload rule, pinned source-side over the generator
# host AND the App.tsx frontend. Fail-closed literal lists, Test-3 style:
# every pin names its literal, any miss exits 1. The host path reuses the
# WSON_GENERATOR_HOST_CS override; the frontend path gains its own
# WSON_GENERATOR_APP_TSX override (same idiom) for bite proofs.
print("\n[Test 6/6] Verifying the Phase 36 picker wiring literals...")

def check_picker_pins(source, source_label, pins):
    """Evaluate (name, literal, op, expected) pins over one source;
    print a named [FAIL] line per miss and return True when all pass."""
    failed = False
    for name, shape, op, expected in pins:
        count = source.count(shape)
        ok = (count == expected) if op == "==" else (count >= expected)
        if not ok:
            print(f"[FAIL] picker wiring {source_label}: pin '{name}' expects "
                  f"{op} {expected} occurrence(s) of: {shape} (found {count})")
            failed = True
    return not failed

# Host pins (over the existing GENERATOR_HOST_CS reader - gen_host_src
# already holds the resolved path's content from Tests 3/4).
picker_pins_host = [
    # The spawn site re-extracts the selection with a SECOND independent
    # call of the pure parser (SaveIniFiles' pinned call is the first).
    ("upgrade payload re-extraction at spawn site",
     "GetUpgradePayloadSelection(payload, out bool upgradePayloadPresent)", ">=", 2),
    # DEC-08 singular grammar, composed only from validated key digits.
    ("token composition literal",
     '"/includeupgrade:"', ">=", 1),
    # Arch-routed token lists (x64 -> w100-x64, x86 -> w100).
    ("arch-routed x64 token list",
     "upgradeSwitchesX64", ">=", 1),
    ("arch-routed x86 token list",
     "upgradeSwitchesX86", ">=", 1),
    # DEC-36-01 scope widening predicates (upgrade-only selections spawn).
    ("scope widening x64 predicate",
     'EndsWith("_x64")', ">=", 1),
    ("scope widening x86 predicate",
     'EndsWith("_x86")', ">=", 1),
    # The env carriage exists exactly once - set only on a language value.
    ("language env carriage (exactly once)",
     'EnvironmentVariables["WOU_UPGRADE_LANG"]', "==", 1),
    # DEC-36-03: the budget reads the staged manifest total_mib.
    ("budget source (manifest total_mib)",
     "total_mib", ">=", 1),
]

# Frontend pins (new reader, path overridable for bite proofs).
GENERATOR_APP_TSX = os.environ.get(
    "WSON_GENERATOR_APP_TSX",
    os.path.join("src-modern", "generator", "src", "App.tsx"))
with open(GENERATOR_APP_TSX, "r", encoding="utf-8") as f:
    gen_app_src = f.read()

picker_pins_app = [
    # Touched-flag payload rule (the 26a0073 regression class).
    ("payload rule spread-conditional",
     "upgradeTouched || upgradeSelection.length > 0 || upgradeFullTarget", "==", 1),
    # DEC-36-06: the language rides inside the same conditional.
    ("payload language fragment",
     "upgradeLang: upgradeLang", "==", 1),
    # DEC-36-07 roster partition over the pushed rows.
    ("roster partition fuMedia",
     "fuMedia", ">=", 1),
    ("roster partition ekbPresent",
     "ekbPresent", ">=", 1),
    # Budget line states - byte-exact UI-SPEC Copywriting Contract copy.
    ("budget calm copy",
     "Estimated download: ", "==", 1),
    ("budget warning copy",
     "Media above 4 GB needs exFAT/NTFS formatting or split .swm handling on FAT32 drives", "==", 1),
    ("budget estimate copy",
     "measured on 26200 en-us; varies by target and language", "==", 1),
    # Default option label of the media-language select.
    ("default language label",
     "English (en-us)", "==", 1),
    # Roster merge arm inside the state-message listener.
    ("roster state arm",
     "if (data.upgrades)", "==", 1),
    # UX-1 (36-UAT live run 2026-11-14): the EKB group renders newest-first.
    # The pin is the descending comparator literal (b before a) - an
    # ascending flip (a-b) misses the pin and fails the test.
    ("EKB newest-first comparator (UX-1)",
     "parseInt(b.build, 10) - parseInt(a.build, 10)", "==", 1),
    # UX-2 (36-UAT live run 2026-11-14): friendly version labels on the
    # picker rows. The pins target the new machinery (map const, its
    # render sites, the label template) plus one Win10 vocabulary string
    # unique to the map - a bare "Windows 11" pin could not bite, the
    # Win11 tab's own state list already carries those names.
    ("friendly label map const (UX-2)",
     "UPGRADE_BUILD_LABELS", ">=", 2),
    ("friendly label render sites (UX-2)",
     "upgradeLabelOf(row.build)", ">=", 3),
    ("friendly label template (UX-2)",
     "`${friendly} (Build ${build})`", "==", 1),
    ("friendly label win10 vocabulary (UX-2)",
     "'Windows 10 22H2'", ">=", 1),
]

host_ok = check_picker_pins(gen_host_src, GENERATOR_HOST_CS, picker_pins_host)
app_ok = check_picker_pins(gen_app_src, GENERATOR_APP_TSX, picker_pins_app)
if not host_ok or not app_ok:
    sys.exit(1)
print("[PASS] Test 6: Phase 36 picker wiring literals verified "
      f"(host {GENERATOR_HOST_CS}, frontend {GENERATOR_APP_TSX}).")

print("\n" + "=" * 71)
print("SUCCESS: All 6 GUI contract tests passed!")
print("=" * 71)
