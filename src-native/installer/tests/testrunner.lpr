program testrunner;

{$mode objfpc}{$H+}

{*** Pure-unit battery for the native installer (plan 26-02).

    Console project - links the production units WITHOUT the LCL forms
    (mainform stays out; the gating logic lives in the pure functions of
    detection/buildsupgrade/enginecontracts/enginespine/strings_de_en).
    TAP-style output: one `ok N - <desc>` or `not ok N - <desc>` line per
    case, then a final `UNIT-FAIL:<count>` line; exit 0 only when every
    case passed. ci/tests/test-native-installer-units.sh is the fail-closed
    gate around this runner.

    Covered (task 1 matrix): .NET release-to-display golden cases, the
    per-OS target-release table, all toggle gates (enablement three-state
    incl. the forced branch, dotnet4 rule incl. forced-check, wmf rule +
    re-evaluation, autoreboot rule, shutdown-showlog coupling, auditonly
    coupling shape, presence/plain toggles), PathValid, language select,
    INI merge order, SysNative resolution matrix, argv emission order,
    the enablement predicates over a golden builds-table fixture (19041
    branch range boundaries, enforcement skip, ineligible short-circuit,
    malformed-line tolerance), and the mode-aware completion matrix. }

uses
  Classes, SysUtils, Windows, IniFiles,
  enginecontracts, enginespine, detection, buildsupgrade, strings_de_en;

var
  GCaseCount: Integer = 0;
  GFailCount: Integer = 0;

procedure Check(AOk: Boolean; const ADesc: string);
begin
  Inc(GCaseCount);
  if AOk then
    WriteLn(Format('ok %d - %s', [GCaseCount, ADesc]))
  else
  begin
    WriteLn(Format('not ok %d - %s', [GCaseCount, ADesc]));
    Inc(GFailCount);
  end;
end;

function CheckEq(const AActual, AExpected, ADesc: string): Boolean;
begin
  Result := AActual = AExpected;
  Check(Result, ADesc + ' (expected "' + AExpected + '", got "' + AActual + '")');
end;

{ ---- enablement fixture ---- }

const
  GOLDEN_BUILDS =
    '# comment line - ignored' + LineEnding +
    LineEnding +
    '19041|x86|win10|19041|active|||||0' + LineEnding +
    '19041|x64|win10|19041|active|||||0' + LineEnding +
    '19042|x86|win10|19041|eol|19041|kb4562830|kb5008212|572|1' + LineEnding +
    '19042|x64|win10|19041|eol|19041|kb4562830|kb5008212|572|1' + LineEnding +
    '19044|x64|win10|19041|eol|19041|kb5003791|kb5008212|1237|0' + LineEnding +
    '19045|x64|win10|19041|active|19041|kb5015684|kb5021233|1865|0' + LineEnding +
    '26100|x64|win11|26100|active|||||0' + LineEnding +
    '26200|x64|win11|26100|active|26100|kb5054156|kb5064081|5074|0' + LineEnding +
    '28000|x64|win11|28000|ineligible|||||0' + LineEnding +
    'this|row|is|malformed|nine|fields|only|so|skipped' + LineEnding;

var
  GTempDir: string;
  GFixtures: TStringList;

function WriteFixture(const AName, AContent: string): string;
var
  Sl: TStringList;
begin
  Result := GTempDir + '\' + AName;
  GFixtures.Add(Result);
  Sl := TStringList.Create;
  try
    Sl.Text := AContent;
    Sl.SaveToFile(Result);
  finally
    Sl.Free;
  end;
end;

{ Recording file probe: returns True exactly for paths listed in
  GProbeTrue (';'-separated), so the EKB file-probe branches are driven
  without a real tree. }
var
  GProbeTrue: string = '';

function StubProbe(const APath: string): Boolean;
var
  Token: string;
  Rest: string;
  P: Integer;
begin
  Result := False;
  Rest := GProbeTrue;
  while Rest <> '' do
  begin
    P := Pos(';', Rest);
    if P = 0 then
    begin
      Token := Rest;
      Rest := '';
    end
    else
    begin
      Token := Copy(Rest, 1, P - 1);
      Rest := Copy(Rest, P + 1, MaxInt);
    end;
    if Token = APath then
      Exit(True);
  end;
end;

procedure TestEnablementPredicates;
var
  Rows: TBuildRows;
  FixturePath: string;
begin
  FixturePath := WriteFixture('builds-golden.txt', GOLDEN_BUILDS);
  Rows := BuParseBuildsFile(FixturePath);
  Check(Length(Rows) = 9, 'parser: 12-line fixture yields 9 rows (comments, blank, malformed skipped)');

  { IsBuildIneligible (au3:290-297). }
  Check(BuIsBuildIneligible(Rows, '28000'), 'ineligible: 28000 row status ineligible');
  Check(not BuIsBuildIneligible(Rows, '19045'), 'eligible: 19045 active');
  Check(not BuIsBuildIneligible(Rows, '99999'), 'ineligible: unknown build -> false');
  Check(not BuIsBuildIneligible(Rows, ''), 'ineligible: empty build -> false');

  { BuildUpgradeEnforced (au3:337-347): keys on the row's
    ekb_source_build matching the CURRENT build. }
  Check(BuBuildUpgradeEnforced(Rows, '19041', 'x64') = 1,
    'enforced: 19042 x64 row (ekb_source 19041) is_enforced=1');
  Check(BuBuildUpgradeEnforced(Rows, '19041', 'x86') = 1,
    'enforced: 19042 x86 row (ekb_source 19041) is_enforced=1');
  Check(BuBuildUpgradeEnforced(Rows, '19045', 'x64') = 0,
    'enforced: no row carries ekb_source 19045');
  Check(BuBuildUpgradeEnforced(Rows, '26100', 'x64') = 0,
    'enforced: 26200 row exists but is_enforced=0');
  Check(BuBuildUpgradeEnforced(Rows, '26200', 'x86') = 0,
    'enforced: arch mismatch -> 0');

  { BuildUpgradeAvailable - ineligible short-circuit (au3:303). }
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '28000', 'x64',
    @StubProbe) = 0, 'available: ineligible build short-circuits to 0');

  { Source-build rule + file probes (au3:307): a machine ON build 19041
    with the 19042 EKB payload staged -> 1 (row 19042 x64 is enforced). }
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19041', 'x64',
    @StubProbe) = 0, 'available: 19041 x64 without EKB payload -> 0');
  GProbeTrue := 'C:\tree\w100-x64\glb\windows10.0-kb4562830-x64*.*';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19041', 'x64',
    @StubProbe) = 1, 'available: 19041 x64 with EKB payload p1 -> 1');
  GProbeTrue := 'C:\tree\w100-x64\glb\19041\windows10.0-kb4562830-x64*.*';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19041', 'x64',
    @StubProbe) = 1, 'available: 19041 x64 with EKB payload p2 (build dir) -> 1');

  { The 19041-family branch rule (au3:309): servicing_branch=19041 AND
    arch AND 19041 <= current < row build - boundaries below/at/above. }
  GProbeTrue := 'C:\tree\w100-x64\glb\windows10.0-kb5003791-x64*.*';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19042', 'x64',
    @StubProbe) = 1, 'branch rule: 19042 < 19044 row matched via 19041 branch');
  GProbeTrue := 'C:\tree\w100-x64\glb\windows10.0-kb5015684-x64*.*';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19043', 'x64',
    @StubProbe) = 1, 'branch rule: unlisted 19043 inside [19041,19045) matches');
  GProbeTrue := '';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19045', 'x64',
    @StubProbe) = 0,
    'branch rule: 19045 is the topmost 19041-branch row -> no target -> 0');
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19046', 'x64',
    @StubProbe) = 0, 'branch rule: 19046 above every 19041-branch row -> no match');
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19040', 'x64',
    @StubProbe) = 0, 'branch rule: 19040 below the lower bound -> no match');

  { Enforcement-mode skip (au3:319): mode 1 skips non-enforced rows -
    a 19044 machine only matches the 19045 row (not enforced). }
  GProbeTrue := 'C:\tree\w100-x64\glb\windows10.0-kb5015684-x64*.*';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 1, '19044', 'x64',
    @StubProbe) = 0, 'enforcement skip: 19044 in mode 1 skips the non-enforced row');
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '19044', 'x64',
    @StubProbe) = 1, 'enforcement skip: 19044 in mode 0 matches it');

  { win11 os_family drives the windows11.0 prefix; 26100 -> 26200 row by
    the source-build rule. }
  GProbeTrue := 'C:\tree\w100-x64\glb\windows11.0-kb5054156-x64*.*';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '26100', 'x64',
    @StubProbe) = 1, 'available: win11 prefix for the 26200 target row');
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 1, '26100', 'x64',
    @StubProbe) = 0, 'enforcement skip: 26200 row (not enforced) skipped in mode 1');
  GProbeTrue := '';
  Check(BuBuildUpgradeAvailable(Rows, 'C:\tree', 0, '26200', 'x64',
    @StubProbe) = 0, 'available: 26200 has no target row above it -> 0');
  GProbeTrue := '';
end;

procedure TestDisplayMaps;
var
  Os: TOsInfo;
begin
  { Release-to-display golden cases (plan pins 378389/533320 + unknown). }
  CheckEq(DetectDotNet4ReleaseToDisplay('378389'), '4.5', 'dotnet4 map: 378389');
  CheckEq(DetectDotNet4ReleaseToDisplay('378675'), '4.5.1', 'dotnet4 map: 378675');
  CheckEq(DetectDotNet4ReleaseToDisplay('379893'), '4.5.2', 'dotnet4 map: 379893');
  CheckEq(DetectDotNet4ReleaseToDisplay('394806'), '4.6.2', 'dotnet4 map: 394806');
  CheckEq(DetectDotNet4ReleaseToDisplay('461808'), '4.7.2', 'dotnet4 map: 461808');
  CheckEq(DetectDotNet4ReleaseToDisplay('528040'), '4.8', 'dotnet4 map: 528040');
  CheckEq(DetectDotNet4ReleaseToDisplay('528449'), '4.8', 'dotnet4 map: 528449');
  CheckEq(DetectDotNet4ReleaseToDisplay('533320'), '4.8.1', 'dotnet4 map: 533320');
  CheckEq(DetectDotNet4ReleaseToDisplay('533325'), '4.8.1', 'dotnet4 map: 533325');
  CheckEq(DetectDotNet4ReleaseToDisplay('999999'), '', 'dotnet4 map: unknown -> empty');
  CheckEq(DetectDotNet4ReleaseToDisplay(''), '', 'dotnet4 map: empty -> empty');

  { Per-OS target-release table (au3:464-499). }
  Os.Major := 10; Os.Minor := 0; Os.Workstation := True; Os.Build := 10240;
  CheckEq(DetectDotNet4TargetRelease(Os), '394806', 'target release: win10 10240');
  Os.Build := 14393;
  CheckEq(DetectDotNet4TargetRelease(Os), '528049', 'target release: win10 14393');
  Os.Build := 18362;
  CheckEq(DetectDotNet4TargetRelease(Os), '528040', 'target release: win10 18362');
  Os.Build := 18363;
  CheckEq(DetectDotNet4TargetRelease(Os), '528040', 'target release: win10 18363');
  Os.Build := 19041;
  CheckEq(DetectDotNet4TargetRelease(Os), '533325', 'target release: win10 >= 19041');
  Os.Build := 19045;
  CheckEq(DetectDotNet4TargetRelease(Os), '533325', 'target release: win10 19045');
  Os.Workstation := False; Os.Build := 14393;
  CheckEq(DetectDotNet4TargetRelease(Os), '528049', 'target release: server 2016');
  Os.Build := 17763;
  CheckEq(DetectDotNet4TargetRelease(Os), '528049', 'target release: server 2019');
  Os.Build := 20348;
  CheckEq(DetectDotNet4TargetRelease(Os), '533325', 'target release: server 2022');
  Os.Build := 26100;
  CheckEq(DetectDotNet4TargetRelease(Os), '0', 'target release: server >= 26100 unmapped');
  Os.Workstation := True; Os.Build := 22000;
  CheckEq(DetectDotNet4TargetRelease(Os), '533325', 'target release: win11 22000');
  Os.Build := 22621;
  CheckEq(DetectDotNet4TargetRelease(Os), '533320', 'target release: win11 22621');
  Os.Build := 26100;
  CheckEq(DetectDotNet4TargetRelease(Os), '533320', 'target release: win11 26100');
  Os.Major := 6; Os.Minor := 3; Os.Build := 9600;
  CheckEq(DetectDotNet4TargetRelease(Os), '0', 'target release: 8.1 unmapped -> 0');
end;

procedure TestToggleGates;
begin
  { Enablement three-state (au3:665-677, incl. the preserved tautology). }
  Check(GateEnablement(0, True, False, True).Enabled and
        GateEnablement(0, True, False, True).Checked,
    'enablement: available normal + INI enabled -> enabled+checked');
  Check(GateEnablement(0, True, False, False).Enabled and
        not GateEnablement(0, True, False, False).Checked,
    'enablement: available normal + INI disabled -> enabled+unchecked');
  Check(not GateEnablement(0, False, False, True).Enabled and
        not GateEnablement(0, False, False, True).Checked,
    'enablement: unavailable -> disabled+unchecked');
  Check(GateEnablement(0, True, True, False).Enabled and
        (not GateEnablement(0, True, True, False).Checked),
    'enablement: available normal wins over the enforced branch (per INI)');
  Check(GateEnablement(2, False, True, False).Checked and
        not GateEnablement(2, False, True, False).Enabled,
    'enablement: Enforced>1 + available(enforcement) -> forced checked+disabled');
  Check(not GateEnablement(1, False, True, False).Checked,
    'enablement: Enforced=1 tautology keeps the normal branch semantics');

  { dotnet4 rule (au3:732-744). }
  Check((GateDotNet4('533325', '533320', True, '4.8', '4.8', True).Checked = False) and
        (GateDotNet4('533325', '533320', True, '4.8', '4.8', True).Enabled = False),
    'dotnet4: release >= target -> disabled+unchecked');
  Check(GateDotNet4('', '533320', False, '', '', True).Checked = False,
    'dotnet4: installer payload absent -> disabled+unchecked');
  Check(GateDotNet4('', '533320', True, '4.5', '4.5', False).Checked,
    'dotnet4: main 4.5 -> FORCED checked+disabled');
  Check(not GateDotNet4('', '533320', True, '4.5', '4.5', False).Enabled,
    'dotnet4: forced branch is disabled');
  Check(GateDotNet4('', '533320', True, '4.6', '4.6', False).Checked,
    'dotnet4: display 4.6 -> FORCED checked');
  Check(GateDotNet4('', '533320', True, '4.6', '4.6.1', False).Checked,
    'dotnet4: display 4.6.1 -> FORCED checked');
  Check(GateDotNet4('', '533320', True, '4.6', '4.6.2', True).Enabled and
        GateDotNet4('', '533320', True, '4.6', '4.6.2', True).Checked,
    'dotnet4: display 4.6.2 escapes the forced branch -> per INI');
  Check(GateDotNet4('', '533320', True, '4.8', '4.8', False).Enabled and
        not GateDotNet4('', '533320', True, '4.8', '4.8', False).Checked,
    'dotnet4: 4.8 below target with installer -> enabled per INI (off)');

  { wmf rule (au3:753-763). }
  Check(not GateWmf(True, '4.8', False, False, True).Enabled,
    'wmf: modern OS -> disabled');
  Check(not GateWmf(False, '', False, False, True).Enabled,
    'wmf: no .NET upgrade path and dotnet4 unchecked -> disabled');
  Check(GateWmf(False, '', False, True, True).Enabled,
    'wmf: dotnet4 checked revives the offer despite missing path');
  Check(not GateWmf(False, '4.8', True, False, True).Enabled,
    'wmf: already at target 5.1 -> disabled');
  Check(GateWmf(False, '4.8', False, False, True).Enabled and
        GateWmf(False, '4.8', False, False, True).Checked,
    'wmf: 4.8 path, below target, legacy OS -> enabled per INI');

  { wmf re-evaluation on the dotnet4 click (au3:1113-1120). }
  Check(GateWmfReevaluate(False, '4.8', False, True),
    'wmf re-eval: dotnet4 checked + legacy + below target -> enable');
  Check(GateWmfReevaluate(False, '', False, False) = False,
    'wmf re-eval: no path, unchecked dotnet4 -> disable');
  Check(GateWmfReevaluate(True, '4.8', False, True) = False,
    'wmf re-eval: modern OS -> disable');
  Check(GateWmfReevaluate(False, '4.8', True, True) = False,
    'wmf re-eval: already at target -> disable');

  { autoreboot rule - INST-05 redesign of au3:887-895. }
  Check(GateAutoreboot(True, False, True).Enabled,
    'autoreboot: Win10+ enabled (RunOnce path) even without Autologon');
  Check(GateAutoreboot(True, False, True).Checked,
    'autoreboot: Win10+ checked per INI');
  Check(GateAutoreboot(False, True, False).Enabled and
        not GateAutoreboot(False, True, False).Checked,
    'autoreboot: legacy + Autologon present -> enabled per INI (off)');
  Check(not GateAutoreboot(False, False, True).Enabled and
        not GateAutoreboot(False, False, True).Checked,
    'autoreboot: legacy without Autologon -> blocked');

  { shutdown-showlog coupling (au3:918-926). }
  Check(GateShowlog(True, False).Checked and GateShowlog(True, False).Enabled,
    'showlog: INI enabled + shutdown off -> checked');
  Check(not GateShowlog(True, True).Checked and
        not GateShowlog(True, True).Enabled,
    'showlog: shutdown checked -> unchecked + disabled');
  Check(not GateShowlog(False, False).Checked and GateShowlog(False, False).Enabled,
    'showlog: INI disabled -> unchecked, still enabled');

  { presence/plain toggles. }
  Check(GatePresence(True, True).Enabled and GatePresence(True, True).Checked,
    'presence: present + INI -> checked');
  Check(GatePresence(True, False).Enabled and
        not GatePresence(True, False).Checked, 'presence: present + off INI');
  Check(not GatePresence(False, True).Enabled and
        not GatePresence(False, True).Checked,
    'presence: absent -> disabled + unchecked');
  Check(GatePlainToggle(True).Enabled and GatePlainToggle(True).Checked,
    'plain toggle: always offerable, checked');
end;

procedure TestPathValid;
var
  Chars: string;
  I: Integer;
begin
  Check(EngPathValid(StringOfChar('a', ENG_PATH_MAX_LENGTH)),
    'pathvalid: exactly 192 chars accepted');
  Check(not EngPathValid(StringOfChar('a', ENG_PATH_MAX_LENGTH + 1)),
    'pathvalid: 193 chars rejected');
  Chars := ENG_PATH_INVALID_CHARS;
  for I := 1 to Length(Chars) do
    Check(not EngPathValid('C:\some' + Chars[I] + 'path'),
      'pathvalid: reject char ''' + Chars[I] + '''');
  Check(EngPathValid('C:\wsusoffline\client'),
    'pathvalid: clean path accepted');
end;

procedure TestLanguageSelect;
begin
  Check(StringsSelectLanguage('enu', True) = False, 'lang: argv enu wins (over German UI)');
  Check(StringsSelectLanguage('deu', False) = True, 'lang: argv deu wins (over English UI)');
  Check(StringsSelectLanguage('ENU', False) = False, 'lang: argv case-insensitive');
  Check(StringsSelectLanguage('', True) = True, 'lang: empty -> autodetect (German UI)');
  Check(StringsSelectLanguage('', False) = False, 'lang: empty -> autodetect (English UI)');
  Check(StringsSelectLanguage('fra', True) = True, 'lang: unknown token -> autodetect');
end;

procedure TestIniMergeOrder;
var
  ClientIni, TempIni, Missing: string;
begin
  ClientIni := WriteFixture('client-merge.ini',
    '[Installation]' + LineEnding + 'updatecpp=Disabled' + LineEnding);
  TempIni := WriteFixture('temp-merge.ini',
    '[Installation]' + LineEnding + 'updatecpp=Enabled' + LineEnding);
  Missing := GTempDir + '\wou-testrunner-nope.ini';

  CheckEq(EngMyIniRead(ClientIni, TempIni, 'Installation', 'updatecpp', 'x'),
    'Enabled', 'ini merge: %TEMP% copy overrides the client INI');
  CheckEq(EngMyIniRead(ClientIni, Missing, 'Installation', 'updatecpp', 'x'),
    'Disabled', 'ini merge: client INI alone wins when no copy exists');
  CheckEq(EngMyIniRead(Missing, Missing, 'Installation', 'updatecpp', 'x'),
    'x', 'ini merge: no files at all -> default');
  CheckEq(EngDefaultIniRead(ClientIni, 'Installation', 'updatecpp', 'x'),
    'Disabled', 'ini merge: DefaultIniRead ignores the %TEMP% copy');
  CheckEq(EngDefaultIniRead(Missing, 'Control', 'verify', 'd'),
    'd', 'ini merge: DefaultIniRead missing file -> default');
  CheckEq(EngIniDefault('Installation', 'updatecpp'), 'Enabled',
    'ini defaults: template default updatecpp=Enabled');
  CheckEq(EngIniDefault('Control', 'autoreboot'), 'Disabled',
    'ini defaults: template default autoreboot=Disabled');
end;

procedure TestSysNativeMatrix;
var
  SysRoot: string;
begin
  SysRoot := 'C:\WINDOWS';
  CheckEq(EngCmdExePathFor(SysRoot, '', True, True),
    SysRoot + '\SysNative\cmd.exe',
    'sysnative: 32-bit process + SysNative dir -> SysNative');
  CheckEq(EngCmdExePathFor(SysRoot, SysRoot + '\System32\cmd.exe', True, False),
    SysRoot + '\System32\cmd.exe',
    'sysnative: missing SysNative dir -> %ComSpec%');
  CheckEq(EngCmdExePathFor(SysRoot, SysRoot + '\System32\cmd.exe', False, True),
    SysRoot + '\System32\cmd.exe',
    'sysnative: 64-bit process -> %ComSpec% even with SysNative');
  CheckEq(EngCmdExePathFor(SysRoot, 'cmd.exe', True, False),
    SysRoot + '\System32\cmd.exe',
    'sysnative: bare ComSpec name is absolutized, never PATH-spawned');
  CheckEq(EngCmdExePathFor('', '', False, False), '',
    'sysnative: nothing resolvable -> empty (fail closed)');
end;

procedure TestArgvEmission;
var
  T: TArgvToggles;
begin
  FillChar(T, SizeOf(T), 0);
  CheckEq(EngBuildArgv(T), '', 'argv: nothing checked -> empty');

  FillChar(T, SizeOf(T), 0);
  T.UpgradeBuilds := True; T.UpdateCpp := True;
  T.Verify := True; T.AuditOnly := True;
  CheckEq(EngBuildArgv(T), '/upgradebuilds /updatecpp /verify /auditonly',
    'argv: checkbox subset in incumbent order');

  FillChar(T, SizeOf(T), 0);
  T.SkipIeInst := True; T.SecOnly := True;
  T.ShowDismProgress := True; T.MonitorOn := True;
  CheckEq(EngBuildArgv(T),
    '/skipieinst /seconly /showdismprogress /monitoron',
    'argv: INI-driven subset in incumbent order');

  FillChar(T, SizeOf(T), 0);
  T.UpgradeBuilds := True; T.Updatercerts := True;
  T.InstDotNet35 := True; T.InstDotNet4 := True; T.InstWmf := True;
  T.UpdateDotNet5 := True; T.UpdateCpp := True; T.InstEdge := True;
  T.InstWebView2 := True; T.UpdateOffice := True;
  T.SkipIeInst := True; T.SkipDefs := True; T.SkipDynamic := True;
  T.AllUpdates := True; T.ExcludeStatics := True; T.SecOnly := True;
  T.Verify := True; T.AuditOnly := True; T.AutoReboot := True;
  T.Shutdown := True; T.ShowLog := True;
  T.ShowDismProgress := True; T.MonitorOn := True;
  CheckEq(EngBuildArgv(T),
    '/upgradebuilds /updatercerts /instdotnet35 /instdotnet4 /instwmf ' +
    '/updatedotnet5 /updatecpp /instedge /instwebview2 /updateoffice ' +
    '/skipieinst /skipdefs /skipdynamic /all /excludestatics /seconly ' +
    '/verify /auditonly /autoreboot /shutdown /showlog /showdismprogress ' +
    '/monitoron',
    'argv: the full frozen emission in the exact au3 order');

  CheckEq(EngSwitchToken('bogus'), '', 'argv: unknown token name -> empty (allow-list)');
  CheckEq(EngSwitchToken('updatecpp'), '/updatecpp', 'argv: token lookup');
end;

procedure TestCompletionMatrix;
begin
  { exit 0/1/3010/3011 x finish-mode present/absent. }
  Check(SpineOutcomeKind('', True, ENG_EXIT_OK, False) = soCompleted,
    'completion: exit 0 -> completed');
  Check(SpineOutcomeKind('', True, ENG_EXIT_ERROR, False) = soError,
    'completion: exit 1 -> error');
  Check(SpineOutcomeKind('', True, ENG_EXIT_REBOOT_REQUIRED, False) = soRebootRequired,
    'completion: exit 3010 -> reboot required');
  Check(SpineOutcomeKind('', True, ENG_EXIT_RECALL, False) = soRecall,
    'completion: exit 3011 -> recall');
  Check(SpineOutcomeKind('/auditonly', True, 42, False) = soError,
    'completion: unexpected integer -> error');
  Check(SpineOutcomeKind('/autoreboot', False, -1, False) = soAbruptFinishSuccess,
    'completion: abrupt death under /autoreboot = success (Pitfall C)');
  Check(SpineOutcomeKind('/shutdown', False, -1, False) = soAbruptFinishSuccess,
    'completion: abrupt death under /shutdown = success');
  Check(SpineOutcomeKind('/auditonly', False, -1, False) = soNoVerdict,
    'completion: abrupt death without finish mode = no verdict');
  Check(SpineOutcomeKind('', True, ENG_EXIT_OK, True) = soCanceled,
    'completion: cancel wins over any exit state');
  Check(SpineOutcomeKind('/autoreboot', True, ENG_EXIT_REBOOT_REQUIRED, True) = soCanceled,
    'completion: cancel wins even in finish mode');
  Check(SpineAbruptDeathIsSuccess('/verify /autoreboot'),
    'completion: finish-mode detector /autoreboot');
  Check(SpineAbruptDeathIsSuccess('/shutdown') and
        not SpineAbruptDeathIsSuccess('/verify /auditonly'),
    'completion: finish-mode detector /shutdown only');
end;

var
  I: Integer;
begin
  GTempDir := IncludeTrailingPathDelimiter(EngCallerTempDir) + 'wou-testrunner';
  ForceDirectories(GTempDir);
  GFixtures := TStringList.Create;
  try
    TestDisplayMaps;
    TestEnablementPredicates;
    TestToggleGates;
    TestPathValid;
    TestLanguageSelect;
    TestIniMergeOrder;
    TestSysNativeMatrix;
    TestArgvEmission;
    TestCompletionMatrix;
  finally
    { Best-effort fixture cleanup - the gate is output-based. }
    for I := 0 to GFixtures.Count - 1 do
      SysUtils.DeleteFile(GFixtures.Strings[I]);
    RemoveDir(GTempDir);
    GFixtures.Free;
  end;
  WriteLn(Format('1..%d', [GCaseCount]));
  WriteLn(Format('UNIT-FAIL:%d', [GFailCount]));
  if GFailCount > 0 then
    Halt(1)
  else
    Halt(0);
end.
