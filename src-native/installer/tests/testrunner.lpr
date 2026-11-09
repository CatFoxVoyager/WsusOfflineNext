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
    malformed-line tolerance), and the mode-aware completion matrix.
    Plan 29-01 task 2 adds the selfupdate core matrix: channel/links
    parsers, the strict-newer comparator, the daily cache and the
    kill-switch INI reader, fixture-for-fixture against the battery's
    section (a) matrix. Plan 261106-p8q adds the UNC share-root split
    matrix: the pure DetectSplitUncPath scanner pin (share root +
    remainder, malformed and root-only shapes) behind the network
    script-dir fallback. Plan 261106-sgi adds the free-drive-letter
    selection pin: the pure DetectPickFreeDriveLetter contract
    (Z-downto-C order, occupied-letter skip, full-range exhaustion,
    case-lenient match) behind the explicit device choice.
    Plan 261106-toz adds the modern-extras OS gate pin: Edge/WebView2
    offers gated off on pre-Win10 OSes (2x2 OS/presence matrix). }

uses
  Classes, SysUtils, Windows, IniFiles, Registry, zipper,
  enginecontracts, enginespine, detection, buildsupgrade, strings_de_en,
  resume, selfupdate;

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

procedure TestOsGate;
begin
  { plan 261106-toz: the 2x2 OS/presence matrix for the Edge/WebView2
    modern-extras gate. }
  Check(not GateModernExtrasByOs(False, True, True).Enabled and
        not GateModernExtrasByOs(False, True, True).Checked,
    'osgate: legacy OS + present + INI checked -> disabled + unchecked');
  Check(GateModernExtrasByOs(True, True, True).Enabled and
        GateModernExtrasByOs(True, True, True).Checked,
    'osgate: modern OS + present + INI checked -> passthrough enabled + checked');
  Check(not GateModernExtrasByOs(True, False, True).Enabled and
        not GateModernExtrasByOs(True, False, True).Checked,
    'osgate: modern OS + absent -> presence rule disabled + unchecked');
  Check(not GateModernExtrasByOs(False, False, True).Enabled and
        not GateModernExtrasByOs(False, False, True).Checked,
    'osgate: legacy OS + absent -> disabled + unchecked');
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

procedure TestUncSplit;
var
  LRoot, LRest: string;
begin
  { Plan 261106-p8q: pin the pure UNC split contract the share-root
    fallback consumes - 7 cases x 3 checks (Boolean + ARoot +
    ARemainder). Pascal backslashes are literal characters. }
  Check(DetectSplitUncPath('\\vmware-host\Shared Folders\E\wsusoffline\client\',
      LRoot, LRest),
    'uncsplit: deep HGFS path splits to the share root + remainder');
  CheckEq(LRoot, '\\vmware-host\Shared Folders',
    'uncsplit: deep HGFS path ARoot is the share root');
  CheckEq(LRest, '\E\wsusoffline\client\',
    'uncsplit: deep HGFS path ARemainder starts at the next backslash');

  Check(DetectSplitUncPath('\\srv\share', LRoot, LRest),
    'uncsplit: two-component UNC splits with empty remainder');
  CheckEq(LRoot, '\\srv\share',
    'uncsplit: two-component UNC ARoot is the whole path');
  CheckEq(LRest, '',
    'uncsplit: two-component UNC ARemainder is empty');

  Check(DetectSplitUncPath('\\srv\share\', LRoot, LRest),
    'uncsplit: share-root path with trailing delimiter splits with backslash remainder');
  CheckEq(LRoot, '\\srv\share',
    'uncsplit: trailing-delimiter ARoot stops before the delimiter');
  CheckEq(LRest, '\',
    'uncsplit: trailing-delimiter ARemainder is the backslash');

  Check(DetectSplitUncPath('\\srv\share\E\wsusoffline', LRoot, LRest),
    'uncsplit: mid-depth path splits to the share root + remainder');
  CheckEq(LRoot, '\\srv\share',
    'uncsplit: mid-depth ARoot is the share root');
  CheckEq(LRest, '\E\wsusoffline',
    'uncsplit: mid-depth ARemainder carries the balance');

  Check(not DetectSplitUncPath('\\srv', LRoot, LRest),
    'uncsplit: server-only UNC rejected');
  CheckEq(LRoot, '', 'uncsplit: server-only ARoot stays empty');
  CheckEq(LRest, '', 'uncsplit: server-only ARemainder stays empty');

  Check(not DetectSplitUncPath('\\srv\', LRoot, LRest),
    'uncsplit: server-only UNC with trailing delimiter rejected');
  CheckEq(LRoot, '',
    'uncsplit: server-only trailing-delimiter ARoot stays empty');
  CheckEq(LRest, '',
    'uncsplit: server-only trailing-delimiter ARemainder stays empty');

  Check(not DetectSplitUncPath('C:\tree', LRoot, LRest),
    'uncsplit: non-UNC path rejected');
  CheckEq(LRoot, '', 'uncsplit: non-UNC ARoot stays empty');
  CheckEq(LRest, '', 'uncsplit: non-UNC ARemainder stays empty');
end;

procedure TestPickFreeLetter;
begin
  { Plan 261106-sgi: pin the free-drive-letter selection contract the
    explicit-letter map consumes. Pascal backslashes are literal
    characters. }
  CheckEq(DetectPickFreeDriveLetter(''), 'Z:',
    'freeletter: empty drive set picks Z: (first candidate, last letter first)');
  CheckEq(DetectPickFreeDriveLetter('Z:\'), 'Y:',
    'freeletter: Z: occupied picks Y:');
  CheckEq(DetectPickFreeDriveLetter('Y:\Z:\'), 'X:',
    'freeletter: Y: and Z: occupied pick X:');
  CheckEq(DetectPickFreeDriveLetter(
    'C:\D:\E:\F:\G:\H:\I:\J:\K:\L:\M:\N:\O:\P:\Q:\R:\S:\T:\U:\V:\W:\X:\Y:\Z:\'),
    '',
    'freeletter: full range from C: to Z: exhausted returns empty');
  CheckEq(DetectPickFreeDriveLetter('z:\'), 'Y:',
    'freeletter: lowercase existing entry still occupies Z: (case-lenient match)');
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

procedure TestMsiContract;
var
  Names: TStringList;
  SelPath: string;
  Raw: AnsiString;
  Fs: TFileStream;
begin
  { EngReadMsiListing: bare names, empty lines dropped. }
  Names := TStringList.Create;
  try
    EngReadMsiListing(WriteFixture('msi-listing.txt',
      'pkg-a.msi' + LineEnding + LineEnding + 'pkg-b.msi' + LineEnding), Names);
    Check((Names.Count = 2) and (Names.Strings[0] = 'pkg-a.msi') and
          (Names.Strings[1] = 'pkg-b.msi'),
      'msi listing: bare names parsed, blank lines dropped');
    EngReadMsiListing(GTempDir + '\wou-testrunner-missing.txt', Names);
    Check(Names.Count = 0, 'msi listing: missing file -> empty');

    { EngWriteMsiSelection: raw one-filename-per-line, CRLF-terminated,
      no quoting or decoration (threat T-26-05). }
    SelPath := GTempDir + '\wouselmsi-test.txt';
    Names.Clear;
    Names.Add('pkg-a.msi');
    Names.Add('pkg-b.msi');
    EngWriteMsiSelection(SelPath, Names);
    Fs := TFileStream.Create(SelPath, fmOpenRead);
    try
      SetLength(Raw, Fs.Size);
      if Fs.Size > 0 then
        Fs.ReadBuffer(PAnsiChar(Raw)^, Fs.Size);
    finally
      Fs.Free;
    end;
    CheckEq(string(Raw), 'pkg-a.msi' + #13#10 + 'pkg-b.msi' + #13#10,
      'msi selection: raw lines written (no quoting, trailing CRLF)');

    { Empty selection DELETES the file (au3:1291-1293). }
    Names.Clear;
    EngWriteMsiSelection(SelPath, Names);
    Check(not FileExists(SelPath),
      'msi selection: empty selection deletes the file');
    { Deleting when absent stays a no-op. }
    EngWriteMsiSelection(SelPath, Names);
    Check(not FileExists(SelPath),
      'msi selection: empty selection on absent file stays absent');
  finally
    Names.Free;
  end;
end;

procedure TestProgressParsing;
var
  N, M: Integer;
begin
  { Exact engine shape (InstallListedUpdates.cmd:44,59). }
  Check(SpineParseProgressLine(
    '13:25:08,32 - Installing update 3 of 40 (stage size: 5)...', N, M)
    and (N = 3) and (M = 40),
    'progress: exact engine line parses (N=3, M=40)');
  Check(SpineParseProgressLine(
    '08:01:02,03 - Installing update 1 of 1 (stage size: 12)...', N, M)
    and (N = 1) and (M = 1),
    'progress: single-update stage parses');

  { Off-format lines pass through unparsed. }
  Check(not SpineParseProgressLine(
    'Info: Installed 3 of 40 updates', N, M),
    'progress: completion-summary line does not parse');
  Check(not SpineParseProgressLine(
    'Checking user''s privileges...', N, M),
    'progress: lifecycle line does not parse');
  Check(not SpineParseProgressLine('', N, M),
    'progress: empty line does not parse');
  Check(not SpineParseProgressLine(
    'Installing update x of y (stage size: 5)...', N, M),
    'progress: non-numeric counters do not parse');
  Check(not SpineParseProgressLine(
    'Installing update 0 of 40 (stage size: 5)...', N, M),
    'progress: zero counter rejected');
  Check(not SpineParseProgressLine(
    'Installing update 41 of 40 (stage size: 5)...', N, M),
    'progress: N > M rejected');
  Check(not SpineParseProgressLine(
    'Installing update 12 off 40 (stage size: 5)...', N, M),
    'progress: wrong separator rejected');
end;

procedure TestWatcherCounts;
var
  Counts: TSpineOutcomeCounts;
  Dir: string;
begin
  { Live counts over the five outcome files on temp fixtures. }
  Dir := IncludeTrailingPathDelimiter(GTempDir) + 'watcher';
  ForceDirectories(Dir);
  WriteFixture('watcher\wou_installed_updates.txt',
    'u1' + LineEnding + 'u2' + LineEnding + 'u3' + LineEnding);
  WriteFixture('watcher\wou_failed_updates.txt',
    'f1' + LineEnding);
  Counts := SpineReadOutcomeCounts(Dir);
  Check((Counts.Installed = 3) and (Counts.Failed = 1)
        and (Counts.Corrupt = 0) and (Counts.CleanSkipped = 0)
        and (Counts.VerificationSkipped = 0),
    'watcher: counts over fixture outcome files (3/1/0/0/0)');
  Check(SpineCountFileLines(Dir + '\wou_installed_updates.txt') = 3,
    'watcher: line counting');
  Check(SpineCountFileLines(Dir + '\absent-file.txt') = 0,
    'watcher: absent outcome file counts 0');
end;

procedure TestAuditReportParsing;
var
  Sl: TStringList;
  Counts: TSpineAuditCounts;
begin
  { The engine's emission shape (DoUpdate.cmd:2722-2766). }
  Sl := TStringList.Create;
  try
    Sl.Text :=
      '================================================================================' + LineEnding +
      'WSUS Offline Update - Offline Applicability & Missing Updates Report' + LineEnding +
      'Timestamp: 11/04/2026 13:00:00,00' + LineEnding +
      'Target System: Microsoft Windows w100 10.0.26300.0 (x64)' + LineEnding +
      'Execution Mode:          Audit Only [/auditonly - Zero System Modifications]' + LineEnding +
      '--------------------------------------------------------------------------------' + LineEnding +
      'Total Missing Items:     7' + LineEnding +
      LineEnding +
      '[Windows Cumulative & Checkpoint Updates] [Count: 3]' + LineEnding +
      '  C:\\w100-x64\\glb\\windows10.0-kbX-x64.exe' + LineEnding +
      '[Integrated Servicing Stack Updates] [Count: 1]' + LineEnding +
      '[Windows Defender Security Intelligence] [Count: 0]' + LineEnding +
      '  None missing / Not requested' + LineEnding +
      '[Microsoft Office Updates] [Count: 2]' + LineEnding +
      '[Modern Extras & Runtimes] [Count: 1]' + LineEnding +
      '[Other Components] [Count: 0]' + LineEnding +
      '--------------------------------------------------------------------------------' + LineEnding +
      'Audit Result: Updates required [7 item(s) missing]' + LineEnding +
      '================================================================================';
    Check(SpineParseAuditReport(Sl, Counts), 'audit parse: report recognized');
    Check((Counts.Total = 7) and (Counts.Lcu = 3) and (Counts.Ssu = 1)
          and (Counts.Defender = 0) and (Counts.Office = 2)
          and (Counts.Runtimes = 1) and (Counts.Other = 0),
      'audit parse: all compartment counts extracted');
    Check(Pos('Updates required [7 item(s) missing]', Counts.ResultLine) > 0,
      'audit parse: result line captured');

    Sl.Text := 'just some log noise' + LineEnding;
    Check(not SpineParseAuditReport(Sl, Counts),
      'audit parse: non-report text rejected');
  finally
    Sl.Free;
  end;
end;

procedure TestAuditParserLastReportWins;
var
  Sl: TStringList;
  Counts: TSpineAuditCounts;
begin
  { The report file APPENDS every run's report: the parser must end with the
    LAST report's values (an older "fully up to date" above must not win). }
  Sl := TStringList.Create;
  try
    Sl.Text :=
      '================================================================================' + LineEnding +
      'Total Missing Items:     0' + LineEnding +
      '[Windows Cumulative & Checkpoint Updates] [Count: 0]' + LineEnding +
      'Audit Result: System is fully up to date [0 missing updates]' + LineEnding +
      '================================================================================' + LineEnding +
      '================================================================================' + LineEnding +
      'Total Missing Items:     7' + LineEnding +
      '[Windows Cumulative & Checkpoint Updates] [Count: 3]' + LineEnding +
      '[Integrated Servicing Stack Updates] [Count: 1]' + LineEnding +
      '[Windows Defender Security Intelligence] [Count: 0]' + LineEnding +
      '[Microsoft Office Updates] [Count: 2]' + LineEnding +
      '[Modern Extras & Runtimes] [Count: 1]' + LineEnding +
      '[Other Components] [Count: 0]' + LineEnding +
      'Audit Result: Updates required [7 item(s) missing]' + LineEnding;
    Check(SpineParseAuditReport(Sl, Counts),
      'audit append: report recognized across two appended blocks');
    CheckEq(IntToStr(Counts.Total), '7', 'audit append: the LAST report total wins');
    CheckEq(IntToStr(Counts.Lcu), '3', 'audit append: the LAST report lcu wins');
    Check(Pos('Updates required', Counts.ResultLine) > 0,
      'audit append: the LAST report result line wins');
  finally
    Sl.Free;
  end;
end;

procedure TestAuditReportFreshness;
begin
  { baseline absent, still absent -> nothing to show }
  Check(not SpineAuditReportIsFresh(-1, -1),
    'audit fresh: absent before and after -> not fresh');
  { baseline absent, now present -> this run wrote it }
  Check(SpineAuditReportIsFresh(-1, 12345),
    'audit fresh: new file -> fresh');
  { present and unchanged -> a leftover of an earlier run (the false up-to-date bug) }
  Check(not SpineAuditReportIsFresh(12345, 12345),
    'audit fresh: unchanged leftover -> not fresh');
  { present and rewritten -> this run wrote it }
  Check(SpineAuditReportIsFresh(12345, 12346),
    'audit fresh: rewritten file -> fresh');
  { present before, gone after -> nothing to show }
  Check(not SpineAuditReportIsFresh(12345, -1),
    'audit fresh: file vanished -> not fresh');
end;

procedure TestRunOnceResume;
var
  Name, Data: string;
  LongPath: string;
  MarkerDir: string;
begin
  { Builder shape (threat T-26-06): '!'-prefixed name, quoted exe +
    /resume only. }
  Check(ResBuildRunOnceValue('C:\client\UpdateInstallerLegacy.exe', Name, Data),
    'runonce: builder succeeds for a normal path');
  CheckEq(Name, '!WOUResume', 'runonce: value name carries the ! prefix');
  Check(Copy(Data, 1, 1) = '"', 'runonce: data opens with a quote');
  Check(Copy(Data, Length(Data) - Length(' /resume') + 1,
        Length(' /resume')) = ' /resume',
    'runonce: data ends with the /resume flag');
  Check(Pos('\', Data) > 0, 'runonce: data carries the exe path');
  Check(Length(Data) <= RES_RUNONCE_MAX,
    'runonce: composed command within the 260-char limit');

  { Hard 260-char refusal on an oversized path. }
  LongPath := 'C:\client\' + StringOfChar('d', 300) + '.exe';
  Check(not ResBuildRunOnceValue(LongPath, Name, Data),
    'runonce: oversized command line refused');
  CheckEq(Data, '', 'runonce: refused build leaves the data empty');

  { /resume decision matrix (staging present/absent). }
  Check(ResStagingPresentIn(GTempDir) = False,
    'resume: empty staging dir -> nothing to resume');
  ForceDirectories(IncludeTrailingPathDelimiter(GTempDir) + 'staging');
  WriteFixture('staging\' + ENG_STAGING_UPDATES, 'u1' + LineEnding);
  Check(ResStagingPresentIn(
      IncludeTrailingPathDelimiter(GTempDir) + 'staging'),
    'resume: WOUpdatesToInstall.txt present -> resume the stage');
  SysUtils.DeleteFile(IncludeTrailingPathDelimiter(GTempDir) + 'staging'
    + '\' + ENG_STAGING_UPDATES);
  WriteFixture('staging\' + ENG_STAGING_STAGE_CMD,
    '@set UPDATE_STAGE=1' + LineEnding);
  Check(ResStagingPresentIn(
      IncludeTrailingPathDelimiter(GTempDir) + 'staging'),
    'resume: SetWOUpdateStage.cmd present -> resume the stage');

  { Pending marker (reboots before the engine staged anything): the
    decision is staging OR marker, and the marker has its own lifecycle. }
  MarkerDir := IncludeTrailingPathDelimiter(GTempDir) + 'resumemarker';
  ForceDirectories(MarkerDir);
  Check(not ResResumePendingIn(MarkerDir),
    'resume: no staging and no marker -> nothing to resume');
  Check(ResMarkerWriteIn(MarkerDir),
    'resume: marker write succeeds');
  Check(ResMarkerPresentIn(MarkerDir),
    'resume: marker present after write');
  Check(ResResumePendingIn(MarkerDir),
    'resume: marker alone (reboot before staging) -> resume the run');
  ResMarkerDeleteIn(MarkerDir);
  Check(not ResMarkerPresentIn(MarkerDir),
    'resume: marker gone after delete');
  Check(not ResResumePendingIn(MarkerDir),
    'resume: marker deleted and no staging -> nothing to resume');
  { staging alone still resumes (the pre-existing contract). }
  Check(ResResumePendingIn(
      IncludeTrailingPathDelimiter(GTempDir) + 'staging'),
    'resume: staging alone still resumes the run');
  { deleting a marker that is not there is harmless. }
  ResMarkerDeleteIn(MarkerDir);
  Check(not ResMarkerPresentIn(MarkerDir),
    'resume: deleting an absent marker is harmless');

  { The engine's own automatic recall (legacy /autoreboot) owns the
    continuation: the GUI resume must detect it and stay out. }
  Check(not ResEngineRecallPreparedIn(MarkerDir),
    'resume: no WOURecall directory -> engine recall not prepared');
  ForceDirectories(IncludeTrailingPathDelimiter(MarkerDir) + 'WOURecall');
  Check(not ResEngineRecallPreparedIn(MarkerDir),
    'resume: empty WOURecall directory -> engine recall not prepared');
  WriteFixture('resumemarker\WOURecall\RecallUpdate.cmd',
    '@echo recall' + LineEnding);
  Check(ResEngineRecallPreparedIn(MarkerDir),
    'resume: WOURecall\\RecallUpdate.cmd present -> engine recall prepared');
  { the marker and the engine recall are independent signals. }
  Check(not ResResumePendingIn(MarkerDir),
    'resume: engine recall alone is not a GUI-pending run');
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

procedure TestSelfUpdateCore;
var
  ZipUrl, HashesUrl: string;
  Scheme, Host, ObjPath: string;
  Port: DWORD;
  Today, Yesterday: string;
  Ok: Boolean;
begin
  { ---- channel version parsing (battery section a channel matrix) ---- }
  CheckEq(SUParseChannelVersion('9.0.0+2099.01,release' + #13#10),
    '9.0.0+2099.01', 'selfupdate: channel 9.0.0+2099.01,release parses');
  CheckEq(SUParseChannelVersion('6.0.2+2026.11,release' + #13#10),
    '6.0.2+2026.11', 'selfupdate: channel 6.0.2+2026.11,release parses');
  CheckEq(SUParseChannelVersion('  9.0.1+2099.01,release  ' + #13#10),
    '9.0.1+2099.01', 'selfupdate: channel CRLF + surrounding spaces parses');
  CheckEq(SUParseChannelVersion('not-a-channel-file' + #13#10), '',
    'selfupdate: channel garbage rejects');
  CheckEq(SUParseChannelVersion('1.0.0,a,b' + #13#10), '',
    'selfupdate: channel multi-comma rejects');
  CheckEq(SUParseChannelVersion(''), '',
    'selfupdate: channel empty rejects');

  { ---- links parsing (battery section a links matrix) ---- }
  Check(SUParseLinksFile(
      'https://example.com/WsusOfflineNext-9.0.0.zip' + #13#10 +
      'https://example.com/WsusOfflineNext-9.0.0_hashes.txt' + #13#10,
      ZipUrl, HashesUrl)
    and (ZipUrl = 'https://example.com/WsusOfflineNext-9.0.0.zip')
    and (HashesUrl = 'https://example.com/WsusOfflineNext-9.0.0_hashes.txt'),
    'selfupdate: links https zip + hashes pair parses');
  Check(not SUParseLinksFile(
      'https://example.com/WsusOfflineNext-9.0.0.zip' + #13#10,
      ZipUrl, HashesUrl),
    'selfupdate: links missing second line rejects');
  { The http:// pair must reject with the hook unset - the shipped
    default (the env is cleared defensively so a stale process env can
    never flip this case). }
  Windows.SetEnvironmentVariable('WSON_UPDATE_ALLOW_HTTP', nil);
  Check(not SUParseLinksFile(
      'http://example.com/WsusOfflineNext-9.0.0.zip' + #13#10 +
      'https://example.com/WsusOfflineNext-9.0.0_hashes.txt' + #13#10,
      ZipUrl, HashesUrl),
    'selfupdate: links http pair rejects while WSON_UPDATE_ALLOW_HTTP unset');
  Check(not SUParseLinksFile(
      'https://example.com/WsusOfflineNext-9.0.0.rar' + #13#10 +
      'https://example.com/WsusOfflineNext-9.0.0_files.txt' + #13#10,
      ZipUrl, HashesUrl),
    'selfupdate: links wrong suffixes reject');
  Check(not SUParseLinksFile(
      'https://example.com/WsusOfflineNext-9.0.0.zip' + #13#10 +
      'https://example.com/WsusOfflineNext-9.0.0_hashes.txt' + #13#10 +
      'https://example.com/third-line.txt' + #13#10,
      ZipUrl, HashesUrl),
    'selfupdate: links third non-empty line rejects');

  { ---- strict-newer comparator (WebView2Compat parity) ---- }
  Check(SUChannelNewer('9.0.0+2099.01', '6.0.2'),
    'selfupdate: comparator newer core offers');
  Check(not SUChannelNewer('6.0.2+2026.11', '6.0.2'),
    'selfupdate: comparator metadata-equal is not newer (strictness pin)');
  Check(not SUChannelNewer('5.9.9', '6.0.2'),
    'selfupdate: comparator older channel no offer');
  Check(SUChannelNewer('6.0.10', '6.0.9'),
    'selfupdate: comparator numeric not lexicographic');
  Check(SUChannelNewer('6.0.2.1', '6.0.2'),
    'selfupdate: comparator extra 4th part is newer');
  Check((not SUChannelNewer('', '6.0.2')) and (not SUChannelNewer('6.0.2', '')),
    'selfupdate: comparator empty input is False both directions');
  CheckEq(SUCoreVersion('6.0.2+2026.11'), '6.0.2',
    'selfupdate: core version strips the +metadata suffix');

  { ---- daily cache (battery section a cache matrix) ---- }
  Today := FormatDateTime('yyyy-mm-dd', Now);
  Yesterday := FormatDateTime('yyyy-mm-dd', Now - 1);
  Check(SUisCheckedToday(WriteFixture('su-cache-today.txt', Today)),
    'selfupdate: cache today-string reads checked-today');
  Check(not SUisCheckedToday(WriteFixture('su-cache-yesterday.txt', Yesterday)),
    'selfupdate: cache yesterday-string re-checks');
  Check(not SUisCheckedToday(WriteFixture('su-cache-garbage.txt', 'not-a-date')),
    'selfupdate: cache garbage re-checks');
  Check(not SUisCheckedToday(WriteFixture('su-cache-empty.txt', '')),
    'selfupdate: cache empty re-checks');

  { ---- kill-switch INI reader (battery section a ini matrix) ---- }
  Check(SUIniSelfUpdateDisabled(WriteFixture('su-ini-disabled.ini',
      '[Misc]' + LineEnding + 'w96=Enabled' + LineEnding +
      '[Control]' + LineEnding + '; comment' + LineEnding +
      '# comment' + LineEnding + 'SkipSelfUpdate=eNaBlEd' + LineEnding +
      'verify=Enabled' + LineEnding)),
    'selfupdate: ini kill-switch mixed case with comments disables');
  Check(not SUIniSelfUpdateDisabled(WriteFixture('su-ini-absent-key.ini',
      '[Control]' + LineEnding + 'verify=Enabled' + LineEnding +
      'autoreboot=Disabled' + LineEnding)),
    'selfupdate: ini key absent stays enabled');
  Check(not SUIniSelfUpdateDisabled(WriteFixture('su-ini-other-section.ini',
      '[Other]' + LineEnding + 'SkipSelfUpdate=Enabled' + LineEnding)),
    'selfupdate: ini other section stays enabled');
  Check(not SUIniSelfUpdateDisabled(
      GTempDir + '\su-ini-missing-file.ini'),
    'selfupdate: ini missing file stays enabled');

  { ---- SUSplitUrl (the fetch layer's URL split) ---- }
  Ok := SUSplitUrl('https://host/p?a=b', Scheme, Host, Port, ObjPath);
  Check(Ok and (Scheme = 'https') and (Host = 'host') and (Port = 0)
        and (ObjPath = '/p?a=b'),
    'selfupdate: spliturl https form defaults the port');
  Ok := SUSplitUrl('http://h:8080/x', Scheme, Host, Port, ObjPath);
  Check(Ok and (Scheme = 'http') and (Host = 'h') and (Port = 8080)
        and (ObjPath = '/x'),
    'selfupdate: spliturl explicit port parses');
  Check(not SUSplitUrl('not-a-url', Scheme, Host, Port, ObjPath),
    'selfupdate: spliturl garbage rejects');
end;

procedure TestSelfUpdateAccept;
{ Plan 29-02 accept-pipeline matrix: hashes-file parser fixtures (with a
  REAL digest through SUSha256File - the frame-free CNG path's
  ground-truth exercise, run after hundreds of console writes exactly
  like the shipped testrunner workload), the fail-closed verify gate,
  and the whole-archive zip-slip guard over real zips built with the
  zipper writer side. }
const
  FIX_BYTES = 'wson-selfupdate-accept-fixture-bytes';
  { sha256 of 76800 bytes of (i mod 256), i = 0.. ; pinned - the digest
    of a deterministic multi-chunk (>64KB) fixture. }
  BIG_DIGEST = 'f8b0585eb91f58c007a5634362c9f90d8543822c113f702523bc7b73408a9392';
var
  I: Integer;
  FixturePath, BigPath, ZipPath, HashesText, Hex: string;
  Big: AnsiString;
  Fs: TFileStream;
  HSize: Int64;
  HDigest: string;
  StageDir, EvilTarget, AbsDrive: string;
  Z: TZipper;
  Ok: Boolean;
begin
  { Deterministic fixtures in the runner temp dir (byte-exact - no
    trailing line ending, so the pinned digest is over exactly these
    bytes). }
  FixturePath := GTempDir + '\su-accept-fixture.dat';
  Fs := TFileStream.Create(FixturePath, fmCreate or fmShareDenyWrite);
  try
    Fs.WriteBuffer(FIX_BYTES[1], Length(FIX_BYTES));
  finally
    Fs.Free;
  end;
  GFixtures.Add(FixturePath);
  BigPath := GTempDir + '\su-accept-big.bin';
  SetLength(Big, 76800);
  for I := 1 to Length(Big) do
    Big[I] := AnsiChar((I - 1) mod 256);
  Fs := TFileStream.Create(BigPath, fmCreate or fmShareDenyWrite);
  try
    Fs.WriteBuffer(Big[1], Length(Big));
  finally
    Fs.Free;
  end;

  { ---- SUSha256File (the frame-free CNG path) ---- }
  Check(SUSha256File(FixturePath, Hex)
        and (Hex = 'a55e9f61523e1875c44892269b2e2f3548df333301ca79a24de1c2e7e7327808'),
    'selfupdate: sha256 small fixture matches the pinned digest');
  Check(SUSha256File(BigPath, Hex) and (Hex = BIG_DIGEST),
    'selfupdate: sha256 multi-chunk >64KB digest matches the pinned value');
  Check((not SUSha256File(GTempDir + '\su-accept-missing.bin', Hex))
        and (Hex = ''),
    'selfupdate: sha256 missing file fails closed');
  { empty-file digest: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 }
  Fs := TFileStream.Create(GTempDir + '\su-accept-empty.bin',
    fmCreate or fmShareDenyWrite);
  try
    { leave empty }
  finally
    Fs.Free;
  end;
  Check(SUSha256File(GTempDir + '\su-accept-empty.bin', Hex)
        and (Hex = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'),
    'selfupdate: sha256 empty file matches the published digest');

  { ---- hashes-file parser (hashdeep shape) ---- }
  Check(SUSha256File(FixturePath, Hex), 'selfupdate: fixture digest for parser cases');
  HashesText := '%%%% v1.0' + #13#10 + '%%%%' + #13#10
    + IntToStr(Length(FIX_BYTES)) + ',md5x,sha1x,' + Hex
    + ',wson-fix.dat' + #13#10;
  Check(SUParseHashesFile(HashesText, HSize, HDigest)
        and (HSize = Length(FIX_BYTES)) and (HDigest = Hex),
    'selfupdate: hashes parser accepts the well-formed hashdeep line');
  Check(not SUParseHashesFile(
      '%%%% v1.0' + #13#10 + '%%%%' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects header-only input');
  Check(not SUParseHashesFile(
      '%%%% v1.0' + #13#10 + IntToStr(Length(FIX_BYTES)) + ',md5x,sha1x,'
      + Uppercase(Hex) + ',wson-fix.dat' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects an uppercase hex digest');
  Check(not SUParseHashesFile(
      IntToStr(Length(FIX_BYTES)) + ',md5x,sha1x,' + Hex + ',a.dat' + #13#10
      + IntToStr(Length(FIX_BYTES)) + ',md5x,sha1x,' + Hex + ',b.dat' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects two data lines');
  Check(not SUParseHashesFile(
      IntToStr(Length(FIX_BYTES)) + ',md5x,sha1x' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects a 3-field line');
  Check(not SUParseHashesFile(
      IntToStr(Length(FIX_BYTES)) + ',,sha1x,' + Hex + ',a.dat' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects an empty field');
  Check(not SUParseHashesFile(
      '0,md5x,sha1x,' + Hex + ',a.dat' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects a zero size');
  Check(not SUParseHashesFile(
      IntToStr(Length(FIX_BYTES)) + ',md5x,sha1x,zz' + Hex + ',a.dat' + #13#10,
      HSize, HDigest),
    'selfupdate: hashes parser rejects a non-hex digest');

  { ---- SUVerifyZipAgainstHashes (fail-closed gate, end to end) ---- }
  ZipPath := GTempDir + '\su-accept-good.zip';
  Z := TZipper.Create;
  try
    Z.FileName := ZipPath;
    Z.Entries.AddFileEntry(FixturePath, 'wsusoffline/dir/fixture.dat');
    Z.ZipAllFiles;
  finally
    Z.Free;
  end;
  SUSha256File(ZipPath, Hex);
  SUFileSizeOf(ZipPath, HSize);
  HashesText := '%%%%' + #13#10 + IntToStr(HSize) + ',md5x,sha1x,' + Hex
    + ',release.zip' + #13#10;
  Check(SUVerifyZipAgainstHashes(ZipPath, HashesText),
    'selfupdate: verify gate accepts the matching zip (size + digest)');
  Check(not SUVerifyZipAgainstHashes(ZipPath,
      '%%%%' + #13#10 + IntToStr(HSize + 1) + ',md5x,sha1x,' + Hex
      + ',release.zip' + #13#10),
    'selfupdate: verify gate rejects a wrong published size');
  Check(not SUVerifyZipAgainstHashes(ZipPath,
      '%%%%' + #13#10 + IntToStr(HSize) + ',md5x,sha1x,'
      + StringReplace(Hex, 'a', 'b', [rfReplaceAll]) + ',release.zip'
      + #13#10),
    'selfupdate: verify gate rejects a wrong digest');
  Check(not SUVerifyZipAgainstHashes(GTempDir + '\su-accept-missing.zip',
      HashesText),
    'selfupdate: verify gate fails closed on a missing zip (never raises)');
  Check(not SUVerifyZipAgainstHashes(ZipPath, 'not-a-hashes-file'),
    'selfupdate: verify gate fails closed on unparsable hashes');

  { ---- SUExtractGuarded (whole-archive zip-slip refusal) ---- }
  StageDir := GTempDir + '\su-accept-stage';
  SysUtils.DeleteFile(StageDir + '\wsusoffline\dir\fixture.dat');
  RemoveDir(StageDir + '\wsusoffline\dir');
  RemoveDir(StageDir + '\wsusoffline');
  Check(SUExtractGuarded(ZipPath, StageDir)
        and FileExists(StageDir + '\wsusoffline\dir\fixture.dat'),
    'selfupdate: guard extracts a safe nested archive');
  EvilTarget := GTempDir + '\evil.txt';
  SysUtils.DeleteFile(EvilTarget);
  ZipPath := GTempDir + '\su-accept-evil.zip';
  Fs := TFileStream.Create(GTempDir + '\su-accept-seed.dat',
    fmCreate or fmShareDenyWrite);
  try
    Fs.WriteBuffer(FIX_BYTES[1], Length(FIX_BYTES));
  finally
    Fs.Free;
  end;
  Z := TZipper.Create;
  try
    Z.FileName := ZipPath;
    Z.Entries.AddFileEntry(GTempDir + '\su-accept-seed.dat',
      'wsusoffline/safe/seed.dat');
    Z.Entries.AddFileEntry(GTempDir + '\su-accept-seed.dat', '../evil.txt');
    Z.ZipAllFiles;
  finally
    Z.Free;
  end;
  StageDir := GTempDir + '\su-accept-stage-evil';
  Ok := not SUExtractGuarded(ZipPath, StageDir);
  Check(Ok and (not FileExists(EvilTarget))
        and (not FileExists(StageDir + '\wsusoffline\safe\seed.dat')),
    'selfupdate: guard refuses a ../evil.txt archive whole (nothing extracted)');
  { Absolute-path entry name - drive of the temp dir. }
  AbsDrive := Copy(ExcludeTrailingPathDelimiter(GTempDir), 1, 2) + '\wson-abs-evil.txt';
  SysUtils.DeleteFile(AbsDrive);
  ZipPath := GTempDir + '\su-accept-abs.zip';
  Z := TZipper.Create;
  try
    Z.FileName := ZipPath;
    { NOTE: FPC 3.2.2 TZipper crashes on MIXED file+stream entries in
      one ZipAllFiles (EFOpenError on the file entry) - file entries
      with explicit archive names only. }
    Z.Entries.AddFileEntry(GTempDir + '\su-accept-seed.dat', AbsDrive);
    Z.ZipAllFiles;
  finally
    Z.Free;
  end;
  StageDir := GTempDir + '\su-accept-stage-abs';
  Ok := not SUExtractGuarded(ZipPath, StageDir);
  Check(Ok and (not FileExists(AbsDrive)),
    'selfupdate: guard refuses an absolute-path entry');
end;

procedure TestRegistryValueToString;
const
  CKEY = 'Software\WOUTest26Val';
var
  R: TRegistry;
  B: array[0..1] of Byte;
  KeyExisted: Boolean;
  Probe: TRegistry;
begin
  { 26-04 Win7 x86 battery regression pin: TRegistry.ReadString RAISES
    ERegistryException on a DWORD-typed value; RegValueToString is the
    au3-RegRead-tolerant reader every registry probe goes through
    (DWORD -> decimal string, REG_SZ/EXPAND_SZ -> text, other types ->
    ''). Staged under HKCU, deleted after; the WSH end-to-end leg runs
    only when the real policy key is absent on this host. }
  Probe := TRegistry.Create(KEY_ALL_ACCESS);
  try
    Probe.RootKey := HKEY_CURRENT_USER;
    KeyExisted := Probe.KeyExists(CKEY);
    if KeyExisted then
      Probe.DeleteKey(CKEY); { stale scratch from a crashed prior run }
  finally
    Probe.Free;
  end;
  R := TRegistry.Create(KEY_ALL_ACCESS);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if not R.OpenKey(CKEY, True) then
    begin
      Check(False, 'regval: could not stage the HKCU scratch key');
      Exit;
    end;
    R.WriteInteger('DwordVal', 528029);
    R.WriteInteger('DwordZero', 0);
    R.WriteString('SzVal', 'abc');
    R.WriteExpandString('ExpSzVal', '%SystemRoot%');
    B[0] := 1;
    B[1] := 2;
    R.WriteBinaryData('BinVal', B[0], SizeOf(B));
    Check(RegValueToString(R, 'DwordVal') = '528029',
      'regval: DWORD value reads as its decimal string (au3 RegRead parity)');
    Check(RegValueToString(R, 'DwordZero') = '0',
      'regval: DWORD zero reads as 0 (the WSH Enabled=0 spelling)');
    Check(RegValueToString(R, 'SzVal') = 'abc',
      'regval: REG_SZ reads as text');
    Check(RegValueToString(R, 'ExpSzVal') <> '',
      'regval: REG_EXPAND_SZ reads without raising');
    Check(RegValueToString(R, 'BinVal') = '',
      'regval: binary value reads as empty (au3 absent-comparison behavior)');
    Check(RegValueToString(R, 'MissingVal') = '',
      'regval: missing value reads as empty');
    R.CloseKey;
    R.DeleteKey(CKEY);
    Check(not R.KeyExists(CKEY), 'regval: scratch key deleted after the test');
  finally
    R.Free;
  end;
  if KeyExisted then
    Exit; { pre-existing policy key on this host - skip the WSH leg }
  R := TRegistry.Create(KEY_ALL_ACCESS);
  try
    R.RootKey := HKEY_CURRENT_USER;
    if not R.OpenKey('Software\Microsoft\Windows Script Host\Settings', True) then
    begin
      Check(False, 'wsh-e2e: could not stage the HKCU WSH scratch key');
      Exit;
    end;
    R.WriteInteger('Enabled', 0);
    Check(not DetectWSHAvailable,
      'wsh-e2e: DWORD Enabled=0 reads without raising and disables WSH');
    R.WriteInteger('Enabled', 1);
    Check(DetectWSHAvailable,
      'wsh-e2e: DWORD Enabled=1 keeps WSH available');
    R.DeleteValue('Enabled');
    Check(DetectWSHAvailable,
      'wsh-e2e: value removed restores the default');
  finally
    R.Free;
  end;
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
    TestOsGate;
    TestPathValid;
    TestUncSplit;
    TestPickFreeLetter;
    TestLanguageSelect;
    TestIniMergeOrder;
    TestSysNativeMatrix;
    TestArgvEmission;
    TestMsiContract;
    TestProgressParsing;
    TestWatcherCounts;
    TestAuditReportParsing;
    TestRunOnceResume;
    TestAuditReportFreshness;
    TestAuditParserLastReportWins;
    TestCompletionMatrix;
    TestSelfUpdateCore;
    TestSelfUpdateAccept;
    TestRegistryValueToString;
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
