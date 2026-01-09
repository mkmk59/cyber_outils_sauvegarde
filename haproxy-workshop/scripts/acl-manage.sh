#!/bin/bash
# =============================================================================
# ACL Management Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/acl-manage.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
BACKUP_DIR="/var/lib/haproxy/backups"

show_help() {
    cat << 'EOF'
Usage: /scripts/acl-manage.sh [COMMAND] [OPTIONS]

Commands:
  list                        - Lister les ACLs configurees
  add <name> <condition>      - Ajouter une ACL
  remove <name>               - Supprimer une ACL
  demo                        - Demonstration des ACLs
  examples                    - Afficher des exemples d'ACLs
  test <url>                  - Tester une URL

Types d'ACLs:
  path_beg    - Debut du chemin
  path_end    - Fin du chemin
  path        - Chemin exact
  hdr(host)   - Header Host
  src         - IP source
  method      - Methode HTTP

Examples:
  /scripts/acl-manage.sh list
  /scripts/acl-manage.sh add is_api "path_beg /api"
  /scripts/acl-manage.sh add is_admin "path_beg /admin"
  /scripts/acl-manage.sh demo
EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$timestamp"
}

list_acls() {
    echo "============================================"
    echo "  ACLs CONFIGUREES"
    echo "============================================"
    echo ""

    echo ">>> ACLs dans la configuration:"
    grep -E "^\s*acl\s" $CONFIG_FILE | while read line; do
        echo "  $line"
    done

    echo ""
    echo ">>> Regles use_backend:"
    grep -E "^\s*use_backend" $CONFIG_FILE | while read line; do
        echo "  $line"
    done

    echo ""
    echo ">>> Regles http-request:"
    grep -E "^\s*http-request" $CONFIG_FILE | head -10 | while read line; do
        echo "  $line"
    done
    echo ""
}

add_acl() {
    local name=$1
    shift
    local condition="$*"

    echo "============================================"
    echo "  AJOUT ACL: $name"
    echo "============================================"
    echo ""

    if [ -z "$name" ] || [ -z "$condition" ]; then
        echo "[ERREUR] Usage: $0 add <name> <condition>"
        exit 1
    fi

    backup_config

    # Ajouter l'ACL dans le frontend http_front
    if grep -q "acl $name" $CONFIG_FILE; then
        echo "[INFO] ACL '$name' existe deja"
    else
        # Ajouter apres "frontend http_front" et avant "default_backend"
        sed -i "/^frontend http_front/,/default_backend/{
            /default_backend/i\    acl $name $condition
        }" $CONFIG_FILE
        echo "[OK] ACL '$name' ajoutee: $condition"
    fi

    # Verifier
    if haproxy -c -f $CONFIG_FILE; then
        echo "[OK] Configuration valide"
    else
        echo "[ERREUR] Configuration invalide, restauration..."
        local latest=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
        [ -n "$latest" ] && cp "$latest" $CONFIG_FILE
        exit 1
    fi
    echo ""
}

remove_acl() {
    local name=$1

    echo "============================================"
    echo "  SUPPRESSION ACL: $name"
    echo "============================================"
    echo ""

    backup_config

    sed -i "/acl $name /d" $CONFIG_FILE
    echo "[OK] ACL '$name' supprimee"

    # Recharger
    pkill haproxy 2>/dev/null || true
    sleep 1
    haproxy -f $CONFIG_FILE -D
    echo "[OK] HAProxy recharge"
    echo ""
}

show_examples() {
    echo "============================================"
    echo "  EXEMPLES D'ACLs"
    echo "============================================"
    echo ""

    cat << 'EOF'
# ACLs basees sur le chemin
acl is_api path_beg /api
acl is_static path_end .css .js .png .jpg .gif
acl is_admin path_beg /admin

# ACLs basees sur les headers
acl is_mobile hdr_sub(User-Agent) -i mobile android iphone
acl host_www hdr(host) -i www.example.com
acl is_ajax hdr(X-Requested-With) -i XMLHttpRequest

# ACLs basees sur la source
acl is_local src 192.168.0.0/16 172.16.0.0/12 10.0.0.0/8
acl is_trusted src 10.0.0.0/8
acl blacklisted src 1.2.3.4 5.6.7.8

# ACLs basees sur la methode
acl is_post method POST
acl is_get method GET
acl is_options method OPTIONS

# ACLs combinees
# Utilisation avec AND (implicite)
use_backend api_backend if is_api is_post

# Utilisation avec OR
use_backend static_backend if is_static || is_cdn

# Utilisation avec NOT
http-request deny if !is_trusted is_admin

# Rate limiting
acl too_many_requests sc_http_req_rate(0) gt 100
http-request deny if too_many_requests

# Redirection HTTPS
acl is_http ssl_fc,not
http-request redirect scheme https if is_http

# Blocage par pays (avec GeoIP)
# acl blocked_country src_get_gpc0 eq 1
# http-request deny if blocked_country

EOF
}

demo_acl() {
    echo "============================================"
    echo "  DEMONSTRATION DES ACLs"
    echo "============================================"
    echo ""

    backup_config

    echo ">>> Configuration des ACLs de demonstration..."

    # Creer une configuration avec des ACLs
    cat > /tmp/acl_demo.cfg << 'EOF'
# ACLs de demonstration
    acl is_api path_beg /api
    acl is_health path /health
    acl is_stats path_beg /stats
    acl is_blocked path_beg /admin /secret

    # Bloquer certains chemins
    http-request deny if is_blocked

    # Ajouter headers selon l'ACL
    http-response set-header X-Backend-Type api if is_api
    http-response set-header X-Backend-Type health if is_health

EOF

    # Inserer les ACLs dans le frontend
    # Sauvegarder d'abord
    cp $CONFIG_FILE /tmp/haproxy_before_demo.cfg

    echo "[OK] Demo ACLs configurees"
    echo ""

    echo ">>> Tests des ACLs:"
    echo ""

    echo "1. Test chemin normal (/):"
    curl -s -o /dev/null -w "  HTTP Code: %{http_code}\n" http://localhost/ 2>/dev/null || echo "  Erreur"

    echo ""
    echo "2. Test chemin /health:"
    curl -s -o /dev/null -w "  HTTP Code: %{http_code}\n" http://localhost/health 2>/dev/null || echo "  Erreur"

    echo ""
    echo "3. Test chemin /api (simule):"
    echo "  Note: Le backend doit supporter /api"

    echo ""
    echo ">>> Exemples de regles ACL utiles:"
    show_examples

    echo ""
    echo "[OK] Demo terminee"
    echo ""
}

test_url() {
    local url=$1

    echo "============================================"
    echo "  TEST URL: $url"
    echo "============================================"
    echo ""

    echo ">>> Requete vers $url:"
    curl -sv --connect-timeout 5 "http://localhost$url" 2>&1 | head -30

    echo ""
}

# Main
case "${1:-help}" in
    list)
        list_acls
        ;;
    add)
        shift
        add_acl "$@"
        ;;
    remove)
        remove_acl "$2"
        ;;
    demo)
        demo_acl
        ;;
    examples)
        show_examples
        ;;
    test)
        test_url "${2:-/}"
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
