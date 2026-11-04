#!/usr/bin/env bash
# Fixture test for the WebView2 SDK dependency bumper — run from repo root.
#
# Offline by construction: WEBVIEW2_INDEX_FILE points the bumper at fixture
# JSON documents (the same downstream code path as a live curl response).
# The sandbox mirrors the repo layout (ci/bump-webview2-dep.bash + the two
# csproj) and the fixtures carry app-version DECOYS (<Version>5.0.0+2026.11
# </Version>, <FileVersion>5.0.0.0</FileVersion>, <AssemblyVersion>5.0.0.0
# </AssemblyVersion>) that must never move: the SDK lane (4-part 1.0.x) and
# the app-version matrix (3-part X.Y.Z) are disjoint namespaces.
#
# Sections:
#   a. bump old -> new applied to BOTH fixtures, decoys intact, prerelease
#      entries (higher-numbered, hyphenated) filtered out
#   b. no-op when the pin already equals the latest stable (byte-identical;
#      the floor rewrite is idempotent because the consumer fixtures carry
#      the lane's floor constant)
#   c. never-downgrade: an index whose max is older than the pin fails
#      closed and leaves the fixtures intact
#   d. ONLY the PackageReference line moves — exactly one changed line per fixture
#   e. absent index (WEBVIEW2_INDEX_FILE to a missing file) fails closed
#   f. --print-files prints exactly the two csproj paths plus the four
#      floor consumers (6 lines)
#   g. generator/installer divergence fails closed before any mutation
#   h. the MIN_WEBVIEW2_FLOOR single-sourcing lane: a drifted consumer is
#      healed to the constant exactly once per site; a stale floor (floor
#      build below the resolved SDK build) fails closed with NO writes; a
#      duplicated floor site in a consumer fails the lane before any write
set -u
SANDBOX="$(mktemp -d)"
SCRIPT_SRC="$(cd "$(dirname "$0")/.." && pwd)/bump-webview2-dep.bash"
FAILED_CASES=0
FLOOR_CURRENT="156.0.4314.35"

fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

write_fixture_csproj () {
    # $1 = destination, $2 = SDK version carried by the PackageReference
    cat > "$1" <<EOF
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <Version>5.0.0+2026.11</Version>
    <FileVersion>5.0.0.0</FileVersion>
    <AssemblyVersion>5.0.0.0</AssemblyVersion>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.Web.WebView2" Version="$2" />
  </ItemGroup>

</Project>
EOF
}

write_fixture_cs_program () {
    # $1 = destination, $2 = floor literal carried by the const line.
    # Mirrors the real consumer site shape (line-start-anchored const) and
    # carries a comment decoy citing the symbol WITHOUT the literal.
    cat > "$1" <<EOF
namespace Wson.Host
{
    public static class WebView2Compat
    {
        // The floor is rewritten by ci/bump-webview2-dep.bash; the
        // WebView2Compat.MinWebView2Version usages must not recopy it.
        public const string MinWebView2Version = "$2";

        public static bool IsVersionAtLeast(string detected, string min) => true;
    }
}
EOF
}

write_fixture_cmd_launcher () {
    # $1 = destination, $2 = floor literal carried by the set-line.
    # Mirrors the real consumer site shape (line-start-anchored set "...")
    # and carries a comment decoy naming the variable WITHOUT a literal.
    cat > "$1" <<EOF
@echo off
rem Minimum WebView2 runtime version accepted by the modern interface.
rem This literal is rewritten automatically by ci/bump-webview2-dep.bash
rem and must not be recopied or duplicated anywhere else in this file.
set "MIN_WEBVIEW2_VERSION=$2"

rem The gate expands %MIN_WEBVIEW2_VERSION% at the comparator call.
EOF
}

make_index () {
    # $@ = versions listed in the fixture index (prerelease entries carry '-')
    {
        printf '{"versions":['
        local first=1 v
        for v in "$@"; do
            [ "${first}" -eq 1 ] || printf ','
            printf '"%s"' "${v}"
            first=0
        done
        printf ']}\n'
    } > "${SANDBOX}/index.json"
}

make_sandbox_tree () {
    # $1 = SDK version written in both fixtures. The four floor-consumer
    # fixtures carry the lane's floor constant (FLOOR_CURRENT) so every
    # section runs the floor rewrite as an idempotent no-op unless a
    # section deliberately drifts them.
    rm -rf "${SANDBOX}/ci" "${SANDBOX}/src-modern" "${SANDBOX}/client"
    rm -f "${SANDBOX}/index.json" "${SANDBOX}/does-not-exist.json" "${SANDBOX}/UpdateGenerator.cmd"
    mkdir -p "${SANDBOX}/ci" \
        "${SANDBOX}/src-modern/generator/host" \
        "${SANDBOX}/src-modern/installer/host" \
        "${SANDBOX}/client"
    cp "${SCRIPT_SRC}" "${SANDBOX}/ci/bump-webview2-dep.bash"
    write_fixture_csproj "${SANDBOX}/src-modern/generator/host/UpdateGenerator.csproj" "$1"
    write_fixture_csproj "${SANDBOX}/src-modern/installer/host/UpdateInstaller.csproj" "$1"
    write_fixture_cs_program "${GEN_CS_FIX}" "${FLOOR_CURRENT}"
    write_fixture_cs_program "${INS_CS_FIX}" "${FLOOR_CURRENT}"
    write_fixture_cmd_launcher "${GEN_CMD_FIX}" "${FLOOR_CURRENT}"
    write_fixture_cmd_launcher "${INS_CMD_FIX}" "${FLOOR_CURRENT}"
}

# The index variable MUST be exported (a plain assignment does not reach the
# child process and the bumper would silently fall through to the live curl
# path — the exact bite this battery caught on its first run). Unset after
# each section so no fixture index leaks across sections and the battery
# stays offline by construction.
run_bumper () {
    BUMP_OUT="$(bash "${SANDBOX}/ci/bump-webview2-dep.bash" 2> "${SANDBOX}/bump-stderr.txt")"
    BUMP_RC=$?
}

point_index () {
    # $1 = index file the bumper must read
    export WEBVIEW2_INDEX_FILE="$1"
}

unpoint_index () {
    unset WEBVIEW2_INDEX_FILE
}

count_decoys () {
    grep -cE '<(Version>5\.0\.0\+2026\.11|FileVersion>5\.0\.0\.0|AssemblyVersion>5\.0\.0\.0)' "$1"
}

GEN_FIX="${SANDBOX}/src-modern/generator/host/UpdateGenerator.csproj"
INST_FIX="${SANDBOX}/src-modern/installer/host/UpdateInstaller.csproj"
GEN_CS_FIX="${SANDBOX}/src-modern/generator/host/Program.cs"
INS_CS_FIX="${SANDBOX}/src-modern/installer/host/Program.cs"
GEN_CMD_FIX="${SANDBOX}/UpdateGenerator.cmd"
INS_CMD_FIX="${SANDBOX}/client/UpdateInstaller.cmd"
OLD_SDK="1.0.2903.1"
NEW_SDK="1.0.4314.35"

# ---- section a: bump applied to both fixtures, decoys intact ---------------
make_sandbox_tree "${OLD_SDK}"
make_index "0.9.538.0" "${OLD_SDK}" "1.0.9999.0-prerelease" "${NEW_SDK}"
point_index "${SANDBOX}/index.json"
gen_decoys_before="$(count_decoys "${GEN_FIX}")"
inst_decoys_before="$(count_decoys "${INST_FIX}")"
run_bumper
[ "${BUMP_RC}" -eq 0 ] \
    || fail_case "a — le bump doit réussir (rc=${BUMP_RC}; stderr: $(cat "${SANDBOX}/bump-stderr.txt" | tr '\n' ' '))"
[ "${BUMP_OUT}" = "${NEW_SDK}" ] \
    || fail_case "a — stdout doit être EXACTEMENT une ligne: ${NEW_SDK} (lu: '${BUMP_OUT}')"
[ "$(grep -cF "Version=\"${NEW_SDK}\"" "${GEN_FIX}")" -eq 1 ] \
    || fail_case "a — la fixture generator doit porter ${NEW_SDK}"
[ "$(grep -cF "Version=\"${NEW_SDK}\"" "${INST_FIX}")" -eq 1 ] \
    || fail_case "a — la fixture installer doit porter ${NEW_SDK}"
gen_decoys_after="$(count_decoys "${GEN_FIX}")"
inst_decoys_after="$(count_decoys "${INST_FIX}")"
unpoint_index
[ "${gen_decoys_before}" = "${gen_decoys_after}" ] && [ "${gen_decoys_after}" -ge 3 ] \
    || fail_case "a — leurres app-version generator intacts (before=${gen_decoys_before} after=${gen_decoys_after})"
[ "${inst_decoys_before}" = "${inst_decoys_after}" ] && [ "${inst_decoys_after}" -ge 3 ] \
    || fail_case "a — leurres app-version installer intacts (before=${inst_decoys_before} after=${inst_decoys_after})"

# ---- section b: no-op when the pin already equals the latest stable --------
make_sandbox_tree "${NEW_SDK}"
make_index "${NEW_SDK}" "${OLD_SDK}"
point_index "${SANDBOX}/index.json"
cp "${GEN_FIX}" "${GEN_FIX}.pre"
cp "${INST_FIX}" "${INST_FIX}.pre"
run_bumper
unpoint_index
[ "${BUMP_RC}" -eq 0 ] || fail_case "b — le no-op doit réussir (rc=${BUMP_RC})"
[ "${BUMP_OUT}" = "${NEW_SDK}" ] || fail_case "b — stdout du no-op = version courante (lu: '${BUMP_OUT}')"
cmp -s "${GEN_FIX}" "${GEN_FIX}.pre" || fail_case "b — fixture generator modifiée par un no-op"
cmp -s "${INST_FIX}" "${INST_FIX}.pre" || fail_case "b — fixture installer modifiée par un no-op"

# ---- section c: never downgrade --------------------------------------------
make_sandbox_tree "${NEW_SDK}"
make_index "${OLD_SDK}" "0.9.538.0"
point_index "${SANDBOX}/index.json"
cp "${GEN_FIX}" "${GEN_FIX}.pre"
cp "${INST_FIX}" "${INST_FIX}.pre"
run_bumper
unpoint_index
[ "${BUMP_RC}" -ne 0 ] || fail_case "c — un index plus vieux que le pin doit échouer (rc=0 obtenu)"
cmp -s "${GEN_FIX}" "${GEN_FIX}.pre" || fail_case "c — fixture generator modifiée malgré le refus"
cmp -s "${INST_FIX}" "${INST_FIX}.pre" || fail_case "c — fixture installer modifiée malgré le refus"

# ---- section d: exactly one changed line per fixture ------------------------
make_sandbox_tree "${OLD_SDK}"
make_index "${NEW_SDK}"
point_index "${SANDBOX}/index.json"
cp "${GEN_FIX}" "${GEN_FIX}.pre"
cp "${INST_FIX}" "${INST_FIX}.pre"
run_bumper
unpoint_index
[ "${BUMP_RC}" -eq 0 ] || fail_case "d — le bump doit réussir (rc=${BUMP_RC})"
gen_diff_lines="$(diff "${GEN_FIX}.pre" "${GEN_FIX}" | grep -cE '^[<>]')"
inst_diff_lines="$(diff "${INST_FIX}.pre" "${INST_FIX}" | grep -cE '^[<>]')"
[ "${gen_diff_lines}" -eq 2 ] \
    || fail_case "d — generator: exactement 1 ligne changée (lignes diff <>=${gen_diff_lines})"
[ "${inst_diff_lines}" -eq 2 ] \
    || fail_case "d — installer: exactement 1 ligne changée (lignes diff <>=${inst_diff_lines})"

# ---- section e: absent index fails closed -----------------------------------
make_sandbox_tree "${OLD_SDK}"
point_index "${SANDBOX}/does-not-exist.json"
cp "${GEN_FIX}" "${GEN_FIX}.pre"
cp "${INST_FIX}" "${INST_FIX}.pre"
run_bumper
unpoint_index
[ "${BUMP_RC}" -ne 0 ] || fail_case "e — un index absent doit échouer (rc=0 obtenu)"
cmp -s "${GEN_FIX}" "${GEN_FIX}.pre" || fail_case "e — fixture generator modifiée malgré l'index absent"
cmp -s "${INST_FIX}" "${INST_FIX}.pre" || fail_case "e — fixture installer modifiée malgré l'index absent"

# ---- section f: --print-files prints 2 csproj + 4 floor consumers ----------
PRINTED="$(cd "${SANDBOX}" && bash "${SANDBOX}/ci/bump-webview2-dep.bash" --print-files)"
RCF=$?
[ "${RCF}" -eq 0 ] || fail_case "f — --print-files must succeed (rc=${RCF})"
[ "$(printf '%s\n' "${PRINTED}" | wc -l)" -eq 6 ] \
    || fail_case "f — --print-files must print exactly 6 lines (got: $(printf '%s\n' "${PRINTED}" | wc -l))"
printf '%s\n' "${PRINTED}" | grep -qx "src-modern/generator/host/UpdateGenerator.csproj" \
    || fail_case "f — generator csproj path missing from --print-files"
printf '%s\n' "${PRINTED}" | grep -qx "src-modern/installer/host/UpdateInstaller.csproj" \
    || fail_case "f — installer csproj path missing from --print-files"
printf '%s\n' "${PRINTED}" | grep -qx "src-modern/generator/host/Program.cs" \
    || fail_case "f — floor consumer Program.cs (generator) missing from --print-files"
printf '%s\n' "${PRINTED}" | grep -qx "src-modern/installer/host/Program.cs" \
    || fail_case "f — floor consumer Program.cs (installer) missing from --print-files"
printf '%s\n' "${PRINTED}" | grep -qx "UpdateGenerator.cmd" \
    || fail_case "f — floor consumer launcher (generator) missing from --print-files"
printf '%s\n' "${PRINTED}" | grep -qx "client/UpdateInstaller.cmd" \
    || fail_case "f — floor consumer launcher (installer) missing from --print-files"

# ---- section g: generator/installer divergence fails closed ------------------
make_sandbox_tree "${OLD_SDK}"
write_fixture_csproj "${INST_FIX}" "1.0.1722.45"
make_index "${NEW_SDK}"
point_index "${SANDBOX}/index.json"
cp "${GEN_FIX}" "${GEN_FIX}.pre"
cp "${INST_FIX}" "${INST_FIX}.pre"
run_bumper
unpoint_index
[ "${BUMP_RC}" -ne 0 ] || fail_case "g — une divergence generator/installer doit échouer (rc=0 obtenu)"
cmp -s "${GEN_FIX}" "${GEN_FIX}.pre" || fail_case "g — fixture generator modifiée malgré la divergence"
cmp -s "${INST_FIX}" "${INST_FIX}.pre" || fail_case "g — fixture installer modifiée malgré la divergence"

# ---- section h: MIN_WEBVIEW2_FLOOR single-sourcing lane ----------------------

# h1: a drifted consumer is healed to the lane's floor constant — exactly
# one floor site per consumer after the run, symmetric across all four.
make_sandbox_tree "${NEW_SDK}"
write_fixture_cs_program "${GEN_CS_FIX}" "156.0.4314.34"
write_fixture_cs_program "${INS_CS_FIX}" "156.0.4314.34"
write_fixture_cmd_launcher "${GEN_CMD_FIX}" "156.0.4314.34"
write_fixture_cmd_launcher "${INS_CMD_FIX}" "156.0.4314.34"
make_index "${NEW_SDK}"
point_index "${SANDBOX}/index.json"
run_bumper
unpoint_index
[ "${BUMP_RC}" -eq 0 ] \
    || fail_case "h1 — the floor-heal run must succeed (rc=${BUMP_RC}; stderr: $(tr '\n' ' ' < "${SANDBOX}/bump-stderr.txt"))"
for fixture in "${GEN_CS_FIX}" "${INS_CS_FIX}" "${GEN_CMD_FIX}" "${INS_CMD_FIX}"; do
    [ "$(grep -cF "156.0.4314.34" "${fixture}")" -eq 0 ] \
        || fail_case "h1 — stale floor literal still present in ${fixture}"
    [ "$(grep -cF "${FLOOR_CURRENT}" "${fixture}")" -eq 1 ] \
        || fail_case "h1 — floor literal must appear exactly once in ${fixture}"
done

# h2: a stale floor (floor build below the resolved SDK build) fails closed
# with NO writes anywhere in the sandbox tree.
make_sandbox_tree "${NEW_SDK}"
sed -i 's/readonly MIN_WEBVIEW2_FLOOR="156\.0\.4314\.35"/readonly MIN_WEBVIEW2_FLOOR="156.0.0000.1"/' \
    "${SANDBOX}/ci/bump-webview2-dep.bash"
grep -qF 'MIN_WEBVIEW2_FLOOR="156.0.0000.1"' "${SANDBOX}/ci/bump-webview2-dep.bash" \
    || fail_case "h2 — the stale-floor mutation of the sandbox lane did not land"
for fixture in "${GEN_FIX}" "${INST_FIX}" "${GEN_CS_FIX}" "${INS_CS_FIX}" "${GEN_CMD_FIX}" "${INS_CMD_FIX}"; do
    cp "${fixture}" "${fixture}.pre"
done
run_bumper
unpoint_index
[ "${BUMP_RC}" -ne 0 ] || fail_case "h2 — a stale floor must fail the lane (rc=0 obtained)"
grep -qF "raise MIN_WEBVIEW2_FLOOR in ci/bump-webview2-dep.bash" "${SANDBOX}/bump-stderr.txt" \
    || fail_case "h2 — the stale-floor refusal must name the operator action (stderr: $(tr '\n' ' ' < "${SANDBOX}/bump-stderr.txt"))"
for fixture in "${GEN_FIX}" "${INST_FIX}" "${GEN_CS_FIX}" "${INS_CS_FIX}" "${GEN_CMD_FIX}" "${INS_CMD_FIX}"; do
    cmp -s "${fixture}" "${fixture}.pre" \
        || fail_case "h2 — ${fixture} was written despite the stale-floor refusal"
done

# h3: a duplicated floor site in a consumer fails the lane before any write.
make_sandbox_tree "${NEW_SDK}"
printf 'set "MIN_WEBVIEW2_VERSION=%s"\n' "${FLOOR_CURRENT}" >> "${GEN_CMD_FIX}"
grep -cE '^set "MIN_WEBVIEW2_VERSION=' "${GEN_CMD_FIX}" | grep -qx "2" \
    || fail_case "h3 — the duplicated-site mutation of the sandbox fixture did not land"
for fixture in "${GEN_FIX}" "${INST_FIX}" "${GEN_CS_FIX}" "${INS_CS_FIX}" "${GEN_CMD_FIX}" "${INS_CMD_FIX}"; do
    cp "${fixture}" "${fixture}.pre"
done
run_bumper
unpoint_index
[ "${BUMP_RC}" -ne 0 ] || fail_case "h3 — a duplicated floor site must fail the lane (rc=0 obtained)"
for fixture in "${GEN_FIX}" "${INST_FIX}" "${GEN_CS_FIX}" "${INS_CS_FIX}" "${GEN_CMD_FIX}" "${INS_CMD_FIX}"; do
    cmp -s "${fixture}" "${fixture}.pre" \
        || fail_case "h3 — ${fixture} was written despite the duplicated-site refusal"
done

rm -rf "${SANDBOX}"
if [ "${FAILED_CASES}" -gt 0 ]
then
    echo "FAIL bump-webview2-dep: ${FAILED_CASES} case(s) failed"
    exit "${FAILED_CASES}"
fi
echo "PASS bump-webview2-dep (symmetric bump + decoys intact, byte-identical no-op, never-downgrade, 1 line/fixture, absent index fail-closed, print-files 6, divergence fail-closed, floor single-sourcing: heal + stale-floor + duplicate-site fail-closed)"
exit 0
