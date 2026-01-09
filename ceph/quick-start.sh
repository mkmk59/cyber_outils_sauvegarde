#!/bin/bash
# =============================================================================
# DÉPLOIEMENT CEPH SIMPLIFIÉ POUR FORMATION
# =============================================================================
# Cette approche utilise un conteneur unique avec simulation des composants
# Idéal pour l'apprentissage sans les complexités d'un vrai cluster
# =============================================================================

set -e

echo "============================================================================="
echo "    ENVIRONNEMENT CEPH POUR FORMATION PS/PCA - CYBERSÉCURITÉ"
echo "============================================================================="

# Vérifier Docker
if ! command -v docker &> /dev/null; then
    echo "ERREUR: Docker n'est pas installé"
    exit 1
fi

# Nettoyage
echo "[1/6] Nettoyage de l'environnement précédent..."
docker rm -f ceph-training 2>/dev/null || true
docker network rm ceph-net 2>/dev/null || true

# Création du réseau
echo "[2/6] Création du réseau Docker..."
docker network create --subnet=172.20.0.0/16 ceph-net

# Téléchargement de l'image
echo "[3/6] Téléchargement de l'image Ceph (peut prendre plusieurs minutes)..."
docker pull --platform linux/amd64 quay.io/ceph/demo:latest

# Lancement du conteneur
echo "[4/6] Lancement du conteneur Ceph..."
docker run -d \
    --name ceph-training \
    --platform linux/amd64 \
    --privileged \
    --network ceph-net \
    --ip 172.20.0.10 \
    -p 8080:8080 \
    -p 7480:7480 \
    -p 6789:6789 \
    -p 3300:3300 \
    -e MON_IP=172.20.0.10 \
    -e CEPH_PUBLIC_NETWORK=172.20.0.0/16 \
    -e CEPH_DEMO_UID=training \
    -e CEPH_DEMO_ACCESS_KEY=training-key \
    -e CEPH_DEMO_SECRET_KEY=training-secret \
    -e RGW_FRONTEND_PORT=7480 \
    -e OSD_TYPE=directory \
    quay.io/ceph/demo:latest demo

# Attente
echo "[5/6] Attente du démarrage des services Ceph (60 secondes)..."
sleep 60

# Vérification
echo "[6/6] Vérification du cluster Ceph..."
if docker exec ceph-training ceph status; then
    echo ""
    echo "============================================================================="
    echo "SUCCESS: Cluster Ceph prêt!"
    echo "============================================================================="
    echo ""
    echo "Accès au conteneur : docker exec -it ceph-training bash"
    echo "Dashboard Ceph     : http://localhost:8080"
    echo "API RGW (S3)       : http://localhost:7480"
else
    echo ""
    echo "ERREUR: Le cluster Ceph n'a pas démarré correctement"
    echo "Vérifiez les logs : docker logs ceph-training"
    exit 1
fi

echo ""
echo "============================================================================="
