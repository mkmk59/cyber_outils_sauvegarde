#!/usr/bin/env bash
# TP1 - Workshop HAProxy (PCA/PRA) Martial HOCQUETTE / Mark GYURJYAN


echo "=== TP1 : Decouverte de HAProxy ==="
echo

# --- Exercice 1.1 : Verification de l'installation ---

echo "[TP1.1] Version de HAProxy"
docker exec haproxy1 haproxy -v
echo

echo "[TP1.1] Verification de la configuration"
docker exec haproxy1 haproxy -c -f /etc/haproxy/haproxy.cfg
echo

echo "[TP1.1] Statut du service HAProxy"
docker exec haproxy1 /scripts/haproxy-status.sh
echo

# --- Exercice 1.2 : Structure de la configuration ---

echo "[TP1.2] Affichage du fichier de configuration"
docker exec haproxy1 cat /etc/haproxy/haproxy.cfg
echo

# --- Exercice 1.3 : Acces au dashboard ---

echo "[TP1.3] Statistiques HAProxy"
echo "URL : http://localhost:8404/stats (admin / admin)"
curl -u admin:admin http://localhost:8404/stats
echo

# --------------------------------------------------------------------
# REPONSES TP1 
#
# 1. Quelle version de HAProxy est installee ?
# -> HAProxy version 2.4.29-0ubuntu0.22.04.1
#
# 2. Combien de backends sont configures ?
# -> 2 sections 'backend' dans la configuration
# -> 3 serveurs backends (backend1, backend2, backend3)
#
# 3. Quel est le mode de load balancing par defaut ?
# -> roundrobin
# --------------------------------------------------------------------
