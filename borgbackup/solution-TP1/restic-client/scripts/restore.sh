#!/bin/bash
set -e

echo "=========================================="
echo "RESTAURATION CONFIGURATION BORG DEPUIS MINIO"
echo "=========================================="
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Verification du repository
echo "[INFO] Verification du repository Restic..."
if ! restic snapshots > /dev/null 2>&1; then
    echo "[ERREUR] Le repository Restic n'est pas accessible"
    exit 1
fi

# Affichage des snapshots disponibles
echo "[INFO] Snapshots disponibles:"
restic snapshots
echo ""

# Selection du snapshot
SNAPSHOT_ID="${1:-latest}"
echo "[INFO] Snapshot a restaurer: $SNAPSHOT_ID"
echo ""

# Repertoire de restauration
RESTORE_DIR="/tmp/restore-$(date '+%Y%m%d-%H%M%S')"
mkdir -p "$RESTORE_DIR"

echo "[INFO] Repertoire de restauration: $RESTORE_DIR"
echo ""

# Restauration
echo "[INFO] Demarrage de la restauration..."
restic restore "$SNAPSHOT_ID" --target "$RESTORE_DIR" --verbose

RESTORE_STATUS=$?

if [ $RESTORE_STATUS -eq 0 ]; then
    echo ""
    echo "[OK] Restauration terminee avec succes!"
    echo ""
    echo "[INFO] Contenu restaure:"
    find "$RESTORE_DIR" -type f | head -20
    echo ""
    echo "=========================================="
    echo "INSTRUCTIONS DE RECUPERATION"
    echo "=========================================="
    echo ""
    echo "Les fichiers ont ete restaures dans: $RESTORE_DIR"
    echo ""
    echo "Structure:"
    echo "  $RESTORE_DIR/backup-source/borg-client-ssh/  -> Cles SSH client"
    echo "  $RESTORE_DIR/backup-source/borg-server-ssh/  -> Cles SSH serveur"
    echo "  $RESTORE_DIR/backup-source/borg-repo/        -> Repository Borg"
    echo ""
    echo "Pour restaurer manuellement:"
    echo "  1. Arretez les conteneurs: docker-compose down"
    echo "  2. Copiez les fichiers vers leurs emplacements d'origine"
    echo "  3. Redemarrez: docker-compose up -d"
    echo ""
    echo "=========================================="
else
    echo ""
    echo "[ERREUR] La restauration a echoue avec le code: $RESTORE_STATUS"
    exit $RESTORE_STATUS
fi
