#!/bin/bash
set -e

export BORG_PASSPHRASE="${BORG_PASSPHRASE:-changeme}"

SERVER="${BORG_SERVER_HOST:-borg-server}"
PORT="${BORG_SERVER_PORT:-22}"
USER="${BORG_USER:-borg}"

export BORG_REPO="ssh://${USER}@${SERVER}:${PORT}/var/borg/repos/main"

echo "[INFO] Test de connexion SSH..."
ssh -o StrictHostKeyChecking=no -p $PORT $USER@$SERVER "echo Connexion OK"

echo "[INFO] Initialisation du dépôt si nécessaire..."
ssh -p $PORT $USER@$SERVER "borg init --encryption=repokey /var/borg/repos/main || true"

ARCHIVE_NAME=$(date +'%Y-%m-%d_%H-%M-%S')

echo "[INFO] Création de l'archive $ARCHIVE_NAME..."
borg create --stats "$BORG_REPO::$ARCHIVE_NAME" /data

echo "[INFO] Rotation..."
borg prune -v "$BORG_REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6

echo "[INFO] Sauvegarde terminée."
