#!/bin/bash
# =============================================================================
# SOLUTION TP2 - Modes de Replication
# =============================================================================

echo "=============================================="
echo "  SOLUTION TP2 - Modes de Replication"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Exercice 2.1: Choix du Protocole
# -----------------------------------------------------------------------------

cat << 'EOF'
REPONSES - CHOIX DU PROTOCOLE:

┌─────────────────────────────────────────┬──────────┬─────────────────────────────────────────────┐
│ Scenario                                │ Protocol │ Justification                               │
├─────────────────────────────────────────┼──────────┼─────────────────────────────────────────────┤
│ Base de donnees financieres             │    C     │ Zero perte de donnees obligatoire.          │
│                                         │          │ Les transactions financieres ne peuvent     │
│                                         │          │ pas etre perdues. La latence supplementaire │
│                                         │          │ est acceptable pour la securite.            │
├─────────────────────────────────────────┼──────────┼─────────────────────────────────────────────┤
│ Serveur de logs                         │    A     │ Les logs sont importants mais peuvent       │
│                                         │          │ tolerer une perte minime. La performance    │
│                                         │          │ est prioritaire car le volume est eleve.    │
│                                         │          │ Protocol A offre le meilleur throughput.    │
├─────────────────────────────────────────┼──────────┼─────────────────────────────────────────────┤
│ Cluster de virtualisation               │    C     │ Les VMs contiennent des donnees critiques.  │
│                                         │          │ Une corruption de disque virtuel serait     │
│                                         │          │ catastrophique. La securite prime.          │
├─────────────────────────────────────────┼──────────┼─────────────────────────────────────────────┤
│ Replication inter-datacenter (100ms)    │    A     │ Avec 100ms de latence, Protocol C serait    │
│                                         │          │ trop lent (chaque ecriture +200ms).         │
│                                         │          │ Protocol A permet d'operer normalement.     │
│                                         │          │ Le RPO sera de quelques secondes max.       │
└─────────────────────────────────────────┴──────────┴─────────────────────────────────────────────┘

NOTES IMPORTANTES:

1. Protocol C est TOUJOURS recommande quand:
   - La latence reseau est faible (<5ms)
   - Les donnees sont critiques
   - Le RPO (Recovery Point Objective) doit etre 0

2. Protocol A est acceptable quand:
   - La performance est prioritaire
   - Une petite perte de donnees est toleree
   - La latence reseau est elevee

3. Protocol B est un bon compromis quand:
   - La latence reseau est moderee (5-20ms)
   - On veut un equilibre performance/securite

EOF

# -----------------------------------------------------------------------------
# Exercice 2.2: Simulation de Latence Reseau
# -----------------------------------------------------------------------------

echo ""
echo "=============================================="
echo "  Exercice 2.2: Script de Simulation Latence"
echo "=============================================="
echo ""

cat << 'SCRIPT'
#!/bin/bash
# Script pour simuler differentes latences et comparer les protocoles

# Configuration
LATENCIES=("0ms" "10ms" "50ms" "100ms")
PROTOCOLS=("A" "B" "C")
RESULTS_FILE="/tmp/latency_benchmark_results.txt"

# Fonction pour ajouter de la latence
add_latency() {
    LATENCY=$1
    PEER_IP="${DRBD_PEER_IP:-172.28.0.12}"

    if [ "$LATENCY" != "0ms" ]; then
        echo "Ajout de latence: $LATENCY"
        tc qdisc add dev eth0 root netem delay $LATENCY 2>/dev/null || \
        tc qdisc change dev eth0 root netem delay $LATENCY
    else
        echo "Suppression de la latence"
        tc qdisc del dev eth0 root 2>/dev/null || true
    fi
}

# Fonction de benchmark
run_benchmark() {
    PROTOCOL=$1
    LATENCY=$2

    echo "Testing Protocol $PROTOCOL with $LATENCY latency..."

    # Changer le protocole
    /scripts/change-protocol.sh $PROTOCOL <<< "y"

    # Attendre stabilisation
    sleep 5

    # Benchmark
    START=$(date +%s.%N)
    dd if=/dev/urandom of=/mnt/drbd/test_file bs=1M count=50 conv=fdatasync 2>/dev/null
    END=$(date +%s.%N)

    DURATION=$(echo "$END - $START" | bc)
    SPEED=$(echo "scale=2; 50 / $DURATION" | bc)

    echo "Protocol $PROTOCOL @ $LATENCY: ${SPEED} MB/s"
    echo "$PROTOCOL,$LATENCY,$SPEED" >> $RESULTS_FILE

    rm -f /mnt/drbd/test_file
}

# Main
echo "DRBD Latency Benchmark"
echo "======================"
echo ""

> $RESULTS_FILE
echo "Protocol,Latency,Speed_MBps" >> $RESULTS_FILE

for LATENCY in "${LATENCIES[@]}"; do
    add_latency $LATENCY

    for PROTOCOL in "${PROTOCOLS[@]}"; do
        run_benchmark $PROTOCOL $LATENCY
    done
done

# Restaurer
add_latency "0ms"
/scripts/change-protocol.sh C <<< "y"

echo ""
echo "Resultats sauvegardes dans $RESULTS_FILE"
echo ""
echo "Tableau de resultats:"
column -t -s',' $RESULTS_FILE
SCRIPT

echo ""
echo "=============================================="
echo "  Resultats Attendus (Exemple)"
echo "=============================================="
echo ""

cat << 'EOF'
Resultats typiques d'un benchmark avec simulation de latence:

┌──────────┬─────────┬────────────┬────────────┬────────────┐
│ Latency  │ Proto A │ Proto B    │ Proto C    │ Notes      │
├──────────┼─────────┼────────────┼────────────┼────────────┤
│ 0ms      │ 450 MB/s│ 380 MB/s   │ 320 MB/s   │ LAN local  │
│ 10ms     │ 420 MB/s│ 180 MB/s   │ 45 MB/s    │ Metro area │
│ 50ms     │ 380 MB/s│ 38 MB/s    │ 9 MB/s     │ Regional   │
│ 100ms    │ 350 MB/s│ 19 MB/s    │ 4.5 MB/s   │ WAN        │
└──────────┴─────────┴────────────┴────────────┴────────────┘

Observations:
- Protocol A reste performant quelle que soit la latence
- Protocol B est fortement impacte par la latence
- Protocol C devient tres lent avec latence >50ms

Recommandations:
- LAN local (0-5ms): Protocol C recommande
- Metro (5-20ms): Protocol B ou C selon criticite
- WAN (>20ms): Protocol A, sauf si RPO=0 obligatoire
EOF
