#!/bin/bash
# =============================================================================
# Rate Limiting Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/rate-limit.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/var/lib/haproxy/backups"

show_help() {
    cat << 'EOF'
Usage: /scripts/rate-limit.sh [COMMAND] [OPTIONS]

Commands:
  status              - Afficher la configuration actuelle
  enable <rps>        - Activer le rate limiting (req/sec)
  disable             - Desactiver le rate limiting
  test                - Tester le rate limiting
  demo                - Demonstration du rate limiting
  stats               - Afficher les statistiques

Examples:
  /scripts/rate-limit.sh status
  /scripts/rate-limit.sh enable 10
  /scripts/rate-limit.sh test
  /scripts/rate-limit.sh disable
EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$timestamp"
}

show_status() {
    echo "============================================"
    echo "  STATUT RATE LIMITING"
    echo "============================================"
    echo ""

    if grep -q "stick-table.*rate" $CONFIG_FILE; then
        echo "[ACTIVE] Rate limiting configure"
        echo ""
        echo "Configuration:"
        grep -E "stick-table|track-sc|deny.*rate|tarpit" $CONFIG_FILE | head -15
    else
        echo "[INACTIVE] Rate limiting non configure"
    fi
    echo ""
}

enable_rate_limit() {
    local rps=${1:-10}

    echo "============================================"
    echo "  ACTIVATION RATE LIMITING: $rps req/sec"
    echo "============================================"
    echo ""

    backup_config

    # Verifier si deja configure
    if grep -q "stick-table.*rate" $CONFIG_FILE; then
        echo "[INFO] Mise a jour de la configuration existante..."
        sed -i "s/http_req_rate([^)]*) gt [0-9]*/http_req_rate(10s) gt $((rps * 10))/" $CONFIG_FILE
    else
        # Ajouter la configuration de rate limiting dans le frontend
        cat > /tmp/rate_limit_config.txt << EOF

    # Rate Limiting Configuration
    stick-table type ip size 100k expire 30s store http_req_rate(10s)
    http-request track-sc0 src
    acl rate_abuse sc_http_req_rate(0) gt $((rps * 10))
    http-request deny deny_status 429 if rate_abuse

EOF

        # Inserer avant default_backend dans le frontend http_front
        sed -i "/^frontend http_front/,/default_backend/{
            /default_backend/e cat /tmp/rate_limit_config.txt
        }" $CONFIG_FILE

        rm -f /tmp/rate_limit_config.txt
    fi

    # Verifier et recharger
    echo ">>> Verification de la configuration..."
    if haproxy -c -f $CONFIG_FILE; then
        echo "[OK] Configuration valide"
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] Rate limiting active: max $rps req/sec par IP"
    else
        echo "[ERREUR] Configuration invalide, restauration..."
        local latest=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
        [ -n "$latest" ] && cp "$latest" $CONFIG_FILE
        exit 1
    fi
    echo ""
}

disable_rate_limit() {
    echo "============================================"
    echo "  DESACTIVATION RATE LIMITING"
    echo "============================================"
    echo ""

    backup_config

    # Supprimer les lignes de rate limiting
    sed -i '/# Rate Limiting Configuration/d' $CONFIG_FILE
    sed -i '/stick-table.*rate/d' $CONFIG_FILE
    sed -i '/track-sc0/d' $CONFIG_FILE
    sed -i '/rate_abuse/d' $CONFIG_FILE
    sed -i '/http-request deny deny_status 429/d' $CONFIG_FILE

    echo "[OK] Rate limiting desactive"

    # Recharger
    pkill haproxy 2>/dev/null || true
    sleep 1
    haproxy -f $CONFIG_FILE -D
    echo "[OK] HAProxy recharge"
    echo ""
}

test_rate_limit() {
    echo "============================================"
    echo "  TEST RATE LIMITING"
    echo "============================================"
    echo ""

    echo ">>> Envoi de 20 requetes rapides..."
    echo ""

    local success=0
    local blocked=0

    for i in $(seq 1 20); do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost/ 2>/dev/null)
        if [ "$http_code" = "429" ]; then
            echo "  Requete $i: BLOQUE (429 Too Many Requests)"
            ((blocked++))
        elif [ "$http_code" = "200" ]; then
            echo "  Requete $i: OK (200)"
            ((success++))
        else
            echo "  Requete $i: $http_code"
        fi
    done

    echo ""
    echo ">>> Resultats:"
    echo "  - Requetes reussies: $success"
    echo "  - Requetes bloquees: $blocked"
    echo ""

    if [ $blocked -gt 0 ]; then
        echo "[OK] Rate limiting fonctionne!"
    else
        echo "[INFO] Aucune requete bloquee - rate limit peut etre trop haut"
    fi
    echo ""
}

show_stats() {
    echo "============================================"
    echo "  STATISTIQUES RATE LIMITING"
    echo "============================================"
    echo ""

    if [ -S /var/run/haproxy/admin.sock ]; then
        echo ">>> Table de stick:"
        echo "show table" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -20

        echo ""
        echo ">>> Contenu de la table (IPs trackees):"
        echo "show table http_front" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -20
    else
        echo "[ERREUR] Socket admin non disponible"
    fi
    echo ""
}

demo_rate_limit() {
    echo "============================================"
    echo "  DEMONSTRATION RATE LIMITING"
    echo "============================================"
    echo ""

    echo ">>> Etape 1: Activation du rate limiting (5 req/sec)"
    enable_rate_limit 5 2>/dev/null

    sleep 2

    echo ""
    echo ">>> Etape 2: Test sans depasser la limite"
    echo "Envoi de 3 requetes espacees..."
    for i in 1 2 3; do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://localhost/ 2>/dev/null)
        echo "  Requete $i: $http_code"
        sleep 0.5
    done

    echo ""
    echo ">>> Etape 3: Test en depassant la limite"
    echo "Envoi de 100 requetes rapides..."
    local blocked=0
    for i in $(seq 1 100); do
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 1 http://localhost/ 2>/dev/null)
        [ "$http_code" = "429" ] && ((blocked++))
    done
    echo "  Requetes bloquees: $blocked/100"

    echo ""
    echo ">>> Etape 4: Desactivation"
    disable_rate_limit 2>/dev/null

    echo ""
    echo "[OK] Demo terminee"
    echo ""
}

# Main
case "${1:-help}" in
    status)
        show_status
        ;;
    enable)
        enable_rate_limit "${2:-10}"
        ;;
    disable)
        disable_rate_limit
        ;;
    test)
        test_rate_limit
        ;;
    demo)
        demo_rate_limit
        ;;
    stats)
        show_stats
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
