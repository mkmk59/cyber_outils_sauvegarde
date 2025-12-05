#!/bin/bash
set -e

echo "[INFO] Configuration du client Restic..."

# Verification des variables d'environnement
if [ -z "$RESTIC_REPOSITORY" ]; then
    echo "[ERREUR] RESTIC_REPOSITORY non defini"
    exit 1
fi

if [ -z "$RESTIC_PASSWORD" ]; then
    echo "[ERREUR] RESTIC_PASSWORD non defini"
    exit 1
fi

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "[ERREUR] Credentials MinIO non definis (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY)"
    exit 1
fi

echo "[INFO] Repository Restic: $RESTIC_REPOSITORY"
echo "[INFO] Sources a sauvegarder:"
ls -la /backup-source/

echo "[INFO] Client Restic pret. Utilisez les scripts suivants:"
echo "       - ./init-repo.sh    : Initialiser le repository Restic"
echo "       - ./backup.sh       : Sauvegarder la configuration Borg"
echo "       - ./restore.sh      : Restaurer la configuration Borg"
echo "       - ./list.sh         : Lister les snapshots"

exec "$@"
