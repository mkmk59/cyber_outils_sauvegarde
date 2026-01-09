#!/bin/bash
# =============================================================================
# TP4 : MONITORING ET OBSERVABILITÉ
# =============================================================================
# Objectifs:
#   - Maîtriser la page de statistiques
#   - Configurer l'export Prometheus
#   - Analyser les logs HAProxy
#   - Mettre en place des alertes
# Prérequis: TP1, TP2, TP3 complétés
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

CONTAINER="haproxy-master"

echo "============================================================================="
echo "           TP4 : MONITORING ET OBSERVABILITÉ"
echo "============================================================================="

# -----------------------------------------------------------------------------
# PARTIE 1 : Page de statistiques
# -----------------------------------------------------------------------------
section "PARTIE 1 : Page de statistiques détaillée"

cat << 'EOF'
La page de statistiques HAProxy fournit des métriques en temps réel :

URL : http://localhost:8404/stats
Credentials : admin / P@ssw0rd_HAProxy_2024!

Informations disponibles :
┌─────────────────────────────────────────────────────────────────────────────┐
│  FRONTEND                          │  BACKEND / SERVER                      │
├────────────────────────────────────┼────────────────────────────────────────┤
│  • Sessions courantes/max          │  • État (UP/DOWN/DRAIN)               │
│  • Sessions totales                │  • Sessions actives                    │
│  • Bytes in/out                    │  • Temps de réponse                    │
│  • Requêtes/seconde                │  • Health check status                 │
│  • Erreurs connexion               │  • Poids effectif                      │
│  • Requêtes refusées               │  • Downtime cumulé                     │
└────────────────────────────────────┴────────────────────────────────────────┘
EOF

echo ""
info "Accès aux statistiques en format CSV :"
echo ""
curl -s -u admin:P@ssw0rd_HAProxy_2024! "http://localhost:8404/stats;csv" 2>/dev/null | head -5

echo ""
info "Colonnes importantes du CSV :"
cat << 'EOF'
  • pxname  : Nom du proxy (frontend/backend)
  • svname  : Nom du serveur
  • status  : UP, DOWN, DRAIN, MAINT
  • weight  : Poids du serveur
  • scur    : Sessions courantes
  • smax    : Sessions max atteintes
  • stot    : Sessions totales
  • bin/bout: Bytes in/out
  • dreq    : Requêtes refusées
  • ereq    : Erreurs requêtes
  • hrsp_4xx: Réponses 4xx
  • hrsp_5xx: Réponses 5xx
EOF

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 2 : Runtime API - Statistiques avancées
# -----------------------------------------------------------------------------
section "PARTIE 2 : Statistiques via Runtime API"

info "Commande: show info - Informations générales"
docker exec $CONTAINER sh -c 'echo "show info" | socat stdio /var/run/haproxy.sock' 2>/dev/null | grep -E "Name|Version|Uptime|CurrConns|MaxConn|Tasks|Run_queue"

echo ""
info "Commande: show stat - Résumé des backends"
echo "Format: backend,server,status,sessions"
docker exec $CONTAINER sh -c 'echo "show stat" | socat stdio /var/run/haproxy.sock' 2>/dev/null | grep -E "^web_servers|^api_servers" | cut -d',' -f1,2,18,5

echo ""
info "Commande: show servers state - État détaillé des serveurs"
docker exec $CONTAINER sh -c 'echo "show servers state" | socat stdio /var/run/haproxy.sock' 2>/dev/null

echo ""
info "Commande: show sess - Sessions actives"
docker exec $CONTAINER sh -c 'echo "show sess" | socat stdio /var/run/haproxy.sock' 2>/dev/null | head -10 || echo "(Aucune session active)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 3 : Métriques Prometheus
# -----------------------------------------------------------------------------
section "PARTIE 3 : Export Prometheus"

cat << 'EOF'
HAProxy expose nativement des métriques au format Prometheus.

Configuration :
  frontend prometheus
      bind *:8404
      http-request use-service prometheus-exporter if { path /metrics }

Endpoint : http://localhost:8404/metrics
EOF

echo ""
info "Aperçu des métriques Prometheus :"
curl -s http://localhost:8404/metrics 2>/dev/null | grep -E "^haproxy_" | head -20 || echo "(Métriques sur /metrics)"

echo ""
info "Métriques clés pour le monitoring PS/PCA :"
cat << 'EOF'
┌─────────────────────────────────────────────────────────────────────────────┐
│  MÉTRIQUE                                    │  USAGE                       │
├──────────────────────────────────────────────┼──────────────────────────────┤
│  haproxy_backend_up                          │  Santé backend (1=UP, 0=DOWN)│
│  haproxy_backend_current_sessions            │  Sessions actives            │
│  haproxy_backend_http_responses_total        │  Réponses par code (2xx,5xx) │
│  haproxy_backend_response_time_average       │  Temps de réponse moyen      │
│  haproxy_frontend_current_sessions           │  Sessions frontend           │
│  haproxy_frontend_limit_sessions             │  Limite max sessions         │
│  haproxy_server_check_failures_total         │  Échecs health check         │
│  haproxy_process_current_connections         │  Connexions totales          │
└──────────────────────────────────────────────┴──────────────────────────────┘
EOF

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 4 : Logs HAProxy
# -----------------------------------------------------------------------------
section "PARTIE 4 : Analyse des logs"

cat << 'EOF'
Format de log HTTP configuré (httplog) :

%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r

Décomposition :
  %ci:%cp     : IP:port client
  %tr         : Timestamp
  %ft         : Frontend
  %b/%s       : Backend/Serveur
  %TR/%Tw/%Tc/%Tr/%Ta : Temps (request/wait/connect/response/total)
  %ST         : Status HTTP
  %B          : Bytes envoyés
  %tsc        : Termination state
  %sq/%bq     : Server queue/Backend queue
  %{+Q}r      : Requête HTTP
EOF

echo ""
info "Logs récents de HAProxy :"
docker logs $CONTAINER 2>&1 | tail -20 || echo "(Logs non disponibles)"

echo ""
info "Filtrer les erreurs (status 4xx/5xx) :"
docker logs $CONTAINER 2>&1 | grep -E " [45][0-9]{2} " | tail -10 || echo "(Aucune erreur récente)"

echo ""
info "Codes de terminaison (tsc) importants :"
cat << 'EOF'
  CD : Client aborted
  SC : Server closed
  sD : Server timeout
  cD : Client timeout
  -- : Normal completion
  PH : Proxy protocol error
  PR : Proxy error
EOF

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 5 : Script de monitoring
# -----------------------------------------------------------------------------
section "PARTIE 5 : Script de monitoring PS/PCA"

cat << 'MONITORING_SCRIPT'
#!/bin/bash
# haproxy-monitor.sh - Script de monitoring pour PS/PCA

SOCKET="/var/run/haproxy.sock"
LOG_FILE="/var/log/haproxy-monitor.log"
ALERT_THRESHOLD_SESSIONS=80  # Pourcentage

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

alert() {
    log "ALERT: $1"
    # Ajouter ici : envoi email, SMS, webhook Slack...
}

# Vérifier que HAProxy répond
check_haproxy_alive() {
    if ! pgrep -x haproxy > /dev/null; then
        alert "HAProxy process NOT RUNNING!"
        return 1
    fi
    return 0
}

# Vérifier les backends
check_backends() {
    local stats=$(echo "show stat" | socat stdio $SOCKET 2>/dev/null)
    
    echo "$stats" | while IFS=',' read -r pxname svname _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ status _; do
        if [[ "$pxname" =~ ^(web_servers|api_servers)$ ]] && [ "$svname" != "BACKEND" ]; then
            if [ "$status" = "DOWN" ]; then
                alert "Server $pxname/$svname is DOWN"
            fi
        fi
    done
}

# Vérifier l'utilisation des sessions
check_sessions() {
    local info=$(echo "show info" | socat stdio $SOCKET 2>/dev/null)
    
    local curr=$(echo "$info" | grep "CurrConns:" | cut -d: -f2 | tr -d ' ')
    local max=$(echo "$info" | grep "Maxconn:" | cut -d: -f2 | tr -d ' ')
    
    if [ -n "$curr" ] && [ -n "$max" ] && [ "$max" -gt 0 ]; then
        local usage=$((curr * 100 / max))
        if [ $usage -gt $ALERT_THRESHOLD_SESSIONS ]; then
            alert "Session usage at ${usage}% (${curr}/${max})"
        fi
        log "Sessions: ${curr}/${max} (${usage}%)"
    fi
}

# Vérifier les erreurs récentes
check_errors() {
    local stats=$(echo "show stat" | socat stdio $SOCKET 2>/dev/null)
    
    # Compter les erreurs 5xx sur les backends
    local errors_5xx=$(echo "$stats" | grep "BACKEND" | awk -F',' '{sum+=$40} END {print sum}')
    
    if [ -n "$errors_5xx" ] && [ "$errors_5xx" -gt 0 ]; then
        log "Total 5xx errors: $errors_5xx"
    fi
}

# Main
main() {
    log "=== HAProxy Health Check ==="
    check_haproxy_alive || exit 1
    check_backends
    check_sessions
    check_errors
    log "=== Check Complete ==="
}

main
MONITORING_SCRIPT

echo ""
info "Pour utiliser ce script en production :"
echo "  1. Sauvegarder dans /usr/local/bin/haproxy-monitor.sh"
echo "  2. Ajouter au crontab : */5 * * * * /usr/local/bin/haproxy-monitor.sh"
echo "  3. Configurer les alertes (email, Slack, PagerDuty...)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 6 : Alertes Prometheus/Grafana
# -----------------------------------------------------------------------------
section "PARTIE 6 : Règles d'alerte Prometheus"

cat << 'EOF'
Règles d'alerte recommandées pour PS/PCA :

groups:
  - name: haproxy_alerts
    rules:
      # Backend DOWN
      - alert: HAProxyBackendDown
        expr: haproxy_backend_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Backend {{ $labels.backend }} is DOWN"
      
      # Serveur DOWN
      - alert: HAProxyServerDown
        expr: haproxy_server_status != 1
        for: 30s
        labels:
          severity: warning
        annotations:
          summary: "Server {{ $labels.server }} in {{ $labels.backend }} is down"
      
      # Taux d'erreurs 5xx élevé
      - alert: HAProxyHigh5xxRate
        expr: |
          rate(haproxy_backend_http_responses_total{code="5xx"}[5m]) 
          / rate(haproxy_backend_http_responses_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High 5xx rate (>5%) on {{ $labels.backend }}"
      
      # Sessions proches de la limite
      - alert: HAProxySessionsNearLimit
        expr: |
          haproxy_frontend_current_sessions 
          / haproxy_frontend_limit_sessions > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Sessions at {{ $value | humanizePercentage }} of limit"
      
      # Queue backend non vide
      - alert: HAProxyBackendQueue
        expr: haproxy_backend_current_queue > 10
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Queue building up on {{ $labels.backend }}"
EOF

echo ""
info "Accès Prometheus : http://localhost:9090"
info "Accès Grafana    : http://localhost:3000 (admin/admin)"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 7 : Dashboard Grafana
# -----------------------------------------------------------------------------
section "PARTIE 7 : Dashboard Grafana"

cat << 'EOF'
Panneaux recommandés pour un dashboard HAProxy :

┌─────────────────────────────────────────────────────────────────────────────┐
│  ROW 1 : VUE D'ENSEMBLE                                                     │
├───────────────────┬───────────────────┬───────────────────┬─────────────────┤
│  Total Requests   │  Active Sessions  │  Backend Health   │  Error Rate    │
│     /second       │      (gauge)      │    (UP/DOWN)      │    (%)         │
├───────────────────┴───────────────────┴───────────────────┴─────────────────┤
│  ROW 2 : TRAFIC                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Graph] Requests per second                                                │
│  [Graph] Response time (percentiles p50, p95, p99)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│  ROW 3 : BACKENDS                                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Table] Servers status, sessions, response time                           │
│  [Graph] Sessions per backend                                               │
├─────────────────────────────────────────────────────────────────────────────┤
│  ROW 4 : ERREURS                                                            │
├─────────────────────────────────────────────────────────────────────────────┤
│  [Graph] HTTP responses by code (2xx, 4xx, 5xx)                            │
│  [Graph] Connection errors, retries                                         │
└─────────────────────────────────────────────────────────────────────────────┘
EOF

echo ""
info "Import du dashboard HAProxy officiel dans Grafana :"
echo "  1. Aller dans Grafana → Dashboards → Import"
echo "  2. Entrer l'ID : 2428 (HAProxy Servers)"
echo "  3. Ou ID : 12693 (HAProxy 2 Full)"
echo "  4. Sélectionner la datasource Prometheus"

read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SYNTHÈSE
# -----------------------------------------------------------------------------
section "SYNTHÈSE DU TP4"

cat << 'EOF'
Compétences acquises :

  ✓ Utilisation de la page de statistiques
  ✓ Extraction de métriques via Runtime API
  ✓ Configuration de l'export Prometheus
  ✓ Analyse des logs HAProxy
  ✓ Création de scripts de monitoring
  ✓ Configuration d'alertes

Outils de monitoring PS/PCA :
  • Stats page     : Vue temps réel, actions admin
  • Runtime API    : Automatisation, scripting
  • Prometheus     : Métriques historiques, alertes
  • Grafana        : Visualisation, dashboards
  • Logs           : Audit, troubleshooting

Métriques critiques à surveiller :
  • haproxy_backend_up : Santé des backends
  • haproxy_backend_http_responses_total{code="5xx"} : Erreurs
  • haproxy_frontend_current_sessions : Charge
  • haproxy_backend_response_time_average : Performance
EOF

echo ""
echo "============================================================================="
echo "                         FIN DU TP4"
echo "============================================================================="
echo ""
echo "Félicitations ! Vous avez terminé la formation HAProxy PS/PCA."
echo ""
echo "Pour aller plus loin :"
echo "  • Documentation officielle : https://docs.haproxy.org/"
echo "  • HAProxy Blog : https://www.haproxy.com/blog/"
echo "  • Community Discourse : https://discourse.haproxy.org/"
echo ""
