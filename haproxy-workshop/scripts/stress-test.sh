#!/bin/bash
# =============================================================================
# Stress Test Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/stress-test.sh [COMMAND] [OPTIONS]
# =============================================================================

set -e

show_help() {
    cat << 'EOF'
Usage: /scripts/stress-test.sh [COMMAND] [OPTIONS]

Commands:
  quick               - Test rapide (100 requetes)
  normal              - Test normal (1000 requetes)
  heavy               - Test intensif (5000 requetes)
  concurrent <n>      - Test avec N connexions simultanees
  duration <sec>      - Test pendant N secondes
  report              - Generer un rapport
  <url> [n] [c]       - Test custom: URL, n requetes (defaut: 100), c concurrence (defaut: 10)

Examples:
  /scripts/stress-test.sh quick
  /scripts/stress-test.sh concurrent 50
  /scripts/stress-test.sh duration 30
  /scripts/stress-test.sh report
  /scripts/stress-test.sh http://localhost 200
  /scripts/stress-test.sh http://localhost:8080 500 20
EOF
}

run_test() {
    local requests=$1
    local concurrency=$2
    local url=${3:-http://localhost/}

    echo "============================================"
    echo "  TEST DE CHARGE"
    echo "============================================"
    echo ""
    echo "URL:          $url"
    echo "Requetes:     $requests"
    echo "Concurrence:  $concurrency"
    echo ""

    # Verifier si ab est disponible
    if command -v ab > /dev/null 2>&1; then
        echo ">>> Execution avec Apache Bench (ab)..."
        echo ""
        ab -n $requests -c $concurrency -q "$url" 2>&1 | grep -E "Requests per second|Time per request|Transfer rate|Complete requests|Failed requests|Time taken"
    else
        # Fallback avec curl et boucle
        echo ">>> Execution avec curl (ab non disponible)..."
        echo ""

        local start_time=$(date +%s.%N)
        local success=0
        local failed=0

        # Creer des processus paralleles
        for i in $(seq 1 $requests); do
            {
                if curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" | grep -q "200\|304"; then
                    echo "OK"
                else
                    echo "FAIL"
                fi
            } &

            # Limiter la concurrence
            if [ $(jobs -r | wc -l) -ge $concurrency ]; then
                wait -n
            fi
        done

        wait

        local end_time=$(date +%s.%N)
        local duration=$(echo "$end_time - $start_time" | bc)
        local rps=$(echo "scale=2; $requests / $duration" | bc)

        echo ""
        echo "Resultats:"
        echo "  Requetes totales: $requests"
        echo "  Duree:            ${duration}s"
        echo "  Req/sec:          $rps"
    fi
    echo ""
}

quick_test() {
    echo "============================================"
    echo "  TEST RAPIDE (100 requetes)"
    echo "============================================"
    echo ""

    local success=0
    local failed=0
    local start_time=$(date +%s)

    declare -A backend_hits

    for i in $(seq 1 100); do
        response=$(curl -s --connect-timeout 5 http://localhost/ 2>/dev/null)
        if [ $? -eq 0 ]; then
            ((success++))
            backend=$(echo "$response" | grep -oE 'backend[0-9]' | head -1)
            [ -n "$backend" ] && backend_hits[$backend]=$((${backend_hits[$backend]:-0} + 1))
        else
            ((failed++))
        fi
    done

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    echo ">>> Resultats:"
    echo "  Requetes reussies: $success"
    echo "  Requetes echouees: $failed"
    echo "  Duree:             ${duration}s"
    [ $duration -gt 0 ] && echo "  Req/sec:           $((success / duration))"

    echo ""
    echo ">>> Distribution par backend:"
    for backend in "${!backend_hits[@]}"; do
        printf "  %-10s: %d requetes (%.1f%%)\n" "$backend" "${backend_hits[$backend]}" $(echo "scale=1; ${backend_hits[$backend]} * 100 / $success" | bc)
    done
    echo ""
}

normal_test() {
    run_test 1000 10 "http://localhost/"
}

heavy_test() {
    run_test 5000 50 "http://localhost/"
}

concurrent_test() {
    local concurrency=${1:-10}
    run_test 1000 $concurrency "http://localhost/"
}

duration_test() {
    local duration=${1:-30}

    echo "============================================"
    echo "  TEST DURATION: ${duration}s"
    echo "============================================"
    echo ""

    local end_time=$(($(date +%s) + duration))
    local success=0
    local failed=0
    local start_time=$(date +%s)

    echo ">>> Test en cours pendant ${duration} secondes..."
    echo ""

    while [ $(date +%s) -lt $end_time ]; do
        if curl -s -o /dev/null --connect-timeout 2 http://localhost/; then
            ((success++))
        else
            ((failed++))
        fi
    done

    local actual_duration=$(($(date +%s) - start_time))

    echo ">>> Resultats:"
    echo "  Requetes reussies: $success"
    echo "  Requetes echouees: $failed"
    echo "  Duree reelle:      ${actual_duration}s"
    echo "  Req/sec:           $((success / actual_duration))"
    echo ""
}

generate_report() {
    echo "============================================"
    echo "  RAPPORT DE PERFORMANCE"
    echo "============================================"
    echo ""

    echo ">>> Configuration HAProxy:"
    /scripts/haproxy-status.sh process 2>/dev/null | head -10

    echo ""
    echo ">>> Etat des backends:"
    /scripts/backend-manage.sh test 2>/dev/null

    echo ""
    echo ">>> Test de charge rapide:"
    quick_test

    echo ""
    echo ">>> Statistiques HAProxy:"
    if [ -S /var/run/haproxy/admin.sock ]; then
        echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -10
    else
        echo "Stats non disponibles (socket admin)"
    fi

    echo ""
    echo "============================================"
    echo "  FIN DU RAPPORT"
    echo "============================================"
}

# Main
case "${1:-help}" in
    quick)
        quick_test
        ;;
    normal)
        normal_test
        ;;
    heavy)
        heavy_test
        ;;
    concurrent)
        concurrent_test "${2:-10}"
        ;;
    duration)
        duration_test "${2:-30}"
        ;;
    report)
        generate_report
        ;;
    help|--help|-h)
        show_help
        ;;
    http://*|https://*)
        # Custom URL avec nombre de requetes optionnel
        run_test "${2:-100}" "${3:-10}" "$1"
        ;;
    *)
        echo "Commande inconnue: $1"
        show_help
        exit 1
        ;;
esac
