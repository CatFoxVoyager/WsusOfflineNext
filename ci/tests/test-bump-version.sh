#!/usr/bin/env bash
# Fixture test for ci/bump-version.bash — run from repo root on a clean tree.
#
# Part 1 (sandbox, always runs): the library ci/lib-bump-version.bash is
# probed on synthetic files - occurrence counting (two occurrences on one
# line count 2), digit-boundary safety (2026.10.2 never matches inside
# 2026.10.20) and border preservation. These probes never touch the tree.
# Part 2 (real tree, clean tree only): the full bump must land exactly 32
# substitutions in exactly 17 files with the build tag intact.
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
# de metadata, forme que les gates after (20 pleines / 12 numériques / 32
# cœurs) savent valider. Les after-gates du moteur avortent sur un NEW nu :
# la dérivation arithmétique fixe d'origine (2026.10.2 -> 2026.10.3) est
# restée bloquée sous les nouvelles gates.
OLD="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+(\+[0-9]{4}\.[0-9]{2})?' cmd/DownloadUpdates.cmd | head -1 | cut -d'=' -f2)"
[ -n "${OLD}" ] || { echo "FAIL: version introuvable dans cmd/DownloadUpdates.cmd"; exit 1; }
MONTH="$(date -u +%Y.%m)"
case "${OLD}" in *+*) MONTH="${OLD#*+}" ;; esac
NEW="$(next_full_version "v$(strip_version_metadata "${OLD}")" "${MONTH}" "")"
[ -n "${NEW}" ] || { echo "FAIL: résolution de NEW impossible depuis ${OLD}"; exit 1; }
bash ci/bump-version.bash "${NEW}" || { echo "FAIL: bump-version exited $?"; git checkout -- .; exit 1; }
STAT="$(git diff --stat --ignore-cr-at-eol | tail -1)"
echo "$STAT" | grep -q "17 files changed" || { echo "FAIL: attends 17 fichiers, obtenu: $STAT"; git checkout -- .; exit 1; }
echo "$STAT" | grep -q "32 insertions" || { echo "FAIL: attends 32 substitutions, obtenu: $STAT"; git checkout -- .; exit 1; }
grep -rnF "${OLD}" --include="*.au3" --include="*.json" --include="*.csproj" --include="*.tsx" . 2>/dev/null | grep -vE "node_modules|dist/|bin/|obj/|RELEASE_NOTES|docs/|\.superpowers|\.planning|\.playwright" | head -1 | grep -q . && { echo "FAIL: residu d'ancienne version ${OLD}"; git checkout -- .; exit 1; }
grep -q "${NEW}" cmd/DownloadUpdates.cmd || { echo "FAIL: nouvelle version absente du moteur"; git checkout -- .; exit 1; }
grep -q "(b2026.10)" cmd/DownloadUpdates.cmd || { echo "FAIL: le build tag b2026.10 ne doit pas bouger"; git checkout -- .; exit 1; }
grep -q "${NEW},release" static/SelfUpdateVersion-this.txt || { echo "FAIL: marqueur selfupdate non bumpé"; git checkout -- .; exit 1; }
git checkout -- .
[ -z "$(git diff --name-only --ignore-cr-at-eol)" ] || { echo "FAIL: revert incomplet"; exit 1; }
echo "PASS bump-version (17 fichiers, 32 substitutions, build tag intact, revert propre)"
