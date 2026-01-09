#!/bin/bash
# =============================================================================
# TP1 : DÉCOUVERTE ET CONFIGURATION HAPROXY
# =============================================================================
# Objectifs:
#   - Comprendre l'architecture HAProxy
#   - Maîtriser les commandes de base
#   - Explorer la page de statistiques
#   - Utiliser le Runtime API
# Prérequis: Lab déployé (./deploy-lab.sh)
# =============================================================================

set -e

# Couleurs
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

section() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"; }
info() { echo -e "${GREEN}>>>${NC} $1"; }
note() { echo -e "${YELLOW}NOTE:${NC} $1"; }

CONTAINER="haproxy-master"

echo "============================================================================="
echo "            TP1 : DÉCOUVERTE ET CONFIGURATION HAPROXY"
echo "============================================================================="

# -----------------------------------------------------------------------------
# EXERCICE 1 : Vérification de l'installation
# -----------------------------------------------------------------------------
section "EXERCICE 1 : Vérification de l'installation"

info "Version de HAProxy"
docker exec $CONTAINER haproxy -v

echo ""
info "Vérification de la syntaxe de configuration"
docker exec $CONTAINER haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg

echo ""
note "Si la configuration est valide, HAProxy affiche 'Configuration file is valid'"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 2 : Exploration de la configuration
# -----------------------------------------------------------------------------
section "EXERCICE 2 : Exploration de la configuration"

info "Structure de la configuration HAProxy"
echo ""
cat << 'EOF'
La configuration HAProxy est divisée en sections :

┌─────────────────────────────────────────────────────────────────┐
│  GLOBAL                                                         │
│  └── Paramètres globaux (logs, performance, SSL...)            │
├─────────────────────────────────────────────────────────────────┤
│  DEFAULTS                                                       │
│  └── Valeurs par défaut (timeouts, mode, options)              │
├─────────────────────────────────────────────────────────────────┤
│  FRONTEND                                                       │
│  └── Points d'entrée (bind IP:port, ACL, routing)              │
├─────────────────────────────────────────────────────────────────┤
│  BACKEND                                                        │
│  └── Pools de serveurs (balance, health checks, servers)       │
└─────────────────────────────────────────────────────────────────┘
EOF

echo ""
info "Affichage des premières lignes de la configuration"
docker exec $CONTAINER head -50 /usr/local/etc/haproxy/haproxy.cfg

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 3 : Test du load balancing
# -----------------------------------------------------------------------------
section "EXERCICE 3 : Test du load balancing"

info "Envoi de plusieurs requêtes pour observer la répartition"
echo ""

for i in {1..6}; do
    echo -n "Requête $i : "
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "?")
    echo "Serveur web$response"
    sleep 0.3
done

echo ""
note "Avec l'algorithme roundrobin, les requêtes sont distribuées circulairement"
note "web3 est configuré comme 'backup' et ne reçoit du trafic que si web1 et web2 sont DOWN"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 4 : Page de statistiques
# -----------------------------------------------------------------------------
section "EXERCICE 4 : Page de statistiques"

info "La page de statistiques est accessible à : http://localhost:8404/stats"
info "Credentials : admin / P@ssw0rd_HAProxy_2024!"
echo ""

cat << 'EOF'
Informations visibles sur la page de stats :

┌─────────────────────────────────────────────────────────────────┐
│  FRONTEND STATS                                                 │
│  • Sessions courantes/max                                       │
│  • Bytes in/out                                                 │
│  • Requêtes HTTP par seconde                                    │
│  • Erreurs de connexion                                         │
├─────────────────────────────────────────────────────────────────┤
│  BACKEND STATS                                                  │
│  • État de chaque serveur (UP/DOWN/DRAIN)                      │
│  • Temps de réponse                                             │
│  • Sessions actives                                             │
│  • Health check status                                          │
├─────────────────────────────────────────────────────────────────┤
│  ACTIONS DISPONIBLES (mode admin)                               │
│  • Disable/Enable server                                        │
│  • Drain server                                                 │
│  • Set weight                                                   │
│  • Kill sessions                                                │
└─────────────────────────────────────────────────────────────────┘
EOF

echo ""
info "Test d'accès aux stats en ligne de commande :"
curl -s -u admin:P@ssw0rd_HAProxy_2024! "http://localhost:8404/stats;csv" | head -5

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 5 : Runtime API (Socket)
# -----------------------------------------------------------------------------
section "EXERCICE 5 : Runtime API (Socket Unix)"

info "Le Runtime API permet d'administrer HAProxy sans redémarrage"
echo ""

info "Commande: show info - Informations générales"
docker exec $CONTAINER sh -c 'echo "show info" | socat stdio /var/run/haproxy.sock' | head -20

echo ""
read -p "Appuyez sur Entrée pour voir les statistiques..."

info "Commande: show stat - Statistiques détaillées"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | cut -d',' -f1,2,18 | head -15

echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 6 : Commandes Runtime API essentielles
# -----------------------------------------------------------------------------
section "EXERCICE 6 : Commandes Runtime API essentielles"

cat << 'EOF'
Commandes Runtime API les plus utilisées :

┌────────────────────────────────────────────────────────────────────────────┐
│  INFORMATION                                                               │
│  • show info              : Informations générales HAProxy                │
│  • show stat              : Statistiques (format CSV)                     │
│  • show servers state     : État des serveurs                             │
│  • show sess              : Sessions actives                              │
│  • show errors            : Dernières erreurs                             │
├────────────────────────────────────────────────────────────────────────────┤
│  GESTION DES SERVEURS                                                      │
│  • disable server be/srv  : Désactiver un serveur                        │
│  • enable server be/srv   : Réactiver un serveur                         │
│  • set server be/srv state drain : Mode drain (arrêt gracieux)           │
│  • set server be/srv state ready : Retour en service                     │
│  • set server be/srv weight N    : Modifier le poids (0-256)             │
├────────────────────────────────────────────────────────────────────────────┤
│  SESSIONS                                                                  │
│  • shutdown sessions server be/srv : Fermer les sessions d'un serveur    │
│  • shutdown session <id>           : Fermer une session spécifique       │
├────────────────────────────────────────────────────────────────────────────┤
│  TABLES                                                                    │
│  • show table             : Lister les stick-tables                       │
│  • show table <name>      : Contenu d'une table                          │
│  • clear table <name>     : Vider une table                              │
└────────────────────────────────────────────────────────────────────────────┘
EOF

echo ""
info "Exemple : Afficher l'état des serveurs du backend web_servers"
docker exec $CONTAINER sh -c 'echo "show servers state web_servers" | socat stdio /var/run/haproxy.sock'

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 7 : Test de maintenance d'un serveur
# -----------------------------------------------------------------------------
section "EXERCICE 7 : Test de maintenance d'un serveur"

info "Nous allons mettre web1 en maintenance via le Runtime API"
echo ""

info "État actuel des serveurs :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Désactivation de web1..."
docker exec $CONTAINER sh -c 'echo "disable server web_servers/web1" | socat stdio /var/run/haproxy.sock'

echo ""
info "Nouvel état des serveurs :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

echo ""
info "Test de requêtes (web1 ne devrait plus recevoir de trafic) :"
for i in {1..4}; do
    echo -n "Requête $i : "
    response=$(curl -s http://localhost:80 2>/dev/null | grep -o 'server-id">[0-9]' | grep -o '[0-9]' || echo "?")
    echo "Serveur web$response"
    sleep 0.3
done

echo ""
info "Réactivation de web1..."
docker exec $CONTAINER sh -c 'echo "enable server web_servers/web1" | socat stdio /var/run/haproxy.sock'

info "État final :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 8 : Health Checks
# -----------------------------------------------------------------------------
section "EXERCICE 8 : Comprendre les Health Checks"

cat << 'EOF'
Configuration des health checks dans notre lab :

backend web_servers
    option httpchk GET /health HTTP/1.1    # Requête HTTP
    http-check expect status 200           # Réponse attendue
    
    server web1 172.20.0.21:80 check inter 2000 fall 3 rise 2
                               │     │          │      │
                               │     │          │      └── 2 checks OK pour UP
                               │     │          └── 3 échecs pour DOWN
                               │     └── Intervalle 2 secondes
                               └── Activer le health check

Timeline d'une panne :
    T+0s  : Serveur tombe en panne
    T+2s  : 1er check échoué
    T+4s  : 2ème check échoué
    T+6s  : 3ème check échoué → Serveur marqué DOWN
    T+6s  : Trafic redirigé vers autres serveurs (RTO = 6s max)
EOF

echo ""
info "Simulation d'une panne de web2 :"
docker stop web2
echo "web2 arrêté. Observation des health checks (attendre 10 secondes)..."
sleep 10

info "État des serveurs après panne :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18,19

echo ""
info "Restauration de web2..."
docker start web2
sleep 5

info "État après restauration :"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' | grep -E "^web_servers" | cut -d',' -f1,2,18,19

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SYNTHÈSE
# -----------------------------------------------------------------------------
section "SYNTHÈSE DU TP1"

cat << 'EOF'
Compétences acquises :

  ✓ Vérification de la configuration HAProxy
  ✓ Compréhension de la structure de configuration
  ✓ Test du load balancing roundrobin
  ✓ Utilisation de la page de statistiques
  ✓ Maîtrise du Runtime API (socket)
  ✓ Gestion des serveurs (disable/enable)
  ✓ Compréhension des health checks

Commandes essentielles à retenir :

  • haproxy -c -f config.cfg     : Vérifier la syntaxe
  • haproxy -sf $(pidof haproxy) : Reload graceful
  • echo "show stat" | socat ... : Statistiques via socket
  • disable/enable server        : Maintenance serveur
  • set server ... state drain   : Arrêt gracieux

Prochaine étape : TP2 - Haute Disponibilité et Failover
EOF

echo ""
echo "============================================================================="
echo "                         FIN DU TP1"
echo "============================================================================="
