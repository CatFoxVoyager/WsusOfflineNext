{*** Main form of the native installer - tracer scope (plan 26-01).

    Caption from the exe's own VERSIONINFO (versionless fallback until plan
    03), the incumbent intro label, the tracer's three presence-gated
    toggles (Update C++ Runtime Libraries / Verify installation packages /
    Audit only) with MyIniRead parity (%TEMP% INI overrides the client INI),
    Start/Exit buttons with the incumbent Enter/Escape accelerators, and a
    read-only progress pane fed by the engine spine. On completion a summary
    line reports the observed engine exit code.

    argv emission goes ONLY through the enginecontracts switch table keyed
    by checkbox state - never raw INI text (threat T-26-01). }

unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Windows, Messages, IniFiles,
  Forms, Controls, Graphics, Dialogs, StdCtrls,
  enginecontracts, strings_de_en, enginespine;

type

  { TMainForm }

  TMainForm = class(TForm)
    btnStart: TButton;
    btnExit: TButton;
    chkUpdateCpp: TCheckBox;
    chkVerify: TCheckBox;
    chkAuditOnly: TCheckBox;
    lblIntro: TLabel;
    memoProgress: TMemo;
    procedure btnExitClick(Sender: TObject);
    procedure btnStartClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
  private
    FExeDir: string;
    FCmdDir: string;
    FCallerTempIni: string;
    FRunning: Boolean;
    FSpine: TEngineSpine;
    { MyIniRead parity (au3:220-229): the client INI provides the default,
      a %TEMP%\UpdateInstaller.ini copy overrides it when present. }
    function IniState(const ASection, AKey, ADefault: string): string;
    function CppPresent: Boolean;
    function MdPresent: Boolean;
    procedure ApplyToggleGating;
    procedure BuildArgvFromToggles(out ASwitches: string);
    { IniCopy parity for the tracer's three keys (au3:231-260): copy the
      client INI to %TEMP%\UpdateInstaller.ini, then IniWrite the three
      checkbox states. }
    procedure IniCopyThreeKeys;
    procedure SpineLine(const ALine: string);
    procedure SpineIdle;
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
begin
  FExeDir := ExtractFilePath(Application.ExeName);
  FCmdDir := FExeDir + 'cmd';
  FCallerTempIni := IncludeTrailingPathDelimiter(EngCallerTempDir)
    + ENG_TEMP_INI_NAME;
  FSpine := TEngineSpine.Create;
  FRunning := False;

  Caption := EngWindowCaption;
  lblIntro.Caption := StringsGet(siIntro);
  chkUpdateCpp.Caption := StringsGet(siToggleCpp);
  chkVerify.Caption := StringsGet(siToggleVerify);
  chkAuditOnly.Caption := StringsGet(siToggleAudit);
  btnStart.Caption := StringsGet(siBtnStart);
  btnExit.Caption := StringsGet(siBtnExit);
  memoProgress.Lines.Clear;

  ApplyToggleGating;
end;

procedure TMainForm.ApplyToggleGating;
begin
  { Update C++ Runtime Libraries - enabled iff \cpp\vcredist*.exe exists,
    default per INI (au3:779-790). }
  chkUpdateCpp.Enabled := CppPresent;
  chkUpdateCpp.Checked := chkUpdateCpp.Enabled
    and SameText(IniState(ENG_INI_SECTION_INSTALLATION, 'updatecpp',
      EngIniDefault(ENG_INI_SECTION_INSTALLATION, 'updatecpp')),
      ENG_INI_ENABLED);

  { Verify installation packages - enabled iff \md\ exists (au3:860-872). }
  chkVerify.Enabled := MdPresent;
  chkVerify.Checked := chkVerify.Enabled
    and SameText(IniState(ENG_INI_SECTION_CONTROL, 'verify',
      EngIniDefault(ENG_INI_SECTION_CONTROL, 'verify')),
      ENG_INI_ENABLED);

  { Audit only - always offerable (au3:928-934). }
  chkAuditOnly.Enabled := True;
  chkAuditOnly.Checked := SameText(IniState(ENG_INI_SECTION_CONTROL,
      'auditonly', EngIniDefault(ENG_INI_SECTION_CONTROL, 'auditonly')),
      ENG_INI_ENABLED);
end;

function TMainForm.IniState(const ASection, AKey, ADefault: string): string;
var
  ClientIni: TIniFile;
  TempIni: TIniFile;
begin
  Result := ADefault;
  if FileExists(FExeDir + ENG_TEMP_INI_NAME) then
  begin
    ClientIni := TIniFile.Create(FExeDir + ENG_TEMP_INI_NAME);
    try
      Result := ClientIni.ReadString(ASection, AKey, ADefault);
    finally
      ClientIni.Free;
    end;
  end;
  if FileExists(FCallerTempIni) then
  begin
    TempIni := TIniFile.Create(FCallerTempIni);
    try
      Result := TempIni.ReadString(ASection, AKey, Result);
    finally
      TempIni.Free;
    end;
  end;
end;

function TMainForm.CppPresent: Boolean;
var
  SearchRec: TSearchRec;
begin
  Result := FindFirst(FExeDir + 'cpp\vcredist*.exe', faAnyFile, SearchRec) = 0;
  if Result then
    SysUtils.FindClose(SearchRec);
end;

function TMainForm.MdPresent: Boolean;
begin
  Result := DirectoryExists(FExeDir + 'md');
end;

procedure TMainForm.BuildArgvFromToggles(out ASwitches: string);
  procedure AddSwitch(const AName: string);
  var
    Token: string;
  begin
    Token := EngSwitchToken(AName);
    if Token <> '' then
      ASwitches := ASwitches + ' ' + Token;
  end;
begin
  ASwitches := '';
  { Only enabled toggles can be checked - gate anyway: an argv token is
    emitted solely for a checked AND enabled box. }
  if chkUpdateCpp.Enabled and chkUpdateCpp.Checked then
    AddSwitch('updatecpp');
  if chkVerify.Enabled and chkVerify.Checked then
    AddSwitch('verify');
  if chkAuditOnly.Checked then
    AddSwitch('auditonly');
  ASwitches := Trim(ASwitches);
end;

procedure TMainForm.IniCopyThreeKeys;
begin
  if FileExists(FExeDir + ENG_TEMP_INI_NAME) then
  begin
    EngCopyFileRaw(FExeDir + ENG_TEMP_INI_NAME, FCallerTempIni);
    { au3 FileSetAttrib -R parity. }
    FileSetAttr(FCallerTempIni, FILE_ATTRIBUTE_NORMAL);
  end;
  with TIniFile.Create(FCallerTempIni) do
    try
      WriteString(ENG_INI_SECTION_INSTALLATION, 'updatecpp',
        CheckedState(chkUpdateCpp.Checked));
      WriteString(ENG_INI_SECTION_CONTROL, 'verify',
        CheckedState(chkVerify.Checked));
      WriteString(ENG_INI_SECTION_CONTROL, 'auditonly',
        CheckedState(chkAuditOnly.Checked));
      UpdateFile;
    finally
      Free;
    end;
end;

procedure TMainForm.btnStartClick(Sender: TObject);
var
  Switches: string;
  Res: TSpineResult;
begin
  if FRunning then
    Exit;
  FRunning := True;
  btnStart.Enabled := False;
  btnExit.Enabled := False;
  try
    IniCopyThreeKeys;
    BuildArgvFromToggles(Switches);
    FSpine.OnLine := @SpineLine;
    FSpine.OnIdle := @SpineIdle;
    FSpine.Run(FCmdDir, Switches, 0, Res);
    { Exit code -1 = no engine verdict observed (spawn failure). }
    memoProgress.Lines.Add(Format(StringsGet(siSummaryExitCode),
      [Res.ExitCode]));
  finally
    btnExit.Enabled := True;
    btnStart.Enabled := True;
    FRunning := False;
  end;
end;

procedure TMainForm.btnExitClick(Sender: TObject);
begin
  Close;
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
  { Keep the GUI alive while the pump loop runs (spine stays responsive;
    the Cancel wiring lands with plan 02's full option surface). }
  Application.ProcessMessages;
end;

end.
