#!/bin/bash
set -e

echo "=========================================="
echo "LISTE DES SNAPSHOTS RESTIC"
echo "=========================================="
echo ""

# Verification du repository
if ! restic snapshots > /dev/null 2>&1; then
    echo "[ERREUR] Le repository Restic n'est pas accessible"
    echo "[INFO] Executez d'abord: ./init-repo.sh"
    exit 1
fi

# Liste des snapshots
echo "[INFO] Snapshots disponibles:"
echo ""
restic snapshots

# Statistiques
echo ""
echo "=========================================="
echo "STATISTIQUES DU REPOSITORY"
echo "=========================================="
restic stats

echo ""
echo "=========================================="
echo "COMMANDES UTILES"
echo "=========================================="
echo ""
echo "Voir le contenu d'un snapshot:"
echo "  restic ls <snapshot-id>"
echo ""
echo "Restaurer un snapshot:"
echo "  ./restore.sh <snapshot-id>"
echo "  ./restore.sh latest"
echo ""
echo "Supprimer les anciens snapshots:"
echo "  restic forget --keep-last 5 --prune"
echo ""
