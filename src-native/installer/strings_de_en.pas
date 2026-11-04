{*** Bilingual DE/EN string table for the native installer.

    Record/array table per 26-RESEARCH.md Pattern 6 option A: zero runtime
    files, incumbent inline-model behavior, trivially auditable parity.
    DE strings are transcribed from the incumbent installer au3
    (Windows-1252) via a one-shot iconv read - umlauts intact. UTF-8
    source, no mojibake.

    This table is the COMPLETE incumbent inventory (plan 02 task 1): every
    user-visible au3 string - intro, groups, tabs, all toggle captions,
    buttons, every startup/informational/warning MsgBox - plus the strings
    the native GUI itself adds (progress summary; later plans append
    theirs here). NO product string may live inline in mainform; the
    python gate ci/tests/test-native-installer-strings.py enforces the
    bilingual parity and pins the umlaut integrity strings byte-exact.
    Plan 03 deletes the au3 ONLY on this gate being green. }

unit strings_de_en;

{$mode objfpc}{$H+}

interface

type
  TStringId = (
    siIntro,            { form intro label (au3:620/622) }
    siMediumGroup,      { Medium info group box (au3:631/633) }
    siBuildLabel,       { build line inside the group (au3:637), %s = date }
    siTabUpdating,      { Updating tab caption (au3:647/649) }
    siTabSoftware,      { Software tab caption (au3:948, same in both) }
    siGrpInstallation,  { Installation group box (au3:655, same in both) }
    siGrpControl,       { Control group box (au3:857/859) }
    siGrpMsi,           { MSI packages group box (au3:961/963) }
    siMsiSelectAll,     { select-all checkbox on the Software tab
                          (au3:954/956) }
    siToggleUpgradeBuilds, { enablement toggle (au3:661/663) }
    siToggleRcerts,     { root certificates toggle (au3:696/698) }
    siToggleDotNet35,   { .NET 3.5 toggle (au3:714/716) }
    siToggleDotNet4,    { .NET 4 toggle (au3:728/730), %s = target display }
    siToggleWmf,        { WMF toggle (au3:749/751), %s = target version }
    siToggleDotNet5,    { .NET 5+ toggle (au3:769/771) }
    siToggleCpp,        { C++ runtime toggle (au3:782/784) }
    siToggleEdge,       { Edge toggle (au3:800/802) }
    siToggleWebView2,   { WebView2 toggle (au3:817/819) }
    siToggleOffice,     { Office toggle (au3:835/837) }
    siOfficeDetected,   { office info label when detected (au3:148) }
    siOfficeNone,       { office info label when not (au3:151/153) }
    siToggleVerify,     { verify packages toggle (au3:866/868) }
    siToggleAutoReboot, { automatic reboot toggle (au3:883/885) }
    siToggleShutdown,   { shut down toggle (au3:901/903) }
    siToggleShowLog,    { show log toggle (au3:914/916) }
    siToggleAudit,      { audit only toggle (au3:932/934) }
    siBtnStart,         { start button (au3:985, both languages) }
    siBtnExit,          { exit button (au3:989/992: Ende/Exit) }
    siOsGateTitle,      { OS gate box title (au3:1000/1002) - the incumbent
                          carries the German title byte-parity in BOTH
                          language branches there; copied as-is }
    siOsGateError,      { OS gate message (au3:1000/1002), %s = OS version }
    siWshTitle,         { WSH box title (au3:1008/1012: Fehler/Error) }
    siWshError,         { WSH message (au3:1008-1014) }
    siErrorTitle,       { generic error box title (au3:1020-1054: Fehler/
                          Error) }
    siInfoTitle,        { information box title (au3:681-690, 1064-1087:
                          Information in both) }
    siWarnTitle,        { warning box title (au3:1091/1093, 1125-1152:
                          Warnung/Warning) }
    siScriptDirAssignError, { drive-letter assignment failure (au3:1020-1024),
                          %s = script dir }
    siPathScriptDirError,   { script path validation failure (au3:1030-1034),
                          %d = max length, %s = invalid chars }
    siPathTempError,    { %TEMP% path validation failure (au3:1040-1044),
                          %d = max length, %s = invalid chars }
    siTempTrailingError,{ %TEMP% trailing \ or : failure (au3:1050-1054) }
    siIe11Info,         { IE11-on-2012 info dialog (au3:1064-1068) }
    siDotNet462Info,    { .NET 4.6.2 info dialog (au3:1075-1079) }
    siEnablementEnforcedInfo, { enforced enablement info (au3:1085/1087) }
    siEnablementEnforcedWarning, { enforced-but-unavailable warning
                          (au3:1091/1093) }
    siIneligibleBuildInfo, { Win11 26H1 ineligible-build info dialog
                          (au3:681-690), %s = OS build }
    siUacDisableWarning,{ legacy autoreboot UAC-disable warning (au3:1125-1133) }
    siNetworkShareWarning, { legacy autoreboot network-share warning
                          (au3:1140-1152), %s = launcher name }
    siSpawnError,       { engine spawn failure (au3:1313-1319 shape),
                          %d = error code, %s = command, %s = directory }
    siSummaryExitCode,  { completion summary line, %d = observed engine
                          exit code (native GUI addition) }
    siBtnCancel,        { cancel button (native GUI addition, task 3) }
    siCancelConfirm,    { cancel confirmation body }
    siOutcomeCompleted, { completion state: exit 0 }
    siOutcomeError,     { completion state: exit 1 / unexpected }
    siOutcomeRebootRequired, { completion state: exit 3010 }
    siOutcomeRecall,    { completion state: exit 3011 }
    siOutcomeAbruptFinish, { completion state: abrupt death under a
                          finish mode (Pitfall C success path) }
    siOutcomeCanceled,  { completion state: user cancel }
    siOutcomeNoVerdict, { completion state: no engine verdict }
    siCountsLine,       { live outcome counts, 5 x %d (task 3 watcher) }
    siRebootPrompt,     { reboot prompt on 3010/3011 (INST-05) }
    siBtnOpenReport,    { open-report button on the audit view }
    siAuditPaneLabel,   { audit view header, %s = report path }
    siNothingToResume,  { /resume with absent staging (INST-05) }
    siOpenReportFailed, { report open failure feedback }
    siResumeRegisterFailed { RunOnce write failure feedback }
  );

{ Select the active language: True = German (incumbent $gergui), False =
  English. Startup calls this once before any string is rendered. }
procedure StringsSetLanguage(AGerman: Boolean);

{ Localized string for an id. }
function StringsGet(Id: TStringId): string;

{ German primary-language autodetect (au3:157-167 parity): the user's
  default UI language has primary language id $07. }
function StringsPrimaryLangIsGerman: Boolean;

{ Pure language selection (au3:157-167 verbatim): the 'enu'/'deu' argv
  token wins, otherwise the UI primary language decides. Returns True =
  German. Unit-testable. }
function StringsSelectLanguage(const ALangArg: string;
  AUiPrimaryGerman: Boolean): Boolean;

implementation

uses
  SysUtils;

function GetUserDefaultUILanguage(): Word; stdcall;
  external 'kernel32' name 'GetUserDefaultUILanguage';

type
  TBilingual = record
    EN: string;
    DE: string;
  end;

const
  { Line breaks reproduce the incumbent @LF positions; %% escapes keep
    the literal %TEMP%/%s spelling out of Format's specifier scan. }
  STRINGS: array[TStringId] of TBilingual = (
    (EN: 'Select desired options and click ''Start'''#10'to install missing Microsoft updates on your computer.';
     DE: 'Wählen Sie die gewünschten Optionen und klicken Sie auf ''Start,'#10'um die fehlenden Microsoft-Updates auf Ihrem System zu installieren.'),
    (EN: 'Medium info';
     DE: 'Medium-Info'),
    (EN: 'Build: %s';
     DE: 'Build: %s'),
    (EN: 'Updating';
     DE: 'Aktualisierung'),
    (EN: 'Software';
     DE: 'Software'),
    (EN: 'Installation';
     DE: 'Installation'),
    (EN: 'Control';
     DE: 'Steuerung'),
    (EN: 'MSI packages';
     DE: 'MSI-Pakete'),
    (EN: 'Select all';
     DE: 'Alle auswählen'),
    (EN: 'Feature Update via Enablement Package';
     DE: 'Feature Update Über Enablement Package'),
    (EN: 'Update Root Certificates';
     DE: 'Stammzertifikate aktualisieren'),
    (EN: 'Install .NET Framework 3.5';
     DE: '.NET Framework 3.5 installieren'),
    (EN: 'Install .NET Framework %s';
     DE: '.NET Framework %s installieren'),
    (EN: 'Install Management Framework %s';
     DE: 'Management Framework %s installieren'),
    (EN: 'Update .NET Framework 5 (and newer)';
     DE: '.NET Framework 5 (und neuer) aktualisieren'),
    (EN: 'Update C++ Runtime Libraries';
     DE: 'C++-Laufzeitbibliotheken aktualisieren'),
    (EN: 'Install Microsoft Edge';
     DE: 'Microsoft Edge installieren'),
    (EN: 'Install Edge WebView2 Runtime';
     DE: 'Edge WebView2-Laufzeit installieren'),
    (EN: 'Update Microsoft Office';
     DE: 'Microsoft Office aktualisieren'),
    (EN: 'Microsoft Office 2016+';
     DE: 'Microsoft Office 2016+'),
    (EN: 'No Office detected';
     DE: 'Kein Office erkannt'),
    (EN: 'Verify installation packages';
     DE: 'Installationspakete verifizieren'),
    (EN: 'Automatic reboot and recall';
     DE: 'Automatisch neu starten und fortsetzen'),
    (EN: 'Shut down on completion';
     DE: 'Herunterfahren nach Abschluss'),
    (EN: 'Show log file';
     DE: 'Protokolldatei anzeigen'),
    (EN: 'Audit only (missing updates report)';
     DE: 'Nur auditieren (Bericht fehlender Updates)'),
    (EN: 'Start';
     DE: 'Start'),
    (EN: 'Exit';
     DE: 'Ende'),
    (EN: 'Fehler';   { incumbent byte-parity: the au3 uses the German title
                       in its English branch here too (au3:1002) }
     DE: 'Fehler'),
    (EN: 'Unsupported Operating System: %s';
     DE: 'Nicht unterstütztes Betriebssystem: %s'),
    (EN: 'Error';
     DE: 'Fehler'),
    (EN: 'Windows Script Host is disabled on this machine. Please check registry values'#10'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Script Host\Settings\Enabled and'#10'HKEY_CURRENT_USER\Software\Microsoft\Windows Script Host\Settings\Enabled';
     DE: 'Der Windows Script Host ist deaktiviert. Bitte prüfen Sie die Registrierungswerte'#10'HKEY_LOCAL_MACHINE\Software\Microsoft\Windows Script Host\Settings\Enabled und'#10'HKEY_CURRENT_USER\Software\Microsoft\Windows Script Host\Settings\Enabled'),
    (EN: 'Error';
     DE: 'Fehler'),
    (EN: 'Information';
     DE: 'Information'),
    (EN: 'Warning';
     DE: 'Warnung'),
    (EN: 'Unable to assign a drive letter'#10'to the script path %s';
     DE: 'Dem Skript-Pfad %s'#10'konnte kein Laufwerksbuchstabe zugewiesen werden.'),
    (EN: 'The script path must not be more than %d characters long and'#10'must not contain any of the following characters: %s';
     DE: 'Der Skript-Pfad darf nicht mehr als %d Zeichen lang sein und'#10'darf keines der folgenden Zeichen enthalten: %s'),
    (EN: 'The %%TEMP%% path must not be more than %d characters long and'#10'must not contain any of the following characters: %s';
     DE: 'Der %%TEMP%%-Pfad darf nicht mehr als %d Zeichen lang sein und'#10'darf keines der folgenden Zeichen enthalten: %s'),
    (EN: 'The %%TEMP%% path contains a trailing backslash (''\'')'#10'or a trailing colon ('':'').';
     DE: 'Der %%TEMP%%-Pfad enthält einen abschließenden Backslash (''\'')'#10'oder einen abschließenden Doppelpunkt ('':'').'),
    (EN: 'On this system, the most recent version of Internet Explorer (IE11)'#10'will be automatically installed, when you start the updating process.';
     DE: 'Auf diesem System wird die neueste Version des Internet Explorers (IE11)'#10'automatisch installiert, wenn Sie die Aktualisierung starten.'),
    (EN: 'On this system, version 4.6.2 of .NET Framework'#10'will be automatically installed, when you start the updating process.';
     DE: 'Auf diesem System wird Version 4.6.2 des .NET Framework'#10'automatisch installiert, wenn Sie die Aktualisierung starten.'),
    (EN: 'On this system, the Feature Update via Enablement Package will be automatically installed, when you start the updating process.';
     DE: 'Auf diesem System wird das Feature Update Über Enablement Package automatisch installiert, wenn Sie die Aktualisierung starten.'),
    (EN: 'This system is running a version of Windows 10, which cannot be automatically upgraded to a supported one.'#10'The dynamic update search might report missing updates for Windows.';
     DE: 'Auf diesem System wird eine nicht unterstützte Version von Windows 10 ausgeführt, welche nicht automatisch aktualisiert werden kann.'#10'Die Update-Ermittlung kann fehlende Updates für Windows melden.'),
    (EN: 'This system is running Windows 11 build %s (26H1).'#10'This version is on a separate servicing branch and is ineligible'#10'for in-place feature upgrade via enablement package.';
     DE: 'Auf diesem System wird Windows 11 Build %s (26H1) ausgeführt.'#10'Diese Version befindet sich auf einem separaten Servicing-Zweig und ist'#10'für ein Upgrade über Enablement Package nicht berechtigt.'),
    (EN: 'The option ''Automatic reboot and recall'' temporarily'#10'disables the User Account Control (UAC), if required.'#10'Do you wish to proceed?';
     DE: 'Die Option ''Automatisch neu starten und fortsetzen'' deaktiviert'#10'temporär die Benutzerkontensteuerung (UAC), falls erforderlich.'#10'Möchten Sie fortsetzen?'),
    (EN: '%s was started from a network share.'#10'The option ''Automatic reboot and recall'''#10'does only work without user interaction,'#10'if this share permits anonymous access.'#10'Do you wish to proceed?';
     DE: '%s wurde von einer Netzwerkfreigabe gestartet.'#10'Die Option ''Automatisch neu starten und fortsetzen'''#10'funktioniert nur dann ohne Benutzereingriff,'#10'wenn diese Freigabe anonymen Zugriff erlaubt.'#10'Möchten Sie fortsetzen?'),
    (EN: 'Error #%d when calling'#10'%s'#10'in %s.';
     DE: 'Fehler #%d beim Aufruf von'#10'%s'#10'in %s.'),
    (EN: 'Engine run finished. Exit code: %d';
     DE: 'Engine-Lauf beendet. Exit-Code: %d'),
    (EN: 'Cancel';
     DE: 'Abbrechen'),
    (EN: 'Cancel the running update installation?';
     DE: 'Die laufende Update-Installation abbrechen?'),
    (EN: 'Updates installed.';
     DE: 'Updates installiert.'),
    (EN: 'The update run ended with errors.';
     DE: 'Der Update-Durchlauf wurde mit Fehlern beendet.'),
    (EN: 'A restart is required to complete the updates.';
     DE: 'Ein Neustart ist erforderlich, um die Updates abzuschließen.'),
    (EN: 'Updates remain staged for a follow-up run.';
     DE: 'Updates wurden für einen Folgedurchlauf vorgemerkt.'),
    (EN: 'The system is rebooting or shutting down as requested.';
     DE: 'Das System wird wie angefordert neu gestartet oder heruntergefahren.'),
    (EN: 'The update run was canceled.';
     DE: 'Der Update-Durchlauf wurde abgebrochen.'),
    (EN: 'The engine could not be started.';
     DE: 'Die Engine konnte nicht gestartet werden.'),
    (EN: 'Installed: %d  Failed: %d  Corrupt: %d  Skipped: %d  Unverified: %d';
     DE: 'Installiert: %d  Fehlgeschlagen: %d  Beschädigt: %d  Übersprungen: %d  Unverifiziert: %d'),
    (EN: 'A restart is required to complete the updates. Restart now?'#10'The system restarts after 30 seconds; Windows then shows a short cancel window.';
     DE: 'Ein Neustart ist erforderlich, um die Updates abzuschließen. Jetzt neu starten?'#10'Das System startet nach 30 Sekunden neu; Windows zeigt dabei ein kurzes Abbruchfenster.'),
    (EN: 'Open report';
     DE: 'Bericht öffnen'),
    (EN: 'Audit report (%s)';
     DE: 'Audit-Bericht (%s)'),
    (EN: 'Nothing to resume - no staged updates were found.';
     DE: 'Nichts fortzusetzen - es wurden keine gestaffelten Updates gefunden.'),
    (EN: 'The report file could not be opened.';
     DE: 'Die Berichtsdatei konnte nicht geöffnet werden.'),
    (EN: 'The resume registration could not be written.';
     DE: 'Die Wiederaufnahme-Registrierung konnte nicht geschrieben werden.')
  );

var
  GGerman: Boolean = False;

procedure StringsSetLanguage(AGerman: Boolean);
begin
  GGerman := AGerman;
end;

function StringsGet(Id: TStringId): string;
begin
  if GGerman then
    Result := STRINGS[Id].DE
  else
    Result := STRINGS[Id].EN;
end;

function StringsSelectLanguage(const ALangArg: string;
  AUiPrimaryGerman: Boolean): Boolean;
begin
  { au3:157-167 verbatim: the argv token wins, otherwise autodetect. }
  if SameText(ALangArg, 'enu') then
    Exit(False);
  if SameText(ALangArg, 'deu') then
    Exit(True);
  Result := AUiPrimaryGerman;
end;

function StringsPrimaryLangIsGerman: Boolean;
begin
  { PRIMARYLANGID(langid) = langid and $3FF; $07 = German. }
  Result := (GetUserDefaultUILanguage and $3FF) = $07;
end;

end.
