FROM debian:bookworm-slim

# Installation des paquets necessaires
RUN apt-get update && apt-get install -y \
    openssh-server \
    borgbackup \
    && rm -rf /var/lib/apt/lists/*

# Configuration SSH
RUN mkdir -p /var/run/sshd \
    && sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config \
    && sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && echo "AuthorizedKeysFile .ssh/authorized_keys" >> /etc/ssh/sshd_config

# Creation de l'utilisateur borg (sans mot de passe - authentification par cle uniquement)
RUN useradd -m -d /home/borg -s /bin/bash borg \
    && mkdir -p /home/borg/.ssh \
    && chmod 700 /home/borg/.ssh \
    && chown -R borg:borg /home/borg

# Creation du repertoire des depots Borg
RUN mkdir -p /var/borg/repos \
    && chown -R borg:borg /var/borg

# Script d'entrypoint pour configurer les cles SSH au demarrage
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/sbin/sshd", "-D"]
