#!/bin/bash
# =============================================================================
# Script de Sante Detaillee Ceph
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_DIR="/var/lib/ceph/state"

show_health_detail() {
    local health=$(cat "$STATE_DIR/health" 2>/dev/null || echo "HEALTH_OK")

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    CEPH HEALTH DETAIL                             ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    case $health in
        HEALTH_OK)
            echo -e "${CYAN}║${NC}  Status: ${GREEN}HEALTH_OK${NC}"
            echo -e "${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}  ${GREEN}All checks passed!${NC}"
            echo -e "${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}  Checks performed:"
            echo -e "${CYAN}║${NC}    [${GREEN}OK${NC}] Monitor quorum: 3/3 monitors in quorum"
            echo -e "${CYAN}║${NC}    [${GREEN}OK${NC}] OSD status: 3/3 OSDs up and in"
            echo -e "${CYAN}║${NC}    [${GREEN}OK${NC}] PG status: All PGs active+clean"
            echo -e "${CYAN}║${NC}    [${GREEN}OK${NC}] Disk usage: Below warning threshold"
            echo -e "${CYAN}║${NC}    [${GREEN}OK${NC}] Scrub status: No issues found"
            ;;
        HEALTH_WARN)
            echo -e "${CYAN}║${NC}  Status: ${YELLOW}HEALTH_WARN${NC}"
            echo -e "${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}  ${YELLOW}Warnings detected:${NC}"

            # Lire les warnings
            if [ -f "$STATE_DIR/warnings" ]; then
                while read warning; do
                    echo -e "${CYAN}║${NC}    ${YELLOW}[WARN]${NC} $warning"
                done < "$STATE_DIR/warnings"
            fi
            ;;
        HEALTH_ERR)
            echo -e "${CYAN}║${NC}  Status: ${RED}HEALTH_ERR${NC}"
            echo -e "${CYAN}║${NC}"
            echo -e "${CYAN}║${NC}  ${RED}Critical issues detected:${NC}"

            if [ -f "$STATE_DIR/errors" ]; then
                while read error; do
                    echo -e "${CYAN}║${NC}    ${RED}[ERR]${NC} $error"
                done < "$STATE_DIR/errors"
            fi
            ;;
    esac

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}Component Status:${NC}"
    echo -e "${CYAN}║${NC}"

    # Monitors
    local mon_ok=0
    for ip in 172.20.0.11 172.20.0.12 172.20.0.13; do
        if ping -c 1 -W 1 $ip &>/dev/null; then
            ((mon_ok++))
        fi
    done
    if [ $mon_ok -eq 3 ]; then
        echo -e "${CYAN}║${NC}    Monitors:  ${GREEN}$mon_ok/3 healthy${NC}"
    else
        echo -e "${CYAN}║${NC}    Monitors:  ${YELLOW}$mon_ok/3 healthy${NC}"
    fi

    # OSDs
    local osd_ok=0
    for ip in 172.20.0.21 172.20.0.22 172.20.0.23; do
        if ping -c 1 -W 1 $ip &>/dev/null; then
            ((osd_ok++))
        fi
    done
    if [ $osd_ok -eq 3 ]; then
        echo -e "${CYAN}║${NC}    OSDs:      ${GREEN}$osd_ok/3 up, $osd_ok/3 in${NC}"
    else
        echo -e "${CYAN}║${NC}    OSDs:      ${YELLOW}$osd_ok/3 up, $osd_ok/3 in${NC}"
    fi

    # MDS
    if ping -c 1 -W 1 172.20.0.31 &>/dev/null; then
        echo -e "${CYAN}║${NC}    MDS:       ${GREEN}1 active${NC}"
    else
        echo -e "${CYAN}║${NC}    MDS:       ${RED}0 active${NC}"
    fi

    # RGW
    if ping -c 1 -W 1 172.20.0.41 &>/dev/null; then
        echo -e "${CYAN}║${NC}    RGW:       ${GREEN}1 active${NC}"
    else
        echo -e "${CYAN}║${NC}    RGW:       ${RED}0 active${NC}"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_help() {
    cat << EOF

Usage: $0 [command]

Commands:
    (none)      Afficher la sante detaillee
    watch       Surveiller la sante en temps reel
    set-warn    Simuler un warning
    set-err     Simuler une erreur
    set-ok      Restaurer l'etat OK

EOF
}

set_health() {
    local status="$1"
    echo "$status" > "$STATE_DIR/health"
    echo "Health set to: $status"
}

case "${1:-}" in
    watch)
        while true; do
            clear
            show_health_detail
            echo "Rafraichissement toutes les 5 secondes. Ctrl+C pour arreter."
            sleep 5
        done
        ;;
    set-warn)
        set_health "HEALTH_WARN"
        echo "1 OSD down" > "$STATE_DIR/warnings"
        ;;
    set-err)
        set_health "HEALTH_ERR"
        echo "Multiple OSDs down - data at risk" > "$STATE_DIR/errors"
        ;;
    set-ok)
        set_health "HEALTH_OK"
        rm -f "$STATE_DIR/warnings" "$STATE_DIR/errors"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_health_detail
        ;;
esac
