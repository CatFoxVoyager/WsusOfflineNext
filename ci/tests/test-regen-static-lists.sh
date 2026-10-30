#!/usr/bin/env bash
# Fixture test for ci/regen-static-lists.bash — run from repo root.
set -u
F="ci/tests/fixtures-regen"
# fixtures auto-portantes : état initial recréé à chaque exécution
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$F/static-test/listA.txt"
printf 'https://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$F/static-test/listB.txt"
rm -f "$F/.regen-report.md"
hDRY="$(cat "$F"/static-test/*.txt | md5sum)"
bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines 2 --dry-run; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: fixture dry-run exited $rc"; exit 1; }
# dry-run: listes INCHANGÉES (hash avant/après)
hDRY2="$(cat "$F"/static-test/*.txt | md5sum)"
[ "$hDRY" = "$hDRY2" ] || { echo "FAIL: dry-run a modifié les listes (hash avant/après)"; exit 1; }
# dry-run: AUCUN fichier dans l'arbre — le rapport n'existe pas (CISC-03)
[ ! -f "$F/.regen-report.md" ] || { echo "FAIL: dry-run a créé .regen-report.md (CISC-03)"; exit 1; }
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
# instrument de comptage CRLF (obs #5790) : tr, pas od|grep
CRLF=$(head -1 "$F/static-test/listA.txt" | tr -dc '\r' | wc -c)
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
# bite strict-awk : un dead-file materialise CRLF au checkout (.gitattributes
# eol=crlf) doit etre REMOVE meme quand l'awk preserve le CR du record. Le shim
# gawk -v BINMODE=1 reproduit en local la semantique de record Linux ; sur
# ubuntu mawk est deja strict — le cas tourne aussi sans shim (jamais masque).
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$T/static/listE.txt"
printf 'https://download.example/a/prod-dead.exe\r\n' > "$T/dead-crlf.txt"
STUB="$(mktemp -d)"
PATHSHIM=""
if command -v gawk > /dev/null 2>&1; then
  printf '#!/usr/bin/env bash\nexec gawk -v BINMODE=1 "$@"\n' > "$STUB/awk"
  chmod +x "$STUB/awk"
  PATHSHIM="${STUB}:"
fi
PATH="${PATHSHIM}${PATH}" bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead-crlf.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: strict-awk run exited $rc"; rm -rf "$T" "$STUB"; exit 1; }
grep -q 'prod-dead' "$T/static/listE.txt" && { echo "FAIL: REMOVE strict-awk — dead CRLF encore dans la liste"; rm -rf "$T" "$STUB"; exit 1; }
grep -qE '\| listE\.txt *\| *1 *\| *1 *\| *1 *\|' "$T/.regen-report.md" || { echo "FAIL: rapport strict-awk mensonger (attendu 1 kept, 1 added, 1 removed)"; rm -rf "$T" "$STUB"; exit 1; }
rm -rf "$T" "$STUB"
# miroir sans shim : awk hote tel quel, meme dead-file CRLF — le fix ne doit pas
# dependre du shim (sur ubuntu mawk est deja strict : ce cas mord directement).
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$T/static/listE.txt"
printf 'https://download.example/a/prod-dead.exe\r\n' > "$T/dead-crlf.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead-crlf.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: no-shim run exited $rc"; rm -rf "$T"; exit 1; }
grep -q 'prod-dead' "$T/static/listE.txt" && { echo "FAIL: REMOVE no-shim — dead CRLF encore dans la liste"; rm -rf "$T"; exit 1; }
grep -qE '\| listE\.txt *\| *1 *\| *1 *\| *1 *\|' "$T/.regen-report.md" || { echo "FAIL: rapport no-shim mensonger (attendu 1 kept, 1 added, 1 removed)"; rm -rf "$T"; exit 1; }
rm -rf "$T"
# CISC-01 : un fichier mixte (URL + commentaire + ligne vide) traverse la
# réécriture verbatim — la doc inline ne peut plus être rasée. CISC-03 : le
# run réel écrit toujours le rapport à l'emplacement du contrat
# (monthly-updates.yml).
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
cp "$F/dead.txt" "$T/dead.txt"
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\n# hand-curated\r\n\r\nhttps://download.example/a/prod-v1.5.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\r\n' > "$T/static/listM.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: mixed-file run exited $rc"; rm -rf "$T"; exit 1; }
grep -qF '# hand-curated' "$T/static/listM.txt" || { echo "FAIL: commentaire détruit par la réécriture (CISC-01)"; rm -rf "$T"; exit 1; }
grep -qF 'prod-v1.0.exe,alias1.exe' "$T/static/listM.txt" || { echo "FAIL: URL vivante + alias détruites (CISC-01)"; rm -rf "$T"; exit 1; }
grep -qF 'prod-v1.5.exe' "$T/static/listM.txt" || { echo "FAIL: 2e URL vivante détruite (CISC-01)"; rm -rf "$T"; exit 1; }
grep -qF 'prod-v2.0.exe' "$T/static/listM.txt" || { echo "FAIL: ajout même-famille manquant sur fichier mixte"; rm -rf "$T"; exit 1; }
grep -qF 'prod-dead' "$T/static/listM.txt" && { echo "FAIL: dead non retiré sur fichier mixte"; rm -rf "$T"; exit 1; }
# la ligne vide est préservée : census = 5 lignes CRLF (2 URL vivantes +
# commentaire + ligne vide + ajout) ; instrument de comptage tr (obs #5790)
[ "$(tr -dc '\r' < "$T/static/listM.txt" | wc -c)" -eq 5 ] || { echo "FAIL: census fichier mixte != 5 lignes — ligne vide non préservée (CISC-01)"; rm -rf "$T"; exit 1; }
# la colonne kept compte AUSSI les lignes non-URL (4 = 2 URL + commentaire + vide)
grep -qE '\| listM\.txt *\| *4 *\| *1 *\| *1 *\|' "$T/.regen-report.md" || { echo "FAIL: rapport mixte mensonger (attendu 4 kept, 1 added, 1 removed)"; rm -rf "$T"; exit 1; }
[ -f "$T/.regen-report.md" ] || { echo "FAIL: run réel sans rapport (CISC-03)"; rm -rf "$T"; exit 1; }
rm -rf "$T"
# CISC-07 morsure : un nom de fichier tout-chiffres n'a PAS de famille — il ne
# peut ni en fournir (côté liste) ni en recevoir (côté catalogue). Pré-fix, la
# famille vide "" matchait "" et l'URL tout-chiffres du catalogue était ajoutée.
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
printf 'guid-5,https://download.example/n/20261029.exe\n' >> "$T/staging/update-ids-and-locations-all.txt"
cp "$F/dead.txt" "$T/dead.txt"
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\nhttps://download.example/n/20261001.exe\r\n' > "$T/static/listN.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: all-digits run exited $rc"; rm -rf "$T"; exit 1; }
grep -qF '20261029' "$T/static/listN.txt" && { echo "FAIL: famille vide — URL tout-chiffres du catalogue ajoutée (CISC-07)"; rm -rf "$T"; exit 1; }
grep -qF '20261001.exe' "$T/static/listN.txt" || { echo "FAIL: URL tout-chiffres de la liste détruite"; rm -rf "$T"; exit 1; }
grep -qF 'prod-v2.0.exe' "$T/static/listN.txt" || { echo "FAIL: ajout famille prod-v cassé par le cas tout-chiffres"; rm -rf "$T"; exit 1; }
rm -rf "$T"
# CISC-07 + WR-05 (obs #5797) : la morsure doit mordre à CHAQUE classe de
# position que le mécanisme ordonne — l'URL tout-chiffres du catalogue triant
# PREMIER (0/), au MILIEU (a/mid/) et en DERNIER (n/). Le bloc listN
# ci-dessus n'échantillonne que le dernier, ordre favorable où la
# désynchronisation du paste (CR-01 : family_of supprimait la ligne vide)
# retombe sur la ligne terminale perdue au lieu de décaler les paires. À
# chaque position : l'URL tout-chiffres n'est PAS ajoutée, les ajouts de même
# famille survivent (other-x1, prod-v2.0), le dead est retiré, l'URL
# tout-chiffres de la liste est préservée. Fins de ligne CRLF mixtes.
for pos in 0/20261029.exe a/mid/20261029.exe n/20261029.exe; do
  T="$(mktemp -d)"
  mkdir -p "$T/staging" "$T/static"
  cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
  printf 'guid-7,https://download.example/%s\n' "$pos" >> "$T/staging/update-ids-and-locations-all.txt"
  cp "$F/dead.txt" "$T/dead.txt"
  printf 'https://download.example/a/b/other-x2.exe,alias2.exe\r\nhttps://download.example/a/prod-v1.0.exe\r\nhttps://download.example/a/prod-dead.exe,aliasd.exe\nhttps://download.example/n/20261001.exe\n' > "$T/static/listP.txt"
  bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead.txt" --min-lines 2 --add; rc=$?
  [ "$rc" -eq 0 ] || { echo "FAIL: all-digits pos=$pos run exited $rc"; rm -rf "$T"; exit 1; }
  grep -qF '20261029' "$T/static/listP.txt" && { echo "FAIL: famille vide pos=$pos — URL tout-chiffres du catalogue ajoutée (CISC-07/CR-01)"; rm -rf "$T"; exit 1; }
  grep -qF 'other-x1.exe' "$T/static/listP.txt" || { echo "FAIL: pos=$pos — ajout même-famille other-x manquant (CR-01)"; rm -rf "$T"; exit 1; }
  grep -qF 'prod-v2.0.exe' "$T/static/listP.txt" || { echo "FAIL: pos=$pos — prod-v2.0 perdu (désynchronisation paste, CR-01)"; rm -rf "$T"; exit 1; }
  grep -qF 'prod-dead' "$T/static/listP.txt" && { echo "FAIL: pos=$pos — dead non retiré (REMOVE cassé)"; rm -rf "$T"; exit 1; }
  grep -qF '20261001.exe' "$T/static/listP.txt" || { echo "FAIL: pos=$pos — URL tout-chiffres de la liste détruite"; rm -rf "$T"; exit 1; }
  grep -qE '\| listP\.txt *\| *3 *\| *2 *\| *1 *\|' "$T/.regen-report.md" || { echo "FAIL: pos=$pos — rapport mensonger (attendu 3 kept, 2 added, 1 removed)"; rm -rf "$T"; exit 1; }
  rm -rf "$T"
done
# CISC-07 morsure dernier bloc de chiffres : kb4012215 et kb4012218 sont deux
# familles DIFFÉRENTES (windows6.1-kb4012215-v vs windows6.1-kb4012218-v).
# Pré-fix, la troncature au premier bloc donnait famille "windows" commune →
# l'URL du catalogue était ajoutée.
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
cp ci/tests/fixtures-regen/update-ids-and-locations-all.txt "$T/staging/"
printf 'guid-6,https://download.example/w/windows6.1-kb4012218-v2.msu\n' >> "$T/staging/update-ids-and-locations-all.txt"
cp "$F/dead.txt" "$T/dead.txt"
printf 'https://download.example/w/windows6.1-kb4012215-v2.msu\r\n' > "$T/static/listK.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead.txt" --min-lines 2 --add; rc=$?
[ "$rc" -eq 0 ] || { echo "FAIL: last-digit-block run exited $rc"; rm -rf "$T"; exit 1; }
grep -qF 'kb4012218' "$T/static/listK.txt" && { echo "FAIL: dernier bloc — kb4012218 ajouté via la famille kb4012215 (CISC-07)"; rm -rf "$T"; exit 1; }
grep -qF 'kb4012215' "$T/static/listK.txt" || { echo "FAIL: URL de la liste détruite (dernier bloc)"; rm -rf "$T"; exit 1; }
grep -qE '\| listK\.txt *\| *1 *\| *0 *\| *0 *\|' "$T/.regen-report.md" || { echo "FAIL: rapport dernier bloc mensonger (attendu 1 kept, 0 added)"; rm -rf "$T"; exit 1; }
rm -rf "$T"
# CISC-06 : UNE seule implémentation de la sémantique de famille — la fonction
# morte url_family a disparu au profit de family_of(), appelée des deux côtés
grep -qF 'url_family' ci/regen-static-lists.bash && { echo "FAIL: url_family subsiste (CISC-06)"; exit 1; }
# CISC-09 : gardes fail-closed AVANT toute écriture.
# (a) static-dir sans liste -> exit 1 + message, rien écrit (miroir validate-links)
h1="$(cat "$F"/static-test/*.txt | md5sum)"
rm -f "$F/.regen-report.md"
E="$(mktemp -d)"
mkdir -p "$E/empty-static"
msg="$(bash ci/regen-static-lists.bash "$F" "$E/empty-static" "$F/dead.txt" --min-lines 2 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: static-dir vide doit aborter (rc=$rc)"; rm -rf "$E"; exit 1; }
printf '%s\n' "$msg" | grep -qF 'no lists under' || { echo "FAIL: static-dir vide sans message 'no lists under'"; rm -rf "$E"; exit 1; }
[ "$(cat "$F"/static-test/*.txt | md5sum)" = "$h1" ] || { echo "FAIL: static-dir vide a écrit dans les listes"; rm -rf "$E"; exit 1; }
[ ! -f "$E/.regen-report.md" ] || { echo "FAIL: static-dir vide a écrit un rapport"; rm -rf "$E"; exit 1; }
rm -rf "$E"
# (b)/(c) --min-lines non numérique ou sans valeur -> exit 1 avec message
bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines abc >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: --min-lines abc doit aborter (rc=$rc)"; exit 1; }
msg="$(bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines abc 2>&1)"
printf '%s\n' "$msg" | grep -qF -- '--min-lines must be' || { echo "FAIL: --min-lines abc sans message 'must be'"; exit 1; }
bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: --min-lines sans valeur doit aborter (rc=$rc)"; exit 1; }
msg="$(bash ci/regen-static-lists.bash "$F" "$F/static-test" "$F/dead.txt" --min-lines 2>&1)"
printf '%s\n' "$msg" | grep -qF -- '--min-lines requires' || { echo "FAIL: --min-lines sans valeur sans message 'requires'"; exit 1; }
# (e)/(f) catalogue sans URL : les DEUX formes abortent avant toute écriture —
# épingle la garde existante (morsure anti-régression : sans elle ces cas
# tournent rc 0 et écrivent un rapport vide crédible)
T="$(mktemp -d)"
mkdir -p "$T/staging" "$T/static"
printf 'https://download.example/a/prod-v1.0.exe,alias1.exe\r\n' > "$T/static/listZ.txt"
: > "$T/staging/update-ids-and-locations-all.txt"
cp "$F/dead.txt" "$T/dead.txt"
h1="$(md5sum < "$T/static/listZ.txt")"
msg="$(bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead.txt" --min-lines 0 2>&1)"; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: catalogue 0 octet + --min-lines 0 doit aborter (rc=$rc)"; rm -rf "$T"; exit 1; }
printf '%s\n' "$msg" | grep -qF 'no URLs in staging catalog' || { echo "FAIL: catalogue vide sans message 'no URLs in staging catalog'"; rm -rf "$T"; exit 1; }
[ "$(md5sum < "$T/static/listZ.txt")" = "$h1" ] || { echo "FAIL: catalogue vide a écrit dans la liste"; rm -rf "$T"; exit 1; }
[ ! -f "$T/.regen-report.md" ] || { echo "FAIL: catalogue vide a écrit un rapport"; rm -rf "$T"; exit 1; }
# forme 2 : >= min-lines lignes brutes mais aucune ligne URL (le garde min-lines
# seul la laisserait passer — seule la garde 0-URL la couvre)
printf 'garbage-one\r\ngarbage-two\r\n' > "$T/staging/update-ids-and-locations-all.txt"
bash ci/regen-static-lists.bash "$T/staging" "$T/static" "$T/dead.txt" --min-lines 2 >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] || { echo "FAIL: catalogue sans URL (lignes brutes) doit aborter (rc=$rc)"; rm -rf "$T"; exit 1; }
rm -rf "$T"
echo "PASS regen fixtures (KEEP/ADD/famille/REMOVE multi-listes/CRLF/dry-run/abort)"
