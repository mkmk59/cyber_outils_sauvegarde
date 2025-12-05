FROM debian:bookworm-slim

# Installation de Restic
RUN apt-get update && apt-get install -y \
    restic \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Creation des repertoires necessaires
RUN mkdir -p /backup-source \
    && mkdir -p /backup-scripts

# Copie des scripts de sauvegarde
COPY scripts/ /backup-scripts/
RUN chmod +x /backup-scripts/*.sh

# Script d'entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /backup-scripts

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
