#!/bin/bash
# =============================================================================
# TP2 : HAUTE DISPONIBILITÉ ET FAILOVER
# =============================================================================
# Objectifs:
#   - Tester les scénarios de failover
#   - Comprendre le comportement en cas de panne
#   - Configurer les sticky sessions
#   - Mesurer les métriques RPO/RTO
# Prérequis: TP1 complété
# =============================================================================

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

section() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"; }
info() { echo -e "${GREEN}>>>${NC} $1"; }
warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
alert() { echo -e "${RED}ALERT:${NC} $1"; }

CONTAINER="haproxy-master"

echo "============================================================================="
echo "           TP2 : HAUTE DISPONIBILITÉ ET FAILOVER"
echo "============================================================================="

# -----------------------------------------------------------------------------
# SCÉNARIO 1 : Panne d'un serveur backend
# -----------------------------------------------------------------------------
section "SCÉNARIO 1 : Panne d'un serveur backend"

cat << 'EOF'
Contexte PS/PCA :
  • Un serveur web tombe en panne
  • Le service doit rester disponible
  • Les utilisateurs ne doivent pas être impactés

Configuration :
  • 3 serveurs web (web1, web2, web3)
  • web3 est en mode "backup"
  • Health check toutes les 2 secondes
  • fall 3 : 3 échecs = DOWN
EOF

echo ""
info "État initial des serveurs :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Démarrage du test de charge en arrière-plan..."
(
    for i in {1..100}; do
        curl -s -o /dev/null -w "%{http_code} " http://localhost:80
        sleep 0.1
    done
) &
LOAD_PID=$!

sleep 2
alert "Simulation panne web1 (docker stop)..."
docker stop web1 > /dev/null 2>&1

echo ""
info "Observation du failover (10 secondes)..."
for i in {1..10}; do
    status=$(docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' 2>/dev/null | grep "web_servers,web1" | cut -d',' -f18)
    echo "  T+${i}s : web1 status = $status"
    sleep 1
done

wait $LOAD_PID 2>/dev/null || true
echo ""

info "État après failover :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Restauration de web1..."
docker start web1 > /dev/null 2>&1
sleep 5

info "État après restauration :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

cat << 'EOF'

Analyse PS/PCA :
  • RPO = 0 (pas de perte de données)
  • RTO = ~6 secondes (3 checks x 2s)
  • Requêtes en cours au moment de la panne : peuvent échouer
  • Nouvelles requêtes : redirigées automatiquement
EOF

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 2 : Panne multiple (2 serveurs)
# -----------------------------------------------------------------------------
section "SCÉNARIO 2 : Panne multiple (2 serveurs principaux)"

cat << 'EOF'
Contexte :
  • web1 ET web2 tombent en panne simultanément
  • web3 (backup) doit prendre le relais
  • Test de la résilience maximale
EOF

echo ""
info "État initial :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

alert "Simulation panne web1 ET web2..."
docker stop web1 web2 > /dev/null 2>&1

sleep 8
info "État après double panne :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Test de disponibilité (web3 backup devrait répondre) :"
for i in {1..5}; do
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "ERREUR")
    echo "  Requête $i : Serveur web$response"
    sleep 0.3
done

echo ""
info "Restauration des serveurs..."
docker start web1 web2 > /dev/null 2>&1
sleep 5

info "État final :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 3 : Maintenance planifiée avec drain
# -----------------------------------------------------------------------------
section "SCÉNARIO 3 : Maintenance planifiée (mode drain)"

cat << 'EOF'
Contexte PS/PCA :
  • Maintenance planifiée de web1
  • Objectif : zéro interruption de service
  • Les sessions en cours doivent se terminer proprement

Procédure :
  1. Mettre web1 en mode "drain"
  2. Attendre la fin des sessions existantes
  3. Effectuer la maintenance
  4. Remettre web1 en service
EOF

echo ""
info "État initial :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

info "Étape 1 : Passage de web1 en mode drain..."
docker exec $CONTAINER sh -c 'echo "set server web_servers/web1 state drain" | socat stdio /var/run/haproxy.sock'

info "État après drain :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Test : web1 ne reçoit plus de nouvelles connexions :"
for i in {1..5}; do
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "?")
    echo "  Requête $i : Serveur web$response"
    sleep 0.2
done

echo ""
info "Étape 2 : Simulation maintenance (5 secondes)..."
sleep 5

info "Étape 3 : Remise en service de web1..."
docker exec $CONTAINER sh -c 'echo "set server web_servers/web1 state ready" | socat stdio /var/run/haproxy.sock'

info "État final :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Vérification du retour de web1 dans le pool :"
for i in {1..5}; do
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "?")
    echo "  Requête $i : Serveur web$response"
    sleep 0.2
done

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 4 : Modification du poids dynamique
# -----------------------------------------------------------------------------
section "SCÉNARIO 4 : Modification dynamique des poids"

cat << 'EOF'
Contexte :
  • Canary deployment : diriger 10% du trafic vers un nouveau serveur
  • Blue/Green : basculer progressivement le trafic
  • Décommissionnement progressif
EOF

echo ""
info "Poids actuels :"
docker exec $CONTAINER sh -c 'echo "show servers state web_servers" | socat stdio /var/run/haproxy.sock'

info "Réduction du poids de web1 à 10 (sur 100)..."
docker exec $CONTAINER sh -c 'echo "set server web_servers/web1 weight 10" | socat stdio /var/run/haproxy.sock'

info "Nouveaux poids :"
docker exec $CONTAINER sh -c 'echo "show servers state web_servers" | socat stdio /var/run/haproxy.sock'

echo ""
info "Distribution du trafic avec nouveaux poids (20 requêtes) :"
declare -A count
for i in {1..20}; do
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "0")
    ((count[$response]++)) || count[$response]=1
done

echo "  web1: ${count[1]:-0} requêtes"
echo "  web2: ${count[2]:-0} requêtes"
echo "  web3: ${count[3]:-0} requêtes (backup)"

echo ""
info "Restauration du poids normal de web1..."
docker exec $CONTAINER sh -c 'echo "set server web_servers/web1 weight 100" | socat stdio /var/run/haproxy.sock'

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 5 : Sticky Sessions
# -----------------------------------------------------------------------------
section "SCÉNARIO 5 : Sticky Sessions (affinité de session)"

cat << 'EOF'
Notre configuration utilise des cookies pour les sticky sessions :

backend web_servers
    cookie SERVERID insert indirect nocache
    server web1 ... cookie web1
    server web2 ... cookie web2
    server web3 ... cookie web3

Le client reçoit un cookie "SERVERID=webX" et ses requêtes
suivantes sont toujours dirigées vers le même serveur.
EOF

echo ""
info "Test sans cookie (nouvelle session à chaque requête) :"
for i in {1..4}; do
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "?")
    echo "  Requête $i : Serveur web$response"
done

echo ""
info "Test avec cookie (même serveur pour toutes les requêtes) :"
COOKIE_JAR=$(mktemp)
for i in {1..4}; do
    response=$(curl -s -b $COOKIE_JAR -c $COOKIE_JAR http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "?")
    echo "  Requête $i : Serveur web$response"
done
rm -f $COOKIE_JAR

echo ""
info "Contenu du cookie :"
curl -s -c - http://localhost:80 2>/dev/null | grep -i serverid || echo "(Cookie visible dans les headers de réponse)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# MÉTRIQUES PS/PCA
# -----------------------------------------------------------------------------
section "MÉTRIQUES PS/PCA - SYNTHÈSE"

cat << 'EOF'
┌─────────────────────────────────────────────────────────────────────────────┐
│                    MÉTRIQUES RPO/RTO - HAPROXY                              │
├────────────────────┬────────────┬───────────────────┬───────────────────────┤
│    Scénario        │    RPO     │       RTO         │   Configuration       │
├────────────────────┼────────────┼───────────────────┼───────────────────────┤
│ 1 serveur DOWN     │     0      │  ~6s (3x2s)       │ fall 3, inter 2000    │
│ Panne réseau       │     0      │  ~6s              │ Health check TCP      │
│ Maintenance drain  │     0      │  0 (graceful)     │ set state drain       │
│ HAProxy crash      │     0      │  ~3s              │ + Keepalived          │
│ Pic de charge      │     0      │  0 (queue)        │ timeout queue 60s     │
└────────────────────┴────────────┴───────────────────┴───────────────────────┘

Recommandations pour améliorer le RTO :
  • Réduire "inter" (intervalle health check) : 1000ms au lieu de 2000ms
  • Réduire "fall" : 2 au lieu de 3
  • Attention : trop agressif = faux positifs

Exemple optimisé :
  server web1 172.20.0.21:80 check inter 1000 fall 2 rise 2
  # RTO théorique : 2 x 1s = 2 secondes
EOF

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SYNTHÈSE
# -----------------------------------------------------------------------------
section "SYNTHÈSE DU TP2"

cat << 'EOF'
Compétences acquises :

  ✓ Simulation de pannes backend
  ✓ Observation du failover automatique
  ✓ Gestion de la maintenance planifiée (drain)
  ✓ Modification dynamique des poids
  ✓ Configuration des sticky sessions
  ✓ Calcul des métriques RPO/RTO

Points clés PS/PCA :

  • HAProxy détecte automatiquement les pannes
  • Le failover est transparent pour les utilisateurs
  • Le mode drain permet une maintenance sans interruption
  • Les sticky sessions préservent les sessions utilisateur
  • Le RTO dépend de la configuration des health checks

Prochaine étape : TP3 - Sécurisation et Hardening
EOF

echo ""
echo "============================================================================="
echo "                         FIN DU TP2"
echo "============================================================================="
