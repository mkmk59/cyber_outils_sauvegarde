#!/bin/bash
# =============================================================================
# TP3 : SÉCURISATION ET CHIFFREMENT CEPH
# =============================================================================
# Objectifs:
#   - Comprendre l'authentification CephX
#   - Configurer le chiffrement en transit (TLS)
#   - Mettre en place le chiffrement au repos
#   - Appliquer les bonnes pratiques de sécurité
# Prérequis: TP1 et TP2 complétés
# =============================================================================

CONTAINER="ceph-demo"

ceph_exec() {
    docker exec $CONTAINER "$@"
}

echo "============================================================================="
echo "          TP3 : SÉCURISATION ET CHIFFREMENT CEPH"
echo "============================================================================="
echo ""

# -----------------------------------------------------------------------------
# PARTIE 1 : Authentification CephX
# -----------------------------------------------------------------------------
echo "═══════════════════════════════════════════════════════════════════════════"
echo "PARTIE 1 : Authentification CephX"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "CephX est le protocole d'authentification natif de Ceph."
echo "Il fonctionne sur un modèle similaire à Kerberos."
echo ""

cat << 'CEPHX_DIAGRAM'
┌─────────────────────────────────────────────────────────────┐
│                  FLUX AUTHENTIFICATION CEPHX                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   Client                    Monitor                  OSD    │
│     │                          │                      │     │
│     │  1. Demande de session   │                      │     │
│     │ ─────────────────────────>                      │     │
│     │                          │                      │     │
│     │  2. Ticket de session    │                      │     │
│     │ <─────────────────────────                      │     │
│     │                          │                      │     │
│     │  3. Requête + Ticket     │                      │     │
│     │ ──────────────────────────────────────────────> │     │
│     │                          │                      │     │
│     │  4. Validation ticket    │                      │     │
│     │                          │ <───────────────────  │     │
│     │                          │                      │     │
│     │  5. Accès autorisé       │                      │     │
│     │ <────────────────────────────────────────────── │     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
CEPHX_DIAGRAM

echo ""
echo ">>> Vérification de l'activation de CephX"
ceph_exec ceph auth list 2>/dev/null | head -30
echo ""

echo ">>> Les différents types d'entités:"
echo "    - client.admin   : Administrateur (tous les droits)"
echo "    - osd.N          : Daemon OSD"
echo "    - mon.           : Daemon Monitor"
echo "    - mgr.           : Daemon Manager"
echo "    - client.rgw.*   : RADOS Gateway"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 1.1 : Gestion des clés
# -----------------------------------------------------------------------------
echo ""
echo "───────────────────────────────────────────────────────────────────────────"
echo "EXERCICE 1.1 : Gestion des clés d'authentification"
echo "───────────────────────────────────────────────────────────────────────────"
echo ""

echo ">>> Création d'un utilisateur avec droits limités"
echo ">>> Commande: ceph auth get-or-create client.pca-reader"
echo "              mon 'allow r'"
echo "              osd 'allow r pool=pca-test'"
echo ""

ceph_exec ceph auth get-or-create client.pca-reader \
    mon 'allow r' \
    osd 'allow r pool=pca-test' 2>/dev/null || echo "(Création simulée)"

echo ""
echo ">>> Vérification des droits"
ceph_exec ceph auth get client.pca-reader 2>/dev/null || \
    echo "[client.pca-reader]
    key = AQD...example...==
    caps mon = \"allow r\"
    caps osd = \"allow r pool=pca-test\""

echo ""
echo ">>> Création d'un utilisateur applicatif (accès complet à un pool)"
ceph_exec ceph auth get-or-create client.app-backup \
    mon 'allow r' \
    osd 'allow rwx pool=backups' 2>/dev/null || echo "(Création simulée)"

echo ""
echo "Bonnes pratiques sécurité:"
echo "  ✓ Principe du moindre privilège"
echo "  ✓ Un utilisateur par application"
echo "  ✓ Rotation régulière des clés"
echo "  ✓ Ne jamais partager client.admin"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE 1.2 : Audit des accès
# -----------------------------------------------------------------------------
echo ""
echo "───────────────────────────────────────────────────────────────────────────"
echo "EXERCICE 1.2 : Audit et rotation des clés"
echo "───────────────────────────────────────────────────────────────────────────"
echo ""

echo ">>> Script d'audit des utilisateurs Ceph"
echo ""

cat << 'AUDIT_SCRIPT'
#!/bin/bash
# Script d'audit des utilisateurs Ceph

echo "=== AUDIT DES UTILISATEURS CEPH ==="
echo "Date: $(date)"
echo ""

echo "--- Utilisateurs admin (à surveiller) ---"
ceph auth list 2>/dev/null | grep -A3 "client.admin"

echo ""
echo "--- Utilisateurs avec droits 'rwx' (potentiellement dangereux) ---"
ceph auth list 2>/dev/null | grep -B1 "rwx"

echo ""
echo "--- Tous les utilisateurs ---"
ceph auth list 2>/dev/null | grep "^\[" | sort

echo ""
echo "Recommandations:"
echo "  - Vérifier que chaque utilisateur est nécessaire"
echo "  - Supprimer les utilisateurs obsolètes: ceph auth del <user>"
echo "  - Documenter le rôle de chaque utilisateur"
AUDIT_SCRIPT

echo ""
echo ">>> Rotation d'une clé (en cas de compromission suspectée)"
echo ">>> Commande: ceph auth caps client.app-backup \\"
echo "              mon 'allow r' osd 'allow rwx pool=backups'"
echo ">>> Cela génère automatiquement une nouvelle clé"
echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 2 : Chiffrement en transit (TLS)
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "PARTIE 2 : Chiffrement en transit (TLS)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Le chiffrement en transit protège contre:"
echo "  - L'interception des données (man-in-the-middle)"
echo "  - L'écoute réseau"
echo "  - La modification des paquets"
echo ""

cat << 'TLS_CONFIG'
Configuration TLS dans ceph.conf:

[global]
# Activer le mode messager v2 (requis pour TLS)
ms_bind_msgr2 = true

# Chiffrement entre clients et cluster
ms_client_mode = secure

# Chiffrement entre daemons du cluster
ms_cluster_mode = secure

# Niveau de sécurité (prefer = TLS si disponible, require = TLS obligatoire)
ms_mon_service_mode = secure
ms_osd_service_mode = secure
ms_mgr_service_mode = secure

# Certificats
ms_mon_keyfile = /etc/ceph/mon.key
ms_mon_certfile = /etc/ceph/mon.crt

TLS_CONFIG

echo ""
echo ">>> Vérification de la configuration actuelle"
ceph_exec ceph config get mon ms_client_mode 2>/dev/null || \
    echo "ms_client_mode = crc (non chiffré - par défaut)"

echo ""
echo ">>> Ports Ceph:"
echo "    - 6789  : Legacy (v1, non chiffré)"
echo "    - 3300  : msgr2 (v2, supporte TLS)"
echo "    - 6800+ : OSD"
echo ""

echo ">>> Script de configuration TLS"
cat << 'TLS_SETUP_SCRIPT'
#!/bin/bash
# Configuration TLS pour Ceph (à adapter selon votre PKI)

# 1. Générer les certificats (exemple avec OpenSSL)
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout /etc/ceph/ceph.key \
    -out /etc/ceph/ceph.crt \
    -subj "/CN=ceph-cluster"

# 2. Copier sur tous les nœuds
for host in mon1 mon2 mon3 osd1 osd2 osd3; do
    scp /etc/ceph/ceph.{key,crt} $host:/etc/ceph/
done

# 3. Configurer Ceph
ceph config set global ms_client_mode secure
ceph config set global ms_cluster_mode secure

# 4. Redémarrer les services progressivement
# (Important: respecter l'ordre pour maintenir le quorum)
TLS_SETUP_SCRIPT

echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 3 : Chiffrement au repos
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "PARTIE 3 : Chiffrement au repos (Encryption at Rest)"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

echo "Deux approches possibles:"
echo ""
echo "1. CHIFFREMENT AU NIVEAU OSD (dm-crypt/LUKS)"
echo "   - Chiffre tout le disque OSD"
echo "   - Transparent pour Ceph"
echo "   - Performance légèrement réduite"
echo ""
echo "2. CHIFFREMENT AU NIVEAU APPLICATION"
echo "   - Le client chiffre avant d'envoyer"
echo "   - Ceph stocke des données chiffrées"
echo "   - Gestion des clés côté client"
echo ""

cat << 'LUKS_SETUP'
┌─────────────────────────────────────────────────────────────┐
│          CONFIGURATION LUKS POUR OSD CEPH                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  # 1. Création d'un OSD chiffré                            │
│  ceph-volume lvm create --data /dev/sdX --dmcrypt          │
│                                                             │
│  # 2. Structure résultante                                  │
│  /dev/sdX                                                   │
│    └── dm-crypt (LUKS)                                     │
│        └── LVM                                              │
│            └── OSD data                                     │
│                                                             │
│  # 3. Gestion des clés                                      │
│  - Clé stockée dans le MON (chiffrée)                      │
│  - Déverrouillage automatique au boot                      │
│  - Possibilité d'utiliser un HSM                           │
│                                                             │
└─────────────────────────────────────────────────────────────┘
LUKS_SETUP

echo ""
echo ">>> Configuration RADOS Gateway avec chiffrement SSE-S3"
echo ""

cat << 'SSE_CONFIG'
# Configuration RGW pour Server-Side Encryption

[client.rgw.rgw0]
rgw crypt s3 kms backend = vault    # Ou "testing" pour démo
rgw crypt vault addr = https://vault.example.com:8200
rgw crypt vault auth = token
rgw crypt vault prefix = /v1/transit

# Utilisation côté client (exemple AWS CLI)
aws s3 cp secret.txt s3://bucket/secret.txt \
    --sse aws:kms \
    --sse-kms-key-id my-key-id

SSE_CONFIG

echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# PARTIE 4 : Hardening et bonnes pratiques
# -----------------------------------------------------------------------------
echo ""
echo "═══════════════════════════════════════════════════════════════════════════"
echo "PARTIE 4 : Hardening et bonnes pratiques sécurité"
echo "═══════════════════════════════════════════════════════════════════════════"
echo ""

cat << 'SECURITY_CHECKLIST'
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CHECKLIST SÉCURITÉ CEPH PS/PCA                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RÉSEAU                                                                     │
│  □ Réseau dédié pour le trafic Ceph (public + cluster)                     │
│  □ Firewall entre zones (clients / cluster / management)                   │
│  □ Pas d'accès direct aux OSD depuis les clients                           │
│  □ TLS activé (ms_client_mode = secure)                                    │
│                                                                             │
│  AUTHENTIFICATION                                                           │
│  □ CephX activé (auth_cluster_required = cephx)                            │
│  □ Clés par application (pas de partage)                                   │
│  □ Rotation des clés planifiée                                             │
│  □ Suppression des utilisateurs obsolètes                                  │
│                                                                             │
│  CHIFFREMENT                                                                │
│  □ Chiffrement au repos (dm-crypt ou applicatif)                          │
│  □ Gestion sécurisée des clés (HSM recommandé)                            │
│  □ Backups des clés de chiffrement                                         │
│                                                                             │
│  MONITORING & AUDIT                                                         │
│  □ Logs centralisés (syslog/ELK)                                          │
│  □ Alertes sur événements sécurité                                         │
│  □ Audit régulier des accès                                                │
│  □ Métriques exportées vers SIEM                                           │
│                                                                             │
│  HAUTE DISPONIBILITÉ                                                        │
│  □ Minimum 3 MON pour le quorum                                            │
│  □ OSD répartis sur racks/zones différents                                 │
│  □ Réplication factor >= 3 pour données critiques                          │
│  □ Tests de reprise réguliers                                              │
│                                                                             │
│  GESTION DES ACCÈS                                                          │
│  □ Dashboard protégé (HTTPS + authentification forte)                      │
│  □ API REST sécurisée                                                      │
│  □ Accès SSH par clé uniquement                                            │
│  □ Sudo avec logging                                                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
SECURITY_CHECKLIST

echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# EXERCICE PRATIQUE : Configuration sécurisée
# -----------------------------------------------------------------------------
echo ""
echo "───────────────────────────────────────────────────────────────────────────"
echo "EXERCICE PRATIQUE : Audit et renforcement"
echo "───────────────────────────────────────────────────────────────────────────"
echo ""

echo ">>> Audit de configuration actuel"
echo ""
echo "1. Vérification de l'authentification:"
ceph_exec ceph config get mon auth_cluster_required 2>/dev/null || echo "   auth_cluster_required = cephx (par défaut)"
ceph_exec ceph config get mon auth_service_required 2>/dev/null || echo "   auth_service_required = cephx (par défaut)"
ceph_exec ceph config get mon auth_client_required 2>/dev/null || echo "   auth_client_required = cephx (par défaut)"

echo ""
echo "2. Vérification du chiffrement réseau:"
ceph_exec ceph config get global ms_client_mode 2>/dev/null || echo "   ms_client_mode = crc (à renforcer: secure)"
ceph_exec ceph config get global ms_cluster_mode 2>/dev/null || echo "   ms_cluster_mode = crc (à renforcer: secure)"

echo ""
echo "3. Paramètres de sécurité recommandés à appliquer:"
cat << 'HARDENING_COMMANDS'
# Activer le chiffrement réseau
ceph config set global ms_client_mode secure
ceph config set global ms_cluster_mode secure

# Désactiver les fonctionnalités non utilisées
ceph config set global rbd_default_features layering,exclusive-lock,object-map,fast-diff,deep-flatten

# Activer les logs d'audit
ceph config set mgr mgr/cephadm/log_to_cluster true
ceph config set global log_to_file true

# Limiter les connexions
ceph config set global ms_max_connections 8192

# Timeout de sécurité
ceph config set global ms_connection_idle_timeout 900
HARDENING_COMMANDS

echo ""
read -p "Appuyez sur Entrée pour continuer..."

# -----------------------------------------------------------------------------
# SYNTHÈSE
# -----------------------------------------------------------------------------
echo ""
echo "============================================================================="
echo "                         FIN DU TP3"
echo "============================================================================="
echo ""
echo "Compétences acquises:"
echo "  ✓ Configuration de l'authentification CephX"
echo "  ✓ Création et gestion des utilisateurs"
echo "  ✓ Mise en place du chiffrement en transit (TLS)"
echo "  ✓ Compréhension du chiffrement au repos"
echo "  ✓ Application d'une checklist de sécurité"
echo ""
echo "Documentation de référence:"
echo "  - https://docs.ceph.com/en/latest/rados/configuration/auth-config-ref/"
echo "  - https://docs.ceph.com/en/latest/rados/configuration/network-config-ref/"
echo ""
echo "Prochaine étape: TP4 - Backup et réplication multi-site"
