# Design — CI/CD mensuel : dépendances de sécurité + rafraîchissement des mises à jour

**Date :** 2026-10-28 (v2 après builder-check)
**Statut :** proposition, en attente de validation humaine
**Repo :** CatFoxVoyager/WsusOfflineNext (public)

## Intent et pourquoi

Aujourd'hui tout est manuel : les dépendances npm portent des vulnérabilités (2 par app, dont 1 high au 2026-10-28), et les listes d'URLs statiques vieillissent sans détection. Objectif : que chaque mois, sans action humaine — (1) les PRs de mise à jour des dépendances arrivent et soient validés automatiquement, (2) le catalogue Microsoft soit re-téléchargé, les listes statiques régénérées, (3) une release GitHub publiée si (et seulement si) quelque chose a changé.

## Goals

- **Volet A** : Dependabot ouvre les PRs (npm generator, npm installer, github-actions) ; un CI gratuit sur runners hébergés valide chaque PR (tsc + vite build ×2, build dotnet win-x64).
- **Volet B** : un workflow mensuel sur runner self-hosted Windows télécharge `wsusscn2.cab`, **régénère** les listes d'URLs statiques selon une politique de fusion bornée, pousse sur `main`, puis construit et publie une release si les listes ou le code ont changé depuis le dernier tag.
- Activation des **Dependabot security updates** (PRs automatiques sur alertes CVE, indépendantes du cron).

## Non-goals

- Les migrations majeures (React 19, Vite 8, Tailwind 4, TypeScript 7) restent des PRs manuels avec adaptation de code — Dependabot les propose, l'humain décide.
- Pas d'auto-merge des PRs Dependabot.
- Pas de téléchargement de l'arbre client complet en CI (Go de données ; l'arbre `client/` n'est pas embarqué dans le repo). Le run mensuel télécharge uniquement le catalogue.
- `client/static/StaticUpdateIds-*` (194 fichiers d'IDs de révisions/KB) **hors périmètre v1** — seules les listes d'URLs sont régénérées.
- Le runner self-hosted ne lance **jamais** de workflow `pull_request` (voir Sécurité).

## Contraintes

- Repo **public** : le self-hosted runner exécute du code sur la machine de dev — surface d'attaque à verrouiller.
- Toolchain du runner en **service Windows** : le PATH de session interactive (scoop shims) n'existe pas. 7-Zip installé machine-wide (`%ProgramFiles%\7-Zip`), node/dotnet/git sur le PATH machine.
- Style projet : pas de PowerShell, scripts CMD/VBS/bash ; tools vendus dans `bin/`.
- Version : schéma `YYYY.MM.P` (2026.10.1 courante), 17 fichiers portent la version (référence : commit `339f600`).
- Les événements créés via `GITHUB_TOKEN` ne déclenchent pas d'autres workflows : le workflow mensuel **valide lui-même** le build (tsc + vite ×2) avant tout commit sur `main`.

## Architecture

```text
.github/dependabot.yml                     — 2 écosystèmes npm + github-actions, cron weekly
.github/workflows/ci.yml                   — PR validation (runs-on: ubuntu-latest, gratuit)
.github/workflows/monthly-updates.yml      — schedule mensuel + workflow_dispatch
  runs-on: [self-hosted, wson-windows]
  permissions: contents:write
  concurrency: wson-monthly (groupe unique)
ci/bump-version.cmd                        — substitution des 17 fichiers (référence 339f600)
ci/regen-static-lists.cmd                  — catalogue → extraction → fusion politique bornée
ci/validate-links.cmd                      — HEAD sur les URLs des listes (retry, UA, parallélisme ~10)
```

### Régénération des listes statiques (cœur du volet B)

**Périmètre exact** : les 83 fichiers d'URLs — `static/StaticDownloadLinks-*.txt` (81) + `static/StaticDownloadLink-wddefs-*.txt` (2), ~250 URLs. (`client/static/` = IDs, hors scope.)

**Mécanisme** : l'outillage XSLT/VBS existant (`CreateDownloadTable.vbs`, `xslt/*.xsl`, modèle `ExtractDownloadLinks-all.cmd`) est piloté par produit/langue/architecture vers un répertoire de staging. L'existant ne réécrit pas `static/` — `ci/regen-static-lists.cmd` ajoute la couche de fusion qui manque.

**Politique de fusion (arbitrage, protège les listes écurées à la main)** :
- **ADD** — URL produite par l'extraction catalogue, absente de la liste → ajoutée.
- **REMOVE** — URL de la liste dont le HEAD échoue (2 passes, 24 h d'écart) → retirée.
- **KEEP** — URL vivante mais non produite par l'extraction → **conservée** (le curage manuel gagne ; jamais de suppression aveugle au premier run).

**Validation** : HEAD avant (état des listes courantes) → régénération/fusion → HEAD après (URLs nouvellement ajoutées). Rapport par liste dans le job summary : N ajoutées, M retirées (mortes), K vivantes hors extraction.

### Workflow mensuel (étapes, dans l'ordre)

1. **Checkout** de `main`.
2. **Téléchargement** de `wsusscn2.cab` via `bin/wget64.exe` vers un cache runner (hors repo).
3. **Validation HEAD** des listes courantes.
4. **Régénération** via `ci/regen-static-lists.cmd` (politique ci-dessus).
5. **Build de contrôle** (tsc + vite ×2) — remplace le CI que `GITHUB_TOKEN` ne déclencherait pas.
6. **Commit direct sur `main`** si les listes ont changé (message `chore(static): refresh download links YYYY-MM` + rapport en body).
7. **Gate de release** : release uniquement si (listes changées) OU (`git rev-list --count <dernier-tag>..HEAD` > 0). Sinon succès « no-op ».
8. **Release** : version = `YYYY.MM.0` du mois, **patch+1 si le tag existe déjà** (règle de collision) ; `ci/bump-version.cmd`, commit, **pré-fetch des helpers runtime** (mkisofs, sigcheck/streams/Autologon, ODT — mêmes sources que le runtime, pour reproduire le contenu du zip v2026.10.1), build complet (`CompileModernApps.cmd --no-pause`), `MakeRelease.cmd <version>`, section datée dans `RELEASE_NOTES.md` (N ajoutées / M retirées / K morts sans remplacement), tag, publication GitHub Release (`WsusOfflineNext-X.Y.Z.zip` + `_hashes.txt`).

Liens morts sans remplacement : rapport + entrée dans les notes ; **ne bloquent pas** la release (bloquer stallerait le train mensuel pour toujours ; les listes sont de toute façon plus fraîches qu'aujourd'hui).

### Sécurité du runner self-hosted (repo public)

- Le workflow mensuel s'auto-exclut : `if: github.event_name != 'pull_request' && github.repository == 'CatFoxVoyager/WsusOfflineNext'`.
- Aucun workflow du repo n'utilise `pull_request_target` ; `ci.yml` ne cible que les runners hébergés.
- Settings repo : approval requise pour les PRs d'extérieurs (défaut conservé).
- Runner sous compte de service dédié (non admin), hors du repo de dev (`D:\actions-runner`), service Windows (survit au reboot).
- Le workflow cible `runs-on: [self-hosted, wson-windows]` ; le runner est enregistré avec le label custom `wson-windows` (les labels par défaut `self-hosted` restent actifs — tous les labels listés doivent matcher).

## Décisions déjà prises (par l'humain)

- Runner self-hosted **sur la machine de dev, en service Windows**.
- **Publication automatique** de la release si changements ; rien si rien n'a changé.
- **Régénération complète** des listes (pas seulement la validation), rendue sûre par la politique de fusion KEEP/ADD/REMOVE.
- **Tout sur `main`** : le runner pousse bump+tag directement. La branche locale `publish` s'aligne (`git pull`) avant les prochaines poussées.

## Décisions du builder (à contredire dans la review)

- Cron le **15 du mois à 06:00 UTC** (Patch Tuesday au plus tard le 14) + `workflow_dispatch` manuel.
- Premier mois en **dry-run** (`dry_run: true` : tout sauf commit/push/release) + étalonnage local préalable de `ci/regen-static-lists.cmd` sur un catalogue réel avant mise en service.
- HEAD avec User-Agent réaliste et retries — `msdownload` est sensible aux UA nus.
- AutoIt compile headless (validé sur cette machine) ; build du workflow identique au build manuel éprouvé.

## Laissé au builder

- Découpage exact `ci/*.cmd` vs étapes inline du YAML.
- Détails HEAD (retry, timeout, parallélisme) et du calcul `git describe`/`rev-list`.
- Pilotage précis du pipeline XSLT/VBS par produit (quel jeu `ExtractDownloadLinks`/`CreateDownloadTable` appeler avec quels paramètres pour couvrir les 83 listes).
- Installation effective du runner (`config.cmd --runasservice`, compte de service, registration token via `gh api`).
- Toggles repo via API (`PUT vulnerability-alerts`, `PUT automated-security-fixes`).

## Vérification (à quoi ressemble « fini »)

1. Une PR (Dependabot ou manuelle) déclenche `ci.yml` vert sur runners hébergés.
2. `workflow_dispatch` en dry-run : catalogue téléchargé, listes validées, rapport de fusion visible, aucune écriture sur `main`, aucune release.
3. Runner visible « Idle » dans Settings → Actions → Runners, service Windows démarré après reboot.
4. Un run réel avec listes modifiées produit : commit des listes sur `main` + release publiée, zip au contenu ≈ v2026.10.1 (helpers runtime présents), zéro entrée dev (grep `wsusoffline/\.` vide).
