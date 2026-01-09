#!/bin/bash
# =============================================================================
# Entrypoint pour Ceph RGW (RADOS Gateway - S3/Swift)
# =============================================================================

set -e

CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}  Ceph Workshop - RGW: ${CEPH_NODE_NAME}${NC}"
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
mkdir -p "$STATE_DIR/rgw"
mkdir -p "$STATE_DIR/rgw/users"
mkdir -p "$STATE_DIR/rgw/buckets"

echo "active" > "$STATE_DIR/rgw_status"

cat << EOF

╔═══════════════════════════════════════════════════════════════════╗
║                    CEPH RGW - RADOS Gateway                       ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  RGW Name: ${CEPH_NODE_NAME}                                              ║
║  Status: Active                                                   ║
║  Port: 7480                                                       ║
║  API: S3, Swift compatible                                        ║
║                                                                   ║
║  Endpoint: http://ceph-rgw:7480                                   ║
║                                                                   ║
║  Commandes:                                                       ║
║    /scripts/rgw-setup.sh       - Configurer utilisateurs S3       ║
║    /scripts/ceph-status.sh     - Status du cluster                ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF

exec "$@"
