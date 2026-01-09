#!/bin/bash
# =============================================================================
# SCRIPT DE DÉPLOIEMENT LAB HAPROXY - PS/PCA
# =============================================================================
# Ce script prépare et déploie l'environnement complet du lab
# =============================================================================

set -e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# -----------------------------------------------------------------------------
# Vérification prérequis
# -----------------------------------------------------------------------------
check_prerequisites() {
    log_info "Vérification des prérequis..."
    
    if ! command -v docker &> /dev/null; then
        log_error "Docker n'est pas installé"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose n'est pas installé"
        exit 1
    fi
    
    log_success "Prérequis OK"
}

# -----------------------------------------------------------------------------
# Création de l'arborescence
# -----------------------------------------------------------------------------
create_directories() {
    log_info "Création de l'arborescence..."
    
    mkdir -p config
    mkdir -p certs
    mkdir -p errors
    mkdir -p webapps/web1
    mkdir -p webapps/web2
    mkdir -p webapps/web3
    mkdir -p api
    mkdir -p scripts
    
    log_success "Arborescence créée"
}

# -----------------------------------------------------------------------------
# Génération du certificat SSL auto-signé
# -----------------------------------------------------------------------------
generate_certificates() {
    log_info "Génération des certificats SSL..."
    
    if [ -f "certs/server.pem" ]; then
        log_warning "Certificat existant, conservation"
        return
    fi
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout certs/server.key \
        -out certs/server.crt \
        -subj "/C=FR/ST=IDF/L=Paris/O=Training/OU=PSPCA/CN=haproxy.local" \
        2>/dev/null
    
    cat certs/server.crt certs/server.key > certs/server.pem
    
    log_success "Certificats générés"
}

# -----------------------------------------------------------------------------
# Création des pages web de test
# -----------------------------------------------------------------------------
create_webapps() {
    log_info "Création des applications web de test..."
    
    for i in 1 2 3; do
        cat > webapps/web$i/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>Web Server $i</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
        }
        .container {
            text-align: center;
            padding: 40px;
            background: rgba(255,255,255,0.1);
            border-radius: 20px;
            backdrop-filter: blur(10px);
        }
        h1 { font-size: 3em; margin-bottom: 10px; }
        .server-id {
            font-size: 5em;
            font-weight: bold;
            color: #ffd700;
        }
        .info { margin-top: 20px; font-size: 1.2em; }
        .timestamp { color: #ccc; font-size: 0.9em; margin-top: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🖥️ Web Server</h1>
        <div class="server-id">$i</div>
        <div class="info">
            <p>Backend: web$i (172.21.0.2$i)</p>
            <p>Formation HAProxy PS/PCA</p>
        </div>
        <div class="timestamp">
            <script>document.write(new Date().toLocaleString());</script>
        </div>
    </div>
</body>
</html>
EOF
        
        # Page de health check
        cat > webapps/web$i/health << EOF
OK - web$i
EOF
    done
    
    log_success "Applications web créées"
}

# -----------------------------------------------------------------------------
# Configuration Nginx pour health checks
# -----------------------------------------------------------------------------
create_nginx_config() {
    log_info "Création de la configuration Nginx..."
    
    cat > config/nginx-health.conf << 'EOF'
server {
    listen 80;
    server_name localhost;

    location / {
        root /usr/share/nginx/html;
        index index.html;
    }

    location /health {
        access_log off;
        return 200 'OK';
        add_header Content-Type text/plain;
    }

    location /ready {
        access_log off;
        return 200 'READY';
        add_header Content-Type text/plain;
    }

    location /live {
        access_log off;
        return 200 'LIVE';
        add_header Content-Type text/plain;
    }
}
EOF
    
    log_success "Configuration Nginx créée"
}

# -----------------------------------------------------------------------------
# Configuration HAProxy
# -----------------------------------------------------------------------------
create_haproxy_config() {
    log_info "Création de la configuration HAProxy..."

    cat > config/haproxy.cfg << 'EOF'
# =============================================================================
# CONFIGURATION HAPROXY - LAB PS/PCA
# =============================================================================

global
    log stdout format raw local0
    maxconn 4096
    stats socket /tmp/haproxy.sock mode 660 level admin expose-fd listeners
    stats timeout 30s

defaults
    log     global
    mode    http
    option  httplog
    option  dontlognull
    option  forwardfor
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
    default_backend web_backend

    # ACL pour l'API
    acl is_api path_beg /api
    use_backend api_backend if is_api

# -----------------------------------------------------------------------------
# Frontend HTTPS
# -----------------------------------------------------------------------------
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    default_backend web_backend

    acl is_api path_beg /api
    use_backend api_backend if is_api

# -----------------------------------------------------------------------------
# Frontend Stats
# -----------------------------------------------------------------------------
frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:P@ssw0rd_HAProxy_2024!
    http-request use-service prometheus-exporter if { path /metrics }

# -----------------------------------------------------------------------------
# Backend Web Servers
# -----------------------------------------------------------------------------
backend web_backend
    balance roundrobin
    option http-server-close
    option httpchk GET /health
    http-check expect status 200

    server web1 172.21.0.21:80 check inter 2s fall 3 rise 2
    server web2 172.21.0.22:80 check inter 2s fall 3 rise 2
    server web3 172.21.0.23:80 check inter 2s fall 3 rise 2 backup

# -----------------------------------------------------------------------------
# Backend API
# -----------------------------------------------------------------------------
backend api_backend
    balance roundrobin
    server api1 172.21.0.31:8080 check
EOF

    log_success "Configuration HAProxy créée"
}

# -----------------------------------------------------------------------------
# Création de l'API de test
# -----------------------------------------------------------------------------
create_api() {
    log_info "Création de l'API de test..."
    
    cat > api/index.html << 'EOF'
{"service": "api", "status": "running", "version": "1.0.0"}
EOF
    
    cat > api/health << 'EOF'
{"status": "healthy"}
EOF
    
    log_success "API créée"
}

# -----------------------------------------------------------------------------
# Configuration Prometheus
# -----------------------------------------------------------------------------
create_prometheus_config() {
    log_info "Création de la configuration Prometheus..."
    
    cat > config/prometheus.yml << 'EOF'
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy-master:8404', 'haproxy-backup:8404']
    metrics_path: /metrics
EOF
    
    log_success "Configuration Prometheus créée"
}

# -----------------------------------------------------------------------------
# Création des pages d'erreur personnalisées
# -----------------------------------------------------------------------------
create_error_pages() {
    log_info "Création des pages d'erreur..."
    
    for code in 400 403 408 500 502 503 504; do
        cat > errors/$code.http << EOF
HTTP/1.1 $code Error
Cache-Control: no-cache
Connection: close
Content-Type: text/html

<!DOCTYPE html>
<html>
<head>
    <title>Error $code</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background: #1a1a2e;
            color: #eee;
        }
        .error-container {
            text-align: center;
        }
        .error-code {
            font-size: 8em;
            color: #e94560;
            margin: 0;
        }
        .error-message {
            font-size: 1.5em;
            color: #888;
        }
    </style>
</head>
<body>
    <div class="error-container">
        <h1 class="error-code">$code</h1>
        <p class="error-message">Service Temporarily Unavailable</p>
        <p>HAProxy PS/PCA Training</p>
    </div>
</body>
</html>
EOF
    done
    
    log_success "Pages d'erreur créées"
}

# -----------------------------------------------------------------------------
# Déploiement Docker
# -----------------------------------------------------------------------------
deploy_docker() {
    log_info "Déploiement des conteneurs..."
    
    # Arrêt des conteneurs existants
    docker-compose down 2>/dev/null || docker compose down 2>/dev/null || true
    
    # Démarrage
    if command -v docker-compose &> /dev/null; then
        docker-compose up -d
    else
        docker compose up -d
    fi
    
    log_success "Conteneurs déployés"
}

# -----------------------------------------------------------------------------
# Vérification du déploiement
# -----------------------------------------------------------------------------
verify_deployment() {
    log_info "Vérification du déploiement (30 secondes)..."
    
    sleep 10
    
    # Vérifier que les conteneurs sont up
    local containers=("haproxy-master" "web1" "web2" "web3")
    for container in "${containers[@]}"; do
        if docker ps | grep -q "$container"; then
            log_success "$container: Running"
        else
            log_error "$container: Not running"
        fi
    done
    
    # Test de connectivité
    sleep 5
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:80 | grep -q "200"; then
        log_success "HAProxy répond sur le port 80"
    else
        log_warning "HAProxy ne répond pas encore (peut nécessiter quelques secondes)"
    fi
}

# -----------------------------------------------------------------------------
# Affichage des informations
# -----------------------------------------------------------------------------
show_info() {
    echo ""
    echo "============================================================================="
    echo "           LAB HAPROXY PS/PCA - DÉPLOIEMENT TERMINÉ"
    echo "============================================================================="
    echo ""
    echo "ACCÈS:"
    echo "  • Application Web    : http://localhost:80"
    echo "  • HTTPS              : https://localhost:443"
    echo "  • Statistiques       : http://localhost:8404/stats"
    echo "  • Prometheus         : http://localhost:9090"
    echo "  • Grafana            : http://localhost:3000"
    echo ""
    echo "CREDENTIALS:"
    echo "  • HAProxy Stats      : admin / P@ssw0rd_HAProxy_2024!"
    echo "  • Grafana            : admin / admin"
    echo ""
    echo "COMMANDES UTILES:"
    echo "  • Logs HAProxy       : docker logs -f haproxy-master"
    echo "  • Shell HAProxy      : docker exec -it haproxy-master sh"
    echo "  • Stats CLI          : docker exec haproxy-master sh -c 'echo \"show stat\" | socat stdio /tmp/haproxy.sock'"
    echo "  • Reload config      : docker kill -s HUP haproxy-master"
    echo ""
    echo "TESTS:"
    echo "  • Failover web1      : docker stop web1"
    echo "  • Restaurer web1     : docker start web1"
    echo "  • Test charge        : ab -n 1000 -c 100 http://localhost/"
    echo ""
    echo "============================================================================="
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================================================="
    echo "       DÉPLOIEMENT LAB HAPROXY - FORMATION PS/PCA"
    echo "============================================================================="
    echo ""
    
    check_prerequisites
    create_directories
    generate_certificates
    create_webapps
    create_nginx_config
    create_haproxy_config
    create_api
    create_prometheus_config
    create_error_pages
    deploy_docker
    verify_deployment
    show_info
}

main "$@"
