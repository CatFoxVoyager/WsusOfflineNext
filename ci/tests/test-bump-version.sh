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
rm -rf "${SANDBOX}"

# L'arbre stocke des blobs CRLF contre .gitattributes text=eol=crlf (blobs non
# renormalisés — un checkout frais est donc PERMANEMENT « sale » pour
# git status/git diff : ~337 fichiers M, 222 fichiers dans diff --stat, alors
# que le contenu est identique au blob). C'est la classe documentée du dépôt
# (« blobs CRLF → diff --ignore-cr-at-eol ») : l'instrument du garde ignore les
# seules fins de ligne — une vraie édition de contenu reste détectée (contrôle
# positif mesuré : une édition réelle -> 1 fichier).
if [ -n "$(git diff --name-only --ignore-cr-at-eol)" ] || [ -n "$(git diff --cached --name-only)" ]; then
  echo "SKIP: arbre sale — revert d'abord"
  exit 2
fi
OLD="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+' cmd/DownloadUpdates.cmd | head -1 | cut -d'=' -f2)"
[ -n "${OLD}" ] || { echo "FAIL: version introuvable dans cmd/DownloadUpdates.cmd"; exit 1; }
NEW="${OLD%.*}.$(( ${OLD##*.} + 1 ))"
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
