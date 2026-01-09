# =============================================================================
# HAProxy Master Node - Workshop Load Balancing & HA
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

# Installation des paquets
RUN apt-get update && apt-get install -y \
    haproxy \
    keepalived \
    curl \
    wget \
    vim \
    nano \
    net-tools \
    iputils-ping \
    iproute2 \
    procps \
    htop \
    tcpdump \
    openssl \
    ca-certificates \
    jq \
    socat \
    hatop \
    && rm -rf /var/lib/apt/lists/*

# Creer les repertoires necessaires
RUN mkdir -p /var/lib/haproxy \
    && mkdir -p /var/run/haproxy \
    && mkdir -p /etc/haproxy/certs \
    && mkdir -p /etc/haproxy/errors \
    && mkdir -p /var/log/haproxy

# Copier l'entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ports exposes
EXPOSE 80 443 8404 8405

# Volume pour la persistance
VOLUME ["/var/lib/haproxy"]

# Entrypoint
CMD ["/entrypoint.sh"]
