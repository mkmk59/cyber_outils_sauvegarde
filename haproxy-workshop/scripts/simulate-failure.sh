#!/bin/bash
# =============================================================================
# Failure Simulation Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/simulate-failure.sh [COMMAND] [TARGET]
# =============================================================================

set -e

SOCKET="/var/run/haproxy/admin.sock"

show_help() {
    cat << 'EOF'
Usage: /scripts/simulate-failure.sh [COMMAND] [TARGET]

Commands:
  backend <name>      - Simuler une panne backend
  haproxy             - Simuler une panne HAProxy
  keepalived          - Simuler une panne Keepalived
  network <backend>   - Simuler une panne reseau
  restore             - Restaurer tous les services
  slow <backend>      - Simuler un backend lent
  scenario-1          - Scenario: panne d'un backend
  scenario-2          - Scenario: panne HAProxy (failover VIP)
  scenario-3          - Scenario: pannes multiples

Examples:
  /scripts/simulate-failure.sh backend backend1
  /scripts/simulate-failure.sh haproxy
  /scripts/simulate-failure.sh restore
  /scripts/simulate-failure.sh scenario-1
EOF
}

fail_backend() {
    local backend=$1

    echo "============================================"
    echo "  SIMULATION PANNE BACKEND: $backend"
    echo "============================================"
    echo ""

    if [ -S "$SOCKET" ]; then
        echo ">>> Desactivation de $backend dans HAProxy..."
        echo "set server web_backend/$backend state maint" | socat stdio $SOCKET
        echo "[OK] $backend desactive (mode maintenance)"
    else
        echo "[ATTENTION] Socket non disponible"
        echo "Alternative: arreter le service nginx sur $backend"
    fi

    echo ""
    echo ">>> Verification:"
    /scripts/backend-manage.sh test 2>/dev/null || true
    echo ""
}

fail_haproxy() {
    echo "============================================"
    echo "  SIMULATION PANNE HAPROXY"
    echo "============================================"
    echo ""

    echo "[ATTENTION] Cette action va arreter HAProxy!"
    echo "Le failover Keepalived devrait transferer la VIP"
    echo ""

    echo ">>> Arret de HAProxy..."
    pkill haproxy || true

    echo "[OK] HAProxy arrete"
    echo ""

    echo ">>> Verification Keepalived:"
    /scripts/keepalived-status.sh vip 2>/dev/null || true
    echo ""

    echo "Note: La VIP devrait basculer vers le noeud backup"
    echo "Verifiez depuis le host: curl http://172.30.0.100/"
    echo ""
}

fail_keepalived() {
    echo "============================================"
    echo "  SIMULATION PANNE KEEPALIVED"
    echo "============================================"
    echo ""

    echo ">>> Arret de Keepalived..."
    pkill keepalived || true

    echo "[OK] Keepalived arrete"
    echo ""

    echo ">>> La VIP sera relachee"
    echo ">>> Le noeud backup devrait prendre le relais"
    echo ""

    ip addr show eth0 | grep -E "inet "
    echo ""
}

simulate_network() {
    local backend=$1

    echo "============================================"
    echo "  SIMULATION PANNE RESEAU: $backend"
    echo "============================================"
    echo ""

    local ip=""
    case $backend in
        backend1) ip="172.30.0.21" ;;
        backend2) ip="172.30.0.22" ;;
        backend3) ip="172.30.0.23" ;;
        *) echo "[ERREUR] Backend inconnu"; exit 1 ;;
    esac

    echo ">>> Blocage du trafic vers $ip..."
    iptables -A OUTPUT -d $ip -j DROP 2>/dev/null || echo "[INFO] iptables non disponible"

    echo "[OK] Trafic vers $backend ($ip) bloque"
    echo ""

    echo ">>> Les health checks devraient echouer"
    echo ">>> Le backend sera marque DOWN apres quelques secondes"
    echo ""
}

simulate_slow() {
    local backend=$1

    echo "============================================"
    echo "  SIMULATION BACKEND LENT: $backend"
    echo "============================================"
    echo ""

    echo "[INFO] Cette simulation change le poids du backend"
    echo ">>> Reduction du poids de $backend a 1..."

    if [ -S "$SOCKET" ]; then
        echo "set server web_backend/$backend weight 1" | socat stdio $SOCKET
        echo "[OK] Poids reduit"
    else
        echo "[ERREUR] Socket non disponible"
    fi
    echo ""
}

restore_all() {
    echo "============================================"
    echo "  RESTAURATION DES SERVICES"
    echo "============================================"
    echo ""

    # Restaurer HAProxy
    echo ">>> Verification/demarrage HAProxy..."
    if ! pgrep -x haproxy > /dev/null; then
        haproxy -f /etc/haproxy/haproxy.cfg -D
        echo "[OK] HAProxy demarre"
    else
        echo "[OK] HAProxy deja en cours"
    fi

    # Restaurer Keepalived
    echo ">>> Verification/demarrage Keepalived..."
    if ! pgrep -x keepalived > /dev/null; then
        keepalived --dont-fork --log-console &
        sleep 2
        echo "[OK] Keepalived demarre"
    else
        echo "[OK] Keepalived deja en cours"
    fi

    # Restaurer les backends dans HAProxy
    echo ">>> Reactivation de tous les backends..."
    if [ -S "$SOCKET" ]; then
        for server in backend1 backend2 backend3; do
            echo "set server web_backend/$server state ready" | socat stdio $SOCKET 2>/dev/null || true
            echo "set server web_backend/$server weight 100" | socat stdio $SOCKET 2>/dev/null || true
        done
        echo "[OK] Backends reactives"
    fi

    # Nettoyer iptables
    echo ">>> Nettoyage des regles iptables..."
    iptables -F OUTPUT 2>/dev/null || true
    echo "[OK] Regles nettoyees"

    echo ""
    echo ">>> Verification finale:"
    /scripts/backend-manage.sh test 2>/dev/null || true
    echo ""
}

scenario_1() {
    echo "============================================"
    echo "  SCENARIO 1: Panne d'un backend"
    echo "============================================"
    echo ""

    echo ">>> Etape 1: Etat initial"
    /scripts/backend-manage.sh test 2>/dev/null || true

    echo ">>> Etape 2: Simulation panne backend1"
    fail_backend backend1

    echo ">>> Etape 3: Test du load balancing"
    echo "Les requetes devraient etre distribuees sur backend2 et backend3"
    echo ""
    for i in 1 2 3 4 5; do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  Requete $i: ${response:-erreur}"
    done

    echo ""
    echo ">>> Etape 4: Restauration"
    if [ -S "$SOCKET" ]; then
        echo "set server web_backend/backend1 state ready" | socat stdio $SOCKET
        echo "[OK] backend1 reactive"
    fi

    echo ""
    echo "[OK] Scenario 1 termine"
    echo ""
}

scenario_2() {
    echo "============================================"
    echo "  SCENARIO 2: Failover HAProxy"
    echo "============================================"
    echo ""

    echo "[INFO] Ce scenario doit etre execute sur haproxy1 (master)"
    echo ""

    echo ">>> Etape 1: Verification de la VIP"
    /scripts/keepalived-status.sh vip 2>/dev/null || true

    echo ">>> Etape 2: Arret de HAProxy (declenchement failover)"
    echo "[ATTENTION] HAProxy va etre arrete!"
    echo ""

    pkill haproxy || true

    echo "[OK] HAProxy arrete"
    echo ""

    echo ">>> Etape 3: Verification"
    echo "La VIP devrait basculer vers haproxy2"
    echo ""
    echo "Depuis le host, verifiez:"
    echo "  curl http://172.30.0.100/"
    echo "  docker exec haproxy2 /scripts/keepalived-status.sh vip"
    echo ""

    echo ">>> Etape 4: Restauration automatique dans 10 secondes..."
    sleep 10

    haproxy -f /etc/haproxy/haproxy.cfg -D
    echo "[OK] HAProxy redemarre"
    echo ""

    echo "[OK] Scenario 2 termine"
    echo ""
}

scenario_3() {
    echo "============================================"
    echo "  SCENARIO 3: Pannes multiples"
    echo "============================================"
    echo ""

    echo ">>> Etape 1: Etat initial"
    /scripts/backend-manage.sh test 2>/dev/null || true

    echo ">>> Etape 2: Panne backend1"
    if [ -S "$SOCKET" ]; then
        echo "set server web_backend/backend1 state maint" | socat stdio $SOCKET
    fi
    echo "[SIMULE] backend1 en panne"

    echo ""
    echo ">>> Etape 3: Panne backend2"
    if [ -S "$SOCKET" ]; then
        echo "set server web_backend/backend2 state maint" | socat stdio $SOCKET
    fi
    echo "[SIMULE] backend2 en panne"

    echo ""
    echo ">>> Etape 4: Test - seul backend3 devrait repondre"
    for i in 1 2 3 4 5; do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  Requete $i: ${response:-erreur}"
    done

    echo ""
    echo ">>> Etape 5: Panne backend3 (tous les backends down)"
    if [ -S "$SOCKET" ]; then
        echo "set server web_backend/backend3 state maint" | socat stdio $SOCKET
    fi
    echo "[SIMULE] backend3 en panne"

    echo ""
    echo ">>> Etape 6: Test - devrait retourner 503"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost/ 2>/dev/null)
    echo "  HTTP Code: $http_code (attendu: 503)"

    echo ""
    echo ">>> Etape 7: Restauration progressive"
    sleep 2
    if [ -S "$SOCKET" ]; then
        echo "set server web_backend/backend1 state ready" | socat stdio $SOCKET
        echo "[OK] backend1 restaure"
        sleep 1

        echo "set server web_backend/backend2 state ready" | socat stdio $SOCKET
        echo "[OK] backend2 restaure"
        sleep 1

        echo "set server web_backend/backend3 state ready" | socat stdio $SOCKET
        echo "[OK] backend3 restaure"
    fi

    echo ""
    echo ">>> Etape 8: Verification finale"
    /scripts/backend-manage.sh test 2>/dev/null || true

    echo "[OK] Scenario 3 termine"
    echo ""
}

# Main
case "${1:-help}" in
    backend)
        if [ -z "$2" ]; then
            echo "Usage: $0 backend <backend_name>"
            exit 1
        fi
        fail_backend "$2"
        ;;
    haproxy)
        fail_haproxy
        ;;
    keepalived)
        fail_keepalived
        ;;
    network)
        if [ -z "$2" ]; then
            echo "Usage: $0 network <backend_name>"
            exit 1
        fi
        simulate_network "$2"
        ;;
    slow)
        if [ -z "$2" ]; then
            echo "Usage: $0 slow <backend_name>"
            exit 1
        fi
        simulate_slow "$2"
        ;;
    restore)
        restore_all
        ;;
    scenario-1)
        scenario_1
        ;;
    scenario-2)
        scenario_2
        ;;
    scenario-3)
        scenario_3
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Commande inconnue: $1"
        show_help
        exit 1
        ;;
esac
