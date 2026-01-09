#!/bin/bash
# =============================================================================
# Health Check Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/health-check.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/var/lib/haproxy/backups"

show_help() {
    cat << 'EOF'
Usage: /scripts/health-check.sh [COMMAND] [OPTIONS]

Commands:
  status                    - Afficher la configuration health check
  test                      - Tester les health checks
  configure <type>          - Configurer le type de health check
  interval <ms>             - Changer l'intervalle
  threshold <rise> <fall>   - Configurer les seuils
  demo                      - Demonstration

Types de health check:
  tcp         - Verification TCP simple
  http        - Verification HTTP GET
  httpchk     - HTTP avec chemin specifique

Examples:
  /scripts/health-check.sh status
  /scripts/health-check.sh test
  /scripts/health-check.sh configure http
  /scripts/health-check.sh interval 3000
  /scripts/health-check.sh threshold 3 5
EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$timestamp"
}

show_status() {
    echo "============================================"
    echo "  CONFIGURATION HEALTH CHECK"
    echo "============================================"
    echo ""

    echo ">>> Type de health check:"
    if grep -q "option httpchk" $CONFIG_FILE; then
        echo "  HTTP Health Check"
        grep "option httpchk" $CONFIG_FILE | awk '{print "  " $0}'
        grep "http-check" $CONFIG_FILE | awk '{print "  " $0}'
    elif grep -q "option tcp-check" $CONFIG_FILE; then
        echo "  TCP Health Check"
    else
        echo "  TCP basique (check par defaut)"
    fi

    echo ""
    echo ">>> Parametres des serveurs:"
    grep "^\s*server" $CONFIG_FILE | while read line; do
        echo "  $line"
    done

    echo ""
    echo ">>> Intervalles et seuils:"
    # Extraire inter, rise, fall
    local inter=$(grep "^\s*server" $CONFIG_FILE | head -1 | grep -oE 'inter [0-9]+' | awk '{print $2}')
    local rise=$(grep "^\s*server" $CONFIG_FILE | head -1 | grep -oE 'rise [0-9]+' | awk '{print $2}')
    local fall=$(grep "^\s*server" $CONFIG_FILE | head -1 | grep -oE 'fall [0-9]+' | awk '{print $2}')

    echo "  Intervalle: ${inter:-2000}ms"
    echo "  Rise:       ${rise:-2} checks reussis pour UP"
    echo "  Fall:       ${fall:-3} checks echoues pour DOWN"
    echo ""
}

test_health() {
    echo "============================================"
    echo "  TEST DES HEALTH CHECKS"
    echo "============================================"
    echo ""

    for server in backend1:172.30.0.21 backend2:172.30.0.22 backend3:172.30.0.23; do
        name=$(echo $server | cut -d: -f1)
        ip=$(echo $server | cut -d: -f2)

        printf "%-12s " "$name"

        # Test TCP
        if nc -z -w2 $ip 80 2>/dev/null; then
            printf "[TCP: OK] "
        else
            printf "[TCP: FAIL] "
        fi

        # Test HTTP /health
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 http://$ip/health 2>/dev/null || echo "000")
        if [ "$http_code" = "200" ]; then
            printf "[HTTP /health: OK]"
        else
            printf "[HTTP /health: $http_code]"
        fi

        echo ""
    done

    echo ""
    echo ">>> Etat dans HAProxy:"
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "^#|web_backend" | head -10
    fi
    echo ""
}

configure_health() {
    local type=$1

    echo "============================================"
    echo "  CONFIGURATION HEALTH CHECK: $type"
    echo "============================================"
    echo ""

    backup_config

    case $type in
        tcp)
            # Supprimer httpchk si present
            sed -i '/option httpchk/d' $CONFIG_FILE
            sed -i '/http-check/d' $CONFIG_FILE
            echo "[OK] Health check TCP configure"
            ;;

        http|httpchk)
            # Ajouter option httpchk si absent
            if ! grep -q "option httpchk" $CONFIG_FILE; then
                sed -i '/^backend web_backend/a\    option httpchk GET /health\n    http-check expect status 200' $CONFIG_FILE
            fi
            echo "[OK] Health check HTTP configure (GET /health)"
            ;;

        *)
            echo "[ERREUR] Type inconnu: $type"
            echo "Types valides: tcp, http"
            exit 1
            ;;
    esac

    # Recharger
    if haproxy -c -f $CONFIG_FILE; then
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] HAProxy recharge"
    else
        echo "[ERREUR] Configuration invalide"
        local latest=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
        [ -n "$latest" ] && cp "$latest" $CONFIG_FILE
    fi
    echo ""
}

set_interval() {
    local interval=$1

    echo "============================================"
    echo "  CHANGEMENT INTERVALLE: ${interval}ms"
    echo "============================================"
    echo ""

    backup_config

    # Modifier l'intervalle pour tous les serveurs
    sed -i "s/inter [0-9]*/inter $interval/g" $CONFIG_FILE

    # Recharger
    if haproxy -c -f $CONFIG_FILE; then
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] Intervalle change a ${interval}ms"
    else
        echo "[ERREUR] Configuration invalide"
    fi
    echo ""
}

set_threshold() {
    local rise=$1
    local fall=$2

    echo "============================================"
    echo "  CHANGEMENT SEUILS: rise=$rise, fall=$fall"
    echo "============================================"
    echo ""

    backup_config

    # Modifier les seuils
    sed -i "s/rise [0-9]*/rise $rise/g" $CONFIG_FILE
    sed -i "s/fall [0-9]*/fall $fall/g" $CONFIG_FILE

    # Recharger
    if haproxy -c -f $CONFIG_FILE; then
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] Seuils configures: rise=$rise, fall=$fall"
    else
        echo "[ERREUR] Configuration invalide"
    fi
    echo ""
}

demo_health() {
    echo "============================================"
    echo "  DEMONSTRATION HEALTH CHECKS"
    echo "============================================"
    echo ""

    echo ">>> Etape 1: Etat initial"
    test_health

    echo ">>> Etape 2: Simulation panne backend1"
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "set server web_backend/backend1 state maint" | socat stdio /var/run/haproxy/admin.sock
        echo "[SIMULE] backend1 en maintenance"
    fi

    sleep 3

    echo ""
    echo ">>> Etape 3: Verification (backend1 devrait etre DOWN)"
    /scripts/backend-manage.sh test 2>/dev/null || true

    echo ""
    echo ">>> Etape 4: Restauration"
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "set server web_backend/backend1 state ready" | socat stdio /var/run/haproxy/admin.sock
        echo "[OK] backend1 restaure"
    fi

    sleep 3

    echo ""
    echo ">>> Etape 5: Verification finale"
    test_health

    echo "[OK] Demo terminee"
    echo ""
}

# Main
case "${1:-help}" in
    status)
        show_status
        ;;
    test)
        test_health
        ;;
    configure)
        if [ -z "$2" ]; then
            echo "Usage: $0 configure <tcp|http>"
            exit 1
        fi
        configure_health "$2"
        ;;
    interval)
        if [ -z "$2" ]; then
            echo "Usage: $0 interval <ms>"
            exit 1
        fi
        set_interval "$2"
        ;;
    threshold)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 threshold <rise> <fall>"
            exit 1
        fi
        set_threshold "$2" "$3"
        ;;
    demo)
        demo_health
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
