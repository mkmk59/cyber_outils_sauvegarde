FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    borgbackup openssh-client && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /data /root/.ssh /backup-scripts

COPY backup.sh /backup-scripts/backup.sh
RUN chmod +x /backup-scripts/backup.sh

CMD ["bash"]
