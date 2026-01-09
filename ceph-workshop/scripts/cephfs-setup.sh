#!/bin/bash
# =============================================================================
# Script de Configuration CephFS
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
    create <fs_name>        Creer un nouveau filesystem CephFS
    list                    Lister les filesystems
    status [fs_name]        Status du filesystem
    mount <fs_name> <path>  Monter le filesystem
    umount <path>           Demonter le filesystem
    quota set <path> <size> Definir un quota
    snap create <path>      Creer un snapshot

Examples:
    $0 create cephfs
    $0 mount cephfs /mnt/cephfs
    $0 snap create /mnt/cephfs

EOF
}

create_fs() {
    local fs_name="${1:-cephfs}"

    echo ""
    echo -e "${CYAN}Creation du filesystem CephFS: $fs_name${NC}"
    echo ""

    # Creer les pools
    echo "Creation du pool de metadonnees..."
    /scripts/pool-create.sh ${fs_name}-metadata 32 3
    /scripts/pool-create.sh set ${fs_name}-metadata application cephfs

    echo "Creation du pool de donnees..."
    /scripts/pool-create.sh ${fs_name}-data 64 3
    /scripts/pool-create.sh set ${fs_name}-data application cephfs

    # Enregistrer le filesystem
    mkdir -p "$STATE_DIR/cephfs"
    cat > "$STATE_DIR/cephfs/$fs_name" << EOF
name=$fs_name
metadata_pool=${fs_name}-metadata
data_pool=${fs_name}-data
created=$(date -Iseconds)
status=active
EOF

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    CEPHFS CREATED                                 ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Filesystem:     $fs_name"
    echo -e "${GREEN}║${NC}  Metadata Pool:  ${fs_name}-metadata"
    echo -e "${GREEN}║${NC}  Data Pool:      ${fs_name}-data"
    echo -e "${GREEN}║${NC}  MDS:            mds1 (active)"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Pour monter le filesystem:"
    echo "  $0 mount $fs_name /mnt/cephfs"
    echo ""
}

list_fs() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                       CEPHFS LIST                                 ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  NAME              METADATA POOL         DATA POOL"
    echo -e "${CYAN}║${NC}  ───────────────────────────────────────────────────────"

    if [ -d "$STATE_DIR/cephfs" ] && [ "$(ls -A $STATE_DIR/cephfs 2>/dev/null)" ]; then
        for fs in $(ls "$STATE_DIR/cephfs"); do
            local meta=$(grep "metadata_pool=" "$STATE_DIR/cephfs/$fs" | cut -d= -f2)
            local data=$(grep "data_pool=" "$STATE_DIR/cephfs/$fs" | cut -d= -f2)
            printf "${CYAN}║${NC}  %-17s %-21s %s\n" "$fs" "$meta" "$data"
        done
    else
        echo -e "${CYAN}║${NC}  (aucun filesystem)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

fs_status() {
    local fs_name="${1:-cephfs}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    CEPHFS STATUS: $fs_name${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    if [ -f "$STATE_DIR/cephfs/$fs_name" ]; then
        echo -e "${CYAN}║${NC}  Filesystem: $fs_name"
        echo -e "${CYAN}║${NC}  Status: ${GREEN}active${NC}"
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  MDS:"
        echo -e "${CYAN}║${NC}    mds1: ${GREEN}active${NC} (rank 0)"
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  Pools:"
        local meta=$(grep "metadata_pool=" "$STATE_DIR/cephfs/$fs_name" | cut -d= -f2)
        local data=$(grep "data_pool=" "$STATE_DIR/cephfs/$fs_name" | cut -d= -f2)
        echo -e "${CYAN}║${NC}    Metadata: $meta"
        echo -e "${CYAN}║${NC}    Data:     $data"
    else
        echo -e "${CYAN}║${NC}  ${RED}Filesystem '$fs_name' non trouve${NC}"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

mount_fs() {
    local fs_name="$1"
    local mount_point="$2"

    if [ -z "$fs_name" ] || [ -z "$mount_point" ]; then
        echo -e "${RED}Erreur: Usage: $0 mount <fs_name> <path>${NC}"
        exit 1
    fi

    mkdir -p "$mount_point"

    # Simuler le montage
    echo "$fs_name" > "$mount_point/.cephfs_mounted"

    echo ""
    echo -e "${GREEN}CephFS '$fs_name' monte sur $mount_point${NC}"
    echo ""
    echo "Verification:"
    echo "  ls $mount_point"
    echo ""
    echo "Pour demonter:"
    echo "  $0 umount $mount_point"
    echo ""

    # Creer quelques fichiers de demo
    mkdir -p "$mount_point/shared"
    echo "Bienvenue sur CephFS!" > "$mount_point/README.txt"
}

create_snapshot() {
    local path="$1"

    if [ -z "$path" ]; then
        echo -e "${RED}Erreur: Chemin requis${NC}"
        exit 1
    fi

    local snap_name="snap-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$path/.snap/$snap_name"

    echo ""
    echo -e "${GREEN}Snapshot cree: $path/.snap/$snap_name${NC}"
    echo ""
    echo "Pour lister les snapshots:"
    echo "  ls $path/.snap/"
    echo ""
    echo "Pour restaurer un fichier:"
    echo "  cp $path/.snap/$snap_name/file $path/file"
    echo ""
}

# Main
case "${1:-help}" in
    create)
        create_fs "$2"
        ;;
    list|ls)
        list_fs
        ;;
    status)
        fs_status "$2"
        ;;
    mount)
        mount_fs "$2" "$3"
        ;;
    umount)
        rm -f "$2/.cephfs_mounted"
        echo "Filesystem demonte de $2"
        ;;
    snap)
        case "$2" in
            create)
                create_snapshot "$3"
                ;;
            *)
                echo -e "${RED}Commande snap inconnue${NC}"
                ;;
        esac
        ;;
    quota)
        echo "Quota set on $3: $4"
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
