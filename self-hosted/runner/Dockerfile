# Self-hosted GitHub Actions runner (Linux) pour WSUS Offline Next — job catalogue.
# Pattern: MermaidStudio/self-hosted (runner éphémère recyclé par compose).
# Le tag suit la release courante de actions/runner.
FROM ghcr.io/actions/actions-runner:2.338.2

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
