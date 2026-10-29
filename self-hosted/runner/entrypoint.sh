#!/usr/bin/env bash
# Enregistrement au premier démarrage, puis exécution durable.
# Deux modes :
#   RUNNER_TOKEN — token d'enregistrement (1 h) : utilisé UNE FOIS au premier
#     start ; l'état .runner persiste dans le conteneur (restart OK, une
#     recréation du conteneur exigera un token frais).
#   RUNNER_PAT — PAT fine-grained (Administration: RW) : mode éphémère du
#     pattern MermaidStudio (1 job = 1 registration, recycle par compose).
set -euo pipefail

: "${REPO_SLUG:?REPO_SLUG manquant (ex. CatFoxVoyager/WsusOfflineNext)}"
: "${RUNNER_NAME:?RUNNER_NAME manquant}"

api() { curl -fsSL -X POST -H "Authorization: Bearer ${RUNNER_PAT}" \
  -H "Accept: application/vnd.github+json" "https://api.github.com/repos/${REPO_SLUG}/${1}"; }

if [ -f .runner ]; then
  echo "Runner déjà enregistré — démarrage direct."
elif [ -n "${RUNNER_PAT:-}" ]; then
  cleanup() {
    rt=$(api actions/runners/remove-token | jq -r .token) || return 0
    ./config.sh remove --token "$rt" --unattended || true
  }
  trap cleanup EXIT
  echo "Registration éphémère de ${RUNNER_NAME} sur ${REPO_SLUG}..."
  token=$(api actions/runners/registration-token | jq -r .token)
  [ -n "$token" ] && [ "$token" != "null" ] || { echo "registration-token vide : PAT invalide ?" >&2; exit 1; }
  ./config.sh --url "https://github.com/${REPO_SLUG}" --token "$token" \
    --name "${RUNNER_NAME}" --labels "self-hosted,Linux,X64,wson-docker" \
    --ephemeral --unattended --replace
elif [ -n "${RUNNER_TOKEN:-}" ]; then
  echo "Registration de ${RUNNER_NAME} sur ${REPO_SLUG} (token d'enregistrement)..."
  ./config.sh --url "https://github.com/${REPO_SLUG}" --token "${RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" --labels "self-hosted,Linux,X64,wson-docker" \
    --unattended --replace
else
  echo "Ni RUNNER_TOKEN ni RUNNER_PAT fourni." >&2
  exit 1
fi

exec ./run.sh
