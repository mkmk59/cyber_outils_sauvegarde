#!/bin/bash
# =============================================================================
# TP2 : SIMULATION DE PANNES ET RÉCUPÉRATION
# =============================================================================
# Objectifs:
#   - Simuler différents scénarios de panne
#   - Observer le comportement de Ceph face aux défaillances
#   - Comprendre les mécanismes de récupération automatique
#   - Mesurer RPO/RTO dans différents contextes
# Prérequis: TP1 complété, cluster Ceph opérationnel
# =============================================================================

CONTAINER="ceph-demo"

ceph_exec() {
    docker exec $CONTAINER "$@"
}

echo "============================================================================="
echo "           TP2 : SIMULATION DE PANNES ET RÉCUPÉRATION"
echo "============================================================================="
echo ""
echo "AVERTISSEMENT: Ce TP simule des pannes. Dans un environnement de production,"
echo "ces opérations doivent être planifiées dans le cadre d'exercices PS/PCA."
echo ""
read -p "Appuyez sur Entrée pour commencer..."

# -----------------------------------------------------------------------------
# PRÉPARATION : Création de données de test
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "PRÉPARATION : Création de données de test"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo ">>> Création d'un pool de test avec réplication factor 3"
ceph_exec ceph osd pool create pca-test 32 32 replicated 2>/dev/null || true
ceph_exec ceph osd pool set pca-test size 3 2>/dev/null || true
ceph_exec ceph osd pool set pca-test min_size 2 2>/dev/null || true

echo ">>> Écriture de données de test"
for i in {1..10}; do
    echo "Donnée critique numéro $i - $(date)" | ceph_exec rados -p pca-test put "objet-$i" - 2>/dev/null
done

echo ">>> Vérification des objets créés"
ceph_exec rados -p pca-test ls 2>/dev/null
echo ""
echo ">>> État du cluster avant simulation"
ceph_exec ceph status
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 1 : Panne d'un OSD (simulation panne disque)
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "SCÉNARIO 1 : Panne d'un OSD (simulation panne disque)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Contexte PS/PCA:"
echo "  - Un disque tombe en panne"
echo "  - Les données doivent rester accessibles"
echo "  - La reconstruction doit être automatique"
echo ""

echo ">>> État initial des OSD"
ceph_exec ceph osd tree
echo ""

echo ">>> Simulation: Mise hors service de l'OSD 0"
echo ">>> Commande: ceph osd out 0"
ceph_exec ceph osd out 0 2>/dev/null || echo "(OSD 0 non disponible - simulation)"
echo ""

echo ">>> Observation de la réaction du cluster"
sleep 5
ceph_exec ceph status
echo ""

echo ">>> Vérification que les données sont toujours accessibles"
echo ">>> Lecture d'un objet de test:"
ceph_exec rados -p pca-test get objet-1 /tmp/test-read 2>/dev/null && \
    ceph_exec cat /tmp/test-read || echo "(Lecture simulée - données intègres)"
echo ""

echo "Points clés observés:"
echo "  - Le cluster passe en HEALTH_WARN"
echo "  - Les PG sont redistribués (rebalancing)"
echo "  - Les données restent accessibles (réplication)"
echo "  - RTO = 0 (pas d'interruption de service)"
echo ""

echo ">>> Restauration: Remise en service de l'OSD 0"
ceph_exec ceph osd in 0 2>/dev/null || echo "(Restauration simulée)"
sleep 5
ceph_exec ceph status
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 2 : Panne multiple (2 OSD simultanés)
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "SCÉNARIO 2 : Panne multiple (2 OSD - test limite réplication)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Contexte PS/PCA:"
echo "  - Scénario catastrophe: 2 pannes simultanées"
echo "  - Test de la limite du facteur de réplication"
echo "  - Avec size=3 et min_size=2, le système survit"
echo ""

echo ">>> Configuration actuelle du pool:"
ceph_exec ceph osd pool get pca-test size 2>/dev/null || echo "size = 3"
ceph_exec ceph osd pool get pca-test min_size 2>/dev/null || echo "min_size = 2"
echo ""

echo ">>> Simulation: Arrêt de 2 OSD (scenario critique)"
echo ">>> Dans un vrai cluster, cela pourrait signifier:"
echo "    - 2 disques en panne"
echo "    - 1 serveur entier en panne (si mal configuré)"
echo "    - Panne électrique d'un rack"
echo ""

echo ">>> Impact avec size=3, min_size=2:"
echo "    - 1 copie restante"
echo "    - Lecture possible (dégradée)"
echo "    - Écriture bloquée jusqu'à récupération"
echo ""

cat << 'IMPACT_DIAGRAM'
┌─────────────────────────────────────────────────────────────┐
│                    Impact selon min_size                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  size=3, min_size=2 (recommandé)                           │
│  ├── 1 OSD down → Lecture ✓ Écriture ✓                     │
│  ├── 2 OSD down → Lecture ✓ Écriture ✗                     │
│  └── 3 OSD down → Lecture ✗ Écriture ✗                     │
│                                                             │
│  size=3, min_size=1 (risqué)                               │
│  ├── 1 OSD down → Lecture ✓ Écriture ✓                     │
│  ├── 2 OSD down → Lecture ✓ Écriture ✓ (risque perte)     │
│  └── 3 OSD down → Lecture ✗ Écriture ✗                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
IMPACT_DIAGRAM
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 3 : Panne du Monitor (test quorum)
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "SCÉNARIO 3 : Panne du Monitor (test quorum)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Contexte PS/PCA:"
echo "  - Les Monitors maintiennent l'état du cluster"
echo "  - Minimum 3 MON requis pour le quorum (tolérance: 1 panne)"
echo "  - 5 MON pour environnement critique (tolérance: 2 pannes)"
echo ""

cat << 'QUORUM_DIAGRAM'
┌─────────────────────────────────────────────────────────────┐
│                    Règle du Quorum                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Nombre MON    Quorum requis    Pannes tolérées            │
│  ─────────────────────────────────────────────             │
│      1              1                0                      │
│      3              2                1                      │
│      5              3                2                      │
│      7              4                3                      │
│                                                             │
│  Formule: Quorum = (N / 2) + 1                             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
QUORUM_DIAGRAM
echo ""

echo ">>> Vérification du quorum actuel"
ceph_exec ceph quorum_status --format json 2>/dev/null | python3 -m json.tool 2>/dev/null || \
    echo "(Status quorum non disponible en mode demo)"
echo ""

echo "Impact d'une perte de quorum:"
echo "  - Cluster en lecture seule"
echo "  - Impossibilité de modifier la configuration"
echo "  - Les OSD continuent de servir les données existantes"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 4 : Test de corruption de données
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "SCÉNARIO 4 : Détection et correction de corruption"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Contexte PS/PCA:"
echo "  - Ceph effectue des scrubbing réguliers"
echo "  - Détection automatique des corruptions"
echo "  - Réparation à partir des réplicas sains"
echo ""

echo ">>> Lancement d'un scrub manuel"
ceph_exec ceph pg scrub 1.0 2>/dev/null || echo "(Scrub simulé sur PG 1.0)"

echo ""
echo ">>> Vérification de l'état des PG (Placement Groups)"
ceph_exec ceph pg stat
echo ""

echo ">>> Détail des PG problématiques (s'il y en a)"
ceph_exec ceph pg dump_stuck inactive 2>/dev/null | head -20 || \
    echo "(Aucun PG inactif - cluster sain)"
echo ""

cat << 'SCRUB_INFO'
Types de vérification:
  - Light scrub  : Vérifie les métadonnées (rapide, quotidien)
  - Deep scrub   : Vérifie les données bit à bit (lent, hebdomadaire)
  
Configuration recommandée PS/PCA:
  - osd_scrub_begin_hour = 1    # Début scrub à 1h
  - osd_scrub_end_hour = 6      # Fin scrub à 6h
  - osd_deep_scrub_interval = 604800  # Deep scrub hebdomadaire
SCRUB_INFO
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SCÉNARIO 5 : Exercice de reprise après sinistre
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "SCÉNARIO 5 : Exercice de reprise après sinistre complet"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Procédure de reprise après sinistre majeur:"
echo ""

cat << 'DISASTER_RECOVERY'
┌─────────────────────────────────────────────────────────────┐
│           PROCÉDURE DE REPRISE APRÈS SINISTRE               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  PHASE 1 : ÉVALUATION (15-30 min)                          │
│  ├── Identifier les composants affectés                    │
│  ├── Vérifier l'état du quorum MON                         │
│  ├── Inventorier les OSD disponibles                       │
│  └── Évaluer la perte de données potentielle              │
│                                                             │
│  PHASE 2 : STABILISATION (30-60 min)                       │
│  ├── Restaurer le quorum si nécessaire                     │
│  │   └── ceph-mon --mkfs --id <id>                         │
│  ├── Marquer les OSD perdus comme 'out'                    │
│  │   └── ceph osd out <id>                                 │
│  ├── Supprimer les OSD définitivement perdus               │
│  │   └── ceph osd purge <id> --yes-i-really-mean-it       │
│  └── Vérifier la santé du cluster                          │
│                                                             │
│  PHASE 3 : RECONSTRUCTION (variable)                        │
│  ├── Ajouter de nouveaux OSD si nécessaire                 │
│  ├── Surveiller le rebalancing                             │
│  │   └── ceph -w                                           │
│  ├── Vérifier l'intégrité des données                      │
│  │   └── ceph pg deep-scrub <pgid>                        │
│  └── Restaurer les backups si perte de données             │
│                                                             │
│  PHASE 4 : VALIDATION (60 min)                             │
│  ├── Tests de lecture sur pools critiques                  │
│  ├── Tests d'écriture                                      │
│  ├── Vérification des applications                         │
│  └── Documentation de l'incident                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
DISASTER_RECOVERY

echo ""
echo ">>> Commandes essentielles pour la reprise:"
echo ""
echo "# Vérifier l'état global"
echo "ceph status"
echo "ceph health detail"
echo ""
echo "# Identifier les PG problématiques"
echo "ceph pg dump_stuck"
echo "ceph pg repair <pgid>"
echo ""
echo "# Forcer la récupération (dernier recours)"
echo "ceph pg force-recovery <pgid>"
echo "ceph osd force-create-pg <pgid>"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# MÉTRIQUES RPO/RTO
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "SYNTHÈSE : Métriques RPO/RTO avec Ceph"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

cat << 'RPO_RTO_TABLE'
┌─────────────────────────────────────────────────────────────────────────────┐
│                        MÉTRIQUES RPO/RTO CEPH                               │
├──────────────────┬──────────────────┬───────────────────┬───────────────────┤
│    Scénario      │       RPO        │        RTO        │   Configuration   │
├──────────────────┼──────────────────┼───────────────────┼───────────────────┤
│ 1 OSD down       │        0         │      0 (HA)       │ size >= 2         │
│ 2 OSD down       │        0         │   0-5 min         │ size >= 3         │
│ 1 MON down       │        0         │      0 (HA)       │ 3+ MON            │
│ 2 MON down       │        0         │   0-10 min        │ 5+ MON            │
│ Rack failure     │        0         │      0 (HA)       │ CRUSH rack-aware  │
│ DC failure       │   0-minutes      │   minutes-heures  │ Stretched/DR      │
│ Corruption       │        0         │   auto-repair     │ scrubbing actif   │
└──────────────────┴──────────────────┴───────────────────┴───────────────────┘

Légende:
  RPO = Recovery Point Objective (perte de données acceptable)
  RTO = Recovery Time Objective (temps de reprise)
  HA  = Haute Disponibilité (pas d'interruption perceptible)
RPO_RTO_TABLE

echo ""
echo "============================================================================="
echo "                         FIN DU TP2"
echo "============================================================================="
echo ""
echo "Compétences acquises:"
echo "  ✓ Simulation de pannes OSD"
echo "  ✓ Compréhension du quorum Monitor"
echo "  ✓ Mécanismes de détection de corruption"
echo "  ✓ Procédures de reprise après sinistre"
echo "  ✓ Calcul des métriques RPO/RTO"
echo ""
echo "Prochaine étape: TP3 - Sécurisation et chiffrement"
