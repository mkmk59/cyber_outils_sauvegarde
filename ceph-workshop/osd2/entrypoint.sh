#!/bin/bash
# =============================================================================
# Entrypoint pour Ceph OSD
# =============================================================================

set -e

CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}  Ceph Workshop - OSD: ${CEPH_NODE_NAME}${NC}"
echo -e "${CYAN}  OSD ID: ${CEPH_OSD_ID}${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

# Configurer /etc/hosts
cat >> /etc/hosts << EOF
172.20.0.11 mon1 ceph-mon1
172.20.0.12 mon2 ceph-mon2
172.20.0.13 mon3 ceph-mon3
172.20.0.21 osd1 ceph-osd1
172.20.0.22 osd2 ceph-osd2
172.20.0.23 osd3 ceph-osd3
172.20.0.31 mds1 ceph-mds
172.20.0.41 rgw1 ceph-rgw
172.20.0.50 client ceph-client
EOF

# Attendre la configuration
while [ ! -f /etc/ceph/ceph.conf ]; do
    echo "Attente de la configuration du cluster..."
    sleep 2
done

# Initialiser l'etat OSD
STATE_DIR="/var/lib/ceph/state"
mkdir -p "$STATE_DIR"

echo "up" > "$STATE_DIR/status"
echo "in" > "$STATE_DIR/in"
echo "0" > "$STATE_DIR/usage_percent"
echo "1073741824" > "$STATE_DIR/total_bytes"  # 1GB
echo "1073741824" > "$STATE_DIR/avail_bytes"

# Simuler le disque OSD
OSD_DIR="/var/lib/ceph/osd/ceph-${CEPH_OSD_ID}"
mkdir -p "$OSD_DIR"

cat << EOF

╔═══════════════════════════════════════════════════════════════════╗
║                    CEPH OSD - ${CEPH_NODE_NAME}                            ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  OSD ID: ${CEPH_OSD_ID}                                                    ║
║  Status: UP, IN                                                   ║
║  Disk: /data/osd/osd-disk.img (1GB)                              ║
║                                                                   ║
║  Commandes:                                                       ║
║    /scripts/ceph-status.sh     - Status du cluster                ║
║    /scripts/simulate-failure.sh osd.${CEPH_OSD_ID} - Simuler panne        ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF

exec "$@"
