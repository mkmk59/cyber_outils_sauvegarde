#!/bin/bash
# =============================================================================
# Backend Management Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/backend-manage.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

SOCKET="/var/run/haproxy/admin.sock"

show_help() {
    cat << 'EOF'
Usage: /scripts/backend-manage.sh [COMMAND] [OPTIONS]

Commands:
  list                          - Lister tous les backends
  status <backend> <server>     - Voir le statut d'un serveur
  enable <backend> <server>     - Activer un serveur
  disable <backend> <server>    - Desactiver un serveur
  drain <backend> <server>      - Mettre un serveur en mode drain
  weight <backend> <server> <w> - Changer le poids d'un serveur
  health <backend> <server>     - Tester la sante d'un serveur
  test                          - Tester tous les backends

Examples:
  /scripts/backend-manage.sh list
  /scripts/backend-manage.sh status web_backend backend1
  /scripts/backend-manage.sh disable web_backend backend1
  /scripts/backend-manage.sh enable web_backend backend1
  /scripts/backend-manage.sh weight web_backend backend1 50
  /scripts/backend-manage.sh test
EOF
}

check_socket() {
    if [ ! -S "$SOCKET" ]; then
        echo "[ATTENTION] Socket HAProxy non disponible"
        echo "Certaines commandes peuvent ne pas fonctionner"
        return 1
    fi
    return 0
}

list_backends() {
    echo "============================================"
    echo "  LISTE DES BACKENDS"
    echo "============================================"
    echo ""

    if check_socket; then
        echo "show servers state" | socat stdio $SOCKET 2>/dev/null || {
            echo "Backends configures:"
            grep -A5 "^backend" /etc/haproxy/haproxy.cfg 2>/dev/null || echo "Aucun backend"
        }
    else
        echo "Backends configures:"
        grep -A5 "^backend" /etc/haproxy/haproxy.cfg 2>/dev/null || echo "Aucun backend"
    fi
    echo ""
}

get_status() {
    local backend=$1
    local server=$2

    echo "============================================"
    echo "  STATUT: $backend/$server"
    echo "============================================"
    echo ""

    if check_socket; then
        echo "show servers state $backend" | socat stdio $SOCKET 2>/dev/null | grep -E "^#|$server" || echo "Serveur non trouve"
    else
        echo "Socket non disponible, test direct..."
        # Extraire l'IP du serveur depuis la config
        local ip=$(grep -A1 "server $server" /etc/haproxy/haproxy.cfg 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if [ -n "$ip" ]; then
            if curl -s --connect-timeout 2 http://$ip/health > /dev/null 2>&1; then
                echo "[UP] $server ($ip) - Health check OK"
            else
                echo "[DOWN] $server ($ip) - Health check failed"
            fi
        else
            echo "Impossible de trouver l'IP du serveur"
        fi
    fi
    echo ""
}

enable_server() {
    local backend=$1
    local server=$2

    echo "============================================"
    echo "  ACTIVATION: $backend/$server"
    echo "============================================"
    echo ""

    if check_socket; then
        echo "set server $backend/$server state ready" | socat stdio $SOCKET
        echo "[OK] Serveur $server active dans $backend"
    else
        echo "[ERREUR] Socket non disponible"
        exit 1
    fi
    echo ""
}

disable_server() {
    local backend=$1
    local server=$2

    echo "============================================"
    echo "  DESACTIVATION: $backend/$server"
    echo "============================================"
    echo ""

    if check_socket; then
        echo "set server $backend/$server state maint" | socat stdio $SOCKET
        echo "[OK] Serveur $server desactive dans $backend"
    else
        echo "[ERREUR] Socket non disponible"
        exit 1
    fi
    echo ""
}

drain_server() {
    local backend=$1
    local server=$2

    echo "============================================"
    echo "  MODE DRAIN: $backend/$server"
    echo "============================================"
    echo ""

    if check_socket; then
        echo "set server $backend/$server state drain" | socat stdio $SOCKET
        echo "[OK] Serveur $server en mode drain dans $backend"
        echo "Note: Les nouvelles connexions ne seront plus envoyees a ce serveur"
    else
        echo "[ERREUR] Socket non disponible"
        exit 1
    fi
    echo ""
}

set_weight() {
    local backend=$1
    local server=$2
    local weight=$3

    echo "============================================"
    echo "  CHANGEMENT POIDS: $backend/$server = $weight"
    echo "============================================"
    echo ""

    if check_socket; then
        echo "set server $backend/$server weight $weight" | socat stdio $SOCKET
        echo "[OK] Poids du serveur $server change a $weight"
    else
        echo "[ERREUR] Socket non disponible"
        exit 1
    fi
    echo ""
}

health_check() {
    local backend=$1
    local server=$2

    echo "============================================"
    echo "  HEALTH CHECK: $backend/$server"
    echo "============================================"
    echo ""

    # Trouver l'IP du serveur
    local ip=""
    case $server in
        backend1) ip="172.30.0.21" ;;
        backend2) ip="172.30.0.22" ;;
        backend3) ip="172.30.0.23" ;;
        *)
            ip=$(grep -A1 "server $server" /etc/haproxy/haproxy.cfg 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
            ;;
    esac

    if [ -z "$ip" ]; then
        echo "[ERREUR] IP non trouvee pour $server"
        exit 1
    fi

    echo "Test de $server ($ip)..."
    echo ""

    # Test HTTP
    echo ">>> Test HTTP (/):"
    if curl -s --connect-timeout 2 -w "\n  HTTP Code: %{http_code}\n  Time: %{time_total}s\n" http://$ip/ -o /dev/null; then
        echo "  [OK] HTTP accessible"
    else
        echo "  [ERREUR] HTTP non accessible"
    fi
    echo ""

    # Test Health endpoint
    echo ">>> Test Health (/health):"
    local health_response=$(curl -s --connect-timeout 2 http://$ip/health 2>/dev/null)
    if [ "$health_response" = "OK" ]; then
        echo "  [OK] Health check: $health_response"
    else
        echo "  [ATTENTION] Health check: ${health_response:-timeout}"
    fi
    echo ""

    # Test Status endpoint
    echo ">>> Test Status (/status):"
    curl -s --connect-timeout 2 http://$ip/status 2>/dev/null | jq . 2>/dev/null || echo "  Status non disponible"
    echo ""
}

test_all() {
    echo "============================================"
    echo "  TEST DE TOUS LES BACKENDS"
    echo "============================================"
    echo ""

    for server in backend1 backend2 backend3; do
        case $server in
            backend1) ip="172.30.0.21" ;;
            backend2) ip="172.30.0.22" ;;
            backend3) ip="172.30.0.23" ;;
        esac

        printf "%-12s %-15s " "$server" "($ip)"
        if curl -s --connect-timeout 2 http://$ip/health > /dev/null 2>&1; then
            echo "[UP]"
        else
            echo "[DOWN]"
        fi
    done
    echo ""

    echo ">>> Test de load balancing (5 requetes):"
    echo ""
    for i in $(seq 1 5); do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  Requete $i: ${response:-erreur}"
    done
    echo ""
}

# Main
case "${1:-help}" in
    list)
        list_backends
        ;;
    status)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 status <backend> <server>"
            exit 1
        fi
        get_status "$2" "$3"
        ;;
    enable)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 enable <backend> <server>"
            exit 1
        fi
        enable_server "$2" "$3"
        ;;
    disable)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 disable <backend> <server>"
            exit 1
        fi
        disable_server "$2" "$3"
        ;;
    drain)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 drain <backend> <server>"
            exit 1
        fi
        drain_server "$2" "$3"
        ;;
    weight)
        if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
            echo "Usage: $0 weight <backend> <server> <weight>"
            exit 1
        fi
        set_weight "$2" "$3" "$4"
        ;;
    health)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 health <backend> <server>"
            exit 1
        fi
        health_check "$2" "$3"
        ;;
    test)
        test_all
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
