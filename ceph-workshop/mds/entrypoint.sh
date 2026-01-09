#!/bin/bash
# =============================================================================
# Entrypoint pour Ceph MDS (Metadata Server)
# =============================================================================

set -e

CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}  Ceph Workshop - MDS: ${CEPH_NODE_NAME}${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

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

while [ ! -f /etc/ceph/ceph.conf ]; do
    echo "Attente de la configuration du cluster..."
    sleep 2
done

STATE_DIR="/var/lib/ceph/state"
mkdir -p "$STATE_DIR"
echo "active" > "$STATE_DIR/mds_status"

cat << EOF

╔═══════════════════════════════════════════════════════════════════╗
║                    CEPH MDS - Metadata Server                     ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  MDS Name: ${CEPH_NODE_NAME}                                              ║
║  Status: Active                                                   ║
║  Role: Gestion des metadonnees CephFS                             ║
║                                                                   ║
║  Commandes:                                                       ║
║    /scripts/cephfs-setup.sh    - Configurer CephFS                ║
║    /scripts/ceph-status.sh     - Status du cluster                ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF

exec "$@"
