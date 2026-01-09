#!/bin/bash
# =============================================================================
# SOLUTION TP3 - Failover et Haute Disponibilite
# =============================================================================

echo "=============================================="
echo "  SOLUTION TP3 - Failover et HA"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Exercice 3.1: Automatisation du Failover
# -----------------------------------------------------------------------------

cat << 'EOF'
EXERCICE 3.1: Script d'Automatisation du Failover

Le script suivant detecte la panne du Primary et promeut
automatiquement le Secondary apres un delai de grace.
EOF

echo ""
echo "Script: auto-failover.sh"
echo "========================"
echo ""

cat << 'SCRIPT'
#!/bin/bash
# =============================================================================
# Script de Failover Automatique DRBD
# =============================================================================
# Surveille le Primary et promeut le Secondary en cas de panne.
# A executer sur le noeud Secondary.
# =============================================================================

# Configuration
PRIMARY_IP="${DRBD_PEER_IP:-172.28.0.11}"
GRACE_PERIOD=30          # Secondes avant failover
CHECK_INTERVAL=5         # Intervalle de verification
CONSECUTIVE_FAILURES=3   # Nombre d'echecs consecutifs requis
NOTIFY_EMAIL="admin@example.com"
NOTIFY_SCRIPT="/scripts/notify.sh"
LOG_FILE="/var/log/drbd-failover.log"

# Variables d'etat
FAILURE_COUNT=0
LAST_STATE="unknown"

# Fonction de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Fonction de notification
notify() {
    MESSAGE="$1"
    SEVERITY="$2"

    log "NOTIFY [$SEVERITY]: $MESSAGE"

    # Notification par script personnalise
    if [ -x "$NOTIFY_SCRIPT" ]; then
        "$NOTIFY_SCRIPT" "$SEVERITY" "$MESSAGE"
    fi

    # Notification par email (si sendmail disponible)
    if command -v sendmail &>/dev/null; then
        echo -e "Subject: DRBD Alert [$SEVERITY]\n\n$MESSAGE" | \
        sendmail "$NOTIFY_EMAIL" 2>/dev/null
    fi

    # Notification syslog
    logger -t drbd-failover -p daemon.$SEVERITY "$MESSAGE"
}

# Verification du Primary
check_primary() {
    # Test 1: Ping
    if ! ping -c 1 -W 2 "$PRIMARY_IP" &>/dev/null; then
        return 1
    fi

    # Test 2: Port DRBD accessible
    if ! nc -z -w 2 "$PRIMARY_IP" 7788 &>/dev/null; then
        return 1
    fi

    # Test 3: Service DRBD repond (optionnel)
    # Necessite un endpoint de health check

    return 0
}

# Execution du failover
do_failover() {
    log "=========================================="
    log "DEBUT DU FAILOVER AUTOMATIQUE"
    log "=========================================="

    # 1. Notification pre-failover
    notify "Failover en cours - Primary ($PRIMARY_IP) injoignable depuis ${GRACE_PERIOD}s" "warning"

    # 2. Deconnecter du peer (pour eviter les conflits)
    log "Deconnexion du peer..."
    /scripts/drbd-init.sh disconnect

    # 3. Promouvoir en Primary
    log "Promotion en Primary..."
    /scripts/drbd-role.sh primary --force

    # 4. Monter le filesystem
    log "Montage du filesystem..."
    mkdir -p /mnt/drbd
    mount /dev/drbd0 /mnt/drbd 2>/dev/null || true

    # 5. Demarrer les services (ex: PostgreSQL)
    log "Demarrage des services..."
    if [ -x /scripts/pg-failover.sh ]; then
        /scripts/pg-failover.sh start
    fi

    # 6. Notification post-failover
    notify "Failover COMPLETE - Ce noeud est maintenant PRIMARY" "critical"

    log "=========================================="
    log "FAILOVER TERMINE"
    log "=========================================="
}

# Boucle principale de surveillance
main() {
    log "Demarrage de la surveillance du Primary: $PRIMARY_IP"
    log "Grace period: ${GRACE_PERIOD}s, Check interval: ${CHECK_INTERVAL}s"

    while true; do
        if check_primary; then
            # Primary OK
            if [ "$LAST_STATE" != "ok" ]; then
                log "Primary OK - Connectivite restauree"
                LAST_STATE="ok"
            fi
            FAILURE_COUNT=0
        else
            # Primary KO
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            log "Primary FAIL (${FAILURE_COUNT}/${CONSECUTIVE_FAILURES})"
            LAST_STATE="fail"

            if [ $FAILURE_COUNT -ge $CONSECUTIVE_FAILURES ]; then
                TOTAL_WAIT=$((FAILURE_COUNT * CHECK_INTERVAL))

                if [ $TOTAL_WAIT -ge $GRACE_PERIOD ]; then
                    log "Grace period expiree - Lancement du failover"
                    do_failover
                    break  # Sortir de la boucle apres failover
                else
                    log "Attente... (${TOTAL_WAIT}s / ${GRACE_PERIOD}s)"
                fi
            fi
        fi

        sleep $CHECK_INTERVAL
    done
}

# Verification des prerequis
if [ "$(cat /var/lib/drbd/role 2>/dev/null)" == "primary" ]; then
    echo "ERREUR: Ce script doit etre execute sur le Secondary"
    exit 1
fi

# Lancement
main
SCRIPT

# -----------------------------------------------------------------------------
# Exercice 3.2: Configuration Anti-Split-Brain
# -----------------------------------------------------------------------------

echo ""
echo ""
echo "=============================================="
echo "  Exercice 3.2: Configuration Anti-Split-Brain"
echo "=============================================="
echo ""

cat << 'EOF'
Configuration complete pour la gestion du split-brain:

# /etc/drbd.d/global_common.conf

global {
    usage-count no;
}

common {
    # Handlers pour les evenements critiques
    handlers {
        # Alerte si Primary demarre avec disque inconsistent
        pri-on-incon-degr "/scripts/handlers/alert-degraded.sh";

        # Alerte si Primary perdu apres split-brain
        pri-lost-after-sb "/scripts/handlers/alert-splitbrain.sh";

        # Gestion des erreurs I/O
        local-io-error "/scripts/handlers/handle-io-error.sh";

        # Fencing du peer (optionnel mais recommande)
        fence-peer "/scripts/handlers/fence-peer.sh";
        unfence-peer "/scripts/handlers/unfence-peer.sh";
    }

    startup {
        # Timeouts de demarrage
        wfc-timeout 120;
        degr-wfc-timeout 60;
        outdated-wfc-timeout 20;

        # Ne pas attendre le peer au demarrage si degrade
        # become-primary-on older;
    }

    options {
        # Action si aucune donnee accessible
        on-no-data-accessible io-error;
    }

    disk {
        # Detacher le disque en cas d'erreur I/O
        on-io-error detach;
    }

    net {
        protocol C;

        # Gestion du split-brain automatique
        # ===================================

        # Cas 0: Les deux etaient Secondary
        # -> Garder celui avec les changements les plus recents
        after-sb-0pri discard-zero-changes;

        # Cas 1: Un seul etait Primary
        # -> Jeter les donnees du Secondary
        after-sb-1pri discard-secondary;

        # Cas 2: Les deux etaient Primary (vrai split-brain)
        # -> Deconnecter et alerter (intervention manuelle requise)
        after-sb-2pri disconnect;

        # Alternative plus agressive pour after-sb-2pri:
        # after-sb-2pri call-pri-lost-after-sb;

        # Verification des donnees (detecte corruption)
        # verify-alg sha1;
        # csums-alg sha1;

        # Connexion persistante
        ping-int 10;
        ping-timeout 5;
        connect-int 10;
    }
}
EOF

echo ""
echo "=============================================="
echo "  Scripts de Handlers"
echo "=============================================="
echo ""

cat << 'HANDLER1'
#!/bin/bash
# /scripts/handlers/alert-splitbrain.sh
# Appele quand un split-brain est detecte

RESOURCE="$1"
MESSAGE="SPLIT-BRAIN DETECTED on resource $RESOURCE!"

# Log
logger -t drbd-splitbrain -p daemon.crit "$MESSAGE"

# Email
echo "$MESSAGE" | mail -s "[CRITICAL] DRBD Split-Brain" admin@example.com

# Slack/Teams webhook (exemple)
# curl -X POST -H 'Content-type: application/json' \
#   --data "{\"text\":\"$MESSAGE\"}" \
#   https://hooks.slack.com/services/XXX/YYY/ZZZ

# PagerDuty (exemple)
# curl -X POST \
#   --data "{\"service_key\":\"XXX\",\"event_type\":\"trigger\",\"description\":\"$MESSAGE\"}" \
#   https://events.pagerduty.com/generic/2010-04-15/create_event.json

exit 0
HANDLER1

echo ""

cat << 'HANDLER2'
#!/bin/bash
# /scripts/handlers/fence-peer.sh
# Fencing du peer pour eviter le split-brain

RESOURCE="$1"
PEER_HOSTNAME="$2"

logger -t drbd-fence -p daemon.warning "Fencing peer $PEER_HOSTNAME for resource $RESOURCE"

# Options de fencing (choisir selon l'infrastructure):

# 1. STONITH via IPMI/iLO/DRAC
# ipmitool -H ${PEER_HOSTNAME}-ipmi -U admin -P password chassis power off

# 2. SSH (si accessible)
# ssh $PEER_HOSTNAME "drbdadm secondary $RESOURCE && drbdadm disconnect $RESOURCE"

# 3. Fence agent (avec Pacemaker)
# stonith_admin --fence $PEER_HOSTNAME

# 4. Cloud provider API (AWS, GCP, Azure)
# aws ec2 stop-instances --instance-ids i-xxxxx

echo "Fencing non implemente - intervention manuelle requise"
exit 1  # Retourner 1 si fencing echoue
HANDLER2

echo ""
echo "=============================================="
echo "  Bonnes Pratiques Anti-Split-Brain"
echo "=============================================="
echo ""

cat << 'EOF'
BONNES PRATIQUES POUR EVITER LE SPLIT-BRAIN:

1. Infrastructure Reseau
   - Utiliser plusieurs chemins reseau (bonding)
   - Reseau dedie pour la replication DRBD
   - Heartbeat/crossover cable direct entre noeuds

2. Fencing (STONITH)
   - Toujours configurer un mecanisme de fencing
   - IPMI/iLO pour serveurs physiques
   - API cloud pour instances virtuelles

3. Quorum
   - Avec 2 noeuds: utiliser un quorum device externe
   - Avec 3+ noeuds: majority quorum
   - Exemples: QDevice de Corosync, arbitrateur externe

4. Monitoring
   - Alertes sur tous les changements d'etat
   - Surveillance de la latence reseau
   - Verification periodique de synchronisation

5. Procedures Documentees
   - Procedure de resolution split-brain
   - Runbook pour chaque scenario de panne
   - Formation des equipes d'astreinte
EOF
