program installer;

{$mode objfpc}{$H+}

{*** Entry point of the native installer GUI.

    Startup order (incumbent au3:997-1017 parity): LCL init, language
    select (argv 'enu'/'deu' override, else German primary-language
    autodetect - au3:157-167), the startup OS gate port (au3:998-1005 -
    blocks XP/2003/Vista/2008/7/2008R2/8.0 with the bilingual error box
    and exit code 1), then the WSH gate (au3:1006-1017 - a disabled
    Windows Script Host kills the run the same way), then the form
    (FormCreate carries the scriptdir/path gates, the full toggle
    gating, and the informational dialogs). The OS gate is compiled out
    ONLY under -dWOU_VALIDATE_OLDOS (the Win7 validation build of plan
    04 - never built by any shipped lane).

    Healthy-first-launch marker (Phase 28 contract, plan 29-02
    plumbing): the updater relaunches the app with
    --healthy-marker <path> after the swap. The argument is parsed
    here - AFTER the OS and WSH gates, mirroring the .NET installer
    host which parses it after its elevation gate - and handed to the
    main form, whose FIRST SHOW writes the marker file (never the
    startup code: a healthy launch is proven by a visible window). A
    normal launch ignores the whole mechanism. }

uses
  Interfaces, { LCL widgetset }
  Forms,
  SysUtils,
  Windows,
  enginecontracts,
  strings_de_en,
  detection,
  resume,
  mainform;

{ The .lpi carries the declarative resource set (XPManifest requireAdmin +
  PerMonitorV2 + LongPathAware, VERSIONINFO global block, icon from the
  side-by-side installer.ico), so lazbuild emits <project>.res and this
  directive links it. The form streams from the unit-level {$R *.lfm}. }
{$R *.res}

var
  HealthyMarkerPath: string;
  I: Integer;
  ResumePending, EngineRecall: Boolean;
begin
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;

  { Language select - the launcher forwards argv verbatim, so the
    incumbent 'enu'/'deu' argument contract persists. }
  StringsSetLanguage(StringsSelectLanguage(ParamStr(1),
    StringsPrimaryLangIsGerman));

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

  if not DetectWSHAvailable then
  begin
    Application.MessageBox(
      PChar(StringsGet(siWshError)),
      PChar(StringsGet(siWshTitle)),
      MB_TASKMODAL or MB_ICONERROR or MB_OK);
    Halt(1);
  end;

  { Parse the updater's --healthy-marker argument (Ordinal match, next
    argument is the path). Null-shaped on every normal launch. }
  HealthyMarkerPath := '';
  I := 1;
  while I < ParamCount do
  begin
    if ParamStr(I) = '--healthy-marker' then
    begin
      HealthyMarkerPath := ParamStr(I + 1);
      Break;
    end;
    Inc(I);
  end;

  { INST-05 /resume startup path: the RunOnce relaunch lands here after
    a reboot. The GUI deletes its OWN value defensively on BOTH paths
    (successful resume AND nothing-to-resume - threat T-26-06); the
    engine's wourecall.1-9 guard stays the ONLY loop protection, the GUI
    adds no counter. }
  if ResWantsResume then
  begin
    { Decide BEFORE deleting: ResDeleteResume also removes the pending
      marker. A run is pending when the engine staged updates OR the GUI
      registered this very RunOnce (marker): reboots that happen before the
      update list exists (IE11, SHA-2 pair, agent refresh, .NET, WMF) leave
      no staging and must still continue - stopping there ended the run. }
    ResumePending := ResResumePending;
    EngineRecall := ResEngineRecallPrepared;
    ResDeleteResume;
    if EngineRecall then
    begin
      { Legacy /autoreboot: the engine's own recall (Run key, WOUTempAdmin
        autologon) continues the run. This RunOnce entry runs BEFORE it - any
        dialog, UAC prompt or second engine here would block or duplicate the
        recall. Leave silently. }
      Halt(0);
    end;
    if ResumePending then
    begin
      { FormCreate restores the prior toggle set from the INI (the same
        MyIniRead layering the interrupted run wrote); StartRun re-emits
        the frozen argv and continues the engine's stage. }
      Application.CreateForm(TMainForm, InstallerForm);
      InstallerForm.StartRun;
    end
    else
    begin
      Application.MessageBox(
        PChar(StringsGet(siNothingToResume)),
        PChar(StringsGet(siInfoTitle)),
        MB_TASKMODAL or MB_ICONINFORMATION or MB_OK);
      Halt(0);
    end;
  end
  else
    Application.CreateForm(TMainForm, InstallerForm);
  { Hand the parsed marker path to the form BEFORE the run loop: the
    write happens on the form's FIRST SHOW, never during startup. }
  InstallerForm.SetHealthyMarkerPath(HealthyMarkerPath);
  Application.Run;
end.
