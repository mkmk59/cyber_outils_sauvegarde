#!/bin/bash
# =============================================================================
# SOLUTION TP4 - Integration avec PostgreSQL
# =============================================================================

echo "=============================================="
echo "  SOLUTION TP4 - PostgreSQL sur DRBD"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Exercice 4.1: Test de Coherence
# -----------------------------------------------------------------------------

cat << 'EOF'
EXERCICE 4.1: Test de Coherence Transactionnelle

Objectif: Verifier que les transactions non commitees sont
          correctement annulees lors d'un failover.
EOF

echo ""
echo "Script de test de coherence:"
echo "============================"
echo ""

cat << 'SCRIPT'
#!/bin/bash
# =============================================================================
# Test de Coherence Transactionnelle PostgreSQL/DRBD
# =============================================================================

set -e

PGDATA="/mnt/drbd/pgdata"
PGUSER="postgres"
TESTDB="coherence_test"

log() {
    echo "[$(date '+%H:%M:%S')] $1"
}

# Preparation
setup_test() {
    log "Creation de la base de test..."

    su - $PGUSER -c "psql -c \"DROP DATABASE IF EXISTS $TESTDB;\""
    su - $PGUSER -c "psql -c \"CREATE DATABASE $TESTDB;\""

    su - $PGUSER -c "psql -d $TESTDB -c \"
        CREATE TABLE accounts (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100),
            balance DECIMAL(10,2) NOT NULL DEFAULT 0
        );

        INSERT INTO accounts (name, balance) VALUES
            ('Alice', 1000.00),
            ('Bob', 1000.00),
            ('Charlie', 1000.00);
    \""

    log "Base de test creee avec 3 comptes de 1000 chacun"
}

# Afficher les soldes
show_balances() {
    log "Soldes actuels:"
    su - $PGUSER -c "psql -d $TESTDB -c \"SELECT * FROM accounts;\""

    TOTAL=$(su - $PGUSER -c "psql -t -d $TESTDB -c \"SELECT SUM(balance) FROM accounts;\"")
    log "Total: $TOTAL (devrait etre 3000.00)"
}

# Test 1: Transaction commitee
test_committed_transaction() {
    log "=========================================="
    log "TEST 1: Transaction commitee"
    log "=========================================="

    su - $PGUSER -c "psql -d $TESTDB -c \"
        BEGIN;
        UPDATE accounts SET balance = balance - 100 WHERE name = 'Alice';
        UPDATE accounts SET balance = balance + 100 WHERE name = 'Bob';
        COMMIT;
    \""

    log "Transaction commitee: Alice -> Bob (100)"
    show_balances
}

# Test 2: Transaction non commitee (simulation de crash)
test_uncommitted_transaction() {
    log "=========================================="
    log "TEST 2: Transaction NON commitee + failover"
    log "=========================================="

    log "Demarrage d'une transaction longue..."

    # Lancer une transaction qui ne commit pas
    su - $PGUSER -c "psql -d $TESTDB" << 'SQL' &
        BEGIN;
        UPDATE accounts SET balance = balance - 500 WHERE name = 'Bob';
        UPDATE accounts SET balance = balance + 500 WHERE name = 'Charlie';
        -- Pas de COMMIT!
        SELECT pg_sleep(60);  -- Attendre 60 secondes
SQL
    TX_PID=$!

    sleep 2

    log "Transaction en cours (PID: $TX_PID)..."
    log "Verification des soldes PENDANT la transaction:"

    # Les changements ne sont pas visibles car pas commitee
    su - $PGUSER -c "psql -d $TESTDB -c \"SELECT * FROM accounts;\""

    log ""
    log ">>> SIMULATION DU FAILOVER <<<"
    log "Arret brutal de PostgreSQL..."

    # Tuer PostgreSQL brutalement (simule crash)
    pkill -9 postgres || true
    sleep 2

    log "PostgreSQL arrete."
    log ""
}

# Verification apres recovery
verify_after_recovery() {
    log "=========================================="
    log "VERIFICATION APRES RECOVERY"
    log "=========================================="

    log "Redemarrage de PostgreSQL..."
    su - $PGUSER -c "pg_ctl -D $PGDATA start" || true
    sleep 5

    log "Verification des soldes apres recovery:"
    show_balances

    # Verifier l'integrite
    TOTAL=$(su - $PGUSER -c "psql -t -d $TESTDB -c \"SELECT SUM(balance) FROM accounts;\"" | tr -d ' ')

    if [ "$TOTAL" == "3000.00" ]; then
        log "SUCCESS: Integrite des donnees preservee!"
        log "La transaction non commitee a ete correctement annulee (rollback)."
    else
        log "FAILURE: Integrite compromise! Total = $TOTAL (attendu: 3000.00)"
    fi
}

# Main
main() {
    log "=========================================="
    log "DEBUT DU TEST DE COHERENCE"
    log "=========================================="
    echo ""

    setup_test
    show_balances
    echo ""

    test_committed_transaction
    echo ""

    test_uncommitted_transaction
    echo ""

    verify_after_recovery
    echo ""

    log "=========================================="
    log "FIN DU TEST DE COHERENCE"
    log "=========================================="
}

main
SCRIPT

echo ""
echo "=============================================="
echo "  Resultats Attendus"
echo "=============================================="
echo ""

cat << 'EOF'
RESULTATS ATTENDUS:

1. Avant le test:
   Alice: 1000, Bob: 1000, Charlie: 1000, Total: 3000

2. Apres transaction commitee (Alice -> Bob: 100):
   Alice: 900, Bob: 1100, Charlie: 1000, Total: 3000

3. Pendant transaction non commitee (Bob -> Charlie: 500):
   Alice: 900, Bob: 1100, Charlie: 1000, Total: 3000
   (Les changements non commites ne sont pas visibles)

4. Apres crash et recovery:
   Alice: 900, Bob: 1100, Charlie: 1000, Total: 3000
   (La transaction non commitee est annulee = rollback automatique)

POURQUOI CA FONCTIONNE:
- PostgreSQL utilise le WAL (Write-Ahead Logging)
- Les transactions non commitees ne sont pas durables
- Au recovery, PostgreSQL rejoue le WAL et annule les transactions incompletes
- DRBD replique au niveau bloc, donc le WAL est replique
- Protocol C garantit que le WAL est sur les deux noeuds avant ACK
EOF

# -----------------------------------------------------------------------------
# Exercice 4.2: Benchmark PostgreSQL
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "  Exercice 4.2: Benchmark PostgreSQL"
echo "=============================================="
echo ""

cat << 'SCRIPT'
#!/bin/bash
# =============================================================================
# Benchmark PostgreSQL sur DRBD vs Local
# =============================================================================

PGDATA="/mnt/drbd/pgdata"
PGDATA_LOCAL="/var/lib/postgresql/data"
TESTDB="benchmark"
SCALE=10  # Facteur d'echelle pgbench

# Initialiser pgbench
init_pgbench() {
    DB_PATH=$1
    DB_NAME=$2

    echo "Initialisation pgbench (scale=$SCALE)..."
    su - postgres -c "pgbench -i -s $SCALE $DB_NAME"
}

# Executer le benchmark
run_benchmark() {
    DB_NAME=$1
    LABEL=$2

    echo ""
    echo "=========================================="
    echo "Benchmark: $LABEL"
    echo "=========================================="

    # Benchmark lecture seule
    echo ""
    echo "--- Read-Only (SELECT) ---"
    su - postgres -c "pgbench -c 10 -j 2 -T 30 -S $DB_NAME"

    # Benchmark lecture/ecriture
    echo ""
    echo "--- Read-Write (TPC-B like) ---"
    su - postgres -c "pgbench -c 10 -j 2 -T 30 $DB_NAME"

    # Benchmark ecriture intensive
    echo ""
    echo "--- Write-Heavy ---"
    su - postgres -c "pgbench -c 10 -j 2 -T 30 -N $DB_NAME"
}

# Resultats compares
show_comparison() {
    cat << 'RESULTS'

RESULTATS TYPIQUES DE COMPARAISON:

┌─────────────────────┬────────────────┬────────────────┬───────────┐
│ Test                │ Local SSD      │ DRBD (Proto C) │ Overhead  │
├─────────────────────┼────────────────┼────────────────┼───────────┤
│ Read-Only TPS       │ 45,000         │ 44,500         │ ~1%       │
│ Read-Write TPS      │ 3,200          │ 1,800          │ ~44%      │
│ Write-Heavy TPS     │ 2,800          │ 1,200          │ ~57%      │
├─────────────────────┼────────────────┼────────────────┼───────────┤
│ Latency (avg) R/O   │ 0.22 ms        │ 0.23 ms        │ ~5%       │
│ Latency (avg) R/W   │ 3.1 ms         │ 5.5 ms         │ ~77%      │
│ Latency (avg) Write │ 3.6 ms         │ 8.3 ms         │ ~130%     │
└─────────────────────┴────────────────┴────────────────┴───────────┘

OBSERVATIONS:

1. Lectures (Read-Only):
   - Overhead negligeable (~1%)
   - DRBD n'impacte pas les lectures

2. Ecritures (Read-Write, Write-Heavy):
   - Overhead significatif (40-60%)
   - Normal avec Protocol C (attente sync reseau)
   - Acceptable pour la securite des donnees

3. Latence:
   - Augmentation proportionnelle a la latence reseau
   - Protocol C ajoute 1 RTT par ecriture

OPTIMISATIONS POSSIBLES:

1. Materiel:
   - NVMe SSD pour reduire la latence disque
   - Reseau 10Gbps+ avec faible latence
   - Jumbo frames actives

2. PostgreSQL:
   - Augmenter shared_buffers
   - Ajuster wal_buffers
   - synchronous_commit = off (si acceptable)

3. DRBD:
   - Augmenter max-buffers
   - Augmenter al-extents
   - Utiliser Protocol A/B si RPO>0 acceptable

RESULTS
}

# Main
echo "PostgreSQL Benchmark sur DRBD"
echo "============================="
echo ""
echo "Configuration: Scale Factor = $SCALE"
echo ""

# Option: executer ou afficher resultats
case "$1" in
    run)
        init_pgbench "$PGDATA" "$TESTDB"
        run_benchmark "$TESTDB" "DRBD Protocol C"
        ;;
    compare)
        show_comparison
        ;;
    *)
        echo "Usage: $0 {run|compare}"
        echo ""
        show_comparison
        ;;
esac
SCRIPT

echo ""
echo "=============================================="
echo "  Recommandations Production"
echo "=============================================="
echo ""

cat << 'EOF'
RECOMMANDATIONS POUR POSTGRESQL EN PRODUCTION SUR DRBD:

1. Configuration PostgreSQL optimisee:
   ─────────────────────────────────────
   # postgresql.conf
   shared_buffers = 25% de la RAM
   effective_cache_size = 75% de la RAM
   work_mem = 256MB
   maintenance_work_mem = 512MB

   # WAL
   wal_buffers = 64MB
   checkpoint_completion_target = 0.9
   max_wal_size = 4GB

   # Si RPO de quelques transactions acceptable:
   # synchronous_commit = off

2. Configuration DRBD optimisee:
   ─────────────────────────────
   disk {
       al-extents 6007;
       c-max-rate 720M;
   }
   net {
       max-buffers 36k;
       sndbuf-size 1024k;
       rcvbuf-size 2048k;
   }

3. Architecture recommandee:
   ─────────────────────────
   - Reseau dedie pour DRBD (10Gbps)
   - Disques NVMe dedies
   - RAM suffisante pour buffer pool

4. Monitoring:
   ────────────
   - pg_stat_activity pour sessions
   - pg_stat_bgwriter pour checkpoints
   - drbdsetup status pour replication
   - Alertes sur lag de replication
EOF
