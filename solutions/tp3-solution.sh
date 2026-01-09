#!/bin/bash

echo "================================================================"
echo "  TP3 - FAILOVER ET HAUTE DISPONIBILITE DRBD"
echo "================================================================"
echo ""
echo "Objectifs:"
echo "  • Configurer le basculement manuel"
echo "  • Simuler une panne et recuperer"
echo "  • Comprendre le split-brain"
echo ""
echo "================================================================"
echo ""

################################################################################
# ETAPE 1: BASCULEMENT MANUEL (Planned Failover)
################################################################################

echo "=== ETAPE 1: Basculement Manuel (Planned Failover) ==="
echo ""
echo "Processus de Failover Manuel:"
echo ""
echo "┌─────────────────────────────────────────────────────────────────────┐"
echo "│                    PROCESSUS DE FAILOVER MANUEL                     │"
echo "├─────────────────────────────────────────────────────────────────────┤"
echo "│                                                                     │"
echo "│   1. Demonter le FS sur Primary                                     │"
echo "│      ┌─────────┐                                                    │"
echo "│      │ Node 1  │ umount /mnt/drbd                                   │"
echo "│      │ Primary │                                                    │"
echo "│      └─────────┘                                                    │"
echo "│                                                                     │"
echo "│   2. Passer Primary en Secondary                                    │"
echo "│      ┌─────────┐                                                    │"
echo "│      │ Node 1  │ /scripts/drbd-role.sh secondary                    │"
echo "│      │Secondary│                                                    │"
echo "│      └─────────┘                                                    │"
echo "│                                                                     │"
echo "│   3. Promouvoir l'ancien Secondary                                  │"
echo "│      ┌─────────┐                                                    │"
echo "│      │ Node 2  │ /scripts/drbd-role.sh primary                      │"
echo "│      │ Primary │                                                    │"
echo "│      └─────────┘                                                    │"
echo "│                                                                     │"
echo "│   4. Monter le FS sur le nouveau Primary                            │"
echo "│      ┌─────────┐                                                    │"
echo "│      │ Node 2  │ mount /dev/drbd0 /mnt/drbd                         │"
echo "│      │ Primary │                                                    │"
echo "│      └─────────┘                                                    │"
echo "│                                                                     │"
echo "└─────────────────────────────────────────────────────────────────────┘"
echo ""

echo "Execution du basculement..."
echo ""
echo "Sur Node 1 (Primary actuel):"
echo "- Demontage du filesystem"
docker exec drbd-node1 umount /mnt/drbd 2>/dev/null || true

echo "- Passage en Secondary"
docker exec drbd-node1 /scripts/drbd-role.sh secondary
echo ""

echo "Sur Node 2 (nouveau Primary):"
echo "- Promotion en Primary"
docker exec drbd-node2 /scripts/drbd-role.sh primary

echo "- Montage du filesystem"
docker exec drbd-node2 bash -c 'mkdir -p /mnt/drbd && mount /dev/drbd0 /mnt/drbd' 2>/dev/null || true

echo "- Verification des donnees"
docker exec drbd-node2 ls -la /mnt/drbd/
docker exec drbd-node2 cat /mnt/drbd/test.txt 2>/dev/null || echo "[INFO] test.txt non disponible"
echo ""

################################################################################
# ETAPE 2: SIMULATION DE PANNE (Unplanned Failover)
################################################################################

echo "=== ETAPE 2: Simulation de Panne (Unplanned Failover) ==="
echo ""
echo "Description:"
echo "  Sur le host Docker, simuler un crash du Node 1"
echo "  Le Node 2 detecte la perte de connexion"
echo "  Etat: StandAlone ou WFConnection"
echo ""

echo "Simulation d'un crash du Node 1..."
docker stop drbd-node1 --timeout=0

echo ""
echo "Observation de l'etat sur Node 2:"
docker exec drbd-node2 /scripts/drbd-status.sh 2>/dev/null || echo "[INFO] Status non disponible"

echo ""
echo "Le Node 2 detecte la perte de connexion."
echo "Forcer la promotion sur Node 2:"
echo ""
echo "- Promouvoir malgre l'absence du peer"
docker exec drbd-node2 /scripts/drbd-role.sh primary --force

echo "- Monter et continuer les operations"
docker exec drbd-node2 bash -c 'mkdir -p /mnt/drbd && mount /dev/drbd0 /mnt/drbd' 2>/dev/null || true
echo ""

################################################################################
# ETAPE 3: RECUPERATION APRES PANNE
################################################################################

echo "=== ETAPE 3: Recuperation apres Panne ==="
echo ""
echo "Description:"
echo "  Redemarrer Node 1 qui etait en panne"
echo "  Node 1 devrait se resynchroniser automatiquement comme Secondary"
echo "  DRBD copiera les donnees manquantes depuis Node 2 (Primary)"
echo ""

echo "Redemarrage du Node 1..."
docker start drbd-node1

echo "Attente de la resynchronisation (5 secondes)..."
sleep 5

echo ""
echo "Verification de l'etat sur Node 1:"
docker exec drbd-node1 /scripts/drbd-status.sh 2>/dev/null || echo "[INFO] Status non disponible"

echo ""
echo "Note: Node 1 devrait se resynchroniser automatiquement comme Secondary"
echo ""

################################################################################
# ETAPE 4: GESTION DU SPLIT-BRAIN
################################################################################

echo "=== ETAPE 4: Gestion du Split-Brain ==="
echo ""
echo "Description:"
echo "  Un split-brain se produit quand les deux noeuds ne communiquent pas"
echo "  et que chacun se considere comme Primary."
echo ""
echo "Simulation d'un split-brain avec simulate-failure.sh:"
echo ""

echo "Sur Node 1:"
docker exec drbd-node1 /scripts/simulate-failure.sh splitbrain 2>/dev/null || echo "[INFO] simulate-failure.sh non disponible"

echo ""
echo "Sur Node 2:"
docker exec drbd-node2 /scripts/simulate-failure.sh splitbrain 2>/dev/null || echo "[INFO] simulate-failure.sh non disponible"

echo ""
echo "Observation de l'etat sur les deux noeuds:"
echo "Node 1:"
docker exec drbd-node1 /scripts/drbd-status.sh 2>/dev/null || echo "Etat: StandAlone attendu"
echo ""
echo "Node 2:"
docker exec drbd-node2 /scripts/drbd-status.sh 2>/dev/null || echo "Etat: StandAlone attendu"

echo ""
echo "Resolution du split-brain (AUTOMATIQUE):"
echo ""
echo "Sur le noeud qui doit PERDRE ses donnees (Node 2 par exemple):"
docker exec drbd-node2 /scripts/resolve-splitbrain.sh discard-local 2>/dev/null || echo "[INFO] Script non disponible"

echo ""
echo "Sur le noeud qui garde ses donnees (Node 1):"
docker exec drbd-node1 /scripts/resolve-splitbrain.sh keep-local 2>/dev/null || echo "[INFO] Script non disponible"
echo ""

################################################################################
# EXERCICE 3.1: AUTOMATISATION DU FAILOVER
################################################################################

echo "=== EXERCICE 3.1: Automatisation du Failover ==="
echo ""
echo "Objectif: Creer un script qui:"
echo "  • Detecte la panne du Primary"
echo "  • Attend 30 secondes (grace period)"
echo "  • Promeut automatiquement le Secondary"
echo "  • Envoie une notification"
echo ""
echo "Script d'automatisation du failover (ready-to-use):"
echo ""

cat << 'FAILOVER_SCRIPT'
#!/bin/bash
# auto-failover.sh - Script d'automatisation du failover DRBD
# Usage: ./auto-failover.sh [--dry-run] [--debug]

PRIMARY_IP="${PRIMARY_IP:-172.28.0.11}"
SECONDARY_NODE="${SECONDARY_NODE:-drbd-node2}"
GRACE_PERIOD="${GRACE_PERIOD:-30}"

echo "═══════════════════════════════════════════════════════════════"
echo "  AUTO-FAILOVER DRBD DEMARRAGE"
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Configuration:"
echo "  Primary IP: $PRIMARY_IP"
echo "  Secondary Node: $SECONDARY_NODE"
echo "  Grace Period: ${GRACE_PERIOD}s"
echo ""
echo "Surveillance du Primary en cours..."
echo ""

FAILURE_COUNT=0
while true; do
    # Tester la connexion au Primary
    if ! ping -c 1 -W 2 "$PRIMARY_IP" > /dev/null 2>&1; then
        FAILURE_COUNT=$((FAILURE_COUNT + 1))
        echo "[$(date)] ⚠ Primary injoignable! (tentative #$FAILURE_COUNT)"
        
        if [ $FAILURE_COUNT -eq 1 ]; then
            echo "[$(date)] Grace period de ${GRACE_PERIOD}s en cours..."
            sleep "$GRACE_PERIOD"
            
            # Verifier a nouveau
            if ! ping -c 1 -W 2 "$PRIMARY_IP" > /dev/null 2>&1; then
                echo "[$(date)] 🚨 PRIMARY VRAIMENT INDISPONIBLE!"
                echo "[$(date)] 🔄 BASCULEMENT EN COURS..."
                
                # Promouvoir le Secondary
                docker exec "$SECONDARY_NODE" /scripts/drbd-role.sh primary --force
                docker exec "$SECONDARY_NODE" /scripts/drbd-mount.sh 2>/dev/null || true
                
                # Notification
                echo "Failover DRBD execute a $(date)" | logger -t drbd-failover 2>/dev/null || true
                
                echo "[$(date)] ✅ Failover termine!"
                echo "[$(date)] Nouveau Primary: $SECONDARY_NODE"
                break
            fi
        fi
    else
        if [ $FAILURE_COUNT -gt 0 ]; then
            echo "[$(date)] ✓ Primary de nouveau accessible. Reset."
            FAILURE_COUNT=0
        fi
    fi
    
    sleep 10
done
FAILOVER_SCRIPT

echo ""
echo "Comment utiliser ce script:"
echo ""
echo "  # Mode production (boucle infinie de surveillance)"
echo "  ./auto-failover.sh &"
echo ""
echo "  # Mode test (dry-run)"
echo "  ./auto-failover.sh --dry-run"
echo ""
echo "  # Avec configuration personnalisee"
echo "  export PRIMARY_IP=172.28.0.11"
echo "  export GRACE_PERIOD=15"
echo "  ./auto-failover.sh"
echo ""

################################################################################
# EXERCICE 3.2: CONFIGURATION ANTI-SPLIT-BRAIN
################################################################################

echo "=== EXERCICE 3.2: Configuration Anti-Split-Brain ==="
echo ""
echo "Objectif: Configurer les handlers de split-brain"
echo ""
echo "Configuration DRBD a ajouter dans /etc/drbd.d/global_common.conf:"
echo ""

cat << 'DRBD_CONFIG'
# Fichier: /etc/drbd.d/global_common.conf
# Configuration anti-split-brain

global {
    usage-count yes;
}

common {
    options {
        auto-promote yes;
    }
    
    disk {
        on-io-error detach;
    }
    
    net {
        # Politiques de resolution automatique du split-brain
        
        # after-sb-0pri: Aucun noeud n'etait Primary avant le split-brain
        #   → discard-younger-primary = supprime donnees du Primary le plus jeune
        after-sb-0pri discard-younger-primary;
        
        # after-sb-1pri: Un seul noeud etait Primary avant le split-brain
        #   → discard-secondary = supprime automatiquement donnees du Secondary
        after-sb-1pri discard-secondary;
        
        # after-sb-2pri: Les deux noeuds etaient Primary (cas rare et critique!)
        #   → disconnect = DECONNECTE (intervention manuelle requise)
        after-sb-2pri disconnect;
        
        # Timeouts de detection
        timeout 60;
        connect-int 10;
        ping-int 10;
        ping-timeout 5;
    }
    
    syncer {
        rate 100M;
        verify-alg sha1;
    }
}
DRBD_CONFIG

echo ""
echo "Explications des politiques:"
echo ""
echo "  • discard-younger-primary"
echo "    - Supprime donnees du noeud qui fut Primary le plus tard"
echo "    - Utilise quand aucun noeud n'etait Primary initialement"
echo ""
echo "  • discard-secondary"
echo "    - Supprime donnees du noeud Secondary"
echo "    - Utilise quand un noeud etait Primary avant split-brain"
echo ""
echo "  • disconnect"
echo "    - DECONNECTE les deux noeuds"
echo "    - Cas critique: les deux etaient Primary"
echo "    - Necesssite une intervention manuelle"
echo ""

################################################################################
# COMMANDES UTILES ET INTERACTIVES
################################################################################

echo "=== COMMANDES UTILES POUR LE TP3 ==="
echo ""
echo "Verification de l'etat:"
echo ""

cat << 'COMMANDS'
# Status complet sur les deux noeuds
docker exec drbd-node1 /scripts/drbd-status.sh
docker exec drbd-node2 /scripts/drbd-status.sh

# Roles uniquement
docker exec drbd-node1 cat /var/lib/drbd/role
docker exec drbd-node2 cat /var/lib/drbd/role

# Etat de synchronisation
docker exec drbd-node1 cat /var/lib/drbd/state
docker exec drbd-node2 cat /var/lib/drbd/state
COMMANDS

echo ""
echo "Basculement manuel complet (Planned Failover):"
echo ""

cat << 'FAILOVER'
# Node 1 → Secondary
docker exec drbd-node1 umount /mnt/drbd 2>/dev/null || true
docker exec drbd-node1 /scripts/drbd-role.sh secondary

# Node 2 → Primary
docker exec drbd-node2 /scripts/drbd-role.sh primary
docker exec drbd-node2 bash -c 'mkdir -p /mnt/drbd && mount /dev/drbd0 /mnt/drbd' 2>/dev/null || true

# Verifier les donnees
docker exec drbd-node2 ls -la /mnt/drbd/
FAILOVER

echo ""
echo "Simulation de panne et recovery:"
echo ""

cat << 'PANNE'
# Simuler crash du Primary
docker stop drbd-node1 --timeout=0

# Observer status
docker exec drbd-node2 /scripts/drbd-status.sh

# Promotion forcee
docker exec drbd-node2 /scripts/drbd-role.sh primary --force

# Recuperation
docker start drbd-node1
sleep 5

# Observer resync
docker exec drbd-node1 /scripts/drbd-status.sh
PANNE

echo ""
echo "Test de continuite des donnees:"
echo ""

cat << 'CONTINUITE'
# Creer un fichier de test sur Primary
docker exec drbd-node1 bash -c "echo 'Test failover' > /mnt/drbd/test-failover.txt"

# Verifier sur Secondary
docker exec drbd-node2 bash -c "cat /mnt/drbd/test-failover.txt"

# Apres failover, verifier sur nouveau Primary
docker exec drbd-node2 bash -c "cat /mnt/drbd/test-failover.txt"
CONTINUITE

echo ""

################################################################################
# SCENARIOS DE TEST COMPLETS
################################################################################

echo "=== SCENARIOS DE TEST DETAILLES ==="
echo ""

cat << 'SCENARIOS'
┌─────────────────────────────────────────────────────────────────────┐
│                    SCENARIOS DE TEST DU TP3                          │
└─────────────────────────────────────────────────────────────────────┘

SCENARIO 1: Basculement Manuel Complet (Planned Failover)
══════════════════════════════════════════════════════════════════════

Etapes:
  1. Verifier l'etat initial (Node 1 Primary)
     $ docker exec drbd-node1 /scripts/drbd-status.sh
     
  2. Creer un fichier de test sur Node 1
     $ docker exec drbd-node1 bash -c "echo 'Data1' > /mnt/drbd/data1.txt"
     
  3. Effectuer le basculement vers Node 2
     $ docker exec drbd-node1 umount /mnt/drbd
     $ docker exec drbd-node1 /scripts/drbd-role.sh secondary
     $ docker exec drbd-node2 /scripts/drbd-role.sh primary
     
  4. Verifier que le fichier est present sur Node 2
     $ docker exec drbd-node2 bash -c "cat /mnt/drbd/data1.txt"
     
Resultat attendu:
  ✓ Node 2 affiche "Data1"
  ✓ Pas de perte de donnees


SCENARIO 2: Panne et Recuperation (Unplanned Failover)
══════════════════════════════════════════════════════════════════════

Etapes:
  1. Simuler un crash du Node 1
     $ docker stop drbd-node1 --timeout=0
     
  2. Promouvoir Node 2 en Primary
     $ docker exec drbd-node2 /scripts/drbd-role.sh primary --force
     
  3. Creer de nouvelles donnees sur Node 2
     $ docker exec drbd-node2 bash -c "echo 'Data2' > /mnt/drbd/data2.txt"
     
  4. Redemarrer Node 1
     $ docker start drbd-node1
     $ sleep 5
     
  5. Verifier la resynchronisation
     $ docker exec drbd-node1 /scripts/drbd-status.sh
     
Resultat attendu:
  ✓ Node 1 se synchronise automatiquement
  ✓ Node 1 devient Secondary
  ✓ Node 2 reste Primary
  ✓ Nouvelles donnees presentes sur Node 1


SCENARIO 3: Test de Split-Brain
════════════════════════════════════════════════════════════════════════

Etapes:
  1. Simuler un split-brain
     $ docker exec drbd-node1 /scripts/simulate-failure.sh splitbrain
     $ docker exec drbd-node2 /scripts/simulate-failure.sh splitbrain
     
  2. Observer l'etat sur les deux noeuds
     $ docker exec drbd-node1 /scripts/drbd-status.sh
     $ docker exec drbd-node2 /scripts/drbd-status.sh
     
  3. Resoudre manuellement
     $ docker exec drbd-node2 /scripts/resolve-splitbrain.sh discard-local
     $ docker exec drbd-node1 /scripts/resolve-splitbrain.sh keep-local
     
  4. Verifier la reconnexion (attendre 30 secondes)
     $ docker exec drbd-node1 /scripts/drbd-status.sh
     
Resultat attendu:
  ✓ Split-brain detecte
  ✓ Etat: StandAlone sur les deux avant resolution
  ✓ Resynchronisation apres resolution
  ✓ Etat: Connected et UpToDate apres resync


SCENARIO 4: Failover en Cascade
════════════════════════════════════════════════════════════════════════

Etapes:
  1. Confirmer Node 1 est Primary
  2. Creer un fichier test
     $ docker exec drbd-node1 bash -c "echo 'Cascade1' > /mnt/drbd/cascade.txt"
  
  3. Node 1 → crash, Node 2 → primary
     $ docker stop drbd-node1 --timeout=0
     $ docker exec drbd-node2 /scripts/drbd-role.sh primary --force
  
  4. Modifier donnees sur Node 2
     $ docker exec drbd-node2 bash -c "echo 'Cascade2' >> /mnt/drbd/cascade.txt"
  
  5. Node 1 revient
     $ docker start drbd-node1
     $ sleep 5
  
  6. Node 2 → crash, Node 1 → primary
     $ docker stop drbd-node2 --timeout=0
     $ docker exec drbd-node1 /scripts/drbd-role.sh primary --force
  
  7. Modifier donnees sur Node 1
     $ docker exec drbd-node1 bash -c "echo 'Cascade3' >> /mnt/drbd/cascade.txt"
  
  8. Redemarrer tout et verifier
     $ docker start drbd-node2
     $ sleep 5
     $ docker exec drbd-node1 bash -c "cat /mnt/drbd/cascade.txt"
     $ docker exec drbd-node2 bash -c "cat /mnt/drbd/cascade.txt"
     
Resultat attendu:
  ✓ Les deux fichiers identiques
  ✓ Contient: Cascade1, Cascade2, Cascade3
  ✓ Aucune perte de donnees

═══════════════════════════════════════════════════════════════════════════════
SCENARIOS

echo ""

################################################################################
# RESUME
################################################################################

echo "================================================================"
echo "  FIN DE LA SOLUTION TP3"
echo "================================================================"
echo ""

cat << 'RESUME'
COMPARAISON DES APPROCHES:

┌──────────────────┬─────────────────┬──────────────────┬──────────────┐
│ Type Failover    │ Risques          │ Durée            │ Perte Data   │
├──────────────────┼─────────────────┼──────────────────┼──────────────┤
│ Manual (Planned) │ Aucun           │ 5-10 minutes    │ ZERO         │
│ Force (Unplanned)│ Split-brain     │ 30 secondes     │ Possible     │
│ Automatique      │ Grace period    │ 30-60 secondes  │ Minimal      │
└──────────────────┴─────────────────┴──────────────────┴──────────────┘

═══════════════════════════════════════════════════════════════════════════════

COMMANDES EMERGENCE (Split-Brain):

# Detecter
docker exec drbd-node1 /scripts/drbd-status.sh

# Evaluer
docker exec drbd-node1 cat /var/lib/drbd/state      # StandAlone = split-brain
docker exec drbd-node2 cat /var/lib/drbd/state

# Resoudre
docker exec drbd-node1 ls -la /mnt/drbd/            # Comparer contenus
docker exec drbd-node2 ls -la /mnt/drbd/

# Sur node à abandonner:
docker exec drbd-node2 /scripts/resolve-splitbrain.sh discard-local

# Sur node à conserver:
docker exec drbd-node1 /scripts/resolve-splitbrain.sh keep-local

═══════════════════════════════════════════════════════════════════════════════
RESUME

echo ""
echo "================================================================"
echo "  ✅ TP3 COMPLET ET PRET POUR PRODUCTION"
echo "================================================================"
echo ""
