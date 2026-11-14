{*** Pure consent layer for the OS-upgrade consent sheet (plan 36-02,
    GUI-01, DEC-36-02/04/05). Structural mold: upgradespredicates -
    no LCL, no form references, and every decision delegated to the
    frozen verdict layer, which is this unit's single decision source
    (threat T-36-04: the client can never be offered a target the
    engine's own layer would refuse; the units gate count-pins the
    verdict call at exactly one call site).

    The functions are PURE (all inputs as parameters) so the console
    testrunner links them without LCL forms (detection.pas charter;
    mainform stays out of the testrunner). The ONE exception is the
    self-contained UBR registry probe - a fail-closed read with no
    parameters to inject and no state to mutate.

    Contracts implemented here:

    - DEC-36-02 enumeration: the consent sheet names the FIRST row in
      upgrades.txt file order whose row is arch-matched, status=active
      and carries a hop (a non-empty EKB field) or fu_media=1, AND
      whose verdict through the frozen layer answers upgEKB or
      upgFullFU. The matrix lang slot 'glb' is passed internally
      (DEC-33-01 - the OS's real language would answer
      language-not-carried everywhere). When no row qualifies, the
      FIRST data-qualified candidate's blocked path travels for
      display; a roster without any candidate at all answers no-media.

    - DEC-36-04 caller inputs: the OS family derives from the build
      number ('win11' iff >= 22000, 'win10' for any other numeric
      build, empty on a non-numeric build - fail-closed to the verdict
      layer's unknown-current rule); the current revision comes from
      the UBR registry probe and fails closed to the empty string (the
      verdict layer then answers baseline-unknown, which BLOCKS
      consent - a wrong or stale revision can only block consent,
      never grant it, threat T-36-05).

    - Consent is never computed: the gate returns Checked=False for
      every input (the toggle's default and only resting state is
      unchecked; opt-in per run only - nothing here reads or writes
      INI state). }

unit upgradesconsent;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Registry, upgradespredicates, detection, strings_de_en;

const
  { The DEC-36-04 UBR probe: the DWORD revision value under the
    CurrentVersion key. The key is shared between the registry views,
    and the explicit 64-bit-view flag is ignored on a 32-bit OS - one
    open answers the OS revision for both process architectures. }
  UC_REG_KEY_CURRENT_VERSION = 'Software\Microsoft\Windows NT\CurrentVersion';
  UC_REG_VAL_UBR = 'UBR';

{ DEC-36-04: 'win11' iff the build number is >= 22000, 'win10' for any
  other numeric build, the empty string on a non-numeric build. }
function UcDeriveOsFamily(const ABuild: string): string;

{ DEC-36-04: the current revision from HKLM (...)\CurrentVersion\UBR
  (DWORD) rendered as its decimal string. ANY failure - key absent,
  value absent, open error, unexpected value type - returns the empty
  string. Never a guessed revision. }
function UcProbeCurrentRevision: string;

{ DEC-36-02 enumeration. Walks ARows in file order; a candidate row is
  arch-matched (Row.Arch = ACurrArch), status=active, and carries a
  hop (a non-empty EKB field) or fu_media=1. Each candidate resolves
  through the frozen verdict layer with the matrix lang slot 'glb'
  (DEC-33-01) and the DEC-36-04 family derivation. The first
  upgEKB/upgFullFU answer wins. ATargetBuild carries the named
  target's build digits (the sheet's Target line and the argv
  composition both consume them - a TUpgradePath record alone cannot
  carry them, and re-walking would duplicate the candidacy heuristic).
  When every candidate is blocked, the FIRST data-qualified candidate's
  path (its blocked reason travels for display) and build are
  returned; an empty candidate roster answers upgBlocked with reason
  'no-media' and an empty ATargetBuild. }
function UcEnumerateConsentTarget(ARows: TUpgradeRows;
  const ACurrBuild, ACurrRevision, ACurrArch: string;
  out ATargetBuild: string): TUpgradePath;

{ The consent gate (TGateState shape, detection.pas charter): the
  toggle is ENABLED only for an upgEKB/upgFullFU verdict and DISABLED
  on upgBlocked - and Checked is False for EVERY input. There is no
  input that yields Checked=True: consent is a user act, never a
  computed state. }
function UcConsentGate(AVerdict: TUpgradeVerdict): TGateState;

{ Total map over the frozen reason vocabulary - the verdict layer's
  ten machine tokens - onto the siUpgradeReason* display ids. Any value
  outside the vocabulary (a row's own blocked_reason passthrough is
  data, not vocabulary) maps to siUpgradeReasonGeneric. Never a raw
  token in the UI. }
function UcReasonToDisplayId(const AReason: string): TStringId;

{ One-decimal disk-GB rendering of the manifest's total_mib (DEC-33-07:
  consume the total, never re-sum): 10397 MiB renders '10.2' with '.'
  and '10,2' with ',' - the Copywriting Contract's decimal shapes.
  Half-up rounding in integer tenths - no floating point - and the
  separator is a parameter so neither language's locale can leak into
  the sheet. }
function UcDiskGbText(ATotalMib: Integer;
  const ADecimalSeparator: string): string;

implementation

function UcDeriveOsFamily(const ABuild: string): string;
var
  BuildNum: Integer;
begin
  BuildNum := StrToIntDef(ABuild, -1);
  if BuildNum >= 22000 then
    Result := 'win11'
  else if BuildNum >= 0 then
    Result := 'win10'
  else
    Result := '';
end;

function UcProbeCurrentRevision: string;
var
  R: TRegistry;
begin
  Result := '';
  R := TRegistry.Create(KEY_READ);
  try
    R.RootKey := HKEY_LOCAL_MACHINE;
    R.Access := R.Access or KEY_WOW64_64KEY;
    if R.OpenKeyReadOnly(UC_REG_KEY_CURRENT_VERSION) then
    begin
      try
        if R.ValueExists(UC_REG_VAL_UBR) then
          Result := IntToStr(R.ReadInteger(UC_REG_VAL_UBR));
      except
        { Unexpected value type or read error - fail closed. }
        Result := '';
      end;
      R.CloseKey;
    end;
  finally
    R.Free;
  end;
end;

function UcEnumerateConsentTarget(ARows: TUpgradeRows;
  const ACurrBuild, ACurrRevision, ACurrArch: string;
  out ATargetBuild: string): TUpgradePath;
var
  I: Integer;
  Row: TUpgradeRow;
  Family: string;
  Path, FirstPath: TUpgradePath;
  IsCandidate, HaveCandidate: Boolean;
begin
  { No candidate at all: blocked with no-media and no named build. }
  ATargetBuild := '';
  Result.Verdict := upgBlocked;
  Result.NeedsBaselineCU := False;
  Result.Reason := 'no-media';
  Family := UcDeriveOsFamily(ACurrBuild);
  HaveCandidate := False;
  for I := 0 to High(ARows) do
  begin
    Row := ARows[I];
    IsCandidate := (Row.Arch = ACurrArch)
                   and (Row.Status = 'active')
                   and ((Row.EkbSourceBuild <> '') or (Row.EkbKb <> '')
                        or (Row.EkbMinRevision <> '')
                        or (Row.EkbPrereqKb <> '')
                        or (Row.FuMedia = '1'));
    if not IsCandidate then
      Continue;
    Path := UpgResolvePath(ARows, ACurrBuild, ACurrRevision, ACurrArch,
      'glb', Family, Row.TargetBuild);
    if not HaveCandidate then
    begin
      { First data-qualified candidate: its blocked path travels for
        display when nothing qualifies. }
      HaveCandidate := True;
      FirstPath := Path;
      ATargetBuild := Row.TargetBuild;
    end;
    if Path.Verdict <> upgBlocked then
    begin
      { The winning candidate is the named target - its build digits
        must travel with the verdict (the fall-through default above
        carried only the FIRST candidate's build for the blocked
        sheet). }
      ATargetBuild := Row.TargetBuild;
      Result := Path;
      Exit;
    end;
  end;
  if HaveCandidate then
    Result := FirstPath;
end;

function UcConsentGate(AVerdict: TUpgradeVerdict): TGateState;
begin
  { The frozen table, verbatim: EKB/full-FU enable the toggle, blocked
    disables it - and no branch ever computes a checked state. }
  case AVerdict of
    upgEKB, upgFullFU:
    begin
      Result.Enabled := True;
      Result.Checked := False;
    end;
    upgBlocked:
    begin
      Result.Enabled := False;
      Result.Checked := False;
    end;
  end;
end;

function UcReasonToDisplayId(const AReason: string): TStringId;
begin
  if AReason = 'unknown-current' then
    Result := siUpgradeReasonUnknownCurrent
  else if AReason = 'bad-target' then
    Result := siUpgradeReasonBadTarget
  else if AReason = 'already-on-target' then
    Result := siUpgradeReasonAlreadyOnTarget
  else if AReason = 'downgrade' then
    Result := siUpgradeReasonDowngrade
  else if AReason = 'legacy-os' then
    Result := siUpgradeReasonLegacyOs
  else if AReason = 'ineligible' then
    Result := siUpgradeReasonIneligible
  else if AReason = 'no-media' then
    Result := siUpgradeReasonNoMedia
  else if AReason = 'arch-unsupported' then
    Result := siUpgradeReasonArchUnsupported
  else if AReason = 'baseline-unknown' then
    Result := siUpgradeReasonBaselineUnknown
  else if AReason = 'language-not-carried' then
    Result := siUpgradeReasonLangNotCarried
  else
    Result := siUpgradeReasonGeneric;
end;

function UcDiskGbText(ATotalMib: Integer;
  const ADecimalSeparator: string): string;
var
  Tenths: Integer;
begin
  Tenths := (ATotalMib * 10 + 512) div 1024;
  Result := IntToStr(Tenths div 10) + ADecimalSeparator
            + IntToStr(Tenths mod 10);
end;

end.
