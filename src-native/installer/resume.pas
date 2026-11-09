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

function ResRegisterResume(const AExePath: string): Boolean;
var
  Name, Data: string;
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
  { Companion marker AFTER the registry write: without it a reboot before the
    engine staged anything would land on the nothing-to-resume dead end. A
    marker failure degrades to that old behaviour, it never fails the run. }
  if Result then
    ResMarkerWriteIn(EngEngineTempDir);
end;

procedure ResDeleteResume;
var
  R: TRegistry;
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
begin
  Result := ResResumePendingIn(EngEngineTempDir);
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

end.
