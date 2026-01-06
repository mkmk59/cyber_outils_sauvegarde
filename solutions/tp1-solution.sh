#!/bin/bash
# TP1 - Installation et Configuration de Base DRBD

echo "=========================================="
echo "  TP1 - Installation et Configuration DRBD"
echo "=========================================="
echo ""

# ETAPE 1: Démarrer l'environnement
echo "[ETAPE 1] Démarrage de l'environnement..."
cd drbd-workshop
docker-compose up -d
docker-compose ps

echo ""
echo "=========================================="
echo "  [ETAPE 2] Exploration de la configuration DRBD"
echo "=========================================="
echo ""

# ETAPE 2: Explorer la configuration DRBD
docker exec -it drbd-node1 cat /etc/drbd.d/r0.res

echo ""
echo "=========================================="
echo "  [ETAPE 3] Initialisation de DRBD"
echo "=========================================="
echo ""

# ETAPE 3: Initialiser DRBD sur Node 1
echo "--- Configuration du Node 1 (Primary) ---"
docker exec -it drbd-node1 /scripts/drbd-init.sh create-md
docker exec -it drbd-node1 /scripts/drbd-init.sh start
docker exec -it drbd-node1 /scripts/drbd-init.sh primary --force

echo ""
echo "--- Configuration du Node 2 (Secondary) ---"
# ETAPE 3: Initialiser DRBD sur Node 2
docker exec -it drbd-node2 /scripts/drbd-init.sh create-md
docker exec -it drbd-node2 /scripts/drbd-init.sh start

echo ""
echo "=========================================="
echo "  [ETAPE 4] Vérification de l'état du cluster"
echo "=========================================="
echo ""

# ETAPE 4: Vérifier l'état du cluster
docker exec -it drbd-node1 /scripts/drbd-status.sh

echo ""
echo "=========================================="
echo "  [ETAPE 5] Test de la réplication"
echo "=========================================="
echo ""

# ETAPE 5: Tester la réplication
echo "PROBLEME RENCONTRE: Le device /dev/drbd0 n'existe pas dans la simulation"
echo "SOLUTION: Créer un lien symbolique vers le fichier image disque"
echo "NOTE: Le lien disparaît après redémarrage, il faut le recréer si besoin"
echo ""
docker exec -it drbd-node1 bash -c "ln -sf /data/drbd-disk.img /dev/drbd0"

# Formater le device DRBD avec ext4
docker exec -it drbd-node1 mkfs.ext4 /dev/drbd0

# Monter le device DRBD
docker exec -it drbd-node1 bash -c "mkdir -p /mnt/drbd && mount /dev/drbd0 /mnt/drbd"

# Créer des fichiers de test
docker exec -it drbd-node1 bash -c "echo 'Donnees critiques - \$(date)' > /mnt/drbd/test.txt"
docker exec -it drbd-node1 bash -c "dd if=/dev/urandom of=/mnt/drbd/data.bin bs=1M count=10 2>/dev/null"

# Vérifier les fichiers créés
docker exec -it drbd-node1 ls -lah /mnt/drbd/
docker exec -it drbd-node1 cat /mnt/drbd/test.txt

echo ""
echo "=========================================="
echo "  EXERCICE 1.1: Réponses aux Questions"
echo "=========================================="
echo ""

echo "Question 1: Pourquoi le Node 2 ne peut-il pas monter /dev/drbd0 directement?"
echo ""
echo "RÉPONSE:"
echo "Le Node 2 est en mode Secondary. Seul le nœud Primary peut accéder en"
echo "lecture/écriture au device DRBD pour maintenir la cohérence des données et éviter"
echo "la corruption du filesystem. Le Secondary reçoit passivement les réplications."
echo ""

echo "Question 2: Que se passe-t-il si on essaie d'écrire sur le Secondary?"
echo ""
echo "RÉPONSE:"
echo "Le device /dev/drbd0 sur le Secondary est en lecture seule. Toute tentative"
echo "de montage en écriture sera bloquée. DRBD génère une erreur d'I/O pour garantir que"
echo "toutes les écritures passent par le Primary et sont répliquées selon le protocole C."
echo ""

echo "Question 3: Quelle est la différence entre meta-disk internal et meta-disk /dev/sdb1?"
echo ""
echo "RÉPONSE:"
echo "- meta-disk internal: métadonnées sur le même disque que les données, simple mais"
echo "  peut impacter les performances I/O"
echo "- meta-disk /dev/sdb1: métadonnées sur un disque séparé, meilleure performance,"
echo "  recommandé en production (surtout avec SSD)"
echo ""

echo "=========================================="
echo "  EXERCICE 1.2: Configuration Personnalisée"
echo "=========================================="
echo ""

echo "Changement du port de 7788 à 7799..."
# Changer le port de 7788 à 7799
docker exec -it drbd-node1 bash -c "sed -i 's/:7788/:7799/g' /etc/drbd.d/r0.res"
docker exec -it drbd-node2 bash -c "sed -i 's/:7788/:7799/g' /etc/drbd.d/r0.res"

echo "Rate limit de 100M est déjà configuré dans la section disk"
echo ""

echo "Redémarrage de DRBD pour appliquer les modifications..."
# Rate limit de 100M est déjà configuré dans la section disk { resync-rate 100M; }

# Redémarrer DRBD pour appliquer les modifications
docker exec -it drbd-node1 /scripts/drbd-init.sh stop
docker exec -it drbd-node2 /scripts/drbd-init.sh stop
docker exec -it drbd-node1 /scripts/drbd-init.sh start
docker exec -it drbd-node2 /scripts/drbd-init.sh start

echo ""
echo "=========================================="
echo "  TP1 TERMINÉ"
echo "=========================================="
echo ""

