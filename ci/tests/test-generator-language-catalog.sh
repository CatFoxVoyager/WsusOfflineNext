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
#   e. UI-PINS      — App.tsx source-shape pins for the frontend half of the
#                     phase (plan 38-03): the nav entry id/placement, the
#                     pushed-catalog state consumption, the 24-row tab with
#                     the locked-active glb row, the fail-open note guard,
#                     and the conditional payload wiring (SC4 untouched-omit).
#                     Plan 38-02 sections a-d stay untouched; the battery
#                     grows additively per plan task (RED baseline 38-03 T1).
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
APP_TSX="${REPO_ROOT}/src-modern/generator/src/App.tsx"

FAILED_CASES=0
fail_case () {
    echo "FAIL: $1"
    FAILED_CASES=$((FAILED_CASES + 1))
    return 0
}

for f in "${STATIC_DIR}" "${ISO_CMD}" "${COPY_CMD}" "${ENGINE_CMD}" "${PROGRAM_CS}" "${APP_TSX}"; do
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

# tsx_tab: one tab's JSX block in App.tsx — from its `{activeTab === '<id>' && (`
# opening line (inclusive) to the NEXT tab block's opening line (exclusive).
# The any-char quote anchors tolerate the single-quote JSX idiom without
# ERE quote escapes; the next-tab stop keeps a sibling tab's markup (and its
# comments, which may carry sibling-contract words) out of the shape greps —
# the extractor-bound discipline of obs #6603, TSX side.
tsx_tab () { # <app-tsx-file> <tab-id> -> lines on stdout
    awk -v id="$2" '
        !inr && $0 ~ "\\{activeTab === ." id ". && \\(" { inr = 1; print; next }
        inr && $0 ~ "\\{activeTab === " { exit }
        inr { print }
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

# check_sc4_pins: the byte-frozen glb invocation literals (38-02 T3,
# parameterized for the can-fail control). These are the SC4 contract -
# the three glb argument strings must stay byte-identical. Return status
# = fail count.
check_sc4_pins () { # <program-cs-file> -> status (fail count)
    local fails=0 f="$1" n
    n="$(count_f "${f}" 'w100-x64 glb {job.Switches}{upgradeSwitchesX64}')"
    [ "${n}" -eq 1 ] || { echo "    sc4: w100-x64 glb literal x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" 'w100 glb {job.Switches}{upgradeSwitchesX86}')"
    [ "${n}" -eq 1 ] || { echo "    sc4: w100 glb literal x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" '{legTarget} glb {job.Switches}')"
    [ "${n}" -eq 1 ] || { echo "    sc4: legacy glb literal x${n}, want 1"; fails=$((fails + 1)); }
    return "${fails}"
}

# check_composition_pins: the per-language loop + the DEC-36-06 firewall
# (38-02 T3, parameterized for the can-fail control). Non-glb passes
# carry job.Switches ONLY - never the upgrade switches, never the 5th
# upgrade-language argument. Return status = fail count.
check_composition_pins () { # <program-cs-file> -> status (fail count)
    local fails=0 f="$1" loop n
    loop="$(region "${f}" 'foreach [(]string lang in selectedLanguages[)]' '// 2. Download Office C2R')"
    if [ -z "${loop}" ]; then
        echo "    composition: loop region not extractable"
        return 1
    fi
    n="$(printf '%s\n' "${loop}" | grep -cF 'w100-x64 {lang} {job.Switches}')"
    [ "${n}" -eq 1 ] || { echo "    composition: w100-x64 per-language call x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF 'w100 {lang} {job.Switches}')"
    [ "${n}" -eq 1 ] || { echo "    composition: w100 per-language call x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF '{legTarget} {lang} {job.Switches}')"
    [ "${n}" -eq 1 ] || { echo "    composition: legacy per-language call x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF 'upgradeSwitches')"
    [ "${n}" -eq 0 ] || { echo "    composition: firewall - upgrade switches in a non-glb pass x${n}, want 0"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF 'upgradeLangValue')"
    [ "${n}" -eq 0 ] || { echo "    composition: firewall - upgrade-language carriage x${n}, want 0"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF 'WOU_UPGRADE_LANG')"
    [ "${n}" -eq 0 ] || { echo "    composition: firewall - env carriage name x${n}, want 0"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF ', cmdDir, ct, ')"
    [ "${n}" -eq 0 ] || { echo "    composition: firewall - 5-argument call form x${n}, want 0"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${loop}" | grep -cF ', cmdDir, ct);')"
    [ "${n}" -eq 3 ] || { echo "    composition: 4-argument call forms x${n}, want 3"; fails=$((fails + 1)); }
    return "${fails}"
}

# check_nav_pins: the languages nav entry pin set (38-03 T1, parameterized
# for the can-fail control) — the entry exists exactly once with the
# Languages glyph, the activeTab union carries the member, and the entry
# sits BETWEEN the legacy and upgrades entries (line-index comparisons,
# never line-number pins). Return status = fail count.
check_nav_pins () { # <app-tsx-file> -> status (fail count)
    local fails=0 f="$1" n l1 l2 l3
    n="$(count_f "${f}" "{ id: 'languages', label: 'Languages', icon: Languages, count: languagesCount }")"
    [ "${n}" -eq 1 ] || { echo "    nav: languages entry x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" "'legacy' | 'languages' | 'upgrades'")"
    [ "${n}" -eq 1 ] || { echo "    nav: activeTab union member x${n}, want 1"; fails=$((fails + 1)); }
    l1="$(grep -nF "{ id: 'legacy', label: 'Legacy Windows'" "${f}" | head -n1 | cut -d: -f1)"
    l2="$(grep -nF "{ id: 'languages', label: 'Languages'" "${f}" | head -n1 | cut -d: -f1)"
    l3="$(grep -nF "{ id: 'upgrades', label: 'OS Upgrades'" "${f}" | head -n1 | cut -d: -f1)"
    if [ -z "${l1}" ] || [ -z "${l2}" ] || [ -z "${l3}" ] || [ "${l2}" -le "${l1}" ] || [ "${l2}" -ge "${l3}" ]; then
        echo "    nav: placement broken (legacy=${l1} languages=${l2} upgrades=${l3})"
        fails=$((fails + 1))
    fi
    return "${fails}"
}

# check_copy_pins: the verbatim UI copy pin set (38-03 T2, parameterized
# for the can-fail control) — panel heading, sub-copy, and the fail-open
# note pair, byte-exact per the approved surface contract. Return status
# = fail count.
check_copy_pins () { # <app-tsx-file> -> status (fail count)
    local fails=0 f="$1" n
    n="$(count_f "${f}" '>Update languages<')"
    [ "${n}" -eq 1 ] || { echo "    copy: panel heading x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" 'Choose the languages this medium carries in addition to English (global). Each selected language adds its language-specific packages — .NET language packs, plus IE11 language packs when Server 2012 is among the targets.')"
    [ "${n}" -eq 1 ] || { echo "    copy: panel sub-copy x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" 'Additional languages unavailable')"
    [ "${n}" -eq 1 ] || { echo "    copy: fail-open note heading x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" 'Only English (global) is available right now, so the medium will carry global updates only — the same content as a default run. Restart the generator to reload the language list.')"
    [ "${n}" -eq 1 ] || { echo "    copy: fail-open note body x${n}, want 1"; fails=$((fails + 1)); }
    return "${fails}"
}

# check_guard_pins: the init-resolution guard + toolbar scoping pins
# (38-03 T2, parameterized) — the fail-open note renders only after the
# first state message and only on an empty catalog, on the calm zinc info
# idiom (never amber/rose), with the toolbar buttons hidden alongside.
# Return status = fail count.
check_guard_pins () { # <app-tsx-file> -> status (fail count)
    local fails=0 f="$1" n tab_region
    n="$(count_f "${f}" 'const [catalogResolved, setCatalogResolved] = useState(false);')"
    [ "${n}" -eq 1 ] || { echo "    guard: resolved flag declaration x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" 'setCatalogResolved(true);')"
    [ "${n}" -eq 1 ] || { echo "    guard: resolved set on the state message x${n}, want 1"; fails=$((fails + 1)); }
    n="$(count_f "${f}" 'catalogResolved && Object.keys(languages).length === 0')"
    [ "${n}" -eq 1 ] || { echo "    guard: note gated on init resolution + empty catalog x${n}, want 1"; fails=$((fails + 1)); }
    tab_region="$(tsx_tab "${f}" 'languages')"
    if [ -z "${tab_region}" ]; then
        echo "    guard: tab region not extractable"
        return 1
    fi
    n="$(printf '%s\n' "${tab_region}" | grep -cF 'p-4 rounded-lg bg-dark-900 border border-dark-800')"
    [ "${n}" -eq 1 ] || { echo "    guard: note on the calm zinc info panel idiom x${n}, want 1"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${tab_region}" | grep -cE 'amber|rose')"
    [ "${n}" -eq 0 ] || { echo "    guard: note is never amber/rose x${n}, want 0"; fails=$((fails + 1)); }
    n="$(printf '%s\n' "${tab_region}" | grep -cF '{Object.keys(languages).length > 0 && (')"
    [ "${n}" -eq 1 ] || { echo "    guard: toolbar buttons hidden on an empty catalog x${n}, want 1"; fails=$((fails + 1)); }
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

# P12 (38-02 T3): the byte-frozen SC4 glb invocation literals.
if check_sc4_pins "${PROGRAM_CS}"; then
    echo "  ok: HOST: SC4 glb invocation literals byte-frozen"
else
    fail_case "HOST: SC4 glb invocation literals drifted"
fi

# P13 (38-02 T3): the per-language composition loop + the DEC-36-06
# firewall (non-glb passes carry job.Switches ONLY).
if check_composition_pins "${PROGRAM_CS}"; then
    echo "  ok: HOST: per-language composition + DEC-36-06 firewall complete"
else
    fail_case "HOST: per-language composition + DEC-36-06 firewall incomplete"
fi

# P14 (38-02 T3): extraction site - the validated selection is filtered
# and sorted ascending before the composition.
EXTRACT_GLB_FILTER="$(count_f "${PROGRAM_CS}" 'selectedLanguages.RemoveAll(lang => lang == "glb")')"
pin_eq "HOST: glb filtered defensively out of the selection" 1 "${EXTRACT_GLB_FILTER}"
EXTRACT_SORT="$(count_f "${PROGRAM_CS}" 'selectedLanguages.Sort(StringComparer.Ordinal)')"
pin_eq "HOST: selection sorted ascending (Ordinal) before composition" 1 "${EXTRACT_SORT}"

# P15 (38-02 T3): spawn order - all three glb lines precede the
# per-language loop (line-index assertion, never a line-number pin).
GLB64_LINE="$(grep -nF 'w100-x64 glb {job.Switches}{upgradeSwitchesX64}' "${PROGRAM_CS}" | head -n1 | cut -d: -f1)"
GLBX86_LINE="$(grep -nF 'w100 glb {job.Switches}{upgradeSwitchesX86}' "${PROGRAM_CS}" | head -n1 | cut -d: -f1)"
GLBLEG_LINE="$(grep -nF '{legTarget} glb {job.Switches}' "${PROGRAM_CS}" | head -n1 | cut -d: -f1)"
LOOP_LINE="$(grep -nF 'foreach (string lang in selectedLanguages)' "${PROGRAM_CS}" | head -n1 | cut -d: -f1)"
ORDER_OK=1
for glb_line in "${GLB64_LINE}" "${GLBX86_LINE}" "${GLBLEG_LINE}"; do
    if [ -z "${glb_line}" ] || [ -z "${LOOP_LINE}" ] || [ "${LOOP_LINE}" -le "${glb_line}" ]; then
        ORDER_OK=0
    fi
done
if [ "${ORDER_OK}" -eq 1 ]; then
    echo "  ok: HOST: spawn order — all three glb lines precede the per-language loop (glb64=${GLB64_LINE} glbx86=${GLBX86_LINE} glbleg=${GLBLEG_LINE} loop=${LOOP_LINE})"
else
    fail_case "HOST: spawn order broken (glb64=${GLB64_LINE} glbx86=${GLBX86_LINE} glbleg=${GLBLEG_LINE} loop=${LOOP_LINE})"
fi

# --- section e: UI-PINS (38-03, App.tsx source shapes) ----------------------
echo "--- section e: UI-PINS (App.tsx source shapes) ---"

# U1 (38-03 T1): the nav entry pin set — id, icon, badge count, placement.
if check_nav_pins "${APP_TSX}"; then
    echo "  ok: UI: languages nav entry complete (id, union member, placement)"
else
    fail_case "UI: languages nav entry incomplete or misplaced"
fi

# U2: the Languages glyph joins the lucide-react import block.
IMPORT_REGION="$(region "${APP_TSX}" '^import [{]' 'from .lucide-react.')"
IMPORT_LANGS="$(printf '%s\n' "${IMPORT_REGION}" | grep -cF 'Languages')"
if [ -z "${IMPORT_REGION}" ]; then
    fail_case "UI: lucide-react import region not extractable — import pin vacuous"
else
    pin_eq "UI: Languages glyph imported from lucide-react" 1 "${IMPORT_LANGS}"
fi

# U3: the pushed-catalog state records + tolerant merge consumption
# (absent push keys never crash — the spread-merge reads only when the key
# is present, mirroring the sibling picker's consumption shape).
STATE_CATALOG="$(count_f "${APP_TSX}" 'const [languages, setLanguages] = useState<Record<string, string>>({});')"
pin_eq "UI: pushed catalog state record declared once" 1 "${STATE_CATALOG}"
STATE_SELECTION="$(count_f "${APP_TSX}" 'const [languagesSelection, setLanguagesSelection] = useState<Record<string, boolean>>({});')"
pin_eq "UI: pushed selection state record declared once" 1 "${STATE_SELECTION}"
MERGE_CATALOG="$(count_f "${APP_TSX}" 'setLanguages(prev => ({ ...prev, ...data.languages }));')"
pin_eq "UI: catalog consumed via the tolerant spread-merge" 1 "${MERGE_CATALOG}"
MERGE_SELECTION="$(count_f "${APP_TSX}" 'setLanguagesSelection(prev => ({ ...prev, ...data.languagesSelection }));')"
pin_eq "UI: selection consumed via the tolerant spread-merge" 1 "${MERGE_SELECTION}"

# U4: the derivations are the single source of truth (badge count and
# payload both read the same sorted, glb-free selection).
DERIVE_SEL="$(count_f "${APP_TSX}" 'const selectedLangs = Object.keys(languagesSelection)')"
pin_eq "UI: selectedLangs derives from the pushed selection record" 1 "${DERIVE_SEL}"
SEL_GLB_FILTER="$(count_f "${APP_TSX}" "filter(t => t !== 'glb' && languagesSelection[t])")"
pin_eq "UI: selectedLangs filters the pinned token out (badge and payload are non-glb)" 1 "${SEL_GLB_FILTER}"
SEL_REGION="$(region "${APP_TSX}" 'const selectedLangs' 'const languagesCount')"
if [ -z "${SEL_REGION}" ]; then
    fail_case "UI: selection derivation region not extractable — sort pin vacuous"
else
    SEL_SORT="$(printf '%s\n' "${SEL_REGION}" | grep -cF '.sort()')"
    pin_eq "UI: selectedLangs sorted ascending (JS lexicographic == Ordinal over 3-letter ASCII tokens)" 1 "${SEL_SORT}"
fi
DERIVE_COUNT="$(count_f "${APP_TSX}" 'const languagesCount = selectedLangs.length')"
pin_eq "UI: nav badge count derives from selectedLangs" 1 "${DERIVE_COUNT}"

# U5: the tab region exists and carries the Win11 row anatomy — a missing
# region makes every region-scoped pin below vacuous, so the emptiness is
# a loud instrument condition, never a green.
TAB_REGION="$(tsx_tab "${APP_TSX}" 'languages')"
if [ -z "${TAB_REGION}" ]; then
    fail_case "UI: languages tab region not extractable — region pins would read vacuously"
    TAB_REGION="(unextractable)"
fi
ROW_TOGGLE="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'onClick={() => toggleLanguage(token)}')"
pin_eq "UI: selectable rows toggle through the row-level handler" 1 "${ROW_TOGGLE}"
ROW_ANATOMY="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'px-4 py-2.5 hover:bg-dark-850/70 transition-colors cursor-pointer')"
pin_eq "UI: selectable rows copy the Win11 row anatomy (hover + cursor-pointer)" 1 "${ROW_ANATOMY}"
POINTER_NONE="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'pointer-events-none')"
pin_eq "UI: checkboxes are pointer-events-none (the row owns the toggle)" 2 "${POINTER_NONE}"

# U6: the locked-active glb row — permanently selected, never
# disabled-unavailable (the explicit inverse of the sibling not-available
# row): full-strength label, accent tint, checked+disabled checkbox with
# the pinned accessible name, emerald status badge, NO hover, NO row
# toggle handler (only the toolbar buttons and the selectable-row
# template carry onClick in this region).
TAB_GLB_ARIA="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'aria-label="English (global) — always included"')"
pin_eq "UI: glb row locked-active aria-label" 1 "${TAB_GLB_ARIA}"
TAB_GLB_BADGE="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'Always included')"
pin_eq "UI: glb row carries the emerald included badge" 1 "${TAB_GLB_BADGE}"
TAB_GLB_EMERALD="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20')"
pin_eq "UI: the included badge reuses the Listed badge shape byte-for-byte" 1 "${TAB_GLB_EMERALD}"
TAB_GLB_CHECKED="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'checked disabled')"
pin_eq "UI: glb checkbox is checked + disabled with the accent idiom retained" 1 "${TAB_GLB_CHECKED}"
TAB_TINT="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'bg-accent-600/5')"
pin_eq "UI: accent tint on the glb row and the checked-row template" 2 "${TAB_TINT}"
TAB_ROW_HOVER="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'hover:bg-dark-850/70')"
pin_eq "UI: the row-hover idiom appears only on selectable rows (glb never hovers)" 1 "${TAB_ROW_HOVER}"
TAB_ONCLICK="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'onClick={')"
pin_eq "UI: onClick sites in the tab (select-all + clear + row toggle; glb has none)" 3 "${TAB_ONCLICK}"

# U7: table columns per the surface contract — header is w-8 empty,
# flex-1 Language, w-36 Status; token chips reuse the mono chip idiom.
TAB_HEADER_LANG="$(printf '%s\n' "${TAB_REGION}" | grep -cF '<div className="flex-1">Language</div>')"
pin_eq "UI: table header Language column" 1 "${TAB_HEADER_LANG}"
TAB_HEADER_STATUS="$(printf '%s\n' "${TAB_REGION}" | grep -cF '<div className="w-36 text-center">Status</div>')"
pin_eq "UI: table header Status column" 1 "${TAB_HEADER_STATUS}"
TAB_CHIP="$(printf '%s\n' "${TAB_REGION}" | grep -cF 'text-[10px] font-mono px-1.5 py-0.5 rounded bg-dark-800 text-zinc-300 border border-dark-700')"
pin_eq "UI: mono token chips reuse the row-chip idiom (glb + template)" 2 "${TAB_CHIP}"

# U8: the interactions — the row toggle handler and the scoped
# select-all/clear pair iterate the catalog keys only (the pinned token is
# not a catalog member by host construction, so it is never touched).
HANDLER_TOGGLE="$(count_f "${APP_TSX}" 'const toggleLanguage = (token: string)')"
pin_eq "UI: row toggle handler declared once" 1 "${HANDLER_TOGGLE}"
HANDLER_ALL="$(count_f "${APP_TSX}" 'const selectAllLanguages = ()')"
pin_eq "UI: select-all handler declared once" 1 "${HANDLER_ALL}"
HANDLER_CLEAR="$(count_f "${APP_TSX}" 'const clearLanguageSelection = ()')"
pin_eq "UI: clear handler declared once" 1 "${HANDLER_CLEAR}"
HANDLERS_REGION="$(region "${APP_TSX}" 'const toggleLanguage =' 'const handleStart =')"
if [ -z "${HANDLERS_REGION}" ]; then
    fail_case "UI: language handlers region not extractable — scoping pins vacuous"
    HANDLERS_REGION="(unextractable)"
fi
SCOPE_FOREACH="$(printf '%s\n' "${HANDLERS_REGION}" | grep -cF 'Object.keys(languages).forEach')"
pin_eq "UI: select-all/clear scope the catalog keys" 2 "${SCOPE_FOREACH}"
SCOPE_GLB="$(printf '%s\n' "${HANDLERS_REGION}" | grep -ciF 'glb')"
pin_eq "UI: the interactions never reference the pinned token (not a catalog member)" 0 "${SCOPE_GLB}"

# U9 (38-03 T2): the verbatim copy set — panel heading, sub-copy, and the
# fail-open note pair, byte-exact per the approved contract.
if check_copy_pins "${APP_TSX}"; then
    echo "  ok: UI: verbatim copy set complete (heading, sub-copy, note pair)"
else
    fail_case "UI: verbatim copy set drifted from the approved contract"
fi

# U10 (38-03 T2): the init-resolution guard + toolbar scoping + calm-panel
# color discipline.
if check_guard_pins "${APP_TSX}"; then
    echo "  ok: UI: catalog guard, toolbar scoping and panel colors complete"
else
    fail_case "UI: catalog guard / toolbar scoping / panel colors incomplete"
fi

# U11 (38-03 T2): fail-open naming — a label the push leaves empty falls
# back to the bare token; labels come from the pushed catalog by
# construction, never from a frontend-side hardcoded map.
FALLBACK_TOKEN="$(printf '%s\n' "${TAB_REGION}" | grep -cF '{label || token}')"
pin_eq "UI: bare-token fallback for a missing pushed label" 1 "${FALLBACK_TOKEN}"
HARDCODED_ZH="$(count_f "${APP_TSX}" 'Chinese (traditional)')"
pin_eq "UI: no frontend-side display-name entry (Chinese (traditional))" 0 "${HARDCODED_ZH}"
HARDCODED_PT="$(count_f "${APP_TSX}" 'Portuguese (Brazil)')"
pin_eq "UI: no frontend-side display-name entry (Portuguese (Brazil))" 0 "${HARDCODED_PT}"
HARDCODED_HU="$(count_f "${APP_TSX}" 'Hungarian')"
pin_eq "UI: no frontend-side display-name entry (Hungarian)" 0 "${HARDCODED_HU}"

# U12 (38-03 T2, DEC-36-06 firewall, frontend side): the languages tab
# region and its interactions carry zero references to the sibling
# upgrade-language axis — adjacent axes, never merged.
TAB_UPGLANG_LEAK="$(printf '%s\n' "${TAB_REGION}" | grep -ciF 'upgradelang')"
pin_eq "UI: languages tab region carries zero upgrade-language references" 0 "${TAB_UPGLANG_LEAK}"
TAB_UPTOUCHED_LEAK="$(printf '%s\n' "${TAB_REGION}" | grep -ciF 'upgradetouched')"
pin_eq "UI: languages tab region carries zero sibling touched-flag references" 0 "${TAB_UPTOUCHED_LEAK}"
TAB_UPSEL_LEAK="$(printf '%s\n' "${TAB_REGION}" | grep -ciF 'upgradeselection')"
pin_eq "UI: languages tab region carries zero sibling selection references" 0 "${TAB_UPSEL_LEAK}"
HDL_UPGLANG_LEAK="$(printf '%s\n' "${HANDLERS_REGION}" | grep -ciF 'upgrade')"
pin_eq "UI: language interactions carry zero sibling-axis references" 0 "${HDL_UPGLANG_LEAK}"

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

# Control 5 (SC4 bite, 38-02 T3): a copy with one glb literal degraded
# (upgrade switches stripped) must red the SC4 pin set.
sed 's/w100-x64 glb {job.Switches}{upgradeSwitchesX64}/w100-x64 glb {job.Switches}/' "${PROGRAM_CS}" > "${SANDBOX}/ProgramSc4Bite.cs"
SC4_RESIDUE="$(count_f "${SANDBOX}/ProgramSc4Bite.cs" '{job.Switches}{upgradeSwitchesX64}')"
SC4_OUT="$(check_sc4_pins "${SANDBOX}/ProgramSc4Bite.cs")"
SC4_RC=$?
if [ -s "${SANDBOX}/ProgramSc4Bite.cs" ] && [ "${SC4_RESIDUE}" -eq 0 ] && [ "${SC4_RC}" -ne 0 ]; then
    echo "  control ok: the SC4 pin set bites on one degraded glb literal"
else
    fail_case "control 5: SC4 bite failed (residue=${SC4_RESIDUE}, rc=${SC4_RC})"
fi

# Control 6 (firewall bite, 38-02 T3): a copy where one per-language pass
# regains the 5th upgrade-language argument must red the firewall pins.
sed 's/w100-x64 {lang} {job.Switches}".Trim(), cmdDir, ct);/w100-x64 {lang} {job.Switches}".Trim(), cmdDir, ct, upgradeLangValue);/' "${PROGRAM_CS}" > "${SANDBOX}/ProgramFwBite.cs"
FW_LANDED="$(count_f "${SANDBOX}/ProgramFwBite.cs" 'ct, upgradeLangValue);')"
FW_OUT="$(check_composition_pins "${SANDBOX}/ProgramFwBite.cs")"
FW_RC=$?
if [ -s "${SANDBOX}/ProgramFwBite.cs" ] && [ "${FW_LANDED}" -ge 1 ] && [ "${FW_RC}" -ne 0 ]; then
    echo "  control ok: the firewall pins bite on a 5-argument per-language pass"
else
    fail_case "control 6: firewall bite failed (landed=${FW_LANDED}, rc=${FW_RC})"
fi

# Control 7 (nav placement bite, 38-03 T1): a scratch App.tsx copy whose
# languages nav entry carries a mutated tab id must red the nav pin set
# (count AND placement) — the mutation REMOVES the asserted literal from
# its pinned form (obs #6590: the bite deletes the pinned shape, it never
# comments it). The landing is proven before the verdict is read.
sed "s/{ id: 'languages', label: 'Languages', icon: Languages/{ id: 'languagez', label: 'Languages', icon: Languages/" "${APP_TSX}" > "${SANDBOX}/AppNavBite.tsx"
NAV_RESIDUE="$(count_f "${SANDBOX}/AppNavBite.tsx" "{ id: 'languages', label: 'Languages'")"
NAV_OUT="$(check_nav_pins "${SANDBOX}/AppNavBite.tsx")"
NAV_RC=$?
if [ -s "${SANDBOX}/AppNavBite.tsx" ] && [ "${NAV_RESIDUE}" -eq 0 ] && [ "${NAV_RC}" -ne 0 ]; then
    echo "  control ok: the nav pins bite on a mutated tab id"
else
    fail_case "control 7: nav placement bite failed (residue=${NAV_RESIDUE}, rc=${NAV_RC})"
fi

# Control 8 (copy bite, 38-03 T2): a scratch App.tsx copy with one verbatim
# UI literal REPLACED must red the copy pin set. The mutation removes the
# pinned phrase entirely — an appended suffix would leave it intact as a
# substring and no-op the bite (obs #6590); the landing is proven before
# the verdict is read.
sed 's/Additional languages unavailable/Language list unavailable/' "${APP_TSX}" > "${SANDBOX}/AppCopyBite.tsx"
COPY_RESIDUE="$(count_f "${SANDBOX}/AppCopyBite.tsx" 'Additional languages unavailable')"
COPY_OUT="$(check_copy_pins "${SANDBOX}/AppCopyBite.tsx")"
COPY_RC=$?
if [ -s "${SANDBOX}/AppCopyBite.tsx" ] && [ "${COPY_RESIDUE}" -eq 0 ] && [ "${COPY_RC}" -ne 0 ]; then
    echo "  control ok: the copy pins bite on one altered verbatim literal"
else
    fail_case "control 8: copy bite failed (residue=${COPY_RESIDUE}, rc=${COPY_RC})"
fi

# Control 9 (guard bite, 38-03 T2): a scratch copy whose fail-open note
# lost the init-resolution gate must red the guard pin set (the
# startup-flash regression — an unavailable flash during normal init).
sed 's/catalogResolved && Object.keys(languages).length === 0/Object.keys(languages).length === 0/' "${APP_TSX}" > "${SANDBOX}/AppGuardBite.tsx"
GUARD_RESIDUE="$(count_f "${SANDBOX}/AppGuardBite.tsx" 'catalogResolved && Object.keys(languages).length === 0')"
GUARD_OUT="$(check_guard_pins "${SANDBOX}/AppGuardBite.tsx")"
GUARD_RC=$?
if [ -s "${SANDBOX}/AppGuardBite.tsx" ] && [ "${GUARD_RESIDUE}" -eq 0 ] && [ "${GUARD_RC}" -ne 0 ]; then
    echo "  control ok: the guard pins bite on an ungated fail-open note"
else
    fail_case "control 9: guard bite failed (residue=${GUARD_RESIDUE}, rc=${GUARD_RC})"
fi

# --- verdict (the counter comparison is the final instruction) -------------
if [ "${FAILED_CASES}" -eq 0 ]; then
    echo "LANGUAGE-CATALOG-PASS"
    exit 0
fi
echo "LANGUAGE-CATALOG-FAIL (${FAILED_CASES} failed case(s))"
exit 1
