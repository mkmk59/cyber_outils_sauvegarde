#!/bin/bash
set -e

echo "=========================================="
echo "SAUVEGARDE CONFIGURATION BORG VERS MINIO"
echo "=========================================="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Verification du repository
echo "[INFO] Verification du repository Restic..."
if ! restic snapshots > /dev/null 2>&1; then
    echo "[ERREUR] Le repository Restic n'est pas initialise"
    echo "[INFO] Executez d'abord: ./init-repo.sh"
    exit 1
fi

# Liste des fichiers a sauvegarder
echo "[INFO] Fichiers a sauvegarder:"
echo "  - /backup-source/borg-client-ssh (cles SSH client)"
echo "  - /backup-source/borg-server-ssh (cles SSH serveur)"
echo "  - /backup-source/borg-repo (repository Borg)"
echo ""

# Verification des sources
if [ ! -d "/backup-source/borg-client-ssh" ]; then
    echo "[WARN] Repertoire borg-client-ssh non trouve"
fi

if [ ! -d "/backup-source/borg-server-ssh" ]; then
    echo "[WARN] Repertoire borg-server-ssh non trouve"
fi

# Sauvegarde avec Restic
echo "[INFO] Demarrage de la sauvegarde..."

restic backup \
    --verbose \
    --tag "borg-config" \
    --tag "$(date '+%Y%m%d')" \
    /backup-source/borg-client-ssh \
    /backup-source/borg-server-ssh \
    /backup-source/borg-repo

BACKUP_STATUS=$?

if [ $BACKUP_STATUS -eq 0 ]; then
    echo ""
    echo "[OK] Sauvegarde terminee avec succes!"
    echo ""

    # Affichage du dernier snapshot
    echo "[INFO] Dernier snapshot:"
    restic snapshots --last 1

    # Nettoyage des anciens snapshots (garder les 7 derniers)
    echo ""
    echo "[INFO] Nettoyage des anciens snapshots (retention: 7 derniers)..."
    restic forget --keep-last 7 --prune

    echo ""
    echo "=========================================="
    echo "SAUVEGARDE TERMINEE"
    echo "=========================================="
else
    echo ""
    echo "[ERREUR] La sauvegarde a echoue avec le code: $BACKUP_STATUS"
    exit $BACKUP_STATUS
fi
