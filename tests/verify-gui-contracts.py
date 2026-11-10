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
print("[Test 1/4] Verifying enginecontracts.pas frozen INI sections and keys...")
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
print("\n[Test 2/4] Verifying command-line argument handling contracts...")
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
print("\n[Test 3/4] Verifying the generator host OS-upgrades twin contract...")
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

# Test 4: native compile + launcher contracts
print("\n[Test 4/4] Compiling the native installer (both Release modes) and verifying the launcher contract...")
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
print("[PASS] Test 4: Native compile and launcher contracts verified.")

print("\n" + "=" * 71)
print("SUCCESS: All 4 GUI contract tests passed!")
print("=" * 71)
