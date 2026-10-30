# Self-hosted GitHub Actions runner (Linux) pour WSUS Offline Next — job catalogue.
# Pattern: MermaidStudio/self-hosted (runner éphémère recyclé par compose).
# Le tag suit la release courante de actions/runner — épinglé par digest (CISH-03).
# Ce conteneur exécute les jobs CI de CE repo : toute mise à jour de l'image de
# base est désormais une décision délibérée et visible dans le diff, jamais un
# drift silencieux d'un tag flottant. Procédure de refresh : relancer
# `docker buildx imagetools inspect ghcr.io/actions/actions-runner:2.338.2`,
# comparer le Digest affiché au pin ci-dessous, relire les release notes
# upstream de la nouvelle version, puis mettre à jour le tag ET le digest
# ensemble dans un commit dédié. Ne jamais inventer ni tronquer un digest : la
# valeur est sondée, et si le drift gate échoue la réponse est un refresh
# délibéré, pas une nouvelle supposition. Le pin est le digest de l'INDEX OCI
# multi-arch (résolu en direct le 2026-10-30) ; docker résout lui-même le
# manifeste enfant de la plateforme au moment du build.
FROM ghcr.io/actions/actions-runner:2.338.2@sha256:759a1d94a15b05941aba5196974ff43fe15b4cbba29b694b35cbc32a1166b232

USER root
# cabextract + xsltproc: extraction du catalogue wsusscn2.cab côté Linux
# (équivalent de expand.exe + cscript/XSLT.vbs côté Windows), jq pour le token.
RUN apt-get update \
 && apt-get install -y --no-install-recommends cabextract xsltproc jq curl wget \
 && rm -rf /var/lib/apt/lists/*
# node embarqué de l'image runner, exposé pour le build de contrôle (npm).
ENV PATH=/home/runner/externals/node24/bin:${PATH}

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
USER runner
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
