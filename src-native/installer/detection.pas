{*** Detection layer of the native installer: registry/tree probes, the
    .NET/WMF display maps, the Enablement data probe inputs, the network
    share mapping, and the PURE toggle-gating functions.

    Every incumbent probe preserves its per-probe registry VIEW semantics
    (research Pitfall D): the WSH probe reads the 64-bit HKLM view (the
    au3 HKLM64; the flag is ignored on 32-bit Windows), IE/.NET/WMF/Office
    read the default view, the DPI keys are HKCU and unredirected. Never
    route all probes through KEY_WOW64_64KEY.

    The gate functions are PURE (all inputs as parameters) so the console
    testrunner can prove each incumbent gating rule verbatim without LCL
    or live registry state; mainform fills the inputs from the live probes.

    Extraction source: the incumbent installer au3 (Windows-1252, read via
    iconv) - lines 23-44 (constants), 126-202 (Office + share mapping),
    280-365 (builds table predicates + WSH), 367-511 (IE/.NET/WMF maps),
    513-546 (presence probes). The au3 stays the parity source until plan
    03 deletes it. }

unit detection;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Registry,
  enginecontracts, strings_de_en;

const
  { ===== Registry constants (au3:23-41) ===== }
  DET_REG_KEY_WSH_SETTINGS = 'Software\Microsoft\Windows Script Host\Settings';
  DET_REG_VAL_ENABLED = 'Enabled';
  DET_REG_KEY_IE = 'Software\Microsoft\Internet Explorer';
  DET_REG_VAL_VERSION = 'Version';
  DET_REG_KEY_DOTNET35 = 'Software\Microsoft\NET Framework Setup\NDP\v3.5';
  DET_REG_KEY_DOTNET4 = 'Software\Microsoft\NET Framework Setup\NDP\v4\Full';
  DET_REG_VAL_RELEASE = 'Release';
  DET_REG_VAL_PSHVERSION = 'PowerShellVersion';
  DET_REG_KEY_WMF = 'Software\Microsoft\PowerShell\3\PowerShellEngine';
  DET_REG_KEY_OFFICE16_ROOT = 'Software\Microsoft\Office\16.0\Common\InstallRoot';
  DET_REG_KEY_OFFICE16_ROOT_WOW = 'Software\Wow6432Node\Microsoft\Office\16.0\Common\InstallRoot';
  DET_REG_VAL_PATH = 'Path';
  DET_REG_KEY_HKCU_DESKTOP = 'Control Panel\Desktop';
  DET_REG_VAL_LOGPIXELS = 'LogPixels';
  DET_REG_KEY_HKCU_WINMETRICS = 'Control Panel\Desktop\WindowMetrics';
  DET_REG_VAL_APPLIEDDPI = 'AppliedDPI';

  { ===== Default constants (au3:45-46) ===== }
  DET_DEFAULT_LOGPIXELS = 96;

  { ===== Presence-probe path fragments (au3:93-102), relative to the
    script directory. Wildcard fragments are matched with FindFirst
    parity (the incumbent's FileExists accepts wildcards). }
  DET_PATH_REL_BUILDDATE = 'builddate.txt';
  DET_PATH_REL_HASHES = 'md';
  DET_PATH_REL_AUTOLOGON = 'bin\Autologon.exe';
  DET_PATH_REL_RCERTS = 'win\glb\*.crt';
  DET_PATH_REL_CPP = 'cpp\vcredist*.exe';
  DET_PATH_REL_INSTDOTNET48 = 'dotnet\ndp48-x86-x64-allos-*.exe';
  DET_PATH_REL_INSTDOTNET481 = 'dotnet\ndp481-x86-x64-allos-*.exe';
  DET_PATH_REL_EDGE = 'edge\MicrosoftEdgeEnterprise*.msi';
  DET_PATH_REL_MSEDGE_LEGACY = 'msedge\MicrosoftEdge_*.exe';
  DET_PATH_REL_WEBVIEW2 = 'edge\MicrosoftEdgeWebView2*.exe';

  { ===== WMF target (au3:509-511) - frozen by the incumbent ===== }
  DET_WMF_TARGET_VERSION = '5.1';

  { NET-toned gray for the Office info label (au3:841). }
  DET_OFFICE_LABEL_COLOR = $606060;

type
  { OS facts the pure gates need - built once from RtlGetVersion
    (au3 reads @OSVersion/@OSBuild/@OSArch; the product type replaces the
    au3 WIN_2016/WIN_2019/WIN_2022 server enumerations). }
  TOsInfo = record
    Major: Integer;
    Minor: Integer;
    Build: Integer;
    Workstation: Boolean; { VER_NT_WORKSTATION }
  end;

  { Result of one toggle gate: the checkbox Enabled/Checked pair exactly
    as the incumbent's GUICtrlSetState combination would produce it.
    Forced=True marks the checked-by-rule state (dotnet4 forced-checked /
    enablement enforced) - always paired with Enabled=False. }
  TGateState = record
    Enabled: Boolean;
    Checked: Boolean;
  end;

{ ---- OS gate helpers (RtlGetVersion is the reliable source on Vista+) ---- }
function DetectOsInfo: TOsInfo;
{ The au3 WIN_10/WIN_2016/WIN_2019/WIN_2022/WIN_11 membership used by the
  WMF and (legacy) autoreboot rules = every OS with major >= 10. }
function OsIsWin10OrNewer(const AOs: TOsInfo): Boolean;
{ 64-bit-capable OS probe for the WSH view selection - the au3
  @OSArch <> "X86". True on any x64 OS regardless of the process arch. }
function OsIs64Bit: Boolean;
{ The au3 @OSArch token ('x86'/'x64') - the OS architecture, not the
  process architecture; feeds the enablement predicates. }
function DetectOsArchToken: string;

{ ---- Registry probes (default view unless stated otherwise) ---- }
{ au3:349-365: HKLM via the 64-bit view (KEY_WOW64_64KEY, ignored on a
  32-bit OS), then HKCU default view; value "0" disables. }
{ au3-RegRead parity (26-04 Win7 x86 battery finding): AutoIt's RegRead
  returns ANY value type as its string spelling, while TRegistry.ReadString
  RAISES ERegistryException on a REG_DWORD-typed value. On 32-bit Windows
  the .NET v4 Full 'Release' key sits in the native (only) view as a DWORD,
  so the strict read killed the GUI there; the 64-bit dev host never saw it
  because the redirected 32-bit view lacks the key. RegValueToString is the
  tolerant reader every probe in this unit goes through (testrunner pin:
  DWORD -> decimal string, REG_SZ/EXPAND_SZ -> text, other types -> ''). }
function RegValueToString(const R: TRegistry; const AValue: string): string;
function DetectWSHAvailable: Boolean;
function DetectIEVersion: string;
function DetectDotNet35Version: string;
function DetectDotNet4Version: string;
function DetectDotNet4Release: string;
function DetectDotNet4MainVersion: string;
function DetectWMFMainVersion: string;
{ au3:126-135: env O2K16_VER_MAJOR, then the InstallRoot Path under the
  default view, then the Wow6432Node spelling. }
function DetectOffice16Detected: Boolean;

{ ---- Pure display maps (testrunner golden cases) ---- }
{ au3:399-458 - the verbatim release-to-display Switch table. }
function DetectDotNet4ReleaseToDisplay(const ARelease: string): string;
{ au3:464-499 - the verbatim per-OS target-release table; the au3
  WIN_2016/WIN_2019/WIN_2022 server enumerations become the product-type
  + build checks. Returns '0' for an unmapped OS (the au3 Case Else). }
function DetectDotNet4TargetRelease(const AOs: TOsInfo): string;

{ ---- Presence probes (base path = the script directory) ---- }
function DetectFileExistsWildcard(const APath: string): Boolean;
function DetectHashFilesPresent(const ABasePath: string): Boolean;
function DetectAutologonPresent(const ABasePath: string): Boolean;
function DetectRootCertificatesPresent(const ABasePath: string): Boolean;
function DetectCppPresent(const ABasePath: string): Boolean;
function DetectEdgePresent(const ABasePath: string): Boolean;
function DetectWebView2Present(const ABasePath: string): Boolean;
function DetectDotNet4InstPresent(const ABasePath: string;
  const ATargetDisplay: string): Boolean;
{ au3:280-288 - first line of builddate.txt, '' when absent. }
function DetectMediumBuildDate(const ABasePath: string): string;

{ ---- Office description (au3:137-155) ---- }
function DetectOffice16Description: string;

{ ---- Script directory + share mapping (au3:170-202) ---- }
{ The au3 DriveGetType(... ) = "Network" probe: UNC spelling or a drive
  backed by DRIVE_REMOTE. }
function DetectIsNetworkPath(const APath: string): Boolean;
{ Pure UNC scanner used by the share-root fallback (plan 261106-p8q):
  returns the \\server\share prefix in ARoot and the balance starting at
  the next backslash in ARemainder; False for anything without a
  non-empty server and share component. }
function DetectSplitUncPath(const APath: string;
  out ARoot, ARemainder: string): Boolean;
{ Pure free-drive-letter picker used by the explicit-letter map (plan
  261106-sgi): AExistingDrives is the concatenated 'X:\' strings exactly
  as GetLogicalDriveStringsW and the drive-snapshot loops build them.
  The scan runs from 'Z' downto 'C' - the WNetAddConnection2
  automatic-assignment convention (assignment begins with the last
  letter and ends with C). Returns the first letter whose three-char
  token is NOT present in the concatenation, formatted as 'L:'; the
  empty string when the whole C..Z range is taken. Matching is
  case-lenient. Provenance: the star auto device is rejected by
  WNetAddConnection2W with ERROR_BAD_DEVICE (1200) before any provider
  lookup (measured on the dev host and the Win7 SP1 VM, 2026-11-06);
  the au3 DriveMapAdd star call resolved client-side and this picker is
  that mechanism. }
function DetectPickFreeDriveLetter(const AExistingDrives: string): string;
{ Returns the usable script directory: a UNC path is mapped to a free
  drive letter - delimiter-stripped deep-path attempt first, then a
  share-root fallback (DetectSplitUncPath) returning device + remainder,
  the same shape as the reuse branch; the letter is chosen client-side
  by DetectPickFreeDriveLetter (plan 261106-sgi) and passed explicitly
  as the device to WNetAddConnection2W.
  An existing mapped-drive spelling is reused; lettered network paths
  and local paths pass through. AMapped=True marks a NEW mapping the
  caller must release with DetectReleaseScriptDirectory when the GUI
  closes. Returns '' on failure (the au3's error shape). }
function DetectAssignScriptDirectory(const AExeDir: string;
  out AMapped: Boolean): string;
procedure DetectReleaseScriptDirectory(const ADrive: string);

{ ---- WUStatusServer pre-launch write (au3:1205-1208) ---- }
procedure DetectWriteWUStatusServer(const AValue: string);

{ ---- PURE toggle gates (au3 665-942 verbatim) ---- }
{ Presence-gated toggles (rcerts/cpp/edge/webview2/office/verify):
  present -> checked per INI, absent -> unchecked + disabled (au3:700-708
  shape). AIniChecked = the MyIniRead state equals Enabled. }
function GatePresence(APresent, AIniChecked: Boolean): TGateState;
{ Always-offerable toggles (dotnet35/dotnet5/shutdown/auditonly). }
function GatePlainToggle(AIniChecked: Boolean): TGateState;

{ Enablement three-state, PRE-ineligible-override (au3:665-677) - the
  incumbent's conditions verbatim, including the Enforced<=1 tautology:
  Enforced() is 0/1 there, so the branch is Available(dir,0) and the
  forced branch can only fire for Enforced>1 (dead in the incumbent;
  ported unchanged - parity over "fixing"). }
function GateEnablement(AEnforcedValue: Integer;
  AAvailableNormal, AAvailableEnforcement, AIniChecked: Boolean): TGateState;

{ .NET 4 rule (au3:732-744): satisfied-or-no-installer -> off; old main
  version or 4.6/4.6.1 display -> FORCED checked + disabled; else per INI.
  ARelease/ATargetRelease are the numeric release strings (compared with
  the au3 Number() semantics = StrToIntDef 0). }
function GateDotNet4(const ARelease, ATargetRelease: string;
  AInstPresent: Boolean; const AMainVersion, ADisplayVersion: string;
  AIniChecked: Boolean): TGateState;

{ WMF rule (au3:753-763): modern OS, no .NET 4.x upgrade path with the
  dotnet4 box unchecked, or WMF already at target -> off; else per INI. }
function GateWmf(AOsModern: Boolean; const AMainVersion: string;
  ACurrentEqualsTarget, ADotNet4Checked, AIniChecked: Boolean): TGateState;

{ WMF re-evaluation on the dotnet4 click (au3:1113-1120): upgrade path
  present AND legacy OS AND WMF below target -> ENABLE (never checked
  here); otherwise uncheck + disable. Only Enabled is returned - the
  handler never re-reads the INI. }
function GateWmfReevaluate(AOsModern: Boolean; const AMainVersion: string;
  ACurrentEqualsTarget, ADotNet4Checked: Boolean): Boolean;

{ Automatic-reboot gating (au3:887-895) with the DESIGNED INST-05 change:
  Win10+ -> enabled (the RunOnce resume path exists there; no UAC-disable
  warning); <=8.1 -> enabled only with the legacy Autologon.exe present
  (legacy path: UAC-disable + network-share warnings apply); otherwise
  blocked. }
function GateAutoreboot(AOsModern, AAutologonPresent, AIniChecked: Boolean): TGateState;

{ Show-log coupling (au3:918-926): checked iff INI-enabled and shutdown
  unchecked; DISABLED while shutdown is checked. }
function GateShowlog(AIniChecked, AShutdownChecked: Boolean): TGateState;

implementation

const
  { Local Windows SDK constant (rtl's TOSVersionInfoExW is not exported
    by the FPC Windows unit). }
  DET_VER_NT_WORKSTATION = 1;

type
  { OSVERSIONINFOEXW layout for the product-type probe. }
  TDetOsVersionInfoExW = record
    dwOSVersionInfoSize: DWord;
    dwMajorVersion: DWord;
    dwMinorVersion: DWord;
    dwBuildNumber: DWord;
    dwPlatformId: DWord;
    szCSDVersion: array[0..127] of WideChar;
    wServicePackMajor: Word;
    wServicePackMinor: Word;
    wSuiteMask: Word;
    wProductType: Byte;
    wReserved: Byte;
  end;

{ RtlGetVersion: available since Windows 2000; this unit may run on the
  OS it gates. The Ex layout is a strict extension of TOSVersionInfoW. }
function RtlGetVersion(var AInfo: TOSVersionInfoW): LongInt; stdcall;
  external 'ntdll' name 'RtlGetVersion';
function RtlGetVersionEx(var AInfo: TDetOsVersionInfoExW): LongInt; stdcall;
  external 'ntdll' name 'RtlGetVersion';

function IsWow64ProcessCompat(out AWow64: LongBool): Boolean;
type
  TIsWow64Process = function(hProcess: THandle; var Wow64Process: LongBool): LongBool; stdcall;
var
  Fn: TIsWow64Process;
begin
  Result := False;
  Fn := TIsWow64Process(GetProcAddress(GetModuleHandle('kernel32'),
    'IsWow64Process'));
  if Assigned(Fn) then
    Result := Fn(GetCurrentProcess, AWow64);
end;

function OsIs64Bit: Boolean;
var
  Wow64: LongBool;
  Info: TOSVersionInfoW;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.dwOSVersionInfoSize := SizeOf(Info);
  { An unknown version fails closed to "assume modern 64-bit" only for the
    WSH VIEW choice - the view flag is ignored on 32-bit Windows anyway. }
  if RtlGetVersion(Info) <> 0 then
    Exit(True);
  if Info.dwMajorVersion >= 6 then
  begin
    if IsWow64ProcessCompat(Wow64) then
      Exit(Wow64 or (SizeOf(Pointer) = 8));
    { No IsWow64Process (pre-XP SP2): 64-bit editions did not exist. }
    Exit(False);
  end;
  { NT 5.x: 64-bit editions (XP Pro x64 / Server 2003 x64) are 6.0-ish
    edge cases the incumbent also treats via @OSArch; WOW64 probe covers
    them for the 32-bit process. }
  if IsWow64ProcessCompat(Wow64) then
    Exit(Wow64);
  Result := SizeOf(Pointer) = 8;
end;

function DetectOsInfo: TOsInfo;
var
  Info: TDetOsVersionInfoExW;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.dwOSVersionInfoSize := SizeOf(Info);
  FillChar(Result, SizeOf(Result), 0);
  if RtlGetVersionEx(Info) <> 0 then
    Exit;
  Result.Major := Info.dwMajorVersion;
  Result.Minor := Info.dwMinorVersion;
  Result.Build := Info.dwBuildNumber;
  Result.Workstation :=
    (Info.wProductType = DET_VER_NT_WORKSTATION);
end;

function DetectOsArchToken: string;
begin
  { The au3: (@OSArch = "X86" ? "x86" : "x64") - the OS architecture. }
  if OsIs64Bit then
    Exit('x64');
  Result := 'x86';
end;

function OsIsWin10OrNewer(const AOs: TOsInfo): Boolean;
begin
  Result := AOs.Major >= 10;
end;

function RegValueToString(const R: TRegistry; const AValue: string): string;
begin
  case R.GetDataType(AValue) of
    rdString, rdExpandString: Result := R.ReadString(AValue);
    rdInteger: Result := IntToStr(R.ReadInteger(AValue));
  else
    Result := '';
  end;
end;

function DetectWSHAvailable: Boolean;
var
  R: TRegistry;
begin
  { KEY_WOW64_64KEY on the HKLM probe = the au3 HKLM64 spelling; the flag
    is ignored by a 32-bit OS so the au3 @OSArch branch collapses into one
    open call (research Pattern: registry probe with explicit view). }
  Result := True;
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    R.Access := R.Access or KEY_WOW64_64KEY;
    if R.OpenKeyReadOnly(DET_REG_KEY_WSH_SETTINGS) then
    begin
      if R.ValueExists(DET_REG_VAL_ENABLED)
         and (RegValueToString(R, DET_REG_VAL_ENABLED) = '0') then
        Exit(False);
    end;
    R.CloseKey;
    R.Access := KEY_READ;
    R.RootKey := HKEY_CURRENT_USER;
    if R.OpenKeyReadOnly(DET_REG_KEY_WSH_SETTINGS) then
    begin
      if R.ValueExists(DET_REG_VAL_ENABLED)
         and (RegValueToString(R, DET_REG_VAL_ENABLED) = '0') then
        Exit(False);
    end;
  finally
    R.Free;
  end;
end;

function RegReadStringDef(const AKey, AValue: string): string;
var
  R: TRegistry;
begin
  Result := '';
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKeyReadOnly(AKey) and R.ValueExists(AValue) then
      Result := RegValueToString(R, AValue);
  finally
    R.Free;
  end;
end;

{ AutoIt StringLeft up to the FIRST '.' - '' safe. }
function LeftUpToFirstDot(const AValue: string): string;
var
  P: Integer;
begin
  P := Pos('.', AValue);
  if P = 0 then
    Result := AValue
  else
    Result := Copy(AValue, 1, P - 1);
end;

{ AutoIt StringLeft up to the LAST '.' - '' safe. }
function LeftUpToLastDot(const AValue: string): string;
var
  I: Integer;
begin
  I := Length(AValue);
  while (I > 0) and (AValue[I] <> '.') do
    Dec(I);
  if I = 0 then
    Result := AValue
  else
    Result := Copy(AValue, 1, I - 1);
end;

function DetectIEVersion: string;
var
  V: string;
begin
  V := RegReadStringDef(DET_REG_KEY_IE, DET_REG_VAL_VERSION);
  { au3:367-378 - the 9.10/9.11 marketing-version mapping. }
  if Pos('9.10.', V) > 0 then
    Exit('10');
  if Pos('9.11.', V) > 0 then
    Exit('11');
  Result := LeftUpToFirstDot(V);
end;

function DetectDotNet35Version: string;
begin
  Result := LeftUpToLastDot(
    RegReadStringDef(DET_REG_KEY_DOTNET35, DET_REG_VAL_VERSION));
end;

function DetectDotNet4Version: string;
begin
  Result := RegReadStringDef(DET_REG_KEY_DOTNET4, DET_REG_VAL_VERSION);
end;

function DetectDotNet4Release: string;
begin
  Result := RegReadStringDef(DET_REG_KEY_DOTNET4, DET_REG_VAL_RELEASE);
end;

function DetectDotNet4MainVersion: string;
begin
  { au3:460-462: StringLeft(version, 3) -> '4.0'/'4.5'/... }
  Result := Copy(DetectDotNet4Version, 1, 3);
end;

function DetectWMFMainVersion: string;
begin
  { au3:505-507: StringLeft(PowerShellVersion, 3). }
  Result := Copy(RegReadStringDef(DET_REG_KEY_WMF, DET_REG_VAL_PSHVERSION), 1, 3);
end;

function DetectOffice16Detected: Boolean;
var
  P: string;
begin
  if SysUtils.GetEnvironmentVariable('O2K16_VER_MAJOR') <> '' then
    Exit(True);
  P := RegReadStringDef(DET_REG_KEY_OFFICE16_ROOT, DET_REG_VAL_PATH);
  if P <> '' then
    Exit(True);
  P := RegReadStringDef(DET_REG_KEY_OFFICE16_ROOT_WOW, DET_REG_VAL_PATH);
  if P <> '' then
    Exit(True);
  Result := False;
end;

function DetectDotNet4ReleaseToDisplay(const ARelease: string): string;
begin
  { au3:399-458 verbatim. }
  if ARelease = '378389' then Exit('4.5');
  if ARelease = '378675' then Exit('4.5.1'); { Windows 8.1 / Server 2012 R2 }
  if ARelease = '378758' then Exit('4.5.1');
  if ARelease = '379893' then Exit('4.5.2');
  if ARelease = '393295' then Exit('4.6');   { Windows 10 1507 (10240) }
  if ARelease = '393297' then Exit('4.6');
  if ARelease = '394254' then Exit('4.6.1'); { Windows 10 1511 (10586) }
  if ARelease = '394271' then Exit('4.6.1');
  if ARelease = '394802' then Exit('4.6.2'); { Windows 10 1607 / Server 2016 }
  if ARelease = '394806' then Exit('4.6.2');
  if ARelease = '460798' then Exit('4.7');   { Windows 10 1703 (15063) }
  if ARelease = '460805' then Exit('4.7');
  if ARelease = '461308' then Exit('4.7.1'); { Windows 10 1709 (16299) }
  if ARelease = '461310' then Exit('4.7.1');
  if ARelease = '461808' then Exit('4.7.2'); { Windows 10 1803 (17134) }
  if ARelease = '461814' then Exit('4.7.2');
  if ARelease = '528040' then Exit('4.8');   { Windows 10 1903/1909 (18362) }
  if ARelease = '528049' then Exit('4.8');
  if ARelease = '528372' then Exit('4.8');   { Windows 10 2004/20H2/21H1/21H2 }
  if ARelease = '528449' then Exit('4.8');   { Server 2022 / Windows 11 22000 }
  if ARelease = '533320' then Exit('4.8.1'); { Windows 11 (22621) }
  if ARelease = '533325' then Exit('4.8.1');
  Result := '';
end;

function DetectDotNet4TargetRelease(const AOs: TOsInfo): string;
begin
  { au3:464-499 verbatim; the au3 @OSVersion enumeration becomes
    workstation/server + build checks. WIN_2016 = Server build 14393,
    WIN_2019 = Server build 17763, WIN_2022 = Server build 20348;
    WIN_11 = client build >= 22000. }
  if AOs.Major < 10 then
    Exit('0');
  if AOs.Workstation then
  begin
    if AOs.Build >= 22000 then
    begin
      { WIN_11 branch }
      if AOs.Build = 22000 then
        Exit('533325');
      Exit('533320');
    end;
    { WIN_10 branch }
    if AOs.Build < 19041 then
    begin
      if AOs.Build = 10240 then Exit('394806');
      if AOs.Build = 14393 then Exit('528049');
      if (AOs.Build = 18362) or (AOs.Build = 18363) then Exit('528040');
      Exit('528049');
    end;
    Exit('533325');
  end
  else
  begin
    { Server SKUs }
    if AOs.Build = 14393 then Exit('528049'); { WIN_2016 }
    if AOs.Build = 17763 then Exit('528049'); { WIN_2019 }
    if AOs.Build = 20348 then Exit('533325'); { WIN_2022 }
    Exit('0');
  end;
end;

function DetectFileExistsWildcard(const APath: string): Boolean;
var
  SearchRec: TSearchRec;
begin
  { The incumbent's FileExists accepts wildcards; FindFirst is the
    parity primitive (wave-1 CppPresent shape). }
  Result := SysUtils.FindFirst(APath, faAnyFile, SearchRec) = 0;
  if Result then
    SysUtils.FindClose(SearchRec);
end;

function DetectHashFilesPresent(const ABasePath: string): Boolean;
begin
  Result := DirectoryExists(IncludeTrailingPathDelimiter(ABasePath)
    + DET_PATH_REL_HASHES);
end;

function DetectAutologonPresent(const ABasePath: string): Boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(ABasePath)
    + DET_PATH_REL_AUTOLOGON);
end;

function DetectRootCertificatesPresent(const ABasePath: string): Boolean;
begin
  Result := DetectFileExistsWildcard(
    IncludeTrailingPathDelimiter(ABasePath) + DET_PATH_REL_RCERTS);
end;

function DetectCppPresent(const ABasePath: string): Boolean;
begin
  Result := DetectFileExistsWildcard(
    IncludeTrailingPathDelimiter(ABasePath) + DET_PATH_REL_CPP);
end;

function DetectEdgePresent(const ABasePath: string): Boolean;
begin
  { au3:529-531: the Edge MSI or the legacy msedge stub. }
  Result := DetectFileExistsWildcard(
    IncludeTrailingPathDelimiter(ABasePath) + DET_PATH_REL_EDGE)
    or DetectFileExistsWildcard(
    IncludeTrailingPathDelimiter(ABasePath) + DET_PATH_REL_MSEDGE_LEGACY);
end;

function DetectWebView2Present(const ABasePath: string): Boolean;
begin
  Result := DetectFileExistsWildcard(
    IncludeTrailingPathDelimiter(ABasePath) + DET_PATH_REL_WEBVIEW2);
end;

function DetectDotNet4InstPresent(const ABasePath: string;
  const ATargetDisplay: string): Boolean;
var
  Rel: string;
begin
  { au3:537-546 verbatim, incl. the incumbent's "not optimal, but
    working" fallback to the 4.8 payload. }
  if ATargetDisplay = '4.8.1' then
    Rel := DET_PATH_REL_INSTDOTNET481
  else
    Rel := DET_PATH_REL_INSTDOTNET48;
  Result := DetectFileExistsWildcard(
    IncludeTrailingPathDelimiter(ABasePath) + Rel);
end;

function DetectMediumBuildDate(const ABasePath: string): string;
var
  Sl: TStringList;
begin
  Result := '';
  Sl := TStringList.Create;
  try
    try
      Sl.LoadFromFile(IncludeTrailingPathDelimiter(ABasePath)
        + DET_PATH_REL_BUILDDATE);
      if Sl.Count > 0 then
        Result := Trim(Sl.Strings[0]);
    except
      { Missing/unreadable file = the au3 FileReadLine error path (''). }
      on E: Exception do
        Result := '';
    end;
  finally
    Sl.Free;
  end;
end;

function DetectOffice16Description: string;
var
  Name, Arch: string;
begin
  Name := SysUtils.GetEnvironmentVariable('O2K16_PRODUCT_NAME');
  Arch := SysUtils.GetEnvironmentVariable('O2K16_ARCH');
  if Name <> '' then
  begin
    if Arch <> '' then
      Exit(Name + ' (' + Arch + ')');
    Exit(Name);
  end;
  if DetectOffice16Detected then
    Exit('Microsoft Office 2016+');
  Result := StringsGet(siOfficeNone);
end;

{ ---- Share mapping (au3:170-202) ---- }

type
  PDetNetResourceW = ^TDetNetResourceW;
  TDetNetResourceW = record
    dwScope: DWord;
    dwType: DWord;
    dwDisplayType: DWord;
    dwUsage: DWord;
    lpLocalName: PWideChar;
    lpRemoteName: PWideChar;
    lpComment: PWideChar;
    lpProvider: PWideChar;
  end;

const
  DET_RESOURCETYPE_DISK = 1; { RESOURCETYPE_DISK }

function WNetAddConnection2W(ANetResource: PDetNetResourceW;
  APassword, AUser: PWideChar; AFlags: DWord): DWord; stdcall;
  external 'mpr' name 'WNetAddConnection2W';
function WNetCancelConnection2W(AName: PWideChar; AFlags: DWord;
  AForce: LongBool): DWord; stdcall; external 'mpr' name 'WNetCancelConnection2W';
function WNetGetConnectionW(ALocalName: PWideChar; ARemote: PWideChar;
  var ALength: DWord): DWord; stdcall; external 'mpr' name 'WNetGetConnectionW';

{ The au3 DriveGetType(... ) = "Network" probe: UNC spelling or a drive
  backed by DRIVE_REMOTE. }
function DetectIsNetworkPath(const APath: string): Boolean;
var
  DrivePart: string;
begin
  if Pos('\\', APath) > 0 then
    Exit(True);
  if (Length(APath) >= 2) and (APath[2] = ':') then
  begin
    DrivePart := Copy(APath, 1, 2) + '\';
    Result := GetDriveType(PChar(DrivePart)) = DRIVE_REMOTE;
    Exit;
  end;
  Result := False;
end;

{ Plan 261106-p8q: \\server\share scanner - the share root goes to
  ARoot, the balance from the next backslash to ARemainder. False for
  anything without a non-empty server AND share component (server-only,
  trailing-delimiter-only, non-UNC). }
function DetectSplitUncPath(const APath: string;
  out ARoot, ARemainder: string): Boolean;
var
  ServerStart: Integer;
  ServerEnd: Integer;
  ShareEnd: Integer;
begin
  ARoot := '';
  ARemainder := '';
  Result := False;
  { (a) anything whose first two chars are not the UNC prefix is out. }
  if (Length(APath) < 2) or (Copy(APath, 1, 2) <> '\\') then
    Exit;
  { (b) first backslash after the prefix ends the server; none means
    server-only. }
  ServerStart := 3;
  ServerEnd := ServerStart;
  while (ServerEnd <= Length(APath)) and (APath[ServerEnd] <> '\') do
    Inc(ServerEnd);
  if ServerEnd > Length(APath) then
    Exit;
  { (c) empty server is not a usable UNC. }
  if ServerEnd = ServerStart then
    Exit;
  { (d) the share runs to the next backslash (or to the end). }
  ShareEnd := ServerEnd + 1;
  while (ShareEnd <= Length(APath)) and (APath[ShareEnd] <> '\') do
    Inc(ShareEnd);
  if ShareEnd = ServerEnd + 1 then
    Exit; { empty share component }
  if ShareEnd > Length(APath) then
  begin
    { Two-component UNC: the root is the whole input. }
    ARoot := APath;
    Result := True;
    Exit;
  end;
  { (e) root = everything before the backslash, remainder = from it
    (leading backslash and trailing delimiter preserved). }
  ARoot := Copy(APath, 1, ShareEnd - 1);
  ARemainder := Copy(APath, ShareEnd, MaxInt);
  Result := True;
end;

{ Plan 261106-sgi free-letter picker: case-lenient Z-downto-C scan over
  the normalized snapshot; the interface comment carries the contract. }
function DetectPickFreeDriveLetter(const AExistingDrives: string): string;
var
  C: Char;
  Drives: string;
  Token: string;
begin
  Drives := UpperCase(AExistingDrives);
  for C := 'Z' downto 'C' do
  begin
    Token := C + ':\';
    if Pos(Token, Drives) = 0 then
      Exit(C + ':');
  end;
  Result := '';
end;

{ Plan 261106-sgi replaces the star-device helper: the star was
  rejected with ERROR_BAD_DEVICE (1200) before any provider lookup
  (measured on the dev host and the Win7 SP1 VM, 2026-11-06), so the
  letter is chosen client-side by DetectPickFreeDriveLetter and passed
  explicitly as lpLocalName. Letter exhaustion fails closed (no
  mapping attempted); a failed add returns False with nothing to
  release - the device is known by construction, so no mapping exists
  unless the add succeeded. The remote name is the UNC path itself -
  no user-derived content. }
function MapRemote(const ARemote: string; out ADevice: string): Boolean;
var
  DrivesBuf: array[0..511] of WideChar;
  DLen: Integer;
  I: Integer;
  DriveLetter: WideString;
  K: Integer;
  Letter: string;
  LetterWide: WideString;
  Nr: TDetNetResourceW;
  RemoteWide: WideString;
  Snapshot: WideString;
  Res: DWord;
begin
  ADevice := '';
  Result := False;

  { Fresh drive snapshot for the free-letter picker. }
  FillChar(DrivesBuf, SizeOf(DrivesBuf), 0);
  DLen := GetLogicalDriveStringsW(Length(DrivesBuf) - 1, @DrivesBuf[0]);
  Snapshot := '';
  I := 0;
  while (DLen > 0) and (I + 3 < DLen) do
  begin
    DriveLetter := PWideChar(@DrivesBuf[I]); { 'X:\' }
    Snapshot := Snapshot + DriveLetter;
    Inc(I, 4);
  end;

  Letter := DetectPickFreeDriveLetter(string(Snapshot));
  if Letter = '' then
    Exit; { C..Z exhausted: fail closed, no mapping attempted. }

  { Materialize the letter as a WideChar buffer element-wise - no
    implicit AnsiString-to-WideString string conversion on this path. }
  SetLength(LetterWide, Length(Letter));
  for K := 1 to Length(Letter) do
    LetterWide[K] := Letter[K];

  { The remote name is the UNC path itself - no user-derived content. }
  FillChar(Nr, SizeOf(Nr), 0);
  Nr.dwType := DET_RESOURCETYPE_DISK;
  RemoteWide := ARemote;
  Nr.lpRemoteName := PWideChar(RemoteWide);
  Nr.lpLocalName := PWideChar(LetterWide);
  Res := WNetAddConnection2W(@Nr, nil, nil, 0);
  if Res <> NO_ERROR then
    Exit;

  ADevice := Letter;
  Result := True;
end;

function DetectAssignScriptDirectory(const AExeDir: string;
  out AMapped: Boolean): string;
var
  DrivesBuf: array[0..511] of WideChar;
  DLen: Integer;
  I: Integer;
  DriveLetter: WideString;
  Remote: WideString;
  RemoteLen: DWord;
  Res: DWord;
  Dev: string;
  Root: string;
  Rest: string;
begin
  AMapped := False;
  Result := AExeDir;
  if not DetectIsNetworkPath(AExeDir) then
    Exit;

  { Lettered network drive (no UNC inside): the au3 accepts it as-is. }
  if Pos('\\', AExeDir) = 0 then
    Exit;

  { UNC: try to reuse an existing mapped drive whose remote name appears
    inside the path (au3:180-188, case-insensitive per StringInStr). }
  FillChar(DrivesBuf, SizeOf(DrivesBuf), 0);
  DLen := GetLogicalDriveStringsW(Length(DrivesBuf) - 1, @DrivesBuf[0]);
  I := 0;
  while (DLen > 0) and (I + 3 < DLen) do
  begin
    DriveLetter := PWideChar(@DrivesBuf[I]); { 'X:\' }
    if Length(DriveLetter) = 3 then
    begin
      RemoteLen := 0;
      Res := WNetGetConnectionW(PWideChar(Copy(DriveLetter, 1, 2)),
        nil, RemoteLen);
      if (Res = ERROR_MORE_DATA) and (RemoteLen > 0) then
      begin
        SetLength(Remote, RemoteLen);
        if WNetGetConnectionW(PWideChar(Copy(DriveLetter, 1, 2)),
            PWideChar(Remote), RemoteLen) = NO_ERROR then
        begin
          SetLength(Remote, StrLen(PWideChar(Remote)));
          if (Remote <> '')
             and (Pos(UpperCase(string(Remote)), UpperCase(AExeDir)) > 0) then
            Exit(Copy(string(DriveLetter), 1, 2)
              + Copy(AExeDir, Length(Remote) + 1, MaxInt));
        end;
      end;
    end;
    Inc(I, 4);
  end;

  { No reuse: map a fresh drive with an explicitly chosen letter.
    DELIBERATE deviation from au3:190-196 (incumbent commit 0a4358b,
    DriveMapAdd("*", @ScriptDir)), documented per plans 261106-p8q and
    261106-sgi: the au3 star call resolved the auto device client-side,
    but the direct API rejects the star with ERROR_BAD_DEVICE (1200)
    before any provider lookup (measured on the dev host and the Win7
    SP1 VM, 2026-11-06) - the MSDN lpLocalName contract admits only a
    lettered device, an LPT device, or NULL/empty, so this port picks
    the letter client-side (DetectPickFreeDriveLetter, Z downto C) and
    passes it explicitly as the device. The incumbent's deep-path
    limitation stands: providers like VMware HGFS reject deep
    spellings (measured 1202), so this port first maps the
    delimiter-stripped deep path (the au3 @ScriptDir carried no
    trailing backslash) and falls back to the share root, returning
    device + remainder in the reuse branch's shape. The remote name is
    the UNC path itself - no user-derived content. }
  if MapRemote(ExcludeTrailingPathDelimiter(AExeDir), Dev) then
  begin
    AMapped := True;
    Exit(Dev);
  end;

  { Deep spelling unmappable: the share-root fallback. Not a splittable
    UNC (or the root is unmappable too) -> the au3 error shape: ''. }
  if not DetectSplitUncPath(AExeDir, Root, Rest) then
    Exit('');
  if MapRemote(Root, Dev) then
  begin
    AMapped := True;
    Exit(Dev + Rest);
  end;
  Result := '';
end;

procedure DetectReleaseScriptDirectory(const ADrive: string);
var
  DriveWide: WideString;
begin
  if ADrive = '' then
    Exit;
  DriveWide := ADrive;
  WNetCancelConnection2W(PWideChar(DriveWide), 0, True);
end;

procedure DetectWriteWUStatusServer(const AValue: string);
var
  R: TRegistry;
begin
  if AValue = '' then
    Exit;
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKey(ENG_REG_KEY_WINDOWSUPDATE, True) then
      R.WriteString(ENG_REG_VAL_WUSTATUSSERVER, AValue);
  finally
    R.Free;
  end;
end;

{ ---- Pure gates ---- }

function GatePresence(APresent, AIniChecked: Boolean): TGateState;
begin
  if APresent then
  begin
    Result.Enabled := True;
    Result.Checked := AIniChecked;
  end
  else
  begin
    Result.Enabled := False;
    Result.Checked := False;
  end;
end;

function GatePlainToggle(AIniChecked: Boolean): TGateState;
begin
  Result.Enabled := True;
  Result.Checked := AIniChecked;
end;

function GateEnablement(AEnforcedValue: Integer;
  AAvailableNormal, AAvailableEnforcement, AIniChecked: Boolean): TGateState;
begin
  { au3:665-677 verbatim (see the interface comment on the Enforced<=1
    tautology). }
  if (AEnforcedValue <= 1) and AAvailableNormal then
  begin
    Result.Enabled := True;
    Result.Checked := AIniChecked;
  end
  else if (AEnforcedValue > 1) and AAvailableEnforcement then
  begin
    Result.Enabled := False;
    Result.Checked := True;
  end
  else
  begin
    Result.Enabled := False;
    Result.Checked := False;
  end;
end;

function AuNumber(const AValue: string): Integer;
begin
  { The au3 Number() semantics for the release comparisons: a non-numeric
    or empty value is 0. }
  Result := StrToIntDef(Trim(AValue), 0);
end;

function GateDotNet4(const ARelease, ATargetRelease: string;
  AInstPresent: Boolean; const AMainVersion, ADisplayVersion: string;
  AIniChecked: Boolean): TGateState;
begin
  { au3:732-744 verbatim. }
  if (AuNumber(ARelease) >= AuNumber(ATargetRelease))
     or (not AInstPresent) then
  begin
    Result.Enabled := False;
    Result.Checked := False;
  end
  else if (AMainVersion = '4.0') or (AMainVersion = '4.5')
          or (ADisplayVersion = '4.6') or (ADisplayVersion = '4.6.1') then
  begin
    Result.Enabled := False;
    Result.Checked := True;
  end
  else
  begin
    Result.Enabled := True;
    Result.Checked := AIniChecked;
  end;
end;

function DotNet4UpgradePathPresent(const AMainVersion: string): Boolean;
begin
  { au3:754 / 1114: the .NET main versions whose update machinery can
    pull the WMF prerequisite. }
  Result := (AMainVersion = '4.5') or (AMainVersion = '4.6')
    or (AMainVersion = '4.7') or (AMainVersion = '4.8');
end;

function GateWmf(AOsModern: Boolean; const AMainVersion: string;
  ACurrentEqualsTarget, ADotNet4Checked, AIniChecked: Boolean): TGateState;
begin
  { au3:753-763 verbatim: modern OS, missing .NET path with the dotnet4
    box unchecked, or WMF already at target -> unchecked + disabled. }
  if AOsModern
     or ((not DotNet4UpgradePathPresent(AMainVersion)) and (not ADotNet4Checked))
     or ACurrentEqualsTarget then
  begin
    Result.Enabled := False;
    Result.Checked := False;
  end
  else
  begin
    Result.Enabled := True;
    Result.Checked := AIniChecked;
  end;
end;

function GateWmfReevaluate(AOsModern: Boolean; const AMainVersion: string;
  ACurrentEqualsTarget, ADotNet4Checked: Boolean): Boolean;
begin
  { au3:1113-1120 verbatim. }
  Result := ((ADotNet4Checked) or DotNet4UpgradePathPresent(AMainVersion))
    and (not AOsModern)
    and (not ACurrentEqualsTarget);
end;

function GateAutoreboot(AOsModern, AAutologonPresent, AIniChecked: Boolean): TGateState;
begin
  { au3:887-895 with the DESIGNED INST-05 change: the au3 disabled the
    box on Win10+ because only the legacy autologon recall existed; the
    RunOnce resume path re-enables Win10+ here. Legacy (<=8.1) stays
    AutologonPresent-gated. }
  if AOsModern then
  begin
    Result.Enabled := True;
    Result.Checked := AIniChecked;
  end
  else if AAutologonPresent then
  begin
    Result.Enabled := True;
    Result.Checked := AIniChecked;
  end
  else
  begin
    Result.Enabled := False;
    Result.Checked := False;
  end;
end;

function GateShowlog(AIniChecked, AShutdownChecked: Boolean): TGateState;
begin
  { au3:918-926 verbatim. }
  Result.Enabled := not AShutdownChecked;
  Result.Checked := AIniChecked and (not AShutdownChecked);
end;

end.
