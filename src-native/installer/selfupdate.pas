{*** Self-update CHECK + ACCEPT slice for the native installer.

    Phase 29 plan 01 (tracer) ported the CHECK slice; plan 02 added the
    ACCEPT pipeline (UpdateInstall.cs parity): hashes-file parser,
    streaming zip download, fail-closed SHA256 verification, guarded
    extraction, staging completeness, and the updater handoff with the
    frozen CLI contract, plus the offer continuation that closes the
    host so the waiting updater can swap. Behaviorally identical to the
    two .NET hosts; the same WSON_UPDATE_* environment hooks and the
    same %LOCALAPPDATA% update.log / last-check.txt state files are
    used so the unified fake-channel battery drives all three apps
    case for case.

    Plumbing contract (29-CONTEXT, locked):
    - Win32 NATIVE APIs only. WinHTTP for the fetches (static import is
      XP-SP1+-safe: winhttp.dll 5.1 ships with XP SP1+). CNG bcrypt for
      SHA256 is bound DYNAMICALLY ONLY (LoadLibrary + GetProcAddress) -
      there is deliberately NO compile-time import declaration for
      bcrypt.dll anywhere in this unit, so the exe still loads on
      XP-class machines.
    - NO fphttpclient, NO openssl, no external DLLs. The guarded
      extraction uses the FCL zipper unit (TFPZipper family - in FPC
      3.2.2 the classes are TZipper/TUnZipper), a pure-Pascal in-process
      extractor: no dependency on bin\unzip.exe.

    XP TRADEOFF (D-05 essential-XP floor, stated honestly): bcrypt.dll
    exists since Vista. On an XP-class machine the CNG provider cannot
    load and the self-update FEATURE degrades to a named silent skip:
    the check thread logs check-skip-no-crypto BEFORE any network event
    and exits. A machine without the CNG provider skips updates - it
    never skips verification. XP additionally cannot negotiate TLS 1.2
    with the real channel, so the feature is effectively Vista+ while
    the binary itself still loads on XP.

    FAIL-CLOSED RULE (T-29-04/T-29-07): the hash gate runs BEFORE
    extraction; the extraction guard refuses WHOLE archives (never
    per-entry); and a machine whose CNG provider is unavailable can
    never reach this code at all - the check slice already degraded
    with check-skip-no-crypto before any download starts, so there is
    no code path that downloads or extracts without verification (the
    degrade skips the update entirely, never the hash gate).

    CNG/exception-frame discipline (29-02 root cause, ledger 23): on
    this FPC 3.2.2 i386 lane, running the CNG hash sequence with FPC
    try/finally exception frames ACTIVE ACROSS the bcrypt calls
    corrupts the exception-dispatch state - the NEXT exception raised
    after the hash dies inside dispatch at a fixed stack-top address
    (a garbage handler call, exit 217). The digest itself was always
    correct; the corruption is dispatch-side. SUSha256File therefore
    runs the CNG section with ZERO FPC exception frames spanning it
    (sequential status checks, single staged teardown, raw Win32 file
    I/O - nothing in the section can raise). Caller-level frames
    spanning SUSha256File are proven safe by the same probe matrix
    (planning tmp 29-02-rootcause).

    Layering:
    - PURE layer: total parsers and decisions, no I/O beyond the named
      state files, every malformed input rejected, never raises.
    - Win32 layer: URL split, text fetch, zip download, SHA256 - every
      failure returns False (silent-failure discipline).
    - TSelfUpdateCheckThread: the frozen Phase 28 check order, started
      fire-and-forget from the host's form construction.
    - SUInstallAccepted: the accept continuation, always entered from
      the main thread (the offer dialog marshals there).

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
  Any nonzero NTSTATUS or I/O failure returns False (fail-closed).
  Implementation note: the CNG section of this function carries NO FPC
  exception frames (see the unit header - frames spanning the bcrypt
  calls corrupt exception dispatch on this lane); callers may keep
  their own frames, that is proven safe. }
function SUSha256File(const APath: string; out AHexLower: string): Boolean;

{ ----- accept pipeline (plan 29-02, UpdateInstall.cs parity) }

{ One accepted update offer: the channel version plus the two real
  download URLs already validated by SUParseLinksFile (https pin +
  suffix pins) during the check slice. }
type
  TSUUpdateOffer = record
    ChannelVersion: string;
    ZipUrl: string;
    HashesUrl: string;
  end;

{ Host hook: close the main form so the process exits and the waiting
  updater proceeds. Assigned by the host form via SURegisterHostClose -
  a plain procedure pointer, so this unit stays LCL-free. }
  TSUHostCloseProc = procedure;

var
  SUHostCloseProc: TSUHostCloseProc = nil;

{ Register the host-close hook (no-op until the host registers). }
procedure SURegisterHostClose(AProc: TSUHostCloseProc);

{ Parse the published hashes file as MEASURED from the release pipeline
  (hashdeep -c md5,sha1,sha256 -b): data lines are
  "size,md5,sha1,sha256,filename", comma-separated, lowercase hex,
  filename last. Lines that are empty, start with '%%%%' or start with
  '##' are headers. Exactly one data line is required; field POSITION
  decides (never the filename): field 0 = size (> 0), field 3 = SHA256
  (exactly 64 chars of [0-9a-f], checked char by char). Every field
  must be non-empty. Anything else returns False. }
function SUParseHashesFile(const AText: string; out ASize: Int64;
  out ASHA256: string): Boolean;

{ GET the URL and stream the payload to ADestPath (status must be 200;
  a 30s per-step receive budget - a stalled link aborts, a slow-but-
  flowing one does not). Every failure returns False. }
function SUDownloadToFile(const AUrl, ADestPath: string): Boolean;

{ Native size of a file through raw Win32; False when the file cannot
  be opened (never raises). The verify gate's length check. }
function SUFileSizeOf(const APath: string; out ASize: Int64): Boolean;

{ FAIL-CLOSED verification - the only gate between the download and the
  extraction. True only when the hashes text parses, the file length
  matches the published size AND the SHA256 of the file bytes equals
  the published digest. Anything else (unreadable hashes, wrong size,
  wrong digest, unreadable zip) is False; never raises. }
function SUVerifyZipAgainstHashes(const AZipPath, AHashesText: string): Boolean;

{ Extract the archive only when EVERY entry destination resolves inside
  the staging directory (case-insensitive containment). The WHOLE
  archive refuses when any entry violates - never per-entry extraction
  (T-29-05). Directory entries (trailing '/') extract as nothing; their
  names still pass the guard. Every failure returns False. }
function SUExtractGuarded(const AZipPath, AStageDir: string): Boolean;

{ The accept continuation, always entered from the main thread (the
  offer dialog marshals there). Decision-for-decision port of
  UpdateInstall.RunAsync: %TEMP%\WsusOfflineNext-Update staging root,
  download-start/complete, fail-closed verify (hash-mismatch), guarded
  extraction (extraction-rejected), the three-exe staging completeness
  assert (incomplete-staging-tree), the minted healthy-launch marker
  path, the updater handoff with the frozen CLI (updater-launched /
  updater-missing), and the restart-now dialog (auto-Yes under
  WSON_UPDATE_AUTO_ACCEPT=1 via the registered host-close hook). Every
  failure path logs a named event with the actor, leaves the
  application running and changes nothing on disk outside %TEMP%. }
procedure SUInstallAccepted(const AActor: string; const AOffer: TSUUpdateOffer);

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
    FZipUrl: string;
    FHashesUrl: string;
    procedure DoOfferDialog; { runs on the main thread via Synchronize }
  protected
    procedure Execute; override;
  public
    constructor Create(const AIniPath, AActor: string);
  end;

implementation

uses
  enginecontracts, Process, zipper;

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

{ ROOT CAUSE (plan 29-02, resolves ledger entry 23): the earlier
  console-channel hazard was NOT heap corruption. Probe matrix in
  .planning/tmp/29-02-rootcause (probes 9-13): running the bcrypt
  sequence with FPC try/finally exception frames ACTIVE ACROSS the
  calls corrupts the exception-dispatch state on this FPC 3.2.2 i386
  lane - the next raised exception then dies inside dispatch at a fixed
  stack-top address (garbage handler, exit 217). With ZERO frames
  spanning the CNG calls the identical sequence is deterministic and
  correct in every combination (with/without console pre-writes, with
  caller-level frames). This implementation therefore: opens the file
  through raw Win32 (no exceptions possible inside), checks every
  NTSTATUS, frees through one staged teardown, and has no try block in
  the whole body - nothing can raise while bcrypt is in flight. }
function SUSha256File(const APath: string; out AHexLower: string): Boolean;
const
  ChunkSize = 65536;
  HexChars = '0123456789abcdef';
var
  HAlg, HHash, HashObj, Buf: Pointer;
  HFile: THandle;
  HashBytes: array[0..31] of Byte;
  Read: DWORD;
  I: Integer;
  Status: LongInt;
  ObjLen, ResultLen: DWORD;
  Ok: Boolean;
begin
  Result := False;
  AHexLower := '';
  HAlg := nil;
  HHash := nil;
  HashObj := nil;
  Buf := nil;
  HFile := INVALID_HANDLE_VALUE;
  Ok := False;
  if not SULoadBcrypt then
    Exit;
  HFile := Windows.CreateFileW(PWideChar(WideString(APath)), GENERIC_READ,
    FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if HFile = INVALID_HANDLE_VALUE then
    Exit;
  { ---- CNG section: NO try/finally may span these calls ---- }
  Status := SUBcryptOpenAlgorithmProvider(@HAlg,
    PWideChar(WideString('SHA256')), nil, 0);
  if Status >= 0 then
  begin
    ObjLen := 0;
    ResultLen := 0;
    Status := SUBcryptGetProperty(HAlg,
      PWideChar(WideString('ObjectLength')), @ObjLen, SizeOf(ObjLen),
      ResultLen, 0);
    if (Status >= 0) and (ObjLen > 0) then
    begin
      GetMem(HashObj, ObjLen + 4096); { slack: some CNG builds overrun ObjectLength }
      Status := SUBcryptCreateHash(HAlg, @HHash, HashObj, ObjLen, nil, 0, 0);
      if Status >= 0 then
      begin
        GetMem(Buf, ChunkSize + 4096); { slack, same overrun guard }
        repeat
          if not Windows.ReadFile(HFile, Buf^, ChunkSize, Read, nil) then
            Break;
          if Read > 0 then
          begin
            Status := SUBcryptHashData(HHash, Buf, Read, 0);
            if Status < 0 then
              Break;
          end;
        until Read < ChunkSize;
        if Status >= 0 then
        begin
          Status := SUBcryptFinishHash(HHash, @HashBytes[0],
            SizeOf(HashBytes), 0);
          if Status >= 0 then
          begin
            for I := 0 to SizeOf(HashBytes) - 1 do
              AHexLower := AHexLower + HexChars[1 + (HashBytes[I] shr 4)]
                + HexChars[1 + (HashBytes[I] and $F)];
            Ok := True;
          end;
        end;
      end;
    end;
  end;
  { ---- single staged teardown, still frame-free ---- }
  if Buf <> nil then
    FreeMem(Buf, ChunkSize + 4096);
  if HHash <> nil then
    SUBcryptDestroyHash(HHash, 0);
  if HashObj <> nil then
    FreeMem(HashObj);
  if HAlg <> nil then
    SUBcryptCloseAlgorithmProvider(HAlg, 0);
  Windows.CloseHandle(HFile);
  Result := Ok;
end;

{ ===== accept pipeline (plan 29-02, UpdateInstall.cs parity) ===== }

procedure SURegisterHostClose(AProc: TSUHostCloseProc);
begin
  SUHostCloseProc := AProc;
end;

{ Close the host so the process exits and the waiting updater proceeds
  (the frozen Phase 28 swap cue). No-op when the host never registered. }
procedure SURequestHostClose;
begin
  if Assigned(SUHostCloseProc) then
    SUHostCloseProc;
end;

{ Native size of a file through raw Win32 (no exceptions). }
function SUFileSizeOf(const APath: string; out ASize: Int64): Boolean;
var
  H: THandle;
  Lo, Hi: DWORD;
begin
  Result := False;
  ASize := 0;
  H := Windows.CreateFileW(PWideChar(WideString(APath)), GENERIC_READ,
    FILE_SHARE_READ, nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if H = INVALID_HANDLE_VALUE then
    Exit;
  Lo := Windows.GetFileSize(H, @Hi);
  Windows.CloseHandle(H);
  if (Lo = DWORD($FFFFFFFF)) and (Windows.GetLastError <> 0) then
    Exit;
  ASize := (Int64(Hi) shl 32) or Int64(Lo);
  Result := True;
end;

function SUParseHashesFile(const AText: string; out ASize: Int64;
  out ASHA256: string): Boolean;
var
  Rest, Line, DataLine, S, Field: string;
  P, Nf, I: Integer;
  V: Int64;
begin
  Result := False;
  ASize := 0;
  ASHA256 := '';
  { Ordinal parity with the .NET parser: no BOM strip here - a BOM
    before the first header makes that line a data line, which rejects
    (same verdict as .NET reading the bytes via GetStringAsync). }
  Rest := AText;
  DataLine := '';
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
    { .NET: Trim('\r').Trim() }
    while (Length(Line) > 0) and (Line[Length(Line)] = #13) do
      SetLength(Line, Length(Line) - 1);
    Line := SUTrimWs(Line);
    if Line = '' then
      Continue;
    if Pos('%%%%', Line) = 1 then
      Continue;
    if Pos('##', Line) = 1 then
      Continue;
    if DataLine <> '' then
      Exit; { more than one data line }
    DataLine := Line;
  end;
  if DataLine = '' then
    Exit;
  { A trailing comma means an empty last field in the .NET Split(',') -
    reject exactly like it. }
  if DataLine[Length(DataLine)] = ',' then
    Exit;
  { Split by ',' - at least 4 fields, all non-empty, field 0 numeric
    > 0, field 3 exactly 64 lowercase hex (char by char - Ordinal). }
  Nf := 0;
  V := 0;
  ASHA256 := '';
  S := DataLine;
  while S <> '' do
  begin
    P := Pos(',', S);
    if P = 0 then
    begin
      Field := S;
      S := '';
    end
    else
    begin
      Field := Copy(S, 1, P - 1);
      S := Copy(S, P + 1, MaxInt);
    end;
    Inc(Nf);
    if Field = '' then
      Exit; { an empty field anywhere rejects }
    if Nf = 1 then
    begin
      { field 0 - the size }
      if not TryStrToInt64(Field, V) then
        Exit;
      if V <= 0 then
        Exit;
    end
    else if Nf = 4 then
    begin
      { field 3 - the SHA256 }
      if Length(Field) <> 64 then
        Exit;
      for I := 1 to 64 do
        if not (Field[I] in ['0'..'9', 'a'..'f']) then
          Exit;
      ASHA256 := Field;
    end;
  end;
  if Nf < 4 then
    Exit;
  ASize := V;
  Result := ASHA256 <> '';
end;

{ Streaming zip download - the SUFetchText loop with a 30s per-step
  receive budget (UpdateInstall.cs: a 10s HttpClient timeout cannot
  carry a multi-hundred-megabyte download on slow links; 30s per read
  step aborts a stalled link, never a slow-but-flowing one). Status
  must be 200; every failure returns False. }
function SUDownloadToFile(const AUrl, ADestPath: string): Boolean;
var
  Session, Connect, Request: Pointer;
  Scheme, Host, ObjectPath: string;
  Port: DWORD;
  WHost, WVerb, WPath, WDest: WideString;
  Secure: Boolean;
  Status, StatusLen: DWORD;
  Avail, ReadBytes: DWORD;
  Chunk: AnsiString;
  Fs: TFileStream;
begin
  Result := False;
  if not SUSplitUrl(AUrl, Scheme, Host, Port, ObjectPath) then
    Exit;
  Secure := SameText(Scheme, 'https');
  WVerb := 'GET';
  WHost := Host;
  WPath := ObjectPath;
  WDest := ADestPath;
  Fs := nil;
  Session := WinHttpOpen(PWideChar(WideString('WsusOfflineNext-selfupdate')),
    SUWINHTTPACCESSTYPEDEFAULTPROXY, nil, nil, 0);
  if Session = nil then
    Exit;
  try
    { 30s resolve/connect/send/receive per step - the download budget. }
    WinHttpSetTimeouts(Session, 30000, 30000, 30000, 30000);
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
        try
          Fs := TFileStream.Create(ADestPath, fmCreate or fmShareDenyWrite);
        except
          Fs := nil;
          Exit;
        end;
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
          Fs.WriteBuffer(Chunk[1], Length(Chunk));
        until False;
        Result := True;
      finally
        WinHttpCloseHandle(Request);
      end;
    finally
      WinHttpCloseHandle(Connect);
    end;
  finally
    WinHttpCloseHandle(Session);
    Fs.Free;
  end;
end;

function SUVerifyZipAgainstHashes(const AZipPath, AHashesText: string): Boolean;
var
  PublishedSize, FileSize: Int64;
  PublishedSha, Hex: string;
begin
  Result := False;
  try
    if not SUParseHashesFile(AHashesText, PublishedSize, PublishedSha) then
      Exit;
    if not SUFileSizeOf(AZipPath, FileSize) then
      Exit;
    if FileSize <> PublishedSize then
      Exit;
    if not SUSha256File(AZipPath, Hex) then
      Exit;
    Result := (Hex = PublishedSha);
  except
    Result := False; { unreadable zip fails closed, never raises }
  end;
end;

{ Destination resolver behind the zip-slip guard - the twin of
  GetFullPath(Path.Combine(stageDir, entry.FullName)). Returns the
  resolved absolute destination, or '' when the name resolves OUTSIDE
  the staging directory (refuse). }
function SUGuardResolveDestination(const AStageExpanded,
  AEntryName: string): string;
var
  Name, Base, Seg: string;
  Segs, Stack: TStringList;
  I: Integer;
begin
  Result := '';
  Name := StringReplace(AEntryName, '/', '\', [rfReplaceAll]);
  if Pos('\\', Name) = 1 then
    Exit; { a UNC destination is outside by construction }
  Base := ExcludeTrailingPathDelimiter(AStageExpanded);
  if (Length(Name) >= 2) and (Name[2] = ':') then
    Result := Name { drive-absolute - Path.Combine keeps it }
  else if (Length(Name) >= 1) and (Name[1] = '\') then
    Result := Copy(Base, 1, 2) + Name { drive-rooted - the stage's drive }
  else
    Result := Base + '\' + Name;
  { Resolve '.' and '..' segments left-to-right with a stack
    (GetFullPath semantics); '..' above the drive root refuses. }
  Segs := TStringList.Create;
  Stack := TStringList.Create;
  try
    Segs.StrictDelimiter := True;
    Segs.Delimiter := '\';
    Segs.DelimitedText := Result;
    for I := 0 to Segs.Count - 1 do
    begin
      Seg := Segs[I];
      if (Seg = '') or (Seg = '.') then
        Continue;
      if Seg = '..' then
      begin
        if Stack.Count <= 1 then
          Exit; { '..' resolves at/above the drive root - outside }
        Stack.Delete(Stack.Count - 1);
      end
      else
        Stack.Add(Seg);
    end;
    Result := '';
    for I := 0 to Stack.Count - 1 do
    begin
      if I > 0 then
        Result := Result + '\';
      Result := Result + Stack[I];
    end;
  finally
    Stack.Free;
    Segs.Free;
  end;
  { Containment: equal to the stage or below it (case-insensitive). }
  if SameText(Result, AStageExpanded) then
    Exit;
  if (Length(Result) > Length(AStageExpanded))
     and SameText(Copy(Result, 1, Length(AStageExpanded) + 1),
           AStageExpanded + '\') then
    Exit;
  Result := ''; { outside - refuse }
end;

{ Guarded extraction: enumerate every entry FIRST and refuse the WHOLE
  archive when any destination would resolve outside the staging
  directory (zip-slip, T-29-05). Only then extract - through the FCL
  zipper (TUnZipper, pure-Pascal inflate; no bin\unzip.exe dependency).
  The whole archive refuses, never single entries. }
function SUExtractGuarded(const AZipPath, AStageDir: string): Boolean;
var
  U: TUnZipper;
  I: Integer;
  Dest: string;
  StageExpanded: string;
begin
  Result := False;
  if not FileExists(AZipPath) then
    Exit;
  StageExpanded := ExpandFileName(AStageDir);
  U := TUnZipper.Create;
  try
    try
      U.FileName := AZipPath;
      U.Examine;
      { WHOLE-ARCHIVE GUARD FIRST: every entry (directories included)
        must resolve inside the staging directory. }
      for I := 0 to U.Entries.Count - 1 do
      begin
        Dest := SUGuardResolveDestination(StageExpanded,
          U.Entries[I].ArchiveFileName);
        if Dest = '' then
          Exit; { one bad entry refuses the whole archive }
      end;
      ForceDirectories(AStageDir);
      U.OutputPath := IncludeTrailingPathDelimiter(AStageDir);
      U.UnZipAllFiles;
      Result := True;
    except
      Result := False; { unreadable archive extracts nothing }
    end;
  finally
    U.Free;
  end;
end;

{ Best-effort deletes (temp cleanup never blocks the accept path). }
procedure SUTryDelete(const APath: string);
begin
  try
    if FileExists(APath) then
      SysUtils.DeleteFile(APath);
  except
  end;
end;

procedure SUTryDeleteDir(const APath: string);
begin
  try
    if DirectoryExists(APath) then
      RemoveDir(APath);
  except
  end;
end;

{ The named warning box over the title 'WSUS Offline Next' - same
  wording as the .NET MessageBox calls in UpdateInstall.RunAsync. }
procedure SUAcceptWarning(const AText: string);
var
  WText, WTitle: WideString;
begin
  WTitle := 'WSUS Offline Next';
  WText := AText;
  SUMessageBoxW(0, PWideChar(WText), PWideChar(WTitle),
    MB_TASKMODAL or MB_ICONWARNING or MB_OK);
end;

procedure SUInstallAccepted(const AActor: string; const AOffer: TSUUpdateOffer);
var
  StagingRoot, Stamp, ZipPath, StageDir: string;
  HashesText: string;
  StagedRoot, ExeDir, RootDir, InstallRoot, UpdaterPath: string;
  MarkerPath, G: string;
  RootTrimmed, RootName, RootParent, BackupDir: string;
  Updater: TProcess;
  GUID: TGUID;
begin
  try
    { Staging root + stamp (UpdateInstall.cs 124-128; the stamp is a
      local timestamp here - the value is only a unique temp name). }
    StagingRoot := IncludeTrailingPathDelimiter(EngCallerTempDir)
      + 'WsusOfflineNext-Update';
    ForceDirectories(StagingRoot);
    Stamp := FormatDateTime('yymmddhhnnsszzz', Now);
    ZipPath := StagingRoot + '\update-' + Stamp + '.zip';
    StageDir := StagingRoot + '\stage-' + Stamp;

    SULogAppend(AActor, 'download-start');
    { The hashes text first (small fetch), then the zip (streamed). A
      failed fetch is an exception in .NET (GetStringAsync) - the same
      install-error outcome here. }
    if not SUFetchText(AOffer.HashesUrl, SUFetchTimeoutMs, HashesText) then
    begin
      SULogAppend(AActor, 'install-error');
      SUAcceptWarning('The update could not be completed.' + #13#10 +
        'Nothing was changed - the application continues normally.');
      Exit;
    end;
    if not SUDownloadToFile(AOffer.ZipUrl, ZipPath) then
    begin
      SULogAppend(AActor, 'install-error');
      SUAcceptWarning('The update could not be completed.' + #13#10 +
        'Nothing was changed - the application continues normally.');
      Exit;
    end;
    SULogAppend(AActor, 'download-complete');

    { Fail-closed verification: nothing is extracted, the zip is
      deleted and the app continues normally. }
    if not SUVerifyZipAgainstHashes(ZipPath, HashesText) then
    begin
      SULogAppend(AActor, 'hash-mismatch');
      SUTryDelete(ZipPath);
      SUAcceptWarning('Verification of the downloaded update failed.' + #13#10 +
        'Nothing was changed - the application continues normally.');
      Exit;
    end;
    SULogAppend(AActor, 'hash-verified');

    { Guarded extraction: enumerate-first whole-archive zip-slip
      refusal (T-29-05). }
    if not SUExtractGuarded(ZipPath, StageDir) then
    begin
      SULogAppend(AActor, 'extraction-rejected');
      SUTryDelete(ZipPath);
      SUAcceptWarning('The downloaded update was rejected.' + #13#10 +
        'Nothing was changed - the application continues normally.');
      Exit;
    end;

    { Staging completeness: the new tree must carry all THREE
      application executables before anything is applied
      (UpdateInstall.cs:179-181 - case-for-case parity). }
    StagedRoot := IncludeTrailingPathDelimiter(StageDir) + 'wsusoffline';
    if (not FileExists(StagedRoot + '\UpdateGeneratorModern.exe'))
       or (not FileExists(StagedRoot + '\client\UpdateInstallerModern.exe'))
       or (not FileExists(StagedRoot + '\WsusOfflineUpdater.exe')) then
    begin
      SULogAppend(AActor, 'incomplete-staging-tree');
      SUTryDelete(ZipPath);
      SUTryDeleteDir(StageDir);
      SUAcceptWarning('The downloaded update is incomplete.' + #13#10 +
        'Nothing was changed - the application continues normally.');
      Exit;
    end;
    SULogAppend(AActor, 'staged');
    SUTryDelete(ZipPath); { the staged tree is now the source of truth }

    { Healthy-marker path is MINTED here; the marker file itself is
      only written by the relaunched app after its window shows. }
    CreateGUID(GUID);
    { GUIDToString yields XX-... wrapped in braces - strip them. }
    G := GUIDToString(GUID);
    G := AnsiLowerCase(Copy(G, 2, Length(G) - 2));
    ForceDirectories(SUStateRoot);
    MarkerPath := SUStateRoot + '\launch-' + G + '.ok';

    { The updater lives at the install root: the PARENT of this exe's
      own directory (the native exe ships in client\). ParamStr(0) is
      the LCL-free twin of Application.ExeName. }
    ExeDir := ExcludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)));
    RootDir := ExtractFilePath(ExeDir);          { the install root + '\' }
    InstallRoot := ExcludeTrailingPathDelimiter(RootDir);
    UpdaterPath := InstallRoot + '\WsusOfflineUpdater.exe';
    if not FileExists(UpdaterPath) then
    begin
      SULogAppend(AActor, 'updater-missing');
      SUAcceptWarning('The updater component is missing from this installation.' +
        #13#10 + 'Nothing was changed - the application continues normally.');
      Exit;
    end;

    { Backup dir (UpdateInstall.cs:212-220 parity): beside the install
      root as <root>.bak-<timestamp>, with the %TEMP% staging fallback
      when the root cannot be derived. }
    RootTrimmed := InstallRoot;
    RootName := ExtractFileName(RootTrimmed);
    RootParent := ExtractFilePath(RootTrimmed); { ends with '\' }
    if (RootName <> '') and (RootParent <> '') then
      BackupDir := RootParent + RootName + '.bak-'
        + FormatDateTime('yyyymmdd-hhnnss', Now)
    else
      BackupDir := StagingRoot + '\backup-'
        + FormatDateTime('yyyymmdd-hhnnss', Now);

    { The handoff - the frozen Phase 28 CLI, parsed by the updater at
      Program.cs 525-541. TProcess quotes whitespace-bearing arguments
      itself (MaybeQuoteIfNotQuoted); channel-controlled data never
      reaches this command line - only local paths and the own pid
      (T-29-06). The updater is asInvoker (28-02: manifest count 1):
      launched from this elevated process it inherits elevation with
      no new UAC prompt (SC4). }
    Updater := TProcess.Create(nil);
    try
      Updater.Executable := UpdaterPath;
      Updater.Parameters.Add('--pid');
      Updater.Parameters.Add(IntToStr(Windows.GetCurrentProcessId));
      Updater.Parameters.Add('--staging');
      Updater.Parameters.Add(StageDir);
      Updater.Parameters.Add('--backup');
      Updater.Parameters.Add(BackupDir);
      Updater.Parameters.Add('--relaunch');
      Updater.Parameters.Add(ParamStr(0));
      Updater.Parameters.Add('--marker');
      Updater.Parameters.Add(MarkerPath);
      Updater.Options := [poNoConsole];
      Updater.Execute;
    finally
      Updater.Free;
    end;
    SULogAppend(AActor, 'updater-launched');

    { Same test / Phase 30 harness hook as the offer dialog: auto-answer
      Yes so the application closes itself and the waiting updater
      proceeds (no dialog a headless harness would have to click). }
    if SUEnv('WSON_UPDATE_AUTO_ACCEPT') = '1' then
      SURequestHostClose
    else if SUMessageBoxW(0,
        PWideChar(WideString('Update downloaded and verified.' + #13#10 +
          'It will be applied when this application closes.' + #13#10#13#10 +
          'Restart now?')),
        PWideChar(WideString('WSUS Offline Next')),
        MB_TASKMODAL or MB_ICONINFORMATION or MB_YESNO) = IDYES then
      SURequestHostClose;
  except
    { Same silent-failure discipline as the check slice: a named error
      event, the app keeps running, nothing was applied. }
    SULogAppend(AActor, 'install-error');
    SUAcceptWarning('The update could not be completed.' + #13#10 +
      'Nothing was changed - the application continues normally.');
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
  FZipUrl := '';
  FHashesUrl := '';
  FreeOnTerminate := True;
  Start;
end;

procedure TSelfUpdateCheckThread.DoOfferDialog;
var
  WText, WTitle: WideString;
  Choice: Integer;
  Offer: TSUUpdateOffer;
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
      { The accept continuation (plan 29-02): verified download,
        fail-closed SHA256, guarded extraction, staging, updater
        handoff - UpdateInstall.RunAsync parity. Every failure path
        inside logs a named event and leaves the app running. }
      Offer.ChannelVersion := FChannelVersion;
      Offer.ZipUrl := FZipUrl;
      Offer.HashesUrl := FHashesUrl;
      SUInstallAccepted(FActor, Offer);
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
    { 12. The offer on the main thread (OfferGuard latch inside); the
       offer carries the real URLs (the accept continuation needs them). }
    FLocalVersion := LocalVersion;
    FZipUrl := ZipUrl;
    FHashesUrl := HashesUrl;
    Synchronize(@DoOfferDialog);
  except
    { silent-failure discipline: any network or parse error logs
      check-error and leaves the launch path untouched }
    SULogAppend(FActor, 'check-error');
  end;
end;

end.
