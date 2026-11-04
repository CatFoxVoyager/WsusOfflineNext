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
    - answers the /resume startup decision: the engine staging in
      %SystemRoot%\Temp (WOUpdatesToInstall.txt present, SetWOUpdateStage
      deleted-on-read by the engine) decides resume vs nothing-to-resume.

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

end.
