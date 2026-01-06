#!/bin/bash
# =============================================================================
# Entrypoint pour DRBD Node 2
# =============================================================================

set +e

echo "=============================================="
echo "  DRBD Workshop - Node: ${DRBD_NODE_NAME}"
echo "=============================================="
echo ""
echo "Configuration:"
echo "  - Node IP: ${DRBD_NODE_IP}"
echo "  - Peer IP: ${DRBD_PEER_IP}"
echo "  - DRBD Port: ${DRBD_PORT}"
echo "  - Resource: ${DRBD_RESOURCE}"
echo ""

# Creer le fichier hosts
grep -q "node1" /etc/hosts || echo "172.28.0.11 node1" >> /etc/hosts
grep -q "node2" /etc/hosts || echo "172.28.0.12 node2" >> /etc/hosts

# Creer les repertoires necessaires
mkdir -p /data
mkdir -p /mnt/drbd
mkdir -p /var/lib/drbd

# Initialiser le fichier disque DRBD (500MB)
if [ ! -f /data/drbd-disk.img ]; then
    echo ">>> Creation du fichier disque DRBD (500MB)..."
    dd if=/dev/zero of=/data/drbd-disk.img bs=1M count=500 2>/dev/null
    echo "[OK] Fichier disque cree: /data/drbd-disk.img"
fi

# Creer le loop device pour simuler /dev/drbd0
echo ">>> Configuration du loop device..."

# Trouver un loop device libre
LOOP_DEV=""
for i in 0 1 2 3 4 5 6 7; do
    if [ -e /dev/loop$i ]; then
        # Verifier si deja attache a notre fichier
        if losetup /dev/loop$i 2>/dev/null | grep -q "/data/drbd-disk.img"; then
            LOOP_DEV="/dev/loop$i"
            echo "[INFO] Loop device deja configure: $LOOP_DEV"
            break
        fi
    fi
done

# Si pas trouve, essayer d'en configurer un
if [ -z "$LOOP_DEV" ]; then
    for i in 0 1 2 3 4 5 6 7; do
        if [ -e /dev/loop$i ]; then
            # Detacher si attache
            losetup -d /dev/loop$i 2>/dev/null || true
            # Essayer d'attacher
            if losetup /dev/loop$i /data/drbd-disk.img 2>/dev/null; then
                LOOP_DEV="/dev/loop$i"
                echo "[OK] Loop device configure: $LOOP_DEV -> /data/drbd-disk.img"
                break
            fi
        fi
    done
fi

if [ -n "$LOOP_DEV" ]; then
    # Creer un lien symbolique /dev/drbd0 -> loop device
    rm -f /dev/drbd0 2>/dev/null || true
    ln -sf $LOOP_DEV /dev/drbd0
    echo "[OK] Lien symbolique: /dev/drbd0 -> $LOOP_DEV"

    # Sauvegarder le loop device utilise
    echo "$LOOP_DEV" > /var/lib/drbd/loop_device
else
    echo "[ERROR] Impossible de configurer le loop device"
    echo "        Les containers ont besoin de --privileged"
fi

# Verifier le device
echo ""
echo ">>> Verification du device:"
if [ -L /dev/drbd0 ]; then
    REAL_DEV=$(readlink -f /dev/drbd0)
    echo "  /dev/drbd0 -> $REAL_DEV"
    if [ -b "$REAL_DEV" ]; then
        SIZE=$(blockdev --getsize64 "$REAL_DEV" 2>/dev/null || echo "unknown")
        echo "  [OK] Block device disponible (${SIZE} bytes)"
    fi
elif [ -b /dev/drbd0 ]; then
    echo "  [OK] /dev/drbd0 est un block device"
else
    echo "  [WARN] /dev/drbd0 non disponible"
fi

# Message de bienvenue
cat << 'EOF'

=====================================================================
                    DRBD WORKSHOP - LAB ENVIRONMENT
=====================================================================

  Commandes disponibles:

  /scripts/drbd-init.sh       - Initialiser DRBD
  /scripts/drbd-status.sh     - Voir le status
  /scripts/drbd-role.sh       - Changer de role
  /scripts/drbd-mount.sh      - Monter/demonter le filesystem
  /scripts/monitor.sh         - Monitoring temps reel
  /scripts/benchmark.sh       - Lancer des benchmarks
  /scripts/failover.sh        - Effectuer un failover
  /scripts/simulate-failure.sh - Simuler des pannes

  Pour commencer:
    1. /scripts/drbd-init.sh create-md
    2. /scripts/drbd-init.sh start
    3. /scripts/drbd-init.sh primary --force   # Sur node1
    4. /scripts/drbd-mount.sh format           # Formater (premiere fois)
    5. /scripts/drbd-mount.sh mount            # Monter

=====================================================================

EOF

# Executer la commande passee en argument
exec "$@"
