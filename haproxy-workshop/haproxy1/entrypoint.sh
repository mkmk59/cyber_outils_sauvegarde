#!/bin/bash
# =============================================================================
# HAProxy Master Node - Entrypoint
# =============================================================================
set +e

echo "============================================"
echo "  HAProxy Master Node - Initialisation"
echo "============================================"

# Variables d'environnement
HAPROXY_NODE_NAME=${HAPROXY_NODE_NAME:-haproxy1}
HAPROXY_NODE_IP=${HAPROXY_NODE_IP:-172.30.0.11}
HAPROXY_ROLE=${HAPROXY_ROLE:-MASTER}
KEEPALIVED_PRIORITY=${KEEPALIVED_PRIORITY:-101}
KEEPALIVED_STATE=${KEEPALIVED_STATE:-MASTER}
VIP_ADDRESS=${VIP_ADDRESS:-172.30.0.100}

echo "Node: $HAPROXY_NODE_NAME"
echo "IP: $HAPROXY_NODE_IP"
echo "Role: $HAPROXY_ROLE"
echo "VIP: $VIP_ADDRESS"

# Configuration HAProxy initiale (basique)
cat > /etc/haproxy/haproxy.cfg << 'EOF'
# =============================================================================
# HAProxy Configuration - Workshop
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

# -----------------------------------------------------------------------------
# Frontend HTTP
# -----------------------------------------------------------------------------
frontend http_front
    bind *:80
    mode http

    # ACL pour le stats
    acl is_stats path_beg /haproxy-stats
    use_backend stats_backend if is_stats

    # Backend par defaut
    default_backend web_backend

# -----------------------------------------------------------------------------
# Backend Web Servers
# -----------------------------------------------------------------------------
backend web_backend
    mode http
    balance roundrobin
    option httpchk GET /health
    http-check expect status 200

    server backend1 172.30.0.21:80 check inter 2000 rise 2 fall 3
    server backend2 172.30.0.22:80 check inter 2000 rise 2 fall 3
    server backend3 172.30.0.23:80 check inter 2000 rise 2 fall 3

# -----------------------------------------------------------------------------
# Stats Backend
# -----------------------------------------------------------------------------
backend stats_backend
    mode http
    stats enable
    stats uri /
    stats refresh 5s
    stats show-legends
    stats admin if TRUE

# -----------------------------------------------------------------------------
# Stats Frontend (dedié)
# -----------------------------------------------------------------------------
frontend stats_front
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 5s
    stats show-legends
    stats admin if TRUE
    stats auth admin:admin123

# -----------------------------------------------------------------------------
# Prometheus Metrics
# -----------------------------------------------------------------------------
frontend prometheus_front
    bind *:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
    stats enable
    stats uri /stats
    stats refresh 10s

EOF

# Creer les pages d'erreur
mkdir -p /etc/haproxy/errors

cat > /etc/haproxy/errors/400.http << 'ERROREOF'
HTTP/1.0 400 Bad Request
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>400 Bad Request</h1>
Your browser sent an invalid request.
</body></html>
ERROREOF

cat > /etc/haproxy/errors/403.http << 'ERROREOF'
HTTP/1.0 403 Forbidden
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>403 Forbidden</h1>
Request forbidden by administrative rules.
</body></html>
ERROREOF

cat > /etc/haproxy/errors/408.http << 'ERROREOF'
HTTP/1.0 408 Request Time-out
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>408 Request Time-out</h1>
Your browser didn't send a complete request in time.
</body></html>
ERROREOF

cat > /etc/haproxy/errors/500.http << 'ERROREOF'
HTTP/1.0 500 Internal Server Error
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>500 Internal Server Error</h1>
An internal server error occurred.
</body></html>
ERROREOF

cat > /etc/haproxy/errors/502.http << 'ERROREOF'
HTTP/1.0 502 Bad Gateway
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>502 Bad Gateway</h1>
The server returned an invalid or incomplete response.
</body></html>
ERROREOF

cat > /etc/haproxy/errors/503.http << 'ERROREOF'
HTTP/1.0 503 Service Unavailable
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>503 Service Unavailable</h1>
No server is available to handle this request.
</body></html>
ERROREOF

cat > /etc/haproxy/errors/504.http << 'ERROREOF'
HTTP/1.0 504 Gateway Time-out
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<html><body><h1>504 Gateway Time-out</h1>
The server didn't respond in time.
</body></html>
ERROREOF

# Configuration Keepalived
cat > /etc/keepalived/keepalived.conf << EOF
# =============================================================================
# Keepalived Configuration - $HAPROXY_NODE_NAME
# =============================================================================

global_defs {
    router_id $HAPROXY_NODE_NAME
    script_user root
    enable_script_security
}

vrrp_script check_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight 2
    fall 2
    rise 2
}

vrrp_instance VI_1 {
    state $KEEPALIVED_STATE
    interface eth0
    virtual_router_id 51
    priority $KEEPALIVED_PRIORITY
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass haproxy123
    }

    virtual_ipaddress {
        $VIP_ADDRESS/16 dev eth0
    }

    track_script {
        check_haproxy
    }
}
EOF

# Demarrer HAProxy
echo ""
echo ">>> Demarrage de HAProxy..."
haproxy -f /etc/haproxy/haproxy.cfg -D

# Demarrer Keepalived
echo ">>> Demarrage de Keepalived..."
keepalived --dont-fork --log-console &

echo ""
echo "============================================"
echo "  HAProxy Master Node - Ready"
echo "============================================"
echo ""
echo "Services disponibles:"
echo "  - HTTP:       http://$HAPROXY_NODE_IP:80"
echo "  - Stats:      http://$HAPROXY_NODE_IP:8404/stats"
echo "  - Prometheus: http://$HAPROXY_NODE_IP:8405/metrics"
echo "  - VIP:        http://$VIP_ADDRESS:80"
echo ""

# Garder le container en vie
exec tail -f /dev/null
