#!/bin/bash
# =============================================================================
# Load Balancing Algorithm Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/lb-algorithm.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/var/lib/haproxy/backups"

show_help() {
    cat << 'EOF'
Usage: /scripts/lb-algorithm.sh [COMMAND] [OPTIONS]

Commands:
  show                  - Afficher l'algorithme actuel
  set <algorithm>       - Changer l'algorithme
  list                  - Lister les algorithmes disponibles
  test <algorithm>      - Tester un algorithme
  demo                  - Demonstration des algorithmes
  restore               - Restaurer la configuration originale

Algorithmes disponibles:
  roundrobin   - Distribution circulaire (defaut)
  leastconn    - Moins de connexions actives
  source       - Basé sur l'IP source (persistance)
  uri          - Basé sur l'URI
  random       - Distribution aleatoire
  first        - Premier serveur disponible
  hdr(name)    - Basé sur un header HTTP

Examples:
  /scripts/lb-algorithm.sh show
  /scripts/lb-algorithm.sh set leastconn
  /scripts/lb-algorithm.sh test roundrobin
  /scripts/lb-algorithm.sh demo
EOF
}

show_current() {
    echo "============================================"
    echo "  ALGORITHME ACTUEL"
    echo "============================================"
    echo ""

    local algo=$(grep -E "^\s*balance" $CONFIG_FILE | head -1 | awk '{print $2}')
    if [ -n "$algo" ]; then
        echo "Algorithme: $algo"
    else
        echo "Algorithme: roundrobin (defaut)"
    fi
    echo ""

    echo "Configuration backend web_backend:"
    sed -n '/^backend web_backend/,/^backend\|^frontend/p' $CONFIG_FILE | head -15
    echo ""
}

list_algorithms() {
    echo "============================================"
    echo "  ALGORITHMES DISPONIBLES"
    echo "============================================"
    echo ""

    cat << 'EOF'
1. roundrobin
   - Distribution circulaire
   - Chaque serveur reçoit une requête à tour de rôle
   - Poids des serveurs pris en compte
   - Ideal pour: charge uniforme

2. leastconn
   - Connexion vers le serveur le moins chargé
   - Compte les connexions actives
   - Ideal pour: sessions longues (WebSocket, DB)

3. source
   - Hash de l'IP source
   - Même client = même serveur
   - Ideal pour: persistance de session simple

4. uri
   - Hash de l'URI demandée
   - Même URL = même serveur
   - Ideal pour: cache applicatif

5. random
   - Distribution aléatoire
   - Basé sur un générateur aléatoire
   - Ideal pour: répartition équitable

6. first
   - Premier serveur avec slots disponibles
   - Remplit un serveur avant le suivant
   - Ideal pour: économie de ressources

7. hdr(name)
   - Basé sur un header HTTP
   - Ex: hdr(User-Agent)
   - Ideal pour: routage applicatif

EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$timestamp"
    echo "[OK] Backup cree: $BACKUP_DIR/haproxy.cfg.$timestamp"
}

set_algorithm() {
    local algo=$1

    echo "============================================"
    echo "  CHANGEMENT D'ALGORITHME: $algo"
    echo "============================================"
    echo ""

    # Backup
    backup_config

    # Modifier la configuration
    if grep -q "^\s*balance" $CONFIG_FILE; then
        sed -i "s/^\(\s*\)balance.*/\1balance $algo/" $CONFIG_FILE
    else
        # Ajouter après "backend web_backend"
        sed -i "/^backend web_backend/a\    balance $algo" $CONFIG_FILE
    fi

    # Verifier la configuration
    echo ">>> Verification de la configuration..."
    if haproxy -c -f $CONFIG_FILE; then
        echo "[OK] Configuration valide"

        # Recharger HAProxy
        echo ""
        echo ">>> Rechargement de HAProxy..."
        if [ -S /var/run/haproxy/admin.sock ]; then
            echo "reload" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null || {
                # Fallback: redemarrer le processus
                pkill -USR2 haproxy || pkill haproxy
                sleep 1
                haproxy -f $CONFIG_FILE -D
            }
        else
            pkill haproxy 2>/dev/null || true
            sleep 1
            haproxy -f $CONFIG_FILE -D
        fi

        echo "[OK] Algorithme change en: $algo"
    else
        echo "[ERREUR] Configuration invalide, restauration..."
        local latest_backup=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
        if [ -n "$latest_backup" ]; then
            cp "$latest_backup" $CONFIG_FILE
        fi
        exit 1
    fi
    echo ""
}

test_algorithm() {
    local algo=$1
    local count=${2:-10}

    echo "============================================"
    echo "  TEST ALGORITHME: $algo ($count requetes)"
    echo "============================================"
    echo ""

    # Sauvegarder l'algo actuel
    local current=$(grep -E "^\s*balance" $CONFIG_FILE | head -1 | awk '{print $2}')
    current=${current:-roundrobin}

    # Changer temporairement
    echo ">>> Configuration temporaire de $algo..."
    set_algorithm "$algo" 2>/dev/null

    sleep 2

    # Tester
    echo ""
    echo ">>> Envoi de $count requetes..."
    echo ""

    declare -A hits
    for i in $(seq 1 $count); do
        response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
        if [ -n "$response" ]; then
            hits[$response]=$((${hits[$response]:-0} + 1))
            printf "  Requete %2d: %s\n" $i "$response"
        else
            printf "  Requete %2d: erreur\n" $i
        fi
    done

    echo ""
    echo ">>> Resultats:"
    for server in "${!hits[@]}"; do
        printf "  %-10s: %d requetes (%.1f%%)\n" "$server" "${hits[$server]}" $(echo "scale=1; ${hits[$server]} * 100 / $count" | bc)
    done

    # Restaurer l'algorithme original
    echo ""
    echo ">>> Restauration de l'algorithme original ($current)..."
    set_algorithm "$current" 2>/dev/null
    echo ""
}

demo_algorithms() {
    echo "============================================"
    echo "  DEMONSTRATION DES ALGORITHMES"
    echo "============================================"
    echo ""

    for algo in roundrobin leastconn source random; do
        echo "============================================"
        echo ">>> Test de: $algo"
        echo "============================================"

        set_algorithm "$algo" 2>/dev/null
        sleep 1

        echo "Resultats (5 requetes):"
        for i in $(seq 1 5); do
            response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
            echo "  $i: ${response:-erreur}"
        done
        echo ""
        sleep 1
    done

    # Restaurer roundrobin
    set_algorithm "roundrobin" 2>/dev/null
    echo "[OK] Demo terminee, algorithme restaure en roundrobin"
}

restore_config() {
    echo "============================================"
    echo "  RESTAURATION CONFIGURATION"
    echo "============================================"
    echo ""

    local latest_backup=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
    if [ -n "$latest_backup" ]; then
        cp "$latest_backup" $CONFIG_FILE
        echo "[OK] Configuration restauree depuis: $latest_backup"

        # Recharger
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] HAProxy recharge"
    else
        echo "[ERREUR] Aucun backup trouve"
    fi
    echo ""
}

# Main
case "${1:-help}" in
    show)
        show_current
        ;;
    set)
        if [ -z "$2" ]; then
            echo "Usage: $0 set <algorithm>"
            exit 1
        fi
        set_algorithm "$2"
        ;;
    list)
        list_algorithms
        ;;
    test)
        test_algorithm "${2:-roundrobin}" "${3:-10}"
        ;;
    demo)
        demo_algorithms
        ;;
    restore)
        restore_config
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
