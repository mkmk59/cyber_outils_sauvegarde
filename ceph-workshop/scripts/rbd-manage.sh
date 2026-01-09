#!/bin/bash
# =============================================================================
# Script de Gestion RBD (RADOS Block Device)
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
    create <pool/image> --size <size>   Creer une image RBD
    list <pool>                         Lister les images d'un pool
    info <pool/image>                   Informations sur une image
    resize <pool/image> --size <size>   Redimensionner une image
    delete <pool/image>                 Supprimer une image
    map <pool/image>                    Mapper l'image sur un device
    unmap <device>                      Demapper un device
    showmapped                          Afficher les images mappees
    snap create <pool/image@snap>       Creer un snapshot
    snap list <pool/image>              Lister les snapshots
    snap rollback <pool/image@snap>     Rollback vers un snapshot
    snap delete <pool/image@snap>       Supprimer un snapshot

Examples:
    $0 create rbd-pool/disk1 --size 10G
    $0 map rbd-pool/disk1
    $0 snap create rbd-pool/disk1@backup

EOF
}

parse_image_spec() {
    local spec="$1"
    POOL=$(echo "$spec" | cut -d/ -f1)
    IMAGE=$(echo "$spec" | cut -d/ -f2 | cut -d@ -f1)
    SNAP=$(echo "$spec" | grep @ | cut -d@ -f2)
}

create_image() {
    local spec="$1"
    shift

    local size=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --size)
                size="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -z "$spec" ] || [ -z "$size" ]; then
        echo -e "${RED}Erreur: Usage: $0 create <pool/image> --size <size>${NC}"
        exit 1
    fi

    parse_image_spec "$spec"

    # Verifier que le pool existe
    if [ ! -d "$STATE_DIR/pools/$POOL" ]; then
        echo -e "${RED}Erreur: Pool '$POOL' n'existe pas${NC}"
        echo "Creez-le avec: /scripts/pool-create.sh $POOL"
        exit 1
    fi

    # Creer le repertoire pour les images
    mkdir -p "$STATE_DIR/pools/$POOL/images"

    # Creer l'image
    local image_dir="$STATE_DIR/pools/$POOL/images/$IMAGE"
    mkdir -p "$image_dir"

    # Parser la taille
    local size_bytes
    case $size in
        *G) size_bytes=$((${size%G} * 1024 * 1024 * 1024)) ;;
        *M) size_bytes=$((${size%M} * 1024 * 1024)) ;;
        *K) size_bytes=$((${size%K} * 1024)) ;;
        *)  size_bytes=$size ;;
    esac

    cat > "$image_dir/config" << EOF
size=$size_bytes
size_human=$size
created=$(date -Iseconds)
features=layering,exclusive-lock,object-map,fast-diff,deep-flatten
format=2
order=22
object_size=4194304
EOF

    mkdir -p "$image_dir/snapshots"

    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    RBD IMAGE CREATED                              ║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  Pool:    $POOL"
    echo -e "${GREEN}║${NC}  Image:   $IMAGE"
    echo -e "${GREEN}║${NC}  Size:    $size"
    echo -e "${GREEN}║${NC}  Format:  2"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

list_images() {
    local pool="$1"

    if [ -z "$pool" ]; then
        echo -e "${RED}Erreur: Pool requis${NC}"
        exit 1
    fi

    local images_dir="$STATE_DIR/pools/$pool/images"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    RBD IMAGES IN POOL: $pool${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"

    if [ -d "$images_dir" ] && [ "$(ls -A $images_dir 2>/dev/null)" ]; then
        for image in $(ls "$images_dir"); do
            echo -e "${CYAN}║${NC}  $image"
        done
    else
        echo -e "${CYAN}║${NC}  (aucune image)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

image_info() {
    local spec="$1"
    parse_image_spec "$spec"

    local config="$STATE_DIR/pools/$POOL/images/$IMAGE/config"

    if [ ! -f "$config" ]; then
        echo -e "${RED}Erreur: Image '$spec' n'existe pas${NC}"
        exit 1
    fi

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    RBD IMAGE INFO                                 ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  rbd image '$IMAGE':"
    while IFS='=' read -r key value; do
        printf "${CYAN}║${NC}    %-20s %s\n" "$key:" "$value"
    done < "$config"

    # Snapshots
    local snap_dir="$STATE_DIR/pools/$POOL/images/$IMAGE/snapshots"
    local snap_count=$(ls "$snap_dir" 2>/dev/null | wc -l)
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Snapshots: $snap_count"

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

map_image() {
    local spec="$1"
    parse_image_spec "$spec"

    local config="$STATE_DIR/pools/$POOL/images/$IMAGE/config"

    if [ ! -f "$config" ]; then
        echo -e "${RED}Erreur: Image '$spec' n'existe pas${NC}"
        exit 1
    fi

    # Simuler le mapping
    mkdir -p "$STATE_DIR/mapped"
    local device_id=$(ls "$STATE_DIR/mapped" 2>/dev/null | wc -l)
    local device="/dev/rbd$device_id"

    cat > "$STATE_DIR/mapped/rbd$device_id" << EOF
pool=$POOL
image=$IMAGE
device=$device
EOF

    # Creer un fichier sparse pour simuler le device
    local size_bytes=$(grep "^size=" "$config" | cut -d= -f2)
    local sim_file="/data/rbd$device_id.img"
    dd if=/dev/zero of="$sim_file" bs=1M count=0 seek=$((size_bytes / 1024 / 1024)) 2>/dev/null

    echo ""
    echo -e "${GREEN}Image mappee: $POOL/$IMAGE -> $device${NC}"
    echo ""
    echo -e "${YELLOW}Fichier simule: $sim_file${NC}"
    echo ""
    echo "Pour formater et monter:"
    echo "  mkfs.ext4 $sim_file"
    echo "  mkdir -p /mnt/rbd"
    echo "  mount -o loop $sim_file /mnt/rbd"
}

show_mapped() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    MAPPED RBD IMAGES                              ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  ID   POOL         IMAGE          DEVICE"
    echo -e "${CYAN}║${NC}  ─────────────────────────────────────────────────"

    if [ -d "$STATE_DIR/mapped" ] && [ "$(ls -A $STATE_DIR/mapped 2>/dev/null)" ]; then
        local id=0
        for map in $(ls "$STATE_DIR/mapped"); do
            local pool=$(grep "pool=" "$STATE_DIR/mapped/$map" | cut -d= -f2)
            local image=$(grep "image=" "$STATE_DIR/mapped/$map" | cut -d= -f2)
            local device=$(grep "device=" "$STATE_DIR/mapped/$map" | cut -d= -f2)
            printf "${CYAN}║${NC}  %-4s %-12s %-14s %s\n" "$id" "$pool" "$image" "$device"
            ((id++))
        done
    else
        echo -e "${CYAN}║${NC}  (aucune image mappee)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

create_snapshot() {
    local spec="$1"
    parse_image_spec "$spec"

    if [ -z "$SNAP" ]; then
        echo -e "${RED}Erreur: Format attendu: pool/image@snapshot${NC}"
        exit 1
    fi

    local snap_dir="$STATE_DIR/pools/$POOL/images/$IMAGE/snapshots"
    mkdir -p "$snap_dir"

    cat > "$snap_dir/$SNAP" << EOF
created=$(date -Iseconds)
size=$(grep "^size=" "$STATE_DIR/pools/$POOL/images/$IMAGE/config" | cut -d= -f2)
protected=false
EOF

    echo -e "${GREEN}Snapshot cree: $POOL/$IMAGE@$SNAP${NC}"
}

resize_image() {
    local spec="$1"
    shift
    local new_size=""

    while [[ $# -gt 0 ]]; do
        case $1 in
            --size)
                new_size="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    if [ -z "$spec" ] || [ -z "$new_size" ]; then
        echo -e "${RED}Erreur: Usage: $0 resize <pool/image> --size <size>${NC}"
        exit 1
    fi

    parse_image_spec "$spec"

    local config="$STATE_DIR/pools/$POOL/images/$IMAGE/config"
    if [ ! -f "$config" ]; then
        echo -e "${RED}Erreur: Image '$POOL/$IMAGE' n'existe pas${NC}"
        exit 1
    fi

    # Parser la nouvelle taille
    local size_bytes
    case $new_size in
        *G) size_bytes=$((${new_size%G} * 1024 * 1024 * 1024)) ;;
        *M) size_bytes=$((${new_size%M} * 1024 * 1024)) ;;
        *K) size_bytes=$((${new_size%K} * 1024)) ;;
        *)  size_bytes=$new_size ;;
    esac

    # Mettre a jour la config
    sed -i "s/^size=.*/size=$size_bytes/" "$config"
    sed -i "s/^size_human=.*/size_human=$new_size/" "$config"

    echo -e "${GREEN}Image redimensionnee: $POOL/$IMAGE -> $new_size${NC}"
}

unmap_image() {
    local device="$1"

    if [ -z "$device" ]; then
        echo -e "${RED}Erreur: Device requis${NC}"
        exit 1
    fi

    # Trouver le mapping correspondant
    local device_basename=$(basename "$device")
    local map_file="$STATE_DIR/mapped/$device_basename"

    if [ -f "$map_file" ]; then
        rm -f "$map_file"
        echo -e "${GREEN}Image demappee: $device${NC}"
    else
        echo -e "${YELLOW}Device $device n'est pas mappe${NC}"
    fi
}

delete_image() {
    local spec="$1"
    parse_image_spec "$spec"

    local image_dir="$STATE_DIR/pools/$POOL/images/$IMAGE"

    if [ ! -d "$image_dir" ]; then
        echo -e "${RED}Erreur: Image '$POOL/$IMAGE' n'existe pas${NC}"
        exit 1
    fi

    rm -rf "$image_dir"
    echo -e "${GREEN}Image supprimee: $POOL/$IMAGE${NC}"
}

list_snapshots() {
    local spec="$1"
    parse_image_spec "$spec"

    local snap_dir="$STATE_DIR/pools/$POOL/images/$IMAGE/snapshots"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    SNAPSHOTS: $POOL/$IMAGE${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  SNAPID   NAME              SIZE      PROTECTED   TIMESTAMP"
    echo -e "${CYAN}║${NC}  ────────────────────────────────────────────────────────────"

    if [ -d "$snap_dir" ] && [ "$(ls -A $snap_dir 2>/dev/null)" ]; then
        local id=1
        for snap in $(ls "$snap_dir"); do
            local created=$(grep "created=" "$snap_dir/$snap" | cut -d= -f2)
            local size=$(grep "^size=" "$snap_dir/$snap" | cut -d= -f2)
            local protected=$(grep "protected=" "$snap_dir/$snap" | cut -d= -f2)
            local size_h=$((size / 1024 / 1024))M
            printf "${CYAN}║${NC}  %-9s %-17s %-9s %-11s %s\n" "$id" "$snap" "$size_h" "$protected" "$created"
            ((id++))
        done
    else
        echo -e "${CYAN}║${NC}  (aucun snapshot)"
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main
case "${1:-help}" in
    create)
        shift
        create_image "$@"
        ;;
    list|ls)
        list_images "$2"
        ;;
    info)
        image_info "$2"
        ;;
    resize)
        shift
        resize_image "$@"
        ;;
    delete|rm)
        delete_image "$2"
        ;;
    map)
        map_image "$2"
        ;;
    unmap)
        unmap_image "$2"
        ;;
    showmapped)
        show_mapped
        ;;
    snap)
        case "$2" in
            create)
                create_snapshot "$3"
                ;;
            list|ls)
                list_snapshots "$3"
                ;;
            rollback)
                echo -e "${GREEN}Rollback vers $3 effectue${NC}"
                ;;
            delete|rm)
                parse_image_spec "$3"
                snap_file="$STATE_DIR/pools/$POOL/images/$IMAGE/snapshots/$SNAP"
                if [ -f "$snap_file" ]; then
                    rm -f "$snap_file"
                    echo -e "${GREEN}Snapshot supprime: $3${NC}"
                else
                    echo -e "${RED}Snapshot non trouve: $3${NC}"
                fi
                ;;
            *)
                echo -e "${RED}Commande snap inconnue: $2${NC}"
                ;;
        esac
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
