#!/bin/bash
# =============================================================================
# HAProxy Status Script - Workshop
# =============================================================================
# Usage: /scripts/haproxy-status.sh [all|config|process|stats|backends]
# =============================================================================

set -e

show_help() {
    cat << 'EOF'
Usage: /scripts/haproxy-status.sh [COMMAND]

Commands:
  all       - Afficher toutes les informations
  config    - Verifier la configuration HAProxy
  process   - Afficher les processus HAProxy
  stats     - Afficher les statistiques generales
  backends  - Afficher l'etat des backends
  frontend  - Afficher l'etat des frontends
  socket    - Tester le socket admin

Examples:
  /scripts/haproxy-status.sh all
  /scripts/haproxy-status.sh backends
  /scripts/haproxy-status.sh config
EOF
}

check_config() {
    echo "============================================"
    echo "  VERIFICATION CONFIGURATION HAPROXY"
    echo "============================================"
    echo ""
    if haproxy -c -f /etc/haproxy/haproxy.cfg 2>&1; then
        echo "[OK] Configuration valide"
    else
        echo "[ERREUR] Configuration invalide"
    fi
    echo ""
}

show_process() {
    echo "============================================"
    echo "  PROCESSUS HAPROXY"
    echo "============================================"
    echo ""
    if pgrep -x haproxy > /dev/null; then
        echo "[OK] HAProxy est en cours d'execution"
        echo ""
        ps aux | grep -E "^USER|haproxy" | grep -v grep
    else
        echo "[ERREUR] HAProxy n'est pas en cours d'execution"
    fi
    echo ""
}

show_stats() {
    echo "============================================"
    echo "  STATISTIQUES HAPROXY"
    echo "============================================"
    echo ""
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "show info" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null || echo "Impossible de recuperer les stats"
    else
        echo "[ATTENTION] Socket admin non disponible"
        echo "Tentative via curl..."
        curl -s http://localhost:8404/stats?stats;csv 2>/dev/null | head -20 || echo "Stats non disponibles"
    fi
    echo ""
}

show_backends() {
    echo "============================================"
    echo "  ETAT DES BACKENDS"
    echo "============================================"
    echo ""
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "show servers state" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null || {
            echo "Utilisation alternative..."
            echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "^#|BACKEND|backend" | head -20
        }
    else
        echo "[ATTENTION] Socket admin non disponible"
        echo ""
        echo "Test des backends directement:"
        for backend in backend1:172.30.0.21 backend2:172.30.0.22 backend3:172.30.0.23; do
            name=$(echo $backend | cut -d: -f1)
            ip=$(echo $backend | cut -d: -f2)
            if curl -s --connect-timeout 2 http://$ip/health > /dev/null 2>&1; then
                echo "  [UP] $name ($ip)"
            else
                echo "  [DOWN] $name ($ip)"
            fi
        done
    fi
    echo ""
}

show_frontends() {
    echo "============================================"
    echo "  ETAT DES FRONTENDS"
    echo "============================================"
    echo ""
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "^#|FRONTEND" | head -20
    else
        echo "Frontends configures:"
        grep -E "^frontend" /etc/haproxy/haproxy.cfg 2>/dev/null || echo "Aucun frontend trouve"
    fi
    echo ""
}

test_socket() {
    echo "============================================"
    echo "  TEST SOCKET ADMIN"
    echo "============================================"
    echo ""
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "[OK] Socket admin disponible: /var/run/haproxy/admin.sock"
        echo ""
        echo "Commandes disponibles:"
        echo "show help" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -20 || echo "Aide non disponible"
    else
        echo "[ERREUR] Socket admin non disponible"
    fi
    echo ""
}

show_all() {
    show_process
    check_config
    show_frontends
    show_backends
    show_stats
}

# Main
case "${1:-all}" in
    all)
        show_all
        ;;
    config)
        check_config
        ;;
    process)
        show_process
        ;;
    stats)
        show_stats
        ;;
    backends)
        show_backends
        ;;
    frontend|frontends)
        show_frontends
        ;;
    socket)
        test_socket
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
