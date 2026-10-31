# WINDOWS.md — hygiène EOL et arbre propre sur un poste Windows

Documentation des conventions Windows/MSYS de ce dépôt : la passe de
renormalisation EOL, les instruments qui mesurent un arbre propre sur ce
host, et les quirks MSYS hérités des phases 14–15. Ce fichier shippe dans
l'arbre de release : contenu purement procédural, sans credential ni chemin
utilisateur.

## La passe de renormalisation

Pourquoi : `.gitattributes` déclare `* text=auto` (+ `eol=crlf` pour
cmd/bat/vbs/au3/ini/txt, `eol=lf` pour sh), mais des blobs d'index portent
encore des octets CR d'une époque antérieure aux attributs — la
renormalisation n'avait jamais été jouée globalement. Un checkout frais en
était « sale » en vue stricte : `git status`/`git diff` montent des fichiers
modifiés alors que le contenu est identique au blob. Les gardes
EOL-tolerantes posées en 15-02 (dev-fix `aa3ccf9`) compensaient la classe au
fil de l'eau ; la passe l'élimine côté index.

Procédure :

    git add --renormalize .

Règle d'ATOMICITÉ : la passe est UN seul commit, pur — rien d'autre dedans,
jamais mélangée à une édition de contenu. Toute édition qui traîne dans
l'arbre au moment de la passe serait aspirée dans la masse des blobs
re-écrits et passerait inaperçue.

Instruments de vérification (dans cet ordre) :

- AVANT commit : `git diff --cached --ignore-cr-at-eol --stat` doit être
  VIDE — preuve que le staged est content-neutre (seules les fins de ligne
  bougent) ;
- APRÈS commit : `git ls-files --eol | grep -cE "i/(crlf|mixed)"` doit
  rendre 0 — le recensement d'index ne montre plus aucun blob en CR ;
- tout reliquat (blobs que git refuse de renormaliser, classe
  binary-adjacente) est une décision à part entière : élargir
  `.gitattributes` ne se fait pas dans la passe.

Le recensement pré-passe est un état périmissable : ne jamais figer un
comptage dans ce document — le record mesuré d'une passe vit dans le message
de son commit.

## Signaux d'arbre propre sur ce host

`git status --porcelain` n'est PAS l'autorité ici : sur un poste Windows
git-bash il porte du bruit EOL, et `status.renormalize=true` ne le filtre
pas (mesuré en 15-02). Les trois instruments sûrs :

- `git diff --ignore-cr-at-eol` — le contenu, fins de ligne ignorées ;
- `git diff --cached` — le staged ;
- `git ls-files --eol` — le recensement index/worktree.

Un arbre propre se prouve par : diff vide, staged vide, census d'index sans
blob CR.

## Quirks MSYS hérités

- **`-x` sur tout `*.exe` existant** : MSYS rend le test exécutable TRUE
  pour n'importe quel `*.exe` présent, et exécute un fichier non-PE en
  no-op silencieux rc=0. Un stand-in `bin/unzip.exe` pré-créé détournerait
  `resolve_tools` — d'où le stub créé en cours de run (leçon 14-03).
- **grep/sed MSYS avalent les CR** des keyfiles DOS alors que le grep
  ubuntu les voit : une morsure cache-CRLF ne se manifeste que sur CI
  (miroir 15-01/15-02, run 41012438351 — un CR survivant refusait chaque
  pin SHA256 sur ubuntu). Lire les fichiers DOS via les helpers
  CR-normalisés (`cat_dos`, `grep_dos` de `sh/libraries/dos-files.bash`).
- **Split de chemin MSYS vs git.exe** : un chemin `/tmp` passé à git.exe
  atterrit à la racine du drive courant. Passer des chemins drive-absolus
  (`D:/...`) à tout processus natif.

Application du protocole : la garde EOL-aware de
`ci/tests/test-bump-version.sh:47-70` — précondition d'arbre propre lue en
vue `--ignore-cr-at-eol`, assertions diff/stat dans la même vue, contrôle
positif mesuré « une vraie édition de contenu → 1 fichier détecté ».
