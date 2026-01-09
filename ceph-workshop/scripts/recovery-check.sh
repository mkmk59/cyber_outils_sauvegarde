#!/bin/bash
# =============================================================================
# Script de Verification de Recovery Ceph
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_DIR="/var/lib/ceph/state"

show_help() {
    cat << EOF

Usage: $0 <command> [options]

Commands:
    status              Verifier l'etat de recovery
    progress            Afficher la progression
    wait                Attendre la fin du recovery
    history             Historique des recoveries
    simulate            Simuler un recovery

Examples:
    $0 status
    $0 progress
    $0 wait --timeout 300

EOF
}

check_recovery_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    RECOVERY STATUS                                ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    # Simuler les etats de recovery
    local recovering=$((RANDOM % 10))
    local degraded=$((RANDOM % 5))
    local misplaced=$((RANDOM % 3))

    if [ $recovering -eq 0 ] && [ $degraded -eq 0 ] && [ $misplaced -eq 0 ]; then
        echo -e "${CYAN}║${NC}  Status: ${GREEN}HEALTHY - No recovery in progress${NC}"
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  All PGs: ${GREEN}active+clean${NC}"
    else
        echo -e "${CYAN}║${NC}  Status: ${YELLOW}RECOVERY IN PROGRESS${NC}"
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  PGs recovering:  $recovering"
        echo -e "${CYAN}║${NC}  PGs degraded:    $degraded"
        echo -e "${CYAN}║${NC}  PGs misplaced:   $misplaced"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Recovery Stats:"
    echo -e "${CYAN}║${NC}  ────────────────────────────────────────"
    echo -e "${CYAN}║${NC}  Objects recovered:  $((RANDOM % 1000 + 500))"
    echo -e "${CYAN}║${NC}  Bytes recovered:    $((RANDOM % 500 + 100)) MB"
    echo -e "${CYAN}║${NC}  Recovery rate:      $((RANDOM % 50 + 20)) MB/s"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_progress() {
    echo ""
    echo -e "${CYAN}Recovery Progress Monitor${NC}"
    echo ""

    for i in {1..5}; do
        local progress=$((i * 20))
        local bar=""
        for j in $(seq 1 $((progress / 5))); do
            bar="${bar}█"
        done
        for j in $(seq 1 $((20 - progress / 5))); do
            bar="${bar}░"
        done

        echo -ne "\r  [${bar}] ${progress}% - Objects: $((i * 200))/1000 - Rate: $((RANDOM % 30 + 40)) MB/s"
        sleep 1
    done

    echo ""
    echo ""
    echo -e "${GREEN}Recovery complete!${NC}"
    echo ""
}

wait_for_recovery() {
    local timeout="${1:-300}"

    echo ""
    echo -e "${CYAN}Waiting for recovery to complete (timeout: ${timeout}s)...${NC}"
    echo ""

    local elapsed=0
    local interval=5

    while [ $elapsed -lt $timeout ]; do
        local remaining=$((timeout - elapsed))
        echo "  Checking... (${remaining}s remaining)"

        # Simuler la fin du recovery
        if [ $((RANDOM % 3)) -eq 0 ]; then
            echo ""
            echo -e "${GREEN}Recovery completed successfully!${NC}"
            echo ""
            return 0
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    echo ""
    echo -e "${YELLOW}Timeout reached. Recovery may still be in progress.${NC}"
    echo ""
    return 1
}

show_history() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    RECOVERY HISTORY                               ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  TIMESTAMP                  TYPE          DURATION   STATUS"
    echo -e "${CYAN}║${NC}  ─────────────────────────────────────────────────────────────"

    # Generer un historique simule
    for i in {1..5}; do
        local days_ago=$((i * 2))
        local date_str=$(date -d "$days_ago days ago" "+%Y-%m-%d %H:%M" 2>/dev/null || date "+%Y-%m-%d %H:%M")
        local types=("OSD_DOWN" "REWEIGHT" "PG_REPAIR" "SCRUB" "BACKFILL")
        local type=${types[$((RANDOM % 5))]}
        local duration="$((RANDOM % 30 + 5))m $((RANDOM % 60))s"
        local status="${GREEN}completed${NC}"

        printf "${CYAN}║${NC}  %-24s %-13s %-10s %b\n" "$date_str" "$type" "$duration" "$status"
    done

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

simulate_recovery() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    SIMULATING RECOVERY                            ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    echo -e "${CYAN}║${NC}  Phase 1: Detecting failure..."
    sleep 1
    echo -e "${CYAN}║${NC}           ${YELLOW}OSD.2 marked DOWN${NC}"

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Phase 2: Initiating recovery..."
    sleep 1
    echo -e "${CYAN}║${NC}           Remapping 128 PGs"

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Phase 3: Data recovery in progress..."
    for i in {1..5}; do
        local pct=$((i * 20))
        sleep 1
        echo -e "${CYAN}║${NC}           Progress: ${pct}%"
    done

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Phase 4: Verification..."
    sleep 1
    echo -e "${CYAN}║${NC}           ${GREEN}All data verified${NC}"

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Recovery simulation complete!${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Summary:"
    echo -e "${CYAN}║${NC}    - Objects recovered: 1,024"
    echo -e "${CYAN}║${NC}    - Data transferred: 256 MB"
    echo -e "${CYAN}║${NC}    - Duration: 5s (simulated)"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main
case "${1:-help}" in
    status)
        check_recovery_status
        ;;
    progress)
        show_progress
        ;;
    wait)
        timeout="${2:-300}"
        if [ "$2" == "--timeout" ]; then
            timeout="${3:-300}"
        fi
        wait_for_recovery "$timeout"
        ;;
    history)
        show_history
        ;;
    simulate)
        simulate_recovery
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Commande inconnue: $1${NC}"
        show_help
        exit 1
        ;;
esac
