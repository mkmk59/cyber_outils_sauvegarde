#!/bin/bash
# =============================================================================
# Backend Status Script - Workshop HAProxy
# =============================================================================
# Usage: /scripts/backend-status.sh
# =============================================================================

SOCKET="/var/run/haproxy/admin.sock"

echo "============================================"
echo "  STATUT DES BACKENDS"
echo "============================================"
echo ""

# Test de chaque backend
echo ">>> Etat des serveurs:"
echo ""
printf "  %-12s %-15s %s\n" "SERVEUR" "IP" "STATUS"
printf "  %-12s %-15s %s\n" "-------" "--" "------"

for server in backend1 backend2 backend3; do
    case $server in
        backend1) ip="172.30.0.21" ;;
        backend2) ip="172.30.0.22" ;;
        backend3) ip="172.30.0.23" ;;
    esac

    printf "  %-12s %-15s " "$server" "$ip"
    if curl -s --connect-timeout 2 http://$ip/health > /dev/null 2>&1; then
        echo "[UP]"
    else
        echo "[DOWN]"
    fi
done

echo ""

# Stats via socket si disponible
if [ -S "$SOCKET" ]; then
    echo ">>> Statistiques HAProxy:"
    echo ""
    echo "show stat" | socat stdio $SOCKET 2>/dev/null | grep -E "^web_backend|^#" | cut -d',' -f1,2,18,19 | column -t -s',' 2>/dev/null || echo "  Stats non disponibles"
    echo ""
fi

# Test de load balancing
echo ">>> Test de distribution (5 requetes):"
echo ""
for i in $(seq 1 5); do
    response=$(curl -s --connect-timeout 2 http://localhost/ 2>/dev/null | grep -oE 'backend[0-9]' | head -1)
    echo "  Requete $i -> ${response:-erreur}"
done

echo ""
echo "============================================"
