FROM debian:bookworm-slim

# Installation des paquets necessaires
RUN apt-get update && apt-get install -y \
    borgbackup \
    openssh-client \
    postgresql-client \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Creation des repertoires necessaires
RUN mkdir -p /root/.ssh \
    && mkdir -p /backup-scripts \
    && mkdir -p /tmp/backup \
    && chmod 700 /root/.ssh

# Configuration SSH pour accepter automatiquement les nouvelles cles
RUN echo "Host *\n\tStrictHostKeyChecking accept-new\n\tUserKnownHostsFile /root/.ssh/known_hosts" > /root/.ssh/config \
    && chmod 600 /root/.ssh/config

# Copie des scripts
COPY scripts/ /backup-scripts/
RUN chmod +x /backup-scripts/*.sh

# Script d'entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /backup-scripts

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
