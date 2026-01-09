# =============================================================================
# Ceph Monitor/Manager/Client - Workshop Stockage Distribue
# =============================================================================
# Ce conteneur simule un noeud Ceph pour l'apprentissage des concepts.
# Note: Ceph reel necessite une configuration plus complexe.
# Cette image utilise une approche simulee pour les besoins pedagogiques.
# =============================================================================

FROM debian:bookworm-slim

LABEL maintainer="Workshop Ceph"
LABEL description="Ceph Monitor/Manager Node - Simulation pour workshop HA"

# Variables d'environnement
ENV CEPH_NODE_TYPE=mon
ENV CEPH_NODE_NAME=mon1
ENV CEPH_NODE_IP=172.20.0.11
ENV CEPH_CLUSTER_NETWORK=172.20.0.0/16
ENV CEPH_PUBLIC_NETWORK=172.20.0.0/16

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
    jq \
    bc \
    # Python pour simulation
    python3 \
    python3-pip \
    # Outils AWS S3
    awscli \
    # Outils reseau
    netcat-openbsd \
    socat \
    # Bash completion
    bash-completion \
    uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

# Creer les repertoires Ceph
RUN mkdir -p /etc/ceph \
    && mkdir -p /var/lib/ceph/mon \
    && mkdir -p /var/lib/ceph/mgr \
    && mkdir -p /var/lib/ceph/osd \
    && mkdir -p /var/lib/ceph/mds \
    && mkdir -p /var/lib/ceph/radosgw \
    && mkdir -p /var/log/ceph \
    && mkdir -p /scripts \
    && mkdir -p /data

# Creer un fichier d'etat pour la simulation
RUN mkdir -p /var/lib/ceph/state \
    && echo "initialized" > /var/lib/ceph/state/cluster

# Copier l'entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Exposer les ports
EXPOSE 6789 3300 8443 9283

# Volume pour les donnees
VOLUME ["/var/lib/ceph", "/etc/ceph"]

# Point d'entree
ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
