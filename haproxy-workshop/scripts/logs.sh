#!/bin/bash
# =============================================================================
# Logs Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/logs.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

show_help() {
    cat << 'EOF'
Usage: /scripts/logs.sh [COMMAND] [OPTIONS]

Commands:
  haproxy         - Logs HAProxy
  keepalived      - Logs Keepalived
  access          - Logs d'acces
  errors          - Logs d'erreurs
  follow          - Suivre les logs en temps reel
  stats           - Statistiques des logs
  search <term>   - Rechercher dans les logs

Examples:
  /scripts/logs.sh haproxy
  /scripts/logs.sh access
  /scripts/logs.sh follow
  /scripts/logs.sh search 503
EOF
}

show_haproxy_logs() {
    echo "============================================"
    echo "  LOGS HAPROXY"
    echo "============================================"
    echo ""

    # HAProxy log a stdout dans cette config
    echo "Note: HAProxy est configure pour logger sur stdout"
    echo "Utilisez 'docker logs haproxy1' depuis le host"
    echo ""

    if [ -f /var/log/haproxy.log ]; then
        tail -50 /var/log/haproxy.log
    else
        echo "Fichier de log non trouve"
        echo ""
        echo "Pour voir les logs, executez depuis le host:"
        echo "  docker logs haproxy1"
        echo "  docker logs -f haproxy1  # pour suivre en temps reel"
    fi
    echo ""
}

show_keepalived_logs() {
    echo "============================================"
    echo "  LOGS KEEPALIVED"
    echo "============================================"
    echo ""

    echo "Note: Keepalived est configure avec --log-console"
    echo "Les logs sont visibles dans les logs du container"
    echo ""

    if [ -f /var/log/syslog ]; then
        grep -i keepalived /var/log/syslog 2>/dev/null | tail -30 || echo "Pas de logs keepalived dans syslog"
    fi

    echo ""
    echo "Pour voir les logs Keepalived depuis le host:"
    echo "  docker logs haproxy1 | grep -i keepalived"
    echo ""
}

show_access_logs() {
    echo "============================================"
    echo "  LOGS D'ACCES"
    echo "============================================"
    echo ""

    if [ -S /var/run/haproxy/admin.sock ]; then
        echo ">>> Dernieres requetes (via stats):"
        echo "show sess" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -20
    fi

    echo ""
    echo "Pour voir les logs d'acces depuis le host:"
    echo "  docker logs haproxy1 2>&1 | grep -E 'HTTP/1'"
    echo ""
}

show_error_logs() {
    echo "============================================"
    echo "  LOGS D'ERREURS"
    echo "============================================"
    echo ""

    echo ">>> Erreurs recentes:"
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "show errors" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -30
    else
        echo "Socket admin non disponible"
    fi

    echo ""
    echo "Pour voir les erreurs depuis le host:"
    echo "  docker logs haproxy1 2>&1 | grep -iE 'error|warn|fail'"
    echo ""
}

follow_logs() {
    echo "============================================"
    echo "  SUIVI DES LOGS EN TEMPS REEL"
    echo "============================================"
    echo ""
    echo "Note: Cette commande est plus efficace depuis le host:"
    echo "  docker logs -f haproxy1"
    echo ""
    echo "Appuyez sur Ctrl+C pour arreter"
    echo ""

    # Essayer de suivre les logs disponibles
    if [ -f /var/log/haproxy.log ]; then
        tail -f /var/log/haproxy.log
    else
        echo "Pas de fichier de log a suivre dans le container"
        echo ""
        echo "Simulation de suivi avec stats..."
        while true; do
            clear
            echo "=== Stats HAProxy (rafraichi toutes les 2s) ==="
            date
            echo ""
            if [ -S /var/run/haproxy/admin.sock ]; then
                echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | cut -d, -f1,2,18,19 | head -10
            fi
            sleep 2
        done
    fi
}

show_log_stats() {
    echo "============================================"
    echo "  STATISTIQUES DES LOGS"
    echo "============================================"
    echo ""

    if [ -S /var/run/haproxy/admin.sock ]; then
        echo ">>> Statistiques generales:"
        echo "show info" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "CurrConns|MaxConn|CumReq|CumConns"

        echo ""
        echo ">>> Sessions actives:"
        echo "show sess" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | wc -l | xargs echo "Nombre de sessions:"

        echo ""
        echo ">>> Requetes par backend:"
        echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep "BACKEND" | cut -d, -f1,2,8,9,10 | while IFS=, read pxname svname stot bin bout; do
            echo "  $pxname: $stot requetes"
        done
    else
        echo "[ATTENTION] Socket admin non disponible"
    fi
    echo ""
}

search_logs() {
    local term=$1

    echo "============================================"
    echo "  RECHERCHE: $term"
    echo "============================================"
    echo ""

    if [ -f /var/log/haproxy.log ]; then
        grep -i "$term" /var/log/haproxy.log | tail -30
    else
        echo "Fichier de log non disponible dans le container"
        echo ""
        echo "Pour rechercher depuis le host:"
        echo "  docker logs haproxy1 2>&1 | grep -i '$term'"
    fi
    echo ""
}

# Main
case "${1:-help}" in
    haproxy)
        show_haproxy_logs
        ;;
    keepalived)
        show_keepalived_logs
        ;;
    access)
        show_access_logs
        ;;
    errors|error)
        show_error_logs
        ;;
    follow|tail|-f)
        follow_logs
        ;;
    stats)
        show_log_stats
        ;;
    search|grep)
        if [ -z "$2" ]; then
            echo "Usage: $0 search <term>"
            exit 1
        fi
        search_logs "$2"
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
