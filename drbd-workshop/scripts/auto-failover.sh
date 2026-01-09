#!/bin/bash
# =============================================================================
# Script d'automatisation du Failover DRBD
# =============================================================================
# Surveille le Primary et bascule automatiquement en cas de panne
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PRIMARY_IP="${PRIMARY_IP:-172.28.0.11}"
SECONDARY_NODE="${SECONDARY_NODE:-drbd-node2}"
GRACE_PERIOD="${GRACE_PERIOD:-30}"
CHECK_INTERVAL="${CHECK_INTERVAL:-10}"
MAX_RETRIES="${MAX_RETRIES:-3}"
LOG_FILE="/var/log/drbd-auto-failover.log"

# Variables globales
FAILURE_COUNT=0
LAST_FAILURE_TIME=0

# Fonctions
log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[${timestamp}] [${level}] ${message}" >> "$LOG_FILE"
    echo -e "${BLUE}[${timestamp}]${NC} ${message}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $@" >&2
    log "ERROR" "$@"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $@"
    log "WARN" "$@"
}

log_info() {
    echo -e "${GREEN}[INFO]${NC} $@"
    log "INFO" "$@"
}

show_help() {
    cat << EOF

Usage: $0 [options]

Options:
    --primary-ip IP         IP du noeud Primary a surveiller
    --secondary-node NODE   Nom du noeud Secondary pour le basculement
    --grace-period SECS     Grace period avant basculement (default: 30s)
    --check-interval SECS   Intervalle de verifications (default: 10s)
    --dry-run              Afficher les actions sans les executer
    --debug                Afficher les logs detailles
    --stop                 Arreter la surveillance
    -h, --help             Afficher cette aide

Examples:
    $0 --primary-ip 172.28.0.11 --secondary-node drbd-node2
    $0 --grace-period 15 --dry-run
    $0 --debug

Description:
    Surveille la disponibilite du noeud Primary.
    En cas de panne prolongee (grace period), bascule automatiquement
    le Secondary en Primary.

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --primary-ip)
                PRIMARY_IP="$2"
                shift 2
                ;;
            --secondary-node)
                SECONDARY_NODE="$2"
                shift 2
                ;;
            --grace-period)
                GRACE_PERIOD="$2"
                shift 2
                ;;
            --check-interval)
                CHECK_INTERVAL="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --debug)
                DEBUG=1
                shift
                ;;
            --stop)
                STOP_FLAG=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Argument inconnu: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

check_primary_status() {
    # Verifier si le Primary est reachable
    if ping -c 1 -W 2 "$PRIMARY_IP" &>/dev/null; then
        return 0  # Primary est accessible
    else
        return 1  # Primary est injoignable
    fi
}

check_drbd_connection() {
    # Verifier l'etat DRBD
    if [ -f "/var/lib/drbd/connected" ]; then
        local connected=$(cat /var/lib/drbd/connected)
        [ "$connected" == "true" ]
        return $?
    fi
    return 1
}

perform_failover() {
    log_warning "Lancement du failover vers $SECONDARY_NODE..."
    
    if [ "$DRY_RUN" == "1" ]; then
        log_info "[DRY-RUN] Commandes qui seraient executees:"
        echo "  docker exec $SECONDARY_NODE /scripts/drbd-role.sh primary --force"
        echo "  docker exec $SECONDARY_NODE /scripts/drbd-mount.sh"
        return 0
    fi
    
    # Promouvoir le Secondary en Primary
    log_info "Promotion du Secondary en Primary..."
    docker exec "$SECONDARY_NODE" /scripts/drbd-role.sh primary --force 2>&1 | \
        while read line; do log_info "$line"; done
    
    # Monter le filesystem
    log_info "Montage du filesystem..."
    docker exec "$SECONDARY_NODE" /scripts/drbd-mount.sh 2>&1 | \
        while read line; do log_info "$line"; done
    
    # Envoyer une notification
    log_warning "FAILOVER COMPLET: Nouveau Primary = $SECONDARY_NODE"
    
    if command -v logger &> /dev/null; then
        logger -t drbd-auto-failover -p daemon.crit \
            "FAILOVER EXECUTE: Primary=$PRIMARY_IP devient INDISPONIBLE, Promotion de $SECONDARY_NODE"
    fi
    
    return 0
}

reset_failure_count() {
    if [ $FAILURE_COUNT -gt 0 ]; then
        log_info "Primary de nouveau reachable. Compteur reinitialise."
    fi
    FAILURE_COUNT=0
    LAST_FAILURE_TIME=0
}

handle_failure() {
    local current_time=$(date +%s)
    
    FAILURE_COUNT=$((FAILURE_COUNT + 1))
    log_warning "Panne du Primary detectee (tentative #$FAILURE_COUNT)"
    
    if [ $FAILURE_COUNT -eq 1 ]; then
        LAST_FAILURE_TIME=$current_time
    fi
    
    # Verifier le grace period
    local elapsed=$((current_time - LAST_FAILURE_TIME))
    if [ $elapsed -ge $GRACE_PERIOD ]; then
        log_error "Grace period ($GRACE_PERIOD s) depasse! Failover auto..."
        perform_failover
        return 1  # Sortir de la boucle apres failover
    else
        log_warning "Grace period: ${elapsed}s/${GRACE_PERIOD}s"
        return 0
    fi
}

monitor() {
    log_info "=== AUTO-FAILOVER DRBD DEMARRAGE ==="
    log_info "Configuration:"
    log_info "  Primary IP: $PRIMARY_IP"
    log_info "  Secondary Node: $SECONDARY_NODE"
    log_info "  Grace Period: ${GRACE_PERIOD}s"
    log_info "  Check Interval: ${CHECK_INTERVAL}s"
    log_info "  Dry-Run: ${DRY_RUN:-0}"
    echo ""
    
    local iteration=0
    
    while true; do
        iteration=$((iteration + 1))
        
        if [ "$DEBUG" == "1" ]; then
            log_info "Iteration #$iteration - Verification du Primary..."
        fi
        
        if check_primary_status; then
            reset_failure_count
            if [ "$DEBUG" == "1" ]; then
                log_info "Primary reachable"
            fi
        else
            if ! handle_failure; then
                # Failover effectue, sortir
                break
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
    
    log_info "=== AUTO-FAILOVER ARRETE ==="
}

# Main
parse_args "$@"

# Creer le dossier log si necessaire
mkdir -p "$(dirname "$LOG_FILE")"

# Lancer la surveillance
monitor
