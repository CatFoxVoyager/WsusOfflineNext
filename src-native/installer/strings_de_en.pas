{*** Bilingual DE/EN string table for the native installer (tracer skeleton).

    Record/array table per 26-RESEARCH.md Pattern 6 option A: zero runtime
    files, incumbent inline-model behavior, trivially auditable parity.
    DE strings are transcribed from client/UpdateInstaller.au3 (Windows-1252)
    via a one-shot iconv read - umlauts intact. UTF-8 source, no mojibake.
    Plan 02 expands this table; every new product string belongs here. }

unit strings_de_en;

{$mode objfpc}{$H+}

interface

type
  TStringId = (
    siIntro,            { form intro label (au3:620/622) }
    siToggleCpp,        { C++ runtime toggle (au3:782/784) }
    siToggleVerify,     { verify packages toggle (au3:866/868) }
    siToggleAudit,      { audit only toggle (au3:932/934) }
    siBtnStart,         { start button (au3:985, both languages) }
    siBtnExit,          { exit button (au3:989/992: Ende/Exit) }
    siOsGateTitle,      { OS gate box title (au3:1000/1002) - the incumbent
                          carries the German title byte-parity in BOTH
                          language branches there; copied as-is }
    siOsGateError,      { OS gate message (au3:1000/1002), %s = OS version }
    siWshTitle,         { WSH box title (au3:1008/1012: Fehler/Error) }
    siWshError,         { WSH message seed (au3:1008-1012) }
    siSummaryExitCode   { completion summary line, %d = observed engine
                          exit code (tracer skeleton addition for the
                          progress-pane contract) }
  );

{ Select the active language: True = German (incumbent $gergui), False =
  English. Startup calls this once before any string is rendered. }
procedure StringsSetLanguage(AGerman: Boolean);

{ Localized string for an id. }
function StringsGet(Id: TStringId): string;

{ German primary-language autodetect (au3:157-167 parity): the user's
  default UI language has primary language id $07. }
function StringsPrimaryLangIsGerman: Boolean;

implementation

{ The kernel32 import below is a self-contained external declaration - no
  Windows-unit import needed. }

function GetUserDefaultUILanguage(): Word; stdcall;
  external 'kernel32' name 'GetUserDefaultUILanguage';

type
  TBilingual = record
    EN: string;
    DE: string;
  end;

const
  { Line breaks reproduce the incumbent @LF positions (au3:620-622,
    1008-1012). }
  STRINGS: array[TStringId] of TBilingual = (
    (EN: 'Select desired options and click ''Start'''#10'to install missing Microsoft updates on your computer.';
     DE: 'Wählen Sie die gewünschten Optionen und klicken Sie auf ''Start,'#10'um die fehlenden Microsoft-Updates auf Ihrem System zu installieren.'),
    (EN: 'Update C++ Runtime Libraries';
     DE: 'C++-Laufzeitbibliotheken aktualisieren'),
    (EN: 'Verify installation packages';
     DE: 'Installationspakete verifizieren'),
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
    (EN: 'Engine run finished. Exit code: %d';
     DE: 'Engine-Lauf beendet. Exit-Code: %d')
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

function StringsPrimaryLangIsGerman: Boolean;
begin
  { PRIMARYLANGID(langid) = langid and $3FF; $07 = German. }
  Result := (GetUserDefaultUILanguage and $3FF) = $07;
end;

end.
