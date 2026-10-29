#!/usr/bin/env bash
# Fixture test for ci/regen-static-lists.bash — run from repo root.
set -u
F="ci/tests/fixtures-regen"
# fixtures auto-portantes : état initial recréé à chaque exécution
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$F/static-test/listA.txt"
printf 'https://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$F/static-test/listB.txt"
rm -f "$F/.regen-report.md"
bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines 2 --dry-run; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: fixture dry-run exited $rc"; exit 1; }
# dry-run: listes INCHANGÉES
grep -q "prod-v2.0" "$F/static-test/listA.txt" && { echo "FAIL: dry-run modified listA"; exit 1; }
# run réel
bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: real run exited $rc"; exit 1; }
grep -q "prod-v1.0.exe,alias1.exe" "$F/static-test/listA.txt" || { echo "FAIL: KEEP/alias cassé — ligne avec alias perdue ou altérée"; exit 1; }
grep -q "prod-v2.0" "$F/static-test/listA.txt" || { echo "FAIL: ADD broken — url2 (même famille) non ajoutée"; exit 1; }
grep -q "other-x1" "$F/static-test/listA.txt" && { echo "FAIL: hors-famille ajouté"; exit 1; }
grep -q "aliasd" "$F/static-test/listA.txt" && { echo "FAIL: REMOVE broken — dead encore dans listA"; exit 1; }
grep -q "prod-dead" "$F/static-test/listB.txt" && { echo "FAIL: REMOVE broken — dead encore dans listB"; exit 1; }
grep -q "other-x1" "$F/static-test/listB.txt" && { echo "FAIL: pollution croisée dans listB"; exit 1; }
# sans --add : aucun candidat écrit
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$F/static-test/listA.txt"
printf 'https://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$F/static-test/listB.txt"
bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines 2; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: run sans --add exited $rc"; exit 1; }
grep -q "prod-v2.0" "$F/static-test/listA.txt" && { echo "FAIL: ADD écrit sans --add"; exit 1; }
grep -q "prod-dead" "$F/static-test/listA.txt" && { echo "FAIL: REMOVE cassé sans --add"; exit 1; }
CRLF=$(head -1 "$F/static-test/listA.txt" | od -c | grep -c '\r') || true
[ "$CRLF" -ge 1 ] || { echo "FAIL: sortie pas en CRLF"; exit 1; }
# dead-file VIDE : la liste doit survivre integralement (garde awk FILENAME==ARGV[1])
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$T/static/listE.txt"
: > "$T/dead-empty.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead-empty.txt" --min-lines 2; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: empty-dead run exited $rc"; rm -rf "$T"; exit 1; }
h1="$(md5sum < "$T/static/listE.txt")"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead-empty.txt" --min-lines 2; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: empty-dead run 2 exited $rc"; rm -rf "$T"; exit 1; }
h2="$(md5sum < "$T/static/listE.txt")"
[ "$h1" = "$h2" ] || { echo "FAIL: empty-dead sans --add a modifie la liste"; rm -rf "$T"; exit 1; }
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$T/static/listE.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead-empty.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: empty-dead --add exited $rc"; rm -rf "$T"; exit 1; }
grep -q 'prod-v1.0.exe,alias1.exe' "$T/static/listE.txt" || { echo "FAIL: empty-dead --add a RASE la liste (idiome NR==FNR)"; rm -rf "$T"; exit 1; }
grep -q 'prod-dead' "$T/static/listE.txt" || { echo "FAIL: empty-dead --add a retire une URL non prouvee morte"; rm -rf "$T"; exit 1; }
grep -qE '\| listE\.txt *\| *2 *\| *1 *\| *0 *\|' "$T/.regen-report.md" || { echo "FAIL: rapport mensonger (attendu 2 kept, 1 added, 0 removed)"; rm -rf "$T"; exit 1; }
rm -rf "$T"
# abort fail-closed : staging vide (hash avant/après)
h1="$(cat "$F"/static-test/*.txt | md5sum)"
rm -f "$F/.regen-report.md"
bash ci/regen-static-lists.bash ci/tests/empty-dir "$F/static-test" "$F/dead.txt" 2>/dev/null; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: staging vide doit aborter"; exit 1; }
h2="$(cat "$F"/static-test/*.txt | md5sum)"
[ "$h1" = "$h2" ] || { echo "FAIL: abort a écrit quelque chose"; exit 1; }
[ ! -f "$F/.regen-report.md" ] || { echo "FAIL: abort a écrit un rapport"; exit 1; }
echo "PASS regen fixtures (KEEP/ADD/famille/REMOVE multi-listes/CRLF/dry-run/abort)"
