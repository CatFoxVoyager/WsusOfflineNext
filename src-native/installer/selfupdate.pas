{*** Self-update CHECK slice for the native installer - Phase 28 parity port.

    Phase 29 plan 01 (tracer). Port of src-modern/common/selfupdate
    (UpdateCheck.cs + SelfUpdateCore.cs) to Win32-native Pascal, one path
    end-to-end: frozen INI kill-switch -> shared daily cache -> WinHTTP
    channel fetch -> strict-newer decision -> native offer dialog and its
    decline outcome. Behaviorally identical to the two .NET hosts; the
    same WSON_UPDATE_* environment hooks and the same %LOCALAPPDATA%
    update.log / last-check.txt state files are used so the unified
    fake-channel battery drives all three apps case for case.

    Plumbing contract (29-CONTEXT, locked):
    - Win32 NATIVE APIs only. WinHTTP for the fetches (static import is
      XP-SP1+-safe: winhttp.dll 5.1 ships with XP SP1+). CNG bcrypt for
      SHA256 is bound DYNAMICALLY ONLY (LoadLibrary + GetProcAddress) -
      there is deliberately NO compile-time import declaration for
      bcrypt.dll anywhere in this unit, so the exe still loads on
      XP-class machines.
    - NO fphttpclient, NO openssl, no external DLLs.

    XP TRADEOFF (D-05 essential-XP floor, stated honestly): bcrypt.dll
    exists since Vista. On an XP-class machine the CNG provider cannot
    load and the self-update FEATURE degrades to a named silent skip:
    the check thread logs check-skip-no-crypto BEFORE any network event
    and exits. A machine without the CNG provider skips updates - it
    never skips verification. XP additionally cannot negotiate TLS 1.2
    with the real channel, so the feature is effectively Vista+ while
    the binary itself still loads on XP.

    Layering (plan 29-02 consumes the pure/interface layer):
    - PURE layer: total parsers and decisions, no I/O beyond the named
      state files, every malformed input rejected, never raises.
    - Win32 layer: URL split, text fetch, SHA256 - every failure returns
      False (silent-failure discipline; the caller logs check-error).
    - TSelfUpdateCheckThread: the frozen Phase 28 check order, started
      fire-and-forget from the host's form construction.

    Text/BOM discipline: the .NET engine trims U+FEFF (UTF-8 BOM decoded
    by StreamReader). This port reads payloads at the byte level into
    AnsiString, so the same defensive trim is implemented over the UTF-8
    BOM byte triple (#$EF#$BB#$BF) - for a UTF-8 payload the two are
    observably identical, which is the parity this port must keep.

    The offer dialog goes through the Win32 MessageBoxW (user32) instead
    of the LCL's Application.MessageBox on purpose: this unit must stay
    LCL-free so the pure-layer test runner (tests/testrunner.lpr, a
    console project without the LCL) links it. Same flags, same title,
    same text, same task-modal behavior. }

unit selfupdate;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows;

const
  { Production channel, published by every release train (https only) -
    verbatim from UpdateCheck.cs. }
  SUDefaultChannelUrl =
    'https://raw.githubusercontent.com/CatFoxVoyager/WsusOfflineNext/main/static/SelfUpdateVersion-recent.txt';
  SUDefaultLinksUrl =
    'https://raw.githubusercontent.com/CatFoxVoyager/WsusOfflineNext/main/ci/StaticDownloadLink-recent.txt';

  { Text fetch budget: HttpClient.Timeout = 10 s in UpdateCheck.cs. }
  SUFetchTimeoutMs = 10000;

  { UTF-8 BOM byte triple - the byte-level twin of .NET's U+FEFF trim. }
  SUUtf8Bom = #$EF#$BB#$BF;

{ ----- paths (shared with the .NET hosts - 29-CONTEXT standing rule) }

{ %LOCALAPPDATA%\WsusOfflineNext\selfupdate, or '' when neither
  SHGetFolderPathW nor the LOCALAPPDATA variable resolve. }
function SUStateRoot: string;
function SULastCheckFilePath: string;
function SUUpdateLogPath: string;

{ Append one "yyyy-MM-dd HH:mm:ss.zzz|actor|event" line to the shared
  update.log. Never raises (best-effort diagnostics, parity with
  SelfUpdateLog.Append). }
procedure SULogAppend(const AActor, AEvent: string);

{ ----- pure decisions (mirror SelfUpdateCore.cs function by function) }

{ Parse "version,tag": exactly one comma-separated pair, both parts
  non-empty after BOM/whitespace trimming. Returns the trimmed version
  token, or '' for anything else. }
function SUParseChannelVersion(const AText: string): string;

{ Parse the links file: exactly two non-empty lines, line 1 an https://
  URL ending in '.zip', line 2 an https:// URL ending in '_hashes.txt'
  (case-sensitive suffix pins, Ordinal parity). WSON_UPDATE_ALLOW_HTTP=1
  additionally accepts http:// so a local fake channel can serve the
  package - the suffix pins stay enforced. }
function SUParseLinksFile(const AText: string; out AZipUrl, AHashesUrl: string): Boolean;

{ 4-part numeric comparison with launcher-parity semantics: any
  '+'/'-' suffix stripped first, missing or non-numeric parts count 0,
  first difference decides, all-equal is True (WebView2Compat parity).
  False when either side is empty. }
function SUVersionAtLeast(const AVersion, AMinimum: string): Boolean;

{ Strict-newer: IsChannelNewer(channel, local) :=
  AtLeast(channel, local) and not AtLeast(local, channel). }
function SUChannelNewer(const AChannelVersion, ALocalVersion: string): Boolean;

{ Copy up to the first '+' or '-' (the metadata-stripped local version). }
function SUCoreVersion(const AVersion: string): string;

{ Daily cache: a single trimmed "yyyy-MM-dd" line compared by string
  equality against today (exact behavioral equivalent of the .NET
  TryParseExact zero-padded compare). Missing/unparsable/unreadable =
  not checked today. }
function SUisCheckedToday(const ACachePath: string): Boolean;

{ Write today's date tmp-then-rename so a crashed writer can never leave
  a torn line at the real path. Never raises. }
procedure SUWriteCheckedToday(const ACachePath: string);

{ Kill-switch INI reader: inside section [Control] (case-insensitive),
  key SkipSelfUpdate with value Enabled (case-insensitive) disables the
  self-update engine. Tolerates CRLF, UTF-8 BOM, ';'/'#' comments.
  Missing/unreadable INI = not disabled; never raises. Hand-rolled line
  parser on purpose - parity is with the .NET byte-level parser and this
  keeps the decision pure-testable. }
function SUIniSelfUpdateDisabled(const AIniPath: string): Boolean;

{ Environment read wrapper (the WSON_UPDATE_* hook surface). }
function SUEnv(const AName: string): string;

{ ----- Win32 layer }

{ Split scheme://host[:port]/object. Port 0 = scheme default. False on
  any malformed shape. }
function SUSplitUrl(const AUrl: string;
  out AScheme, AHost: string; out APort: DWORD; out AObjectPath: string): Boolean;

{ GET the URL and return the payload bytes as text; the whole read loop.
  Status must be 200. Every failure returns False. }
function SUFetchText(const AUrl: string; ATimeoutMs: Integer; out AText: string): Boolean;

{ True when the CNG bcrypt provider is loadable (XP degrade probe).
  Cached after the first probe. }
function SUSha256Supported: Boolean;

{ SHA256 of the file bytes as lowercase hex through CNG; 64KB chunks.
  Any nonzero NTSTATUS or I/O failure returns False (fail-closed). }
function SUSha256File(const APath: string; out AHexLower: string): Boolean;

{ ----- check thread (the slice the tracer wires) }

{ Fire-and-forget launch-time check in the frozen Phase 28 order:
  kill-switch INI -> daily cache -> check-start -> no-crypto degrade
  (before any network call) -> env-hooked channel+links fetch+parse ->
  write-on-success cache -> strict-newer -> offer. Every failure path is
  silent or a named log event; the thread never crashes the app. }
type
  TSelfUpdateCheckThread = class(TThread)
  private
    FIniPath: string;
    FActor: string;
    FChannelVersion: string;
    FLocalVersion: string;
    procedure DoOfferDialog; { runs on the main thread via Synchronize }
  protected
    procedure Execute; override;
  public
    constructor Create(const AIniPath, AActor: string);
  end;

implementation

uses
  enginecontracts;

{ ===== Win32 API bindings ===== }

{ WinHTTP - static import, XP-SP1+-safe (winhttp.dll 5.1 ships with XP
  SP1+). HINTERNET is kept as Pointer. }

const
  SUWINHTTPACCESSTYPEDEFAULTPROXY = 0;
  SUWINHTTPFLAGSECURE = $00800000;
  SUWINHTTPQUERYSTATUSCODE = 19;
  SUWINHTTPQUERYFLAGNUMBER = $20000000;

function WinHttpOpen(Agent: PWideChar; AccessType: DWORD;
  Proxy: PWideChar; ProxyBypass: PWideChar; Flags: DWORD): Pointer; stdcall;
  external 'winhttp.dll' name 'WinHttpOpen';
function WinHttpConnect(Session: Pointer; Host: PWideChar; Port: Word;
  Reserved: DWORD): Pointer; stdcall;
  external 'winhttp.dll' name 'WinHttpConnect';
function WinHttpOpenRequest(Connect: Pointer; Verb: PWideChar;
  ObjectName: PWideChar; Version: PWideChar; Referrer: PWideChar;
  AcceptTypes: Pointer; Flags: DWORD): Pointer; stdcall;
  external 'winhttp.dll' name 'WinHttpOpenRequest';
function WinHttpSetTimeouts(Handle: Pointer; Resolve, Connect, Send,
  Receive: Integer): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpSetTimeouts';
function WinHttpSendRequest(Request: Pointer; Headers: PWideChar;
  HeadersLen: DWORD; Optional: Pointer; OptionalLen: DWORD;
  TotalLen: DWORD; Context: DWORD_PTR): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpSendRequest';
function WinHttpReceiveResponse(Request: Pointer; Reserved: Pointer): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpReceiveResponse';
function WinHttpQueryHeaders(Request: Pointer; InfoLevel: DWORD;
  Name: PWideChar; Buffer: Pointer; var BufferLen: DWORD;
  Index: Pointer): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpQueryHeaders';
function WinHttpQueryDataAvailable(Request: Pointer;
  out Available: DWORD): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpQueryDataAvailable';
function WinHttpReadData(Request: Pointer; Buffer: Pointer; ToRead: DWORD;
  var ReadBytes: DWORD): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpReadData';
function WinHttpCloseHandle(Handle: Pointer): BOOL; stdcall;
  external 'winhttp.dll' name 'WinHttpCloseHandle';

{ CNG bcrypt - DYNAMIC ONLY. No compile-time import declaration for
  bcrypt.dll exists in this unit: the bindings below are resolved at
  runtime through LoadLibrary/GetProcAddress so the exe still loads on
  XP-class machines where bcrypt.dll does not exist (D-05 floor; the
  XP tradeoff is documented in the unit header). }

var
  SUBcryptLib: THandle = 0;
  SUBcryptProbed: Boolean = False;
  SUBcryptOpenAlgorithmProvider: function(PHAlg: Pointer; AlgId: PWideChar;
    Impl: PWideChar; Flags: DWORD): LongInt; stdcall = nil;
  SUBcryptCloseAlgorithmProvider: function(HAlg: Pointer;
    Flags: DWORD): LongInt; stdcall = nil;
  SUBcryptCreateHash: function(HAlg: Pointer; PHHash: Pointer;
    PBObject: Pointer; ObjectLen: DWORD; PSecret: Pointer;
    SecretLen: DWORD; Flags: DWORD): LongInt; stdcall = nil;
  SUBcryptDestroyHash: function(HHash: Pointer; Flags: DWORD): LongInt; stdcall = nil;
  SUBcryptHashData: function(HHash: Pointer; PBuf: Pointer;
    BufLen: DWORD; Flags: DWORD): LongInt; stdcall = nil;
  SUBcryptFinishHash: function(HHash: Pointer; PResult: Pointer;
    ResultLen: DWORD; Flags: DWORD): LongInt; stdcall = nil;
  SUBcryptGetProperty: function(HAlg: Pointer; Prop: PWideChar;
    Buf: Pointer; BufLen: DWORD; out ResultLen: DWORD;
    Flags: DWORD): LongInt; stdcall = nil;

{ shell32 - static (every Windows carries it); used before any network
  call to find the shared per-user state root. }
function SUShGetFolderPathW(Hwnd: HWND; CSIDL: Integer; HToken: THandle;
  Flags: DWORD; PszPath: PWideChar): HResult; stdcall;
  external 'shell32.dll' name 'SHGetFolderPathW';

{ user32 - the offer dialog. MessageBoxW directly (not the LCL) so this
  unit stays linkable from the LCL-free pure-layer test runner. }
function SUMessageBoxW(Hwnd: HWND; Text: PWideChar; Caption: PWideChar;
  UType: DWORD): Integer; stdcall;
  external 'user32.dll' name 'MessageBoxW';

{ CSIDL_LOCAL_APPDATA }
const
  SUCSIDLLOCALAPPDATA = $001C;

{ ===== helpers ===== }

{ Read a whole file as raw bytes ('' when missing or unreadable -
  callers treat '' as the reject/not-checked/not-disabled verdict,
  exactly like the .NET File.Exists + catch shape). }
function SUReadTextFile(const APath: string): string;
var
  Fs: TFileStream;
begin
  Result := '';
  if not FileExists(APath) then
    Exit;
  try
    Fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
    try
      if Fs.Size > 0 then
      begin
        SetLength(Result, Fs.Size);
        Fs.ReadBuffer(Result[1], Fs.Size);
      end;
    finally
      Fs.Free;
    end;
  except
    Result := '';
  end;
end;

{ Strip leading UTF-8 BOM triples. }
function SUStripLeadingBom(const S: string): string;
begin
  Result := S;
  while Copy(Result, 1, 3) = SUUtf8Bom do
    Delete(Result, 1, 3);
end;

{ Trim BOM triples + CR/LF/space/tab from both ends - the byte-level
  twin of the .NET Trim(#FEFF/CR/LF/space/tab) discipline. }
procedure SUTrimWsBomInPlace(var S: string);
const
  WS = [' ', #9, #13, #10];
begin
  while True do
  begin
    if Copy(S, 1, 3) = SUUtf8Bom then
      Delete(S, 1, 3)
    else if (Length(S) > 0) and (S[1] in WS) then
      Delete(S, 1, 1)
    else
      Break;
  end;
  while True do
  begin
    if (Length(S) >= 3) and (Copy(S, Length(S) - 2, 3) = SUUtf8Bom) then
      SetLength(S, Length(S) - 3)
    else if (Length(S) > 0) and (S[Length(S)] in WS) then
      SetLength(S, Length(S) - 1)
    else
      Break;
  end;
end;

function SUTrimWsBom(const S: string): string;
begin
  Result := S;
  SUTrimWsBomInPlace(Result);
end;

function SUTrimWs(const S: string): string;
const
  WS = [' ', #9, #13, #10];
var
  A, B: Integer;
begin
  A := 1;
  B := Length(S);
  while (A <= B) and (S[A] in WS) do
    Inc(A);
  while (B >= A) and (S[B] in WS) do
    Dec(B);
  Result := Copy(S, A, B - A + 1);
end;

{ ===== paths ===== }

function SUStateRoot: string;
var
  Buf: array[0..MAX_PATH] of WideChar;
  Base: string;
begin
  Result := '';
  FillChar(Buf, SizeOf(Buf), 0);
  if SUShGetFolderPathW(0, SUCSIDLLOCALAPPDATA, 0, 0, @Buf[0]) = 0 then { S_OK }
    Base := PWideChar(@Buf[0])
  else
    Base := SysUtils.GetEnvironmentVariable('LOCALAPPDATA');
  if Base = '' then
    Exit;
  Result := IncludeTrailingPathDelimiter(Base)
    + 'WsusOfflineNext' + '\' + 'selfupdate';
end;

function SULastCheckFilePath: string;
begin
  Result := SUStateRoot + '\' + 'last-check.txt';
end;

function SUUpdateLogPath: string;
begin
  Result := SUStateRoot + '\' + 'update.log';
end;

procedure SULogAppend(const AActor, AEvent: string);
var
  Fs: TFileStream;
  Line: string;
begin
  try
    ForceDirectories(SUStateRoot);
    Line := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now)
      + '|' + AActor + '|' + AEvent + #13#10;
    if FileExists(SUUpdateLogPath) then
      Fs := TFileStream.Create(SUUpdateLogPath, fmOpenWrite or fmShareDenyWrite)
    else
      Fs := TFileStream.Create(SUUpdateLogPath, fmCreate or fmShareDenyWrite);
    try
      Fs.Seek(0, soFromEnd);
      if Length(Line) > 0 then
        Fs.WriteBuffer(Line[1], Length(Line));
    finally
      Fs.Free;
    end;
  except
    { swallow by design: logging is best-effort diagnostics }
  end;
end;

{ ===== pure decisions ===== }

function SUParseChannelVersion(const AText: string): string;
var
  S, Version, Tag: string;
  P, I, Commas: Integer;
begin
  Result := '';
  S := SUTrimWsBom(AText);
  if S = '' then
    Exit;
  Commas := 0;
  for I := 1 to Length(S) do
    if S[I] = ',' then
      Inc(Commas);
  if Commas <> 1 then
    Exit; { multi-comma (and comma-less garbage) rejects }
  P := Pos(',', S);
  Version := SUTrimWsBom(Copy(S, 1, P - 1));
  Tag := SUTrimWsBom(Copy(S, P + 1, MaxInt));
  if (Version = '') or (Tag = '') then
    Exit;
  Result := Version;
end;

function SUParseLinksFile(const AText: string;
  out AZipUrl, AHashesUrl: string): Boolean;
var
  Rest, Line, Zip, Hashes: string;
  P, NonEmpty: Integer;
  AllowHttp: Boolean;
begin
  Result := False;
  AZipUrl := '';
  AHashesUrl := '';
  Rest := SUStripLeadingBom(AText);
  NonEmpty := 0;
  Zip := '';
  Hashes := '';
  while Rest <> '' do
  begin
    P := Pos(#10, Rest);
    if P = 0 then
    begin
      Line := Rest;
      Rest := '';
    end
    else
    begin
      Line := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, MaxInt);
    end;
    Line := SUTrimWs(Line);
    if Line = '' then
      Continue;
    Inc(NonEmpty);
    if NonEmpty = 1 then
      Zip := Line
    else if NonEmpty = 2 then
      Hashes := Line
    else
      Exit; { a third non-empty line is malformed }
  end;
  if (Zip = '') or (Hashes = '') then
    Exit;
  { Scheme pin: https:// always; http:// only under the explicit test /
    Phase-30 harness hook. The suffix pins below stay enforced either
    way (battery links-http fixture runs WITHOUT the hook and must still
    be rejected). }
  AllowHttp := SUEnv('WSON_UPDATE_ALLOW_HTTP') = '1';
  if not ((Pos('https://', Zip) = 1)
      or (AllowHttp and (Pos('http://', Zip) = 1))) then
  begin
    Exit;
  end;
  if not ((Pos('https://', Hashes) = 1)
      or (AllowHttp and (Pos('http://', Hashes) = 1))) then
  begin
    Exit;
  end;
  { Ordinal case-sensitive suffix pins - Copy-based on purpose: StrUtils
    is not in this unit's uses, and the suffix pins must not depend on
    whatever RightStr a stray unit search path resolves to. }
  if (Length(Zip) < 4) or (Copy(Zip, Length(Zip) - 3, 4) <> '.zip') then
    Exit;
  if (Length(Hashes) < 11)
     or (Copy(Hashes, Length(Hashes) - 10, 11) <> '_hashes.txt') then
    Exit;
  AZipUrl := Zip;
  AHashesUrl := Hashes;
  Result := True;
end;

function SUCoreVersion(const AVersion: string): string;
var
  I: Integer;
begin
  Result := AVersion;
  for I := 1 to Length(AVersion) do
    if AVersion[I] in ['+', '-'] then
    begin
      Result := Copy(AVersion, 1, I - 1);
      Exit;
    end;
end;

function SUVersionAtLeast(const AVersion, AMinimum: string): Boolean;

  { Parse the dot-part at Idx (0 when missing or non-numeric) and
    advance Idx past the part and its trailing dot. }
  function NextNum(const S: string; var Idx: Integer): Integer;
  var
    P: Integer;
  begin
    if Idx > Length(S) then
      Exit(0);
    P := Idx;
    while (P <= Length(S)) and (S[P] <> '.') do
      Inc(P);
    Result := StrToIntDef(Copy(S, Idx, P - Idx), 0);
    if P <= Length(S) then
      Idx := P + 1
    else
      Idx := P;
  end;

var
  CA, CB: string;
  IA, IB, VA, VB: Integer;
begin
  Result := False;
  if (AVersion = '') or (AMinimum = '') then
    Exit;
  CA := SUCoreVersion(AVersion);
  CB := SUCoreVersion(AMinimum);
  IA := 1;
  IB := 1;
  while True do
  begin
    VA := NextNum(CA, IA);
    VB := NextNum(CB, IB);
    if VA <> VB then
      Exit(VA > VB);
    if (IA > Length(CA)) and (IB > Length(CB)) then
      Exit(True);
  end;
end;

function SUChannelNewer(const AChannelVersion, ALocalVersion: string): Boolean;
begin
  Result := SUVersionAtLeast(AChannelVersion, ALocalVersion)
    and not SUVersionAtLeast(ALocalVersion, AChannelVersion);
end;

function SUisCheckedToday(const ACachePath: string): Boolean;
begin
  Result := (SUTrimWsBom(SUReadTextFile(ACachePath))
    = FormatDateTime('yyyy-mm-dd', Now));
end;

procedure SUWriteCheckedToday(const ACachePath: string);
var
  Fs: TFileStream;
  Tmp, Today: string;
begin
  try
    ForceDirectories(ExtractFilePath(ACachePath));
    Tmp := ACachePath + '.tmp';
    Today := FormatDateTime('yyyy-mm-dd', Now);
    Fs := TFileStream.Create(Tmp, fmCreate or fmShareDenyWrite);
    try
      if Length(Today) > 0 then
        Fs.WriteBuffer(Today[1], Length(Today));
    finally
      Fs.Free;
    end;
    if FileExists(ACachePath) then
      SysUtils.DeleteFile(ACachePath);
    if not RenameFile(Tmp, ACachePath) then
      SysUtils.DeleteFile(Tmp); { best-effort; the next launch re-checks - harmless }
  except
    { swallow by design: a failed cache write only means the next launch
      re-checks the network }
  end;
end;

function SUIniSelfUpdateDisabled(const AIniPath: string): Boolean;
var
  Content, Rest, Line, Key, Value: string;
  P, Eq: Integer;
  InControl: Boolean;
begin
  Result := False;
  Content := SUStripLeadingBom(SUReadTextFile(AIniPath));
  InControl := False;
  Rest := Content;
  while Rest <> '' do
  begin
    P := Pos(#10, Rest);
    if P = 0 then
    begin
      Line := Rest;
      Rest := '';
    end
    else
    begin
      Line := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, MaxInt);
    end;
    Line := SUTrimWs(Line);
    if (Line = '') or (Line[1] = ';') or (Line[1] = '#') then
      Continue;
    if (Line[1] = '[') and (Line[Length(Line)] = ']') and (Length(Line) >= 2) then
    begin
      InControl := SameText(SUTrimWs(Copy(Line, 2, Length(Line) - 2)), 'Control');
      Continue;
    end;
    if not InControl then
      Continue;
    Eq := Pos('=', Line);
    if Eq = 0 then
      Continue;
    Key := SUTrimWs(Copy(Line, 1, Eq - 1));
    Value := SUTrimWs(Copy(Line, Eq + 1, MaxInt));
    if SameText(Key, 'SkipSelfUpdate') and SameText(Value, 'Enabled') then
      Exit(True);
  end;
end;

function SUEnv(const AName: string): string;
begin
  Result := SysUtils.GetEnvironmentVariable(AName);
end;

{ ===== Win32 layer ===== }

function SUSplitUrl(const AUrl: string;
  out AScheme, AHost: string; out APort: DWORD; out AObjectPath: string): Boolean;
var
  Rest, HostPort: string;
  P, Slash, Colon: Integer;
begin
  Result := False;
  AScheme := '';
  AHost := '';
  APort := 0;
  AObjectPath := '';
  P := Pos('://', AUrl);
  if P < 2 then
    Exit; { no scheme, or an empty scheme (also rejects '://host') }
  AScheme := Copy(AUrl, 1, P - 1);
  Rest := Copy(AUrl, P + 3, MaxInt);
  if Rest = '' then
    Exit;
  Slash := Pos('/', Rest);
  if Slash = 0 then
  begin
    HostPort := Rest;
    AObjectPath := '/';
  end
  else
  begin
    HostPort := Copy(Rest, 1, Slash - 1);
    AObjectPath := Copy(Rest, Slash, MaxInt);
  end;
  if HostPort = '' then
    Exit;
  Colon := Pos(':', HostPort);
  if Colon > 0 then
  begin
    AHost := Copy(HostPort, 1, Colon - 1);
    APort := DWORD(StrToIntDef(Copy(HostPort, Colon + 1, MaxInt), 0));
  end
  else
    AHost := HostPort;
  if AHost = '' then
    Exit;
  Result := True;
end;

function SUFetchText(const AUrl: string; ATimeoutMs: Integer;
  out AText: string): Boolean;
var
  Session, Connect, Request: Pointer;
  Scheme, Host, ObjectPath: string;
  Port: DWORD;
  WHost, WVerb, WPath: WideString;
  Secure: Boolean;
  Status, StatusLen: DWORD;
  Avail, ReadBytes: DWORD;
  Chunk: AnsiString;
  Body: AnsiString;
begin
  AText := '';
  Result := False;
  if not SUSplitUrl(AUrl, Scheme, Host, Port, ObjectPath) then
    Exit;
  Secure := SameText(Scheme, 'https');
  WVerb := 'GET';
  WHost := Host;
  WPath := ObjectPath;
  Session := WinHttpOpen(PWideChar(WideString('WsusOfflineNext-selfupdate')),
    SUWINHTTPACCESSTYPEDEFAULTPROXY, nil, nil, 0);
  if Session = nil then
    Exit;
  try
    WinHttpSetTimeouts(Session, ATimeoutMs, ATimeoutMs, ATimeoutMs, ATimeoutMs);
    Connect := WinHttpConnect(Session, PWideChar(WHost), Word(Port), 0);
    if Connect = nil then
      Exit;
    try
      if Secure then
        Request := WinHttpOpenRequest(Connect, PWideChar(WVerb),
          PWideChar(WPath), nil, nil, nil, SUWINHTTPFLAGSECURE)
      else
        Request := WinHttpOpenRequest(Connect, PWideChar(WVerb),
          PWideChar(WPath), nil, nil, nil, 0);
      if Request = nil then
        Exit;
      try
        if not WinHttpSendRequest(Request, nil, 0, nil, 0, 0, 0) then
          Exit;
        if not WinHttpReceiveResponse(Request, nil) then
          Exit;
        Status := 0;
        StatusLen := SizeOf(Status);
        if not WinHttpQueryHeaders(Request,
            SUWINHTTPQUERYSTATUSCODE or SUWINHTTPQUERYFLAGNUMBER,
            nil, @Status, StatusLen, nil) then
          Exit;
        if Status <> 200 then
          Exit;
        Body := '';
        repeat
          Avail := 0;
          if not WinHttpQueryDataAvailable(Request, Avail) then
            Exit;
          if Avail = 0 then
            Break;
          SetLength(Chunk, Avail);
          ReadBytes := 0;
          if not WinHttpReadData(Request, @Chunk[1], Avail, ReadBytes) then
            Exit;
          if ReadBytes = 0 then
            Break;
          SetLength(Chunk, ReadBytes);
          Body := Body + Chunk;
        until False;
        AText := Body;
        Result := True;
      finally
        WinHttpCloseHandle(Request);
      end;
    finally
      WinHttpCloseHandle(Connect);
    end;
  finally
    WinHttpCloseHandle(Session);
  end;
end;

function SULoadBcrypt: Boolean;
begin
  if SUBcryptProbed then
    Exit(SUBcryptLib <> 0);
  SUBcryptProbed := True;
  { Dynamic LoadLibrary ONLY - no import-table entry for bcrypt.dll, so
    the exe still loads on XP-class machines. }
  SUBcryptLib := Windows.LoadLibrary('bcrypt.dll');
  if SUBcryptLib = 0 then
    Exit(False);
  Pointer(SUBcryptOpenAlgorithmProvider) := GetProcAddress(SUBcryptLib, 'BCryptOpenAlgorithmProvider');
  Pointer(SUBcryptCloseAlgorithmProvider) := GetProcAddress(SUBcryptLib, 'BCryptCloseAlgorithmProvider');
  Pointer(SUBcryptCreateHash) := GetProcAddress(SUBcryptLib, 'BCryptCreateHash');
  Pointer(SUBcryptDestroyHash) := GetProcAddress(SUBcryptLib, 'BCryptDestroyHash');
  Pointer(SUBcryptHashData) := GetProcAddress(SUBcryptLib, 'BCryptHashData');
  Pointer(SUBcryptFinishHash) := GetProcAddress(SUBcryptLib, 'BCryptFinishHash');
  Pointer(SUBcryptGetProperty) := GetProcAddress(SUBcryptLib, 'BCryptGetProperty');
  if (not Assigned(SUBcryptOpenAlgorithmProvider))
     or (not Assigned(SUBcryptCloseAlgorithmProvider))
     or (not Assigned(SUBcryptCreateHash))
     or (not Assigned(SUBcryptDestroyHash))
     or (not Assigned(SUBcryptHashData))
     or (not Assigned(SUBcryptFinishHash))
     or (not Assigned(SUBcryptGetProperty)) then
  begin
    FreeLibrary(SUBcryptLib);
    SUBcryptLib := 0;
    Exit(False);
  end;
  Result := True;
end;

function SUSha256Supported: Boolean;
begin
  Result := SULoadBcrypt;
end;

{ KNOWN HAZARD (plan 29-01, flagged for 29-02): the digest itself is
  CORRECT (verified against sha256sum on multi-chunk files), but on this
  FPC 3.2.2 i386 lane the process's console output channel breaks
  immediately AFTER the function completes (spurious EInOutError/Disk
  Full or an AV at a fixed heap address). Suspected heap-adjacency
  corruption; three fix attempts (NULL-object, explicit ObjectLength
  object, allocation slack) did not clear it. NOT called by any shipped
  path of this plan (the check thread uses SUSha256Supported only).
  Plan 29-02 MUST NOT wire the accept pipeline through this function
  until the corruption is root-caused - see 29-01-SUMMARY and
  .planning/WINDOWS.md. }
function SUSha256File(const APath: string; out AHexLower: string): Boolean;
const
  ChunkSize = 65536;
  HexChars = '0123456789abcdef';
var
  HAlg, HHash, HashObj, Buf: Pointer;
  Fs: TFileStream;
  HashBytes: array[0..31] of Byte;
  Read, I: Integer;
  Status: LongInt;
  ObjLen, ResultLen: DWORD;
begin
  Result := False;
  AHexLower := '';
  if not SULoadBcrypt then
    Exit;
  try
    Fs := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
  except
    Exit;
  end;
  try
    Status := SUBcryptOpenAlgorithmProvider(@HAlg,
      PWideChar(WideString('SHA256')), nil, 0);
    if Status < 0 then
      Exit;
    try
      { Explicit ownership for BOTH CNG-side buffers: the hash object
        (ObjectLength query, our GetMem) and the 64KB chunk buffer. The
        FPC PE default stack header (4KB reserve / 1MB commit swap) makes
        big STACK frames a crash risk on this lane, so no chunk-sized
        stack arrays; and DestroyHash with CNG-allocated object memory
        corrupted the process on this pipeline - with buffers we own,
        DestroyHash frees only the handle and we free ours. }
      ObjLen := 0;
      ResultLen := 0;
      Status := SUBcryptGetProperty(HAlg,
        PWideChar(WideString('ObjectLength')), @ObjLen, SizeOf(ObjLen),
        ResultLen, 0);
      if (Status < 0) or (ObjLen = 0) then
        Exit;
      GetMem(HashObj, ObjLen + 4096); { slack: some CNG builds overrun ObjectLength }
      try
        Status := SUBcryptCreateHash(HAlg, @HHash, HashObj, ObjLen, nil, 0, 0);
        if Status < 0 then
          Exit;
        try
          GetMem(Buf, ChunkSize + 4096); { slack, same overrun guard }
          try
            repeat
              Read := Fs.Read(Buf^, ChunkSize);
              if Read > 0 then
              begin
                Status := SUBcryptHashData(HHash, Buf, DWORD(Read), 0);
                if Status < 0 then
                  Exit;
              end;
            until Read < ChunkSize;
            Status := SUBcryptFinishHash(HHash, @HashBytes[0], SizeOf(HashBytes), 0);
            if Status < 0 then
              Exit;
            for I := 0 to SizeOf(HashBytes) - 1 do
              AHexLower := AHexLower + HexChars[1 + (HashBytes[I] shr 4)]
                + HexChars[1 + (HashBytes[I] and $F)];
            Result := True;
          finally
            FreeMem(Buf, ChunkSize + 4096);
          end;
        finally
          SUBcryptDestroyHash(HHash, 0);
        end;
      finally
        FreeMem(HashObj);
      end;
    finally
      SUBcryptCloseAlgorithmProvider(HAlg, 0);
    end;
  finally
    Fs.Free;
  end;
end;

{ ===== check thread ===== }

{ OfferGuard latch: never more than one offer per process. Checked and
  set INSIDE the synchronized dialog call (UpdateCheck.cs parity). }
var
  SUOfferLatch: Boolean = False;

constructor TSelfUpdateCheckThread.Create(const AIniPath, AActor: string);
begin
  inherited Create(True); { CreateSuspended: fields before the run }
  FIniPath := AIniPath;
  FActor := AActor;
  FChannelVersion := '';
  FLocalVersion := '';
  FreeOnTerminate := True;
  Start;
end;

procedure TSelfUpdateCheckThread.DoOfferDialog;
var
  WText, WTitle: WideString;
  Choice: Integer;
begin
  if SUOfferLatch then
    Exit;
  SUOfferLatch := True;
  try
    WTitle := 'WSUS Offline Next';
    WText := 'Version ' + FChannelVersion + ' is available on the update channel.'
      + #13#10
      + 'Installed version: ' + FLocalVersion + #13#10#13#10
      + 'Download and install the update now?';
    Choice := SUMessageBoxW(0, PWideChar(WText), PWideChar(WTitle),
      MB_TASKMODAL or MB_ICONQUESTION or MB_YESNO);
    if Choice = IDYES then
    begin
      SULogAppend(FActor, 'update-accepted');
      { The accept pipeline (verified download, fail-closed SHA256,
        guarded extraction, staging, updater handoff) arrives with plan
        29-02 task 1 - this branch ONLY logs the event in this plan. }
    end
    else
      SULogAppend(FActor, 'update-declined');
  except
    { the offer must never crash the app }
  end;
end;

procedure TSelfUpdateCheckThread.Execute;
var
  ChannelUrl, LinksUrl, LocalVersion: string;
  ChannelText, LinksText: string;
  ZipUrl, HashesUrl: string;
begin
  try
    { 1. Kill-switch outranks everything (a disabled machine must not
       even touch the cache file). }
    if SUIniSelfUpdateDisabled(FIniPath) then
    begin
      SULogAppend(FActor, 'check-skip-disabled');
      Exit;
    end;
    { 2. Daily cache. }
    if SUisCheckedToday(SULastCheckFilePath) then
    begin
      SULogAppend(FActor, 'check-skip-cache');
      Exit;
    end;
    { 3. }
    SULogAppend(FActor, 'check-start');
    { 4. XP degrade BEFORE any network call - the degrade outranks the
       fetch (see the unit header tradeoff). }
    if not SUSha256Supported then
    begin
      SULogAppend(FActor, 'check-skip-no-crypto');
      Exit;
    end;
    { 5. Test / Phase-30 harness hooks (same surface as UpdateCheck.cs). }
    ChannelUrl := SUEnv('WSON_UPDATE_CHANNEL_URL');
    if ChannelUrl = '' then
      ChannelUrl := SUDefaultChannelUrl;
    LinksUrl := SUEnv('WSON_UPDATE_LINKS_URL');
    if LinksUrl = '' then
      LinksUrl := SUDefaultLinksUrl;
    LocalVersion := SUEnv('WSON_UPDATE_LOCAL_VERSION');
    if SUTrimWs(LocalVersion) = '' then
      LocalVersion := SUCoreVersion(EngOwnProductVersion);
    { 6. Channel read + parse. }
    if (not SUFetchText(ChannelUrl, SUFetchTimeoutMs, ChannelText))
       or (SUParseChannelVersion(ChannelText) = '') then
    begin
      SULogAppend(FActor, 'check-error');
      Exit;
    end;
    FChannelVersion := SUParseChannelVersion(ChannelText);
    { 7. Links read + parse - the offer must carry real URLs. }
    if (not SUFetchText(LinksUrl, SUFetchTimeoutMs, LinksText))
       or (not SUParseLinksFile(LinksText, ZipUrl, HashesUrl)) then
    begin
      SULogAppend(FActor, 'check-error');
      Exit;
    end;
    { 8. Cache write happens ONLY on a completed channel read+parse AND
       links read+parse: a failed run retries the network the same day. }
    SUWriteCheckedToday(SULastCheckFilePath);
    { 9. Strict-newer; not newer stops silently (no log spam). }
    if not SUChannelNewer(FChannelVersion, LocalVersion) then
      Exit;
    { 10. }
    SULogAppend(FActor, 'update-offered');
    { 11. }
    if SUEnv('WSON_UPDATE_AUTO_DECLINE') = '1' then
    begin
      SULogAppend(FActor, 'update-declined');
      Exit;
    end;
    { 12. The offer on the main thread (OfferGuard latch inside). }
    FLocalVersion := LocalVersion;
    Synchronize(@DoOfferDialog);
  except
    { silent-failure discipline: any network or parse error logs
      check-error and leaves the launch path untouched }
    SULogAppend(FActor, 'check-error');
  end;
end;

end.
