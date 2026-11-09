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
  Task 2; pinned case-by-case by the testrunner golden matrix).
  Declared in Task 1 with a marked stub body; Task 2 replaces it. }
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
begin
  { STUB (plan 31-03 Task 1): this body only keeps the runner
    compiling; Task 2 of this plan replaces it with the frozen verdict
    rules and the 20-case golden matrix pins. }
  Result.Verdict := upgBlocked;
  Result.NeedsBaselineCU := False;
  Result.Reason := 'unimplemented';
end;

end.
