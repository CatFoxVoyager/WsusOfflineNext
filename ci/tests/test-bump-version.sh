#!/usr/bin/env bash
# Fixture test for ci/bump-version.bash — run from repo root on a clean tree.
set -u
git status --porcelain | grep -qE '^ ?M ' && { echo "SKIP: arbre sale — revert d'abord"; exit 2; }
OLD="$(grep -oE 'WSUSOFFLINE_VERSION=[0-9]+\.[0-9]+\.[0-9]+' cmd/DownloadUpdates.cmd | head -1 | cut -d'=' -f2)"
[ -n "${OLD}" ] || { echo "FAIL: version introuvable dans cmd/DownloadUpdates.cmd"; exit 1; }
NEW="${OLD%.*}.$(( ${OLD##*.} + 1 ))"
bash ci/bump-version.bash "${NEW}" || { echo "FAIL: bump-version exited $?"; git checkout -- .; exit 1; }
STAT="$(git diff --stat | tail -1)"
echo "$STAT" | grep -q "17 files changed" || { echo "FAIL: attends 17 fichiers, obtenu: $STAT"; git checkout -- .; exit 1; }
echo "$STAT" | grep -q "32 insertions" || { echo "FAIL: attends 32 substitutions, obtenu: $STAT"; git checkout -- .; exit 1; }
grep -rnF "${OLD}" --include="*.au3" --include="*.json" --include="*.csproj" --include="*.tsx" . 2>/dev/null | grep -vE "node_modules|dist/|bin/|obj/|RELEASE_NOTES|docs/|\.superpowers|\.planning|\.playwright" | head -1 | grep -q . && { echo "FAIL: residu d'ancienne version ${OLD}"; git checkout -- .; exit 1; }
grep -q "${NEW}" cmd/DownloadUpdates.cmd || { echo "FAIL: nouvelle version absente du moteur"; git checkout -- .; exit 1; }
grep -q "(b2026.10)" cmd/DownloadUpdates.cmd || { echo "FAIL: le build tag b2026.10 ne doit pas bouger"; git checkout -- .; exit 1; }
grep -q "${NEW},release" static/SelfUpdateVersion-this.txt || { echo "FAIL: marqueur selfupdate non bumpé"; git checkout -- .; exit 1; }
git checkout -- .
[ -z "$(git status --porcelain | grep -E '^ ?M ')" ] || { echo "FAIL: revert incomplet"; exit 1; }
echo "PASS bump-version (17 fichiers, 32 substitutions, build tag intact, revert propre)"
