#!/bin/bash
# =============================================================================
# Frontend Management Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/frontend-manage.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/var/lib/haproxy/backups"
SOCKET="/var/run/haproxy/admin.sock"

show_help() {
    cat << 'EOF'
Usage: /scripts/frontend-manage.sh [COMMAND] [OPTIONS]

Commands:
  list                              - Lister tous les frontends
  show <frontend>                   - Afficher la configuration d'un frontend
  create <name> <port> [backend]    - Creer un nouveau frontend
  delete <name>                     - Supprimer un frontend
  set-rate-limit <frontend> <rate>  - Configurer le rate limiting (req/s)
  remove-rate-limit <frontend>      - Supprimer le rate limiting
  bind <frontend> <ip:port>         - Ajouter un binding
  set-default-backend <frontend> <backend> - Changer le backend par defaut
  status                            - Statut de tous les frontends

Examples:
  /scripts/frontend-manage.sh list
  /scripts/frontend-manage.sh create test-frontend 8080
  /scripts/frontend-manage.sh create api-frontend 8081 api-backend
  /scripts/frontend-manage.sh set-rate-limit web-frontend 100
  /scripts/frontend-manage.sh delete test-frontend
EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$(date +%Y%m%d%H%M%S)"
    echo "[INFO] Configuration sauvegardee"
}

reload_haproxy() {
    echo "[INFO] Verification de la configuration..."
    if haproxy -c -f $CONFIG_FILE > /dev/null 2>&1; then
        echo "[OK] Configuration valide"

        # Reload via socket si disponible
        if [ -S "$SOCKET" ]; then
            echo "[INFO] Rechargement de HAProxy..."
            # Utiliser le reload graceful
            if [ -f /var/run/haproxy.pid ]; then
                haproxy -f $CONFIG_FILE -p /var/run/haproxy.pid -sf $(cat /var/run/haproxy.pid) 2>/dev/null || {
                    echo "[INFO] Reload via service..."
                    service haproxy reload 2>/dev/null || true
                }
            fi
            echo "[OK] HAProxy recharge"
        else
            echo "[INFO] Rechargement manuel necessaire: haproxy -f $CONFIG_FILE -sf \$(cat /var/run/haproxy.pid)"
        fi
        return 0
    else
        echo "[ERREUR] Configuration invalide!"
        haproxy -c -f $CONFIG_FILE
        return 1
    fi
}

list_frontends() {
    echo "============================================"
    echo "  LISTE DES FRONTENDS"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend" $CONFIG_FILE; then
        echo "Aucun frontend configure"
        return
    fi

    grep "^frontend" $CONFIG_FILE | while read line; do
        frontend_name=$(echo "$line" | awk '{print $2}')

        # Trouver le port
        bind_line=$(sed -n "/^frontend $frontend_name/,/^frontend\|^backend/{/bind/p}" $CONFIG_FILE | head -1)
        port=$(echo "$bind_line" | grep -oE ':[0-9]+' | head -1 | tr -d ':')

        # Trouver le backend par defaut
        default_backend=$(sed -n "/^frontend $frontend_name/,/^frontend\|^backend/{/default_backend/p}" $CONFIG_FILE | awk '{print $2}' | head -1)

        printf "  %-25s Port: %-6s Backend: %s\n" "$frontend_name" "${port:-N/A}" "${default_backend:-N/A}"
    done
    echo ""
}

show_frontend() {
    local frontend=$1

    echo "============================================"
    echo "  FRONTEND: $frontend"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend $frontend" $CONFIG_FILE; then
        echo "[ERREUR] Frontend '$frontend' non trouve"
        exit 1
    fi

    # Extraire la configuration du frontend
    sed -n "/^frontend $frontend/,/^frontend\|^backend/{/^frontend\|^backend/!p;/^frontend $frontend/p}" $CONFIG_FILE
    echo ""
}

create_frontend() {
    local name=$1
    local port=$2
    local backend=${3:-web-backend}

    echo "============================================"
    echo "  CREATION FRONTEND: $name"
    echo "============================================"
    echo ""

    # Verifier si le frontend existe deja
    if grep -q "^frontend $name" $CONFIG_FILE; then
        echo "[ERREUR] Le frontend '$name' existe deja"
        exit 1
    fi

    # Verifier si le port est valide
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo "[ERREUR] Port invalide: $port"
        exit 1
    fi

    # Verifier si le port est deja utilise
    if grep -qE "bind.*:$port" $CONFIG_FILE; then
        echo "[ERREUR] Le port $port est deja utilise"
        exit 1
    fi

    backup_config

    # Ajouter le nouveau frontend a la fin du fichier
    cat >> $CONFIG_FILE << EOF

frontend $name
    bind *:$port
    mode http
    option httplog
    default_backend $backend
EOF

    echo "[OK] Frontend '$name' cree sur le port $port"
    echo "     Backend par defaut: $backend"
    echo ""

    reload_haproxy
}

delete_frontend() {
    local name=$1

    echo "============================================"
    echo "  SUPPRESSION FRONTEND: $name"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend $name" $CONFIG_FILE; then
        echo "[ERREUR] Frontend '$name' non trouve"
        exit 1
    fi

    # Protection contre la suppression des frontends critiques
    case $name in
        web-frontend|stats)
            echo "[ATTENTION] Suppression d'un frontend critique!"
            read -p "Confirmer (oui/non): " confirm
            if [ "$confirm" != "oui" ]; then
                echo "Annule"
                exit 0
            fi
            ;;
    esac

    backup_config

    # Supprimer le frontend (de la ligne frontend jusqu'au prochain frontend/backend)
    sed -i "/^frontend $name$/,/^frontend\|^backend/{/^frontend\|^backend/!d}" $CONFIG_FILE
    sed -i "/^frontend $name$/d" $CONFIG_FILE

    # Nettoyer les lignes vides consecutives
    sed -i '/^$/N;/^\n$/d' $CONFIG_FILE

    echo "[OK] Frontend '$name' supprime"
    echo ""

    reload_haproxy
}

set_rate_limit() {
    local frontend=$1
    local rate=$2

    echo "============================================"
    echo "  RATE LIMIT: $frontend = $rate req/s"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend $frontend" $CONFIG_FILE; then
        echo "[ERREUR] Frontend '$frontend' non trouve"
        exit 1
    fi

    if ! [[ "$rate" =~ ^[0-9]+$ ]] || [ "$rate" -lt 1 ]; then
        echo "[ERREUR] Rate invalide: $rate"
        exit 1
    fi

    backup_config

    # Verifier si le stick-table existe deja
    if sed -n "/^frontend $frontend/,/^frontend\|^backend/p" $CONFIG_FILE | grep -q "stick-table"; then
        echo "[INFO] Mise a jour du rate limit existant..."
        # Mettre a jour le rate existant
        sed -i "/^frontend $frontend/,/^frontend\|^backend/{s/http_req_rate([0-9]*s) gt [0-9]*/http_req_rate(1s) gt $rate/}" $CONFIG_FILE
    else
        echo "[INFO] Ajout du rate limiting..."
        # Trouver la ligne apres "bind" pour inserer le rate limiting
        local line_num=$(grep -n "^frontend $frontend" $CONFIG_FILE | cut -d: -f1)
        local bind_line=$(sed -n "${line_num},/^frontend\|^backend/{/bind/=}" $CONFIG_FILE | head -1)

        if [ -n "$bind_line" ]; then
            # Inserer apres le bind
            sed -i "${bind_line}a\\
    # Rate limiting\\
    stick-table type ip size 100k expire 30s store http_req_rate(1s)\\
    http-request track-sc0 src\\
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt $rate }" $CONFIG_FILE
        fi
    fi

    echo "[OK] Rate limit configure: $rate requetes/seconde"
    echo ""

    reload_haproxy
}

remove_rate_limit() {
    local frontend=$1

    echo "============================================"
    echo "  SUPPRESSION RATE LIMIT: $frontend"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend $frontend" $CONFIG_FILE; then
        echo "[ERREUR] Frontend '$frontend' non trouve"
        exit 1
    fi

    backup_config

    # Supprimer les lignes de rate limiting
    sed -i "/^frontend $frontend/,/^frontend\|^backend/{
        /# Rate limiting/d
        /stick-table.*http_req_rate/d
        /http-request track-sc0/d
        /http-request deny.*sc_http_req_rate/d
    }" $CONFIG_FILE

    echo "[OK] Rate limit supprime"
    echo ""

    reload_haproxy
}

add_bind() {
    local frontend=$1
    local bind_addr=$2

    echo "============================================"
    echo "  AJOUT BIND: $frontend -> $bind_addr"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend $frontend" $CONFIG_FILE; then
        echo "[ERREUR] Frontend '$frontend' non trouve"
        exit 1
    fi

    backup_config

    # Trouver la derniere ligne bind du frontend et ajouter apres
    local line_num=$(grep -n "^frontend $frontend" $CONFIG_FILE | cut -d: -f1)
    local last_bind=$(sed -n "${line_num},/^frontend\|^backend/{/bind/=}" $CONFIG_FILE | tail -1)

    if [ -n "$last_bind" ]; then
        sed -i "${last_bind}a\\    bind $bind_addr" $CONFIG_FILE
        echo "[OK] Binding ajoute: $bind_addr"
    else
        echo "[ERREUR] Impossible de trouver la position pour le bind"
        exit 1
    fi
    echo ""

    reload_haproxy
}

set_default_backend() {
    local frontend=$1
    local backend=$2

    echo "============================================"
    echo "  CHANGEMENT BACKEND: $frontend -> $backend"
    echo "============================================"
    echo ""

    if ! grep -q "^frontend $frontend" $CONFIG_FILE; then
        echo "[ERREUR] Frontend '$frontend' non trouve"
        exit 1
    fi

    backup_config

    # Remplacer le default_backend
    sed -i "/^frontend $frontend/,/^frontend\|^backend/{s/default_backend.*/default_backend $backend/}" $CONFIG_FILE

    echo "[OK] Backend par defaut change: $backend"
    echo ""

    reload_haproxy
}

show_status() {
    echo "============================================"
    echo "  STATUT DES FRONTENDS"
    echo "============================================"
    echo ""

    if [ -S "$SOCKET" ]; then
        echo "show stat" | socat stdio $SOCKET 2>/dev/null | grep FRONTEND | while IFS=',' read -r pxname svname status rest; do
            printf "  %-25s %s\n" "$pxname" "$status"
        done
    else
        echo "[INFO] Socket non disponible, affichage de la configuration..."
        echo ""
        list_frontends
        return
    fi
    echo ""

    echo ">>> Test de connectivite:"
    echo ""
    grep -E "bind.*:[0-9]+" $CONFIG_FILE | grep -oE ':[0-9]+' | tr -d ':' | sort -u | while read port; do
        printf "  Port %-6s " "$port"
        if curl -s --connect-timeout 2 -o /dev/null http://localhost:$port 2>/dev/null; then
            echo "[OK]"
        else
            echo "[ERREUR]"
        fi
    done
    echo ""
}

# Main
case "${1:-help}" in
    list)
        list_frontends
        ;;
    show)
        if [ -z "$2" ]; then
            echo "Usage: $0 show <frontend>"
            exit 1
        fi
        show_frontend "$2"
        ;;
    create)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 create <name> <port> [backend]"
            exit 1
        fi
        create_frontend "$2" "$3" "$4"
        ;;
    delete)
        if [ -z "$2" ]; then
            echo "Usage: $0 delete <frontend>"
            exit 1
        fi
        delete_frontend "$2"
        ;;
    set-rate-limit)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 set-rate-limit <frontend> <rate>"
            exit 1
        fi
        set_rate_limit "$2" "$3"
        ;;
    remove-rate-limit)
        if [ -z "$2" ]; then
            echo "Usage: $0 remove-rate-limit <frontend>"
            exit 1
        fi
        remove_rate_limit "$2"
        ;;
    bind)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 bind <frontend> <ip:port>"
            exit 1
        fi
        add_bind "$2" "$3"
        ;;
    set-default-backend)
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "Usage: $0 set-default-backend <frontend> <backend>"
            exit 1
        fi
        set_default_backend "$2" "$3"
        ;;
    status)
        show_status
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
