#!/bin/bash
# =============================================================================
# SSL/TLS Management Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/ssl-manage.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

CONFIG_FILE="/etc/haproxy/haproxy.cfg"
CERT_DIR="/etc/haproxy/certs"
BACKUP_DIR="/var/lib/haproxy/backups"

show_help() {
    cat << 'EOF'
Usage: /scripts/ssl-manage.sh [COMMAND] [OPTIONS]

Commands:
  status              - Afficher le statut SSL
  generate            - Generer un certificat auto-signe
  enable              - Activer SSL termination
  disable             - Desactiver SSL
  show-cert           - Afficher les details du certificat
  test                - Tester la connexion HTTPS
  ciphers             - Afficher les ciphers configures

Examples:
  /scripts/ssl-manage.sh status
  /scripts/ssl-manage.sh generate
  /scripts/ssl-manage.sh enable
  /scripts/ssl-manage.sh test
EOF
}

backup_config() {
    mkdir -p $BACKUP_DIR
    local timestamp=$(date +%Y%m%d_%H%M%S)
    cp $CONFIG_FILE "$BACKUP_DIR/haproxy.cfg.$timestamp"
}

show_status() {
    echo "============================================"
    echo "  STATUT SSL/TLS"
    echo "============================================"
    echo ""

    # Verifier si SSL est configure
    if grep -q "bind.*ssl" $CONFIG_FILE; then
        echo "[ACTIVE] SSL/TLS est active"
        echo ""
        echo "Configuration SSL:"
        grep -E "bind.*:443|ssl crt" $CONFIG_FILE | head -10
    else
        echo "[INACTIVE] SSL/TLS n'est pas configure"
    fi
    echo ""

    # Verifier les certificats
    echo "Certificats disponibles:"
    if [ -d "$CERT_DIR" ] && [ "$(ls -A $CERT_DIR 2>/dev/null)" ]; then
        ls -la $CERT_DIR/
    else
        echo "  Aucun certificat trouve dans $CERT_DIR"
    fi
    echo ""
}

generate_cert() {
    echo "============================================"
    echo "  GENERATION CERTIFICAT AUTO-SIGNE"
    echo "============================================"
    echo ""

    mkdir -p $CERT_DIR

    local domain=${1:-workshop.local}

    echo ">>> Generation de la cle privee..."
    openssl genrsa -out $CERT_DIR/server.key 2048 2>/dev/null

    echo ">>> Generation du certificat..."
    openssl req -new -x509 -days 365 \
        -key $CERT_DIR/server.key \
        -out $CERT_DIR/server.crt \
        -subj "/C=FR/ST=IDF/L=Paris/O=Workshop/OU=HAProxy/CN=$domain" 2>/dev/null

    echo ">>> Creation du fichier PEM combine..."
    cat $CERT_DIR/server.crt $CERT_DIR/server.key > $CERT_DIR/server.pem

    chmod 600 $CERT_DIR/server.key $CERT_DIR/server.pem

    echo ""
    echo "[OK] Certificat genere:"
    echo "  - Cle:         $CERT_DIR/server.key"
    echo "  - Certificat:  $CERT_DIR/server.crt"
    echo "  - PEM:         $CERT_DIR/server.pem"
    echo "  - Domaine:     $domain"
    echo "  - Validite:    365 jours"
    echo ""
}

enable_ssl() {
    echo "============================================"
    echo "  ACTIVATION SSL TERMINATION"
    echo "============================================"
    echo ""

    # Verifier le certificat
    if [ ! -f "$CERT_DIR/server.pem" ]; then
        echo "[INFO] Certificat non trouve, generation..."
        generate_cert
    fi

    backup_config

    # Verifier si le frontend HTTPS existe deja
    if grep -q "frontend https_front" $CONFIG_FILE; then
        echo "[INFO] Frontend HTTPS existe deja"
    else
        # Ajouter le frontend HTTPS
        cat >> $CONFIG_FILE << 'EOF'

# -----------------------------------------------------------------------------
# Frontend HTTPS (SSL Termination)
# -----------------------------------------------------------------------------
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    mode http

    # Ajouter headers de securite
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    http-response set-header X-Content-Type-Options nosniff
    http-response set-header X-Frame-Options DENY

    # Ajouter header X-Forwarded-Proto
    http-request set-header X-Forwarded-Proto https

    default_backend web_backend

EOF
        echo "[OK] Frontend HTTPS ajoute"
    fi

    # Verifier et recharger
    echo ""
    echo ">>> Verification de la configuration..."
    if haproxy -c -f $CONFIG_FILE; then
        echo "[OK] Configuration valide"
        pkill haproxy 2>/dev/null || true
        sleep 1
        haproxy -f $CONFIG_FILE -D
        echo "[OK] HAProxy recharge avec SSL"
    else
        echo "[ERREUR] Configuration invalide"
        local latest=$(ls -t $BACKUP_DIR/haproxy.cfg.* 2>/dev/null | head -1)
        [ -n "$latest" ] && cp "$latest" $CONFIG_FILE
        exit 1
    fi
    echo ""
}

disable_ssl() {
    echo "============================================"
    echo "  DESACTIVATION SSL"
    echo "============================================"
    echo ""

    backup_config

    # Supprimer le frontend HTTPS
    sed -i '/^# ----.*HTTPS.*SSL/,/^frontend\|^backend\|^# ----/{/^frontend\|^backend\|^# ----/!d}' $CONFIG_FILE
    sed -i '/^frontend https_front/,/^frontend\|^backend/{/^frontend\|^backend/!d}' $CONFIG_FILE
    sed -i '/^frontend https_front/d' $CONFIG_FILE

    echo "[OK] SSL desactive"

    # Recharger
    pkill haproxy 2>/dev/null || true
    sleep 1
    haproxy -f $CONFIG_FILE -D
    echo "[OK] HAProxy recharge"
    echo ""
}

show_cert() {
    echo "============================================"
    echo "  DETAILS DU CERTIFICAT"
    echo "============================================"
    echo ""

    if [ -f "$CERT_DIR/server.crt" ]; then
        openssl x509 -in $CERT_DIR/server.crt -text -noout | head -30
    else
        echo "[ERREUR] Certificat non trouve: $CERT_DIR/server.crt"
    fi
    echo ""
}

test_ssl() {
    echo "============================================"
    echo "  TEST CONNEXION SSL/TLS"
    echo "============================================"
    echo ""

    echo ">>> Test HTTPS (port 443):"
    if curl -sk --connect-timeout 5 https://localhost/ > /dev/null 2>&1; then
        echo "[OK] HTTPS accessible"
        echo ""
        echo ">>> Details de la connexion:"
        curl -skv https://localhost/ 2>&1 | grep -E "SSL|TLS|subject|issuer|expire" | head -10
    else
        echo "[ERREUR] HTTPS non accessible"
        echo ""
        echo "Verifiez que SSL est active avec: /scripts/ssl-manage.sh enable"
    fi

    echo ""
    echo ">>> Test du certificat:"
    echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -dates 2>/dev/null || echo "Impossible de recuperer les infos du certificat"
    echo ""
}

show_ciphers() {
    echo "============================================"
    echo "  CIPHERS SSL CONFIGURES"
    echo "============================================"
    echo ""

    if grep -q "ssl-default-bind-ciphers\|ssl-default-bind-ciphersuites" $CONFIG_FILE; then
        echo "Configuration des ciphers:"
        grep -E "ssl-default-bind" $CONFIG_FILE
    else
        echo "Ciphers par defaut utilises (OpenSSL defaults)"
    fi

    echo ""
    echo ">>> Ciphers supportes par le serveur:"
    echo | openssl s_client -connect localhost:443 2>/dev/null | grep -E "Cipher|Protocol" || echo "Impossible de determiner les ciphers"
    echo ""
}

# Main
case "${1:-help}" in
    status)
        show_status
        ;;
    generate)
        generate_cert "$2"
        ;;
    enable)
        enable_ssl
        ;;
    disable)
        disable_ssl
        ;;
    show-cert|cert)
        show_cert
        ;;
    test)
        test_ssl
        ;;
    ciphers)
        show_ciphers
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
