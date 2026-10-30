#!/usr/bin/env bash
# Enregistrement au premier démarrage, puis exécution durable.
# Cycle de vie (CISH-01) : run.sh tourne en ENFANT du shell — plus jamais en
# exec-form, qui remplaçait l'image du shell et tuait le trap EXIT (le
# cleanup était du code mort). Le cleanup s'exécute donc après la sortie de
# l'enfant comme sur TERM/INT : signal transmis à l'enfant (qui est récupéré
# avant la sortie), code de sortie de l'enfant propagé comme code de sortie
# du conteneur.
# Deux modes :
#   RUNNER_TOKEN (mode par défaut, inchangé) — token d'enregistrement (1 h) :
#     utilisé UNE FOIS au premier start ; l'état .runner persiste dans le
#     conteneur (restart OK, une recréation du conteneur exigera un token
#     frais). Le token part toujours sur l'argv du configure en mode non
#     interactif — résidu accepté (décision 16-01, cf. le cleanup).
#   RUNNER_PAT — PAT fine-grained (Administration: RW) : mode éphémère du
#     pattern MermaidStudio (1 job = 1 registration, recycle par compose).
#     Auth API par fichier d'en-têtes mode 600 (CISH-04 : le PAT ne transite
#     ni par argv ni dans l'environnement des enfants) et registration par
#     stdin (le configure de ce mode ne porte plus de credential).
set -euo pipefail

: "${REPO_SLUG:?REPO_SLUG manquant (ex. CatFoxVoyager/WsusOfflineNext)}"
: "${RUNNER_NAME:?RUNNER_NAME manquant}"

# TERM/INT dès la fenêtre de registration : un signal à n'importe quel moment
# (échec fail-closed compris) traverse le trap EXIT et ne laisse rien derrière.
run_pid=""
on_signal () {
  # $1 : signal transmis à l'enfant ; $2 : code de sortie conventionnel
  # (128+15=143 sur SIGTERM, 128+2=130 sur SIGINT). L'enfant est récupéré
  # (wait) AVANT la sortie : le trap EXIT — donc le cleanup — ne s'exécute
  # qu'une fois run.sh disparu ; un enfant qui ignorerait le signal est de
  # toute façon borné par stop_grace_period (plan 16-03).
  local sig="$1" code="$2"
  if [ -n "${run_pid}" ]; then
    kill -"${sig}" "${run_pid}" 2>/dev/null || :
    set +e
    wait "${run_pid}" 2>/dev/null
    set -e
  fi
  exit "${code}"
}
trap 'on_signal TERM 143' TERM
trap 'on_signal INT 130' INT

# CISH-04 : le PAT n'apparaît jamais sur argv — chaque appel lit l'en-tête
# depuis le fichier (forme -H @file), écrit une seule fois au démarrage PAT.
api() { curl -fsSL -X POST -H @"${PAT_HEADER_FILE}" \
  -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO_SLUG}/${1}"; }

if [ -f .runner ]; then
  echo "Runner déjà enregistré — démarrage direct."
elif [ -n "${RUNNER_PAT:-}" ]; then
  PAT_HEADER_FILE="$(mktemp)"
  chmod 600 "${PAT_HEADER_FILE}"
  printf 'Authorization: Bearer %s\n' "${RUNNER_PAT}" > "${PAT_HEADER_FILE}"
  # le PAT quitte l'environnement avant tout enfant (config.sh, run.sh,
  # listener) : l'authentification passe désormais par le fichier ci-dessus.
  unset RUNNER_PAT
  cleanup() {
    rt=$(api actions/runners/remove-token | jq -r .token) || return 0
    # Résidu accepté (décision 16-01) : ce jeton est à usage unique et vient
    # d'être généré — exposition argv ~1 s ; même analyse pour le configure
    # du mode par défaut, laissé tel quel (décision verrouillée).
    ./config.sh remove --token "$rt" --unattended || true
    # le fichier d'en-têtes est supprimé en DERNIER : le cleanup s'authentifie
    # encore avec après la disparition de la variable.
    rm -f -- "${PAT_HEADER_FILE}"
  }
  trap cleanup EXIT
  echo "Registration éphémère de ${RUNNER_NAME} sur ${REPO_SLUG}..."
  token=$(api actions/runners/registration-token | jq -r .token)
  [ -n "$token" ] && [ "$token" != "null" ] || { echo "registration-token vide : PAT invalide ?" >&2; exit 1; }
  # Registration PAT par stdin : sans mode non interactif ni credential sur
  # argv, le Listener lit le token sur son prompt d'entrée standard.
  printf '%s\n' "${token}" | ./config.sh \
    --url "https://github.com/${REPO_SLUG}" \
    --name "${RUNNER_NAME}" --labels "self-hosted,Linux,X64,wson-docker" \
    --ephemeral --replace
elif [ -n "${RUNNER_TOKEN:-}" ]; then
  echo "Registration de ${RUNNER_NAME} sur ${REPO_SLUG} (token d'enregistrement)..."
  ./config.sh --url "https://github.com/${REPO_SLUG}" --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" --labels "self-hosted,Linux,X64,wson-docker" \
    --unattended --replace
else
  echo "Ni RUNNER_TOKEN ni RUNNER_PAT fourni." >&2
  exit 1
fi

# CISH-01 : cycle enfant + wait — le trap EXIT survit à la fin de run.sh.
# RUNNER_MANUALLY_TRAP_SIG=1 active la branche « manual signal trap » du
# run.sh de l'image (actions-runner 2.338.2) : set -m + trap qui relaie le
# signal au groupe de processus du listener.
export RUNNER_MANUALLY_TRAP_SIG=1
set +e
./run.sh &
run_pid=$!
wait "${run_pid}"
run_status=$?
set -e
exit "${run_status}"
