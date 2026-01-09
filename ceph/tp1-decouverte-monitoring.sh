#!/bin/bash
# =============================================================================
# TP1 : DÉCOUVERTE ET MONITORING D'UN CLUSTER CEPH
# =============================================================================
# Objectifs:
#   - Comprendre l'architecture Ceph
#   - Maîtriser les commandes de diagnostic
#   - Interpréter les indicateurs de santé
# Prérequis: Cluster Ceph déployé (./deploy-ceph-demo.sh)
# =============================================================================

# Configuration
CONTAINER="ceph-demo"

# Fonction d'exécution dans le conteneur
ceph_exec() {
    docker exec $CONTAINER "$@"
}

echo "============================================================================="
echo "                    TP1 : DÉCOUVERTE DU CLUSTER CEPH"
echo "============================================================================="
echo ""

# -----------------------------------------------------------------------------
# EXERCICE 1 : État général du cluster
# -----------------------------------------------------------------------------
echo "═══════════════════════════════════════════════════════════════════════════"
echo "EXERCICE 1 : État général du cluster"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Commande: ceph status"
echo ">>> Cette commande affiche un résumé complet de l'état du cluster"
echo ""
ceph_exec ceph status
echo ""

echo "Analyse des sections:"
echo "  - cluster: Identifiant unique (FSID) et état de santé"
echo "  - services: MON, MGR, OSD, MDS actifs"
echo "  - data: Pools, objets, utilisation"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 2 : Détails de santé
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "EXERCICE 2 : Diagnostic de santé détaillé"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Commande: ceph health detail"
echo ">>> Affiche les alertes et warnings avec explications"
echo ""
ceph_exec ceph health detail
echo ""

echo ">>> Commande: ceph health --format json | python3 -m json.tool"
echo ">>> Format JSON pour intégration monitoring (Prometheus, Zabbix...)"
echo ""
ceph_exec ceph health --format json 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(Format JSON non disponible)"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 3 : Arbre des OSD
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "EXERCICE 3 : Topologie des OSD (CRUSH Map)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Commande: ceph osd tree"
echo ">>> Montre la hiérarchie physique: datacenter > rack > host > osd"
echo ""
ceph_exec ceph osd tree
echo ""

echo "Points clés pour PS/PCA:"
echo "  - Chaque OSD doit être 'up' ET 'in'"
echo "  - La répartition des OSD sur différents racks assure la résilience"
echo "  - Un OSD 'down' déclenche la reconstruction automatique"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 4 : Utilisation du stockage
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "EXERCICE 4 : Utilisation du stockage"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Commande: ceph df"
echo ">>> Vue globale de la capacité et utilisation"
echo ""
ceph_exec ceph df
echo ""

echo ">>> Commande: ceph osd df"
echo ">>> Détail par OSD - important pour détecter les déséquilibres"
echo ""
ceph_exec ceph osd df
echo ""

echo "Indicateurs critiques PS/PCA:"
echo "  - %USE > 80% : Alerte capacité"
echo "  - %USE > 95% : Critique - risque de perte de données"
echo "  - VAR importante : Déséquilibre à corriger"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 5 : Pools de stockage
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "EXERCICE 5 : Configuration des pools"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Commande: ceph osd pool ls detail"
echo ">>> Liste les pools avec leur configuration de réplication"
echo ""
ceph_exec ceph osd pool ls detail
echo ""

echo ">>> Commande: ceph osd pool get <pool> all"
echo ">>> Affiche tous les paramètres d'un pool spécifique"
echo ""
POOL=$(ceph_exec ceph osd pool ls 2>/dev/null | head -1)
if [ -n "$POOL" ]; then
    echo "Pool sélectionné: $POOL"
    ceph_exec ceph osd pool get $POOL all 2>/dev/null || echo "(Paramètres non disponibles)"
fi
echo ""

echo "Paramètres critiques:"
echo "  - size: Facteur de réplication (3 recommandé)"
echo "  - min_size: Minimum pour écriture (2 pour haute dispo)"
echo "  - pg_num: Nombre de Placement Groups"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 6 : Monitoring des performances
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "EXERCICE 6 : Métriques de performance"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Commande: ceph osd perf"
echo ">>> Latence des OSD - critique pour détecter les disques défaillants"
echo ""
ceph_exec ceph osd perf 2>/dev/null || echo "(Métriques non disponibles)"
echo ""

echo ">>> Commande: ceph osd pool stats"
echo ">>> Statistiques I/O par pool"
echo ""
ceph_exec ceph osd pool stats 2>/dev/null || echo "(Statistiques non disponibles)"
echo ""

echo "Seuils d'alerte typiques:"
echo "  - Latence commit > 10ms : Dégradation"
echo "  - Latence apply > 20ms : Problème disque probable"
echo ""

# -----------------------------------------------------------------------------
# EXERCICE BONUS : Script de monitoring
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "BONUS : Script de monitoring automatisé"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

cat << 'MONITORING_SCRIPT'
#!/bin/bash
# Script de monitoring Ceph pour PS/PCA
# À exécuter périodiquement via cron

THRESHOLD_CAPACITY=80
THRESHOLD_DEGRADED=0

# Vérification santé
HEALTH=$(ceph health 2>/dev/null)
if [[ "$HEALTH" != *"HEALTH_OK"* ]]; then
    echo "ALERTE: Cluster non healthy - $HEALTH"
    # Ici: envoyer notification (email, SMS, PagerDuty...)
fi

# Vérification capacité
USAGE=$(ceph df --format json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(int(data['stats']['total_used_bytes'] / data['stats']['total_bytes'] * 100))
" 2>/dev/null)

if [ -n "$USAGE" ] && [ "$USAGE" -gt "$THRESHOLD_CAPACITY" ]; then
    echo "ALERTE: Capacité à ${USAGE}% - seuil ${THRESHOLD_CAPACITY}%"
fi

# Vérification OSD down
OSD_DOWN=$(ceph osd tree --format json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
down = [n['name'] for n in data['nodes'] if n['type'] == 'osd' and n['status'] == 'down']
print(' '.join(down) if down else '')
" 2>/dev/null)

if [ -n "$OSD_DOWN" ]; then
    echo "ALERTE: OSD down - $OSD_DOWN"
fi

echo "Monitoring terminé à $(date)"
MONITORING_SCRIPT

echo ""
echo "============================================================================="
echo "                         FIN DU TP1"
echo "============================================================================="
echo ""
echo "Compétences acquises:"
echo "  ✓ Navigation dans l'interface CLI Ceph"
echo "  ✓ Interprétation des indicateurs de santé"
echo "  ✓ Compréhension de la topologie CRUSH"
echo "  ✓ Analyse des métriques de performance"
echo ""
echo "Prochaine étape: TP2 - Simulation de pannes et récupération"
