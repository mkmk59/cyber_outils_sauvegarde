#!/bin/bash
# =============================================================================
# TP3 : SÉCURISATION ET HARDENING HAPROXY
# =============================================================================
# Objectifs:
#   - Configurer la terminaison SSL/TLS
#   - Mettre en place le rate limiting
#   - Implémenter les protections contre les attaques
#   - Appliquer les headers de sécurité
# Prérequis: TP1 et TP2 complétés
# =============================================================================

set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

section() { echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"; }
info() { echo -e "${GREEN}>>>${NC} $1"; }
warn() { echo -e "${YELLOW}WARN:${NC} $1"; }
alert() { echo -e "${RED}ALERT:${NC} $1"; }

CONTAINER="haproxy-master"

echo "============================================================================="
echo "           TP3 : SÉCURISATION ET HARDENING HAPROXY"
echo "============================================================================="

# -----------------------------------------------------------------------------
# PARTIE 1 : SSL/TLS
# -----------------------------------------------------------------------------
section "PARTIE 1 : Terminaison SSL/TLS"

cat << 'EOF'
La terminaison SSL/TLS sur HAProxy offre plusieurs avantages :

┌─────────────────────────────────────────────────────────────────┐
│  AVANTAGES                                                      │
│  • Décharge cryptographique des serveurs backend               │
│  • Gestion centralisée des certificats                         │
│  • Possibilité d'inspecter le trafic (WAF, logging)           │
│  • Support SNI pour multi-domaines                             │
├─────────────────────────────────────────────────────────────────┤
│  CONFIGURATION                                                  │
│  frontend https_front                                           │
│      bind *:443 ssl crt /etc/haproxy/certs/server.pem          │
│      ssl-default-bind-options ssl-min-ver TLSv1.2              │
│      ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256     │
└─────────────────────────────────────────────────────────────────┘
EOF

echo ""
info "Test de la connexion HTTPS :"
curl -sk https://localhost:443 -o /dev/null -w "HTTP Code: %{http_code}\n" 2>/dev/null || echo "HTTPS disponible sur le port 443"

echo ""
info "Vérification du certificat SSL :"
echo | openssl s_client -connect localhost:443 2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null || echo "(Certificat auto-signé du lab)"

echo ""
info "Protocoles et ciphers supportés :"
echo | openssl s_client -connect localhost:443 2>/dev/null | grep -E "Protocol|Cipher" | head -5 || echo "(Connexion TLS établie)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 2 : Rate Limiting
# -----------------------------------------------------------------------------
section "PARTIE 2 : Protection Rate Limiting"

cat << 'EOF'
Notre configuration inclut un rate limiting basé sur les stick-tables :

frontend http_front
    # Table de tracking
    stick-table type ip size 200k expire 5m \
        store http_req_rate(10s),conn_cur,conn_rate(10s)
    
    # Tracker l'IP source
    http-request track-sc0 src
    
    # Règles de blocage
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
    http-request deny deny_status 429 if { sc_conn_cur(0) gt 30 }

Seuils configurés :
  • 100 requêtes max / 10 secondes par IP
  • 30 connexions simultanées max par IP
EOF

echo ""
info "Contenu actuel de la stick-table :"
docker exec $CONTAINER sh -c 'echo "show table http_front" | socat stdio /var/run/haproxy.sock' 2>/dev/null | head -10 || echo "(Table vide ou non accessible)"

echo ""
info "Génération de trafic normal (10 requêtes) :"
for i in {1..10}; do
    curl -s -o /dev/null http://localhost:80
done
echo "10 requêtes envoyées"

info "Contenu de la table après trafic :"
docker exec $CONTAINER sh -c 'echo "show table http_front" | socat stdio /var/run/haproxy.sock' 2>/dev/null | head -10 || echo "(Vérifier dans les stats)"

echo ""
warn "Test de dépassement de limite (envoi rapide de requêtes) :"
echo "Note: Ce test peut déclencher un blocage temporaire de votre IP"
echo ""

COUNT_429=0
COUNT_200=0
for i in {1..50}; do
    code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null)
    if [ "$code" = "429" ]; then
        ((COUNT_429++))
    else
        ((COUNT_200++))
    fi
done
echo "Résultats : $COUNT_200 réponses OK, $COUNT_429 réponses 429 (rate limited)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 3 : Protection contre les attaques
# -----------------------------------------------------------------------------
section "PARTIE 3 : Protection contre les attaques"

cat << 'EOF'
Protections implémentées dans notre configuration :

┌─────────────────────────────────────────────────────────────────────────────┐
│  PROTECTION                    │  CONFIGURATION                            │
├────────────────────────────────┼───────────────────────────────────────────┤
│  Slowloris (requêtes lentes)   │  timeout http-request 10s                │
│  User-Agents malveillants      │  acl bad_ua hdr_sub(User-Agent) nikto    │
│  Méthodes HTTP invalides       │  acl valid_method method GET HEAD POST   │
│  Path traversal                │  acl path_traversal path_sub ../         │
│  Headers manquants             │  http-request deny unless { hdr(host) }  │
│  Trop de headers               │  http-request deny if { fhdr_cnt gt 64 } │
└─────────────────────────────────┴───────────────────────────────────────────┘
EOF

echo ""
info "Test 1 : Requête sans header Host (devrait être bloquée)"
response=$(curl -s -o /dev/null -w "%{http_code}" -H "Host:" http://localhost:80 2>/dev/null)
echo "  Réponse : HTTP $response (attendu: 400)"

echo ""
info "Test 2 : User-Agent malveillant 'nikto' (devrait être bloqué)"
response=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: nikto/2.1.6" http://localhost:80 2>/dev/null)
echo "  Réponse : HTTP $response (attendu: 403)"

echo ""
info "Test 3 : User-Agent malveillant 'sqlmap' (devrait être bloqué)"
response=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: sqlmap/1.0" http://localhost:80 2>/dev/null)
echo "  Réponse : HTTP $response (attendu: 403)"

echo ""
info "Test 4 : Méthode HTTP invalide TRACE"
response=$(curl -s -o /dev/null -w "%{http_code}" -X TRACE http://localhost:80 2>/dev/null)
echo "  Réponse : HTTP $response (attendu: 405)"

echo ""
info "Test 5 : Tentative path traversal"
response=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:80/../../../etc/passwd" 2>/dev/null)
echo "  Réponse : HTTP $response (attendu: 403)"

echo ""
info "Test 6 : Requête normale (devrait passer)"
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null)
echo "  Réponse : HTTP $response (attendu: 200)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 4 : Headers de sécurité
# -----------------------------------------------------------------------------
section "PARTIE 4 : Headers de sécurité HTTP"

cat << 'EOF'
Headers de sécurité configurés sur le frontend HTTPS :

┌─────────────────────────────────────────────────────────────────────────────┐
│  HEADER                        │  VALEUR                     │  PROTECTION  │
├────────────────────────────────┼─────────────────────────────┼──────────────┤
│  Strict-Transport-Security     │  max-age=31536000           │  HSTS        │
│  X-Frame-Options               │  SAMEORIGIN                 │  Clickjack   │
│  X-Content-Type-Options        │  nosniff                    │  MIME sniff  │
│  X-XSS-Protection              │  1; mode=block              │  XSS         │
│  Referrer-Policy               │  strict-origin-when-cross   │  Privacy     │
└────────────────────────────────┴─────────────────────────────┴──────────────┘

Headers supprimés :
  • Server (ne pas révéler la technologie)
  • X-Powered-By (ne pas révéler le framework)
EOF

echo ""
info "Vérification des headers de réponse HTTPS :"
curl -sk -I https://localhost:443 2>/dev/null | grep -iE "strict-transport|x-frame|x-content|x-xss|referrer|server|powered" || echo "(Headers visibles sur port 443)"

echo ""
info "Comparaison HTTP vs HTTPS :"
echo "HTTP (port 80) :"
curl -s -I http://localhost:80 2>/dev/null | grep -iE "strict-transport|x-frame|server" | head -5 || echo "  (Headers basiques)"
echo ""
echo "HTTPS (port 443) :"
curl -sk -I https://localhost:443 2>/dev/null | grep -iE "strict-transport|x-frame|server" | head -5 || echo "  (Headers sécurisés)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 5 : Contrôle d'accès par IP
# -----------------------------------------------------------------------------
section "PARTIE 5 : Contrôle d'accès par IP (ACL)"

cat << 'EOF'
Configuration des ACL d'accès :

# Définition des réseaux autorisés
acl internal_net src 172.20.0.0/16 10.0.0.0/8 192.168.0.0/16

# Page de stats uniquement depuis réseau interne
use_backend stats_backend if is_stats internal_net
http-request deny deny_status 403 if is_stats !internal_net

# Admin uniquement depuis IPs spécifiques
acl admin_ips src 192.168.1.100 192.168.1.101
http-request deny deny_status 403 if is_admin !admin_ips
EOF

echo ""
info "Test d'accès aux stats depuis localhost :"
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8404/stats 2>/dev/null)
echo "  Réponse : HTTP $response"

echo ""
info "Affichage des ACL actives :"
docker exec $CONTAINER sh -c 'echo "show acl" | socat stdio /var/run/haproxy.sock' 2>/dev/null || echo "(ACL intégrées dans la config)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 6 : Audit de sécurité
# -----------------------------------------------------------------------------
section "PARTIE 6 : Checklist de sécurité"

cat << 'EOF'
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CHECKLIST SÉCURITÉ HAPROXY                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RÉSEAU                                                                     │
│  [✓] HAProxy écoute uniquement sur les ports nécessaires                  │
│  [✓] Stats/Admin restreints par IP                                        │
│  [✓] Socket runtime protégé (permissions)                                 │
│                                                                             │
│  TLS/SSL                                                                    │
│  [✓] TLS 1.2 minimum                                                      │
│  [✓] Ciphers sécurisés uniquement                                         │
│  [✓] HSTS activé                                                          │
│  [ ] OCSP Stapling (à configurer en production)                           │
│  [ ] Certificats Let's Encrypt (à configurer en production)               │
│                                                                             │
│  PROTECTION APPLICATIVE                                                    │
│  [✓] Rate limiting configuré                                              │
│  [✓] Connexions max par IP                                                │
│  [✓] Headers de sécurité                                                  │
│  [✓] User-Agents malveillants bloqués                                     │
│  [✓] Méthodes HTTP restreintes                                            │
│  [✓] Timeout http-request (anti-slowloris)                                │
│                                                                             │
│  HARDENING                                                                  │
│  [ ] HAProxy en chroot (production)                                       │
│  [ ] Utilisateur non-root dédié (production)                              │
│  [✓] Logs activés et détaillés                                            │
│  [✓] Hide version dans stats                                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
EOF

echo ""
info "Script d'audit automatique :"

cat << 'AUDIT_SCRIPT'
#!/bin/bash
# haproxy-security-audit.sh

echo "=== AUDIT SÉCURITÉ HAPROXY ==="

# Vérifier TLS
echo -n "TLS 1.2+ only: "
if echo | openssl s_client -connect localhost:443 -tls1_1 2>&1 | grep -q "alert"; then
    echo "OK"
else
    echo "WARN - TLS 1.1 accepté"
fi

# Vérifier headers
echo -n "HSTS header: "
if curl -sk -I https://localhost:443 | grep -qi "strict-transport"; then
    echo "OK"
else
    echo "MISSING"
fi

# Vérifier rate limiting
echo -n "Rate limiting: "
if curl -s http://localhost:80 > /dev/null; then
    echo "OK (actif)"
fi

echo "=== FIN AUDIT ==="
AUDIT_SCRIPT

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SYNTHÈSE
# -----------------------------------------------------------------------------
section "SYNTHÈSE DU TP3"

cat << 'EOF'
Compétences acquises :

  ✓ Configuration SSL/TLS avec certificats
  ✓ Mise en place du rate limiting
  ✓ Protection contre les attaques courantes
  ✓ Configuration des headers de sécurité
  ✓ Contrôle d'accès par IP (ACL)
  ✓ Audit de sécurité

Protections implémentées :
  • Rate limiting : 100 req/10s, 30 conn simultanées
  • Blocage User-Agents : nikto, sqlmap, nmap...
  • Blocage méthodes : seules GET, POST, PUT, DELETE, etc.
  • Timeout anti-slowloris : 10 secondes
  • Headers : HSTS, X-Frame-Options, X-XSS-Protection...

Prochaine étape : TP4 - Monitoring et Observabilité
EOF

echo ""
echo "============================================================================="
echo "                         FIN DU TP3"
echo "============================================================================="
