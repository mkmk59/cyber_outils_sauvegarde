#!/bin/bash
set -e

echo "=========================================="
echo "INITIALISATION DU REPOSITORY RESTIC"
echo "=========================================="

# Verification de la connexion a MinIO
echo "[INFO] Verification de la connexion a MinIO..."

# Attente que MinIO soit disponible
MAX_RETRIES=30
RETRY_COUNT=0
until curl -s http://minio:9000/minio/health/live > /dev/null 2>&1; do
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "[ERREUR] MinIO n'est pas accessible apres $MAX_RETRIES tentatives"
        exit 1
    fi
    echo "[INFO] Attente de MinIO... ($RETRY_COUNT/$MAX_RETRIES)"
    sleep 2
done

echo "[INFO] MinIO est accessible"

# Verification si le repository existe deja
echo "[INFO] Verification du repository Restic..."
if restic snapshots > /dev/null 2>&1; then
    echo "[INFO] Le repository Restic existe deja"
    echo "[INFO] Snapshots existants:"
    restic snapshots
else
    echo "[INFO] Initialisation du nouveau repository Restic..."
    restic init
    echo "[OK] Repository Restic initialise avec succes"
fi

echo ""
echo "=========================================="
echo "REPOSITORY RESTIC PRET"
echo "=========================================="
echo "Repository: $RESTIC_REPOSITORY"
echo ""
echo "Prochaines etapes:"
echo "  1. ./backup.sh  - Sauvegarder la configuration Borg"
echo "  2. ./list.sh    - Lister les snapshots"
echo "=========================================="
