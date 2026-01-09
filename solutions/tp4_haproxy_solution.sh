#!/bin/bash
# =============================================================================
# TP4 Solution: Health Checks HAProxy
# =============================================================================
# Objectifs:
#   1. Configurer différents types de health checks
#   2. Comprendre les paramètres de détection
#   3. Gérer les serveurs défaillants
#   4. Tester le comportement avec des pannes simulées
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP4: Health Checks HAProxy"
echo "============================================"
echo ""

# Démarrer docker-compose
echo "[INFO] Démarrage des containers Docker..."
docker-compose up -d
sleep 10
echo "[OK] Containers démarrés"
echo ""

# =============================================================================
# Exercice 4.1: Health Check HTTP
# =============================================================================
echo ">>> Exercice 4.1: Health Check HTTP"
echo ""

echo "[INFO] Configuration actuelle des health checks:"
docker exec haproxy1 bash -c '/scripts/health-check.sh status'
echo ""

echo "[INFO] Tester les health checks:"
docker exec haproxy1 bash -c '/scripts/health-check.sh test'
echo ""

echo "[INFO] Explication des paramètres:"
echo "  inter: Intervalle entre les checks (2000ms = 2s)"
echo "  fall:  Nombre d'échecs avant de marquer le serveur DOWN (3)"
echo "  rise:  Nombre de succès avant de marquer le serveur UP (2)"
echo ""

echo "[OK] Health Check HTTP configuré et fonctionnel"
echo ""

# =============================================================================
# Exercice 4.2: Health Check avancé
# =============================================================================
echo ">>> Exercice 4.2: Health Check avancé"
echo ""

echo "[INFO] Configuration d'une vérification HTTP avec endpoint spécifique:"
docker exec haproxy1 bash -c '/scripts/health-check.sh configure httpchk'
sleep 1
echo ""

echo "[INFO] Afficher la configuration modifiée:"
docker exec haproxy1 bash -c '/scripts/health-check.sh status'
echo ""

echo "[INFO] Modification de l'intervalle de check (3000ms):"
docker exec haproxy1 bash -c '/scripts/health-check.sh interval 3000'
sleep 1
echo ""

echo "[INFO] Modification des seuils (rise=3, fall=5):"
docker exec haproxy1 bash -c '/scripts/health-check.sh threshold 3 5'
sleep 1
echo ""

echo "[OK] Health Check avancé configuré"
echo ""

# =============================================================================
# Exercice 4.3: Simulation de panne
# =============================================================================
echo ">>> Exercice 4.3: Simulation de panne"
echo ""

echo "[INFO] État initial des backends:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | head -30
echo ""

echo "[INFO] Simuler une panne sur backend2:"
docker exec haproxy1 bash -c '/scripts/simulate-failure.sh backend backend2'
sleep 3
echo ""

echo "[INFO] État après la panne de backend2:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | head -30
echo ""

echo "[INFO] Vérifier que le trafic est redirigé (5 requêtes):"
echo "  Distribution sans backend2 (devrait alterner entre backend1 et backend3):"
docker exec backend1 bash -c 'for i in {1..5}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[INFO] Test de distribution avec backend2 en maintenance:"
docker exec haproxy1 bash -c '/scripts/backend-manage.sh test'
echo ""

echo "[INFO] Restaurer backend2:"
docker exec haproxy1 bash -c 'echo "set server web_backend/backend2 state ready" | socat stdio /var/run/haproxy/admin.sock' 2>/dev/null || docker exec haproxy1 bash -c '/scripts/backend-manage.sh enable web_backend backend2'
sleep 2
echo ""

echo "[INFO] État après restauration de backend2:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | head -30
echo ""

echo "[INFO] Vérifier que backend2 est à nouveau actif (5 requêtes):"
echo "  Distribution avec tous les backends actifs:"
docker exec backend1 bash -c 'for i in {1..5}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[OK] Simulation de panne testée"
echo ""

# =============================================================================
# Exercice 4.4: Health Check TCP
# =============================================================================
echo ">>> Exercice 4.4: Health Check TCP"
echo ""

echo "[INFO] Configuration actuelle (après modifications):"
docker exec haproxy1 bash -c '/scripts/health-check.sh status'
echo ""

echo "[INFO] Test de connectivité TCP sur tous les backends:"
echo "  Vérification de la disponibilité des services sur le port 80:"
for backend in backend1:172.30.0.21 backend2:172.30.0.22 backend3:172.30.0.23; do
    name=$(echo $backend | cut -d: -f1)
    ip=$(echo $backend | cut -d: -f2)
    
    if docker exec haproxy1 bash -c "nc -z -w2 $ip 80" 2>/dev/null; then
        echo "  [$name] TCP:80 -> OK"
    else
        echo "  [$name] TCP:80 -> FAIL"
    fi
done
echo ""

echo "[INFO] Statistiques HAProxy - section backends:"
docker exec haproxy1 bash -c "echo 'show stat' | socat stdio /var/run/haproxy/admin.sock | grep web_backend || echo 'Stats non disponibles'"
echo ""

echo "[OK] Health Check TCP vérifié"
echo ""

# =============================================================================
# Résumé final
# =============================================================================
echo "============================================"
echo "  TP4 COMPLETE AVEC SUCCES!"
echo "============================================"
echo ""
echo "Résumé des configurations:"
echo "  [✓] Exercice 4.1: Health Check HTTP (inter, rise, fall)"
echo "  [✓] Exercice 4.2: Health Check avancé (httpchk, interval, threshold)"
echo "  [✓] Exercice 4.3: Simulation de panne (backend2 DOWN + recovery)"
echo "  [✓] Exercice 4.4: Health Check TCP (vérification de connectivité)"
echo ""
echo "Points clés appris:"
echo "  - inter: Fréquence de vérification (2000ms par défaut)"
echo "  - rise: Nombre de vérifications réussies pour revenir UP"
echo "  - fall: Nombre de vérifications échouées pour devenir DOWN"
echo "  - Types: TCP simple, HTTP GET, HTTP avec endpoint"
echo "  - Détection automatique des serveurs défaillants"
echo "  - Redirection du trafic en cas de panne"
echo ""
echo "Commandes utiles:"
echo "  docker exec haproxy1 /scripts/health-check.sh status"
echo "  docker exec haproxy1 /scripts/health-check.sh test"
echo "  docker exec haproxy1 /scripts/health-check.sh configure http"
echo "  docker exec haproxy1 /scripts/health-check.sh interval 3000"
echo "  docker exec haproxy1 /scripts/health-check.sh threshold 3 5"
echo "  docker exec haproxy1 /scripts/simulate-failure.sh backend backend2"
echo "  docker exec haproxy1 /scripts/backend-status.sh"
echo ""
