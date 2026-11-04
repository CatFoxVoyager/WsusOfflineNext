program spineprobe;

{$mode objfpc}{$H+}

{*** Headless end-to-end probe of the engine spine (plan 26-01).

    Reuses enginecontracts + enginespine (no LCL forms). Stages nothing
    itself: takes the (fixture) client tree root as argument, writes the
    tracer's three-key %TEMP% INI state (IniCopy parity), runs the spine
    against <root>\cmd with /auditonly, prints every streamed line prefixed
    STREAM:, prints OBSERVED-EXIT:<code>, and exits 0 iff at least one line
    was streamed AND an integer exit code was observed AND the internal
    10-minute watchdog never fired. }

uses
  Classes, SysUtils, IniFiles,
  enginecontracts, enginespine;

const
  PROBE_WATCHDOG_MS = 10 * 60 * 1000;

type
  TProbe = class
    LinesSeen: Integer;
    procedure HandleLine(const ALine: string);
  end;

procedure TProbe.HandleLine(const ALine: string);
begin
  Inc(LinesSeen);
  WriteLn('STREAM: ', ALine);
end;

var
  TreeRoot: string;
  CmdDir: string;
  ClientIniPath: string;
  TempIniPath: string;
  Spine: TEngineSpine;
  Probe: TProbe;
  Res: TSpineResult;
  Success: Boolean;
begin
  if ParamStr(1) = '' then
  begin
    WriteLn('ERROR: usage: spineprobe <client-tree-root>');
    Halt(2);
  end;
  TreeRoot := ParamStr(1);
  if (Length(TreeRoot) > 0) and (TreeRoot[Length(TreeRoot)] <> '\') then
    TreeRoot := TreeRoot + '\';
  CmdDir := TreeRoot + 'cmd';
  if not FileExists(CmdDir + '\DoUpdate.cmd') then
  begin
    WriteLn('ERROR: no DoUpdate.cmd under ', CmdDir);
    Halt(2);
  end;

  { Three-key %TEMP% INI state - IniCopy parity for the tracer's toggles:
    copy the client template, then IniWrite the three key states. }
  TempIniPath := IncludeTrailingPathDelimiter(EngCallerTempDir)
    + ENG_TEMP_INI_NAME;
  ClientIniPath := TreeRoot + ENG_TEMP_INI_NAME;
  if FileExists(ClientIniPath) then
    EngCopyFileRaw(ClientIniPath, TempIniPath);
  with TIniFile.Create(TempIniPath) do
    try
      WriteString(ENG_INI_SECTION_INSTALLATION, 'updatecpp', ENG_INI_ENABLED);
      WriteString(ENG_INI_SECTION_CONTROL, 'verify', ENG_INI_ENABLED);
      WriteString(ENG_INI_SECTION_CONTROL, 'auditonly', ENG_INI_ENABLED);
      UpdateFile;
    finally
      Free;
    end;

  Probe := TProbe.Create;
  Spine := TEngineSpine.Create;
  try
    Spine.OnLine := @Probe.HandleLine;
    Spine.Run(CmdDir, '/auditonly', PROBE_WATCHDOG_MS, Res);
    WriteLn('OBSERVED-EXIT:', Res.ExitCode);
    WriteLn('LINES-STREAMED:', Res.LineCount);
    if Res.TimedOut then
      WriteLn('PROBE-VERDICT: watchdog timeout - fail');
    Success := (Probe.LinesSeen >= 1) and Res.Observed and (not Res.TimedOut);
  finally
    Spine.Free;
    Probe.Free;
  end;

  if Success then
  begin
    WriteLn('PROBE-VERDICT: pass');
    Halt(0);
  end
  else
  begin
    WriteLn('PROBE-VERDICT: fail');
    Halt(1);
  end;
end.
