import sys
import os
import subprocess
import tempfile

repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(repo_root)

print("=" * 71)
print("WSUS Offline Update - GUI Contract & Encoding Verification Suite")
print("=" * 71)

# Test 1: UpdateGenerator.au3 frozen tokens
print("[Test 1/5] Verifying UpdateGenerator.au3 frozen INI keys and sections...")
with open("UpdateGenerator.au3", "r", encoding="windows-1252") as f:
    gen_content = f.read()

required_gen_tokens = [
    "opts_token_verify", "opts_token_includedotnet", "opts_token_seconly", "opts_token_wddefs",
    "opts_token_includeedge", "opts_token_includewebview2",
    "iso_token_cd", "iso_token_dvd", "iso_token_skiphashes",
    "usb_token_copy", "usb_token_path", "usb_token_cleanup",
    "misc_token_proxy", "misc_token_wsus", "misc_token_skipdownload", "misc_token_minimize",
    "ini_section_o2k16", "ini_section_o2k19", "ini_section_o2k21", "ini_section_o2k24",
    "arch_token_x86", "arch_token_x64", "lang_token_glb",
    "ini_section_win11_ver", "ini_section_win10_ver"
]

missing_gen = [t for t in required_gen_tokens if t not in gen_content]
if missing_gen:
    print(f"[FAIL] Missing tokens in UpdateGenerator.au3: {missing_gen}")
    sys.exit(1)

office_checkbox_tokens = [
    "$o2k16_x86", "$o2k16_x64",
    "$o2k19_x86", "$o2k19_x64",
    "$o2k21_x86", "$o2k21_x64",
    "$o2k24_x86", "$o2k24_x64"
]
missing_office = [t for t in office_checkbox_tokens if t not in gen_content]
if missing_office:
    print(f"[FAIL] Missing Office checkbox controls in UpdateGenerator.au3: {missing_office}")
    sys.exit(1)
print("[PASS] Test 1: UpdateGenerator.au3 frozen tokens intact.")

# Test 2: client/UpdateInstaller.au3 frozen tokens
print("\n[Test 2/5] Verifying client/UpdateInstaller.au3 frozen INI keys and sections...")
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
print("[PASS] Test 2: client/UpdateInstaller.au3 frozen tokens intact.")

# Test 3: Argv contracts
print("\n[Test 3/5] Verifying command-line argument handling contracts...")
assert 'Case "enu"' in gen_content, 'Generator missing enu argv handling'
assert 'Case "deu"' in gen_content, 'Generator missing deu argv handling'
assert 'StringRight($CmdLine[1], 4) = ".ini"' in gen_content, 'Generator missing custom ini argv handling'

assert 'Case "enu"' in inst_content, 'Installer missing enu argv handling'
assert 'Case "deu"' in inst_content, 'Installer missing deu argv handling'
print("[PASS] Test 3: Command-line contracts verified on both AU3 scripts.")

# Test 4: ANSI byte encoding integrity
print("\n[Test 4/5] Verifying Windows-1252 ANSI byte encoding integrity...")
for path in ["UpdateGenerator.au3", "client/UpdateInstaller.au3"]:
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
print("[PASS] Test 4: Windows-1252 ANSI byte integrity verified.")

# Test 5: Compilation with Aut2exe
print("\n[Test 5/6] Compiling both AU3 legacy scripts with bin/Aut2exe.exe /nopack...")
aut2exe = os.path.join(repo_root, "bin", "Aut2exe.exe")
tmp_gen = os.path.join(tempfile.gettempdir(), "test_UpdateGenerator.exe")
tmp_inst = os.path.join(tempfile.gettempdir(), "test_UpdateInstaller.exe")
res1 = subprocess.run([aut2exe, "/in", "UpdateGenerator.au3", "/out", tmp_gen, "/nopack"])
if res1.returncode != 0:
    print(f"[FAIL] Aut2exe failed on UpdateGenerator.au3 (exit code {res1.returncode})")
    sys.exit(1)

res2 = subprocess.run([aut2exe, "/in", os.path.join("client", "UpdateInstaller.au3"), "/out", tmp_inst, "/nopack"])
if res2.returncode != 0:
    print(f"[FAIL] Aut2exe failed on client/UpdateInstaller.au3 (exit code {res2.returncode})")
    sys.exit(1)
if os.path.exists(tmp_gen):
    try: os.remove(tmp_gen)
    except: pass
if os.path.exists(tmp_inst):
    try: os.remove(tmp_inst)
    except: pass
print("[PASS] Test 5: Both AU3 legacy scripts compiled successfully.")

# Test 6: Adaptive Launchers contracts & compilation
print("\n[Test 6/6] Verifying and compiling Adaptive Launchers...")
launcher_paths = ["UpdateGeneratorLauncher.au3", os.path.join("client", "UpdateInstallerLauncher.au3")]
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
print("[PASS] Test 6: Adaptive Launchers contracts and compilation verified.")

print("\n" + "=" * 71)
print("SUCCESS: All 6 GUI contract and encoding tests passed!")
print("=" * 71)
