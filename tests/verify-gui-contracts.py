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
print("[Test 1/3] Verifying enginecontracts.pas frozen INI sections and keys...")
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
]
missing_keys = [t for t in required_keys if f"'{t}'" not in contracts]
if missing_keys:
    print(f"[FAIL] Missing frozen INI keys in enginecontracts.pas: {missing_keys}")
    sys.exit(1)
print("[PASS] Test 1: enginecontracts.pas frozen INI sections and keys intact.")

# Test 2: argv contracts (the launcher forwards argv verbatim, so the
# incumbent 'enu'/'deu' language contract and the frozen switch table persist)
print("\n[Test 2/3] Verifying command-line argument handling contracts...")
assert "ENG_SWITCH_COUNT = 24" in contracts, "Installer missing the frozen 24-token switch table"
for token in ["/auditonly", "/updateoffice", "/autoreboot", "/instmsi"]:
    assert f"'{token}'" in contracts, f"Installer missing frozen argv token {token}"
with open(os.path.join("src-native", "installer", "strings_de_en.pas"), "r", encoding="utf-8") as f:
    strings_unit = f.read()
assert "'enu'" in strings_unit and "'deu'" in strings_unit, \
    "Installer missing enu/deu argv language handling"
print("[PASS] Test 2: Command-line contracts verified on the native sources.")

# Test 3: native compile + launcher contracts
print("\n[Test 3/3] Compiling the native installer (both Release modes) and verifying the launcher contract...")
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
print("[PASS] Test 3: Native compile and launcher contracts verified.")

print("\n" + "=" * 71)
print("SUCCESS: All 3 GUI contract tests passed!")
print("=" * 71)
