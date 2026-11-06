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
  Classes, SysUtils, Windows, IniFiles;

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
    DoUpdate.cmd:1701) - research Pitfall F. Never move the selection
    file to %TEMP% - the engine would silently never see it. }
  ENG_MSI_LISTING_NAME = 'wouallmsi.txt';
  ENG_MSI_SELECTION_NAME = 'wouselmsi.txt';

  { The five engine outcome files (DoUpdate.cmd:53-58 lifecycle; appended
    live during the run - the observation spine watches them on the pump
    tick and the completion summary is built from them). All in the
    caller %TEMP%. }
  ENG_OUTCOME_INSTALLED = 'wou_installed_updates.txt';
  ENG_OUTCOME_FAILED = 'wou_failed_updates.txt';
  ENG_OUTCOME_CORRUPT = 'wou_corrupt_updates.txt';
  ENG_OUTCOME_CLEAN_SKIPPED = 'wou_clean_skipped_updates.txt';
  ENG_OUTCOME_VERIFICATION_SKIPPED = 'wou_verification_skipped.txt';

  { Engine staging across reboots, in %SystemRoot%\Temp
    (InstallListedUpdates.cmd:26-30, 80-84): SetWOUpdateStage.cmd is
    deleted-on-read by the engine; WOUpdatesToInstall.txt is the moved
    remaining-updates list. Their EXISTENCE is the GUI's resume decision
    input - never touched by the GUI. }
  ENG_STAGING_STAGE_CMD = 'SetWOUpdateStage.cmd';
  ENG_STAGING_UPDATES = 'WOUpdatesToInstall.txt';

  { The engine's own log (DoUpdate.cmd UPDATE_LOGFILE default), used for
    the /showlog parity open. }
  ENG_ENGINE_LOG_NAME = 'wsusofflineupdate.log';

  { ===== Incumbent PathValid rule (au3:92-93, 262-278) ===== }
  ENG_PATH_MAX_LENGTH = 192;
  ENG_PATH_INVALID_CHARS = '!%&()^+,;=';

  { ===== WUStatusServer INI -> HKLM-policies contract (au3:32,41,1205-1208):
    a non-empty Miscellaneous/WUStatusServer value is written as REG_SZ to
    this key right before the engine is spawned. }
  ENG_REG_KEY_WINDOWSUPDATE = 'Software\Policies\Microsoft\Windows\WindowsUpdate';
  ENG_REG_VAL_WUSTATUSSERVER = 'WUStatusServer';

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

{ Pure resolution core behind EngCmdExePath with injectable environment -
  the unit-testable form of the SysNative matrix (32-bit-on-x64 ->
  SysNative; 64-bit process or missing SysNative dir -> %ComSpec%). }
function EngCmdExePathFor(const ASysRoot, AComSpec: string;
  AIs32BitProcess, ASysNativeDirExists: Boolean): string;

{ INI merge-order parity (au3:216-229). EngDefaultIniRead reads the CLIENT
  ini only (the template next to the exe - the engine's recall path also
  reads it); EngMyIniRead layers the %TEMP%\UpdateInstaller.ini copy ON
  TOP of it per key (the GUI<->GUI state channel; the engine deletes that
  copy after the run, DoUpdate.cmd:2355). Missing files fall back to the
  default without error, like the incumbent's IniRead. }
function EngDefaultIniRead(const AClientIniPath, ASection, AKey,
  ADefault: string): string;
function EngMyIniRead(const AClientIniPath, ATempIniPath, ASection, AKey,
  ADefault: string): string;

{ Toggle inputs of the pure argv emission - the 15 GUI checkbox switches
  plus the 8 INI-driven switches and the /autoreboot emit decision (the
  incumbent's enabled-AND-checked rule, au3:1264-1266 - a DISABLED box
  never emits even when its Checked flag was left set). }
type
  TArgvToggles = record
    UpgradeBuilds, Updatercerts, InstDotNet35, InstDotNet4, InstWmf: Boolean;
    UpdateDotNet5, UpdateCpp, InstEdge, InstWebView2, UpdateOffice: Boolean;
    Verify, AuditOnly, AutoReboot, Shutdown, ShowLog: Boolean;
    SkipIeInst, SkipDefs, SkipDynamic, AllUpdates, ExcludeStatics: Boolean;
    SecOnly, ShowDismProgress, MonitorOn: Boolean;
  end;

{ Pure argv emission in the incumbent's exact switch order (au3:1210-1281):
  checkbox switches first, then the INI-driven ones, /autoreboot before
  /shutdown, INI-driven messaging/misc last. Tokens come ONLY from the
  frozen table via EngSwitchToken - an unknown toggle name compiles to an
  empty token, never to raw text (threat T-26-01). }
function EngBuildArgv(const A: TArgvToggles): string;

{ The running exe's own VERSIONINFO ProductVersion ('' when the resource is
  absent - true until plan 03 lands the .lpi VersionInfo). }
function EngOwnProductVersion: string;

{ Incumbent caption shape: 'WSUS Offline Next - <ProductVersion> - Installer'
  or the versionless constant when no VERSIONINFO exists yet - never a
  second hardcoded version literal. }
function EngWindowCaption: string;

function EngPathValid(const APath: string): Boolean;

{ Startup OS gate port (au3:998-1005), amended per milestone decision
  D-05 (owner veto: XP SP3 is an essential product target — airgapped
  machines are the core value): False only for versions below 5.1,
  i.e. XP pre-SP1/2000 and older. XP SP3 (5.1) and every later Windows
  are accepted. }
function EngOsVersionSupported: Boolean;

{ Human-readable OS version for the gate error box. }
function EngOsVersionDisplay: string;

{ Byte copy used by the INI-copy contract (au3 IniCopy parity); callers
  clear the read-only bit on the destination afterwards. }
procedure EngCopyFileRaw(const ASrc, ADest: string);

{ MSI listing parse (au3:968 shape): bare package file names, one per
  line; empty lines dropped. The caller owns the read-then-DELETE of the
  listing file (au3:975). }
procedure EngReadMsiListing(const APath: string; ANames: TStrings);

{ MSI selection write-or-delete (au3:1282-1293; threat T-26-05): one RAW
  package file name per line (CRLF-terminated, no quoting, no added
  decoration - the engine consumes the file with find /I exact
  substring), written as ANSI bytes (CP_ACP - the incumbent's
  FileWriteLine byte semantics; the LCL strings are UTF-8). An EMPTY
  selection DELETES the file (the engine then skips the MSI pass
  entirely). Never call this with a %TEMP% path - see
  ENG_MSI_SELECTION_NAME. }
procedure EngWriteMsiSelection(const APath: string; ANames: TStrings);

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

function EngCmdExePathFor(const ASysRoot, AComSpec: string;
  AIs32BitProcess, ASysNativeDirExists: Boolean): string;
var
  ComSpec: string;
begin
  Result := '';
  {$IFDEF WIN32}
  { 32-bit process on 64-bit Windows: SysNative is the supported escape
    hatch - the engine's wusa/dism children must see the native system32. }
  if AIs32BitProcess and ASysNativeDirExists and (ASysRoot <> '') then
    Exit(ASysRoot + '\SysNative\cmd.exe');
  {$ENDIF WIN32}
  ComSpec := AComSpec;
  if ComSpec = '' then
  begin
    if ASysRoot = '' then
      Exit;
    ComSpec := 'cmd.exe';
  end;
  { Guard the contract's absolute-path rule: %ComSpec% is absolute on every
    real install, but a bare name must never reach a PATH spawn. }
  if (Pos('\', ComSpec) = 0) and (Pos('/', ComSpec) = 0) and (ASysRoot <> '') then
    ComSpec := ASysRoot + '\System32\' + ComSpec;
  Result := ComSpec;
end;

function EngCmdExePath: string;
var
  SysRoot: string;
begin
  SysRoot := SysUtils.GetEnvironmentVariable('SystemRoot');
  if SysRoot = '' then
    SysRoot := SysUtils.GetEnvironmentVariable('windir');
  {$IFDEF WIN32}
  Result := EngCmdExePathFor(SysRoot, SysUtils.GetEnvironmentVariable('ComSpec'),
    True, DirectoryExists(SysRoot + '\SysNative'));
  {$ELSE WIN32}
  Result := EngCmdExePathFor(SysRoot, SysUtils.GetEnvironmentVariable('ComSpec'),
    False, DirectoryExists(SysRoot + '\SysNative'));
  {$ENDIF WIN32}
end;

function EngDefaultIniRead(const AClientIniPath, ASection, AKey,
  ADefault: string): string;
begin
  Result := ADefault;
  if FileExists(AClientIniPath) then
  begin
    with TIniFile.Create(AClientIniPath) do
      try
        Result := ReadString(ASection, AKey, ADefault);
      finally
        Free;
      end;
  end;
end;

function EngMyIniRead(const AClientIniPath, ATempIniPath, ASection, AKey,
  ADefault: string): string;
begin
  Result := EngDefaultIniRead(AClientIniPath, ASection, AKey, ADefault);
  if FileExists(ATempIniPath) then
  begin
    with TIniFile.Create(ATempIniPath) do
      try
        Result := ReadString(ASection, AKey, Result);
      finally
        Free;
      end;
  end;
end;

function EngBuildArgv(const A: TArgvToggles): string;
  procedure AddSwitch(const AName: string; AOn: Boolean);
  var
    Token: string;
  begin
    if not AOn then
      Exit;
    Token := EngSwitchToken(AName);
    if Token <> '' then
      Result := Result + ' ' + Token;
  end;
begin
  Result := '';
  { Checkbox switches - the incumbent's emission order (au3:1210-1239). }
  AddSwitch('upgradebuilds', A.UpgradeBuilds);
  AddSwitch('updatercerts', A.Updatercerts);
  AddSwitch('instdotnet35', A.InstDotNet35);
  AddSwitch('instdotnet4', A.InstDotNet4);
  AddSwitch('instwmf', A.InstWmf);
  AddSwitch('updatedotnet5', A.UpdateDotNet5);
  AddSwitch('updatecpp', A.UpdateCpp);
  AddSwitch('instedge', A.InstEdge);
  AddSwitch('instwebview2', A.InstWebView2);
  AddSwitch('updateoffice', A.UpdateOffice);
  { INI-driven switches - read from the client INI only (au3:1240-1257). }
  AddSwitch('skipieinst', A.SkipIeInst);
  AddSwitch('skipdefs', A.SkipDefs);
  AddSwitch('skipdynamic', A.SkipDynamic);
  AddSwitch('all', A.AllUpdates);
  AddSwitch('excludestatics', A.ExcludeStatics);
  AddSwitch('seconly', A.SecOnly);
  { Control + messaging (au3:1258-1281): /autoreboot sits between
    /auditonly and /shutdown in the emission order. }
  AddSwitch('verify', A.Verify);
  AddSwitch('auditonly', A.AuditOnly);
  AddSwitch('autoreboot', A.AutoReboot);
  AddSwitch('shutdown', A.Shutdown);
  AddSwitch('showlog', A.ShowLog);
  AddSwitch('showdismprogress', A.ShowDismProgress);
  AddSwitch('monitoron', A.MonitorOn);
  Result := Trim(Result);
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
  Result := (Info.dwMajorVersion > 5)
    or ((Info.dwMajorVersion = 5) and (Info.dwMinorVersion >= 1));
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

procedure EngReadMsiListing(const APath: string; ANames: TStrings);
var
  Sl: TStringList;
  I: Integer;
  Line: string;
begin
  ANames.Clear;
  if not FileExists(APath) then
    Exit;
  Sl := TStringList.Create;
  try
    Sl.LoadFromFile(APath);
    for I := 0 to Sl.Count - 1 do
    begin
      Line := Trim(Sl.Strings[I]);
      if Line <> '' then
        ANames.Add(Line);
    end;
  finally
    Sl.Free;
  end;
end;

function EngUtf8ToAnsi(const AValue: string): AnsiString;
var
  W: WideString;
  WLen: Integer;
  Len: Integer;
begin
  { CP_ACP = the incumbent's ANSI FileWrite bytes. }
  W := UTF8Decode(AValue);
  WLen := Length(W);
  if WLen = 0 then
    Exit('');
  Len := WideCharToMultiByte(CP_ACP, 0, PWideChar(W), WLen, nil, 0, nil, nil);
  if Len <= 0 then
    Exit('');
  SetLength(Result, Len);
  WideCharToMultiByte(CP_ACP, 0, PWideChar(W), WLen, PAnsiChar(Result), Len, nil, nil);
end;

procedure EngWriteMsiSelection(const APath: string; ANames: TStrings);
var
  Fs: TFileStream;
  S: AnsiString;
  I: Integer;
begin
  if ANames.Count = 0 then
  begin
    { Empty selection = the engine skips the MSI pass (au3:1291-1293). }
    if FileExists(APath) then
      SysUtils.DeleteFile(APath);
    Exit;
  end;
  S := '';
  for I := 0 to ANames.Count - 1 do
    S := S + EngUtf8ToAnsi(ANames.Strings[I]) + #13#10;
  Fs := TFileStream.Create(APath, fmCreate);
  try
    if Length(S) > 0 then
      Fs.WriteBuffer(PAnsiChar(S)^, Length(S));
  finally
    Fs.Free;
  end;
end;

end.
