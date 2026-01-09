#!/bin/bash

# TP4 - Integration PostgreSQL avec DRBD
# Ce script automatise les etapes: preparation du stockage, init PostgreSQL,
# insertion de donnees, failover, verification, et exercices de coherence.

set -euo pipefail

NODE1="drbd-node1"
NODE2="drbd-node2"
DRBD_DEV="/dev/drbd0"
DRBD_MNT="/mnt/drbd"
PGDATA="$DRBD_MNT/pgdata"
NET_CIDR="172.28.0.0/16"
PG_BIN_PATH="/usr/lib/postgresql/15/bin:/usr/lib/postgresql/14/bin:/usr/local/bin:/usr/bin:/bin"

section() {
  echo ""
  echo "================================================================"
  echo "${1}"
  echo "================================================================"
  echo ""
}

print_architecture() {
  cat <<'ARCH'
POSTGRESQL SUR DRBD - HAUTE DISPONIBILITE

+---------------------------+    +---------------------------+
|           NODE 1          |    |           NODE 2          |
|                           |    |                           |
|   PostgreSQL (Active)     |    |   PostgreSQL (Standby)    |
|   Port 5432               |    |   (non demarre)           |
|           |               |    |                           |
|           v               |    |                           |
|   /mnt/drbd/pgdata        |    |   /mnt/drbd/pgdata        |
|   (Mounted - R/W)         |    |   (Not Mounted)           |
|           |               |    |           |               |
|        /dev/drbd0         |<---+--->   /dev/drbd0          |
|        (Primary)          |    |       (Secondary)         |
+---------------------------+    +---------------------------+

En cas de failover:
 1) PostgreSQL s'arrete sur Node 1
 2) DRBD bascule: Node 2 devient Primary
 3) Le FS est monte sur Node 2
 4) PostgreSQL demarre sur Node 2
ARCH
}

run_node() {
  local node=$1; shift
  echo "[$node] $*"
  docker exec "$node" bash -c "$*"
}

prepare_roles() {
  # Ensure clean mounts and roles before starting TP
  run_node "$NODE2" "umount $DRBD_MNT || true"
  run_node "$NODE1" "umount $DRBD_MNT || true"
  run_node "$NODE1" "/scripts/drbd-role.sh primary --force"
  run_node "$NODE2" "/scripts/drbd-role.sh secondary"
}

ensure_pg_binaries() {
  local node=$1
  run_node "$node" "command -v initdb >/dev/null 2>&1 || (apt-get update && apt-get install -y postgresql postgresql-contrib)"
}

ensure_drbd_primary_node1() {
  echo "[Check] Verifier DRBD Primary sur $NODE1"
  run_node "$NODE1" "/scripts/drbd-status.sh --brief || true"
}

step1_prepare_storage() {
  section "ETAPE 1 - PREPARER LE STOCKAGE DRBD POUR POSTGRESQL"
  prepare_roles
  ensure_drbd_primary_node1
  run_node "$NODE1" "mkdir -p $PGDATA && chown -R postgres:postgres $PGDATA && chmod 700 $PGDATA"
  echo "[OK] Repertoire $PGDATA cree et permissions appliquees sur $NODE1"
}

step2_init_postgresql() {
  section "ETAPE 2 - INITIALISER POSTGRESQL"
  ensure_pg_binaries "$NODE1"
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; if [ -f $PGDATA/PG_VERSION ]; then echo 'PG deja initialise, skip initdb'; else su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH initdb -D $PGDATA\"; fi"
  run_node "$NODE1" "grep -q 'TP4-DRBD' $PGDATA/postgresql.conf 2>/dev/null || cat <<'EOF' >> $PGDATA/postgresql.conf
# TP4-DRBD
listen_addresses = '*'
port = 5432
max_connections = 100
EOF"
  run_node "$NODE1" "grep -q 'TP4-DRBD' $PGDATA/pg_hba.conf 2>/dev/null || cat <<EOF >> $PGDATA/pg_hba.conf
# TP4-DRBD
host    all    all    $NET_CIDR    md5
EOF"
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH pg_ctl -D $PGDATA start\" || su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH pg_ctl -D $PGDATA restart\""
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH psql -c \\\"SELECT version();\\\"\""
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH createdb testdb\" || true"
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH psql -d testdb -c \\\"CREATE TABLE IF NOT EXISTS test (id SERIAL PRIMARY KEY, data TEXT, created_at TIMESTAMP DEFAULT NOW());\\\"\""
  echo "[OK] PostgreSQL initialise et base testdb creee sur $NODE1"
}

step3_insert_data() {
  section "ETAPE 3 - INSERER DES DONNEES DE TEST"
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH psql -d testdb -c \\\"INSERT INTO test (data) SELECT 'Record ' || generate_series(1,1000);\\\"\""
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH psql -d testdb -c 'SELECT COUNT(*) FROM test;'\""
  echo "[OK] 1000 enregistrements inseres"
}

step4_failover_db() {
  section "ETAPE 4 - FAILOVER DE LA BASE"
  echo "[Node1] Arret propre de PostgreSQL"
  run_node "$NODE1" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH pg_ctl -D $PGDATA stop\" || true"
  echo "[Node1] Demontage DRBD"
  run_node "$NODE1" "umount $DRBD_MNT || true"
  echo "[Node1] Passage en Secondary"
  run_node "$NODE1" "/scripts/drbd-role.sh secondary"

  echo "[Node2] Promotion en Primary"
  run_node "$NODE2" "umount $DRBD_MNT || true"
  run_node "$NODE2" "/scripts/drbd-role.sh primary --force"
  echo "[Node2] Montage DRBD"
  if docker exec "$NODE2" bash -c "[ -b $DRBD_DEV ]"; then
    run_node "$NODE2" "mkdir -p $DRBD_MNT && mount $DRBD_DEV $DRBD_MNT"
  else
    echo "[WARN] $DRBD_DEV absent sur $NODE2, copie des donnees depuis $NODE1 (simulation)"
    run_node "$NODE2" "mkdir -p $DRBD_MNT"
    docker exec "$NODE1" bash -c "cd $DRBD_MNT && tar cf - ." | docker exec -i "$NODE2" bash -c "cd $DRBD_MNT && tar xf -"
  fi
  echo "[Node2] Demarrage PostgreSQL"
  ensure_pg_binaries "$NODE2"
  run_node "$NODE2" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH pg_ctl -D $PGDATA start\" || su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH pg_ctl -D $PGDATA restart\""
  echo "[Node2] Verification des donnees"
  run_node "$NODE2" "export PATH=\"$PG_BIN_PATH:\$PATH\"; su - postgres -c \"PATH=$PG_BIN_PATH:\\$PATH psql -d testdb -c 'SELECT COUNT(*) FROM test;'\""
  echo "[OK] Failover PostgreSQL effectue sur $NODE2"
}

step5_script_failover() {
  section "ETAPE 5 - SCRIPT DE FAILOVER AUTOMATISE (/scripts/pg-failover.sh)"
  echo "Commandes clefs:" 
  echo "  Sur le Primary actuel: /scripts/pg-failover.sh failover"
  echo "  Sur le Secondary:      /scripts/pg-failover.sh takeover"
  echo "  Status:                /scripts/pg-failover.sh status"
  echo "  Init Postgres:         /scripts/pg-failover.sh init"
}

exercises() {
  section "EXERCICES"
  echo "Exercice 4.1 - Test de coherence"
  echo "  1) Sur Node1, lancer une transaction longue:" 
  echo "     docker exec -it $NODE1 bash"
  echo "     su - postgres -c \"psql -d testdb\""
  echo "       BEGIN;"
  echo "       INSERT INTO test(data) VALUES('long txn');"
  echo "       -- ne pas COMMIT"
  echo "  2) Dans un autre terminal, lancer le failover (Node1 -> Node2):"
  echo "     bash solutions/tp4-solution.sh --failover-only"
  echo "  3) Sur Node2, verifier que la transaction non committee est annulee:"
  echo "     docker exec $NODE2 su - postgres -c \"psql -d testdb -c 'SELECT COUNT(*) FROM test;'\""
  echo "
Exercice 4.2 - Benchmark PostgreSQL"
  echo "  1) Installer pgbench (dans les conteneurs si absent):"
  echo "     docker exec $NODE1 apt-get update && docker exec $NODE1 apt-get install -y postgresql-contrib"
  echo "  2) Initialiser pgbench:"
  echo "     docker exec $NODE1 su - postgres -c \"pgbench -i -s 10 testdb\""
  echo "  3) Lancer un benchmark:"
  echo "     docker exec $NODE1 su - postgres -c \"pgbench -c 10 -j 2 -T 60 testdb\""
  echo "  4) Comparer les performances avec DRBD actif et apres failover sur $NODE2"
}

prereq() {
  section "PREREQUIS"
  echo "Assurez-vous que le docker-compose DRBD est demarre:"
  echo "  docker compose -f drbd-workshop/docker-compose.yaml up -d"
  echo "Conteneurs attendus: $NODE1 et $NODE2"
}

main() {
  MODE=${1:-full}
  prereq
  print_architecture
  step1_prepare_storage
  step2_init_postgresql
  step3_insert_data
  step4_failover_db
  step5_script_failover
  exercises
  echo "" 
  echo "[FIN] TP4 termine"
}

if [[ "${1:-}" == "--failover-only" ]]; then
  step4_failover_db
  exit 0
fi

main "$@"
