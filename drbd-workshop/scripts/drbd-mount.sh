#!/bin/bash
# =============================================================================
# Script de montage DRBD
# =============================================================================
# Gere le montage et demontage du filesystem DRBD
# =============================================================================

set +e

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

DRBD_DEVICE="/dev/drbd0"
MOUNT_POINT="/mnt/drbd"
DRBD_ROLE_FILE="/var/lib/drbd/role"

show_help() {
    cat << EOF

Usage: $0 <command>

Commands:
    format      - Formater le device DRBD en ext4
    mount       - Monter le filesystem DRBD
    umount      - Demonter le filesystem DRBD
    status      - Afficher le status de montage
    check       - Verifier le filesystem

Examples:
    $0 format    # Formater (premiere fois seulement)
    $0 mount     # Monter sur /mnt/drbd
    $0 umount    # Demonter

EOF
}

check_device() {
    if [ ! -e "$DRBD_DEVICE" ]; then
        echo -e "${RED}[ERROR] Device $DRBD_DEVICE non disponible${NC}"
        echo "Executez d'abord: /scripts/drbd-init.sh start"
        exit 1
    fi

    # Resoudre le lien symbolique si necessaire
    if [ -L "$DRBD_DEVICE" ]; then
        REAL_DEV=$(readlink -f "$DRBD_DEVICE")
        if [ ! -b "$REAL_DEV" ]; then
            echo -e "${RED}[ERROR] $REAL_DEV n'est pas un block device${NC}"
            exit 1
        fi
    fi
}

check_primary() {
    ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")
    if [ "$ROLE" != "primary" ]; then
        echo -e "${RED}[ERROR] Ce noeud n'est pas PRIMARY${NC}"
        echo "Role actuel: $ROLE"
        echo "Executez: /scripts/drbd-init.sh primary"
        exit 1
    fi
}

format_device() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Formatage du device DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_device
    check_primary

    # Verifier si deja monte
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${RED}[ERROR] $MOUNT_POINT est deja monte!${NC}"
        echo "Demontez d'abord: $0 umount"
        exit 1
    fi

    # Verifier si deja formate
    if blkid "$DRBD_DEVICE" 2>/dev/null | grep -q "TYPE="; then
        echo -e "${YELLOW}[WARN] Le device semble deja formate:${NC}"
        blkid "$DRBD_DEVICE"
        echo ""
        read -p "Voulez-vous reformater? ATTENTION: Toutes les donnees seront perdues! (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation annulee."
            return 0
        fi
    fi

    echo -e "${GREEN}[INFO] Formatage en ext4...${NC}"
    mkfs.ext4 -F "$DRBD_DEVICE" 2>&1

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}[SUCCESS] Formatage termine!${NC}"
        echo ""
        echo "Prochaine etape: $0 mount"
    else
        echo -e "${RED}[ERROR] Echec du formatage${NC}"
        exit 1
    fi
}

mount_device() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Montage du filesystem DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_device
    check_primary

    # Verifier si deja monte
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${YELLOW}[WARN] $MOUNT_POINT est deja monte${NC}"
        df -h "$MOUNT_POINT"
        return 0
    fi

    # Creer le point de montage
    mkdir -p "$MOUNT_POINT"

    # Verifier si formate
    if ! blkid "$DRBD_DEVICE" 2>/dev/null | grep -q "TYPE="; then
        echo -e "${RED}[ERROR] Le device n'est pas formate${NC}"
        echo "Executez d'abord: $0 format"
        exit 1
    fi

    echo -e "${GREEN}[INFO] Montage de $DRBD_DEVICE sur $MOUNT_POINT...${NC}"
    mount "$DRBD_DEVICE" "$MOUNT_POINT"

    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}[SUCCESS] Filesystem monte!${NC}"
        echo ""
        df -h "$MOUNT_POINT"
        echo ""
        echo "Vous pouvez maintenant utiliser $MOUNT_POINT"
    else
        echo -e "${RED}[ERROR] Echec du montage${NC}"
        exit 1
    fi
}

umount_device() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Demontage du filesystem DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    if ! mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${YELLOW}[INFO] $MOUNT_POINT n'est pas monte${NC}"
        return 0
    fi

    echo -e "${GREEN}[INFO] Demontage de $MOUNT_POINT...${NC}"

    # Forcer la synchronisation
    sync

    umount "$MOUNT_POINT"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[SUCCESS] Filesystem demonte${NC}"
    else
        echo -e "${YELLOW}[WARN] Tentative de demontage force...${NC}"
        umount -f "$MOUNT_POINT" 2>/dev/null || umount -l "$MOUNT_POINT"
    fi
}

show_status() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Status du montage DRBD${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    echo ">>> Device DRBD:"
    if [ -e "$DRBD_DEVICE" ]; then
        if [ -L "$DRBD_DEVICE" ]; then
            REAL_DEV=$(readlink -f "$DRBD_DEVICE")
            echo "  $DRBD_DEVICE -> $REAL_DEV"
        else
            echo "  $DRBD_DEVICE"
        fi
        blkid "$DRBD_DEVICE" 2>/dev/null || echo "  (non formate)"
    else
        echo "  [NON DISPONIBLE]"
    fi

    echo ""
    echo ">>> Role DRBD:"
    ROLE=$(cat "$DRBD_ROLE_FILE" 2>/dev/null || echo "unknown")
    echo "  $ROLE"

    echo ""
    echo ">>> Point de montage:"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo "  [MONTE] $MOUNT_POINT"
        df -h "$MOUNT_POINT" | tail -1
    else
        echo "  [NON MONTE] $MOUNT_POINT"
    fi

    echo ""
    echo ">>> Contenu de $MOUNT_POINT:"
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        ls -la "$MOUNT_POINT" 2>/dev/null | head -10
    else
        echo "  (non monte)"
    fi
    echo ""
}

check_filesystem() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  Verification du filesystem${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""

    check_device

    # Demonter si monte
    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        echo -e "${YELLOW}[WARN] Le filesystem doit etre demonte pour la verification${NC}"
        read -p "Demonter maintenant? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            umount "$MOUNT_POINT"
        else
            echo "Operation annulee."
            return 1
        fi
    fi

    echo -e "${GREEN}[INFO] Verification du filesystem...${NC}"
    fsck -n "$DRBD_DEVICE"
    echo ""
}

# Main
case "${1:-help}" in
    format)
        format_device
        ;;
    mount)
        mount_device
        ;;
    umount|unmount)
        umount_device
        ;;
    status)
        show_status
        ;;
    check|fsck)
        check_filesystem
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
