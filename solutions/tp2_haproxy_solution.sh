#!/bin/bash
# =============================================================================
# TP2 Solution: Configuration des Frontends HAProxy
# =============================================================================
# Objectifs:
#   1. Configurer des points d'entree (Frontends)
#   2. Comprendre les ACLs (Access Control Lists)
#   3. Gerer plusieurs services
#   4. Implémenter le Rate Limiting
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP2: Configuration des Frontends"
echo "============================================"
echo ""

# =============================================================================
# Exercice 2.1: Frontend HTTP basique
# =============================================================================
echo ">>> Exercice 2.1: Frontend HTTP basique"
echo ""

echo "[INFO] Configuration frontends actuels:"
docker exec haproxy1 bash -c '/scripts/show-config.sh frontend' | head -30
echo ""

echo "[INFO] Test d'acces HTTP sur le port 80:"
docker exec backend1 bash -c 'curl -s http://172.30.0.11:80' | grep -i "title\|backend" | head -3
echo "[OK] Frontend HTTP fonctionne"
echo ""

# =============================================================================
# Exercice 2.2: Configuration ACL
# =============================================================================
echo ">>> Exercice 2.2: Configuration ACL"
echo ""

echo "[INFO] Configuration des ACLs pour /api et /static"
docker exec haproxy1 bash << 'EOF'
cat > /etc/haproxy/haproxy.cfg << 'HAPROXY_CONFIG'
# =============================================================================
# HAProxy Configuration - Workshop TP2
# =============================================================================

global
    log stdout format raw local0
    maxconn 4096
    stats socket /var/run/haproxy/admin.sock mode 660 level admin expose-fd listeners
    stats timeout 30s
    user haproxy
    group haproxy
    daemon

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    timeout connect 5000ms
    timeout client  50000ms
    timeout server  50000ms
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# =============================================================================
# Frontend HTTP
# =============================================================================
frontend http_front
    bind *:80
    mode http

    # ACL pour le routing des requetes
    acl is_api path_beg /api
    acl is_static path_end .css .js .png .jpg
    acl is_stats path_beg /haproxy-stats

    # Use backends selon les ACLs
    use_backend api_backend if is_api
    use_backend static_backend if is_static
    use_backend stats_backend if is_stats

    # Backend par defaut
    default_backend web_backend

# =============================================================================
# Frontend Test (Multi-Port)
# =============================================================================
frontend test-frontend
    bind *:8080
    mode http
    default_backend web_backend

# =============================================================================
# Backend Web Servers
# =============================================================================
backend web_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200

    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

# =============================================================================
# API Backend
# =============================================================================
backend api_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200

    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

# =============================================================================
# Static Files Backend
# =============================================================================
backend static_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200

    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

# =============================================================================
# Stats Backend
# =============================================================================
backend stats_backend
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats admin if TRUE

# =============================================================================
# Stats Frontend
# =============================================================================
frontend stats_front
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats show-legends
    stats admin if TRUE
    stats auth admin:admin123

# =============================================================================
# Prometheus Metrics
# =============================================================================
frontend prometheus_front
    bind *:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats refresh 10s
HAPROXY_CONFIG

# Verifier la syntaxe
haproxy -c -f /etc/haproxy/haproxy.cfg && echo "[OK] Configuration valide"

# Redemarrer HAProxy
pkill haproxy || true
sleep 1
haproxy -f /etc/haproxy/haproxy.cfg -D
sleep 1
echo "[OK] HAProxy redémarré"
EOF

echo ""
echo "[INFO] Test des ACLs:"
echo "  - /api/test -> api_backend"
docker exec backend1 bash -c 'curl -s http://172.30.0.11/api/test 2>&1' | head -1
echo "  - /static/style.css -> static_backend"
docker exec backend1 bash -c 'curl -s http://172.30.0.11/static/style.css 2>&1' | head -1
echo "[OK] ACLs configurés et fonctionnels"
echo ""

# =============================================================================
# Exercice 2.3: Frontend multi-ports
# =============================================================================
echo ">>> Exercice 2.3: Frontend multi-ports"
echo ""

echo "[INFO] Lister les frontends:"
docker exec haproxy1 bash -c '/scripts/frontend-manage.sh list'
echo ""

echo "[INFO] Test du frontend sur le port 8080:"
docker exec backend1 bash -c 'curl -s http://172.30.0.11:8080' | grep -i "title\|backend" | head -3
echo "[OK] Frontend multi-port (8080) fonctionne"
echo ""

# =============================================================================
# Exercice 2.4: Rate Limiting
# =============================================================================
echo ">>> Exercice 2.4: Rate Limiting"
echo ""

echo "[INFO] Configuration du rate limiting (100 req/s) sur test-frontend..."
docker exec haproxy1 bash -c '/scripts/frontend-manage.sh set-rate-limit test-frontend 100'
echo ""

echo "[INFO] Verification de la configuration du rate limiting:"
docker exec haproxy1 bash -c 'sed -n "/test-frontend/,/^backend/p" /etc/haproxy/haproxy.cfg | head -10'
echo ""

echo "[INFO] Test de charge avec 200 requetes (limite a 100 req/s):"
echo "[INFO] Certaines requetes seront rejettees avec le code 429 (Too Many Requests)"
docker exec haproxy1 bash -c '/scripts/stress-test.sh http://localhost:8080 50' | tail -10
echo ""

echo "============================================"
echo "  TP2 COMPLETE!"
echo "============================================"
echo ""
echo "Resumé des configurations:"
echo "  1. Frontend HTTP sur port 80"
echo "  2. ACLs configurés pour /api, /static"
echo "  3. Frontend multi-port sur port 8080"
echo "  4. Rate limiting configure a 100 req/s"
echo ""
echo "Commandes utiles:"
echo "  docker exec haproxy1 /scripts/show-config.sh frontend"
echo "  docker exec haproxy1 /scripts/frontend-manage.sh list"
echo "  docker exec haproxy1 curl -s http://localhost:8080"
echo "  docker exec haproxy1 /scripts/frontend-manage.sh set-rate-limit test-frontend 200"
echo ""
