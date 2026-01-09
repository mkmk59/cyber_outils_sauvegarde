#!/bin/bash
# =============================================================================
# SOLUTION TP1 - Installation et Configuration de Base
# =============================================================================

echo "=============================================="
echo "  SOLUTION TP1 - Configuration de Base DRBD"
echo "=============================================="
echo ""

# -----------------------------------------------------------------------------
# Exercice 1.1: Questions de Comprehension
# -----------------------------------------------------------------------------

cat << 'EOF'
REPONSES AUX QUESTIONS:

1. Pourquoi le Node 2 ne peut-il pas monter /dev/drbd0 directement?
   -----------------------------------------------------------------
   En mode Primary/Secondary, seul le noeud Primary peut monter le
   filesystem. Le Secondary n'a acces qu'en lecture au niveau bloc
   pour la replication. Monter le filesystem sur les deux noeuds
   simultanement (sans filesystem cluster) causerait une corruption
   des donnees car les deux noeuds ecriraient sans coordination.

2. Que se passe-t-il si on essaie d'ecrire sur le Secondary?
   ---------------------------------------------------------
   DRBD refuse l'operation et retourne une erreur. Le device DRBD
   en mode Secondary est en lecture seule au niveau bloc.
   Les ecritures ne sont acceptees que sur le Primary.

3. Difference entre meta-disk internal et meta-disk /dev/sdb1?
   -----------------------------------------------------------
   - internal: Les metadonnees DRBD sont stockees a la fin du
     meme disque que les donnees. Simple mais reduit legerement
     l'espace disponible.

   - /dev/sdb1: Les metadonnees sont sur un disque separe.
     Avantages:
     - Meilleures performances (pas de contention I/O)
     - Plus facile de recuperer en cas de probleme
     - Recommande en production

EOF

echo ""
echo "=============================================="
echo "  Exercice 1.2: Configuration Personnalisee"
echo "=============================================="
echo ""

# Creer une configuration modifiee
cat << 'EOF'
# Configuration avec port modifie et rate limit
# /etc/drbd.d/r0.res

resource r0 {
    protocol C;

    net {
        # Limiter le debit de synchronisation a 100 MB/s
        # Utile pour ne pas saturer le reseau
        max-buffers 8000;
        sndbuf-size 512k;
        rcvbuf-size 512k;
    }

    disk {
        # Limiter le taux de resynchronisation
        resync-rate 100M;
    }

    on node1 {
        device /dev/drbd0;
        disk /data/drbd-disk.img;
        # Port modifie de 7788 a 7799
        address 172.28.0.11:7799;
        meta-disk internal;
    }

    on node2 {
        device /dev/drbd0;
        disk /data/drbd-disk.img;
        # Port modifie de 7788 a 7799
        address 172.28.0.12:7799;
        meta-disk internal;
    }
}

# Pour appliquer les changements:
# drbdadm adjust r0

# Pour verifier:
# drbdadm dump r0 | grep -E "address|resync-rate"
EOF

echo ""
echo "=============================================="
echo "  Script de verification"
echo "=============================================="
echo ""

cat << 'SCRIPT'
#!/bin/bash
# Script de verification de la configuration

# Verifier le port
echo "Port configure:"
grep "address" /etc/drbd.d/r0.res

# Verifier le rate limit
echo ""
echo "Rate limit:"
grep "resync-rate" /etc/drbd.d/r0.res

# Verifier la connectivite
echo ""
echo "Test de connectivite sur le nouveau port:"
nc -zv 172.28.0.12 7799 2>&1 || echo "Port 7799 non accessible"
SCRIPT

echo ""
echo "=============================================="
echo "  Commandes utiles apres modification"
echo "=============================================="
echo ""

cat << 'EOF'
# 1. Verifier la syntaxe de la configuration
drbdadm dump r0

# 2. Appliquer les changements sans redemarrage
drbdadm adjust r0

# 3. Verifier que les changements sont pris en compte
drbdadm status r0

# 4. Si necessaire, redemarrer la ressource
drbdadm down r0
drbdadm up r0
EOF
