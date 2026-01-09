# =============================================================================
# Ceph OSD - Workshop Stockage Distribue
# =============================================================================

FROM debian:bookworm-slim

LABEL maintainer="Workshop Ceph"
LABEL description="Ceph OSD Node - Simulation pour workshop HA"

ENV CEPH_NODE_TYPE=osd
ENV CEPH_NODE_NAME=osd1
ENV CEPH_OSD_ID=0
ENV CEPH_NODE_IP=172.20.0.21

RUN apt-get update && apt-get install -y --no-install-recommends \
    procps \
    net-tools \
    iputils-ping \
    iproute2 \
    curl \
    vim \
    less \
    htop \
    jq \
    bc \
    python3 \
    bash-completion \
    uuid-runtime \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/ceph \
    && mkdir -p /var/lib/ceph/osd/ceph-0 \
    && mkdir -p /var/lib/ceph/state \
    && mkdir -p /var/log/ceph \
    && mkdir -p /scripts \
    && mkdir -p /data/osd

# Creer un fichier sparse pour simuler le disque OSD (1GB)
RUN dd if=/dev/zero of=/data/osd/osd-disk.img bs=1M count=0 seek=1024

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 6800-6810

VOLUME ["/var/lib/ceph/osd", "/etc/ceph", "/data"]

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]
