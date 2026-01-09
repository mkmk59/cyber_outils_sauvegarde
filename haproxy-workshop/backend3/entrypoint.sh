#!/bin/bash
# =============================================================================
# Backend Web Server - Entrypoint
# =============================================================================
set +e

echo "============================================"
echo "  Backend Server - Initialisation"
echo "============================================"

# Variables d'environnement
BACKEND_NAME=${BACKEND_NAME:-backend3}
BACKEND_IP=${BACKEND_IP:-172.30.0.23}
BACKEND_COLOR=${BACKEND_COLOR:-red}

echo "Backend: $BACKEND_NAME"
echo "IP: $BACKEND_IP"
echo "Color: $BACKEND_COLOR"

# Configuration Nginx
cat > /etc/nginx/sites-available/default << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/html;
    index index.html;

    server_name _;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location /health {
        access_log off;
        return 200 "OK";
        add_header Content-Type text/plain;
    }

    location /status {
        access_log off;
        return 200 '{"server": "$BACKEND_NAME", "ip": "$BACKEND_IP", "status": "healthy"}';
        add_header Content-Type application/json;
    }

    location /slow {
        access_log off;
        return 200 "Slow response from $BACKEND_NAME";
        add_header Content-Type text/plain;
    }
}
EOF

# Creer la page HTML
mkdir -p /var/www/html
cat > /var/www/html/index.html << EOF
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Backend Server - $BACKEND_NAME</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            text-align: center;
            max-width: 500px;
            width: 90%;
        }
        .server-icon {
            font-size: 80px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 2.5em;
        }
        .server-name {
            display: inline-block;
            background: $BACKEND_COLOR;
            color: white;
            padding: 10px 30px;
            border-radius: 50px;
            font-size: 1.5em;
            margin: 20px 0;
            text-transform: uppercase;
            letter-spacing: 2px;
        }
        .info {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 20px;
            margin-top: 20px;
        }
        .info p {
            margin: 10px 0;
            color: #666;
            font-size: 1.1em;
        }
        .info strong {
            color: #333;
        }
        .status {
            display: inline-block;
            background: #28a745;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            margin-top: 15px;
        }
        .timestamp {
            color: #999;
            font-size: 0.85em;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="server-icon">🖥️</div>
        <h1>HAProxy Workshop</h1>
        <div class="server-name" style="background: $BACKEND_COLOR;">$BACKEND_NAME</div>
        <div class="info">
            <p><strong>Hostname:</strong> $BACKEND_NAME</p>
            <p><strong>IP Address:</strong> $BACKEND_IP</p>
            <p><strong>Server Color:</strong> <span style="color: $BACKEND_COLOR; font-weight: bold;">$BACKEND_COLOR</span></p>
            <span class="status">✓ Healthy</span>
        </div>
        <p class="timestamp">Server Time: <script>document.write(new Date().toLocaleString());</script></p>
    </div>
</body>
</html>
EOF

# Creer une page pour les tests de charge
cat > /var/www/html/load.html << EOF
<!DOCTYPE html>
<html>
<head><title>Load Test - $BACKEND_NAME</title></head>
<body>
<h1>Load Test Response from $BACKEND_NAME</h1>
<p>This page is served from $BACKEND_NAME ($BACKEND_IP)</p>
<p>Request ID: \$(date +%s%N)</p>
</body>
</html>
EOF

# Creer le fichier health check
cat > /var/www/html/health << EOF
OK
EOF

# Demarrer Nginx
echo ""
echo ">>> Demarrage de Nginx..."
nginx -g 'daemon off;' &

echo ""
echo "============================================"
echo "  Backend Server - Ready"
echo "============================================"
echo ""
echo "Endpoints disponibles:"
echo "  - Homepage:   http://$BACKEND_IP/"
echo "  - Health:     http://$BACKEND_IP/health"
echo "  - Status:     http://$BACKEND_IP/status"
echo "  - Load Test:  http://$BACKEND_IP/load.html"
echo ""

# Garder le container en vie
exec tail -f /dev/null
