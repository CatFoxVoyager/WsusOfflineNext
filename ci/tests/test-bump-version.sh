#!/usr/bin/env bash
# Fixture test for ci/bump-version.bash — run from repo root on a clean tree.
#
# Part 1 (sandbox, always runs): the library ci/lib-bump-version.bash is
# probed on synthetic files - occurrence counting (two occurrences on one
# line count 2), digit-boundary safety (2026.10.2 never matches inside
# 2026.10.20) and border preservation. These probes never touch the tree.
# Part 2 (real tree, clean tree only): the full bump must land exactly 22
# substitutions in exactly 14 files with the build tag intact (Phase 24
# plan 02 retarget removed the two AutoIt launcher twins; Phase 25 plan 01
# removed the generator GUI source from the matrix with its deletion;
# Phase 26 plan 03 removed the last au3 and added the native installer's
# .lpi VersionInfo block - one file out, one file in, so the matrix stays
# at 14 files / 22 sites, measured by the live bump run).
set -u
SANDBOX="$(mktemp -d)"
# shellcheck disable=SC1091  # sourced on purpose: the library under test
. ci/lib-bump-version.bash

# ---- probe 1: two occurrences on ONE line count 2 (pre-fix grep -c: 1) ----
# patterns are double-quoted exactly like the consumer: in single quotes the
# \$ reaches grep as a LITERAL dollar, not the end-of-line anchor
printf 'a2026.10.2-b2026.10.2-c' > "${SANDBOX}/two-occ.txt"
[ "$(count_occurrences "(^|[^0-9])2026\.10\.2([^0-9]|\$)" "${SANDBOX}/two-occ.txt")" -eq 2 ] \
    || { echo "FAIL: probe 1 — deux occurrences sur une ligne ne comptent pas 2"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 2: 2026.10.2 does NOT match inside 2026.10.20; file byte-identical ----
printf 'x2026.10.20' > "${SANDBOX}/collide.txt"
cp "${SANDBOX}/collide.txt" "${SANDBOX}/collide.orig"
[ "$(count_occurrences "(^|[^0-9])2026\.10\.2([^0-9]|\$)" "${SANDBOX}/collide.txt")" -eq 0 ] \
    || { echo "FAIL: probe 2 — 2026.10.2 matché à l'intérieur de 2026.10.20"; rm -rf "${SANDBOX}"; exit 1; }
substitute_bounded '2026\.10\.2' '9.9.9' "${SANDBOX}/collide.txt"
cmp -s "${SANDBOX}/collide.orig" "${SANDBOX}/collide.txt" \
    || { echo "FAIL: probe 2 — substitute_bounded a corrompu 2026.10.20 (pré-fix: x9.9.90)"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 3: bordering characters are preserved through the substitution ----
printf 'v2026.10.2.txt' > "${SANDBOX}/border.txt"
substitute_bounded '2026\.10\.2' '9.9.9' "${SANDBOX}/border.txt"
[ "$(cat "${SANDBOX}/border.txt")" = "v9.9.9.txt" ] \
    || { echo "FAIL: probe 3 — caractères de bord non préservés: $(cat "${SANDBOX}/border.txt")"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 4: start-of-line, end-of-line and both-borders all substitute ----
printf '2026.10.2a\nb2026.10.2\n2026.10.2\n' > "${SANDBOX}/edges.txt"
[ "$(count_occurrences "(^|[^0-9])2026\.10\.2([^0-9]|\$)" "${SANDBOX}/edges.txt")" -eq 3 ] \
    || { echo "FAIL: probe 4 — comptage début/fin de ligne incorrect"; rm -rf "${SANDBOX}"; exit 1; }
substitute_bounded '2026\.10\.2' '9.9.9' "${SANDBOX}/edges.txt"
printf '9.9.9a\nb9.9.9\n9.9.9\n' > "${SANDBOX}/edges.expected"
cmp -s "${SANDBOX}/edges.expected" "${SANDBOX}/edges.txt" \
    || { echo "FAIL: probe 4 — substitution début/fin de ligne incorrecte"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 5: classification conventional-commits (D-02) — MAJOR > MINOR > PATCH ----
[ "$(classify_next_version "$(printf 'feat(generator): add x\nfix: y')")" = "MINOR" ] \
    || { echo "FAIL: probe 5 — feat+fix doit classer MINOR"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(classify_next_version "$(printf 'fix(core): y\ndocs: z')")" = "PATCH" ] \
    || { echo "FAIL: probe 5 — fix+docs doit classer PATCH"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(classify_next_version "chore(release): bump")" = "PATCH" ] \
    || { echo "FAIL: probe 5 — chore doit classer PATCH"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(classify_next_version "feat!: drop w60")" = "MAJOR" ] \
    || { echo "FAIL: probe 5 — bang non scopé doit classer MAJOR"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(classify_next_version "fix(gui)!: rewrite")" = "MAJOR" ] \
    || { echo "FAIL: probe 5 — bang scopé doit classer MAJOR"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(classify_next_version "$(printf 'feat: api\n\nBREAKING CHANGE: removed option')")" = "MAJOR" ] \
    || { echo "FAIL: probe 5 — footer BREAKING CHANGE doit classer MAJOR"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(classify_next_version "")" = "PATCH" ] \
    || { echo "FAIL: probe 5 — log vide doit classer PATCH (train sans commit)"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 6: bump_core sur les trois classes ----
[ "$(bump_core "5.0.0" "PATCH")" = "5.0.1" ] \
    || { echo "FAIL: probe 6 — bump_core PATCH"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(bump_core "5.0.0" "MINOR")" = "5.1.0" ] \
    || { echo "FAIL: probe 6 — bump_core MINOR"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(bump_core "5.0.0" "MAJOR")" = "6.0.0" ] \
    || { echo "FAIL: probe 6 — bump_core MAJOR"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(bump_core "4.9.9" "MINOR")" = "4.10.0" ] \
    || { echo "FAIL: probe 6 — bump_core MINOR doit propager 9->10"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 7: strip_version_metadata ----
[ "$(strip_version_metadata "5.0.0+2026.11")" = "5.0.0" ] \
    || { echo "FAIL: probe 7 — strip full-form"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(strip_version_metadata "5.0.0")" = "5.0.0" ] \
    || { echo "FAIL: probe 7 — strip bare-core"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 8: next_full_version — branche CalVer legacy, classes, refus ----
[ "$(next_full_version "v2026.10.2" "2026.11" "")" = "5.0.0+2026.11" ] \
    || { echo "FAIL: probe 8 — tag CalVer legacy doit résoudre 5.0.0+month (D-01)"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(next_full_version "v5.0.0" "2026.12" "feat: x")" = "5.1.0+2026.12" ] \
    || { echo "FAIL: probe 8 — tag SemVer + feat doit résoudre MINOR+month"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(next_full_version "v5.1.0" "2026.12" "fix: y")" = "5.1.1+2026.12" ] \
    || { echo "FAIL: probe 8 — tag SemVer + fix doit résoudre PATCH+month"; rm -rf "${SANDBOX}"; exit 1; }
next_full_version "bogus" "2026.12" "" >/dev/null 2>&1
[ "$?" -ne 0 ] \
    || { echo "FAIL: probe 8 — tag bogus doit être refusé (exit non nul)"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 9: argv matrix is_valid_version_arg (accepte ET refuse) ----
is_valid_version_arg "5.0.0+2026.11" \
    || { echo "FAIL: probe 9 — 5.0.0+2026.11 doit être accepté"; rm -rf "${SANDBOX}"; exit 1; }
is_valid_version_arg "5.0.0" \
    || { echo "FAIL: probe 9 — 5.0.0 (cœur nu) doit être accepté"; rm -rf "${SANDBOX}"; exit 1; }
is_valid_version_arg "5.0.0+26.1" \
    && { echo "FAIL: probe 9 — année 2 chiffres doit être refusée"; rm -rf "${SANDBOX}"; exit 1; }
is_valid_version_arg "5.0.0+2026.11.0" \
    && { echo "FAIL: probe 9 — composant 4 doit être refusé"; rm -rf "${SANDBOX}"; exit 1; }
is_valid_version_arg "5.0.0+2026.1" \
    && { echo "FAIL: probe 9 — mois 1 chiffre doit être refusé"; rm -rf "${SANDBOX}"; exit 1; }
is_valid_version_arg "abc" \
    && { echo "FAIL: probe 9 — non-numérique doit être refusé"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 11: ancres numeriques .lpi (MajorVersionNr/MinorVersionNr/RevisionNr) ----
# Comptage par composant sur un .lpi synthetique; la substitution reecrit
# chaque champ depuis le coeur de destination, BuildNr jamais touche.
mkdir -p "${SANDBOX}/lpi"
printf '<VersionInfo>\n  <UseVersionInfo Value="True"/>\n  <MajorVersionNr Value="5"/>\n  <MinorVersionNr Value="2"/>\n  <RevisionNr Value="0"/>\n  <BuildNr Value="0"/>\n  <StringTable ProductVersion="5.2.0+2026.11"/>\n</VersionInfo>\n' > "${SANDBOX}/lpi/proj.lpi"
[ "$(count_numeric_anchored '5\.2\.0' "${SANDBOX}/lpi/proj.lpi")" -eq 3 ] \
    || { echo "FAIL: probe 11 - les 3 champs .lpi doivent compter 3"; rm -rf "${SANDBOX}"; exit 1; }
substitute_numeric_versions '5\.2\.0' '5.2.1' "${SANDBOX}/lpi/proj.lpi"
grep -q '<RevisionNr Value="1"/>' "${SANDBOX}/lpi/proj.lpi" \
    || { echo "FAIL: probe 11 - RevisionNr doit passer a 1"; rm -rf "${SANDBOX}"; exit 1; }
grep -q '<MajorVersionNr Value="5"/>' "${SANDBOX}/lpi/proj.lpi" \
    || { echo "FAIL: probe 11 - MajorVersionNr doit rester 5"; rm -rf "${SANDBOX}"; exit 1; }
grep -q '<BuildNr Value="0"/>' "${SANDBOX}/lpi/proj.lpi" \
    || { echo "FAIL: probe 11 - BuildNr ne doit jamais bouger"; rm -rf "${SANDBOX}"; exit 1; }
grep -q '<MinorVersionNr Value="2"/>' "${SANDBOX}/lpi/proj.lpi" \
    || { echo "FAIL: probe 11 - MinorVersionNr doit rester 2"; rm -rf "${SANDBOX}"; exit 1; }
[ "$(count_numeric_anchored '5\.2\.1' "${SANDBOX}/lpi/proj.lpi")" -eq 3 ] \
    || { echo "FAIL: probe 11 - recomptage apres bump doit rendre 3"; rm -rf "${SANDBOX}"; exit 1; }

# ---- probe 10: bornes du motif FULL-FORM, dans les deux sens ----
# Le motif borné d'une forme complète matche exactement une fois dans
# "v5.0.0+2026.11.txt" et ne matche PAS dans "5.0.0+2026.110" (voisin droit
# digit — refus structurel CISC-08, pas une absence accidentelle).
printf 'v5.0.0+2026.11.txt' > "${SANDBOX}/full-ok.txt"
[ "$(count_occurrences "(^|[^0-9])5\.0\.0\+2026\.11([^0-9]|\$)" "${SANDBOX}/full-ok.txt")" -eq 1 ] \
    || { echo "FAIL: probe 10 — la forme complète doit matcher exactement 1 fois"; rm -rf "${SANDBOX}"; exit 1; }
printf '5.0.0+2026.110' > "${SANDBOX}/full-collide.txt"
[ "$(count_occurrences "(^|[^0-9])5\.0\.0\+2026\.11([^0-9]|\$)" "${SANDBOX}/full-collide.txt")" -eq 0 ] \
    || { echo "FAIL: probe 10 — la forme complète a matché dans un mois plus long"; rm -rf "${SANDBOX}"; exit 1; }
# Le motif CORE est volontairement plus permissif : il compte le préfixe
# borné porté AU SEIN de la forme complète ("5.0.0" dans "5.0.0+2026.11" —
# le '+' est un non-digit). C'est la base de comptage before/after du moteur
# (22 sites des deux côtés) : disposition délibérée du hazard 1, épinglée
# côté arbre réel par les assertions 22/16/6 de la sonde ci-dessous.
[ "$(count_occurrences "(^|[^0-9])5\.0\.0([^0-9]|\$)" "${SANDBOX}/full-ok.txt")" -eq 1 ] \
    || { echo "FAIL: probe 10 — le motif CORE doit compter le préfixe de la forme complète"; rm -rf "${SANDBOX}"; exit 1; }
rm -rf "${SANDBOX}"

# Les blobs d'index portant du CR contre .gitattributes sont renormalisés :
# la procédure, la règle d'atomicité et les instruments EOL vivent dans
# WINDOWS.md (racine du dépôt). La classe documentée du dépôt reste
# (« blobs CRLF → diff --ignore-cr-at-eol ») : l'instrument du garde ignore
# les seules fins de ligne — une vraie édition de contenu reste détectée
# (contrôle positif mesuré : une édition réelle -> 1 fichier). Ne pas figer
# ici de comptage de blobs : état périmissable, le record vit dans le commit.
if [ -n "$(git diff --name-only --ignore-cr-at-eol)" ] || [ -n "$(git diff --cached --name-only)" ]; then
  echo "SKIP: arbre sale — revert d'abord"
  exit 2
fi
# Derivation format-agnostic (fonctionne avant ET après le train de
# migration) : OLD lu en forme complète, MONTH pris dans la metadata d'OLD
# si présente sinon le mois courant, NEW résolu par la lib — toujours porteur
# de metadata, forme que les gates after (16 pleines / 6 numériques / 22
# cœurs) savent valider. Les after-gates du moteur avortent sur un NEW nu :
# la dérivation arithmétique fixe d'origine (2026.10.2 -> 2026.10.3) est
# restée bloquée sous les nouvelles gates.
OLD="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]{4}\.[0-9]{2})?' cmd/DownloadUpdates.cmd | head -1 | cut -d'=' -f2)"
[ -n "${OLD}" ] || { echo "FAIL: version introuvable dans cmd/DownloadUpdates.cmd"; exit 1; }
MONTH="$(date -u +%Y.%m)"
case "${OLD}" in *+*) MONTH="${OLD#*+}" ;; esac
NEW="$(next_full_version "v$(strip_version_metadata "${OLD}")" "${MONTH}" "")"
[ -n "${NEW}" ] || { echo "FAIL: résolution de NEW impossible depuis ${OLD}"; exit 1; }
BT_BEFORE="$(grep -oE '\(b[0-9.]+\)' cmd/DownloadUpdates.cmd | head -1)"
bash ci/bump-version.bash "${NEW}" || { echo "FAIL: bump-version exited $?"; git checkout -- .; exit 1; }
STAT="$(git diff --stat --ignore-cr-at-eol | tail -1)"
echo "$STAT" | grep -q "14 files changed" || { echo "FAIL: attends 14 fichiers, obtenu: $STAT"; git checkout -- .; exit 1; }
# The 22-site total is asserted independently by the count_occurrences lanes
# below: git diff counts LINES, and a physical line can carry more than one
# substitution site (README's pair, the .lpi version block), so the site
# count never maps 1:1 onto diff insertions. The diff-level property of a
# pure substitution bump is symmetry - every changed line is a modification,
# never an addition or a removal.
INS="$(git diff --numstat --ignore-cr-at-eol | awk '{i += $1} END {print i + 0}')"
DEL="$(git diff --numstat --ignore-cr-at-eol | awk '{d += $2} END {print d + 0}')"
[ "${INS}" = "${DEL}" ] || { echo "FAIL: bump diff is not substitution-symmetric (${INS} insertions / ${DEL} deletions)"; git checkout -- .; exit 1; }
# Comptage de lanes sur l'arbre réel — les tripwire du moteur (22 cœurs /
# 15 full-form / 7 numériques, split 4 csproj + 3 champs .lpi) re-mesurés
# ici indépendamment via count_occurrences, jamais un grep -c brut. Le
# partitionnement 15/7 n'est PAS l'invariant (il dépend de la forme) : le
# TOTAL des sites à token de version = 22 l'est, dans les deux formes.
MATRIX="$(bash ci/bump-version.bash --print-files)"
[ "$(printf '%s\n' "${MATRIX}" | wc -l)" -eq 14 ] || { echo "FAIL: --print-files ne rend pas 14 chemins"; git checkout -- .; exit 1; }
new_esc="${NEW//./\\.}"; new_esc="${new_esc//+/\\+}"
new_core="${NEW%%+*}"; new_core_esc="${new_core//./\\.}"
IFS="." read -r NEW_MAJ NEW_MIN NEW_REV <<< "${new_core}"
full_after=0; num_csproj=0; num_lpi=0; core_after=0
for f in ${MATRIX}; do
  full_after=$(( full_after + $(count_occurrences "(^|[^0-9])${new_esc}([^0-9]|\$)" "${f}") ))
  core_after=$(( core_after + $(count_occurrences "(^|[^0-9])${new_core_esc}([^0-9]|\$)" "${f}") ))
  case "${f}" in
    *.csproj) num_csproj=$(( num_csproj + $(count_occurrences "${new_core_esc}\.0</(FileVersion|AssemblyVersion)>" "${f}") )) ;;
    *.lpi)
      num_lpi=$(( num_lpi + $(count_occurrences "<MajorVersionNr Value=\"${NEW_MAJ}\"" "${f}") ))
      num_lpi=$(( num_lpi + $(count_occurrences "<MinorVersionNr Value=\"${NEW_MIN}\"" "${f}") ))
      num_lpi=$(( num_lpi + $(count_occurrences "<RevisionNr Value=\"${NEW_REV}\"" "${f}") ))
      ;;
  esac
done
# Le motif core-littéral compte 19 sites (les 3 champs entiers .lpi ne
# portent jamais la sous-chaîne "X.Y.Z") : core == full + csproj, et le
# total des sites = core + .lpi = 22.
[ "${core_after}" -eq 19 ] || { echo "FAIL: attendu 19 sites au core littéral, obtenu ${core_after}"; git checkout -- .; exit 1; }
[ "${full_after}" -eq 15 ] || { echo "FAIL: attendu 15 sites full-form, obtenu ${full_after}"; git checkout -- .; exit 1; }
[ "${num_csproj}" -eq 4 ] || { echo "FAIL: attendu 4 ancres csproj, obtenu ${num_csproj}"; git checkout -- .; exit 1; }
[ "${num_lpi}" -eq 3 ] || { echo "FAIL: attendu 3 ancres .lpi, obtenu ${num_lpi}"; git checkout -- .; exit 1; }
[ "$(( core_after + num_lpi ))" -eq 22 ] \
    || { echo "FAIL: le total des sites core+.lpi doit faire 22"; git checkout -- .; exit 1; }
# The generator GUI and launcher sources were deleted in Phase 25 plan 01;
# the last au3 (installer) left in Phase 26 plan 03. The *.au3 include in
# the residue scan stays as zombie-defense: a tracked au3 carrying the old
# version must fail the scan.
grep -rnF "${OLD}" --include="*.au3" --include="*.json" --include="*.csproj" --include="*.tsx" . 2>/dev/null | grep -vE "node_modules|dist/|bin/|obj/|RELEASE_NOTES|docs/|\.superpowers|\.planning|\.playwright" | head -1 | grep -q . && { echo "FAIL: residu d'ancienne version ${OLD}"; git checkout -- .; exit 1; }
grep -q "${NEW}" cmd/DownloadUpdates.cmd || { echo "FAIL: nouvelle version absente du moteur"; git checkout -- .; exit 1; }
# Invariant capture/compare (le littéral figé pourrit à chaque changement de
# mois) : la capture du build tag doit être byte-identique avant/après.
BT_AFTER="$(grep -oE '\(b[0-9.]+\)' cmd/DownloadUpdates.cmd | head -1)"
[ "${BT_AFTER}" = "${BT_BEFORE}" ] || { echo "FAIL: le build tag a bougé (${BT_BEFORE} -> ${BT_AFTER})"; git checkout -- .; exit 1; }
grep -q "${NEW},release" static/SelfUpdateVersion-this.txt || { echo "FAIL: marqueur selfupdate non bumpé"; git checkout -- .; exit 1; }
git checkout -- .
[ -z "$(git diff --name-only --ignore-cr-at-eol)" ] || { echo "FAIL: revert incomplet"; exit 1; }
echo "PASS bump-version (14 fichiers, 22 substitutions, build tag intact, revert propre)"
