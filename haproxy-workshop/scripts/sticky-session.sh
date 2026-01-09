#!/bin/bash
# =============================================================================
# Sticky Session Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/sticky-session.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/var/lib/haproxy/backups"

show_help() {
    cat << 'EOF'
Usage: /scripts/sticky-session.sh [COMMAND] [OPTIONS]

Commands:
  show              - Afficher la configuration sticky actuelle
  enable <type>     - Activer les sticky sessions
  disable           - Desactiver les sticky sessions
  test              - Tester les sticky sessions
  demo              - Demonstration des types de sticky

Types de sticky sessions:
  cookie    - Cookie SERVERID (recommande)
  source    - Basé sur l'IP source
  insert    - Cookie insere par HAProxy
  prefix    - Cookie prefix au cookie applicatif
  rewrite   - Reecrit le cookie applicatif

Examples:
  /scripts/sticky-session.sh show
  /scripts/sticky-session.sh enable cookie
  /scripts/sticky-session.sh enable source
  /scripts/sticky-session.sh test
  /scripts/sticky-session.sh disable
EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$timestamp"
}

show_current() {
    echo "============================================"
    echo "  CONFIGURATION STICKY SESSIONS"
    echo "============================================"
    echo ""

    if grep -q "^\s*cookie" $CONFIG_FILE; then
        echo "[ACTIVE] Sticky sessions par cookie"
        grep -E "^\s*cookie|^\s*server.*cookie" $CONFIG_FILE | head -10
    elif grep -q "^\s*balance source" $CONFIG_FILE; then
        echo "[ACTIVE] Sticky sessions par IP source"
    else
        echo "[INACTIVE] Pas de sticky sessions"
    fi
    echo ""

    echo "Configuration backend:"
    sed -n '/^backend web_backend/,/^backend\|^frontend/p' $CONFIG_FILE | head -20
    echo ""
}

enable_sticky() {
    local type=$1

    echo "============================================"
    echo "  ACTIVATION STICKY SESSIONS: $type"
    echo "============================================"
    echo ""

    backup_config

    case $type in
        cookie|insert)
            # Configurer avec cookie insert
            # Supprimer les anciennes config sticky
            sed -i '/^\s*cookie SERVERID/d' $CONFIG_FILE
            sed -i 's/\s*cookie [a-zA-Z0-9_-]*\s*$//' $CONFIG_FILE

            # Ajouter cookie dans backend
            sed -i '/^backend web_backend/a\    cookie SERVERID insert indirect nocache' $CONFIG_FILE

            # Ajouter cookie aux serveurs
            sed -i 's/server backend1 172.30.0.21:80 check.*/server backend1 172.30.0.21:80 check cookie srv1/' $CONFIG_FILE
            sed -i 's/server backend2 172.30.0.22:80 check.*/server backend2 172.30.0.22:80 check cookie srv2/' $CONFIG_FILE
            sed -i 's/server backend3 172.30.0.23:80 check.*/server backend3 172.30.0.23:80 check cookie srv3/' $CONFIG_FILE

            echo "[OK] Cookie sticky sessions actives"
            ;;

        source)
            # Balance source
            sed -i '/^\s*cookie SERVERID/d' $CONFIG_FILE
            sed -i 's/\s*cookie [a-zA-Z0-9_-]*\s*$//' $CONFIG_FILE
            sed -i 's/^\(\s*\)balance.*/\1balance source/' $CONFIG_FILE

            echo "[OK] Source IP sticky sessions actives"
            ;;

        prefix)
            # Cookie prefix
            sed -i '/^\s*cookie SERVERID/d' $CONFIG_FILE
            sed -i '/^backend web_backend/a\    cookie JSESSIONID prefix nocache' $CONFIG_FILE

            sed -i 's/server backend1 172.30.0.21:80 check.*/server backend1 172.30.0.21:80 check cookie srv1/' $CONFIG_FILE
            sed -i 's/server backend2 172.30.0.22:80 check.*/server backend2 172.30.0.22:80 check cookie srv2/' $CONFIG_FILE
            sed -i 's/server backend3 172.30.0.23:80 check.*/server backend3 172.30.0.23:80 check cookie srv3/' $CONFIG_FILE

            echo "[OK] Prefix cookie sticky sessions actives"
            ;;

        *)
            echo "[ERREUR] Type inconnu: $type"
            echo "Types valides: cookie, source, prefix"
            exit 1
            ;;
    esac

    # Recharger
    echo ""
    echo ">>> Verification et rechargement..."
    if haproxy -c -f $CONFIG_FILE; then
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] HAProxy recharge"
    else
        echo "[ERREUR] Configuration invalide"
        local latest=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
        [ -n "$latest" ] && cp "$latest" $CONFIG_FILE
        exit 1
    fi
    echo ""
}

disable_sticky() {
    echo "============================================"
    echo "  DESACTIVATION STICKY SESSIONS"
    echo "============================================"
    echo ""

    backup_config

    # Supprimer les configurations sticky
    sed -i '/^\s*cookie SERVERID/d' $CONFIG_FILE
    sed -i '/^\s*cookie JSESSIONID/d' $CONFIG_FILE
    sed -i 's/\s*cookie [a-zA-Z0-9_-]*\s*$//' $CONFIG_FILE

    # Remettre balance roundrobin
    sed -i 's/^\(\s*\)balance source/\1balance roundrobin/' $CONFIG_FILE

    # Nettoyer les serveurs
    sed -i 's/server backend1 172.30.0.21:80 check.*/server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3/' $CONFIG_FILE
    sed -i 's/server backend2 172.30.0.22:80 check.*/server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3/' $CONFIG_FILE
    sed -i 's/server backend3 172.30.0.23:80 check.*/server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3/' $CONFIG_FILE

    echo "[OK] Sticky sessions desactivees"

    # Recharger
    echo ""
    echo ">>> Rechargement..."
    pkill haproxy 2>/dev/null || true
    sleep 1
    haproxy -f $CONFIG_FILE -D
    echo "[OK] HAProxy recharge"
    echo ""
}

test_sticky() {
    echo "============================================"
    echo "  TEST STICKY SESSIONS"
    echo "============================================"
    echo ""

    echo ">>> Test sans cookie (premieres requetes):"
    echo ""

    for i in 1 2 3; do
        response=$(curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  Requete $i: ${response:-erreur}"
    done

    echo ""
    echo ">>> Cookies recus:"
    cat /tmp/cookies.txt 2>/dev/null | grep -v "^#" | grep -v "^$" || echo "  Aucun cookie"

    echo ""
    echo ">>> Test avec cookie (meme session):"
    echo ""

    for i in 1 2 3 4 5; do
        response=$(curl -s -b /tmp/cookies.txt --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  Requete $i: ${response:-erreur}"
    done

    echo ""
    echo ">>> Test nouvelle session (sans cookie):"
    echo ""
    rm -f /tmp/cookies.txt

    for i in 1 2 3; do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  Requete $i: ${response:-erreur}"
    done

    rm -f /tmp/cookies.txt
    echo ""
}

demo_sticky() {
    echo "============================================"
    echo "  DEMONSTRATION STICKY SESSIONS"
    echo "============================================"
    echo ""

    # Test sans sticky
    echo ">>> 1. Sans sticky sessions (roundrobin):"
    disable_sticky 2>/dev/null
    sleep 1

    for i in 1 2 3 4 5; do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  $response"
    done

    echo ""
    echo ">>> 2. Avec sticky sessions (cookie):"
    enable_sticky cookie 2>/dev/null
    sleep 1

    rm -f /tmp/cookies.txt
    for i in 1 2 3 4 5; do
        response=$(curl -s -c /tmp/cookies.txt -b /tmp/cookies.txt --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  $response"
    done

    echo ""
    echo ">>> 3. Avec sticky sessions (source IP):"
    enable_sticky source 2>/dev/null
    sleep 1

    for i in 1 2 3 4 5; do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        echo "  $response"
    done

    # Restaurer
    echo ""
    echo ">>> Restauration de la configuration par defaut..."
    disable_sticky 2>/dev/null
    echo "[OK] Demo terminee"
    echo ""
}

# Main
case "${1:-help}" in
    show)
        show_current
        ;;
    enable)
        if [ -z "$2" ]; then
            echo "Usage: $0 enable <type>"
            echo "Types: cookie, source, prefix"
            exit 1
        fi
        enable_sticky "$2"
        ;;
    disable)
        disable_sticky
        ;;
    test)
        test_sticky
        ;;
    demo)
        demo_sticky
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
