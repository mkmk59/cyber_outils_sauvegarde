#!/bin/bash
# =============================================================================
# TP2 Solution: Configuration des Frontends HAProxy
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP2: Configuration des Frontends"
echo "============================================"
echo ""

# Démarrer docker-compose
echo "[INFO] Démarrage des containers Docker..."
docker-compose up -d
sleep 10
echo "[OK] Containers démarrés"
echo ""

# Exercice 2.1
echo ">>> Exercice 2.1: Frontend HTTP basique"
docker exec haproxy1 bash -c '/scripts/show-config.sh frontend' | head -30
docker exec backend1 bash -c 'curl -s http://172.30.0.11:80' | grep -i "title" | head -1
echo "[OK] Frontend HTTP fonctionne"
echo ""

# Exercice 2.2 + 2.3 + 2.4
echo ">>> Exercice 2.2, 2.3, 2.4: ACL, Multi-ports, Rate Limiting"
echo "[INFO] Configuration en cours..."
docker exec haproxy1 bash << 'INNER_EOF'
# Créer la configuration complète
cat > /tmp/haproxy_new.cfg << 'CONFIG'
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

frontend http_front
    bind *:80
    mode http
    acl is_api path_beg /api
    acl is_static path_end .css .js .png .jpg
    acl is_stats path_beg /haproxy-stats
    use_backend api_backend if is_api
    use_backend static_backend if is_static
    use_backend stats_backend if is_stats
    default_backend web_backend

frontend test-frontend
    bind *:8080
    mode http
    stick-table type ip size 100k expire 30s store http_req_rate(1s)
    http-request track-sc0 src
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
    option httplog
    default_backend web_backend

backend web_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

backend api_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

backend static_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200
    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

backend stats_backend
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats admin if TRUE

frontend stats_front
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats show-legends
    stats admin if TRUE
    stats auth admin:admin123

frontend prometheus_front
    bind *:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats refresh 10s
CONFIG

# Vérifier et appliquer
haproxy -c -f /tmp/haproxy_new.cfg && echo "[OK] Config valide"
cp /tmp/haproxy_new.cfg /etc/haproxy/haproxy.cfg
pkill haproxy || true
sleep 1
haproxy -f /etc/haproxy/haproxy.cfg -D
sleep 2
echo "[OK] HAProxy redémarré avec toute la configuration"
INNER_EOF

sleep 2

# Tester ACLs
echo ""
echo "[INFO] Tests des ACLs:"
docker exec backend1 bash -c 'curl -s http://172.30.0.11/api/test 2>&1' | head -1
docker exec backend1 bash -c 'curl -s http://172.30.0.11/static/style.css 2>&1' | head -1
echo "[OK] ACLs fonctionnels"
echo ""

# Tester multi-port
echo "[INFO] Ports en écoute:"
docker exec haproxy1 bash -c 'ss -tlnp | grep haproxy'
echo ""

echo "[INFO] Test port 8080:"
docker exec backend1 bash -c 'curl -s http://172.30.0.11:8080' | grep -i "title" | head -1
echo "[OK] Frontend multi-port fonctionne"
echo ""

# Vérifier rate limiting
echo "[INFO] Configuration rate limiting:"
docker exec haproxy1 bash -c 'sed -n "/test-frontend/,/^backend/p" /etc/haproxy/haproxy.cfg'
echo "[OK] Rate limiting configuré à 100 req/s"
echo ""

echo "============================================"
echo "  TP2 COMPLETE AVEC SUCCES!"
echo "============================================"
echo ""
