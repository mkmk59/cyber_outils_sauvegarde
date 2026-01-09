#!/bin/bash
# =============================================================================
# TP8 Solution: Monitoring et Statistiques HAProxy
# Martial HOCQUETTE / Mark GYURJYAN
# =============================================================================
# Objectifs:
#   1. Utiliser le dashboard de statistiques
#   2. Configurer les métriques
#   3. Analyser les logs
#   4. Monitorer les performances
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP8: Monitoring et Statistiques HAProxy"
echo "============================================"
echo ""

# Démarrer docker-compose
echo "[INFO] Démarrage des containers Docker..."
docker-compose up -d
sleep 10
echo "[OK] Containers démarrés"
echo ""

# Générer du trafic pour avoir des statistiques intéressantes
echo "[INFO] Générer du trafic pour les statistiques..."
docker exec backend1 bash -c 'for i in {1..100}; do curl -s http://172.30.0.11 > /dev/null 2>&1; done' &
TRAFFIC_PID=$!
sleep 2
echo ""

# =============================================================================
# Exercice 8.1: Dashboard Statistiques
# =============================================================================
echo ">>> Exercice 8.1: Dashboard Statistiques"
echo ""

echo "[INFO] Le dashboard HAProxy est accessible à:"
echo "  URL: http://localhost:8404/stats"
echo "  Authentification: admin / admin"
echo ""

echo "[INFO] Accès au dashboard via curl:"
curl -s -u admin:admin http://localhost:8404/stats | head -50 | tail -20
echo ""

echo "[INFO] Informations disponibles dans le dashboard:"
echo "  [✓] Etat des backends (UP/DOWN/MAINT)"
echo "  [✓] Nombre de connexions actives"
echo "  [✓] Nombre de requêtes traitées"
echo "  [✓] Temps de réponse moyen"
echo "  [✓] Erreurs HTTP (4xx, 5xx)"
echo "  [✓] Taux de trafic (in/out)"
echo "  [✓] Distribution du trafic par serveur"
echo "  [✓] Graphiques en temps réel"
echo ""

echo "[OK] Dashboard statistiques présenté"
echo ""

# =============================================================================
# Exercice 8.2: Stats via socket Unix
# =============================================================================
echo ">>> Exercice 8.2: Stats via socket Unix"
echo ""

echo "[INFO] Afficher les statistiques globales:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -5'
echo ""

echo "[INFO] Statistiques détaillées des backends:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep web_backend'
echo ""

echo "[INFO] État des serveurs en détail:"
docker exec haproxy1 bash -c 'echo "show backends" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null'
echo ""

echo "[INFO] Informations de sessionsactives:"
docker exec haproxy1 bash -c 'echo "show sesscount" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null'
echo ""

echo "[INFO] Connections actuelles:"
docker exec haproxy1 bash -c 'echo "show info" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | head -20'
echo ""

echo "[OK] Stats via socket présentées"
echo ""

# =============================================================================
# Exercice 8.3: Métriques Prometheus
# =============================================================================
echo ">>> Exercice 8.3: Métriques Prometheus"
echo ""

echo "[INFO] HAProxy expose les métriques Prometheus sur le port 8405:"
echo "  URL: http://localhost:8405/metrics"
echo ""

echo "[INFO] Accès aux métriques Prometheus:"
curl -s http://localhost:8405/metrics 2>/dev/null | head -30
echo ""

echo "[INFO] Métriques clés disponibles:"
echo ""
echo "  Métriques de Backend:"
docker exec haproxy1 bash -c 'curl -s http://localhost:8405/metrics 2>/dev/null | grep -E "^haproxy_backend" | head -10'
echo ""

echo "  Métriques de Serveur:"
docker exec haproxy1 bash -c 'curl -s http://localhost:8405/metrics 2>/dev/null | grep -E "^haproxy_server" | head -10'
echo ""

echo "  Métriques de Frontend:"
docker exec haproxy1 bash -c 'curl -s http://localhost:8405/metrics 2>/dev/null | grep -E "^haproxy_frontend" | head -10'
echo ""

echo "[INFO] Descriptions des métriques principales:"
echo "  - haproxy_backend_current_sessions: Nombre de sessions actives"
echo "  - haproxy_backend_http_responses_total: Total de réponses HTTP"
echo "  - haproxy_server_status: État du serveur (1=UP, 0=DOWN)"
echo "  - haproxy_backend_bytes_in_total: Octets reçus"
echo "  - haproxy_backend_bytes_out_total: Octets envoyés"
echo "  - haproxy_backend_http_response_time_average: Temps moyen de réponse"
echo ""

echo "[OK] Métriques Prometheus présentées"
echo ""

# =============================================================================
# Exercice 8.4: Analyse des logs
# =============================================================================
echo ">>> Exercice 8.4: Analyse des logs"
echo ""

echo "[INFO] Afficher les logs HAProxy du container (dernières 30 lignes):"
docker logs haproxy1 2>&1 | tail -30
echo ""

echo "[INFO] Compter les requêtes par code HTTP:"
echo "  Métriques de réponses HTTP:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "^web_backend" | awk -F, "{print \$9, \$10, \$11}"' | head -5
echo ""

echo "[INFO] Voir les sessions actives:"
docker exec haproxy1 bash -c 'echo "show tables" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null'
echo ""

echo "[INFO] Analyser la distribution du trafic:"
echo "  Nombre de requêtes par backend:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep backend | awk -F, "{print \$2, \":\", \$8}"'
echo ""

echo "[OK] Analyse des logs présentée"
echo ""

# =============================================================================
# Exercice 8.5: Monitoring en temps réel
# =============================================================================
echo ">>> Exercice 8.5: Monitoring en temps réel"
echo ""

echo "[INFO] État actuel du cluster:"
docker exec haproxy1 bash -c '/scripts/haproxy-status.sh stats'
echo ""

echo "[INFO] État actuel des backends:"
docker exec haproxy1 bash -c '/scripts/backend-status.sh' | head -30
echo ""

echo "[INFO] Métriques de performance (avant le trafic):"
echo "  Attendez la fin du trafic de test..."
wait $TRAFFIC_PID 2>/dev/null || true
echo "  [OK] Trafic généré"
echo ""

echo "[INFO] Statistiques après le trafic:"
docker exec haproxy1 bash -c 'echo "show info" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "Process|PID|Uptime|Connections|Requests|Errors"'
echo ""

echo "[OK] Monitoring en temps réel complété"
echo ""

# =============================================================================
# Exercice 8.6: Analyse de performance
# =============================================================================
echo ">>> Exercice 8.6: Analyse de performance"
echo ""

echo "[INFO] KPIs (Key Performance Indicators):"
echo ""

echo "  [1] Disponibilité:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "web_backend.*backend" | awk -F, "{print \$2, \":\", \$5}"'
echo ""

echo "  [2] Taux de requêtes:"
docker exec haproxy1 bash -c 'echo "show info" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -i "requests"'
echo ""

echo "  [3] Erreurs:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "web_backend" | head -1 | awk -F, "{print \"4xx:\", \$12, \"5xx:\", \$13}"'
echo ""

echo "  [4] Distribution du trafic par serveur:"
docker exec haproxy1 bash -c 'echo "show stat" | socat stdio /var/run/haproxy/admin.sock 2>/dev/null | grep -E "backend[0-9]" | awk -F, "{total+=\$8} END {for (i=1; i<=3; i++) print \"backend\" i}"'
echo ""

echo "[INFO] Alertes recommandées:"
echo "  - Backend DOWN: Déclencher une alerte critique"
echo "  - Taux d'erreur 5xx > 1%: Déclencher une alerte"
echo "  - Temps de réponse moyen > 1s: Déclencher une alerte warning"
echo "  - Utilisation des connexions > 80%: Déclencher une alerte warning"
echo "  - Perte de VIP: Déclencher une alerte critique"
echo ""

echo "[OK] Analyse de performance complétée"
echo ""

# =============================================================================
# Exercice 8.7: Dashboarding
# =============================================================================
echo ">>> Exercice 8.7: Options de dashboarding"
echo ""

echo "[INFO] Options de monitoring recommandées:"
echo ""
echo "  [1] Dashboard HAProxy natif:"
echo "      URL: http://localhost:8404/stats"
echo "      Avantages: Simple, intégré, pas de dépendances"
echo "      Inconvénients: Basique, pas d'historique"
echo ""
echo "  [2] Prometheus + Grafana:"
echo "      - Prometheus: http://localhost:9090"
echo "      - Grafana: http://localhost:3000"
echo "      - Scrape interval: 15 secondes"
echo "      Avantages: Puissant, alertes, historique"
echo ""
echo "  [3] ELK Stack (Elasticsearch + Logstash + Kibana):"
echo "      - Kibana: http://localhost:5601"
echo "      - Recherche full-text dans les logs"
echo "      Avantages: Analyse avancée, recherche"
echo ""
echo "  [4] Datadog / New Relic / Splunk:"
echo "      - SaaS monitoring"
echo "      Avantages: Gestion automatique, support 24/7"
echo ""

echo "[OK] Options de dashboarding présentées"
echo ""

# =============================================================================
# Résumé final
# =============================================================================
echo "============================================"
echo "  TP8 COMPLETE AVEC SUCCES!"
echo "============================================"
echo ""
echo "Résumé des configurations:"
echo "  [✓] Exercice 8.1: Dashboard statistiques HAProxy"
echo "  [✓] Exercice 8.2: Stats via socket Unix"
echo "  [✓] Exercice 8.3: Métriques Prometheus"
echo "  [✓] Exercice 8.4: Analyse des logs"
echo "  [✓] Exercice 8.5: Monitoring en temps réel"
echo "  [✓] Exercice 8.6: Analyse de performance"
echo "  [✓] Exercice 8.7: Options de dashboarding"
echo ""
echo "Points clés appris:"
echo "  - Dashboard HAProxy sur port 8404"
echo "  - Stats via socket Unix (/var/run/haproxy/admin.sock)"
echo "  - Métriques Prometheus sur port 8405"
echo "  - Analyse des logs et statistiques"
echo "  - KPIs et alertes"
echo "  - Options de monitoring (native, Prometheus, ELK, SaaS)"
echo ""
echo "Ports et URLs utiles:"
echo "  - Dashboard HAProxy: http://localhost:8404/stats"
echo "  - Prometheus metrics: http://localhost:8405/metrics"
echo "  - Authentification: admin / admin"
echo ""
echo "Commandes utiles:"
echo "  docker exec haproxy1 /scripts/haproxy-status.sh all"
echo "  docker exec haproxy1 /scripts/backend-status.sh"
echo "  docker exec haproxy1 echo 'show stat' | socat stdio /var/run/haproxy/admin.sock"
echo "  docker exec haproxy1 curl http://localhost:8405/metrics"
echo "  docker logs haproxy1 -f  # pour suivre les logs"
echo ""
echo "Métriques clés à surveiller:"
echo "  - haproxy_backend_current_sessions"
echo "  - haproxy_backend_http_responses_total"
echo "  - haproxy_server_status"
echo "  - haproxy_backend_bytes_in_total"
echo "  - haproxy_backend_bytes_out_total"
echo ""
echo "Seuils d'alerte recommandés:"
echo "  - Backend DOWN: Critique immédiatement"
echo "  - Taux erreur 5xx > 1%: Alerte"
echo "  - Response time > 1s: Warning"
echo "  - Sessions > 80% max: Warning"
echo "  - VIP non accessible: Critique"
echo ""
