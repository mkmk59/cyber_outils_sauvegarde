#!/bin/bash
# =============================================================================
# Entrypoint pour Ceph Node (Monitor/Manager/Client)
# =============================================================================

# Ne pas echouer immediatement
set +e

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}==============================================${NC}"
echo -e "${CYAN}  Ceph Workshop - Node: ${CEPH_NODE_NAME}${NC}"
echo -e "${CYAN}  Type: ${CEPH_NODE_TYPE}${NC}"
echo -e "${CYAN}==============================================${NC}"
echo ""

# Configuration reseau
echo "Configuration:"
echo "  - Node IP: ${CEPH_NODE_IP}"
echo "  - Cluster Network: ${CEPH_CLUSTER_NETWORK}"
echo "  - Public Network: ${CEPH_PUBLIC_NETWORK}"
echo ""

# Creer le fichier hosts
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

# Generer un FSID si premier monitor
FSID_FILE="/etc/ceph/fsid"
LOCK_FILE="/tmp/ceph-init.lock"

# Attendre que le repertoire soit pret
sleep 2

if [ "$CEPH_NODE_NAME" == "mon1" ]; then
    if [ ! -f "$FSID_FILE" ]; then
        FSID=$(uuidgen)
        echo "$FSID" > "$FSID_FILE" 2>/dev/null || true
    fi
fi

# Attendre que le FSID soit disponible
WAIT_COUNT=0
while [ ! -f "$FSID_FILE" ] && [ $WAIT_COUNT -lt 30 ]; do
    echo "Attente du FSID du cluster..."
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 1))
done

if [ -f "$FSID_FILE" ]; then
    FSID=$(cat "$FSID_FILE")
else
    FSID="00000000-0000-0000-0000-000000000000"
fi

# Creer la configuration Ceph (seulement si mon1 ou si n'existe pas)
if [ "$CEPH_NODE_NAME" == "mon1" ] || [ ! -f "/etc/ceph/ceph.conf" ]; then
    cat > /etc/ceph/ceph.conf 2>/dev/null << EOF
[global]
fsid = ${FSID}
mon_initial_members = mon1, mon2, mon3
mon_host = 172.20.0.11, 172.20.0.12, 172.20.0.13
public_network = ${CEPH_PUBLIC_NETWORK}
cluster_network = ${CEPH_CLUSTER_NETWORK}

auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx

osd_pool_default_size = 3
osd_pool_default_min_size = 2
osd_pool_default_pg_num = 64
osd_pool_default_pgp_num = 64

[mon]
mon_allow_pool_delete = true

[osd]
osd_journal_size = 1024
osd_max_object_name_len = 256
osd_max_object_namespace_len = 64

[client]
rbd_cache = true
EOF
fi

# Creer une cle admin simulee
if [ ! -f /etc/ceph/ceph.client.admin.keyring ]; then
    ADMIN_KEY=$(head -c 32 /dev/urandom | base64)
    cat > /etc/ceph/ceph.client.admin.keyring << EOF
[client.admin]
    key = ${ADMIN_KEY}
    caps mds = "allow *"
    caps mgr = "allow *"
    caps mon = "allow *"
    caps osd = "allow *"
EOF
    chmod 600 /etc/ceph/ceph.client.admin.keyring
fi

# Initialiser l'etat du cluster
STATE_DIR="/var/lib/ceph/state"
mkdir -p "$STATE_DIR"

# Fichiers d'etat
echo "HEALTH_OK" > "$STATE_DIR/health"
echo "3" > "$STATE_DIR/mon_count"
echo "3" > "$STATE_DIR/osd_count"
echo "true" > "$STATE_DIR/quorum"

# Simuler les OSDs
for i in 0 1 2; do
    echo "up" > "$STATE_DIR/osd_${i}_status"
    echo "in" > "$STATE_DIR/osd_${i}_in"
    echo "100" > "$STATE_DIR/osd_${i}_usage"
done

# Simuler les pools
mkdir -p "$STATE_DIR/pools"

# Message de bienvenue
cat << 'EOF'

╔═══════════════════════════════════════════════════════════════════╗
║                 CEPH WORKSHOP - LAB ENVIRONMENT                   ║
╠═══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  Commandes disponibles:                                           ║
║                                                                   ║
║  /scripts/ceph-status.sh       - Status du cluster                ║
║  /scripts/ceph-health.sh       - Sante detaillee                  ║
║  /scripts/pool-create.sh       - Creer un pool                    ║
║  /scripts/rbd-manage.sh        - Gerer les images RBD             ║
║  /scripts/cephfs-setup.sh      - Configurer CephFS                ║
║  /scripts/rgw-setup.sh         - Configurer le RGW/S3             ║
║  /scripts/simulate-failure.sh  - Simuler des pannes               ║
║  /scripts/recovery-check.sh    - Verifier le recovery             ║
║  /scripts/benchmark.sh         - Lancer des benchmarks            ║
║                                                                   ║
║  Pour commencer: /scripts/ceph-status.sh                          ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

EOF

# Executer la commande passee en argument
exec "$@"
