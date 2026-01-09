#!/bin/bash
# =============================================================================
# Keepalived Status Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/keepalived-status.sh [COMMAND]
# =============================================================================

set -e

show_help() {
    cat << 'EOF'
Usage: /scripts/keepalived-status.sh [COMMAND]

Commands:
  all       - Afficher toutes les informations
  status    - Statut de Keepalived
  vip       - Afficher la VIP
  vrrp      - Informations VRRP
  config    - Afficher la configuration
  logs      - Derniers logs Keepalived

Examples:
  /scripts/keepalived-status.sh all
  /scripts/keepalived-status.sh vip
  /scripts/keepalived-status.sh status
EOF
}

show_status() {
    echo "============================================"
    echo "  STATUT KEEPALIVED"
    echo "============================================"
    echo ""

    if pgrep -x keepalived > /dev/null; then
        echo "[OK] Keepalived est en cours d'execution"
        echo ""
        ps aux | grep -E "^USER|keepalived" | grep -v grep
    else
        echo "[ERREUR] Keepalived n'est pas en cours d'execution"
    fi
    echo ""
}

show_vip() {
    echo "============================================"
    echo "  VIP (Virtual IP)"
    echo "============================================"
    echo ""

    local vip=${VIP_ADDRESS:-172.30.0.100}

    echo "VIP configuree: $vip"
    echo ""

    echo ">>> Interfaces reseau:"
    ip addr show eth0 2>/dev/null | grep -E "inet " || echo "Interface eth0 non trouvee"
    echo ""

    if ip addr show eth0 2>/dev/null | grep -q "$vip"; then
        echo "[MASTER] Ce noeud possede la VIP"
    else
        echo "[BACKUP] Ce noeud n'a pas la VIP"
    fi
    echo ""

    echo ">>> Test de la VIP:"
    if ping -c 1 -W 2 $vip > /dev/null 2>&1; then
        echo "[OK] VIP $vip est accessible"
    else
        echo "[ATTENTION] VIP $vip n'est pas accessible"
    fi
    echo ""
}

show_vrrp() {
    echo "============================================"
    echo "  INFORMATIONS VRRP"
    echo "============================================"
    echo ""

    local node_name=${HAPROXY_NODE_NAME:-$(hostname)}
    local node_role=${HAPROXY_ROLE:-UNKNOWN}
    local priority=${KEEPALIVED_PRIORITY:-0}
    local state=${KEEPALIVED_STATE:-UNKNOWN}

    echo "Noeud:     $node_name"
    echo "Role:      $node_role"
    echo "Priorite:  $priority"
    echo "Etat:      $state"
    echo ""

    echo ">>> Configuration VRRP:"
    if [ -f /etc/keepalived/keepalived.conf ]; then
        grep -E "state|priority|virtual_ipaddress|interface|virtual_router_id" /etc/keepalived/keepalived.conf | head -10
    else
        echo "Configuration non trouvee"
    fi
    echo ""
}

show_config() {
    echo "============================================"
    echo "  CONFIGURATION KEEPALIVED"
    echo "============================================"
    echo ""

    if [ -f /etc/keepalived/keepalived.conf ]; then
        cat /etc/keepalived/keepalived.conf
    else
        echo "[ERREUR] Fichier de configuration non trouve"
    fi
    echo ""
}

show_logs() {
    echo "============================================"
    echo "  LOGS KEEPALIVED"
    echo "============================================"
    echo ""

    if [ -f /var/log/syslog ]; then
        grep -i keepalived /var/log/syslog 2>/dev/null | tail -20 || echo "Pas de logs keepalived"
    elif [ -f /var/log/messages ]; then
        grep -i keepalived /var/log/messages 2>/dev/null | tail -20 || echo "Pas de logs keepalived"
    else
        echo "Note: Les logs sont affiches sur la console (--log-console)"
        echo ""
        echo "Pour voir les logs en temps reel:"
        echo "  docker logs -f haproxy1"
        echo "  docker logs -f haproxy2"
    fi
    echo ""
}

show_all() {
    show_status
    show_vip
    show_vrrp
}

# Main
case "${1:-all}" in
    all)
        show_all
        ;;
    status)
        show_status
        ;;
    vip)
        show_vip
        ;;
    vrrp)
        show_vrrp
        ;;
    config)
        show_config
        ;;
    logs)
        show_logs
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
