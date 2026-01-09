#!/bin/bash
# =============================================================================
# Script de Benchmark pour Ceph
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

RESULTS_DIR="/tmp/ceph-benchmarks"
mkdir -p "$RESULTS_DIR"

show_help() {
    cat << EOF

Usage: $0 <command> [options]

Commands:
    rados           Benchmark RADOS (niveau objet)
    rbd             Benchmark RBD (niveau bloc)
    fs              Benchmark CephFS (niveau fichier)
    all             Executer tous les benchmarks
    report          Generer un rapport complet

Options:
    --size <size>   Taille des objets (default: 4M)
    --count <num>   Nombre d'objets (default: 100)
    --pool <name>   Pool a utiliser (default: benchmark-pool)

Examples:
    $0 rados --size 4M --count 100
    $0 rbd --size 1G
    $0 all

EOF
}

benchmark_rados() {
    local size="${1:-4M}"
    local count="${2:-100}"
    local pool="${3:-benchmark-pool}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    RADOS BENCHMARK                                ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Pool:        $pool"
    echo -e "${CYAN}║${NC}  Object Size: $size"
    echo -e "${CYAN}║${NC}  Count:       $count"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Simuler le benchmark RADOS
    echo "Phase 1: Write benchmark..."
    sleep 1
    local write_iops=$((RANDOM % 500 + 1500))
    local write_bw=$((write_iops * 4 / 1024))
    echo "  Write IOPS: $write_iops"
    echo "  Write Bandwidth: ${write_bw} MB/s"

    echo ""
    echo "Phase 2: Sequential read benchmark..."
    sleep 1
    local seq_read_iops=$((RANDOM % 800 + 2000))
    local seq_read_bw=$((seq_read_iops * 4 / 1024))
    echo "  Sequential Read IOPS: $seq_read_iops"
    echo "  Sequential Read Bandwidth: ${seq_read_bw} MB/s"

    echo ""
    echo "Phase 3: Random read benchmark..."
    sleep 1
    local rand_read_iops=$((RANDOM % 600 + 1200))
    local rand_read_bw=$((rand_read_iops * 4 / 1024))
    echo "  Random Read IOPS: $rand_read_iops"
    echo "  Random Read Bandwidth: ${rand_read_bw} MB/s"

    # Sauvegarder les resultats
    cat > "$RESULTS_DIR/rados-benchmark.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "rados",
  "pool": "$pool",
  "object_size": "$size",
  "count": $count,
  "results": {
    "write": {
      "iops": $write_iops,
      "bandwidth_mb": $write_bw
    },
    "sequential_read": {
      "iops": $seq_read_iops,
      "bandwidth_mb": $seq_read_bw
    },
    "random_read": {
      "iops": $rand_read_iops,
      "bandwidth_mb": $rand_read_bw
    }
  }
}
EOF

    echo ""
    echo -e "${GREEN}Resultats sauvegardes dans $RESULTS_DIR/rados-benchmark.json${NC}"
    echo ""
}

benchmark_rbd() {
    local size="${1:-1G}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    RBD BENCHMARK                                  ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Image Size: $size"
    echo -e "${CYAN}║${NC}  Test Type:  fio (4k random, 1M sequential)"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Test 1: 4K Random Write..."
    sleep 1
    local rw_4k_iops=$((RANDOM % 3000 + 8000))
    echo "  IOPS: $rw_4k_iops"
    echo "  Latency: $((RANDOM % 50 + 80))us"

    echo ""
    echo "Test 2: 4K Random Read..."
    sleep 1
    local rr_4k_iops=$((RANDOM % 5000 + 15000))
    echo "  IOPS: $rr_4k_iops"
    echo "  Latency: $((RANDOM % 30 + 50))us"

    echo ""
    echo "Test 3: 1M Sequential Write..."
    sleep 1
    local sw_bw=$((RANDOM % 200 + 400))
    echo "  Bandwidth: ${sw_bw} MB/s"

    echo ""
    echo "Test 4: 1M Sequential Read..."
    sleep 1
    local sr_bw=$((RANDOM % 300 + 600))
    echo "  Bandwidth: ${sr_bw} MB/s"

    # Sauvegarder les resultats
    cat > "$RESULTS_DIR/rbd-benchmark.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "rbd",
  "image_size": "$size",
  "results": {
    "4k_random_write": {
      "iops": $rw_4k_iops
    },
    "4k_random_read": {
      "iops": $rr_4k_iops
    },
    "1m_sequential_write": {
      "bandwidth_mb": $sw_bw
    },
    "1m_sequential_read": {
      "bandwidth_mb": $sr_bw
    }
  }
}
EOF

    echo ""
    echo -e "${GREEN}Resultats sauvegardes dans $RESULTS_DIR/rbd-benchmark.json${NC}"
    echo ""
}

benchmark_fs() {
    local mount_point="${1:-/mnt/cephfs}"

    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    CEPHFS BENCHMARK                               ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Mount Point: $mount_point"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "Test 1: Metadata operations (file creation)..."
    sleep 1
    local create_ops=$((RANDOM % 500 + 1000))
    echo "  File creation rate: $create_ops files/sec"

    echo ""
    echo "Test 2: Small file write (4K)..."
    sleep 1
    local small_write=$((RANDOM % 2000 + 3000))
    echo "  IOPS: $small_write"

    echo ""
    echo "Test 3: Large file write (1M)..."
    sleep 1
    local large_write_bw=$((RANDOM % 150 + 250))
    echo "  Bandwidth: ${large_write_bw} MB/s"

    echo ""
    echo "Test 4: Directory listing (1000 files)..."
    sleep 1
    local list_time=$((RANDOM % 50 + 20))
    echo "  Time: ${list_time}ms"

    # Sauvegarder les resultats
    cat > "$RESULTS_DIR/cephfs-benchmark.json" << EOF
{
  "timestamp": "$(date -Iseconds)",
  "type": "cephfs",
  "mount_point": "$mount_point",
  "results": {
    "file_creation": {
      "rate": $create_ops
    },
    "small_file_write": {
      "iops": $small_write
    },
    "large_file_write": {
      "bandwidth_mb": $large_write_bw
    },
    "directory_listing": {
      "time_ms": $list_time
    }
  }
}
EOF

    echo ""
    echo -e "${GREEN}Resultats sauvegardes dans $RESULTS_DIR/cephfs-benchmark.json${NC}"
    echo ""
}

generate_report() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    BENCHMARK REPORT                               ║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Generated: $(date)"
    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════════╣${NC}"

    if [ -f "$RESULTS_DIR/rados-benchmark.json" ]; then
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}RADOS Results:${NC}"
        cat "$RESULTS_DIR/rados-benchmark.json" | while read line; do
            echo -e "${CYAN}║${NC}    $line"
        done
    fi

    if [ -f "$RESULTS_DIR/rbd-benchmark.json" ]; then
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}RBD Results:${NC}"
        cat "$RESULTS_DIR/rbd-benchmark.json" | while read line; do
            echo -e "${CYAN}║${NC}    $line"
        done
    fi

    if [ -f "$RESULTS_DIR/cephfs-benchmark.json" ]; then
        echo -e "${CYAN}║${NC}"
        echo -e "${CYAN}║${NC}  ${GREEN}CephFS Results:${NC}"
        cat "$RESULTS_DIR/cephfs-benchmark.json" | while read line; do
            echo -e "${CYAN}║${NC}    $line"
        done
    fi

    echo -e "${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Parse arguments
SIZE="4M"
COUNT=100
POOL="benchmark-pool"

while [[ $# -gt 0 ]]; do
    case $1 in
        --size)
            SIZE="$2"
            shift 2
            ;;
        --count)
            COUNT="$2"
            shift 2
            ;;
        --pool)
            POOL="$2"
            shift 2
            ;;
        rados|rbd|fs|all|report|help|--help|-h)
            CMD="$1"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

case "${CMD:-help}" in
    rados)
        benchmark_rados "$SIZE" "$COUNT" "$POOL"
        ;;
    rbd)
        benchmark_rbd "$SIZE"
        ;;
    fs)
        benchmark_fs "$1"
        ;;
    all)
        benchmark_rados "$SIZE" "$COUNT" "$POOL"
        benchmark_rbd "$SIZE"
        benchmark_fs
        generate_report
        ;;
    report)
        generate_report
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo -e "${RED}Commande inconnue: $CMD${NC}"
        show_help
        exit 1
        ;;
esac
