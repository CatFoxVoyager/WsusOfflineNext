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
grep -qE '\| bad\.txt *\| *0 *\| *1 *\|' "$rep" || { echo "FAIL: report lacks exact bad.txt row (0 ok / 1 dead)"; exit 1; }
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
# --- totaux libelles + --cache garde + cache CR-safe ---
# totaux libelles sur un run nominal frais: 4 listes, good/crlf/dup portent la
# meme URL -> 2 URLs uniques, 4 entrees, 2 doublons inter-listes. Morsure: le
# rapport pre-fix porte une seule ligne "Total:" qui melange les denominateurs.
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" || exit 1
grep -qE '\*\*Total \(unique\):\*\* 2 URLs probed \(unique\), 1 dead \(unique\)\.' "$rep" || { echo "FAIL: total unique libelle absent ou faux"; exit 1; }
grep -qE '\*\*Somme des listes:\*\* 4 entrées, 1 dead\.' "$rep" || { echo "FAIL: somme des listes libellee absente ou fausse"; exit 1; }
grep -qE '^2 doublon\(s\) inter-listes\.$' "$rep" || { echo "FAIL: mention des doublons inter-listes absente ou fausse"; exit 1; }
# --cache en dernier argument: refus explicite (rc 1 + message) au lieu d'une
# option avalee qui desactive silencieusement la confirmation en deux passes
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --cache 2> "$W/noval.err"; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: --cache sans valeur doit refuser (rc=$rc)"; exit 1; }
grep -q -- "--cache requires a file argument" "$W/noval.err" || { echo "FAIL: message d'arite --cache absent"; exit 1; }
# cache materialise CRLF (editeur) contenant la mort: confirmee des la passe 1.
# Cas sans shim: sur un grep hote qui lit les keyfiles en mode texte (MSYS), il
# est vert meme pre-fix — il porte le contrat CI (le grep ubuntu preserve le CR).
cache2="$W/cache2.txt"
printf 'https://bad.invalid.example/nope\r\n' > "$cache2"
bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --cache "$cache2" || exit 1
grep -q "bad.invalid" "$dead" || { echo "FAIL: cache CRLF: mort non confirmee a la passe 1"; exit 1; }
# meme scenario sous shim grep strict (lecture byte-exact des keyfiles,
# semantique Linux) — morsure reelle locale: cree seulement si le grep hote
# avale les CR des keyfiles (sonde auto-portable), sinon le cas tourne sans shim.
grep_stub="$W/stub-grep"; mkdir -p "$grep_stub"
printf 'a\r\n' > "$W/kprobe.txt"; printf 'a\n' > "$W/tprobe.txt"
if grep -Fx -f "$W/kprobe.txt" "$W/tprobe.txt" > /dev/null 2>&1; then
  cat > "$grep_stub/grep" <<'SHIM'
#!/bin/bash
# strict-grep shim (test-only): reproduce Linux byte-exact semantics for
# `-f KEYFILE` reads on a host whose grep strips CR from keyfiles.
keyfile=""
args=()
while [ $# -gt 0 ]; do
  if [ "$1" = "-f" ] && [ $# -ge 2 ]; then keyfile="$2"; shift 2; continue; fi
  args+=("$1"); shift
done
real="/usr/bin/grep"; [ -x "$real" ] || real="/bin/grep"
if [ -z "${keyfile}" ]; then
  exec "$real" ${args+"${args[@]}"}
fi
pats=()
while IFS= read -r line || [ -n "${line:-}" ]; do pats+=(-e "$line"); done < "${keyfile}"
[ ${#pats[@]} -gt 0 ] || exit 1
exec "$real" ${args+"${args[@]}"} "${pats[@]}"
SHIM
  chmod +x "$grep_stub/grep"
  SHIM_PATH="$grep_stub:$PATH"
else
  SHIM_PATH="$PATH"
fi
printf 'https://bad.invalid.example/nope\r\n' > "$cache2"
PATH="$SHIM_PATH" bash ci/validate-links.bash ci/tests/fixtures-links "$rep" "$dead" --cache "$cache2" || exit 1
grep -q "bad.invalid" "$dead" || { echo "FAIL: cache CRLF sous grep strict: mort non confirmee a la passe 1"; exit 1; }
echo "PASS validate-links fixtures (dead-file, CRLF cleaning, report row, strict exit)"
