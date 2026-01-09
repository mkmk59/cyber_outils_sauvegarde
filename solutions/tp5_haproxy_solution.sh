#!/bin/bash
# =============================================================================
# TP5 Solution: Sticky Sessions HAProxy
#Martial HOCQUETTE / Mark GYURJYAN
# =============================================================================
# Objectifs:
#   1. Comprendre la persistance de session
#   2. Configurer différents types de sticky sessions
#   3. Tester la persistence des connexions
#   4. Gérer les tables de persistence
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP5: Sticky Sessions HAProxy"
echo "============================================"
echo ""

# Démarrer docker-compose
echo "[INFO] Démarrage des containers Docker..."
docker-compose up -d
sleep 10
echo "[OK] Containers démarrés"
echo ""

# =============================================================================
# Exercice 5.1: Cookie-based Persistence
# =============================================================================
echo ">>> Exercice 5.1: Cookie-based Persistence"
echo ""

echo "[INFO] État initial (pas de sticky sessions):"
docker exec haproxy1 bash -c '/scripts/sticky-session.sh show'
echo ""

echo "[INFO] Configurer la persistence par cookie SERVERID:"
docker exec haproxy1 bash -c '/scripts/sticky-session.sh enable cookie'
sleep 2
echo ""

echo "[INFO] Configuration après activation du cookie:"
docker exec haproxy1 bash -c '/scripts/sticky-session.sh show'
echo ""

echo "[INFO] Tester la persistence par cookie (5 requêtes avec cookie):"
echo "  Première requête (reçoit un cookie):"
docker exec backend1 bash -c 'curl -s -D /tmp/headers.txt http://172.30.0.11 2>&1' | grep -i "hostname"
echo "  Afficher le cookie reçu:"
docker exec backend1 bash -c 'cat /tmp/headers.txt 2>/dev/null | grep -i "set-cookie" || echo "No cookies"'
echo ""

echo "[INFO] Requêtes suivantes (cookie envoyé, devrait aller au même serveur):"
echo "  Avec persistence par cookie, le trafic devrait rester sur le même serveur"
docker exec backend1 bash -c 'COOKIE=$(curl -s http://172.30.0.11 | grep -oP "srv\d" | head -1); for i in {1..5}; do curl -s -b "SERVERID=$COOKIE" http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[OK] Cookie-based persistence testée"
echo ""

# =============================================================================
# Exercice 5.2: Source IP Persistence
# =============================================================================
echo ">>> Exercice 5.2: Source IP Persistence"
echo ""

echo "[INFO] Configurer la persistence par IP source:"
docker exec haproxy1 bash -c '/scripts/sticky-session.sh enable source'
sleep 2
echo ""

echo "[INFO] Configuration après activation du source IP:"
docker exec haproxy1 bash -c '/scripts/sticky-session.sh show'
echo ""

echo "[INFO] Tester la persistence par source IP (10 requêtes):"
echo "  Chaque IP source devrait toujours aller au même serveur backend:"
docker exec backend1 bash -c 'for i in {1..10}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[OK] Source IP persistence testée"
echo ""

# =============================================================================
# Exercice 5.3: Table de persistence
# =============================================================================
echo ">>> Exercice 5.3: Table de persistence"
echo ""

echo "[INFO] Afficher la configuration actuelle:"
docker exec haproxy1 bash -c '/scripts/sticky-session.sh show'
echo ""

echo "[INFO] Vérifier les stats HAProxy (sticky sessions actives):"
docker exec haproxy1 bash -c "echo 'show stat' | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E 'web_backend|BACKEND' | head -5 || echo 'Stats non disponibles'"
echo ""

echo "[INFO] Générer du trafic pour remplir la table de persistence (20 requêtes):"
docker exec backend1 bash -c 'for i in {1..20}; do curl -s http://172.30.0.11 > /dev/null 2>&1; done'
echo "[OK] Trafic généré"
echo ""

echo "[INFO] Vérifier les infos de stick table:"
docker exec haproxy1 bash -c "echo 'show table web_backend' | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -20 || echo 'Table non accessible'"
echo ""

echo "[INFO] État de la table de persistence:"
echo "  La table de persistence stocke les associations IP source -> serveur backend"
echo "  Cela permet de maintenir la persistence sans dépendre des cookies"
echo ""

# =============================================================================
# Exercice 5.4: Comparaison des méthodes
# =============================================================================
echo ">>> Exercice 5.4: Comparaison des méthodes de persistence"
echo ""

echo "[INFO] Récapitulatif des types de sticky sessions:"
echo ""
echo "1. COOKIE (insert)"
echo "   - HAProxy insère un cookie SERVERID"
echo "   - Persiste côté client (dans le navigateur)"
echo "   - Meilleure pour les sessions longues"
echo "   - Les clients doivent accepter les cookies"
echo ""
echo "2. SOURCE"
echo "   - Basé sur l'adresse IP source du client"
echo "   - Persiste dans la stick table HAProxy"
echo "   - Meilleure pour les protocoles sans état"
echo "   - Pas dépendant des cookies"
echo ""
echo "3. PREFIX"
echo "   - Ajoute un identifiant serveur au cookie existant"
echo "   - Combine la persistence avec les cookies applicatifs"
echo ""

echo "[INFO] Test final - Vérifier la distribution avec persistence:"
docker exec backend1 bash -c 'echo "Requêtes avec persistence par source IP:" && for i in {1..5}; do curl -s http://172.30.0.11 2>&1; done' | grep -i "hostname" | sort | uniq -c
echo ""

echo "[OK] Comparaison des méthodes complétée"
echo ""

# =============================================================================
# Résumé final
# =============================================================================
echo "============================================"
echo "  TP5 COMPLETE AVEC SUCCES!"
echo "============================================"
echo ""
echo "Résumé des configurations:"
echo "  [✓] Exercice 5.1: Cookie-based persistence (SERVERID)"
echo "  [✓] Exercice 5.2: Source IP persistence"
echo "  [✓] Exercice 5.3: Gestion de la table de persistence"
echo "  [✓] Exercice 5.4: Comparaison des méthodes"
echo ""
echo "Points clés appris:"
echo "  - Persistence par cookie: Client-side storage"
echo "  - Persistence par IP source: Basé sur l'adresse IP"
echo "  - Stick table: Stockage des associations IP -> serveur"
echo "  - Persistance transparente du point de vue client"
echo "  - Améliore l'expérience utilisateur pour les sessions stateful"
echo ""
echo "Commandes utiles:"
echo "  docker exec haproxy1 /scripts/sticky-session.sh show"
echo "  docker exec haproxy1 /scripts/sticky-session.sh enable cookie"
echo "  docker exec haproxy1 /scripts/sticky-session.sh enable source"
echo "  docker exec haproxy1 /scripts/sticky-session.sh disable"
echo "  docker exec haproxy1 echo 'show table web_backend' | socat stdio /var/run/haproxy/admin.sock"
echo ""
