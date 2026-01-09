#!/bin/bash
# =============================================================================
# Script de Status Ceph
# =============================================================================

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_DIR="/var/lib/ceph/state"

show_help() {
    cat << EOF

Usage: $0 [command]

Commands:
    (none)      Afficher le status complet
    health      Afficher uniquement la sante
    mon         Status des monitors
    osd         Status des OSDs
    pg          Status des Placement Groups
    df          Espace disque
    pools       Lister les pools

EOF
}

get_health() {
    if [ -f "$STATE_DIR/health" ]; then
        cat "$STATE_DIR/health"
    else
        echo "HEALTH_OK"
    fi
}

get_health_color() {
    local health=$(get_health)
    case $health in
        HEALTH_OK) echo -e "${GREEN}$health${NC}" ;;
        HEALTH_WARN) echo -e "${YELLOW}$health${NC}" ;;
        HEALTH_ERR) echo -e "${RED}$health${NC}" ;;
        *) echo "$health" ;;
    esac
}

show_full_status() {
    local FSID=$(cat /etc/ceph/fsid 2>/dev/null || echo "unknown")
    local HEALTH=$(get_health)

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                       CEPH CLUSTER STATUS                         ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}Cluster ID:${NC} $FSID"
    echo -e "${CYAN}║${NC}  ${BLUE}Health:${NC}     $(get_health_color)"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}Services:${NC}"
    echo -e "${CYAN}║${NC}    mon: 3 daemons, quorum mon1,mon2,mon3 (age 0s)"
    echo -e "${CYAN}║${NC}    mgr: mon1(active), standbys: mon2, mon3"
    echo -e "${CYAN}║${NC}    osd: 3 osds: 3 up, 3 in"
    echo -e "${CYAN}║${NC}    mds: cephfs:1 {0=mds1=up:active}"
    echo -e "${CYAN}║${NC}    rgw: 1 daemon active (rgw1)"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}Data:${NC}"

    # Compter les pools
    local pool_count=0
    if [ -d "$STATE_DIR/pools" ]; then
        pool_count=$(ls "$STATE_DIR/pools" 2>/dev/null | wc -l)
    fi

    echo -e "${CYAN}║${NC}    pools:   $pool_count pools"
    echo -e "${CYAN}║${NC}    objects: 0 objects, 0 B"
    echo -e "${CYAN}║${NC}    usage:   0 GiB used, 3.0 GiB / 3.0 GiB avail"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}  ${BLUE}I/O:${NC}"
    echo -e "${CYAN}║${NC}    client:   0 B/s rd, 0 B/s wr, 0 op/s rd, 0 op/s wr"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_mon_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                       MONITOR STATUS                              ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Quorum: mon1, mon2, mon3"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ┌──────────┬───────────────┬────────┬─────────┐"
    echo -e "${CYAN}║${NC}  │ Monitor  │ Address       │ Rank   │ Status  │"
    echo -e "${CYAN}║${NC}  ├──────────┼───────────────┼────────┼─────────┤"

    for mon in mon1 mon2 mon3; do
        local ip
        case $mon in
            mon1) ip="172.20.0.11" ;;
            mon2) ip="172.20.0.12" ;;
            mon3) ip="172.20.0.13" ;;
        esac

        local status="up"
        if ping -c 1 -W 1 $ip &>/dev/null; then
            status="${GREEN}up${NC}"
        else
            status="${RED}down${NC}"
        fi

        echo -e "${CYAN}║${NC}  │ $mon     │ $ip    │ $(echo $mon | sed 's/mon//')      │ $status     │"
    done

    echo -e "${CYAN}║${NC}  └──────────┴───────────────┴────────┴─────────┘"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_osd_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         OSD TREE                                  ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ID   CLASS  WEIGHT   TYPE NAME         STATUS  REWEIGHT  PRI-AFF"
    echo -e "${CYAN}║${NC}  ──────────────────────────────────────────────────────────────"
    echo -e "${CYAN}║${NC}   -1         3.00000  root default"
    echo -e "${CYAN}║${NC}   -3         1.00000      host osd1"

    for i in 0 1 2; do
        local host="osd$((i+1))"
        local ip="172.20.0.2$((i+1))"
        local status="up"
        local status_color="${GREEN}up${NC}"

        if ! ping -c 1 -W 1 $ip &>/dev/null; then
            status_color="${RED}down${NC}"
        fi

        if [ $i -gt 0 ]; then
            echo -e "${CYAN}║${NC}   -$((i+3))         1.00000      host $host"
        fi
        echo -e "${CYAN}║${NC}    $i   hdd   1.00000          osd.$i     $status_color     1.00000   1.00000"
    done

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_df() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                       CLUSTER DISK USAGE                          ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  --- RAW STORAGE ---"
    echo -e "${CYAN}║${NC}  CLASS   SIZE    AVAIL    USED    RAW USED   %RAW USED"
    echo -e "${CYAN}║${NC}  hdd     3 GiB   3 GiB    0 B     0 B        0"
    echo -e "${CYAN}║${NC}  TOTAL   3 GiB   3 GiB    0 B     0 B        0"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  --- POOLS ---"
    echo -e "${CYAN}║${NC}  POOL                   ID   PGS   STORED   OBJECTS   USED   %USED"

    if [ -d "$STATE_DIR/pools" ]; then
        local id=1
        for pool in $(ls "$STATE_DIR/pools" 2>/dev/null); do
            echo -e "${CYAN}║${NC}  $pool                $id    64    0 B      0         0 B    0"
            ((id++))
        done
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_pools() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                           POOLS                                   ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  NAME                    ID   PGS   SIZE   MIN_SIZE   TYPE"
    echo -e "${CYAN}║${NC}  ───────────────────────────────────────────────────────────"

    if [ -d "$STATE_DIR/pools" ]; then
        for pool in $(ls "$STATE_DIR/pools" 2>/dev/null); do
            local config="$STATE_DIR/pools/$pool/config"
            local pg_num=$(cat "$config" 2>/dev/null | grep pg_num | cut -d= -f2 || echo "64")
            local size=$(cat "$config" 2>/dev/null | grep size | cut -d= -f2 || echo "3")
            local min_size=$(cat "$config" 2>/dev/null | grep min_size | cut -d= -f2 || echo "2")
            local id=$(cat "$config" 2>/dev/null | grep id | cut -d= -f2 || echo "1")
            echo -e "${CYAN}║${NC}  $pool               $id    $pg_num    $size      $min_size          replicated"
        done
    else
        echo -e "${CYAN}║${NC}  (aucun pool)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_pg_status() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    PLACEMENT GROUPS STATUS                        ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    local total_pgs=0
    if [ -d "$STATE_DIR/pools" ]; then
        for pool in $(ls "$STATE_DIR/pools" 2>/dev/null); do
            local pg_num=$(cat "$STATE_DIR/pools/$pool/config" 2>/dev/null | grep pg_num | cut -d= -f2 || echo "64")
            total_pgs=$((total_pgs + pg_num))
        done
    fi

    echo -e "${CYAN}║${NC}  PGs: $total_pgs total"
    echo -e "${CYAN}║${NC}       $total_pgs active+clean"
    echo -e "${CYAN}║${NC}       0 degraded"
    echo -e "${CYAN}║${NC}       0 recovering"
    echo -e "${CYAN}║${NC}       0 backfilling"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main
case "${1:-}" in
    health)
        echo ""
        echo -e "Cluster Health: $(get_health_color)"
        echo ""
        ;;
    mon)
        show_mon_status
        ;;
    osd)
        show_osd_status
        ;;
    pg)
        show_pg_status
        ;;
    df)
        show_df
        ;;
    pools)
        show_pools
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        show_full_status
        ;;
esac
