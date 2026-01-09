#!/bin/bash
# =============================================================================
# TP3 Solution: Configuration des Backends HAProxy
# Martial HOCQUETTE / Mark GYURJYAN
# =============================================================================
# Objectifs:
#   1. Configurer des pools de serveurs (Backends)
#   2. Comprendre les algorithmes de load balancing
#   3. Gérer les poids des serveurs
#   4. Ajouter/Supprimer des serveurs dynamiquement
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP3: Configuration des Backends"
echo "============================================"
echo ""

# Démarrer docker-compose
echo "[INFO] Démarrage des containers Docker..."
docker-compose up -d
sleep 10
echo "[OK] Containers démarrés"
echo ""

# =============================================================================
# Exercice 3.1: Backend basique
# =============================================================================
echo ">>> Exercice 3.1: Backend basique"
echo ""

echo "[INFO] Voir la configuration backend actuelle:"
docker exec haproxy1 bash -c '/scripts/show-config.sh backend' | head -50
echo ""

echo "[INFO] Vérifier l'état des backends:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh'
echo ""

# =============================================================================
# Exercice 3.2: Algorithmes de Load Balancing
# =============================================================================
echo ">>> Exercice 3.2: Algorithmes de Load Balancing"
echo ""

echo "[INFO] Test avec roundrobin (défaut):"
echo "  Distribution des 10 requêtes:"
docker exec backend1 bash -c 'for i in {1..10}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[INFO] Lister les backends disponibles:"
docker exec haproxy1 bash -c '/scripts/backend-manage.sh list'
echo ""

echo "[OK] Algorithmes de load balancing testés"
echo ""

# =============================================================================
# Exercice 3.3: Poids des serveurs
# =============================================================================
echo ">>> Exercice 3.3: Poids des serveurs"
echo ""

echo "[INFO] Modification des poids:"
echo "  - backend1: 200 (plus de trafic)"
echo "  - backend3: 50 (moins de trafic)"
docker exec haproxy1 bash -c '/scripts/backend-manage.sh weight web_backend backend1 200'
docker exec haproxy1 bash -c '/scripts/backend-manage.sh weight web_backend backend3 50'
sleep 1
echo ""

echo "[INFO] Distribution avec poids (30 requêtes):"
docker exec backend1 bash -c 'for i in {1..30}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[INFO] Réinitialiser les poids (tous à 100):"
docker exec haproxy1 bash -c '/scripts/backend-manage.sh weight web_backend backend1 100'
docker exec haproxy1 bash -c '/scripts/backend-manage.sh weight web_backend backend3 100'
sleep 1
echo ""

echo "[INFO] Distribution après réinitialisation (10 requêtes):"
docker exec backend1 bash -c 'for i in {1..10}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo "[OK] Poids des serveurs testés"
echo ""

# =============================================================================
# Exercice 3.4: Ajout/Suppression de serveurs
# =============================================================================
echo ">>> Exercice 3.4: Ajout/Suppression de serveurs"
echo ""

echo "[INFO] État initial des serveurs:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | grep -E "backend[0-9]|UP|DOWN"
echo ""

echo "[INFO] Désactiver temporairement backend2:"
docker exec haproxy1 bash -c '/scripts/backend-manage.sh disable web_backend backend2'
sleep 1
echo ""

echo "[INFO] État après désactivation:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | grep -E "backend[0-9]|UP|DOWN|DRAIN"
echo ""

echo "[INFO] Tester avec backend2 désactivé (10 requêtes):"
docker exec backend1 bash -c 'for i in {1..10}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[INFO] Réactiver backend2:"
docker exec haproxy1 bash -c '/scripts/backend-manage.sh enable web_backend backend2'
sleep 1
echo ""

echo "[INFO] État après réactivation:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | grep -E "backend[0-9]|UP|DOWN"
echo ""

echo "[INFO] Tester avec tous les serveurs actifs (10 requêtes):"
docker exec backend1 bash -c 'for i in {1..10}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "============================================"
echo "  TP3 COMPLETE AVEC SUCCES!"
echo "============================================"
echo ""
echo "Resume des configurations:"
echo "  [✓] Exercice 3.1: Configuration backend basique"
echo "  [✓] Exercice 3.2: Algorithmes de load balancing (roundrobin)"
echo "  [✓] Exercice 3.3: Poids des serveurs (weight)"
echo "  [✓] Exercice 3.4: Enable/Disable de serveurs"
echo ""
echo "Commandes utiles:"
echo "  docker exec haproxy1 /scripts/show-config.sh backend"
echo "  docker exec haproxy1 /scripts/backend-status.sh"
echo "  docker exec haproxy1 /scripts/backend-manage.sh list"
echo "  docker exec haproxy1 /scripts/backend-manage.sh disable web_backend backend2"
echo "  docker exec haproxy1 /scripts/backend-manage.sh weight web_backend backend1 200"
echo ""
