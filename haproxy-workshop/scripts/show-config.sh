#!/bin/bash
# =============================================================================
# Show Configuration Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/show-config.sh [SECTION]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"

show_help() {
    cat << 'EOF'
Usage: /scripts/show-config.sh [SECTION]

Sections:
  all         - Afficher toute la configuration
  global      - Section global
  defaults    - Section defaults
  frontends   - Tous les frontends
  backends    - Tous les backends
  stats       - Configuration stats
  summary     - Resume de la configuration
  diff        - Differences avec la config originale

Examples:
  /scripts/show-config.sh all
  /scripts/show-config.sh frontends
  /scripts/show-config.sh summary
EOF
}

show_all() {
    echo "============================================"
    echo "  CONFIGURATION HAPROXY COMPLETE"
    echo "============================================"
    echo ""
    cat $CONFIG_FILE
    echo ""
}

show_global() {
    echo "============================================"
    echo "  SECTION GLOBAL"
    echo "============================================"
    echo ""
    sed -n '/^global/,/^defaults\|^frontend\|^backend/p' $CONFIG_FILE | head -n -1
    echo ""
}

show_defaults() {
    echo "============================================"
    echo "  SECTION DEFAULTS"
    echo "============================================"
    echo ""
    sed -n '/^defaults/,/^frontend\|^backend/p' $CONFIG_FILE | head -n -1
    echo ""
}

show_frontends() {
    echo "============================================"
    echo "  FRONTENDS"
    echo "============================================"
    echo ""

    # Trouver tous les frontends
    grep -n "^frontend" $CONFIG_FILE | while read line; do
        frontend_name=$(echo "$line" | awk '{print $2}')
        echo ">>> $frontend_name"
        line_num=$(echo "$line" | cut -d: -f1)
        sed -n "${line_num},/^frontend\|^backend/{/^frontend\|^backend/!p}" $CONFIG_FILE
        echo ""
    done
}

show_backends() {
    echo "============================================"
    echo "  BACKENDS"
    echo "============================================"
    echo ""

    # Trouver tous les backends
    grep -n "^backend" $CONFIG_FILE | while read line; do
        backend_name=$(echo "$line" | awk '{print $2}')
        echo ">>> $backend_name"
        line_num=$(echo "$line" | cut -d: -f1)
        sed -n "${line_num},/^frontend\|^backend/{/^frontend\|^backend/!p}" $CONFIG_FILE
        echo ""
    done
}

show_stats() {
    echo "============================================"
    echo "  CONFIGURATION STATS"
    echo "============================================"
    echo ""

    grep -E "stats|8404|prometheus" $CONFIG_FILE | while read line; do
        echo "  $line"
    done
    echo ""
}

show_summary() {
    echo "============================================"
    echo "  RESUME DE LA CONFIGURATION"
    echo "============================================"
    echo ""

    echo ">>> Frontends:"
    grep "^frontend" $CONFIG_FILE | awk '{print "  - " $2}'

    echo ""
    echo ">>> Backends:"
    grep "^backend" $CONFIG_FILE | awk '{print "  - " $2}'

    echo ""
    echo ">>> Serveurs backend:"
    grep "^\s*server" $CONFIG_FILE | awk '{print "  - " $2 " (" $3 ")"}'

    echo ""
    echo ">>> Ports exposes:"
    grep "bind" $CONFIG_FILE | awk '{print "  - " $2}'

    echo ""
    echo ">>> Algorithme de load balancing:"
    algo=$(grep "^\s*balance" $CONFIG_FILE | head -1 | awk '{print $2}')
    echo "  - ${algo:-roundrobin (defaut)}"

    echo ""
    echo ">>> Health checks:"
    if grep -q "option httpchk" $CONFIG_FILE; then
        echo "  - HTTP health check active"
        grep "option httpchk" $CONFIG_FILE | awk '{print "    " $0}'
    else
        echo "  - TCP health check (defaut)"
    fi

    echo ""
    echo ">>> SSL/TLS:"
    if grep -q "ssl crt" $CONFIG_FILE; then
        echo "  - SSL active"
    else
        echo "  - SSL non configure"
    fi

    echo ""
    echo ">>> Sticky sessions:"
    if grep -q "^\s*cookie" $CONFIG_FILE; then
        echo "  - Cookie sticky sessions active"
    elif grep -q "balance source" $CONFIG_FILE; then
        echo "  - Source IP sticky active"
    else
        echo "  - Pas de sticky sessions"
    fi

    echo ""
}

show_diff() {
    echo "============================================"
    echo "  DIFFERENCES AVEC CONFIG ORIGINALE"
    echo "============================================"
    echo ""

    local backup_dir="/var/lib/haproxy/backups"
    local first_backup=$(ls -t $backup_dir/haproxy.cfg.* 2>/dev/null | tail -1)

    if [ -n "$first_backup" ]; then
        echo "Comparaison avec: $first_backup"
        echo ""
        diff -u "$first_backup" $CONFIG_FILE || true
    else
        echo "[INFO] Aucun backup trouve pour comparaison"
    fi
    echo ""
}

# Main
case "${1:-summary}" in
    all)
        show_all
        ;;
    global)
        show_global
        ;;
    defaults)
        show_defaults
        ;;
    frontends|frontend)
        show_frontends
        ;;
    backends|backend)
        show_backends
        ;;
    stats)
        show_stats
        ;;
    summary)
        show_summary
        ;;
    diff)
        show_diff
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "Section inconnue: $1"
        show_help
        exit 1
        ;;
esac
