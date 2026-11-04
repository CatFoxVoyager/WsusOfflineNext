program installer;

{$mode objfpc}{$H+}

{*** Entry point of the native installer GUI (tracer scope, plan 26-01).

    Startup order: LCL init, language select (argv 'enu'/'deu' override,
    else German primary-language autodetect - au3:157-167 parity), the
    startup OS gate port (au3:998-1005 - blocks XP/2003/Vista/2008/7/
    2008R2/8.0 with the bilingual error box and exit code 1), then the
    form. The gate is compiled out ONLY under -dWOU_VALIDATE_OLDOS (the
    Win7 validation build of plan 04 - never built by any shipped lane). }

uses
  Interfaces, { LCL widgetset }
  Forms,
  SysUtils,
  Windows,
  enginecontracts,
  strings_de_en,
  mainform;

{ No {$R *.res} yet: lazbuild emits <project>.res only once the project has
  resource content (XPManifest / VersionInfo / icon), which plan 03 wires
  into the .lpi - restore the directive together with those options. The
  form streams from the unit-level {$R *.lfm}. }

begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;

  { Language select - the launcher forwards argv verbatim, so the
    incumbent 'enu'/'deu' argument contract persists. }
  if SameText(ParamStr(1), 'enu') then
    StringsSetLanguage(False)
  else if SameText(ParamStr(1), 'deu') then
    StringsSetLanguage(True)
  else
    StringsSetLanguage(StringsPrimaryLangIsGerman);

  {$IFNDEF WOU_VALIDATE_OLDOS}
  if not EngOsVersionSupported then
  begin
    { LCL converts the UTF-8 strings for the modal box. }
    Application.MessageBox(
      PChar(Format(StringsGet(siOsGateError), [EngOsVersionDisplay])),
      PChar(StringsGet(siOsGateTitle)),
      MB_TASKMODAL or MB_ICONERROR or MB_OK);
    Halt(1);
  end;
  {$ENDIF}

  Application.CreateForm(TMainForm, InstallerForm);
  Application.Run;
end.
