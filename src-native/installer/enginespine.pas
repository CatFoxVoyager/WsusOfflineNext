{*** Observation spine: the native GUI's TProcess orchestration of the engine.

    Spawns cmd /D /C "DoUpdate.cmd <switches>" (absolute cmd.exe path from
    enginecontracts, cwd = the client cmd dir), pumps BOTH pipes inside the
    run loop (poUsePipes + poNoConsole, never poWaitOnExit - research
    Pitfall B), feeds each completed stdout/stderr line to an OnLine
    callback, exposes a WatchOutcomeFiles hook (timer-wired in a later plan),
    a Cancel->terminate path, and mode-aware completion: abrupt child death
    with /autoreboot or /shutdown in the argv IS the success path (research
    Pitfall C).

    Engine console output arrives as OEM-codepage bytes; lines are decoded
    with the OEM codepage for display (26-RESEARCH.md Pattern 6). }

unit enginespine;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Pipes, Process,
  enginecontracts;

const
  { Pipe-pump cadence (ms). }
  SPINE_PUMP_DELAY_MS = 100;

type
  TSpineLineEvent = procedure(const ALine: string) of object;
  TSpineIdleEvent = procedure of object;
  TSpineWatchEvent = procedure of object;

  { Outcome of one spine run. ExitCode >= 0 with Observed=True means an
    integer engine exit code was observed (the 0/1/3010/3011 handshake);
    Observed=False with ExitCode=-1 means no engine verdict exists (spawn
    failure or watchdog abort - TimedOut distinguishes the watchdog case).
    Canceled=True marks a user-cancel kill - the summary reports the
    canceled state regardless of any exit code the kill produced. }
  TSpineResult = record
    ExitCode: Integer;
    Observed: Boolean;
    TimedOut: Boolean;
    Canceled: Boolean;
    LineCount: Integer;
  end;

  TEngineSpine = class
  private
    FOnLine: TSpineLineEvent;
    FOnIdle: TSpineIdleEvent;
    FOnWatch: TSpineWatchEvent;
    FCancelRequested: Boolean;
    FProcess: TProcess;
    FOutBuf: AnsiString;
    FErrBuf: AnsiString;
    FLineCount: Integer;
    procedure PumpStream(AStream: TInputPipeStream; var ABuf: AnsiString);
    procedure EmitCompleteLines(var ABuf: AnsiString);
    procedure FlushRemainder(var ABuf: AnsiString);
    procedure DoLine(const ARaw: AnsiString);
    procedure CancelChild;
  public
    { Spawn the engine, stream its output, return its outcome. ATimeoutMs=0
      means unbounded (the GUI trusts the engine's own lifetime); the
      headless probe passes a watchdog budget and must treat TimedOut as a
      probe failure. Returns True when the run completed cleanly (an exit
      code was observed, or the abrupt-death finish modes apply). }
    function Run(const ACmdDir: string; const ASwitches: string;
      ATimeoutMs: LongWord; out AResult: TSpineResult): Boolean;
    { Request cancellation; the run loop terminates the child on its next
      pump tick. }
    procedure Cancel;
    property OnLine: TSpineLineEvent read FOnLine write FOnLine;
    property OnIdle: TSpineIdleEvent read FOnIdle write FOnIdle;
    property OnWatch: TSpineWatchEvent read FOnWatch write FOnWatch;
  end;

{ Pure completion-mode core (unit-testable): when one of the finish modes
  is in the argv, the child is killed mid-stream by the machine's own
  shutdown - "terminated abruptly" IS the success path. }
function SpineAbruptDeathIsSuccess(const ASwitches: string): Boolean;

{ Complete outcome classification of one spine run (unit-testable matrix):
  the engine handshake (0 / 1 / 3010 / 3011) mapped onto the GUI's summary
  states, combined with the finish modes and the cancellation flag.
  Precedence: cancel wins (the child was killed on purpose); then abrupt
  death in a finish mode = success (Pitfall C); then no observed exit =
  no verdict; then the integer handshake. }
type
  TSpineOutcomeKind = (
    soCompleted,         { exit 0 }
    soError,             { exit 1 or any other integer }
    soRebootRequired,    { exit 3010 }
    soRecall,            { exit 3011 }
    soAbruptFinishSuccess, { died mid-run under /autoreboot|/shutdown }
    soCanceled,          { user cancel killed the child }
    soNoVerdict);        { spawn failure / watchdog without finish mode }
function SpineOutcomeKind(const ASwitches: string; AObserved: Boolean;
  AExitCode: Integer; ACanceled: Boolean): TSpineOutcomeKind;

{ Per-update progress parser (unit-testable): recognizes the engine's
  stdout shape '!TIME! - Installing update N of M (stage size: ...)'
  (InstallListedUpdates.cmd:44,59) and exposes (N, M). Unknown lines pass
  through to the pane untouched - the parser never consumes them. }
function SpineParseProgressLine(const ALine: string;
  out ANum, ACount: Integer): Boolean;

{ Live outcome counts over the five wou_*.txt files (DoUpdate.cmd:53-58;
  appended by the engine during the run). Absent file = 0 for that
  compartment. The GUI calls this on every pump tick via OnWatch. }
type
  TSpineOutcomeCounts = record
    Installed, Failed, Corrupt, CleanSkipped, VerificationSkipped: Integer;
  end;
function SpineCountFileLines(const APath: string): Integer;
function SpineReadOutcomeCounts(const ATempDir: string): TSpineOutcomeCounts;

{ Audit report parser (unit-testable): the 5 compartments (LCU / SSU /
  Defender / Office / Runtimes) plus the optional Other compartment, the
  Total line and the Audit Result line, from MissingUpdates.txt
  (DoUpdate.cmd:2607-2614 emission shape). Returns True when at least the
  Total line and one compartment header were recognized. }
type
  TSpineAuditCounts = record
    Total, Lcu, Ssu, Defender, Office, Runtimes, Other: Integer;
    ResultLine: string;
  end;
function SpineParseAuditReport(ALines: TStrings;
  out ACounts: TSpineAuditCounts): Boolean;

{ Decode raw OEM console bytes into display text (UTF-8 for the LCL). }
function SpineOemToDisplay(const ARaw: AnsiString): string;

implementation

function SpineAbruptDeathIsSuccess(const ASwitches: string): Boolean;
begin
  Result := (Pos('/autoreboot', ASwitches) > 0)
    or (Pos('/shutdown', ASwitches) > 0);
end;

function SpineOutcomeKind(const ASwitches: string; AObserved: Boolean;
  AExitCode: Integer; ACanceled: Boolean): TSpineOutcomeKind;
begin
  if ACanceled then
    Exit(soCanceled);
  if not AObserved then
  begin
    if SpineAbruptDeathIsSuccess(ASwitches) then
      Exit(soAbruptFinishSuccess);
    Exit(soNoVerdict);
  end;
  case AExitCode of
    ENG_EXIT_OK: Result := soCompleted;
    ENG_EXIT_REBOOT_REQUIRED: Result := soRebootRequired;
    ENG_EXIT_RECALL: Result := soRecall;
    else Result := soError;
  end;
end;

function ParseIntAt(const ALine: string; var APos: Integer;
  out AValue: Integer): Boolean;
var
  StartPos: Integer;
begin
  Result := False;
  AValue := 0;
  while (APos <= Length(ALine)) and
        ((ALine[APos] < '0') or (ALine[APos] > '9')) do
    Inc(APos);
  StartPos := APos;
  while (APos <= Length(ALine)) and
        (ALine[APos] >= '0') and (ALine[APos] <= '9') do
    Inc(APos);
  if APos = StartPos then
    Exit;
  AValue := StrToInt(Copy(ALine, StartPos, APos - StartPos));
  Result := True;
end;

function SpineParseProgressLine(const ALine: string;
  out ANum, ACount: Integer): Boolean;
var
  P: Integer;
begin
  Result := False;
  ANum := 0;
  ACount := 0;
  P := Pos('Installing update ', ALine);
  if P = 0 then
    Exit;
  P := P + Length('Installing update ');
  if not ParseIntAt(ALine, P, ANum) then
    Exit;
  { au3-parity: only the exact ' of ' separator counts. }
  if Copy(ALine, P, 4) <> ' of ' then
    Exit;
  Inc(P, 4);
  if not ParseIntAt(ALine, P, ACount) then
    Exit;
  Result := (ANum >= 1) and (ACount >= ANum);
end;

function SpineCountFileLines(const APath: string): Integer;
var
  Sl: TStringList;
begin
  Result := 0;
  if not FileExists(APath) then
    Exit;
  Sl := TStringList.Create;
  try
    try
      Sl.LoadFromFile(APath);
      Result := Sl.Count;
    except
      Result := 0;
    end;
  finally
    Sl.Free;
  end;
end;

function SpineReadOutcomeCounts(const ATempDir: string): TSpineOutcomeCounts;
var
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(ATempDir);
  Result.Installed := SpineCountFileLines(Base + ENG_OUTCOME_INSTALLED);
  Result.Failed := SpineCountFileLines(Base + ENG_OUTCOME_FAILED);
  Result.Corrupt := SpineCountFileLines(Base + ENG_OUTCOME_CORRUPT);
  Result.CleanSkipped := SpineCountFileLines(Base + ENG_OUTCOME_CLEAN_SKIPPED);
  Result.VerificationSkipped :=
    SpineCountFileLines(Base + ENG_OUTCOME_VERIFICATION_SKIPPED);
end;

function ExtractCountSuffix(const ALine: string): Integer;
var
  P: Integer;
begin
  Result := -1;
  P := Pos('[Count:', ALine);
  if P = 0 then
    Exit;
  Inc(P, Length('[Count:'));
  if not ParseIntAt(ALine, P, Result) then
    Result := -1;
end;

function SpineParseAuditReport(ALines: TStrings;
  out ACounts: TSpineAuditCounts): Boolean;
var
  I, V: Integer;
  Line: string;
  Compartments: Integer;
begin
  FillChar(ACounts, SizeOf(ACounts), 0);
  ACounts.ResultLine := '';
  Compartments := 0;
  for I := 0 to ALines.Count - 1 do
  begin
    Line := ALines.Strings[I];
    if Pos('Total Missing Items:', Line) > 0 then
    begin
      { The Total line shape is 'Total Missing Items:     N' - a plain
        integer after the colon, not a [Count: n] suffix. }
      V := StrToIntDef(Trim(Copy(Line,
        Pos(':', Line) + 1, MaxInt)), 0);
      ACounts.Total := V;
    end
    else if Pos('[Windows Cumulative', Line) > 0 then
    begin
      ACounts.Lcu := ExtractCountSuffix(Line);
      if ACounts.Lcu >= 0 then
        Inc(Compartments);
    end
    else if Pos('[Integrated Servicing Stack', Line) > 0 then
    begin
      ACounts.Ssu := ExtractCountSuffix(Line);
      if ACounts.Ssu >= 0 then
        Inc(Compartments);
    end
    else if Pos('[Windows Defender', Line) > 0 then
    begin
      ACounts.Defender := ExtractCountSuffix(Line);
      if ACounts.Defender >= 0 then
        Inc(Compartments);
    end
    else if Pos('[Microsoft Office Updates', Line) > 0 then
    begin
      ACounts.Office := ExtractCountSuffix(Line);
      if ACounts.Office >= 0 then
        Inc(Compartments);
    end
    else if Pos('[Modern Extras', Line) > 0 then
    begin
      ACounts.Runtimes := ExtractCountSuffix(Line);
      if ACounts.Runtimes >= 0 then
        Inc(Compartments);
    end
    else if Pos('[Other Components', Line) > 0 then
    begin
      ACounts.Other := ExtractCountSuffix(Line);
      if ACounts.Other >= 0 then
        Inc(Compartments);
    end
    else if Pos('Audit Result:', Line) > 0 then
      ACounts.ResultLine := Trim(Line);
  end;
  Result := (ACounts.Total >= 0) and (Compartments >= 1);
end;

function SpineOemToDisplay(const ARaw: AnsiString): string;
var
  Cp: Cardinal;
  W: WideString;
  WLen: Integer;
  U8Len: Integer;
begin
  Result := '';
  if Length(ARaw) = 0 then
    Exit;
  Cp := GetOEMCP();
  WLen := MultiByteToWideChar(Cp, 0, PAnsiChar(ARaw), Length(ARaw), nil, 0);
  if WLen <= 0 then
  begin
    { Keep the raw bytes rather than lose the line. }
    Result := ARaw;
    Exit;
  end;
  SetLength(W, WLen);
  MultiByteToWideChar(Cp, 0, PAnsiChar(ARaw), Length(ARaw), PWideChar(W), WLen);
  U8Len := WideCharToMultiByte(CP_UTF8, 0, PWideChar(W), WLen, nil, 0, nil, nil);
  if U8Len <= 0 then
  begin
    Result := ARaw;
    Exit;
  end;
  SetLength(Result, U8Len);
  WideCharToMultiByte(CP_UTF8, 0, PWideChar(W), WLen, PAnsiChar(Result), U8Len, nil, nil);
end;

procedure TEngineSpine.PumpStream(AStream: TInputPipeStream; var ABuf: AnsiString);
var
  Count: DWord;
  Chunk: AnsiString;
begin
  Count := AStream.NumBytesAvailable;
  if Count = 0 then
    Exit;
  SetLength(Chunk, Count);
  SetLength(Chunk, AStream.Read(Chunk[1], Count));
  if Length(Chunk) > 0 then
    ABuf := ABuf + Chunk;
end;

procedure TEngineSpine.EmitCompleteLines(var ABuf: AnsiString);
var
  P: Integer;
  Line: AnsiString;
begin
  repeat
    P := Pos(#10, ABuf);
    if P = 0 then
      Break;
    Line := Copy(ABuf, 1, P - 1);
    Delete(ABuf, 1, P);
    if (Length(Line) > 0) and (Line[Length(Line)] = #13) then
      SetLength(Line, Length(Line) - 1);
    DoLine(Line);
  until False;
end;

procedure TEngineSpine.FlushRemainder(var ABuf: AnsiString);
begin
  if Length(ABuf) > 0 then
  begin
    DoLine(ABuf);
    ABuf := '';
  end;
end;

procedure TEngineSpine.DoLine(const ARaw: AnsiString);
begin
  Inc(FLineCount);
  if Assigned(FOnLine) then
    FOnLine(SpineOemToDisplay(ARaw));
end;

procedure TEngineSpine.CancelChild;
begin
  if FProcess = nil then
    Exit;
  if FProcess.Running then
    FProcess.Terminate(1);
end;

procedure TEngineSpine.Cancel;
begin
  FCancelRequested := True;
end;

function TEngineSpine.Run(const ACmdDir: string; const ASwitches: string;
  ATimeoutMs: LongWord; out AResult: TSpineResult): Boolean;
var
  CmdExe: string;
  StartTick: DWord;
  FinalLines: Integer;
begin
  AResult.ExitCode := -1;
  AResult.Observed := False;
  AResult.TimedOut := False;
  AResult.Canceled := False;
  AResult.LineCount := 0;
  Result := False;
  FOutBuf := '';
  FErrBuf := '';
  FCancelRequested := False;
  FLineCount := 0;

  CmdExe := EngCmdExePath;
  if (CmdExe = '') or not FileExists(CmdExe) then
    Exit; { no absolute cmd.exe - fail closed (threat T-26-02) }

  FProcess := TProcess.Create(nil);
  try
    FProcess.Executable := CmdExe;
    FProcess.Parameters.Add('/D');
    FProcess.Parameters.Add('/C');
    { Pre-quoted as ONE parameter: fcl-process's MaybeQuoteIfNotQuoted passes
      an already-quoted parameter through untouched, so cmd.exe receives the
      exact payload ".\DoUpdate.cmd <switches>". The .\ prefix is required
      for the child's cwd-relative resolution: hosts hardening
      NoDefaultCurrentDirectoryInExePath (set on the dev machine) drop bare
      cwd-relative lookup, and the explicit prefix is standard resolution
      everywhere else. The engine anchors everything on %~dp0, so the path
      spelling does not touch the frozen contract. }
    FProcess.Parameters.Add('".\DoUpdate.cmd ' + ASwitches + '"');
    FProcess.CurrentDirectory := ACmdDir;
    FProcess.Options := [poUsePipes, poNoConsole];
    FProcess.Execute;

    StartTick := GetTickCount;
    while FProcess.Running do
    begin
      PumpStream(FProcess.Output, FOutBuf);
      PumpStream(FProcess.Stderr, FErrBuf);
      EmitCompleteLines(FOutBuf);
      EmitCompleteLines(FErrBuf);
      if Assigned(FOnWatch) then
        FOnWatch();
      if Assigned(FOnIdle) then
        FOnIdle();
      if FCancelRequested then
      begin
        AResult.Canceled := True;
        CancelChild;
        Break;
      end;
      if (ATimeoutMs > 0) and (GetTickCount - StartTick >= ATimeoutMs) then
      begin
        AResult.TimedOut := True;
        CancelChild;
        { Drain what already sits in the pipes before giving up. }
        PumpStream(FProcess.Output, FOutBuf);
        PumpStream(FProcess.Stderr, FErrBuf);
        Break;
      end;
      Sleep(SPINE_PUMP_DELAY_MS);
    end;

    { Final drain after the child is gone - the pipes may hold a last chunk. }
    PumpStream(FProcess.Output, FOutBuf);
    PumpStream(FProcess.Stderr, FErrBuf);
    EmitCompleteLines(FOutBuf);
    EmitCompleteLines(FErrBuf);
    FlushRemainder(FOutBuf);
    FlushRemainder(FErrBuf);

    FinalLines := FLineCount;
    if not AResult.TimedOut then
    begin
      AResult.ExitCode := FProcess.ExitCode;
      AResult.Observed := True;
    end;
    AResult.LineCount := FinalLines;
    Result := (not AResult.TimedOut)
      and (AResult.Observed or SpineAbruptDeathIsSuccess(ASwitches));
  finally
    FProcess.Free;
    FProcess := nil;
  end;
end;

end.
