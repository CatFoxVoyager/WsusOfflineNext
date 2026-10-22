#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UpdateProjectBranding.py
Automates the renaming and version/build stamping across the entire WSUS Offline Next codebase:
- Windows Command Scripts (cmd/*.cmd, client/cmd/*.cmd, CompileAutoItScripts.cmd)
- VBScript (client/cmd/DetermineSystemProperties.vbs)
- AutoIt 3 applications (UpdateGenerator.au3, client/UpdateInstaller.au3)
- Bash download/ISO scripts (sh/*.bash, sh/*/*.bash)
- Version tracking files (static/SelfUpdateVersion-this.txt)
- Modern applications (src-modern/generator, src-modern/installer: React, C# host, csproj, package.json)

Preserves exact file encodings (windows-1252 ANSI for AutoIt/VBS/CMD, UTF-8 for modern apps/bash)
and exact newline formats (CRLF for Windows scripts, LF for Bash).
"""

import os
import sys
import re
import argparse
import subprocess

REPO_ROOT = os.path.dirname(os.path.abspath(__file__))

DEFAULT_NAME = "WSUS Offline Next"
DEFAULT_EDITION = "Next Edition"
DEFAULT_VERSION = "2026.10.0"
DEFAULT_BUILD = "b2026.10"
DEFAULT_COMPANY = "WSUS Offline Next Project"

def make_version_4(version_str: str) -> str:
    parts = version_str.strip().split(".")
    while len(parts) < 4:
        parts.append("0")
    return ".".join(parts[:4])

def replace_in_file(rel_path: str, replacements: list, encoding: str = "windows-1252", newline: str = None, dry_run: bool = False):
    full_path = os.path.join(REPO_ROOT, rel_path)
    if not os.path.isfile(full_path):
        print(f"  [WARN] File not found: {rel_path}")
        return 0

    with open(full_path, "r", encoding=encoding, newline=newline) as f:
        content = f.read()

    original_content = content
    changes_count = 0

    for pattern, replacement in replacements:
        if isinstance(pattern, str):
            if pattern in content:
                count = content.count(pattern)
                content = content.replace(pattern, replacement)
                changes_count += count
        elif isinstance(pattern, re.Pattern):
            matches = list(pattern.finditer(content))
            if matches:
                content, count = pattern.subn(lambda m: replacement, content)
                changes_count += count

    if content != original_content:
        print(f"  [MODIFIED] {rel_path} ({changes_count} substitution(s))")
        if not dry_run:
            with open(full_path, "w", encoding=encoding, newline=newline) as f:
                f.write(content)
        return changes_count
    else:
        print(f"  [UNCHANGED] {rel_path}")
        return 0

def apply_branding(name: str, edition: str, version: str, build: str, company: str, dry_run: bool = False):
    version_4 = make_version_4(version)
    full_version_build = f"{version} ({build})"
    print(f"\nTarget Branding:")
    print(f"  Project Name   : {name}")
    print(f"  Edition        : {edition}")
    print(f"  Version        : {version} (4-part: {version_4})")
    print(f"  Build Tag      : {build}")
    print(f"  Version String : {full_version_build}")
    print(f"  Company / Org  : {company}")
    print(f"  Dry Run        : {dry_run}\n")

    total_changes = 0

    # =========================================================================
    # 1. Windows Batch Scripts (*.cmd)
    # =========================================================================
    print("--- Updating Windows Command Scripts (.cmd) ---")

    # Header comment regex: matches "rem ***   - Community Edition -   ***" or any prior "- ... Edition - "
    re_cmd_header = re.compile(r"rem \*\*\*\s+-\s+.*Edition\s+-\s+\*\*\*")
    cmd_header_repl = f"rem ***   - {edition} -   ***"

    # All known CMD files with edition headers
    cmd_files_with_header = [
        "CompileAutoItScripts.cmd",
        "cmd/ActivateAria2Downloads.cmd",
        "cmd/AddCustomLanguageSupport.cmd",
        "cmd/CheckOUVersion.cmd",
        "cmd/CopyToTarget.cmd",
        "cmd/CreateISOImage.cmd",
        "cmd/DownloadUpdates.cmd",
        "cmd/IntegrateSourcesSxsFolder.cmd",
        "cmd/RemoveCustomLanguageSupport.cmd",
        "cmd/RemoveGermanLanguageSupport.cmd",
        "cmd/UpdateOU.cmd",
        "client/cmd/DoUpdate.cmd",
        "client/cmd/InstallListedUpdates.cmd",
        "client/cmd/InstallOfficeUpdate.cmd",
        "client/cmd/InstallOSUpdate.cmd",
        "client/cmd/ListUpdateFile.cmd",
        "client/cmd/ListUpdatesToInstall.cmd",
        "client/cmd/SetTargetEnvVars.cmd",
    ]

    for cf in cmd_files_with_header:
        total_changes += replace_in_file(
            cf,
            [(re_cmd_header, cmd_header_repl)],
            encoding="windows-1252",
            newline="",
            dry_run=dry_run
        )

    # Specific replacements in cmd/DownloadUpdates.cmd
    total_changes += replace_in_file(
        "cmd/DownloadUpdates.cmd",
        [
            (re.compile(r"set WSUSOFFLINE_VERSION=.*"), f"set WSUSOFFLINE_VERSION={full_version_build}"),
            (re.compile(r"echo Starting (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - download v\. %WSUSOFFLINE_VERSION% for %1 %2\.\.\."),
             f"echo Starting {name} - download v. %WSUSOFFLINE_VERSION% for %1 %2..."),
            (re.compile(r'call :Log "Info: Starting (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - download v\. %WSUSOFFLINE_VERSION% for %1 %2"'),
             f'call :Log "Info: Starting {name} - download v. %WSUSOFFLINE_VERSION% for %1 %2"'),
            (re.compile(r'echo action=Run (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - v\. %WSUSOFFLINE_VERSION% \(%DATE:~-11%\)>>\.\.\\client\\autorun\.inf'),
             f'echo action=Run {name} - v. %WSUSOFFLINE_VERSION% (%DATE:~-11%)>>..\\client\\autorun.inf'),
            (re.compile(r'call :Log "Info: Ending (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - download for %1 %2"'),
             f'call :Log "Info: Ending {name} - download for %1 %2"'),
        ],
        encoding="windows-1252",
        newline="",
        dry_run=dry_run
    )

    # Specific replacements in client/cmd/DoUpdate.cmd
    total_changes += replace_in_file(
        "client/cmd/DoUpdate.cmd",
        [
            (re.compile(r"set WSUSOFFLINE_VERSION=.*"), f"set WSUSOFFLINE_VERSION={full_version_build}"),
            (re.compile(r"echo Starting (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - v\. %WSUSOFFLINE_VERSION% at %TIME%\.\.\."),
             f"echo Starting {name} - v. %WSUSOFFLINE_VERSION% at %TIME%..."),
            (re.compile(r'call :Log "Info: Starting (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - v\. %WSUSOFFLINE_VERSION%"'),
             f'call :Log "Info: Starting {name} - v. %WSUSOFFLINE_VERSION%"'),
            (re.compile(r"echo Ending (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - at %TIME%\.\.\."),
             f"echo Ending {name} - at %TIME%..."),
            (re.compile(r'call :Log "Info: Ending (?:WSUS Offline Update - Community Edition|WSUS Offline Next)"'),
             f'call :Log "Info: Ending {name}"'),
        ],
        encoding="windows-1252",
        newline="",
        dry_run=dry_run
    )

    # Replacements in cmd/CheckOUVersion.cmd and cmd/UpdateOU.cmd
    for ou_file in ["cmd/CheckOUVersion.cmd", "cmd/UpdateOU.cmd"]:
        total_changes += replace_in_file(
            ou_file,
            [
                ("WSUS Offline Update - Community Edition", name),
            ],
            encoding="windows-1252",
            newline="",
            dry_run=dry_run
        )

    # =========================================================================
    # 2. VBScript (client/cmd/DetermineSystemProperties.vbs)
    # =========================================================================
    print("\n--- Updating VBScript (.vbs) ---")
    re_vbs_header = re.compile(r"' \*\*\*\s+-\s+.*Edition\s+-\s+\*\*\*")
    vbs_header_repl = f"' ***   - {edition} -   ***"
    total_changes += replace_in_file(
        "client/cmd/DetermineSystemProperties.vbs",
        [(re_vbs_header, vbs_header_repl)],
        encoding="windows-1252",
        newline="",
        dry_run=dry_run
    )

    # =========================================================================
    # 3. AutoIt 3 Scripts (*.au3)
    # =========================================================================
    print("\n--- Updating AutoIt 3 GUI Scripts (.au3) ---")
    # UpdateGenerator.au3
    total_changes += replace_in_file(
        "UpdateGenerator.au3",
        [
            (re.compile(r"; \*\*\*\s+.* - Generator\s+\*\*\*"),
             f"; ***  {name} {version} - Generator  ***"),
            (re.compile(r"; \*\*\*\s+-\s+.*Edition\s+-\s+\*\*\*"),
             f"; ***         - {edition} -          ***"),
            (re.compile(r'#pragma compile\(CompanyName, [^)]+\)'),
             f'#pragma compile(CompanyName, "{company}")'),
            (re.compile(r'#pragma compile\(FileVersion, [^)]+\)'),
             f'#pragma compile(FileVersion, {version})'),
            (re.compile(r'#pragma compile\(ProductName, [^)]+\)'),
             f'#pragma compile(ProductName, "{name}")'),
            (re.compile(r'#pragma compile\(ProductVersion, [^)]+\)'),
             f'#pragma compile(ProductVersion, {version})'),
            (re.compile(r'Dim Const \$caption\s*=\s*"[^"]+"'),
             f'Dim Const $caption                      = "{name} - {full_version_build}"'),
        ],
        encoding="windows-1252",
        newline="",
        dry_run=dry_run
    )

    # client/UpdateInstaller.au3
    total_changes += replace_in_file(
        "client/UpdateInstaller.au3",
        [
            (re.compile(r"; \*\*\*\s+.* - Installer\s+\*\*\*"),
             f"; ***  {name} {version} - Installer  ***"),
            (re.compile(r"; \*\*\*\s+-\s+.*Edition\s+-\s+\*\*\*"),
             f"; ***         - {edition} -          ***"),
            (re.compile(r'#pragma compile\(CompanyName, [^)]+\)'),
             f'#pragma compile(CompanyName, "{company}")'),
            (re.compile(r'#pragma compile\(FileVersion, [^)]+\)'),
             f'#pragma compile(FileVersion, {version})'),
            (re.compile(r'#pragma compile\(ProductName, [^)]+\)'),
             f'#pragma compile(ProductName, "{name}")'),
            (re.compile(r'#pragma compile\(ProductVersion, [^)]+\)'),
             f'#pragma compile(ProductVersion, {version})'),
            (re.compile(r'Dim Const \$caption\s*=\s*"[^"]+"'),
             f'Dim Const $caption                      = "{name} - {full_version_build} - Installer"'),
        ],
        encoding="windows-1252",
        newline="",
        dry_run=dry_run
    )

    # =========================================================================
    # 4. Linux / Bash Scripts (sh/*.bash)
    # =========================================================================
    print("\n--- Updating Linux/Bash Scripts (.bash) ---")
    total_changes += replace_in_file(
        "sh/download-updates-tasks/90-finalization.bash",
        [
            (re.compile(r'printf \'%s\\r\\n\' "action=Run (?:WSUS Offline Update - Community Edition|WSUS Offline Next) - v\. \$\{wsusoffline_version\} \(\$\{build_date\}\)"'),
             f'printf \'%s\\r\\n\' "action=Run {name} - v. ${{wsusoffline_version}} (${{build_date}})"'),
        ],
        encoding="utf-8",
        newline="\n",
        dry_run=dry_run
    )

    total_changes += replace_in_file(
        "sh/common-tasks/20-start-logging.bash",
        [
            (re.compile(r'log_info_message "Running on (?:WSUS Offline Update, Community Edition|WSUS Offline Next) \$\{wsusoffline_version\}"'),
             f'log_info_message "Running on {name} ${{wsusoffline_version}}"'),
        ],
        encoding="utf-8",
        newline="\n",
        dry_run=dry_run
    )

    for bash_script in ["sh/download-updates.bash", "sh/update-generator.bash"]:
        total_changes += replace_in_file(
            bash_script,
            [
                (re.compile(r'# Supported version: WSUS Offline (?:Update, Community Edition \d+\.\d+.*|Next.*)'),
                 f'# Supported version: {name} {full_version_build}'),
            ],
            encoding="utf-8",
            newline="\n",
            dry_run=dry_run
        )

    # =========================================================================
    # 5. Static SelfUpdate Version File
    # =========================================================================
    print("\n--- Updating SelfUpdate Configuration ---")
    total_changes += replace_in_file(
        "static/SelfUpdateVersion-this.txt",
        [
            (re.compile(r"^[^,\r\n]+,[^\r\n]+", re.MULTILINE), f"{version},release"),
        ],
        encoding="utf-8",
        newline="\r\n",
        dry_run=dry_run
    )

    # =========================================================================
    # 6. Build scripts (CompileModernApps.cmd)
    # =========================================================================
    total_changes += replace_in_file(
        "CompileModernApps.cmd",
        [
            (re.compile(r"echo \[.*\] Compiling v.* Executables"), f"echo [{name}] Compiling v{version} Executables"),
        ],
        encoding="windows-1252",
        newline="",
        dry_run=dry_run
    )

    # =========================================================================
    # 6. Modern Apps (src-modern)
    # =========================================================================
    print("\n--- Updating Modern Apps (src-modern) ---")
    
    # C# Hosts
    total_changes += replace_in_file(
        "src-modern/generator/host/Program.cs",
        [
            (re.compile(r'this\.Text = "[^"]* - Generator";'),
             f'this.Text = "{name} {version} - Generator";'),
        ],
        encoding="utf-8",
        newline="",
        dry_run=dry_run
    )

    total_changes += replace_in_file(
        "src-modern/installer/host/Program.cs",
        [
            (re.compile(r'this\.Text = "[^"]* - Client Installer";'),
             f'this.Text = "{name} {version} - Client Installer";'),
        ],
        encoding="utf-8",
        newline="",
        dry_run=dry_run
    )

    # .csproj files
    for csproj in ["src-modern/generator/host/UpdateGenerator.csproj", "src-modern/installer/host/UpdateInstaller.csproj"]:
        total_changes += replace_in_file(
            csproj,
            [
                (re.compile(r'<Product>[^<]+</Product>'), f'<Product>{name}</Product>'),
                (re.compile(r'<Version>[^<]+</Version>'), f'<Version>{version}</Version>'),
                (re.compile(r'<FileVersion>[^<]+</FileVersion>'), f'<FileVersion>{version_4}</FileVersion>'),
                (re.compile(r'<AssemblyVersion>[^<]+</AssemblyVersion>'), f'<AssemblyVersion>{version_4}</AssemblyVersion>'),
            ],
            encoding="utf-8",
            newline="",
            dry_run=dry_run
        )

    # package.json files
    for pkg in ["src-modern/generator/package.json", "src-modern/installer/package.json"]:
        total_changes += replace_in_file(
            pkg,
            [
                (re.compile(r'"version":\s*"[^"]+"'), f'"version": "{version}"'),
            ],
            encoding="utf-8",
            newline="",
            dry_run=dry_run
        )

    # React App.tsx files
    total_changes += replace_in_file(
        "src-modern/generator/src/App.tsx",
        [
            (re.compile(r'<h1 className="text-sm font-semibold text-zinc-100 tracking-tight">WSUS Offline (?:Update|Next)</h1>'),
             f'<h1 className="text-sm font-semibold text-zinc-100 tracking-tight">{name}</h1>'),
            (re.compile(r'v\d+\.\d+\.\d+ • Dépôt local'),
             f'v{version} • Dépôt local'),
        ],
        encoding="utf-8",
        newline="",
        dry_run=dry_run
    )

    total_changes += replace_in_file(
        "src-modern/installer/src/App.tsx",
        [
            (re.compile(r'<h1 className="text-sm font-semibold text-zinc-100 tracking-tight">WSUS Offline (?:Update|Next) Installer</h1>'),
             f'<h1 className="text-sm font-semibold text-zinc-100 tracking-tight">{name} Installer</h1>'),
            (re.compile(r'v\d+\.\d+\.\d+ • Élévation Administrateur'),
             f'v{version} • Élévation Administrateur'),
        ],
        encoding="utf-8",
        newline="",
        dry_run=dry_run
    )

    print(f"\n=======================================================================")
    print(f"Branding update complete! Total substitutions: {total_changes}")
    print(f"=======================================================================")
    return total_changes

def main():
    parser = argparse.ArgumentParser(description="Update WSUS Offline Next Branding and Version Stamping across codebase.")
    parser.add_argument("--name", default=DEFAULT_NAME, help=f"Project display name (default: '{DEFAULT_NAME}')")
    parser.add_argument("--edition", default=DEFAULT_EDITION, help=f"Edition name (default: '{DEFAULT_EDITION}')")
    parser.add_argument("--version", default=DEFAULT_VERSION, help=f"Version number (default: '{DEFAULT_VERSION}')")
    parser.add_argument("--build", default=DEFAULT_BUILD, help=f"Build tag (default: '{DEFAULT_BUILD}')")
    parser.add_argument("--company", default=DEFAULT_COMPANY, help=f"Company / Organization name (default: '{DEFAULT_COMPANY}')")
    parser.add_argument("--dry-run", action="store_true", help="Preview substitutions without modifying files.")
    parser.add_argument("--rebuild", action="store_true", help="Trigger CompileModernApps.cmd after applying branding.")
    parser.add_argument("--no-pause", "--nopause", action="store_true", help="Bypass interactive pause in batch wrappers.")

    args = parser.parse_args()

    changes = apply_branding(
        name=args.name,
        edition=args.edition,
        version=args.version,
        build=args.build,
        company=args.company,
        dry_run=args.dry_run
    )

    if args.rebuild and not args.dry_run:
        print("\n--- Triggering CompileModernApps.cmd ---")
        compile_cmd = os.path.join(REPO_ROOT, "CompileModernApps.cmd")
        res = subprocess.run([compile_cmd, "--no-pause"], cwd=REPO_ROOT)
        if res.returncode != 0:
            print(f"[ERROR] Compilation failed with return code {res.returncode}")
            sys.exit(res.returncode)

    sys.exit(0)

if __name__ == "__main__":
    main()
