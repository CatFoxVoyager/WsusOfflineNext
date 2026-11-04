program spineprobe;

{$mode objfpc}{$H+}

{*** Headless end-to-end probe of the engine spine (plans 26-01/02/03).

    Reuses enginecontracts + enginespine (no LCL forms). Stages nothing
    itself: takes the (fixture) client tree root as argument, writes the
    tracer's three-key %TEMP% INI state (IniCopy parity), runs the spine
    against <root>\cmd with /auditonly, prints every streamed line prefixed
    STREAM:, prints OBSERVED-EXIT:<code>, and exits 0 iff at least one line
    was streamed AND an integer exit code was observed AND the internal
    10-minute watchdog never fired.

    Plan 26-03 extension: the optional second argument names the audit
    report the engine was steered to (WOU_MISSING_LOG_FALLBACK; the gate
    passes the fixture log path). After the run the probe asserts the
    report file EXISTS and the GUI-side parser (SpineParseAuditReport)
    extracts the 5-compartment shape from it - AUDIT-REPORT-OK. }

uses
  Classes, SysUtils, IniFiles, Process, Windows,
  enginecontracts, enginespine;

const
  PROBE_WATCHDOG_MS = 10 * 60 * 1000;

{ Drive the engine's OWN report producer (the ':WriteMissingUpdatesReport'
  argument dispatch at DoUpdate.cmd:48 - reachable without the admin
  privilege gate that guards the full audit flow). The engine renders the
  report into MISSING_UPDATES_LOG, which the gate steered into the
  fixture via WOU_MISSING_LOG_FALLBACK (inherited env). }
procedure SpawnEngineReportTool(const ACmdDir: string);
var
  P: TProcess;
  Chunk: AnsiString;
  Count: DWord;
begin
  P := TProcess.Create(nil);
  try
    P.Executable := EngCmdExePath;
    P.Parameters.Add('/D');
    P.Parameters.Add('/C');
    P.Parameters.Add('".\DoUpdate.cmd :WriteMissingUpdatesReport"');
    P.CurrentDirectory := ACmdDir;
    P.Options := [poUsePipes, poNoConsole];
    try
      P.Execute;
    except
      Exit;
    end;
    while P.Running do
    begin
      Count := P.Output.NumBytesAvailable;
      if Count > 0 then
      begin
        SetLength(Chunk, Count);
        SetLength(Chunk, P.Output.Read(Chunk[1], Count));
        { Drain - the report body echoes to stdout; not asserted here. }
      end;
      Sleep(50);
    end;
  finally
    P.Free;
  end;
end;

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
  ReportPath: string;
  Sl: TStringList;
  Counts: TSpineAuditCounts;
  Spine: TEngineSpine;
  Probe: TProbe;
  Res: TSpineResult;
  Success: Boolean;
  AuditOk: Boolean;
begin
  if ParamStr(1) = '' then
  begin
    WriteLn('ERROR: usage: spineprobe <client-tree-root> [expected-report-path]');
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

  { Plan 26-03: the audit-report assertion on the engine-produced file.
    The full /auditonly flow requires the admin privilege gate, so the
    report is produced by the engine's own report entry point on hosts
    where the gate cannot elevate. }
  AuditOk := False;
  ReportPath := ParamStr(2);
  if ReportPath <> '' then
  begin
    SpawnEngineReportTool(CmdDir);
    if FileExists(ReportPath) then
    begin
      Sl := TStringList.Create;
      try
        Sl.LoadFromFile(ReportPath);
        if SpineParseAuditReport(Sl, Counts) then
        begin
          WriteLn('AUDIT-REPORT-OK total=', Counts.Total,
            ' compartments=', Counts.Lcu, '/', Counts.Ssu, '/',
            Counts.Defender, '/', Counts.Office, '/', Counts.Runtimes,
            ' other=', Counts.Other);
          AuditOk := True;
        end
        else
          WriteLn('AUDIT-REPORT-FAIL: parser could not extract the compartments');
      finally
        Sl.Free;
      end;
    end
    else
      WriteLn('AUDIT-REPORT-FAIL: report file missing at ', ReportPath);
    Success := Success and AuditOk;
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
