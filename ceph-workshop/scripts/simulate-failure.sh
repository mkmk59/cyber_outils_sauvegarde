#!/bin/bash
# =============================================================================
# Script de Simulation de Pannes Ceph
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_DIR="/var/lib/ceph/state"

show_help() {
    cat << EOF

Usage: $0 <failure_type> [options]

Failure Types:
    osd.<id>            Simuler la panne d'un OSD (0, 1, ou 2)
    mon.<name>          Simuler la panne d'un monitor
    network <duration>  Simuler une panne reseau
    disk-full           Simuler un disque plein
    slow-osd <id>       Simuler un OSD lent
    random              Panne aleatoire
    restore             Restaurer l'etat normal

Examples:
    $0 osd.1             # OSD 1 down
    $0 mon.mon2          # Monitor 2 down
    $0 network 30s       # Panne reseau 30 secondes
    $0 restore           # Retour a la normale

Scenarios PCA:
    $0 scenario-1        # Perte d'un rack (1 MON + 1 OSD)
    $0 scenario-2        # Perte de 2 OSDs
    $0 scenario-quorum   # Perte du quorum (2 MONs)

EOF
}

simulate_osd_failure() {
    local osd_id="${1#osd.}"

    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              SIMULATION: OSD.$osd_id DOWN                              ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Marquer l'OSD comme down
    echo "down" > "$STATE_DIR/osd_${osd_id}_status"
    echo "out" > "$STATE_DIR/osd_${osd_id}_in"

    # Mettre a jour la sante du cluster
    echo "HEALTH_WARN" > "$STATE_DIR/health"
    echo "1 OSD down (osd.$osd_id)" > "$STATE_DIR/warnings"

    echo -e "${YELLOW}Etat du cluster:${NC}"
    echo "  - OSD.$osd_id: ${RED}DOWN${NC}"
    echo "  - Cluster: ${YELLOW}HEALTH_WARN${NC}"
    echo ""
    echo -e "${CYAN}Impact:${NC}"
    echo "  - Certains PGs sont degrades"
    echo "  - Les donnees restent accessibles (min_size=2)"
    echo "  - Recovery automatique si l'OSD revient"
    echo ""
    echo -e "${YELLOW}Actions recommandees:${NC}"
    echo "  1. Verifier les logs: journalctl -u ceph-osd@$osd_id"
    echo "  2. Verifier le disque: smartctl -a /dev/sdX"
    echo "  3. Si HS: remplacer le disque"
    echo ""
    echo "Pour restaurer: $0 restore"
    echo ""
}

simulate_mon_failure() {
    local mon_name="${1#mon.}"

    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              SIMULATION: MONITOR $mon_name DOWN                        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "down" > "$STATE_DIR/mon_${mon_name}_status"

    local mon_count=$(grep -c "up" "$STATE_DIR"/mon_*_status 2>/dev/null || echo "2")

    if [ "$mon_count" -lt 2 ]; then
        echo "HEALTH_ERR" > "$STATE_DIR/health"
        echo "Monitor quorum lost!" > "$STATE_DIR/errors"
        echo -e "${RED}ATTENTION: Quorum perdu! Cluster en mode read-only.${NC}"
    else
        echo "HEALTH_WARN" > "$STATE_DIR/health"
        echo "1 monitor down ($mon_name)" > "$STATE_DIR/warnings"
    fi

    echo -e "${YELLOW}Etat du cluster:${NC}"
    echo "  - Monitor $mon_name: ${RED}DOWN${NC}"
    echo "  - Quorum: $(($mon_count))/3 monitors"
    echo ""
}

simulate_network_failure() {
    local duration="${1:-30s}"
    local seconds=$(echo "$duration" | sed 's/s$//')

    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║              SIMULATION: PANNE RESEAU                             ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "HEALTH_WARN" > "$STATE_DIR/health"
    echo "Network connectivity issues" > "$STATE_DIR/warnings"

    echo "Panne reseau simulee pour $duration..."
    echo ""

    # Simuler la degradation
    for i in 0 1 2; do
        echo "degraded" > "$STATE_DIR/osd_${i}_status"
    done

    sleep "$seconds"

    echo ""
    echo -e "${GREEN}Connectivite reseau restauree.${NC}"
    restore_normal
}

simulate_scenario_1() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        SCENARIO PCA 1: PERTE D'UN RACK                            ║${NC}"
    echo -e "${RED}║        (1 Monitor + 1 OSD)                                        ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "down" > "$STATE_DIR/mon_mon3_status"
    echo "down" > "$STATE_DIR/osd_2_status"
    echo "out" > "$STATE_DIR/osd_2_in"

    echo "HEALTH_WARN" > "$STATE_DIR/health"
    cat > "$STATE_DIR/warnings" << EOF
1 monitor down (mon3)
1 OSD down (osd.2)
EOF

    echo -e "${YELLOW}Simulation:${NC}"
    echo "  - Monitor mon3: ${RED}DOWN${NC}"
    echo "  - OSD.2: ${RED}DOWN${NC}"
    echo ""
    echo -e "${GREEN}Impact:${NC}"
    echo "  - Quorum maintenu (2/3 monitors)"
    echo "  - Donnees accessibles (2 replicas disponibles)"
    echo "  - Recovery automatique possible"
    echo ""
    echo -e "${CYAN}RTO estime: ~5 minutes (recovery automatique)${NC}"
    echo -e "${CYAN}RPO: 0 (aucune perte de donnees)${NC}"
    echo ""
}

simulate_scenario_2() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        SCENARIO PCA 2: PERTE DE 2 OSDs                            ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "down" > "$STATE_DIR/osd_1_status"
    echo "down" > "$STATE_DIR/osd_2_status"
    echo "out" > "$STATE_DIR/osd_1_in"
    echo "out" > "$STATE_DIR/osd_2_in"

    echo "HEALTH_WARN" > "$STATE_DIR/health"
    cat > "$STATE_DIR/warnings" << EOF
2 OSDs down (osd.1, osd.2)
some PGs are degraded
EOF

    echo -e "${YELLOW}Simulation:${NC}"
    echo "  - OSD.1: ${RED}DOWN${NC}"
    echo "  - OSD.2: ${RED}DOWN${NC}"
    echo ""
    echo -e "${YELLOW}Impact:${NC}"
    echo "  - Certains PGs n'ont qu'1 replica"
    echo "  - Donnees accessibles si min_size=1"
    echo "  - ${RED}ATTENTION: Risque de perte de donnees si OSD.0 tombe${NC}"
    echo ""
}

simulate_quorum_loss() {
    echo ""
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║        SCENARIO CRITIQUE: PERTE DU QUORUM                         ║${NC}"
    echo -e "${RED}║        (2 Monitors DOWN)                                          ║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "down" > "$STATE_DIR/mon_mon2_status"
    echo "down" > "$STATE_DIR/mon_mon3_status"

    echo "HEALTH_ERR" > "$STATE_DIR/health"
    echo "MONITOR QUORUM LOST - CLUSTER DEGRADED" > "$STATE_DIR/errors"

    echo -e "${RED}!!! ALERTE CRITIQUE !!!${NC}"
    echo ""
    echo -e "${YELLOW}Simulation:${NC}"
    echo "  - Monitor mon2: ${RED}DOWN${NC}"
    echo "  - Monitor mon3: ${RED}DOWN${NC}"
    echo "  - Quorum: ${RED}1/3 - PERDU${NC}"
    echo ""
    echo -e "${RED}Impact:${NC}"
    echo "  - Cluster en mode READ-ONLY"
    echo "  - Impossible de modifier la configuration"
    echo "  - Les ecritures sont bloquees"
    echo ""
    echo -e "${YELLOW}Actions requises:${NC}"
    echo "  1. Restaurer au moins 1 monitor supplementaire"
    echo "  2. Ou reconstruire le quorum manuellement"
    echo ""
}

restore_normal() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              RESTAURATION DE L'ETAT NORMAL                        ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Restaurer les OSDs
    for i in 0 1 2; do
        echo "up" > "$STATE_DIR/osd_${i}_status"
        echo "in" > "$STATE_DIR/osd_${i}_in"
    done

    # Restaurer les monitors
    for mon in mon1 mon2 mon3; do
        echo "up" > "$STATE_DIR/mon_${mon}_status"
    done

    # Restaurer la sante
    echo "HEALTH_OK" > "$STATE_DIR/health"
    rm -f "$STATE_DIR/warnings" "$STATE_DIR/errors"

    echo -e "${GREEN}Cluster restaure a l'etat normal.${NC}"
    echo ""
    echo "Verification:"
    /scripts/ceph-status.sh health
}

# Main
case "${1:-help}" in
    osd.*)
        simulate_osd_failure "$1"
        ;;
    mon.*)
        simulate_mon_failure "$1"
        ;;
    network)
        simulate_network_failure "$2"
        ;;
    scenario-1)
        simulate_scenario_1
        ;;
    scenario-2)
        simulate_scenario_2
        ;;
    scenario-quorum)
        simulate_quorum_loss
        ;;
    random)
        case $((RANDOM % 3)) in
            0) simulate_osd_failure "osd.$((RANDOM % 3))" ;;
            1) simulate_mon_failure "mon.mon$((RANDOM % 3 + 1))" ;;
            2) simulate_scenario_1 ;;
        esac
        ;;
    restore)
        restore_normal
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Type de panne inconnu: $1${NC}"
        show_help
        exit 1
        ;;
esac
