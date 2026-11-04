{*** Enablement-Package predicates fed by the shipped builds-table data
    file (CONTEXT decision: a DATA FILE, not generated Pascal - the
    roadmap's codegen sites step 4 -> 3 when plan 03 deletes the au3
    site).

    Data file contract (generated from static/builds.ini by BOTH generator
    twins, sh/generate-build-sites.bash + cmd/GenerateBuildSites.vbs):

      client/UpdateTable/builds.txt
      # comment lines start with '#'
      build|arch|os_family|servicing_branch|status|ekb_source_build|ekb_kb|ekb_prereq_kb|ekb_min_revision|is_enforced

    - exactly 10 pipe-delimited fields per row, whitespace-trimmed,
      empty = absent
    - malformed rows (wrong field count) are skipped, never fatal
    - the file ships with the client tree; updates need no recompile

    The three predicates are VERBATIM ports of the incumbent installer au3
    lines 290-347, including the 19041-family branch range rule and the
    enforcement-mode skip. The file-existence probes are injected via a
    callback so the console testrunner can drive the golden table without
    a real tree; production passes a FindFirst-based probe (the incumbent
    FileExists accepts wildcards). }

unit buildsupgrade;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

const
  { Relative to the script (client tree root) directory. }
  BU_BUILDS_FILE_REL = 'UpdateTable\builds.txt';

type
  TBuildRow = record
    Build: string;
    Arch: string;
    OsFamily: string;
    ServicingBranch: string;
    Status: string;
    EkbSourceBuild: string;
    EkbKb: string;
    EkbPrereqKb: string;
    EkbMinRevision: string;
    IsEnforced: Integer;
  end;
  TBuildRows = array of TBuildRow;

  { File-existence probe injection (wildcard-tolerant in production). }
  TFileProbe = function(const APath: string): Boolean;

{ Tolerant parser: '#' comments, blank lines and malformed rows are
  skipped; fields are whitespace-trimmed; missing file = empty table. }
function BuParseBuildsFile(const APath: string): TBuildRows;

{ au3:290-297 verbatim: the first row whose build matches decides; a
  matching row with status "ineligible" makes the build ineligible; no
  match = not ineligible. }
function BuIsBuildIneligible(const ARows: TBuildRows;
  const ABuild: string): Boolean;

{ au3:337-347 verbatim: 1 when a row with ekb_source_build = current
  build AND matching arch carries is_enforced = 1; else 0. }
function BuBuildUpgradeEnforced(const ARows: TBuildRows;
  const ACurrBuild, ACurrArch: string): Integer;

{ au3:299-335 verbatim: ineligible short-circuit; row match by
  (ekb_source_build = current build AND arch) OR the 19041-family branch
  rule (servicing_branch = 19041 AND arch AND 19041 <= current build <
  row build); non-enforced rows skipped in enforcement mode; then the EKB
  payload probes at \w100[-x64]\glb\<windows11.0|windows10.0>-<kb>-<arch>*.*
  or the \<currentBuild>\ variant. Returns 1/0 like the incumbent. }
function BuBuildUpgradeAvailable(const ARows: TBuildRows;
  const ABasePath: string; AEnforcementMode: Integer;
  const ACurrBuild, ACurrArch: string; AProbe: TFileProbe): Integer;

{ Production probe - FindFirst parity of the incumbent's wildcard
  FileExists. }
function BuFileProbe(const APath: string): Boolean;

{ Convenience loader: parse <ABasePath>\UpdateTable\builds.txt. }
function BuLoadRows(const ABasePath: string): TBuildRows;

implementation

function BuFileProbe(const APath: string): Boolean;
var
  SearchRec: TSearchRec;
begin
  Result := SysUtils.FindFirst(APath, faAnyFile, SearchRec) = 0;
  if Result then
    SysUtils.FindClose(SearchRec);
end;

function BuLoadRows(const ABasePath: string): TBuildRows;
begin
  Result := BuParseBuildsFile(
    IncludeTrailingPathDelimiter(ABasePath) + BU_BUILDS_FILE_REL);
end;

function BuParseBuildsFile(const APath: string): TBuildRows;
var
  Sl: TStringList;
  I, FieldCount: Integer;
  Line, Field: string;
  Row: TBuildRow;
  InRow: Boolean;
begin
  Result := nil;
  if not FileExists(APath) then
    Exit;
  Sl := TStringList.Create;
  try
    try
      Sl.LoadFromFile(APath);
    except
      { Unreadable data file = empty table, never fatal (fail-closed:
        the gates then treat enablement as unavailable, the incumbent's
        behavior with an empty registry). }
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
        if FieldCount > 10 then
        begin
          { More than 10 fields = malformed row - skip it. }
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
          1: Row.Build := Field;
          2: Row.Arch := Field;
          3: Row.OsFamily := Field;
          4: Row.ServicingBranch := Field;
          5: Row.Status := Field;
          6: Row.EkbSourceBuild := Field;
          7: Row.EkbKb := Field;
          8: Row.EkbPrereqKb := Field;
          9: Row.EkbMinRevision := Field;
          10: Row.IsEnforced := StrToIntDef(Field, 0);
        end;
      end;
      if FieldCount = 10 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := Row;
      end;
    end;
  finally
    Sl.Free;
  end;
end;

function BuIsBuildIneligible(const ARows: TBuildRows;
  const ABuild: string): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to High(ARows) do
    if ARows[I].Build = ABuild then
      Exit(ARows[I].Status = 'ineligible');
end;

function BuBuildUpgradeEnforced(const ARows: TBuildRows;
  const ACurrBuild, ACurrArch: string): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(ARows) do
    if (ARows[I].EkbSourceBuild = ACurrBuild)
       and (ARows[I].Arch = ACurrArch) then
      if ARows[I].IsEnforced = 1 then
        Exit(1);
end;

function BuBuildUpgradeAvailable(const ARows: TBuildRows;
  const ABasePath: string; AEnforcementMode: Integer;
  const ACurrBuild, ACurrArch: string; AProbe: TFileProbe): Integer;
var
  I: Integer;
  Match: Boolean;
  OsPrefix, SubDir, P1, P2: string;
  CurrBuildNum, RowBuildNum: Integer;
begin
  Result := 0;
  if BuIsBuildIneligible(ARows, ACurrBuild) then
    Exit(0);
  CurrBuildNum := StrToIntDef(ACurrBuild, 0);
  for I := 0 to High(ARows) do
  begin
    Match := False;
    if (ARows[I].EkbSourceBuild = ACurrBuild)
       and (ARows[I].Arch = ACurrArch) then
      Match := True
    else if (ARows[I].ServicingBranch = '19041')
            and (ARows[I].Arch = ACurrArch)
            and (CurrBuildNum >= 19041) then
    begin
      RowBuildNum := StrToIntDef(ARows[I].Build, 0);
      if (RowBuildNum > 0) and (CurrBuildNum < RowBuildNum) then
        Match := True;
    end;

    if Match then
    begin
      { Enforcement-mode skip (au3:319). }
      if (AEnforcementMode > 0) and (ARows[I].IsEnforced <> 1) then
        Continue;
      if ARows[I].EkbKb <> '' then
      begin
        if ARows[I].OsFamily = 'win11' then
          OsPrefix := 'windows11.0-'
        else
          OsPrefix := 'windows10.0-';
        if ACurrArch = 'x64' then
          SubDir := '\w100-x64\glb\'
        else
          SubDir := '\w100\glb\';
        { au3 concatenation parity: $basepath carries NO trailing
          backslash and $subDir starts with one. }
        P1 := ABasePath + SubDir
          + OsPrefix + ARows[I].EkbKb + '-' + ACurrArch + '*.*';
        P2 := ABasePath + SubDir
          + ACurrBuild + '\' + OsPrefix + ARows[I].EkbKb + '-' + ACurrArch + '*.*';
        if AProbe(P1) or AProbe(P2) then
          Exit(1);
      end;
    end;
  end;
end;

end.
