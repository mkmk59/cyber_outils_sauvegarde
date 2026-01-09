# =============================================================================
# Backend Web Server 2 - Workshop HAProxy
# =============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Paris

# Installation des paquets
RUN apt-get update && apt-get install -y \
    nginx \
    curl \
    wget \
    vim \
    nano \
    net-tools \
    iputils-ping \
    iproute2 \
    procps \
    htop \
    stress-ng \
    && rm -rf /var/lib/apt/lists/*

# Variables
ENV BACKEND_NAME=backend2
ENV BACKEND_IP=172.30.0.22
ENV BACKEND_COLOR=green

# Copier l'entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Ports exposes
EXPOSE 80

# Entrypoint
CMD ["/entrypoint.sh"]
