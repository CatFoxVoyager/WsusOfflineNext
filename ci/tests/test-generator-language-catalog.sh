#!/usr/bin/env bash
# Battery: generator language catalog (Phase 38, plan 38-02) — the golden-23
# catalog, the engine vocabulary parity anchors, and the Program.cs host
# source pins for the language feature (SEL-01/SEL-02/DL-01). Offline by
# contract: file greps only — no compile, no engine run, no network; budget
# well under 60 s. The frontend/host compile gates run separately
# (npm --prefix src-modern/generator run build, dotnet publish host).
#
# CI home: the dotnet-build job of .github/workflows/ci.yml (it compiles the
# host the pins describe).
#
# Sections:
#   a. GOLDEN       — the catalog derived LIVE from static/ with the host
#                     rule (last '-'-delimited token of every
#                     StaticDownloadLinks-*.txt basename in the BASE static/
#                     dir, 3-char non-glb tokens kept, dedup, Ordinal sort):
#                     family parity (dotnet set == ie11-w62-x64 set), the
#                     measured golden list pinned verbatim, golden within the
#                     engine vocabulary, glb excluded.
#   b. VOCAB-PARITY — the 24-token engine vocabulary literal is identical in
#                     cmd/CreateISOImage.cmd and cmd/CopyToTarget.cmd; the
#                     :Lang_* label set in cmd/DownloadUpdates.cmd equals the
#                     vocabulary minus glb. These are the reconciliation
#                     anchors the host ENGINE_VOCAB constant is pinned
#                     against (section c) — never re-derived from memory.
#   c. HOST-PINS    — source-shape pins on the host: the ENGINE_VOCAB /
#                     LANG_LABELS constants, the tolerant static/ derivation
#                     (base dir only, never static/custom, never fatal), the
#                     [Languages] reader branch, the state push keys with
#                     the fail-open label fallback, the void-all payload
#                     validator (distinct named function), the 26a0073
#                     absent/present save branch, and the writer grammar.
#   d. CAN-FAIL     — always-on controls proving the instruments bite: a
#                     scratch static/ missing one family member reds the
#                     parity check; a scratch Program.cs copy with the
#                     ENGINE_VOCAB declaration stripped reds the constant
#                     pin; a permissivized length check reds the void-all
#                     pin set; an ungated languages write path reds the
#                     save pin set. Conforming twin fixtures must stay
#                     green (detection without over-blocking).
#
# Provenance (census idiom DEC-35-10): the golden list was measured on
# 2026-11-27 (plan 38-02 planning session, RESEARCH G5): 87
# StaticDownloadLinks-*.txt files, the dotnet and ie11-w62-x64 families
# carrying the IDENTICAL 23-code set. Any future divergence is a deliberate
# battery update with its own dated provenance line — never a silent
# re-census.
set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATIC_DIR="${REPO_ROOT}/static"
ISO_CMD="${REPO_ROOT}/cmd/CreateISOImage.cmd"
COPY_CMD="${REPO_ROOT}/cmd/CopyToTarget.cmd"
ENGINE_CMD="${REPO_ROOT}/cmd/DownloadUpdates.cmd"
PROGRAM_CS="${REPO_ROOT}/src-modern/generator/host/Program.cs"

FAILED_CASES=0
fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

for f in "${STATIC_DIR}" "${ISO_CMD}" "${COPY_CMD}" "${ENGINE_CMD}" "${PROGRAM_CS}"; do
    [ -e "${f}" ] || { echo "FAIL: pre-flight: missing ${f}"; exit 1; }
done

SANDBOX="$(mktemp -d)" || { echo "FAIL: mktemp -d"; exit 1; }
trap 'rm -rf "${SANDBOX}"' EXIT

# --- helpers ---------------------------------------------------------------
# count_f: fixed-string occurrence count. grep -c exits 1 on a zero count,
# so the $( ) capture keeps the printed number and the caller compares it
# numerically — a genuine 0 must stay 0 (never compose with ||).
count_f () { # <file> <fixed-string> -> count on stdout
    grep -cF -- "$2" "$1"
}

# pin_eq: numeric equality assertion with a named verdict line.
pin_eq () { # <name> <expected> <actual>
    if [ "${2}" -eq "${3}" ]; then
        echo "  ok: ${1} (${3})"
    else
        fail_case "${1}: expected ${2}, got ${3}"
    fi
}

# region: lines strictly between a start regex match (exclusive) and the
# next end regex match (exclusive).
region () { # <file> <start_re> <end_re> -> lines on stdout
    awk -v s="$2" -v e="$3" '
        $0 ~ s { inr = 1; next }
        inr && $0 ~ e { exit }
        inr { print }
    ' "$1"
}

# cs_method: a C# method body — from the line matching the signature regex
# (exclusive) to the method's own closing brace at the 8-space method
# indent (exclusive). The brace stop keeps a following method's doc
# comment (which may mention the sibling contract's words) out of the
# body — the RED run's "3 languages mentions in the upgrade validator"
# was exactly that leak.
cs_method () { # <file> <signature_re> -> lines on stdout
    awk -v s="$2" '
        !started && $0 ~ s { started = 1; next }
        started && /^        }[[:space:]]*$/ { exit }
        started && /^        (private|public|internal)[ ]/ { exit }
        started { print }
    ' "$1"
}

# vocab_from_cmd: the engine vocabulary from the %%j grammar line (exactly
# one per engine script — pinned in section b), one token per line,
# LC_ALL=C sorted.
#
# Measured count (2026-11-27 RED run): the verbatim %%j anchor carries 25
# tokens — glb + 24 non-glb (the 24 :Lang_ labels). The plan prose said
# "24-token vocabulary": an arithmetic slip counting the non-glb set only.
# The verbatim anchor wins (the anchor's own glb gate needs glb as a
# member); the battery pins 25 + the label set == vocabulary minus glb.
vocab_from_cmd () { # <cmd-file> -> tokens on stdout
    sed -n 's/^.*for %%j in (\([^)]*\)).*$/\1/p' "$1" \
        | tr ' ' '\n' | grep -E '^[a-z]{3}$' | LC_ALL=C sort -u
}

# derive_catalog: the host derivation rule mirrored (the last
# '-'-delimited token of every StaticDownloadLinks-*.txt basename in the
# BASE dir passed, 3-char tokens other than glb kept, dedup, Ordinal
# sort). The vocabulary membership filter is applied by the caller — the
# anchor lives in section b.
derive_catalog () { # <static-dir> -> tokens on stdout
    for f in "$1"/StaticDownloadLinks-*.txt; do
        [ -e "${f}" ] || continue
        stem="$(basename "${f}" .txt)"
        token="${stem##*-}"
        [ "${#token}" -eq 3 ] || continue
        [ "${token}" = "glb" ] && continue
        echo "${token}"
    done | LC_ALL=C sort -u
}

# family_langs: language tokens carried by one static family (glob
# prefix), one per line, sorted.
family_langs () { # <glob-prefix> -> tokens on stdout
    for f in "$1"*.txt; do
        [ -e "${f}" ] || continue
        basename "${f}" .txt | sed 's/^.*-//'
    done | LC_ALL=C sort -u
}

# check_family_parity: status 0 when the dotnet and ie11-w62-x64 families
# carry identical token sets.
check_family_parity () { # <static-dir> -> status
    diff <(family_langs "$1/StaticDownloadLinks-dotnet-") \
         <(family_langs "$1/StaticDownloadLinks-ie11-w62-x64-") >/dev/null 2>&1
}

# check_vocab_decl: the ENGINE_VOCAB declaration pin (parameterized so the
# can-fail control can run it against a mutated copy).
check_vocab_decl () { # <program-cs-file> -> status 0 when pinned
    [ "$(count_f "$1" 'private static readonly string[] ENGINE_VOCAB')" -eq 1 ]
}

# check_validator_pins: the void-all languages validator pin set (38-02
# T2, parameterized for the can-fail control). Every sub-assert prints its
# own diagnosis; the return status is the FAIL COUNT (0 = pinned).
check_validator_pins () { # <program-cs-file> -> status (fail count)
    local fails=0 f="$1" body n
    body="$(cs_method "${f}" 'GetLanguagesPayloadSelection[(]JsonElement payload, out bool payloadPresent[)]')"
    if [ -z "${body}" ]; then
        echo "    validator: body not extractable"
        return 1
    fi
    n="$(printf '%s\n' "${body}" | grep -cF 'TryGetProperty("languages", out var langs)')"
    [ "${n}" -eq 1 ] || { echo "    validator: TryGetProperty(languages) x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${body}" | grep -cF 'ValueKind != JsonValueKind.Array')"
    [ "${n}" -eq 1 ] || { echo "    validator: non-array void-all x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${body}" | grep -cF 'return new List<string>();')"
    [ "${n}" -eq 3 ] || { echo "    validator: void-all returns x${n}, want 3"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${body}" | grep -cF 'Length != 3')"
    [ "${n}" -eq 1 ] || { echo "    validator: fixed-length check x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${body}" | grep -cF 'ENGINE_VOCAB')"
    [ "${n}" -eq 1 ] || { echo "    validator: vocabulary membership x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${body}" | grep -cF 'StringComparison.OrdinalIgnoreCase')"
    [ "${n}" -eq 1 ] || { echo "    validator: OrdinalIgnoreCase dedup x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${body}" | grep -cF '"upgrade"')"
    [ "${n}" -eq 0 ] || { echo "    validator: upgrade coupling x${n}, want 0 (distinct contract)"; fails=$((fails + 1)); }
    return "${fails}"
}

# check_save_pins: the absent/present save branch pin set (38-02 T2,
# parameterized for the can-fail control) — the languages write path is
# behind its OWN property gate; a payload without the property reaches no
# write call (26a0073 both-sides). Return status = fail count.
check_save_pins () { # <program-cs-file> -> status (fail count)
    local fails=0 f="$1" sec n
    sec="$(region "${f}" 'private void SaveIniFiles' 'private static void WriteLanguagesSection')"
    if [ -z "${sec}" ]; then
        echo "    save: region not extractable"
        return 1
    fi
    n="$(printf '%s\n' "${sec}" | grep -cF 'bool hasLanguages = payload.TryGetProperty("languages", out JsonElement _)')"
    [ "${n}" -eq 1 ] || { echo "    save: languages presence gate x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${sec}" | grep -cF 'if (hasLegacy || hasLanguages)')"
    [ "${n}" -eq 1 ] || { echo "    save: compound write guard x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${sec}" | grep -cF 'if (hasLegacy)')"
    [ "${n}" -eq 1 ] || { echo "    save: legacy loop on its own gate x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${sec}" | grep -cF 'GetLanguagesPayloadSelection(payload, out _)')"
    [ "${n}" -eq 1 ] || { echo "    save: validated selection call x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${sec}" | grep -cF 'WriteLanguagesSection(lines,')"
    [ "${n}" -eq 1 ] || { echo "    save: section writer call x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${sec}" | grep -cF 'File.WriteAllLines(genIni, lines)')"
    [ "${n}" -eq 1 ] || { echo "    save: single genIni write x${n}, want 1"; fails=$((fails + 1)); }
    return "${fails}"
}

# --- section a: GOLDEN -----------------------------------------------------
echo "--- section a: GOLDEN (live static/ derivation vs the pinned 23) ---"

GOLDEN="ara chs cht csy dan deu ell esn fin fra heb hun ita jpn kor nld nor plk ptb ptg rus sve trk"

DOTNET_SET="$(family_langs "${STATIC_DIR}/StaticDownloadLinks-dotnet-")"
IE11_SET="$(family_langs "${STATIC_DIR}/StaticDownloadLinks-ie11-w62-x64-")"
CATALOG="$(derive_catalog "${STATIC_DIR}")"
ISO_VOCAB="$(vocab_from_cmd "${ISO_CMD}")"
ENGINE_LABELS="$(grep -oE '^:Lang_[a-z]{3}' "${ENGINE_CMD}" | sed 's/^:Lang_//' | LC_ALL=C sort -u)"

if check_family_parity "${STATIC_DIR}"; then
    echo "  ok: family parity — dotnet and ie11-w62-x64 carry the identical set ($(printf '%s\n' "${DOTNET_SET}" | grep -c .) codes)"
else
    fail_case "GOLDEN: family parity broken — dotnet and ie11-w62-x64 sets diverge"
    diff <(printf '%s\n' "${DOTNET_SET}") <(printf '%s\n' "${IE11_SET}") | sed 's/^/    /'
fi

GOLDEN_COUNT="$(printf '%s\n' "${CATALOG}" | grep -c .)"
pin_eq "GOLDEN: catalog count == 23 (measured 2026-11-27)" 23 "${GOLDEN_COUNT}"

if diff <(printf '%s\n' "${CATALOG}") <(printf '%s\n' "${GOLDEN}" | tr ' ' '\n') >/dev/null; then
    echo "  ok: derived catalog == the pinned golden 23 (dated provenance in header)"
else
    fail_case "GOLDEN: derived catalog diverges from the pinned golden list — a deliberate battery update with new provenance is required (census idiom DEC-35-10), never a silent re-census"
    diff <(printf '%s\n' "${CATALOG}") <(printf '%s\n' "${GOLDEN}" | tr ' ' '\n') | sed 's/^/    /'
fi

GOLDEN_OUTSIDE_VOCAB="$(printf '%s\n' "${CATALOG}" | LC_ALL=C comm -23 - <(printf '%s\n' "${ISO_VOCAB}") | grep -c .)"
pin_eq "GOLDEN: catalog is a subset of the engine vocabulary (0 outside)" 0 "${GOLDEN_OUTSIDE_VOCAB}"

GLB_IN_CATALOG="$(printf '%s\n' "${CATALOG}" | grep -cx glb)"
pin_eq "GOLDEN: glb excluded from the derived catalog (always included, never a checkbox)" 0 "${GLB_IN_CATALOG}"

# --- section b: VOCAB-PARITY -----------------------------------------------
echo "--- section b: VOCAB-PARITY (the reconciliation anchors) ---"

ISO_VOCAB_LINES="$(grep -c 'for %%j in (' "${ISO_CMD}")"
COPY_VOCAB_LINES="$(grep -c 'for %%j in (' "${COPY_CMD}")"
pin_eq "VOCAB: exactly one %%j vocabulary line in CreateISOImage.cmd" 1 "${ISO_VOCAB_LINES}"
pin_eq "VOCAB: exactly one %%j vocabulary line in CopyToTarget.cmd" 1 "${COPY_VOCAB_LINES}"

COPY_VOCAB="$(vocab_from_cmd "${COPY_CMD}")"
if diff <(printf '%s\n' "${ISO_VOCAB}") <(printf '%s\n' "${COPY_VOCAB}") >/dev/null; then
    echo "  ok: the 24-token vocabulary literal is identical in both engine scripts"
else
    fail_case "VOCAB: CreateISOImage.cmd and CopyToTarget.cmd vocabularies diverge"
    diff <(printf '%s\n' "${ISO_VOCAB}") <(printf '%s\n' "${COPY_VOCAB}") | sed 's/^/    /'
fi

VOCAB_COUNT="$(printf '%s\n' "${ISO_VOCAB}" | grep -c .)"
pin_eq "VOCAB: vocabulary carries 25 tokens (glb + 24 non-glb — the verbatim :55 anchor; the plan's 24 counted the non-glb set)" 25 "${VOCAB_COUNT}"

LABEL_COUNT="$(printf '%s\n' "${ENGINE_LABELS}" | grep -c .)"
pin_eq "VOCAB: DownloadUpdates.cmd carries 24 :Lang_ labels" 24 "${LABEL_COUNT}"

VOCAB_MINUS_GLB="$(printf '%s\n' "${ISO_VOCAB}" | grep -vx glb)"
if diff <(printf '%s\n' "${ENGINE_LABELS}") <(printf '%s\n' "${VOCAB_MINUS_GLB}") >/dev/null; then
    echo "  ok: :Lang_ label set == vocabulary minus glb"
else
    fail_case "VOCAB: :Lang_ labels do not match the vocabulary minus glb"
    diff <(printf '%s\n' "${ENGINE_LABELS}") <(printf '%s\n' "${VOCAB_MINUS_GLB}") | sed 's/^/    /'
fi

GLB_IN_VOCAB="$(printf '%s\n' "${ISO_VOCAB}" | grep -cx glb)"
pin_eq "VOCAB: glb is a vocabulary member (the always-included anchor)" 1 "${GLB_IN_VOCAB}"

# --- section c: HOST-PINS --------------------------------------------------
echo "--- section c: HOST-PINS (Program.cs source shapes) ---"

# P1: the ENGINE_VOCAB constant exists, declared once as a string[].
if check_vocab_decl "${PROGRAM_CS}"; then
    echo "  ok: HOST: ENGINE_VOCAB declared once (string[])"
else
    fail_case "HOST: ENGINE_VOCAB declaration missing or duplicated"
fi

# P2: the constant carries EXACTLY the engine vocabulary set — extracted
# from the CreateISOImage.cmd anchor, never retyped from memory. The
# region anchor avoids []/() escape traps by anchoring on the
# declaration's `$`-terminated tail (awk ERE treats \[ as a plain [).
VOCAB_REGION="$(region "${PROGRAM_CS}" 'ENGINE_VOCAB =$' '^[[:space:]]*};')"
CS_VOCAB_TOKENS="$(printf '%s\n' "${VOCAB_REGION}" | grep -oE '"[a-z]{3}"' | tr -d '"' | LC_ALL=C sort -u)"
if diff <(printf '%s\n' "${CS_VOCAB_TOKENS}") <(printf '%s\n' "${ISO_VOCAB}") >/dev/null; then
    echo "  ok: HOST: ENGINE_VOCAB set == CreateISOImage.cmd vocabulary (verbatim anchor)"
else
    fail_case "HOST: ENGINE_VOCAB set diverges from the CreateISOImage.cmd anchor"
    diff <(printf '%s\n' "${CS_VOCAB_TOKENS}") <(printf '%s\n' "${ISO_VOCAB}") | sed 's/^/    /'
fi

# P3: the LANG_LABELS display map (UI-SPEC binding copy) carries one entry
# per vocabulary token.
LABELS_DECL="$(count_f "${PROGRAM_CS}" 'Dictionary<string, string> LANG_LABELS')"
pin_eq "HOST: LANG_LABELS declared once" 1 "${LABELS_DECL}"

LABELS_REGION="$(region "${PROGRAM_CS}" 'Dictionary<string, string> LANG_LABELS' '^[[:space:]]*};')"
LABELS_ENTRIES="$(printf '%s\n' "${LABELS_REGION}" | grep -c '{ "')"
pin_eq "HOST: LANG_LABELS carries 24 entries (glb + 23)" 24 "${LABELS_ENTRIES}"

LABELS_TOKENS="$(printf '%s\n' "${LABELS_REGION}" | grep -oE '"[a-z]{3}"' | tr -d '"' | LC_ALL=C sort -u)"
# Every PUSHABLE token must carry a label: the derived catalog + glb. enu
# sits in the vocabulary but has no static lists behind it (never derived,
# never pushed, never labeled — RESEARCH A1; the fail-open fallback covers
# any surprise token). GOLDEN is space-separated: split to lines first.
if diff <(printf '%s\n' "${LABELS_TOKENS}") <( { printf '%s\n' "${GOLDEN}" | tr ' ' '\n'; echo glb; } | LC_ALL=C sort -u) >/dev/null; then
    echo "  ok: HOST: LANG_LABELS keys == the pushable space (derived catalog + glb)"
else
    fail_case "HOST: LANG_LABELS keys diverge from the pushable token space"
    diff <(printf '%s\n' "${LABELS_TOKENS}") <( { printf '%s\n' "${GOLDEN}" | tr ' ' '\n'; echo glb; } | LC_ALL=C sort -u) | sed 's/^/    /'
fi

# P4: the derivation helper is declared and called.
DERIVE_DECL="$(count_f "${PROGRAM_CS}" 'DeriveLanguageCatalog(string root)')"
pin_eq "HOST: DeriveLanguageCatalog declared once" 1 "${DERIVE_DECL}"

DERIVE_CALLS="$(count_f "${PROGRAM_CS}" 'DeriveLanguageCatalog(root)')"
if [ "${DERIVE_CALLS}" -ge 1 ]; then
    echo "  ok: HOST: DeriveLanguageCatalog called at init (${DERIVE_CALLS} call site(s))"
else
    fail_case "HOST: DeriveLanguageCatalog never called (the catalog would never reach the push)"
fi

# P5: the derivation body carries the tolerant base-dir-only shapes.
# Guard: an empty body makes every region pin below vacuous — that is a
# loud instrument condition, never a green.
DERIVE_BODY="$(cs_method "${PROGRAM_CS}" 'DeriveLanguageCatalog[(]string root[)]')"
if [ -z "${DERIVE_BODY}" ]; then
    fail_case "HOST: DeriveLanguageCatalog body not extractable — region pins would read vacuously"
fi
DERIVE_STATIC_DIR="$(printf '%s\n' "${DERIVE_BODY}" | grep -cF 'Path.Combine(root, "static")')"
pin_eq "HOST: derivation scans the BASE static/ dir" 1 "${DERIVE_STATIC_DIR}"

DERIVE_CUSTOM="$(printf '%s\n' "${DERIVE_BODY}" | grep -ciF 'custom')"
pin_eq "HOST: derivation never references custom (static/custom is user state)" 0 "${DERIVE_CUSTOM}"

DERIVE_PATTERN="$(printf '%s\n' "${DERIVE_BODY}" | grep -cF '"StaticDownloadLinks-*.txt"')"
pin_eq "HOST: derivation filters the StaticDownloadLinks-*.txt family" 1 "${DERIVE_PATTERN}"

DERIVE_VOCAB_USE="$(printf '%s\n' "${DERIVE_BODY}" | grep -cF 'ENGINE_VOCAB')"
if [ "${DERIVE_VOCAB_USE}" -ge 1 ]; then
    echo "  ok: HOST: derivation filters through ENGINE_VOCAB membership"
else
    fail_case "HOST: derivation does not filter through ENGINE_VOCAB"
fi

DERIVE_SORT="$(printf '%s\n' "${DERIVE_BODY}" | grep -cF 'Sort(StringComparer.Ordinal)')"
pin_eq "HOST: derivation sorts Ordinal" 1 "${DERIVE_SORT}"

DERIVE_THROW="$(printf '%s\n' "${DERIVE_BODY}" | grep -cF 'throw')"
pin_eq "HOST: derivation is tolerant and never fatal (no throw)" 0 "${DERIVE_THROW}"

# P6: the [Languages] branch inside the existing section-scoped INI reader
# loop (same isEnabled parse as the sibling branches; the reader stays
# dumb — unknown tokens land in the dict and are filtered at push time).
READER_LANG_BRANCH="$(count_f "${PROGRAM_CS}" 'currentSection == "Languages"')"
pin_eq "HOST: [Languages] reader branch present in the INI loop" 1 "${READER_LANG_BRANCH}"

LANGS_DICT_USES="$(count_f "${PROGRAM_CS}" 'languagesDict')"
if [ "${LANGS_DICT_USES}" -ge 3 ]; then
    echo "  ok: HOST: languagesDict declared, recorded and read (${LANGS_DICT_USES} sites)"
else
    fail_case "HOST: languagesDict lifecycle incomplete (${LANGS_DICT_USES} sites, need declare+record+read)"
fi

# P7: the HandleInit state push carries the two new keys and the labels
# resolve through LANG_LABELS with the bare-token fallback.
HANDLE_INIT_BODY="$(region "${PROGRAM_CS}" 'private void HandleInit' 'private void HandleBrowseFolder')"
PUSH_LANGS="$(printf '%s\n' "${HANDLE_INIT_BODY}" | grep -cF 'languages = languageLabels')"
pin_eq "HOST: state push carries languages (token->label map)" 1 "${PUSH_LANGS}"

PUSH_SELECTION="$(printf '%s\n' "${HANDLE_INIT_BODY}" | grep -cF 'languagesSelection = languageSelection')"
pin_eq "HOST: state push carries languagesSelection (token->bool from [Languages])" 1 "${PUSH_SELECTION}"

LABELS_LOOKUP="$(count_f "${PROGRAM_CS}" 'LANG_LABELS.TryGetValue')"
pin_eq "HOST: labels resolve through LANG_LABELS lookup" 1 "${LABELS_LOOKUP}"

FALLBACK_SHAPE="$(count_f "${PROGRAM_CS}" '? label : langToken')"
pin_eq "HOST: bare-token fallback for unknown derived tokens (fail-open naming)" 1 "${FALLBACK_SHAPE}"

# P8 (38-02 T2): the void-all languages validator — a DISTINCT named
# function with a STRICTER element contract (exact vocabulary membership
# at fixed length 3, void-all on the first bad element).
if check_validator_pins "${PROGRAM_CS}"; then
    echo "  ok: HOST: GetLanguagesPayloadSelection void-all shapes complete"
else
    fail_case "HOST: GetLanguagesPayloadSelection void-all shapes incomplete"
fi

# P9: distinct-contract proof (obs #6574) — the upgrade validator carries
# zero languages coupling and keeps its own void-all shape.
UPG_BODY="$(cs_method "${PROGRAM_CS}" 'GetUpgradePayloadSelection[(]JsonElement payload, out bool payloadPresent[)]')"
UPG_LANG_LEAK="$(printf '%s\n' "${UPG_BODY}" | grep -ciF 'languages')"
pin_eq "HOST: GetUpgradePayloadSelection untouched (zero languages coupling)" 0 "${UPG_LANG_LEAK}"
UPG_VOID_RETURNS="$(printf '%s\n' "${UPG_BODY}" | grep -cF 'return new List<string>();')"
pin_eq "HOST: GetUpgradePayloadSelection keeps its two void-all returns" 2 "${UPG_VOID_RETURNS}"

# P10 (38-02 T2): the absent/present save branch — a save whose payload
# lacks languages reaches no write call (26a0073 carry-over).
if check_save_pins "${PROGRAM_CS}"; then
    echo "  ok: HOST: [Languages] absent/present save branch complete"
else
    fail_case "HOST: [Languages] absent/present save branch incomplete"
fi

# P11 (38-02 T2): the writer grammar — [Languages] header, glb=Enabled
# ALWAYS first, one Enabled/Disabled line per known catalog token.
WRITER_BODY="$(cs_method "${PROGRAM_CS}" 'WriteLanguagesSection[(]List<string> lines, List<string> selection, List<string> catalog[)]')"
if [ -z "${WRITER_BODY}" ]; then
    fail_case "HOST: WriteLanguagesSection body not extractable — writer pins would read vacuously"
fi
WRITER_APPEND_PATH="$(printf '%s\n' "${WRITER_BODY}" | grep -cF 'lines.Add("[Languages]")')"
pin_eq "HOST: writer appends a fresh [Languages] section when absent" 1 "${WRITER_APPEND_PATH}"
WRITER_GLB_FIRST="$(printf '%s\n' "${WRITER_BODY}" | grep -cF 'new List<string> { "glb=Enabled" }')"
pin_eq "HOST: writer serializes glb=Enabled ALWAYS (first key line)" 1 "${WRITER_GLB_FIRST}"
WRITER_STATES="$(printf '%s\n' "${WRITER_BODY}" | grep -cF 'Enabled" : "Disabled"')"
pin_eq "HOST: writer serializes Enabled/Disabled per known token" 1 "${WRITER_STATES}"
WRITER_INSITU="$(printf '%s\n' "${WRITER_BODY}" | grep -cF 'InsertRange(insertIdx, sectionBody)')"
pin_eq "HOST: writer rewrites the section in place (key-line splice after the header)" 1 "${WRITER_INSITU}"

# --- section d: CAN-FAIL controls ------------------------------------------
echo "--- section d: CAN-FAIL controls ---"

# Control 1 (parity bite): a scratch static/ whose ie11 family is missing
# one dotnet member must red the parity check...
BITE_DIR="${SANDBOX}/static-bite"
mkdir -p "${BITE_DIR}"
: > "${BITE_DIR}/StaticDownloadLinks-dotnet-ara.txt"
: > "${BITE_DIR}/StaticDownloadLinks-dotnet-chs.txt"
: > "${BITE_DIR}/StaticDownloadLinks-ie11-w62-x64-ara.txt"
if check_family_parity "${BITE_DIR}"; then
    fail_case "control 1 does not bite: the parity check accepts a family missing one member"
else
    echo "  control ok: the parity check reds a family missing one member"
fi

# ...and its conforming twin (both members present) must stay green —
# detection without over-blocking.
: > "${BITE_DIR}/StaticDownloadLinks-ie11-w62-x64-chs.txt"
if check_family_parity "${BITE_DIR}"; then
    echo "  control ok: the parity check passes the conforming twin fixture"
else
    fail_case "control 1 twin: the parity check rejects a conforming fixture"
fi

# Control 2 (pin bite): a Program.cs copy with the ENGINE_VOCAB declaration
# stripped must red the declaration pin. The mutation's landing is proven
# before the verdict is read (the copy stays non-trivial, the literal gone).
sed '/private static readonly string\[\] ENGINE_VOCAB/d' "${PROGRAM_CS}" > "${SANDBOX}/ProgramBite.cs"
if [ ! -s "${SANDBOX}/ProgramBite.cs" ]; then
    fail_case "control 2: the mutated copy is empty (instrument saw no population)"
elif check_vocab_decl "${SANDBOX}/ProgramBite.cs"; then
    fail_case "control 2 does not bite: the declaration pin accepts a stripped copy"
else
    echo "  control ok: the ENGINE_VOCAB declaration pin bites on a stripped copy"
fi

# Control 3 (void-all bite, 38-02 T2): a copy with the fixed-length check
# permissivized must red the validator pin set. The mutation's landing is
# proven before the verdict is read.
sed 's/value.Length != 3 ||/value.Length != 0 ||/' "${PROGRAM_CS}" > "${SANDBOX}/ProgramVoidBite.cs"
VOID_LANDED="$(count_f "${SANDBOX}/ProgramVoidBite.cs" 'Length != 0')"
VOID_OUT="$(check_validator_pins "${SANDBOX}/ProgramVoidBite.cs")"
VOID_RC=$?
if [ -s "${SANDBOX}/ProgramVoidBite.cs" ] && [ "${VOID_LANDED}" -ge 1 ] && [ "${VOID_RC}" -ne 0 ]; then
    echo "  control ok: the void-all pin set bites on a permissive length check"
else
    fail_case "control 3: void-all bite failed (landed=${VOID_LANDED}, rc=${VOID_RC})"
fi

# Control 4 (absent-branch bite, 38-02 T2): a copy whose languages write
# branch lost its property gate must red the save pin set (the 26a0073
# regression — a languages-less save reaching the writer).
sed 's/if (hasLegacy || hasLanguages)/if (hasLegacy)/' "${PROGRAM_CS}" > "${SANDBOX}/ProgramGateBite.cs"
GATE_LANDED="$(count_f "${SANDBOX}/ProgramGateBite.cs" 'if (hasLegacy || hasLanguages)')"
GATE_OUT="$(check_save_pins "${SANDBOX}/ProgramGateBite.cs")"
GATE_RC=$?
if [ -s "${SANDBOX}/ProgramGateBite.cs" ] && [ "${GATE_LANDED}" -eq 0 ] && [ "${GATE_RC}" -ne 0 ]; then
    echo "  control ok: the absent-branch pin set bites on an ungated write path"
else
    fail_case "control 4: absent-branch bite failed (landed-residue=${GATE_LANDED}, rc=${GATE_RC})"
fi

# --- verdict (the counter comparison is the final instruction) -------------
if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "LANGUAGE-CATALOG-PASS"
    exit 0
fi
echo "LANGUAGE-CATALOG-FAIL (${FAILED_CASES} failed case(s))"
exit 1
