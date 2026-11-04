import sys
import os
import subprocess
import tempfile

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(repo_root)

print("=" * 71)
print("WSUS Offline Update - GUI Contract & Encoding Verification Suite")
print("=" * 71)

# The generator-side INI/argv frozen-contract enforcement was removed with
# the generator itself in Phase 25; it re-lands in Phase 26 against the
# native GUI host.

# Test 1: client/UpdateInstaller.au3 frozen tokens
print("[Test 1/4] Verifying client/UpdateInstaller.au3 frozen INI keys and sections...")
with open("client/UpdateInstaller.au3", "r", encoding="windows-1252") as f:
    inst_content = f.read()

required_inst_tokens = [
    "ini_section_installation", "ini_section_control", "ini_section_messaging", "ini_section_msi",
    "ini_value_buildupgrade", "ini_value_rcerts", "ini_value_dotnet35", "ini_value_dotnet4",
    "ini_value_wmf", "ini_value_dotnet5", "ini_value_cpp",
    "ini_value_instedge", "ini_value_instwebview2", "ini_value_instoffice",
    "ini_value_verify", "ini_value_autoreboot", "ini_value_shutdown", "ini_value_auditonly", "ini_value_showlog"
]

missing_inst = [t for t in required_inst_tokens if t not in inst_content]
if missing_inst:
    print(f"[FAIL] Missing tokens in client/UpdateInstaller.au3: {missing_inst}")
    sys.exit(1)

inst_office_tokens = [
    "$instoffice", "$lbloffice", "/updateoffice"
]
missing_inst_office = [t for t in inst_office_tokens if t not in inst_content]
if missing_inst_office:
    print(f"[FAIL] Missing Office installer tokens in client/UpdateInstaller.au3: {missing_inst_office}")
    sys.exit(1)
print("[PASS] Test 1: client/UpdateInstaller.au3 frozen tokens intact.")

# Test 2: Argv contracts
print("\n[Test 2/4] Verifying command-line argument handling contracts...")
assert 'Case "enu"' in inst_content, 'Installer missing enu argv handling'
assert 'Case "deu"' in inst_content, 'Installer missing deu argv handling'
print("[PASS] Test 2: Command-line contracts verified on the AU3 installer script.")

# Test 3: ANSI byte encoding integrity
print("\n[Test 3/4] Verifying Windows-1252 ANSI byte encoding integrity...")
for path in ["client/UpdateInstaller.au3"]:
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(b"\xef\xbb\xbf"):
        print(f"[FAIL] {path} has a UTF-8 BOM!")
        sys.exit(1)
    try:
        raw.decode("windows-1252")
    except Exception as e:
        print(f"[FAIL] {path} failed to decode as windows-1252: {e}")
        sys.exit(1)
    # German umlauts check
    umlauts = [b"\xe4", b"\xf6", b"\xfc", b"\xdf"] # ä, ö, ü, ß
    found = sum(1 for u in umlauts if u in raw)
    if found < 2:
        print(f"[FAIL] {path} does not contain expected ANSI umlauts!")
        sys.exit(1)
    print(f"  {path}: Windows-1252 ANSI verified ({len(raw)} bytes, {found} umlaut markers).")
print("[PASS] Test 3: Windows-1252 ANSI byte integrity verified.")

# Test 4: Compilation + launcher contracts
print("\n[Test 4/4] Compiling the AU3 installer script and verifying the launcher contract...")
aut2exe = os.path.join(repo_root, "bin", "Aut2exe.exe")
tmp_inst = os.path.join(tempfile.gettempdir(), "test_UpdateInstaller.exe")

res2 = subprocess.run([aut2exe, "/in", os.path.join("client", "UpdateInstaller.au3"), "/out", tmp_inst, "/nopack"])
if res2.returncode != 0:
    print(f"[FAIL] Aut2exe failed on client/UpdateInstaller.au3 (exit code {res2.returncode})")
    sys.exit(1)
if os.path.exists(tmp_inst):
    try: os.remove(tmp_inst)
    except: pass

launcher_paths = [os.path.join("client", "UpdateInstallerLauncher.au3")]
for lp in launcher_paths:
    if not os.path.exists(lp):
        print(f"[FAIL] Launcher script {lp} does not exist!")
        sys.exit(1)
    with open(lp, "r", encoding="windows-1252") as lf:
        l_content = lf.read()
    for token in ["@OSArch", "@OSBuild", "_IsWebView2Installed", "/legacy", "RunWait"]:
        if token not in l_content:
            print(f"[FAIL] Required adaptive token '{token}' missing from {lp}")
            sys.exit(1)
    tmp_l = os.path.join(tempfile.gettempdir(), "test_" + os.path.basename(lp).replace(".au3", ".exe"))
    res_l = subprocess.run([aut2exe, "/in", lp, "/out", tmp_l, "/nopack"])
    if res_l.returncode != 0:
        print(f"[FAIL] Aut2exe compilation failed on {lp} (code {res_l.returncode})")
        sys.exit(1)
    if os.path.exists(tmp_l):
        try: os.remove(tmp_l)
        except: pass
    print(f"  {lp}: Adaptive contracts & compilation verified.")
print("[PASS] Test 4: Installer compile and launcher contracts verified.")

print("\n" + "=" * 71)
print("SUCCESS: All 4 GUI contract and encoding tests passed!")
print("=" * 71)
