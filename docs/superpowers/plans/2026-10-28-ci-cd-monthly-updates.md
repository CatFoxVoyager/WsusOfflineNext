# CI/CD mensuel — dépendances sécurité + mises à jour : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatiser chaque mois : PRs de mise à jour des dépendances (validés par CI gratuit), rafraîchissement des listes d'URLs statiques depuis le catalogue WSUS (runner self-hosted Windows), et release GitHub automatique si changement.

**Architecture:** Volet A = Dependabot + workflow CI sur runners hébergés (ubuntu). Volet B = workflow mensuel `schedule`/`workflow_dispatch` sur runner self-hosted Windows (label `wson-windows`), scripts d'outillage en bash sous `ci/` réutilisant la chaîne XSLT existante, fusion KEEP/ADD/REMOVE bornée, push direct sur `main`, release gated sur (listes changées OU commits depuis dernier tag).

**Tech Stack:** GitHub Actions (hosted + self-hosted Windows service), Dependabot, bash (Git Bash, helpers `sh/libraries/dos-files.bash`), outillage existant : `bin/wget64.exe`, `expand.exe`, `cscript XSLT.vbs`, `xslt/extract-update-cab-exe-ids-and-locations.xsl`, `gsort`, `MakeRelease.cmd`, `CompileModernApps.cmd`.

**Spec:** `docs/superpowers/specs/2026-10-28-ci-cd-dependencies-updates-design.md`

## Global Constraints

- Pas de PowerShell ; scripts bash/CMD/VBS uniquement. Nouveaux scripts `ci/*.bash` exécutés via Git Bash (présent avec Git for Windows sur le runner).
- Lists DOS (CRLF) : parser uniquement via les helpers `sh/libraries/dos-files.bash` (`grep_dos`), jamais grep nu.
- HEAD msdownload : User-Agent réaliste + 2 retries ; UA nu renvoie 403.
- Le runner self-hosted ne court jamais un événement `pull_request` ; le workflow mensuel garde `if: github.event_name != 'pull_request' && github.repository == 'CatFoxVoyager/WsusOfflineNext'`.
- `dry_run=true` interdit tout `git push` et toute création de release.
- Périmètre listes : `static/StaticDownloadLinks-*.txt` + `static/StaticDownloadLink-wddefs-*.txt` (~83 fichiers, ~250 URLs). `client/static/StaticUpdateIds-*` hors scope v1.
- Version `YYYY.MM.P`, 17 fichiers / 32 substitutions (référence exacte : `git show 339f600`).
- Échec du catalogue (cab/xml absent) ⇒ abort non-zero AVANT toute écriture dans `static/`.

## Review Focus

1. **URL dans plusieurs listes** (redist x86/x64, multi-langues) : retirée de chaque liste la contenant, comptée par liste, sans effet de bord inter-listes. Test : fixture Task 4 (même URL morte dans 2 listes factices).
2. **CRLF + URLs avec trailing whitespace** : une ligne `url \r` doit matcher et produire une URL propre. Test : fixture Task 4 avec lignes CRLF.
3. **Catalogue absent/tronqué** : abort fail-closed sans toucher `static/`. Test : fixture Task 4 (staging vide ⇒ exit≠0, `static/` inchangé).
4. **dry_run=true** : aucun push, aucun tag, aucune release — le workflow doit s'arrêter après le rapport. Test : Task 9 (dispatch dry-run, `git log origin/main` inchangé).
5. **Famille d'ADD** : une URL ajoutée doit ressembler aux entrées existantes de SA liste (même famille de nom de fichier), jamais une URL arbitraire du catalogue. Test : fixture Task 4 (candidat hors famille ⇒ ignoré).

---

### Task 1: Dependabot + toggles de sécurité repo

**Files:**
- Create: `.github/dependabot.yml`

**Interfaces:**
- Produces: PRs Dependabot hebdomadaires (npm ×2 + github-actions) ; repo avec vulnerability-alerts et automated-security-fixes actifs (consommé par tout le reste, rien à coder).

- [ ] **Step 1: Écrire `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/src-modern/generator"
    schedule:
      interval: "weekly"
  - package-ecosystem: "npm"
    directory: "/src-modern/installer"
    schedule:
      interval: "weekly"
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

- [ ] **Step 2: Valider et activer les toggles repo**

Run: `gh api repos/CatFoxVoyager/WsusOfflineNext/vulnerability-alerts -X PUT && gh api repos/CatFoxVoyager/WsusOfflineNext/automated-security-fixes -X PUT`
Expected: les deux renvoient 204 (ou 204 déjà-actif).

- [ ] **Step 3: Commit**

```bash
git add .github/dependabot.yml
git commit -m "ci: add Dependabot config for npm and github-actions ecosystems"
```

### Task 2: ci.yml — validation des PRs sur runners hébergés

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Produces: workflow `CI` vert exigible sur toute PR (consommé par les PRs Dependabot de Task 1).

- [ ] **Step 1: Écrire le workflow** — deux jobs, `runs-on: ubuntu-latest`, `permissions: contents: read` :
  - `node-build` : `actions/checkout@v4`, `actions/setup-node@v4` (node 24, cache npm), puis pour CHACUN de `src-modern/generator` et `src-modern/installer` : `npm ci` puis `npm run build` (le script contient déjà `tsc && vite build`).
  - `dotnet-build` : `actions/setup-dotnet@v4` (dotnet-version: 8.0.x), `dotnet publish src-modern/generator/host/UpdateGenerator.csproj -c Release -r win-x64 /p:PublishSingleFile=true /p:SelfContained=false -o ci-out` (sanity compile ; pas d'upload d'artefact).
- [ ] **Step 2: Vérifier la syntaxe en local** — Run: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml'))"` Expected: exit 0.
- [ ] **Step 3: Commit puis vérifier sur une vraie PR** — commit, push sur main, ouvrir une PR jetable (1 ligne README) : Expected: les 2 jobs verts. Fermer la PR.

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add PR validation workflow (node builds and dotnet publish)"
```

### Task 3: ci/validate-links.bash — validation HEAD des listes

**Files:**
- Create: `ci/validate-links.bash`
- Create: `ci/tests/fixtures-links/` (2 fichiers : `good.txt`, `bad.txt`)

**Interfaces:**
- Produces: `bash ci/validate-links.bash <static-dir> <report-file> <dead-file> [--strict]` — exit 0, `report-file` markdown (`| liste | ok | mortes |` par fichier + détail), `dead-file` = URLs mortes une par ligne (consommé tel quel par Task 4) ; `--strict` ⇒ exit 1 si au moins une URL morte. Consommé par Task 4 et Task 7 (rapports pre/post + dead set).

- [ ] **Step 1: Écrire le test fixture**

`good.txt` contient `https://www.microsoft.com/` (vivante garantie) ; `bad.txt` contient `https://bad.invalid.example/nope` (morte garantie). Créer aussi un `crlf.txt` : même URL que good mais ligne terminée CRLF + espace trailing.

- [ ] **Step 2: Écrire le script** — implémentation : `source sh/libraries/dos-files.bash` pour lire les listes ; extraction des URLs (regex `^https?://`), dédoublonnage ; 10 jobs parallèles (`xargs -P10`), chaque probe = `bin/wget64.exe --spider -S -T 20 -t 2 -U "Mozilla/5.0 (Windows NT 10.0; Win64; x64) WSUSOfflineNext/2026.10" <url>` (wget64 sur PATH du runner et du dev — le script le résout via `bin/` relatif au repo root) ; rapport agrégé par liste.

- [ ] **Step 3: Vérifier** — Run: `bash ci/validate-links.bash ci/tests/fixtures-links /tmp/rep.md /tmp/dead.txt` puis `grep -c "bad.invalid" /tmp/rep.md` Expected: 1, exit 0, good ET crlf comptés ok ; `cat /tmp/dead.txt` Expected: exactement l'URL morte. Puis avec `--strict` : Expected: exit 1.

- [ ] **Step 4: Commit**

```bash
git add ci/validate-links.bash ci/tests/
git commit -m "ci: add static link validator with realistic UA and retries"
```

### Task 4: ci/regen-static-lists.bash — fusion KEEP/ADD/REMOVE

**Files:**
- Create: `ci/regen-static-lists.bash`
- Create: `ci/tests/fixtures-regen/` (staging factice + 2 listes factices)

**Interfaces:**
- Consumes: sortie de l'extraction catalogue `update-ids-and-locations-all.txt` (format `<update-id>,<url>`, produite par la chaîne `expand → XSLT.vbs extract-update-cab-exe-ids-and-locations.xsl → join → gsort`, cf. `ExtractDownloadLinks-all.cmd`) ; ensemble des URLs mortes via Task 3.
- Produces: `bash ci/regen-static-lists.bash <package.xml-dir> <static-dir> <dead-urls-file> [--dry-run]` — réécrit les listes in-place, écrit `<static-dir>/../.regen-report.md` (N ajoutées / M retirées / K hors-famille ignorées, par liste), exit 0 ; staging invalide ⇒ exit 1 sans écriture.

- [ ] **Step 1: Écrire les fixtures** — `all-urls.txt` (paires id,url factices dont : `v1` déjà dans listA, `v2` nouveau de même famille que listA, `v3` hors-famille) ; `static-test/listA.txt` (lignes CRLF, contient url-v1 ET url-dead) ; `static-test/listB.txt` (contient la MÊME url-dead — pin du comportement multi-listes). `dead.txt` = l'URL morte (sortie Task 3 simulée). La "famille" est définie par préfixe commun du nom de fichier (tout avant le dernier bloc de chiffres).

- [ ] **Step 2: Écrire le script** — algorithme de fusion (le seul corps non déterminé du plan) :

```bash
# Par liste : set(URLs courantes) = cur ; dead = cur ∩ fichier_mortes ;
# candidates = URLs du catalogue dont le nom de fichier matche la famille
# (préfixe avant le dernier bloc de chiffres) d'au moins une entrée vivante
# de cur, et absentes de cur.
# résultat = (cur − dead) ∪ candidates  ; tri gsort -u ; réécriture CRLF.
# Jamais de suppression autre que dead. Report: par liste added/removed/skipped.
```

Staging invalide (pas de `update-ids-and-locations-all.txt` ou < 1000 lignes) ⇒ abort AVANT toute écriture.

- [ ] **Step 3: Vérifier fixture** — Run: `bash ci/regen-static-lists.bash ci/tests/fixtures-regen ci/tests/fixtures-regen/static-test ci/tests/fixtures-regen/dead.txt --dry-run` Expected: listA gagne url-v2 (CRLF), PAS url-v3 ; url-dead retirée de listA ET listB (comptée par liste) ; report : 1 ajoutée / 2 retirées / 1 hors-famille ignorée. Puis abort : Run: `bash ci/regen-static-lists.bash ci/tests/empty-dir ci/tests/fixtures-regen/static-test ci/tests/fixtures-regen/dead.txt` Expected: exit ≠ 0, `static-test/` inchangé (`git status --porcelain ci/tests` vide).

- [ ] **Step 4: Commit**

```bash
git add ci/regen-static-lists.bash ci/tests/fixtures-regen/
git commit -m "ci: add bounded static-list regeneration (KEEP/ADD/REMOVE fusion)"
```

### Task 5: Étalonnage local sur vrai catalogue (gate humain)

**Files:** aucun (validation only)

**Interfaces:**
- Consumes: Tasks 3+4. Produces: la preuve que la fusion est sûre sur données réelles — **le gate avant branchement du schedule**.

- [ ] **Step 1: Télécharger le catalogue** — Run: `bin/wget64.exe -N -i static/StaticDownloadLinks-wsus.txt -P "$TEMP/wson-cal"` puis la chaîne expand/XSLT de `ExtractDownloadLinks-all.cmd` vers `$TEMP/wson-cal` (sans toucher `static/`).
- [ ] **Step 2: Dry-run réel** — Run: `bash ci/validate-links.bash static "$TEMP/pre.md" "$TEMP/dead.md"` puis `bash ci/regen-static-lists.bash "$TEMP/wson-cal" static "$TEMP/dead.md" --dry-run` Expected: diff borné (`git diff --stat static/` : uniquement ajoutns/retraits plausibles — vc_redist, .NET runtimes, wddefs ; zéro suppression d'URL vivante vérifiable dans le report K).
- [ ] **Step 3: **Montrer le rapport à l'humain** ; ne passer à la Task 6 qu'avec son accord. Si le diff est anormal : corriger la famille/le filtrage de Task 4 et recommencer (itération locale, pas de commit dégradé).

### Task 6: ci/bump-version.bash — substitution de version

**Files:**
- Create: `ci/bump-version.bash`

**Interfaces:**
- Produces: `bash ci/bump-version.bash <nouvelle-version>` — substitue l'ancienne version (lue depuis `cmd/DownloadUpdates.cmd`, regex `WSUSOFFLINE_VERSION=([0-9.]+)`) dans les 17 fichiers de `git show 339f600 --name-only`, imprime le tableau comptes attendus/réels, exit 1 si total ≠ 32.

- [ ] **Step 1: Écrire le script** — la liste des 17 chemins en dur (référence 339f600) ; `sed -i "s/$OLD/$NEW/g"` par fichier ; ancienne version dérivée de `WSUSOFFLINE_VERSION=` (source de vérité unique, cf. conventions repo).
- [ ] **Step 2: Vérifier puis annuler** — Run: `bash ci/bump-version.bash 2026.11.0 && git diff --stat | tail -1` Expected: `17 files changed, 32 insertions(+), 32 deletions(-)` ; puis `git checkout -- .` Expected: arbre propre.
- [ ] **Step 3: Commit**

```bash
git add ci/bump-version.bash
git commit -m "ci: add version bump script matching the 17-file release matrix"
```

### Task 7: monthly-updates.yml — orchestration mensuelle

**Files:**
- Create: `.github/workflows/monthly-updates.yml`

**Interfaces:**
- Consumes: Tasks 3, 4, 6 ; build `CompileModernApps.cmd --no-pause` ; `MakeRelease.cmd <version>` ; `gh release create`.
- Produces: run mensuel complet — commit listes sur `main` + release publiée si changements ; `dry_run` input interdit tout push.

- [ ] **Step 1: Écrire le workflow** — `on: schedule: [{cron: '0 6 15 * *'}]` + `workflow_dispatch` (input bool `dry_run`, **défaut false** — un event `schedule` ne passe pas d'inputs, donc le défaut gouverne les runs planifiés ; Task 9 passe `-f dry_run=true` explicitement) ; `runs-on: [self-hosted, wson-windows]` ; `permissions: {contents: write}` ; `concurrency: {group: wson-monthly}` ; garde globale `if: github.event_name != 'pull_request' && github.repository == 'CatFoxVoyager/WsusOfflineNext'` ; `defaults.run.shell: bash` (Git Bash du runner). Steps : checkout (persist-credentials true pour push) → téléchargement cab + expand/XSLT vers `$RUNNER_TEMP` → `validate-links.bash static pre.md dead.md` → `regen-static-lists.bash "$RUNNER_TEMP" static dead.md --dry-run` → build contrôle (npm ci/build ×2) → **si** diff listes && !dry_run : commit+push `chore(static): refresh download links YYYY-MM` → **gate release** (`git describe --tags --abbrev=0` ; fire = listes changées OU `git rev-list --count tag..HEAD > 0`) → si fire && !dry_run : `bump-version.bash <next>` (next = `YYYY.MM.0`, patch+1 si tag existe — résolu en bash avant bump), commit bump, pré-fetch helpers runtime (mêmes URLs que `sh/download-updates-tasks/20-get-sysinternals-helpers.bash` + ODT, vers `bin/`/`client/bin/`), `cmd //c CompileModernApps.cmd --no-pause`, `cmd //c MakeRelease.cmd <version>`, append section RELEASE_NOTES.md (depuis `.regen-report.md` + comptes), commit notes, tag, `gh release create v<version> --notes-file ... %TEMP%/wsusofflineCE<version>.zip %TEMP%/wsusofflineCE<version>_hashes.txt` (assets renommés `WsusOfflineNext-<version>.*` via copie). `gh` pré-authentifié sur le runner via `ACTIONS_GITHUB_TOKEN` → `gh auth login --with-token <<< $GITHUB_TOKEN`.
- [ ] **Step 2: Valider YAML + garde anti-push** — Run: validation yaml python ; `grep -c "dry_run" .github/workflows/monthly-updates.yml` Expected: ≥ 3 occurrences gardant push/tag/release.
- [ ] **Step 3: Commit**

```bash
git add .github/workflows/monthly-updates.yml
git commit -m "ci: add monthly catalog refresh and release workflow"
```

### Task 8: Installation du runner self-hosted + prérequis machine

**Files:** aucun dans le repo. ⚠️ Nécessite l'humain pour l'élévation admin.

- [ ] **Step 1: 7-Zip machine-wide** — Run: `winget install --scope machine 7zip.7zip` (élévation) Expected: `%ProgramFiles%\7-Zip\7z.exe` existe (1er chemin testé par MakeRelease.cmd).
- [ ] **Step 2: Vérifier PATH service** — Run: `pwsh -Command "whoami"` non pertinent ; vérification réelle au premier job (Step 5) : node, dotnet, git, bash doivent résoudre depuis le contexte service. Si absent : installer machine-wide (winget --scope machine) — JAMAIS de scoop (par-utilisateur).
- [ ] **Step 3: Installer le runner** — Run: `gh api repos/CatFoxVoyager/WsusOfflineNext/actions/runners/registration-token -q .token` ; télécharger https://github.com/actions/runner/releases/latest (win-x64 zip) vers `D:\actions-runner` (HORS du repo) ; `./config.cmd --url https://github.com/CatFoxVoyager/WsusOfflineNext --token <tok> --labels wson-windows --unattended --runasservice --windowslogonaccount NetworkService` (élévation pour le service).
- [ ] **Step 4: Vérifier l'enregistrement** — Run: `gh api repos/CatFoxVoyager/WsusOfflineNext/actions/runners -q '.runners[] | .name + " " + (.labels | map(.name) | join(","))'` Expected: un runner avec `self-hosted,wson-windows`, status idle.
- [ ] **Step 5: Smoke test service** — dispatch d'un mini-job écho (`workflow_dispatch` temporaire `runs-on: [self-hosted, wson-windows]` qui `echo` `node -v; dotnet --version; git --version; bash --version | head -1; 7z i | head -1`) Expected: les 5 outils répondent depuis le contexte service. Supprimer le job jetable.

### Task 9: Premiers runs — dry-run puis réel

**Files:** aucun (exécution + vérification)

- [ ] **Step 1: Dispatch dry-run** — Run: `gh workflow run monthly-updates.yml -f dry_run=true` puis `gh run watch` Expected: succès ; catalogue téléchargé, pre/post rapports dans le summary, **aucun commit sur origin/main** (`git log origin/main -1` inchangé), aucune release.
- [ ] **Step 2: Run réel** — dispatch `dry_run=false` : si les listes changent ⇒ commit sur main + release publiée ; sinon no-op succès. Vérifier si release : zip = contenu ≈ v2026.10.1 (helpers présents), `unzip -l | grep "wsusoffline/\."` vide, version embarquée = nouvelle, notes contiennent les comptes N/M/K.
- [ ] **Step 3: Aligner le local** — Run: `git checkout publish && git pull origin main` (ou `git rebase main`) Expected: branche locale alignée sur la nouvelle ligne main.
- [ ] **Step 4: Clôturer** — rapport final à l'humain ; le schedule du 15 prend le relais.
