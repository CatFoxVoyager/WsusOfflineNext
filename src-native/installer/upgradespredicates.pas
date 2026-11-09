{*** Upgrade-path deduction over the shipped upgrades-table data file
    (plan 31-03: the single decision layer the client app, /auditonly
    and both GUIs consume - PATH-01/PATH-02. The verdict rules and the
    golden matrix boundaries are frozen HERE, proven by the TAP battery,
    before any consumer phase wires them).

    Data file contract (generated from static/builds.ini by BOTH generator
    twins, sh/generate-build-sites.bash + cmd/GenerateBuildSites.vbs):

      client/UpdateTable/upgrades.txt
      # comment lines start with '#'
      target_build|arch|lang|os_family|servicing_branch|status|ekb_source_build|ekb_kb|ekb_min_revision|ekb_prereq_kb|fu_media|blocked_reason

    - exactly 12 pipe-delimited fields per row, whitespace-trimmed,
      empty = absent
    - malformed rows (wrong field count) are skipped, never fatal
    - the file ships with the client tree; updates need no recompile

    Verdict contract (DEC-04): exactly THREE verdicts - upgEKB (the
    enablement-package hop), upgFullFU (a staged full feature-update
    medium) and upgBlocked - with every blocked answer carrying a
    machine-comparable reason token (never prose, never a silent
    fallback substitution: a request with no matching row answers
    blocked + reason, never a substituted language/arch/target).
    NeedsBaselineCU is an annotation on the EKB verdict, not a fourth
    verdict. Every verdict input comes from the parsed rows or the
    caller's arguments - no build/KB/revision constant is hardcoded
    here (zéro KB codé en dur).

    The file-existence probe is injected via a callback so the console
    testrunner can drive golden tables without a real tree; production
    passes a FindFirst-based probe (the incumbent FileExists accepts
    wildcards). }

unit upgradespredicates;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { Relative to the script (client tree root) directory. }
  UP_FILE_REL = 'UpdateTable\upgrades.txt';

type
  TUpgradeRow = record
    TargetBuild: string;
    Arch: string;
    Lang: string;
    OsFamily: string;
    ServicingBranch: string;
    Status: string;
    EkbSourceBuild: string;
    EkbKb: string;
    EkbMinRevision: string;
    EkbPrereqKb: string;
    FuMedia: string;
    BlockedReason: string;
  end;
  TUpgradeRows = array of TUpgradeRow;

  { File-existence probe injection (wildcard-tolerant in production). }
  TFileProbe = function(const APath: string): Boolean;

  { Exactly three verdicts (DEC-04 / PATH-01 - no fourth value). }
  TUpgradeVerdict = (upgEKB, upgFullFU, upgBlocked);

  TUpgradePath = record
    Verdict: TUpgradeVerdict;
    { EKB annotation only: the current revision sits below the target's
      ekb_min_revision, so the prerequisite CU must install first. An
      annotation field, never a verdict (DEC-04). }
    NeedsBaselineCU: Boolean;
    { Machine-comparable reason token on upgBlocked; empty on the other
      two verdicts. }
    Reason: string;
  end;

{ Tolerant parser: '#' comments, blank lines and malformed rows are
  skipped; fields are whitespace-trimmed; missing/unreadable file =
  empty table, never fatal (fail-closed: threat T-31-08). The
  existence guard runs THROUGH the injected probe. }
function UpgParseUpgradesFile(const APath: string;
  AProbe: TFileProbe): TUpgradeRows;

{ The frozen verdict rules for one current -> target pair (plan 31-03
  Task 2; pinned case-by-case by the testrunner golden matrix):
  R0 unknown-current, R1 bad-target, R2 already-on-target, R3
  downgrade, R4 legacy-os, R5 no-media (no target row), R6 the target's
  ineligible row reason, R7 arch-unsupported (x86->win11, arm64->win10),
  R8 upgEKB with the NeedsBaselineCU annotation (baseline-unknown on an
  incomplete EKB triple), R9 upgFullFU, R10 language-not-carried,
  R11/R12 no-media. }
function UpgResolvePath(ARows: TUpgradeRows; const ACurrBuild,
  ACurrRevision, ACurrArch, ACurrLang, ACurrOsFamily,
  ATargetBuild: string): TUpgradePath;

implementation

function UpgParseUpgradesFile(const APath: string;
  AProbe: TFileProbe): TUpgradeRows;
var
  Sl: TStringList;
  I, FieldCount: Integer;
  Line, Field: string;
  Row: TUpgradeRow;
  InRow: Boolean;
begin
  Result := nil;
  if Assigned(AProbe) then
  begin
    if not AProbe(APath) then
      Exit;
  end
  else if not FileExists(APath) then
    Exit;
  Sl := TStringList.Create;
  try
    try
      Sl.LoadFromFile(APath);
    except
      { Unreadable data file = empty table, never fatal (fail-closed:
        the verdict layer then treats every path as unavailable, the
        incumbent's behavior with an empty registry). }
      Exit;
    end;
    for I := 0 to Sl.Count - 1 do
    begin
      Line := Trim(Sl.Strings[I]);
      if (Line = '') or (Line[1] = '#') then
        Continue;
      FieldCount := 0;
      InRow := True;
      while InRow do
      begin
        FieldCount := FieldCount + 1;
        if FieldCount > 12 then
        begin
          { More than 12 fields = malformed row - skip it. }
          InRow := False;
          FieldCount := 0;
          Break;
        end;
        if Pos('|', Line) > 0 then
        begin
          Field := Trim(Copy(Line, 1, Pos('|', Line) - 1));
          Line := Copy(Line, Pos('|', Line) + 1, MaxInt);
        end
        else
        begin
          Field := Trim(Line);
          InRow := False;
        end;
        case FieldCount of
          1: Row.TargetBuild := Field;
          2: Row.Arch := Field;
          3: Row.Lang := Field;
          4: Row.OsFamily := Field;
          5: Row.ServicingBranch := Field;
          6: Row.Status := Field;
          7: Row.EkbSourceBuild := Field;
          8: Row.EkbKb := Field;
          9: Row.EkbMinRevision := Field;
          10: Row.EkbPrereqKb := Field;
          11: Row.FuMedia := Field;
          12: Row.BlockedReason := Field;
        end;
      end;
      if FieldCount = 12 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Row;
      end;
    end;
  finally
    Sl.Free;
  end;
end;

function UpgResolvePath(ARows: TUpgradeRows; const ACurrBuild,
  ACurrRevision, ACurrArch, ACurrLang, ACurrOsFamily,
  ATargetBuild: string): TUpgradePath;
var
  I, T2, T: Integer;
  CurrNum, TargetNum, RevNum, SrcNum, MinRevNum: Integer;
  Ineligible: Boolean;
begin
  { The frozen rule table (plan 31-03 Task 2), evaluated in this exact
    order. All numeric comparisons go through StrToIntDef (0 default);
    reason tokens are the frozen vocabulary; non-blocked verdicts carry
    an empty Reason (threat T-31-09: every blocked answer is loud and
    machine-comparable, a false "upgraded" belief is impossible). }
  Result.Verdict := upgBlocked;
  Result.NeedsBaselineCU := False;
  Result.Reason := '';

  { R0 current build not a positive number. }
  CurrNum := StrToIntDef(ACurrBuild, 0);
  if CurrNum <= 0 then
  begin
    Result.Reason := 'unknown-current';
    Exit;
  end;
  { R1 target build not a positive number. }
  TargetNum := StrToIntDef(ATargetBuild, 0);
  if TargetNum <= 0 then
  begin
    Result.Reason := 'bad-target';
    Exit;
  end;
  { R2 numeric target = numeric current. }
  if TargetNum = CurrNum then
  begin
    Result.Reason := 'already-on-target';
    Exit;
  end;
  { R3 numeric target < numeric current. }
  if TargetNum < CurrNum then
  begin
    Result.Reason := 'downgrade';
    Exit;
  end;
  { R4 current OS family is neither win10 nor win11 - the upgrade
    machinery never leaks pre-Win10 (VAL-02 seed). }
  if (ACurrOsFamily <> 'win10') and (ACurrOsFamily <> 'win11') then
  begin
    Result.Reason := 'legacy-os';
    Exit;
  end;

  { R5 + R6 over the target's rows: first matching row decides the
    ineligible verdict (buildsupgrade.pas shape), R5 answers no-media
    only when NO row carries the target at all. }
  T2 := -1;
  Ineligible := False;
  for I := 0 to High(ARows) do
    if ARows[I].TargetBuild = ATargetBuild then
    begin
      if T2 < 0 then
        T2 := I;
      if ARows[I].Status = 'ineligible' then
      begin
        { R6 fires before the matrix gate (pinned by matrix case 19). }
        if ARows[I].BlockedReason <> '' then
          Result.Reason := ARows[I].BlockedReason
        else
          Result.Reason := 'ineligible';
        Ineligible := True;
        Break;
      end;
    end;
  if Ineligible then
    Exit;
  if T2 < 0 then
  begin
    Result.Reason := 'no-media';
    Exit;
  end;

  { R7 matrix gate on the first target row (any arch/lang): x86 never
    sees a win11 target, arm64 never a win10 one. }
  if ((ACurrArch = 'x86') and (ARows[T2].OsFamily = 'win11'))
     or ((ACurrArch = 'arm64') and (ARows[T2].OsFamily = 'win10')) then
  begin
    Result.Reason := 'arch-unsupported';
    Exit;
  end;

  { T = the caller's (target, arch, lang) row. }
  T := -1;
  for I := 0 to High(ARows) do
    if (ARows[I].TargetBuild = ATargetBuild)
       and (ARows[I].Arch = ACurrArch)
       and (ARows[I].Lang = ACurrLang) then
    begin
      T := I;
      Break;
    end;

  if T >= 0 then
  begin
    { R8 EKB: the row's EKB hop must carry the current build - by exact
      ekb_source_build, or through the servicing-window rule
      (source <= current < target) that lets the 19041-branch family
      keep answering EKB exactly like the incumbent lane
      (BuBuildUpgradeAvailable's branch rule; DEC-05 forbids regressing
      it). An incomplete EKB triple (empty min_revision/prereq_kb or a
      non-positive current revision) answers baseline-unknown - never a
      guessed baseline (DEC-02). }
    SrcNum := StrToIntDef(ARows[T].EkbSourceBuild, 0);
    if ((ARows[T].EkbSourceBuild = ACurrBuild)
        or ((SrcNum > 0) and (SrcNum <= CurrNum) and (CurrNum < TargetNum)))
       and (ARows[T].EkbKb <> '') then
    begin
      if (ARows[T].EkbMinRevision = '') or (ARows[T].EkbPrereqKb = '') then
      begin
        Result.Reason := 'baseline-unknown';
        Exit;
      end;
      RevNum := StrToIntDef(ACurrRevision, 0);
      if RevNum <= 0 then
      begin
        Result.Reason := 'baseline-unknown';
        Exit;
      end;
      MinRevNum := StrToIntDef(ARows[T].EkbMinRevision, 0);
      Result.Verdict := upgEKB;
      Result.NeedsBaselineCU := RevNum < MinRevNum;
      Exit;
    end;
    { R9 full feature update: same family + staged media. }
    if (ARows[T].OsFamily = ACurrOsFamily) and (ARows[T].FuMedia = '1') then
    begin
      Result.Verdict := upgFullFU;
      Exit;
    end;
    { R11 the row exists but carries no FU media. }
    Result.Reason := 'no-media';
    Exit;
  end;

  { R10 the arch is carried but not this language - never substitute. }
  for I := 0 to High(ARows) do
    if (ARows[I].TargetBuild = ATargetBuild)
       and (ARows[I].Arch = ACurrArch) then
    begin
      Result.Reason := 'language-not-carried';
      Exit;
    end;

  { R12 no (target, arch) row at all. }
  Result.Reason := 'no-media';
end;

end.
