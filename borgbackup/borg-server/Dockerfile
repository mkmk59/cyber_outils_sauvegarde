FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    openssh-server \
    borgbackup && \
    rm -rf /var/lib/apt/lists/*

# Préparation SSH
RUN mkdir /var/run/sshd

ARG BORG_USER=borg
ARG BORG_PASSWORD=my_secure_password

RUN useradd -m -d /home/${BORG_USER} -s /bin/bash ${BORG_USER} && \
    echo "${BORG_USER}:${BORG_PASSWORD}" | chpasswd

# Dossier des dépôts Borg
RUN mkdir -p /var/borg/repos && chown -R ${BORG_USER}:${BORG_USER} /var/borg

EXPOSE 22
CMD ["/usr/sbin/sshd","-D"]
