{*** Frozen engine contract table for the native installer GUI (FPC/LCL).

    Single source for every byte this GUI emits toward the client/cmd engine:
    - the 24 argv switches, verbatim from client/cmd/DoUpdate.cmd line 92
    - the INI sections/keys/defaults, verbatim from client/UpdateInstaller.ini
    - the two distinct Temp conventions (caller %TEMP% vs %SystemRoot%\Temp)
    - the engine exit-code handshake (0 / 1 / 3010 / 3011)
    - the absolute cmd.exe resolution (SysNative on 32-bit-on-x64, %ComSpec% else)
    - the incumbent PathValid rule (au3:262-278) and the window caption builder

    Nothing here may change without the matching engine-side contract
    (contract freeze, milestone v2.0 phase 05). The GUI changes technology,
    not contract bytes. }

unit enginecontracts;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows;

const
  { ===== Frozen argv switch table (client/cmd/DoUpdate.cmd:92) =====
    Order and spelling verbatim; the GUI never emits a token that is not
    in this table. }
  ENG_SWITCH_COUNT = 24;
  ENG_SWITCH_TOKENS: array[1..ENG_SWITCH_COUNT] of string = (
    '/upgradebuilds', '/updatercerts', '/instdotnet35', '/instdotnet4',
    '/instwmf', '/updatedotnet5', '/updatecpp', '/skipieinst',
    '/skipdefs', '/skipdynamic', '/all', '/excludestatics',
    '/seconly', '/verify', '/autoreboot', '/shutdown',
    '/showlog', '/showdismprogress', '/monitoron', '/instmsi',
    '/auditonly', '/instedge', '/instwebview2', '/updateoffice');

  { ===== INI sections (client/UpdateInstaller.ini template) ===== }
  ENG_INI_SECTION_INSTALLATION = 'Installation';
  ENG_INI_SECTION_CONTROL = 'Control';
  ENG_INI_SECTION_MESSAGING = 'Messaging';
  ENG_INI_SECTION_MISCELLANEOUS = 'Miscellaneous';
  ENG_INI_SECTION_MSI = 'MSI';

  { Section-value vocabulary: state settings use lowercase key names with
    the Enabled/Disabled values only - unknown values fall back to the
    template default instead of being forwarded (threat T-26-03). }
  ENG_INI_ENABLED = 'Enabled';
  ENG_INI_DISABLED = 'Disabled';

  { Every key and default from the client/UpdateInstaller.ini template:
    Installation 15, Control 4, Messaging 4, Miscellaneous 1 (MSI: none). }
  ENG_INI_DEFAULT_COUNT = 24;
  ENG_INI_DEFAULTS: array[1..ENG_INI_DEFAULT_COUNT, 1..3] of string = (
    (ENG_INI_SECTION_INSTALLATION, 'upgradebuilds',    ENG_INI_ENABLED),
    (ENG_INI_SECTION_INSTALLATION, 'updatercerts',     ENG_INI_ENABLED),
    (ENG_INI_SECTION_INSTALLATION, 'instdotnet35',     ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'instdotnet4',      ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'instwmf',          ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'updatedotnet5',    ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'updatecpp',        ENG_INI_ENABLED),
    (ENG_INI_SECTION_INSTALLATION, 'instedge',         ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'instwebview2',     ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'skipieinst',       ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'skipdefs',         ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'skipdynamic',      ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'all',              ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'excludestatics',   ENG_INI_DISABLED),
    (ENG_INI_SECTION_INSTALLATION, 'seconly',          ENG_INI_DISABLED),
    (ENG_INI_SECTION_CONTROL,      'verify',           ENG_INI_ENABLED),
    (ENG_INI_SECTION_CONTROL,      'autoreboot',       ENG_INI_DISABLED),
    (ENG_INI_SECTION_CONTROL,      'shutdown',         ENG_INI_DISABLED),
    (ENG_INI_SECTION_CONTROL,      'auditonly',        ENG_INI_DISABLED),
    (ENG_INI_SECTION_MESSAGING,    'showlog',          ENG_INI_DISABLED),
    (ENG_INI_SECTION_MESSAGING,    'showieinfo',       ENG_INI_ENABLED),
    (ENG_INI_SECTION_MESSAGING,    'showdotnet4info',  ENG_INI_ENABLED),
    (ENG_INI_SECTION_MESSAGING,    'showdismprogress', ENG_INI_DISABLED),
    (ENG_INI_SECTION_MISCELLANEOUS,'monitoron',        ENG_INI_DISABLED));

  { ===== Engine exit-code handshake (DoUpdate.cmd / InstallListedUpdates.cmd) ===== }
  ENG_EXIT_OK = 0;
  ENG_EXIT_ERROR = 1;
  ENG_EXIT_REBOOT_REQUIRED = 3010;
  ENG_EXIT_RECALL = 3011;

  { ===== File-name constants of the frozen runtime state ===== }
  { The GUI <-> GUI state INI and the engine's delete target
    (DoUpdate.cmd:2355) share this literal name - it is NOT derived from
    the exe name. }
  ENG_TEMP_INI_NAME = 'UpdateInstaller.ini';
  { MSI listing lands in the caller %TEMP%; the selection file lives in
    %SystemRoot%\Temp where the engine reads it (au3:121,1282;
    DoUpdate.cmd:1701) - research Pitfall F. }
  ENG_MSI_LISTING_NAME = 'wouallmsi.txt';
  ENG_MSI_SELECTION_NAME = 'wouselmsi.txt';

  { ===== Incumbent PathValid rule (au3:92-93, 262-278) ===== }
  ENG_PATH_MAX_LENGTH = 192;
  ENG_PATH_INVALID_CHARS = '!%&()^+,;=';

  { ===== Window caption shape (au3:20) ===== }
  ENG_CAPTION_BASE = 'WSUS Offline Next';

{ Resolve an argv token by its bare name; returns '' for anything that is
  not in the frozen table - the only legal source for command-line tokens
  (threat T-26-01: argv is never interpolated from INI text). }
function EngSwitchToken(const AName: string): string;

{ Template default for a frozen INI key; unknown section/key pairs map to
  Disabled rather than being forwarded (threat T-26-03). }
function EngIniDefault(const ASection, AKey: string): string;

{ Caller %TEMP% - the GUI's listing/INI-copy/audit-artifact side. }
function EngCallerTempDir: string;

{ %SystemRoot%\Temp - engine staging area (wouselmsi selection,
  SetWOUpdateStage.cmd, WOUpdatesToInstall.txt). }
function EngEngineTempDir: string;

{ Absolute cmd.exe path (threat T-26-02, research Pitfall E rec b):
  a 32-bit process on 64-bit Windows prefers %SystemRoot%\SysNative\cmd.exe
  so the engine and its children see the native system32; every other
  process uses %ComSpec%, expanded against %SystemRoot%\System32 when a
  bare name slips in. Never a bare PATH spawn. Returns '' when no absolute
  path can be derived - callers must fail closed. }
function EngCmdExePath: string;

{ The running exe's own VERSIONINFO ProductVersion ('' when the resource is
  absent - true until plan 03 lands the .lpi VersionInfo). }
function EngOwnProductVersion: string;

{ Incumbent caption shape: 'WSUS Offline Next - <ProductVersion> - Installer'
  or the versionless constant when no VERSIONINFO exists yet - never a
  second hardcoded version literal. }
function EngWindowCaption: string;

function EngPathValid(const APath: string): Boolean;

{ Startup OS gate port (au3:998-1005): False for the incumbent blocked set
  XP/2003/Vista/2008/7/2008R2/8.0, i.e. every version below 6.3. }
function EngOsVersionSupported: Boolean;

{ Human-readable OS version for the gate error box. }
function EngOsVersionDisplay: string;

{ Byte copy used by the INI-copy contract (au3 IniCopy parity); callers
  clear the read-only bit on the destination afterwards. }
procedure EngCopyFileRaw(const ASrc, ADest: string);

implementation

function EngSwitchToken(const AName: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := Low(ENG_SWITCH_TOKENS) to High(ENG_SWITCH_TOKENS) do
    if SameText(ENG_SWITCH_TOKENS[I], '/' + AName) then
      Exit(ENG_SWITCH_TOKENS[I]);
end;

function EngIniDefault(const ASection, AKey: string): string;
var
  I: Integer;
begin
  Result := ENG_INI_DISABLED;
  for I := 1 to ENG_INI_DEFAULT_COUNT do
    if SameText(ENG_INI_DEFAULTS[I, 1], ASection)
       and SameText(ENG_INI_DEFAULTS[I, 2], AKey) then
      Exit(ENG_INI_DEFAULTS[I, 3]);
end;

function EngCallerTempDir: string;
begin
  Result := SysUtils.GetEnvironmentVariable('TEMP');
  if Result = '' then
    Result := SysUtils.GetEnvironmentVariable('TMP');
end;

function EngEngineTempDir: string;
begin
  Result := SysUtils.GetEnvironmentVariable('SystemRoot');
  if Result = '' then
    Result := SysUtils.GetEnvironmentVariable('windir');
  if Result <> '' then
    Result := Result + '\Temp';
end;

function EngCmdExePath: string;
var
  SysRoot: string;
  ComSpec: string;
begin
  Result := '';
  SysRoot := SysUtils.GetEnvironmentVariable('SystemRoot');
  if SysRoot = '' then
    SysRoot := SysUtils.GetEnvironmentVariable('windir');
  ComSpec := SysUtils.GetEnvironmentVariable('ComSpec');
  {$IFDEF WIN32}
  { 32-bit process on 64-bit Windows: SysNative is the supported escape
    hatch - the engine's wusa/dism children must see the native system32. }
  if (SysRoot <> '') and DirectoryExists(SysRoot + '\SysNative') then
    Exit(SysRoot + '\SysNative\cmd.exe');
  {$ENDIF WIN32}
  if ComSpec = '' then
  begin
    if SysRoot = '' then
      Exit;
    ComSpec := 'cmd.exe';
  end;
  { Guard the contract's absolute-path rule: %ComSpec% is absolute on every
    real install, but a bare name must never reach a PATH spawn. }
  if (Pos('\', ComSpec) = 0) and (Pos('/', ComSpec) = 0) and (SysRoot <> '') then
    ComSpec := SysRoot + '\System32\' + ComSpec;
  Result := ComSpec;
end;

function EngOwnProductVersion: string;
type
  TWordPair = record
    Lang: Word;
    CodePage: Word;
  end;
  PWordPair = ^TWordPair;
var
  Handle: DWORD;
  Size: DWORD;
  Data: Pointer;
  Trans: Pointer;
  TransLen: UINT;
  BufPtr: Pointer;
  ValLen: UINT;
  SubKey: string;
begin
  Result := '';
  Size := GetFileVersionInfoSize(PChar(ParamStr(0)), Handle);
  if Size = 0 then
    Exit;
  GetMem(Data, Size);
  try
    if not GetFileVersionInfo(PChar(ParamStr(0)), Handle, Size, Data) then
      Exit;
    if not VerQueryValue(Data, '\VarFileInfo\Translation', Trans, TransLen) then
      Exit;
    if (Trans = nil) or (TransLen < SizeOf(TWordPair)) then
      Exit;
    SubKey := Format('StringFileInfo\%.4x%.4x\ProductVersion',
      [PWordPair(Trans)^.Lang, PWordPair(Trans)^.CodePage]);
    BufPtr := nil;
    ValLen := 0;
    if VerQueryValue(Data, PChar(SubKey), BufPtr, ValLen) and (BufPtr <> nil) then
      Result := PChar(BufPtr);
  finally
    FreeMem(Data);
  end;
end;

function EngWindowCaption: string;
var
  PV: string;
begin
  PV := EngOwnProductVersion;
  if PV <> '' then
    Result := ENG_CAPTION_BASE + ' - ' + PV + ' - Installer'
  else
    Result := ENG_CAPTION_BASE + ' - Installer';
end;

function EngPathValid(const APath: string): Boolean;
var
  I: Integer;
begin
  if Length(APath) > ENG_PATH_MAX_LENGTH then
    Exit(False);
  for I := 1 to Length(ENG_PATH_INVALID_CHARS) do
    if Pos(ENG_PATH_INVALID_CHARS[I], APath) > 0 then
      Exit(False);
  Result := True;
end;

{ RtlGetVersion is the only reliable version source on Vista+ (GetVersionEx
  lies once a manifest declares supportedOS; this tracer has no manifest
  until plan 03). Available since Windows 2000, so the gate itself can run
  on the OS it blocks. }
function RtlGetVersion(var AInfo: TOSVersionInfoW): LongInt; stdcall;
  external 'ntdll' name 'RtlGetVersion';

function EngOsVersionSupported: Boolean;
var
  Info: TOSVersionInfoW;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.dwOSVersionInfoSize := SizeOf(Info);
  if RtlGetVersion(Info) <> 0 then
  begin
    { No reliable version - fail closed like the incumbent would on an
      unknown @OSVersion. }
    Exit(False);
  end;
  Result := (Info.dwMajorVersion > 6)
    or ((Info.dwMajorVersion = 6) and (Info.dwMinorVersion >= 3));
end;

function EngOsVersionDisplay: string;
var
  Info: TOSVersionInfoW;
begin
  FillChar(Info, SizeOf(Info), 0);
  Info.dwOSVersionInfoSize := SizeOf(Info);
  if RtlGetVersion(Info) <> 0 then
    Exit('unknown');
  Result := Format('%d.%d (build %d)',
    [Info.dwMajorVersion, Info.dwMinorVersion, Info.dwBuildNumber]);
end;

procedure EngCopyFileRaw(const ASrc, ADest: string);
var
  Src: TFileStream;
  Dest: TFileStream;
begin
  Src := TFileStream.Create(ASrc, fmOpenRead or fmShareDenyWrite);
  try
    Dest := TFileStream.Create(ADest, fmCreate);
    try
      Dest.CopyFrom(Src, Src.Size);
    finally
      Dest.Free;
    end;
  finally
    Src.Free;
  end;
end;

end.
