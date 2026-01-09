#!/bin/bash
# =============================================================================
# Script de Creation de Pool Ceph
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

STATE_DIR="/var/lib/ceph/state"

show_help() {
    cat << EOF

Usage: $0 <pool_name> [pg_num] [size]

Arguments:
    pool_name   Nom du pool a creer
    pg_num      Nombre de Placement Groups (default: 64)
    size        Nombre de replicas (default: 3)

Examples:
    $0 rbd-pool              # Pool avec defaults
    $0 rbd-pool 128 3        # 128 PGs, 3 replicas
    $0 cephfs-data 64 2      # 64 PGs, 2 replicas

Commands:
    list                     Lister tous les pools
    delete <pool>            Supprimer un pool
    stats <pool>             Stats d'un pool
    set <pool> <key> <val>   Modifier un parametre

EOF
}

create_pool() {
    local pool_name="$1"
    local pg_num="${2:-64}"
    local size="${3:-3}"
    local min_size=$((size - 1))

    if [ -z "$pool_name" ]; then
        echo -e "${RED}Erreur: Nom du pool requis${NC}"
        show_help
        exit 1
    fi

    mkdir -p "$STATE_DIR/pools/$pool_name"

    # Generer un ID unique
    local pool_id=$(ls "$STATE_DIR/pools" 2>/dev/null | wc -l)
    ((pool_id++))

    # Sauvegarder la configuration
    cat > "$STATE_DIR/pools/$pool_name/config" << EOF
id=$pool_id
pg_num=$pg_num
pgp_num=$pg_num
size=$size
min_size=$min_size
type=replicated
application=
EOF

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    POOL CREATED SUCCESSFULLY                      ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Pool Name:    $pool_name"
    echo -e "${GREEN}║${NC}  Pool ID:      $pool_id"
    echo -e "${GREEN}║${NC}  PG Count:     $pg_num"
    echo -e "${GREEN}║${NC}  Size:         $size (replicas)"
    echo -e "${GREEN}║${NC}  Min Size:     $min_size"
    echo -e "${GREEN}║${NC}  Type:         replicated"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}Pour activer une application sur ce pool:${NC}"
    echo "  $0 set $pool_name application rbd"
    echo "  $0 set $pool_name application cephfs"
    echo "  $0 set $pool_name application rgw"
}

list_pools() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         POOL LIST                                 ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  NAME                 ID    PGS    SIZE   APP"
    echo -e "${CYAN}║${NC}  ─────────────────────────────────────────────────────"

    if [ -d "$STATE_DIR/pools" ] && [ "$(ls -A $STATE_DIR/pools 2>/dev/null)" ]; then
        for pool in $(ls "$STATE_DIR/pools"); do
            local config="$STATE_DIR/pools/$pool/config"
            local id=$(grep "id=" "$config" | cut -d= -f2)
            local pgs=$(grep "pg_num=" "$config" | cut -d= -f2)
            local size=$(grep "^size=" "$config" | cut -d= -f2)
            local app=$(grep "application=" "$config" | cut -d= -f2)
            [ -z "$app" ] && app="-"
            printf "${CYAN}║${NC}  %-20s %-5s %-6s %-6s %s\n" "$pool" "$id" "$pgs" "$size" "$app"
        done
    else
        echo -e "${CYAN}║${NC}  (aucun pool cree)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

delete_pool() {
    local pool_name="$1"

    if [ -z "$pool_name" ]; then
        echo -e "${RED}Erreur: Nom du pool requis${NC}"
        exit 1
    fi

    if [ ! -d "$STATE_DIR/pools/$pool_name" ]; then
        echo -e "${RED}Erreur: Pool '$pool_name' n'existe pas${NC}"
        exit 1
    fi

    echo -e "${YELLOW}ATTENTION: Vous allez supprimer le pool '$pool_name'${NC}"
    echo -e "${YELLOW}Toutes les donnees seront perdues!${NC}"
    read -p "Tapez le nom du pool pour confirmer: " confirm

    if [ "$confirm" != "$pool_name" ]; then
        echo "Annule."
        exit 0
    fi

    rm -rf "$STATE_DIR/pools/$pool_name"
    echo -e "${GREEN}Pool '$pool_name' supprime.${NC}"
}

pool_stats() {
    local pool_name="$1"

    if [ -z "$pool_name" ]; then
        echo -e "${RED}Erreur: Nom du pool requis${NC}"
        exit 1
    fi

    if [ ! -d "$STATE_DIR/pools/$pool_name" ]; then
        echo -e "${RED}Erreur: Pool '$pool_name' n'existe pas${NC}"
        exit 1
    fi

    local config="$STATE_DIR/pools/$pool_name/config"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    POOL STATISTICS: $pool_name${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Configuration:"
    while IFS='=' read -r key value; do
        printf "${CYAN}║${NC}    %-15s %s\n" "$key:" "$value"
    done < "$config"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Statistics:"
    echo -e "${CYAN}║${NC}    Objects:        0"
    echo -e "${CYAN}║${NC}    Size:           0 B"
    echo -e "${CYAN}║${NC}    Reads:          0 B/s"
    echo -e "${CYAN}║${NC}    Writes:         0 B/s"
    echo -e "${CYAN}║${NC}    Read Ops:       0 op/s"
    echo -e "${CYAN}║${NC}    Write Ops:      0 op/s"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

set_pool_param() {
    local pool_name="$1"
    local key="$2"
    local value="$3"

    if [ -z "$pool_name" ] || [ -z "$key" ] || [ -z "$value" ]; then
        echo -e "${RED}Erreur: Usage: $0 set <pool> <key> <value>${NC}"
        exit 1
    fi

    if [ ! -d "$STATE_DIR/pools/$pool_name" ]; then
        echo -e "${RED}Erreur: Pool '$pool_name' n'existe pas${NC}"
        exit 1
    fi

    local config="$STATE_DIR/pools/$pool_name/config"

    # Mettre a jour ou ajouter le parametre
    if grep -q "^${key}=" "$config"; then
        sed -i "s/^${key}=.*/${key}=${value}/" "$config"
    else
        echo "${key}=${value}" >> "$config"
    fi

    echo -e "${GREEN}Pool '$pool_name': $key = $value${NC}"
}

# Main
case "${1:-help}" in
    list)
        list_pools
        ;;
    delete)
        delete_pool "$2"
        ;;
    stats)
        pool_stats "$2"
        ;;
    set)
        set_pool_param "$2" "$3" "$4"
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        create_pool "$1" "$2" "$3"
        ;;
esac
