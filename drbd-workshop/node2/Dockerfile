# =============================================================================
# DRBD Node 2 - Workshop Haute Disponibilite
# =============================================================================
# Ce conteneur simule un noeud DRBD pour l'apprentissage des concepts.
# Note: DRBD reel necessite l'acces au kernel (module drbd).
# Cette image utilise une simulation pour les besoins pedagogiques.
# =============================================================================

FROM debian:bookworm-slim

LABEL maintainer="Workshop DRBD"
LABEL description="DRBD Node 2 - Simulation pour workshop HA"

# Variables d'environnement
ENV DRBD_NODE_NAME=node2
ENV DRBD_NODE_IP=172.28.0.12
ENV DRBD_PEER_IP=172.28.0.11
ENV DRBD_PORT=7788
ENV DRBD_RESOURCE=r0
ENV DRBD_DEVICE=/dev/drbd0
ENV DRBD_MOUNT=/mnt/drbd

# Installation des paquets necessaires
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Outils systeme
    procps \
    net-tools \
    iputils-ping \
    iproute2 \
    curl \
    wget \
    vim \
    less \
    htop \
    bc \
    # PostgreSQL client pour TP avance
    postgresql-client \
    postgresql \
    # Outils de benchmark
    fio \
    sysbench \
    # Outils reseau
    netcat-openbsd \
    socat \
    tcpdump \
    # Outils de monitoring
    sysstat \
    dstat \
    # Bash completion
    bash-completion \
    && rm -rf /var/lib/apt/lists/*

# Creer les repertoires necessaires
RUN mkdir -p /etc/drbd.d \
    && mkdir -p /var/lib/drbd \
    && mkdir -p /mnt/drbd \
    && mkdir -p /scripts \
    && mkdir -p /data

# Creer un fichier sparse pour simuler le disque DRBD
RUN dd if=/dev/zero of=/data/drbd-disk.img bs=1M count=0 seek=1024

# Copier la configuration DRBD
COPY drbd.conf /etc/drbd.d/r0.res

# Copier les scripts (seront montes via volume)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Exposer le port DRBD
EXPOSE 7788

# Volume pour les donnees (seulement /data, /mnt/drbd sera monte via loop device)
VOLUME ["/data"]

# Point d'entree
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
