{*** RunOnce-based reboot resume (INST-05) - the DESIGNED change versus
    the incumbent's Win10+ autoreboot dead-end.

    Microsoft Learn semantics (run-and-runonce-registry-keys, fetched
    2026-11-04): HKLM\...\RunOnce executes ONLY when members of the
    Administrators group log on after the reboot; a value name prefixed
    with '!' defers deletion until AFTER the command runs; the data value
    is a command line no longer than 260 characters.

    This unit:
    - builds the value (pure, unit-proven): name '!WOUResume', data
      '"<short exe path>" /resume' with a HARD refusal above 260 chars
      (threat T-26-06: the command line is the short trusted exe path +
      /resume only - no user-derived content);
    - registers/deletes it under HKLM;
    - answers the /resume startup decision: a run is pending when the
      engine staging in %SystemRoot%\Temp exists (WOUpdatesToInstall.txt
      present, SetWOUpdateStage deleted-on-read by the engine) OR the GUI's
      own pending marker (WOUResumePending.txt, written together with the
      RunOnce value) exists. The marker is what makes the reboots that
      happen BEFORE the engine stages anything (IE11 prerequisites and IE11,
      the SHA-2 pair, the agent refresh, .NET, WMF) resumable: the RunOnce is
      only registered when a reboot was explicitly part of a run, so its
      registration is the proof that a run was interrupted.

    There is NO second loop counter here: the engine's wourecall.1-9
    files stay the ONLY anti-loop guard (plan prohibition). }

unit resume;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Registry,
  enginecontracts;

const
  RES_RUNONCE_KEY = 'Software\Microsoft\Windows\CurrentVersion\RunOnce';
  { The leading '!' defers deletion until after the command runs. }
  RES_RUNONCE_NAME = '!WOUResume';
  RES_RUNONCE_MAX = 260; { Microsoft: command line <= 260 chars }
  RES_TASK_NAME = 'WOUResume';
  RES_RESUME_FLAG = '/resume';
  { GUI-written companion of the RunOnce value: written when it is
    registered, removed when it is deleted. Lives next to the engine staging
    but is NOT touched by the engine (its own cleanup names are wou_*.txt). }
  RES_PENDING_MARKER = 'WOUResumePending.txt';
  { The engine's OWN automatic recall (PrepareRecall.cmd: WOUTempAdmin
    autologon + a HKLM Run entry, legacy <= 8.1 with /autoreboot) keeps its
    script here until CleanupRecall removes the directory. While it exists
    the engine resumes the run by itself. }
  RES_ENGINE_RECALL_REL = 'WOURecall\RecallUpdate.cmd';
  { The ENGINE-owned upgrade-in-progress marker (Phase 35, RECALL-01):
    posed by DoUpdate.cmd beside its launch record before every setup.exe
    launch, cleared only at the observed-build convergence and the stall
    halt. The GUI READS it - it never writes or deletes it (ownership
    boundary, like the staging constants above). While it stands,
    setup.exe owns the machine. }
  RES_UPGRADE_MARKER = 'wou_upgrade_in_progress.txt';

{ Pure builder (unit-proven): AName = '!WOUResume'; AData = the quoted
  exe path (short-path spelling when the file exists and 8.3 names are
  enabled) + ' /resume'. Returns False and leaves AData EMPTY when the
  composed command line would exceed RES_RUNONCE_MAX - callers must
  refuse to register. }
function ResBuildRunOnceValue(const AExePath: string;
  out AName, AData: string): Boolean;

{ Build + write under HKLM\...\RunOnce (KEY_WRITE). Returns True only
  when the builder AND the registry write succeeded. }
function ResRegisterResume(const AExePath: string): Boolean;

{ GUI-side cleanup (threat T-26-06): the value is deleted on successful
  resume AND on cancel/decline - never left dangling beyond the run. }
procedure ResDeleteResume;

{ Persistent state directory surviving Windows feature upgrades
  (%ProgramData%\WSUSOffline, falling back to EngEngineTempDir when
  ProgramData is unset). }
function ResPersistDir: string;

{ True when '/resume' appears in the command-line parameters. }
function ResWantsResume: Boolean;

{ The engine staging probe (pure inputs): WOUpdatesToInstall.txt present
  in the staging dir = a stage continues. SetWOUpdateStage.cmd is
  deleted-on-read by the engine, so its presence also marks staging.
  ResStagingPresent applies it to the frozen %SystemRoot%\Temp location. }
function ResStagingPresentIn(const ADir: string): Boolean;
function ResStagingPresent: Boolean;

{ Pending-marker lifecycle (pure inputs: the directory is a parameter, the
  production wrappers pass the frozen %SystemRoot%\Temp location). }
function ResMarkerWriteIn(const ADir: string): Boolean;
procedure ResMarkerDeleteIn(const ADir: string);
function ResMarkerPresentIn(const ADir: string): Boolean;

{ The /resume startup decision: staging present OR marker present. Evaluate
  it BEFORE ResDeleteResume, which also removes the marker. }
function ResResumePendingIn(const ADir: string): Boolean;
function ResResumePending: Boolean;

{ True while the engine's own automatic recall is prepared (legacy <= 8.1,
  /autoreboot): the engine itself continues the run after the reboot, so the
  GUI's RunOnce resume must stay OUT - it runs BEFORE the Run-key recall and
  a modal dialog, a UAC prompt or a second engine instance there blocks or
  duplicates the very continuation it is supposed to provide. }
function ResEngineRecallPreparedIn(const ADir: string): Boolean;
function ResEngineRecallPrepared: Boolean;

{ The upgrade-in-progress marker probe (Phase 35, RECALL-01). ENGINE-owned
  state: the GUI reads it, never writes or deletes it. }
function ResUpgradeInProgressIn(const ADir: string): Boolean;
function ResUpgradeInProgress: Boolean;

{ The marker's target build: field 2 of line 1 (CSV `full,<target>,<rev>`,
  DEC-35-05). A missing, empty or malformed marker parses as 0 - the
  lenient reader never raises; the decision below fails closed on it. }
function ResUpgradeMarkerTargetIn(const ADir: string): Integer;
function ResUpgradeMarkerTarget: Integer;

{ The /resume decision for the upgrade marker: False when the marker is
  absent (today's behaviour, degrade-silently); True when the parsed
  target is unusable (<= 0) or the observed build differs from it - the
  machine is either still setup.exe-owned or awaiting the engine's own
  stall-halt restore. A converged machine (observed build = target) is
  NOT blocked: the caller falls through so StartRun re-enters the engine
  and the convergence branch clears the marker. NO counter is added here:
  the engine's wourecall.1-9 rotation and the attempts record stay the
  only loop protection (installer.lpr verbatim rule). }
function ResUpgradeResumeBlockedIn(const ADir: string;
  const AObservedBuild: Integer): Boolean;
function ResUpgradeResumeBlocked(const AObservedBuild: Integer): Boolean;

implementation

function ResBuildRunOnceValue(const AExePath: string;
  out AName, AData: string): Boolean;
var
  ShortPath: string;
  Buf: WideString;
  Len: Integer;
begin
  AName := RES_RUNONCE_NAME;
  AData := '';
  ShortPath := AExePath;
  { Short-path spelling keeps the command line far under the 260-char
    limit on real installs; when 8.3 names are disabled (or the file does
    not exist yet - the unit-test path) the long path is used as-is and
    the hard guard decides. }
  SetLength(Buf, MAX_PATH);
  Len := GetShortPathNameW(PWideChar(WideString(AExePath)),
    PWideChar(Buf), Length(Buf));
  if (Len > Length(Buf)) then
  begin
    SetLength(Buf, Len);
    Len := GetShortPathNameW(PWideChar(WideString(AExePath)),
      PWideChar(Buf), Length(Buf));
  end;
  if Len > 0 then
    ShortPath := string(PWideChar(Buf));
  AData := '"' + ShortPath + '" ' + RES_RESUME_FLAG;
  Result := Length(AData) <= RES_RUNONCE_MAX;
  if not Result then
    AData := ''; { refusal clears the payload - never usable by accident }
end;

function ResPersistDir: string;
var
  ProgData: string;
begin
  ProgData := SysUtils.GetEnvironmentVariable('ProgramData');
  if ProgData = '' then
    ProgData := SysUtils.GetEnvironmentVariable('ALLUSERSPROFILE');
  if ProgData <> '' then
    Result := IncludeTrailingPathDelimiter(ProgData) + 'WSUSOffline'
  else
    Result := EngEngineTempDir;
end;

procedure RunSchtasks(const AArgs: string);
var
  SysDir: array[0..MAX_PATH] of WideChar;
  ExePath, CmdLine: WideString;
  Si: TStartupInfoW;
  Pi: TProcessInformation;
  Len: DWORD;
begin
  Len := GetSystemDirectoryW(@SysDir[0], MAX_PATH);
  if (Len = 0) or (Len > MAX_PATH) then
    Exit;
  ExePath := WideString(IncludeTrailingPathDelimiter(string(PWideChar(@SysDir[0]))))
    + 'schtasks.exe';
  CmdLine := '"' + ExePath + '" ' + WideString(AArgs);
  UniqueString(CmdLine);
  FillChar(Si, SizeOf(Si), 0);
  Si.cb := SizeOf(Si);
  FillChar(Pi, SizeOf(Pi), 0);
  if CreateProcessW(PWideChar(ExePath), PWideChar(CmdLine), nil, nil, False,
    CREATE_NO_WINDOW, nil, nil, Si, Pi) then
  begin
    WaitForSingleObject(Pi.hProcess, 10000);
    CloseHandle(Pi.hThread);
    CloseHandle(Pi.hProcess);
  end;
end;

function ResRegisterResume(const AExePath: string): Boolean;
var
  Name, Data, EscapedData, PersistDir: string;
  R: TRegistry;
begin
  Result := False;
  if not ResBuildRunOnceValue(AExePath, Name, Data) then
    Exit; { hard 260-char refusal (threat T-26-06) }
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKey(RES_RUNONCE_KEY, True) then
    begin
      R.WriteString(Name, Data);
      Result := True;
    end;
  finally
    R.Free;
  end;
  { Companion marker + Task Scheduler fallback AFTER the registry write:
    Windows 10 -> 11 Setup strips RunOnce and moves Windows\Temp into
    Windows.old, whereas %ProgramData%\WSUSOffline and WOUResume survive
    feature upgrades. }
  if Result then
  begin
    ResMarkerWriteIn(EngEngineTempDir);
    PersistDir := ResPersistDir;
    if not SameText(PersistDir, EngEngineTempDir) then
      ResMarkerWriteIn(PersistDir);
    EscapedData := StringReplace(Data, '"', '\"', [rfReplaceAll]);
    RunSchtasks('/Create /TN "' + RES_TASK_NAME
      + '" /SC ONLOGON /RL HIGHEST /IT /F /TR "' + EscapedData + '"');
  end;
end;

procedure ResDeleteResume;
var
  R: TRegistry;
  PersistDir: string;
begin
  R := TRegistry.Create(KEY_WRITE);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    if R.OpenKey(RES_RUNONCE_KEY, False) then
      R.DeleteValue(RES_RUNONCE_NAME);
  finally
    R.Free;
  end;
  ResMarkerDeleteIn(EngEngineTempDir);
  PersistDir := ResPersistDir;
  if not SameText(PersistDir, EngEngineTempDir) then
    ResMarkerDeleteIn(PersistDir);
  RunSchtasks('/Delete /TN "' + RES_TASK_NAME + '" /F');
end;

function ResWantsResume: Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 1 to ParamCount do
    if SameText(ParamStr(I), RES_RESUME_FLAG) then
      Exit(True);
end;

function ResStagingPresentIn(const ADir: string): Boolean;
var
  Base: string;
begin
  Base := IncludeTrailingPathDelimiter(ADir);
  Result := FileExists(Base + ENG_STAGING_UPDATES)
    or FileExists(Base + ENG_STAGING_STAGE_CMD);
end;

function ResStagingPresent: Boolean;
begin
  Result := ResStagingPresentIn(EngEngineTempDir);
end;

function ResMarkerPresentIn(const ADir: string): Boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(ADir) + RES_PENDING_MARKER);
end;

function ResMarkerWriteIn(const ADir: string): Boolean;
var
  Sl: TStringList;
begin
  Result := False;
  Sl := TStringList.Create;
  try
    Sl.Add(DateTimeToStr(Now));
    try
      ForceDirectories(ADir);
      Sl.SaveToFile(IncludeTrailingPathDelimiter(ADir) + RES_PENDING_MARKER);
      Result := True;
    except
      Result := False; { degrade to the old behaviour, never fail the caller }
    end;
  finally
    Sl.Free;
  end;
end;

procedure ResMarkerDeleteIn(const ADir: string);
begin
  SysUtils.DeleteFile(IncludeTrailingPathDelimiter(ADir) + RES_PENDING_MARKER);
end;

function ResResumePendingIn(const ADir: string): Boolean;
begin
  Result := ResStagingPresentIn(ADir) or ResMarkerPresentIn(ADir);
end;

function ResResumePending: Boolean;
var
  PersistDir: string;
begin
  Result := ResResumePendingIn(EngEngineTempDir);
  if not Result then
  begin
    PersistDir := ResPersistDir;
    if not SameText(PersistDir, EngEngineTempDir) then
      Result := ResResumePendingIn(PersistDir);
  end;
end;

function ResEngineRecallPreparedIn(const ADir: string): Boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(ADir)
    + RES_ENGINE_RECALL_REL);
end;

function ResEngineRecallPrepared: Boolean;
begin
  Result := ResEngineRecallPreparedIn(EngEngineTempDir);
end;

function ResUpgradeInProgressIn(const ADir: string): Boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(ADir)
    + RES_UPGRADE_MARKER);
end;

function ResUpgradeInProgress: Boolean;
var
  PersistDir: string;
begin
  Result := ResUpgradeInProgressIn(EngEngineTempDir);
  if not Result then
  begin
    PersistDir := ResPersistDir;
    if not SameText(PersistDir, EngEngineTempDir) then
      Result := ResUpgradeInProgressIn(PersistDir);
  end;
end;

function ResUpgradeMarkerTargetIn(const ADir: string): Integer;
var
  Sl: TStringList;
  Line, Field2: string;
  P: Integer;
begin
  Result := 0;
  Sl := TStringList.Create;
  try
    try
      Sl.LoadFromFile(IncludeTrailingPathDelimiter(ADir)
        + RES_UPGRADE_MARKER);
      if Sl.Count < 1 then
        Exit; { empty file parses as 0 (fail-closed downstream) }
      Line := Sl.Strings[0];
      P := Pos(',', Line);
      if P = 0 then
        Exit; { no CSV fields at all }
      Delete(Line, 1, P); { drop field 1 = the leg token }
      P := Pos(',', Line);
      if P = 0 then
        Field2 := Trim(Line) { the target is the last field }
      else
        Field2 := Copy(Line, 1, P - 1);
      Result := StrToIntDef(Trim(Field2), 0);
    except
      Result := 0; { degrade silently: an unreadable marker parses as 0 }
    end;
  finally
    Sl.Free;
  end;
end;

function ResUpgradeMarkerTarget: Integer;
var
  PersistDir: string;
begin
  if ResUpgradeInProgressIn(EngEngineTempDir) then
    Result := ResUpgradeMarkerTargetIn(EngEngineTempDir)
  else
  begin
    PersistDir := ResPersistDir;
    if (not SameText(PersistDir, EngEngineTempDir))
       and ResUpgradeInProgressIn(PersistDir) then
      Result := ResUpgradeMarkerTargetIn(PersistDir)
    else
      Result := 0;
  end;
end;

function ResUpgradeResumeBlockedIn(const ADir: string;
  const AObservedBuild: Integer): Boolean;
var
  Target: Integer;
begin
  if not ResUpgradeInProgressIn(ADir) then
    Exit(False); { no marker: today's behaviour }
  Target := ResUpgradeMarkerTargetIn(ADir);
  if Target <= 0 then
    Exit(True); { unparseable target: stay out, fail-closed }
  Result := AObservedBuild <> Target;
end;

function ResUpgradeResumeBlocked(const AObservedBuild: Integer): Boolean;
var
  PersistDir: string;
begin
  if ResUpgradeInProgressIn(EngEngineTempDir) then
    Result := ResUpgradeResumeBlockedIn(EngEngineTempDir, AObservedBuild)
  else
  begin
    PersistDir := ResPersistDir;
    if not SameText(PersistDir, EngEngineTempDir) then
      Result := ResUpgradeResumeBlockedIn(PersistDir, AObservedBuild)
    else
      Result := False;
  end;
end;

end.
