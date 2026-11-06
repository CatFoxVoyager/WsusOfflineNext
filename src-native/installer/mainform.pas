{*** Main form of the native installer - full incumbent option surface.

    Parity port of the incumbent installer au3 (the extraction source at
    present until plan 03 deletes it):
    - caption from the exe's own VERSIONINFO (versionless fallback until
      plan 03), the incumbent intro label, the Medium-info group
    - the Updating tab with the Installation group (ten toggles in the
      incumbent two-column grid + the gray Office info label) and the
      Control group (verify / autoreboot / shutdown / showlog / auditonly)
    - gating VERBATIM through the pure detection gates: presence probes,
      .NET release-vs-target + forced-checked rule, WMF OS/main-version
      rule, enablement three-state + ineligible override, autoreboot
      (DESIGNED INST-05 change: Win10+ enabled via the RunOnce path,
      <=8.1 legacy autologon path with its UAC/share warnings), shutdown/
      showlog and auditonly couplings
    - INI layer: EngMyIniRead/EngDefaultIniRead parity, the full IniCopy
      (14 toggle keys; per-MSI keys land with the Software tab in task 2,
      /autoreboot-present skip rule) and the WUStatusServer pre-launch
      registry write
    - Start: the pure frozen argv emission, the engine spine run, and the
      bilingual summary line

    argv emission goes ONLY through the enginecontracts switch table keyed
    by checkbox state - never raw INI text (threat T-26-01). }

unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Messages, IniFiles,
  Forms, Controls, Graphics, Dialogs, StdCtrls, ComCtrls, Process, ShellApi,
  enginecontracts, strings_de_en, enginespine, detection, buildsupgrade,
  resume, selfupdate;

type

  { TMainForm }

  TMainForm = class(TForm)
    btnStart: TButton;
    btnExit: TButton;
    btnCancel: TButton;
    lblIntro: TLabel;
    grpMedium: TGroupBox;
    lblBuild: TLabel;
    pcTabs: TPageControl;
    tsUpdating: TTabSheet;
    grpInstallation: TGroupBox;
    chkUpgradeBuilds: TCheckBox;
    chkRcerts: TCheckBox;
    chkDotNet35: TCheckBox;
    chkDotNet4: TCheckBox;
    chkWmf: TCheckBox;
    chkDotNet5: TCheckBox;
    chkUpdateCpp: TCheckBox;
    chkInstEdge: TCheckBox;
    chkInstWebView2: TCheckBox;
    chkUpdateOffice: TCheckBox;
    lblOffice: TLabel;
    grpControl: TGroupBox;
    chkVerify: TCheckBox;
    chkAutoReboot: TCheckBox;
    chkShutdown: TCheckBox;
    chkShowLog: TCheckBox;
    chkAuditOnly: TCheckBox;
    memoProgress: TMemo;
    lblStatus: TLabel;
    btnOpenReport: TButton;
    procedure btnCancelClick(Sender: TObject);
    procedure btnExitClick(Sender: TObject);
    procedure btnOpenReportClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure chkAuditOnlyClick(Sender: TObject);
    procedure chkAutoRebootClick(Sender: TObject);
    procedure chkDotNet4Click(Sender: TObject);
    procedure chkShutdownClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  public
    { Headless resume entry (INST-05): the /resume startup path calls
      this after the form has restored the toggle set from the INI. }
    procedure StartRun;
  private
  private
    FExeDir: string;
    FScriptDir: string;
    FCmdDir: string;
    FClientIni: string;
    FCallerTempIni: string;
    FMapped: Boolean;
    FRunning: Boolean;
    FSpine: TEngineSpine;
    FLastCounts: TSpineOutcomeCounts;
    FLastCountsRaw: string; { change-guard for the live status label }
    FAuditReportPath: string;
    FSwitches: string;      { the argv of the current/last run }
    { Detection snapshot for the cross-gating click handlers. }
    FOs: TOsInfo;
    FOsModern: Boolean;
    FOsArch: string;
    FDotNet4MainVersion: string;
    FWMFAtTarget: Boolean; { WMF already at target (au3 equality rule) }
    FScriptDirIsNetwork: Boolean;
    { Enablement data (shipped builds.txt; empty until the file ships). }
    FBuildRows: TBuildRows;
    { Software tab state - the $msimax=10 cap of the au3 array is GONE:
      the dynamic checkbox list grows with the actual package census. }
    tsSoftware: TTabSheet;
    FMsiAll: TCheckBox;
    sbMsi: TScrollBox;
    FMsiChecks: array of TCheckBox;
    FMsiNames: TStringList;
    { MyIniRead parity (au3:220-229) - client INI default, %TEMP% copy
      overrides per key. }
    function IniState(const ASection, AKey, ADefault: string): string;
    { DefaultIniRead parity (au3:216-218) - client INI only; the hidden
      INI-driven switches and the info-dialog gates read HERE, not from
      the %TEMP% copy. }
    function DefIniState(const ASection, AKey, ADefault: string): string;
    function IniEnabled(const ASection, AKey, ADefault: string): Boolean;
    procedure ApplyToggleGating;
    procedure ShowStartupGates;
    procedure ShowStartupInfoDialogs;
    procedure ShowBox(const AMsg: string; const ATitle: TStringId;
      AWarning: Boolean);
    procedure ListMsiPackages;
    procedure BuildSoftwareTab;
    procedure MsiAllClick(Sender: TObject);
    procedure MsiCheckClick(Sender: TObject);
    procedure IniCopyAll;
    procedure BuildArgvFromToggles(out AToggles: TArgvToggles);
    procedure SpineLine(const ALine: string);
    procedure SpineIdle;
    procedure SpineWatch;
    procedure RenderOutcomeState(Res: TSpineResult);
    procedure RenderAuditView;
    procedure HandleRebootOutcome(Res: TSpineResult);
  end;

var
  { NOT named MainForm: that identifier is taken by the unit itself. }
  InstallerForm: TMainForm;

implementation

{$R *.lfm}

{ Incumbent CheckBoxStateToString: the INI state vocabulary is the frozen
  Enabled/Disabled pair. }
function CheckedState(AChecked: Boolean): string;
begin
  if AChecked then
    Result := ENG_INI_ENABLED
  else
    Result := ENG_INI_DISABLED;
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
var
  BuildDate: string;
begin
  FExeDir := IncludeTrailingPathDelimiter(ExtractFilePath(Application.ExeName));
  FCallerTempIni := IncludeTrailingPathDelimiter(EngCallerTempDir)
    + ENG_TEMP_INI_NAME;
  FClientIni := FExeDir + ENG_TEMP_INI_NAME;
  { Self-update check thread (Phase 29, Phase 28 parity port): started
    right after the client INI path is known and BEFORE the startup
    gates, fire-and-forget - the frozen check order (kill-switch INI,
    daily cache, network) runs on its own thread and a gate failure on
    an odd machine cannot silently kill the check. }
  TSelfUpdateCheckThread.Create(FClientIni, 'installer-legacy');
  FSpine := TEngineSpine.Create;
  FRunning := False;

  Caption := EngWindowCaption;
  lblIntro.Caption := StringsGet(siIntro);
  grpMedium.Caption := StringsGet(siMediumGroup);
  tsUpdating.Caption := StringsGet(siTabUpdating);
  grpInstallation.Caption := StringsGet(siGrpInstallation);
  grpControl.Caption := StringsGet(siGrpControl);
  chkUpgradeBuilds.Caption := StringsGet(siToggleUpgradeBuilds);
  chkRcerts.Caption := StringsGet(siToggleRcerts);
  chkDotNet35.Caption := StringsGet(siToggleDotNet35);
  chkDotNet5.Caption := StringsGet(siToggleDotNet5);
  chkUpdateCpp.Caption := StringsGet(siToggleCpp);
  chkInstEdge.Caption := StringsGet(siToggleEdge);
  chkInstWebView2.Caption := StringsGet(siToggleWebView2);
  chkUpdateOffice.Caption := StringsGet(siToggleOffice);
  chkVerify.Caption := StringsGet(siToggleVerify);
  chkAutoReboot.Caption := StringsGet(siToggleAutoReboot);
  chkShutdown.Caption := StringsGet(siToggleShutdown);
  chkShowLog.Caption := StringsGet(siToggleShowLog);
  chkAuditOnly.Caption := StringsGet(siToggleAudit);
  btnStart.Caption := StringsGet(siBtnStart);
  btnExit.Caption := StringsGet(siBtnExit);
  btnCancel.Caption := StringsGet(siBtnCancel);
  btnOpenReport.Caption := StringsGet(siBtnOpenReport);
  lblOffice.Font.Color := DET_OFFICE_LABEL_COLOR;
  memoProgress.Lines.Clear;
  lblStatus.Caption := '';
  btnOpenReport.Visible := False;
  FillChar(FLastCounts, SizeOf(FLastCounts), 0);
  FLastCountsRaw := '';
  FAuditReportPath := '';

  { Script directory + share mapping (au3:614 / 170-202). The mapped
    drive stays alive while the GUI runs (the incumbent unmaps only on
    close/exit). }
  FScriptDir := DetectAssignScriptDirectory(FExeDir, FMapped);
  if FScriptDir <> '' then
    FCmdDir := IncludeTrailingPathDelimiter(FScriptDir) + 'cmd'
  else
    FCmdDir := '';
  FScriptDirIsNetwork := DetectIsNetworkPath(FScriptDir);

  { Medium info group (au3:625-638). }
  BuildDate := DetectMediumBuildDate(FScriptDir);
  if BuildDate <> '' then
  begin
    grpMedium.Visible := True;
    lblBuild.Caption := Format(StringsGet(siBuildLabel), [BuildDate]);
  end
  else
    grpMedium.Visible := False;

  { Detection snapshot for the gates + click handlers. }
  FOs := DetectOsInfo;
  FOsModern := OsIsWin10OrNewer(FOs);
  FOsArch := DetectOsArchToken;
  FDotNet4MainVersion := DetectDotNet4MainVersion;
  FWMFAtTarget := DetectWMFMainVersion = DET_WMF_TARGET_VERSION;
  FBuildRows := BuLoadRows(FScriptDir);

  { Startup gates (au3:1018-1057): the OS and WSH gates already ran in
    the program entry - the assignment/path gates run here. }
  ShowStartupGates;

  { Full option surface (au3:640-981). }
  ApplyToggleGating;

  { Informational dialogs (au3:1058-1096) - after the toggles, like the
    incumbent's pre-loop sequence. }
  ShowStartupInfoDialogs;

  { Software tab - /listall once at construction, read-then-delete of the
    listing, tab built ONLY when packages exist (au3:944-977). }
  FMsiNames := TStringList.Create;
  ListMsiPackages;
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  { DriveMapDel parity (au3:1102-1110): release the mapping we created. }
  if FMapped then
    DetectReleaseScriptDirectory(FScriptDir);
  FreeAndNil(FSpine);
  FreeAndNil(FMsiNames);
end;

procedure TMainForm.ShowBox(const AMsg: string; const ATitle: TStringId;
  AWarning: Boolean);
begin
  if AWarning then
    Application.MessageBox(PChar(AMsg), PChar(StringsGet(ATitle)),
      MB_TASKMODAL or MB_ICONEXCLAMATION or MB_OK)
  else
    Application.MessageBox(PChar(AMsg), PChar(StringsGet(ATitle)),
      MB_TASKMODAL or MB_ICONINFORMATION or MB_OK);
end;

procedure TMainForm.ShowStartupGates;
begin
  if FScriptDir = '' then
  begin
    Application.MessageBox(
      PChar(Format(StringsGet(siScriptDirAssignError), [FExeDir])),
      PChar(StringsGet(siErrorTitle)),
      MB_TASKMODAL or MB_ICONERROR or MB_OK);
    Halt(1);
  end;
  if not EngPathValid(FScriptDir) then
  begin
    Application.MessageBox(
      PChar(Format(StringsGet(siPathScriptDirError),
        [ENG_PATH_MAX_LENGTH, ENG_PATH_INVALID_CHARS])),
      PChar(StringsGet(siErrorTitle)),
      MB_TASKMODAL or MB_ICONERROR or MB_OK);
    Halt(1);
  end;
  if not EngPathValid(EngCallerTempDir) then
  begin
    Application.MessageBox(
      PChar(Format(StringsGet(siPathTempError),
        [ENG_PATH_MAX_LENGTH, ENG_PATH_INVALID_CHARS])),
      PChar(StringsGet(siErrorTitle)),
      MB_TASKMODAL or MB_ICONERROR or MB_OK);
    Halt(1);
  end;
  { au3:1048-1057 - the %%TEMP%% escape in the table keeps Format happy. }
  if (Length(EngCallerTempDir) > 0)
     and ((EngCallerTempDir[Length(EngCallerTempDir)] = '\')
          or (EngCallerTempDir[Length(EngCallerTempDir)] = ':')) then
  begin
    Application.MessageBox(
      PChar(Format(StringsGet(siTempTrailingError), [])),
      PChar(StringsGet(siErrorTitle)),
      MB_TASKMODAL or MB_ICONERROR or MB_OK);
    Halt(1);
  end;
end;

function TMainForm.IniState(const ASection, AKey, ADefault: string): string;
begin
  Result := EngMyIniRead(FClientIni, FCallerTempIni, ASection, AKey, ADefault);
end;

function TMainForm.DefIniState(const ASection, AKey, ADefault: string): string;
begin
  Result := EngDefaultIniRead(FClientIni, ASection, AKey, ADefault);
end;

function TMainForm.IniEnabled(const ASection, AKey, ADefault: string): Boolean;
begin
  Result := SameText(IniState(ASection, AKey, ADefault), ENG_INI_ENABLED);
end;

procedure TMainForm.ApplyToggleGating;
var
  Gate: TGateState;
  CurrRelease, TargetRelease, TargetDisplay: string;
  Enforced: Integer;
  AvailNormal, AvailEnf, Ineligible: Boolean;
begin
  { ----- Installation group (au3:652-851) ----- }

  { Feature Update via Enablement Package - three-state + ineligible
    override (au3:665-691). }
  Enforced := BuBuildUpgradeEnforced(FBuildRows, IntToStr(FOs.Build), FOsArch);
  AvailNormal := BuBuildUpgradeAvailable(FBuildRows, FScriptDir, 0,
    IntToStr(FOs.Build), FOsArch, @BuFileProbe) = 1;
  AvailEnf := BuBuildUpgradeAvailable(FBuildRows, FScriptDir, 1,
    IntToStr(FOs.Build), FOsArch, @BuFileProbe) = 1;
  Ineligible := BuIsBuildIneligible(FBuildRows, IntToStr(FOs.Build));
  Gate := GateEnablement(Enforced, AvailNormal, AvailEnf,
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'upgradebuilds',
      ENG_INI_ENABLED));
  chkUpgradeBuilds.Enabled := Gate.Enabled;
  chkUpgradeBuilds.Checked := Gate.Checked;
  if Ineligible then
  begin
    chkUpgradeBuilds.Checked := False;
    chkUpgradeBuilds.Enabled := False;
    ShowBox(Format(StringsGet(siIneligibleBuildInfo),
      [IntToStr(FOs.Build)]), siInfoTitle, False);
  end;

  { Update Root Certificates (au3:693-708). }
  Gate := GatePresence(DetectRootCertificatesPresent(FScriptDir),
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'updatercerts',
      ENG_INI_ENABLED));
  chkRcerts.Enabled := Gate.Enabled;
  chkRcerts.Checked := Gate.Checked;

  { Install .NET Framework 3.5 - always offerable (au3:710-722). }
  Gate := GatePlainToggle(IniEnabled(ENG_INI_SECTION_INSTALLATION,
    'instdotnet35', ENG_INI_DISABLED));
  chkDotNet35.Enabled := Gate.Enabled;
  chkDotNet35.Checked := Gate.Checked;

  { Install .NET Framework <target> (au3:724-744). }
  CurrRelease := DetectDotNet4Release;
  TargetRelease := DetectDotNet4TargetRelease(FOs);
  TargetDisplay := DetectDotNet4ReleaseToDisplay(TargetRelease);
  chkDotNet4.Caption := Format(StringsGet(siToggleDotNet4), [TargetDisplay]);
  Gate := GateDotNet4(CurrRelease, TargetRelease,
    DetectDotNet4InstPresent(FScriptDir, TargetDisplay),
    FDotNet4MainVersion,
    DetectDotNet4ReleaseToDisplay(CurrRelease),
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'instdotnet4',
      ENG_INI_DISABLED));
  chkDotNet4.Enabled := Gate.Enabled;
  chkDotNet4.Checked := Gate.Checked;

  { Install Management Framework <target> (au3:746-763). }
  chkWmf.Caption := Format(StringsGet(siToggleWmf), [DET_WMF_TARGET_VERSION]);
  Gate := GateWmf(FOsModern, FDotNet4MainVersion, FWMFAtTarget,
    chkDotNet4.Checked,
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'instwmf', ENG_INI_DISABLED));
  chkWmf.Enabled := Gate.Enabled;
  chkWmf.Checked := Gate.Checked;

  { Update .NET Framework 5 (and newer) - always offerable (au3:765-777). }
  Gate := GatePlainToggle(IniEnabled(ENG_INI_SECTION_INSTALLATION,
    'updatedotnet5', ENG_INI_DISABLED));
  chkDotNet5.Enabled := Gate.Enabled;
  chkDotNet5.Checked := Gate.Checked;

  { Update C++ Runtime Libraries (au3:779-794). }
  Gate := GatePresence(DetectCppPresent(FScriptDir),
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'updatecpp',
      ENG_INI_ENABLED));
  chkUpdateCpp.Enabled := Gate.Enabled;
  chkUpdateCpp.Checked := Gate.Checked;

  { Install Microsoft Edge (au3:796-812). }
  Gate := GatePresence(DetectEdgePresent(FScriptDir),
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'instedge',
      ENG_INI_DISABLED));
  chkInstEdge.Enabled := Gate.Enabled;
  chkInstEdge.Checked := Gate.Checked;

  { Install Edge WebView2 Runtime (au3:814-829). }
  Gate := GatePresence(DetectWebView2Present(FScriptDir),
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'instwebview2',
      ENG_INI_DISABLED));
  chkInstWebView2.Enabled := Gate.Enabled;
  chkInstWebView2.Checked := Gate.Checked;

  { Update Microsoft Office + gray info label (au3:831-851). }
  lblOffice.Caption := DetectOffice16Description;
  Gate := GatePresence(DetectOffice16Detected,
    IniEnabled(ENG_INI_SECTION_INSTALLATION, 'updateoffice',
      ENG_INI_ENABLED));
  chkUpdateOffice.Enabled := Gate.Enabled;
  chkUpdateOffice.Checked := Gate.Checked;

  { ----- Control group (au3:853-942) ----- }

  { Verify installation packages (au3:862-878). }
  Gate := GatePresence(DetectHashFilesPresent(FScriptDir),
    IniEnabled(ENG_INI_SECTION_CONTROL, 'verify', ENG_INI_ENABLED));
  chkVerify.Enabled := Gate.Enabled;
  chkVerify.Checked := Gate.Checked;

  { Automatic reboot and recall (au3:880-895, INST-05 redesign). }
  Gate := GateAutoreboot(FOsModern,
    DetectAutologonPresent(FScriptDir),
    IniEnabled(ENG_INI_SECTION_CONTROL, 'autoreboot', ENG_INI_DISABLED));
  chkAutoReboot.Enabled := Gate.Enabled;
  chkAutoReboot.Checked := Gate.Checked;

  { Automatic shutdown (au3:897-909). }
  Gate := GatePlainToggle(IniEnabled(ENG_INI_SECTION_CONTROL, 'shutdown',
    ENG_INI_DISABLED));
  chkShutdown.Enabled := Gate.Enabled;
  chkShutdown.Checked := Gate.Checked;

  { Show log file (au3:911-926). }
  Gate := GateShowlog(
    IniEnabled(ENG_INI_SECTION_MESSAGING, 'showlog', ENG_INI_DISABLED),
    chkShutdown.Checked);
  chkShowLog.Enabled := Gate.Enabled;
  chkShowLog.Checked := Gate.Checked;

  { Audit only (au3:928-942) - a checked state disables both finish
    modes. }
  Gate := GatePlainToggle(IniEnabled(ENG_INI_SECTION_CONTROL, 'auditonly',
    ENG_INI_DISABLED));
  chkAuditOnly.Enabled := Gate.Enabled;
  chkAuditOnly.Checked := Gate.Checked;
  if chkAuditOnly.Checked then
  begin
    chkAutoReboot.Checked := False;
    chkAutoReboot.Enabled := False;
    chkShutdown.Checked := False;
    chkShutdown.Enabled := False;
  end;
end;

procedure TMainForm.ShowStartupInfoDialogs;
var
  IeMajor: string;
  ProgFilesIe: string;
begin
  { IE11-on-2012 info (au3:1058-1070): Windows Server 2012 R2 (6.3,
    server) with an old IE, skipieinst NOT enabled (client INI only) and
    showieinfo enabled. }
  if (FOs.Major = 6) and (FOs.Minor = 3) and (not FOs.Workstation) then
  begin
    ProgFilesIe := SysUtils.GetEnvironmentVariable('ProgramFiles')
      + '\Internet Explorer\iexplore.exe';
    IeMajor := DetectIEVersion;
    if FileExists(ProgFilesIe)
       and ((IeMajor = '8') or (IeMajor = '9') or (IeMajor = '10'))
       and (SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
              'skipieinst', ENG_INI_DISABLED), ENG_INI_DISABLED))
       and (SameText(DefIniState(ENG_INI_SECTION_MESSAGING,
              'showieinfo', ENG_INI_ENABLED), ENG_INI_ENABLED)) then
      ShowBox(StringsGet(siIe11Info), siInfoTitle, False);
  end;

  { .NET 4.6.2 info (au3:1072-1081). }
  if ((FDotNet4MainVersion = '4.5')
      or ((FDotNet4MainVersion = '4.6')
          and (DetectDotNet4ReleaseToDisplay(DetectDotNet4Release) <> '4.6.2')))
     and (SameText(DefIniState(ENG_INI_SECTION_MESSAGING, 'showdotnet4info',
            ENG_INI_ENABLED), ENG_INI_ENABLED)) then
    ShowBox(StringsGet(siDotNet462Info), siInfoTitle, False);

  { Enforced Enablement info/warning (au3:1082-1096). }
  if BuBuildUpgradeEnforced(FBuildRows, IntToStr(FOs.Build), FOsArch) > 0 then
  begin
    if BuBuildUpgradeAvailable(FBuildRows, FScriptDir, 1,
        IntToStr(FOs.Build), FOsArch, @BuFileProbe) = 1 then
      ShowBox(StringsGet(siEnablementEnforcedInfo), siInfoTitle, False)
    else
      ShowBox(StringsGet(siEnablementEnforcedWarning), siWarnTitle, True);
  end;
end;

procedure TMainForm.chkDotNet4Click(Sender: TObject);
begin
  { au3:1113-1120 verbatim - re-evaluate the WMF box. }
  if GateWmfReevaluate(FOsModern, FDotNet4MainVersion, FWMFAtTarget,
      chkDotNet4.Checked) then
    chkWmf.Enabled := True
  else
  begin
    chkWmf.Checked := False;
    chkWmf.Enabled := False;
  end;
end;

procedure TMainForm.chkAutoRebootClick(Sender: TObject);
begin
  { au3:1122-1156 with the INST-05 redesign: the UAC-disable and
    network-share warnings belong ONLY to the legacy (<=8.1) path - the
    modern Win10+ RunOnce path needs neither. }
  if chkAutoReboot.Checked and (not FOsModern) then
  begin
    if Application.MessageBox(
        PChar(StringsGet(siUacDisableWarning)),
        PChar(StringsGet(siWarnTitle)),
        MB_TASKMODAL or MB_DEFBUTTON2 or MB_ICONEXCLAMATION
          or MB_YESNO) = IDNO then
      chkAutoReboot.Checked := False;
  end;
  if chkAutoReboot.Checked and (not FOsModern) and FScriptDirIsNetwork then
  begin
    if Application.MessageBox(
        PChar(Format(StringsGet(siNetworkShareWarning),
          [ExtractFileName(Application.ExeName)])),
        PChar(StringsGet(siWarnTitle)),
        MB_TASKMODAL or MB_DEFBUTTON2 or MB_ICONEXCLAMATION
          or MB_YESNO) = IDNO then
      chkAutoReboot.Checked := False;
  end;
end;

procedure TMainForm.chkAuditOnlyClick(Sender: TObject);
var
  Gate: TGateState;
begin
  { au3:1158-1176 verbatim - with the INST-05 autoreboot rule. }
  if chkAuditOnly.Checked then
  begin
    chkAutoReboot.Checked := False;
    chkAutoReboot.Enabled := False;
    chkShutdown.Checked := False;
    chkShutdown.Enabled := False;
  end
  else
  begin
    Gate := GateAutoreboot(FOsModern,
      DetectAutologonPresent(FScriptDir),
      IniEnabled(ENG_INI_SECTION_CONTROL, 'autoreboot', ENG_INI_DISABLED));
    chkAutoReboot.Enabled := Gate.Enabled;
    chkAutoReboot.Checked := Gate.Checked;
    chkShutdown.Enabled := True;
    if IniEnabled(ENG_INI_SECTION_CONTROL, 'shutdown', ENG_INI_DISABLED) then
    begin
      chkShutdown.Checked := True;
      chkShowLog.Checked := False;
      chkShowLog.Enabled := False;
    end;
  end;
end;

procedure TMainForm.chkShutdownClick(Sender: TObject);
begin
  { au3:1178-1183 verbatim. }
  if chkShutdown.Checked then
  begin
    chkShowLog.Checked := False;
    chkShowLog.Enabled := False;
  end
  else
    chkShowLog.Enabled := True;
end;

procedure TMainForm.ListMsiPackages;
var
  P: TProcess;
  Buf: AnsiString;
  Chunk: AnsiString;
  Count: DWord;
  ListingPath: string;
begin
  { au3 ListMSIPackages (548-556): RunWait of TouchMSITree.cmd /listall
    in the cmd dir, hidden window. TProcess parity: absolute cmd.exe,
    pre-quoted single payload, pipes drained (never poWaitOnExit with
    pipes). Failures leave the listing absent = no Software tab, exactly
    the au3 FileExists branch (947). }
  ListingPath := IncludeTrailingPathDelimiter(EngCallerTempDir)
    + ENG_MSI_LISTING_NAME;
  if FileExists(ListingPath) then
    SysUtils.DeleteFile(ListingPath); { a stale listing must never mask a failed /listall }

  if (EngCmdExePath = '') or not FileExists(FCmdDir + '\TouchMSITree.cmd') then
    Exit;

  P := TProcess.Create(nil);
  try
    P.Executable := EngCmdExePath;
    P.Parameters.Add('/D');
    P.Parameters.Add('/C');
    P.Parameters.Add('".\TouchMSITree.cmd /listall"');
    P.CurrentDirectory := FCmdDir;
    P.Options := [poUsePipes, poNoConsole];
    try
      P.Execute;
    except
      Exit;
    end;
    Buf := '';
    while P.Running do
    begin
      Count := P.Output.NumBytesAvailable;
      if Count > 0 then
      begin
        SetLength(Chunk, Count);
        SetLength(Chunk, P.Output.Read(Chunk[1], Count));
        Buf := Buf + Chunk;
      end;
      Sleep(50);
    end;
    { Final drain + exit code ignored: the listing file is the contract. }
    Count := P.Output.NumBytesAvailable;
    if Count > 0 then
    begin
      SetLength(Chunk, Count);
      SetLength(Chunk, P.Output.Read(Chunk[1], Count));
      Buf := Buf + Chunk;
    end;
  finally
    P.Free;
  end;

  if not FileExists(ListingPath) then
    Exit;
  EngReadMsiListing(ListingPath, FMsiNames);
  SysUtils.DeleteFile(ListingPath); { read-then-DELETE (au3:975) }
  if FMsiNames.Count > 0 then
    BuildSoftwareTab;
end;

procedure TMainForm.BuildSoftwareTab;
var
  I: Integer;
  Chk: TCheckBox;
begin
  { au3:944-977 with the $msimax=10 cap lifted: one checkbox per listed
    package inside a scrollable container, per-package INI state, plus
    the select-all checkbox (au3:950-957). }
  tsSoftware := TTabSheet.Create(Self);
  tsSoftware.Caption := StringsGet(siTabSoftware);
  tsSoftware.PageControl := pcTabs;

  FMsiAll := TCheckBox.Create(tsSoftware);
  FMsiAll.Parent := tsSoftware;
  FMsiAll.Left := 8;
  FMsiAll.Top := 8;
  FMsiAll.Width := 252;
  FMsiAll.Caption := StringsGet(siMsiSelectAll);
  FMsiAll.OnClick := @MsiAllClick;

  sbMsi := TScrollBox.Create(tsSoftware);
  sbMsi.Parent := tsSoftware;
  sbMsi.Left := 8;
  sbMsi.Top := 34;
  sbMsi.Width := 528;
  sbMsi.Height := 300;
  sbMsi.Anchors := [akLeft, akTop, akRight, akBottom];
  sbMsi.BorderStyle := bsNone;
  sbMsi.VertScrollBar.Tracking := True;

  SetLength(FMsiChecks, FMsiNames.Count);
  for I := 0 to FMsiNames.Count - 1 do
  begin
    Chk := TCheckBox.Create(sbMsi);
    Chk.Parent := sbMsi;
    Chk.Left := 8;
    Chk.Top := 4 + I * 24;
    Chk.Width := 500;
    Chk.Caption := FMsiNames.Strings[I];
    Chk.Checked := IniEnabled(ENG_INI_SECTION_MSI, FMsiNames.Strings[I],
      ENG_INI_DISABLED);
    Chk.OnClick := @MsiCheckClick;
    FMsiChecks[I] := Chk;
  end;
end;

procedure TMainForm.MsiAllClick(Sender: TObject);
var
  I: Integer;
begin
  { au3:1185-1194 verbatim. }
  for I := 0 to High(FMsiChecks) do
    FMsiChecks[I].Checked := FMsiAll.Checked;
end;

procedure TMainForm.MsiCheckClick(Sender: TObject);
var
  I: Integer;
begin
  { au3:1196-1202 verbatim: any unchecked package unchecks select-all
    (never the reverse). }
  for I := 0 to High(FMsiChecks) do
    if not FMsiChecks[I].Checked then
    begin
      FMsiAll.Checked := False;
      Break;
    end;
end;

procedure TMainForm.IniCopyAll;
var
  I: Integer;
begin
  { au3 IniCopy (231-260) parity: byte copy of the client INI, read-only
    bit cleared, then every GUI toggle state written on top. The
    upgradebuilds key is deliberately NOT written - incumbent verbatim
    (au3:239-253). The /autoreboot-present path skips IniCopy entirely
    (au3:1264-1269, enforced by the caller). }
  if FileExists(FClientIni) then
  begin
    EngCopyFileRaw(FClientIni, FCallerTempIni);
    FileSetAttr(FCallerTempIni, FILE_ATTRIBUTE_NORMAL);
  end;
  with TIniFile.Create(FCallerTempIni) do
    try
      WriteString(ENG_INI_SECTION_INSTALLATION, 'updatercerts',
        CheckedState(chkRcerts.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'instdotnet35',
        CheckedState(chkDotNet35.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'instdotnet4',
        CheckedState(chkDotNet4.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'instwmf',
        CheckedState(chkWmf.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'updatedotnet5',
        CheckedState(chkDotNet5.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'updatecpp',
        CheckedState(chkUpdateCpp.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'instedge',
        CheckedState(chkInstEdge.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'instwebview2',
        CheckedState(chkInstWebView2.Checked));
      WriteString(ENG_INI_SECTION_INSTALLATION, 'updateoffice',
        CheckedState(chkUpdateOffice.Checked));
      WriteString(ENG_INI_SECTION_CONTROL, 'verify',
        CheckedState(chkVerify.Checked));
      WriteString(ENG_INI_SECTION_CONTROL, 'autoreboot',
        CheckedState(chkAutoReboot.Checked));
      WriteString(ENG_INI_SECTION_CONTROL, 'shutdown',
        CheckedState(chkShutdown.Checked));
      WriteString(ENG_INI_SECTION_CONTROL, 'auditonly',
        CheckedState(chkAuditOnly.Checked));
      WriteString(ENG_INI_SECTION_MESSAGING, 'showlog',
        CheckedState(chkShowLog.Checked));
      { Per-MSI-package keys (au3:255-257): one key per listed package,
        keyed by the raw package file name. }
      for I := 0 to High(FMsiChecks) do
        WriteString(ENG_INI_SECTION_MSI, FMsiNames.Strings[I],
          CheckedState(FMsiChecks[I].Checked));
      UpdateFile;
    finally
      Free;
    end;
end;

procedure TMainForm.BuildArgvFromToggles(out AToggles: TArgvToggles);
begin
  FillChar(AToggles, SizeOf(AToggles), 0);
  { GUI checkbox switches - only an enabled AND checked box can emit
    (gate-again defense; a disabled box never carries user intent). }
  AToggles.UpgradeBuilds := chkUpgradeBuilds.Enabled and chkUpgradeBuilds.Checked;
  AToggles.Updatercerts := chkRcerts.Enabled and chkRcerts.Checked;
  AToggles.InstDotNet35 := chkDotNet35.Checked;
  AToggles.InstDotNet4 := chkDotNet4.Enabled and chkDotNet4.Checked;
  AToggles.InstWmf := chkWmf.Enabled and chkWmf.Checked;
  AToggles.UpdateDotNet5 := chkDotNet5.Checked;
  AToggles.UpdateCpp := chkUpdateCpp.Enabled and chkUpdateCpp.Checked;
  AToggles.InstEdge := chkInstEdge.Enabled and chkInstEdge.Checked;
  AToggles.InstWebView2 := chkInstWebView2.Enabled and chkInstWebView2.Checked;
  AToggles.UpdateOffice := chkUpdateOffice.Enabled and chkUpdateOffice.Checked;
  AToggles.Verify := chkVerify.Enabled and chkVerify.Checked;
  AToggles.AuditOnly := chkAuditOnly.Checked;
  { The incumbent's /autoreboot emit rule (au3:1264-1266): the box must
    not carry the DISABLED state AND be checked. }
  AToggles.AutoReboot := chkAutoReboot.Enabled and chkAutoReboot.Checked;
  AToggles.Shutdown := chkShutdown.Checked;
  AToggles.ShowLog := chkShowLog.Checked;
  { INI-driven switches - the client INI only (au3:1240-1257, 1276-1281). }
  AToggles.SkipIeInst := SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
    'skipieinst', ENG_INI_DISABLED), ENG_INI_ENABLED);
  AToggles.SkipDefs := SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
    'skipdefs', ENG_INI_DISABLED), ENG_INI_ENABLED);
  AToggles.SkipDynamic := SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
    'skipdynamic', ENG_INI_DISABLED), ENG_INI_ENABLED);
  AToggles.AllUpdates := SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
    'all', ENG_INI_DISABLED), ENG_INI_ENABLED);
  AToggles.ExcludeStatics := SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
    'excludestatics', ENG_INI_DISABLED), ENG_INI_ENABLED);
  AToggles.SecOnly := SameText(DefIniState(ENG_INI_SECTION_INSTALLATION,
    'seconly', ENG_INI_DISABLED), ENG_INI_ENABLED);
  AToggles.ShowDismProgress := SameText(DefIniState(
    ENG_INI_SECTION_MESSAGING, 'showdismprogress', ENG_INI_DISABLED),
    ENG_INI_ENABLED);
  AToggles.MonitorOn := SameText(DefIniState(ENG_INI_SECTION_MISCELLANEOUS,
    'monitoron', ENG_INI_DISABLED), ENG_INI_ENABLED);
end;

procedure TMainForm.btnExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.btnCancelClick(Sender: TObject);
begin
  { Bilingual confirm, then kill the child on the spine's next pump tick. }
  if not FRunning then
    Exit;
  if Application.MessageBox(
      PChar(StringsGet(siCancelConfirm)),
      PChar(StringsGet(siWarnTitle)),
      MB_TASKMODAL or MB_ICONEXCLAMATION or MB_YESNO) = IDYES then
    FSpine.Cancel;
end;

procedure TMainForm.btnOpenReportClick(Sender: TObject);
begin
  { ShellExecute on the engine-produced report file (audit view). }
  if FAuditReportPath = '' then
    Exit;
  if ShellExecute(0, 'open', PChar(FAuditReportPath), nil, nil,
      SW_SHOWNORMAL) <= 32 then
    ShowBox(StringsGet(siOpenReportFailed), siErrorTitle, False);
end;

procedure TMainForm.SpineWatch;
var
  Raw: string;
begin
  { Live counts over the five wou_*.txt outcome files - refreshed on
    every pump tick; the last snapshot doubles as the summary basis for
    abrupt finish-mode deaths (Pitfall C: persist the basis BEFORE any
    reboot lands - the counts already sit in memory and the summary is
    rendered immediately at completion). }
  FLastCounts := SpineReadOutcomeCounts(EngCallerTempDir);
  Raw := Format(StringsGet(siCountsLine),
    [FLastCounts.Installed, FLastCounts.Failed, FLastCounts.Corrupt,
     FLastCounts.CleanSkipped, FLastCounts.VerificationSkipped]);
  if Raw <> FLastCountsRaw then
  begin
    FLastCountsRaw := Raw;
    lblStatus.Caption := Raw;
  end;
end;

procedure TMainForm.RenderOutcomeState(Res: TSpineResult);
var
  Kind: TSpineOutcomeKind;
begin
  Kind := SpineOutcomeKind(FSwitches, Res.Observed, Res.ExitCode,
    Res.Canceled);
  case Kind of
    soCompleted:
      memoProgress.Lines.Add(StringsGet(siOutcomeCompleted));
    soError:
      memoProgress.Lines.Add(StringsGet(siOutcomeError));
    soRebootRequired:
      memoProgress.Lines.Add(StringsGet(siOutcomeRebootRequired));
    soRecall:
      memoProgress.Lines.Add(StringsGet(siOutcomeRecall));
    soAbruptFinishSuccess:
      memoProgress.Lines.Add(StringsGet(siOutcomeAbruptFinish));
    soCanceled:
      memoProgress.Lines.Add(StringsGet(siOutcomeCanceled));
    soNoVerdict:
      memoProgress.Lines.Add(StringsGet(siOutcomeNoVerdict));
  end;
end;

procedure TMainForm.RenderAuditView;
var
  Sl: TStringList;
  Counts: TSpineAuditCounts;
  Candidates: TStringList;
  I: Integer;
begin
  if (Pos('/auditonly', FSwitches) = 0) then
    Exit;
  { Report candidates: the engine's own primary log location
    (..\..\log\MissingUpdates.txt relative to the cmd dir), the engine's
    %SystemRoot% fallback, and the caller %TEMP% spelling the plan names.
    First existing file wins. }
  Candidates := TStringList.Create;
  try
    Candidates.Add(ExpandFileName(FCmdDir + '\..\..\log\MissingUpdates.txt'));
    Candidates.Add(IncludeTrailingPathDelimiter(EngEngineTempDir)
      + '..\wsusofflineupdate_MissingUpdates.txt');
    Candidates.Add(IncludeTrailingPathDelimiter(EngCallerTempDir)
      + 'MissingUpdates.txt');
    FAuditReportPath := '';
    for I := 0 to Candidates.Count - 1 do
      if FileExists(Candidates.Strings[I]) then
      begin
        FAuditReportPath := Candidates.Strings[I];
        Break;
      end;
  finally
    Candidates.Free;
  end;
  if FAuditReportPath = '' then
    Exit;
  Sl := TStringList.Create;
  try
    Sl.LoadFromFile(FAuditReportPath);
    if SpineParseAuditReport(Sl, Counts) then
    begin
      memoProgress.Lines.Add('');
      memoProgress.Lines.Add(Format(StringsGet(siAuditPaneLabel),
        [FAuditReportPath]));
      memoProgress.Lines.Add(StringsGet(siCountsLine));
      memoProgress.Lines.Add(Sl.Text); { the full report, read-only pane }
      btnOpenReport.Visible := True;
    end;
  finally
    Sl.Free;
  end;
end;

procedure TMainForm.HandleRebootOutcome(Res: TSpineResult);
begin
  { INST-05: on 3010/3011 prompt (countdown = the 30-second shutdown
    timer + the Windows cancel toast), register the RunOnce value BEFORE
    issuing the reboot. }
  if SpineOutcomeKind(FSwitches, Res.Observed, Res.ExitCode,
      Res.Canceled) in [soRebootRequired, soRecall] then
  begin
    if Application.MessageBox(
        PChar(StringsGet(siRebootPrompt)),
        PChar(StringsGet(siWarnTitle)),
        MB_TASKMODAL or MB_DEFBUTTON1 or MB_ICONEXCLAMATION
          or MB_YESNO) = IDYES then
    begin
      if not ResRegisterResume(Application.ExeName) then
        memoProgress.Lines.Add(StringsGet(siResumeRegisterFailed))
      else
        ShellExecute(0, 'open', 'shutdown', '/r /t 30', nil, SW_SHOWNORMAL);
    end
    else
      ResDeleteResume; { decline = no dangling persistence (T-26-06) }
  end;
end;

procedure TMainForm.StartRun;
var
  Toggles: TArgvToggles;
  Switches: string;
  StatusServer: string;
  Res: TSpineResult;
  Selection: TStringList;
  I: Integer;
begin
  FRunning := True;
  btnStart.Enabled := False;
  btnExit.Enabled := False;
  btnCancel.Enabled := True;
  Selection := TStringList.Create;
  try
    { WUStatusServer pre-launch write (au3:1205-1208) - MyIniRead, i.e.
      the %TEMP% copy may carry it. }
    StatusServer := IniState(ENG_INI_SECTION_MISCELLANEOUS,
      ENG_REG_VAL_WUSTATUSSERVER, '');
    if StatusServer <> '' then
      DetectWriteWUStatusServer(StatusServer);

    { /autoreboot emit decision (au3:1264-1269): emitting it REPLACES the
      INI copy (the engine's recall path re-reads the client INI). }
    BuildArgvFromToggles(Toggles);
    if not Toggles.AutoReboot then
      IniCopyAll;

    Switches := EngBuildArgv(Toggles);
    FSwitches := Switches;

    { MSI selection write-or-delete at %SystemRoot%\Temp (au3:1282-1293;
      research Pitfall F - NEVER %TEMP%). }
    for I := 0 to High(FMsiChecks) do
      if FMsiChecks[I].Checked then
        Selection.Add(FMsiNames.Strings[I]);
    EngWriteMsiSelection(
      IncludeTrailingPathDelimiter(EngEngineTempDir)
      + ENG_MSI_SELECTION_NAME, Selection);

    { INST-05: with /autoreboot in the argv the ENGINE issues the reboot
      itself - the RunOnce resume must be registered BEFORE the spawn or
      the machine dies before the GUI could react. }
    if Toggles.AutoReboot then
      if not ResRegisterResume(Application.ExeName) then
        memoProgress.Lines.Add(StringsGet(siResumeRegisterFailed));

    FSpine.OnLine := @SpineLine;
    FSpine.OnIdle := @SpineIdle;
    FSpine.OnWatch := @SpineWatch;
    FSpine.Run(FCmdDir, Switches, 0, Res);

    { Summary basis FIRST (outcome files snapshot), the raw code line,
      then the state line - rendered before any reboot lands. }
    memoProgress.Lines.Add(Format(StringsGet(siSummaryExitCode),
      [Res.ExitCode]));
    RenderOutcomeState(Res);

    { /showlog parity: open the engine-produced log when requested. }
    if (Pos('/showlog', Switches) > 0) and Res.Observed then
      ShellExecute(0, 'open',
        PChar(IncludeTrailingPathDelimiter(EngEngineTempDir)
          + '..\' + ENG_ENGINE_LOG_NAME), nil, nil, SW_SHOWNORMAL);

    { /auditonly: switch the completion view to the report pane. }
    RenderAuditView;

    { 3010/3011 reboot prompt (INST-05). }
    HandleRebootOutcome(Res);
  finally
    Selection.Free;
    btnCancel.Enabled := False;
    btnExit.Enabled := True;
    btnStart.Enabled := True;
    FRunning := False;
  end;
end;

procedure TMainForm.btnStartClick(Sender: TObject);
begin
  if FRunning then
    Exit;
  StartRun;
end;

procedure TMainForm.SpineLine(const ALine: string);
begin
  memoProgress.Lines.Add(ALine);
  memoProgress.SelStart := memoProgress.GetTextLen;
  memoProgress.SelLength := 0;
  SendMessage(memoProgress.Handle, EM_SCROLLCARET, 0, 0);
end;

procedure TMainForm.SpineIdle;
begin
  Application.ProcessMessages;
end;

end.
