#!/usr/bin/env bash
# Fixture test for ci/validate-links.bash — run from repo root.
set -u
W="$(mktemp -d)"
trap 'rm -rf "$W"' EXIT
rep="$W/links-report.md"; dead="$W/links-dead.txt"
rm -f "$rep" "$dead"
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: non-strict run exited $rc"; exit 1; }
grep -q "^https://bad.invalid.example/nope$" "$dead" || { echo "FAIL: dead URL missing/cleaned wrong in dead-file"; exit 1; }
[ "$(wc -l < "$dead")" -eq 1 ] || { echo "FAIL: dead-file should hold exactly 1 URL"; exit 1; }
grep -q "bad.txt" "$rep" && grep -q "0" "$rep" || { echo "FAIL: report lacks per-list row"; exit 1; }
grep -qE '\| crlf.txt *\| *1 *\| *0 *\|' "$rep" || { echo "FAIL: crlf.txt not counted 1 ok / 0 dead (CRLF+space cleaning broken)"; exit 1; }
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --strict; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: --strict should exit 1 with a dead URL"; exit 1; }
# deux-passes: cache vide => un lien mort NE part pas encore (confirmation requise)
cache="$W/links-cache.txt"; : > "$cache"
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --cache "$cache" || exit 1
[ -s "$dead" ] && { echo "FAIL: pass 1 sans cache: la mort doit seulement etre candidate"; exit 1; }
grep -q "bad.invalid" "$cache" || { echo "FAIL: pass 1: candidate non enregistree dans le cache"; exit 1; }
# passe 2: le meme lien mort confirme => il part
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --cache "$cache" || exit 1
grep -q "bad.invalid" "$dead" || { echo "FAIL: pass 2: mort confirme non retire"; exit 1; }
# un lien vivant present du cache (faux positif passe) doit sortir du cache et rester vivant
printf 'https://www.microsoft.com/
' > "$cache"
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --cache "$cache" || exit 1
grep -q "microsoft" "$dead" && { echo "FAIL: vivant en cache retire a tort"; exit 1; }
grep -q "microsoft" "$cache" && { echo "FAIL: vivant doit sortir du cache"; exit 1; }
# etage casse (stub PATH sort -> exit 1): le script doit aborter bruyamment au
# lieu de lire "0 dead" en faux vert (WR-06). Cas auto-portable: le stub est
# confine a ce run puis retire; re-run nominal pour prouver que la suite locale
# n'a pas ete empoisonnee. Morsure: sur un script sans pipefail le rc du
# pipeline est celui de xargs (0 sur entree vide) -> rc 0 + "0 dead of".
rep2="$W/rep2.md"; dead2="$W/dead2.txt"; stub_bin="$W/stub-bin"; mkdir -p "$stub_bin"
printf '#!/bin/sh\necho "stub sort: probe stage broken (test injection)" >&2\nexit 1\n' > "$stub_bin/sort"
chmod +x "$stub_bin/sort"
PATH="$stub_bin:$PATH" bash ci/validate-links.bash ci/tests/fixtures-links "$rep2" "$dead2" > "$W/out2.log" 2> "$W/err2.log"; rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL: etage casse doit aborter, pas lire 0 dead (rc=0)"; exit 1; }
grep -q "probe" "$W/err2.log" || { echo "FAIL: etage casse doit nommer le stage probe sur stderr"; exit 1; }
grep -q "0 dead of" "$W/out2.log" "$W/err2.log" && { echo "FAIL: etage casse ne doit pas annoncer 0 dead"; exit 1; }
[ -e "$dead2" ] && { echo "FAIL: etage casse ne doit pas ecrire de dead-file"; exit 1; }
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead"; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: re-run nominal apres stub exited $rc"; exit 1; }
[ "$(wc -l < "$dead")" -eq 1 ] || { echo "FAIL: re-run nominal: dead-file doit rester a 1 URL"; exit 1; }
echo "PASS validate-links fixtures (dead-file, CRLF cleaning, report row, strict exit)"
