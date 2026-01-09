# Ceph pour la Cybersécurité
## Module PS/PCA (Plan de Secours / Plan de Continuité d'Activité)

---

## Table des Matières

1. [Introduction à Ceph](#1-introduction-à-ceph)
2. [Architecture et Composants](#2-architecture-et-composants)
3. [Ceph et les Enjeux PS/PCA](#3-ceph-et-les-enjeux-pspca)
4. [TP1 : Découverte et Monitoring](#4-tp1-découverte-et-monitoring)
5. [TP2 : Simulation de Pannes et Récupération](#5-tp2-simulation-de-pannes-et-récupération)
6. [TP3 : Sécurisation et Chiffrement](#6-tp3-sécurisation-et-chiffrement)
7. [TP4 : Backup et Réplication Multi-site](#7-tp4-backup-et-réplication-multi-site)
8. [Annexes et Références](#8-annexes-et-références)

---

## 1. Introduction à Ceph

### 1.1 Qu'est-ce que Ceph ?

Ceph est un système de stockage distribué open source conçu pour offrir une excellente performance, fiabilité et évolutivité. Développé initialement par Sage Weil dans le cadre de sa thèse de doctorat à l'UC Santa Cruz, Ceph est aujourd'hui maintenu par Red Hat (IBM) et une communauté active.

**Caractéristiques clés :**

- **Software-defined** : Fonctionne sur du matériel standard (commodity hardware)
- **Unifié** : Object, Block et File storage dans une seule plateforme
- **Auto-réparant** : Détection et correction automatique des défaillances
- **Scalable** : De quelques TB à plusieurs Exabytes
- **Pas de SPOF** : Architecture sans point de défaillance unique

### 1.2 Les trois interfaces de stockage

```
┌─────────────────────────────────────────────────────────────────┐
│                      APPLICATIONS                                │
├─────────────────┬─────────────────┬─────────────────┬───────────┤
│    RADOSGW      │       RBD       │     CephFS      │  librados │
│   (S3/Swift)    │    (Block)      │    (POSIX)      │  (Native) │
├─────────────────┴─────────────────┴─────────────────┴───────────┤
│                           RADOS                                  │
│            (Reliable Autonomic Distributed Object Store)         │
└─────────────────────────────────────────────────────────────────┘
```

| Interface | Protocole | Cas d'usage |
|-----------|-----------|-------------|
| **RADOS Gateway (RGW)** | S3, Swift | Stockage objet, archives, backups cloud |
| **RBD (RADOS Block Device)** | iSCSI-like | Volumes VM, bases de données |
| **CephFS** | POSIX, NFS, SMB | Partages fichiers, home directories |
| **librados** | API native | Applications hautes performances |

---

## 2. Architecture et Composants

### 2.1 Vue d'ensemble de l'architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENTS                                         │
│     (Applications, VMs, Containers, S3 clients)                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                  │                                           │
│                    ┌─────────────┴─────────────┐                            │
│                    ▼                           ▼                             │
│              ┌───────────┐              ┌───────────┐                       │
│              │    MON    │              │    MGR    │                       │
│              │ (Monitor) │              │ (Manager) │                       │
│              │           │              │           │                       │
│              │ • Quorum  │              │ • Dashboard│                      │
│              │ • Cluster │              │ • Métriques│                      │
│              │   Map     │              │ • Modules │                       │
│              └───────────┘              └───────────┘                       │
│                    │                                                         │
│    ┌───────────────┼───────────────┬───────────────┐                       │
│    ▼               ▼               ▼               ▼                        │
│ ┌──────┐      ┌──────┐       ┌──────┐        ┌──────┐                      │
│ │ OSD  │      │ OSD  │       │ OSD  │        │ OSD  │                      │
│ │  0   │      │  1   │       │  2   │        │  N   │                      │
│ │      │      │      │       │      │        │      │                      │
│ │ [HDD]│      │ [SSD]│       │ [HDD]│        │[NVMe]│                      │
│ └──────┘      └──────┘       └──────┘        └──────┘                      │
│   Rack A        Rack A         Rack B          Rack B                       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Composants détaillés

#### MON (Monitor)
Le cerveau du cluster. Maintient la carte du cluster (cluster map) qui contient :
- **OSD Map** : Liste des OSD et leur état
- **MON Map** : Liste des monitors
- **PG Map** : État des Placement Groups
- **CRUSH Map** : Topologie physique et règles de placement

**Configuration PS/PCA :**
- Minimum 3 monitors (quorum = 2)
- Recommandé 5 monitors pour environnements critiques (quorum = 3)
- Distribués sur différents racks/zones

#### OSD (Object Storage Daemon)
Un daemon par disque physique. Responsable de :
- Stockage des objets
- Réplication vers les autres OSD
- Détection et signalement des pannes
- Scrubbing (vérification d'intégrité)

**Configuration PS/PCA :**
- Minimum 3 OSD par failure domain
- Répartition sur racks/zones différents
- Surveillance de la latence et des erreurs

#### MGR (Manager)
Collecte les métriques et fournit des interfaces :
- Dashboard web
- Prometheus/Grafana integration
- Orchestration (cephadm)
- Modules additionnels

#### MDS (Metadata Server)
Requis uniquement pour CephFS. Gère les métadonnées du système de fichiers.

### 2.3 CRUSH : L'algorithme de placement

CRUSH (Controlled Replication Under Scalable Hashing) détermine où stocker les données sans catalogue central.

```
┌─────────────────────────────────────────────────────────────────┐
│                      CRUSH Hierarchy                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│                          ROOT                                    │
│                            │                                     │
│              ┌─────────────┼─────────────┐                      │
│              ▼             ▼             ▼                       │
│          Datacenter    Datacenter    Datacenter                 │
│           Paris          Lyon        Marseille                  │
│              │             │             │                       │
│         ┌────┴────┐   ┌────┴────┐   ┌────┴────┐                │
│         ▼         ▼   ▼         ▼   ▼         ▼                 │
│       Rack A   Rack B  Rack A   Rack B  Rack A   Rack B        │
│         │         │     │         │     │         │             │
│        Host     Host   Host     Host   Host     Host            │
│         │         │     │         │     │         │             │
│        OSD       OSD   OSD       OSD   OSD       OSD            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

**Règle CRUSH typique pour PS/PCA :**
```
rule replicated_rule {
    id 0
    type replicated
    step take default
    step chooseleaf firstn 0 type rack    # Réplicas sur racks différents
    step emit
}
```

---

## 3. Ceph et les Enjeux PS/PCA

### 3.1 Définitions

| Terme | Définition | Exemple |
|-------|------------|---------|
| **RPO** (Recovery Point Objective) | Quantité maximale de données pouvant être perdue | RPO = 1h → perte max 1h de données |
| **RTO** (Recovery Time Objective) | Temps maximal pour reprendre le service | RTO = 15min → service restauré en 15 min |
| **MTBF** (Mean Time Between Failures) | Temps moyen entre pannes | Indicateur de fiabilité |
| **MTTR** (Mean Time To Repair) | Temps moyen de réparation | Indicateur de maintenabilité |

### 3.2 Comment Ceph adresse les enjeux PS/PCA

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    NIVEAUX DE PROTECTION CEPH                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  NIVEAU 1 : Réplication interne (automatique)                              │
│  ├── Panne disque → Données sur autres OSD                                 │
│  ├── Panne serveur → Données sur autres serveurs (CRUSH)                   │
│  ├── RPO = 0, RTO = 0                                                      │
│  └── Condition : facteur réplication >= 2                                  │
│                                                                             │
│  NIVEAU 2 : Reconstruction automatique                                      │
│  ├── OSD perdu → Reconstruction sur OSD restants                           │
│  ├── Processus automatique et parallélisé                                  │
│  └── Temps dépend de la quantité de données                                │
│                                                                             │
│  NIVEAU 3 : Snapshots                                                       │
│  ├── Protection contre erreurs logiques                                    │
│  ├── Restauration rapide                                                   │
│  └── RPO = intervalle snapshot                                             │
│                                                                             │
│  NIVEAU 4 : Réplication multi-site                                         │
│  ├── Protection contre sinistre datacenter                                 │
│  ├── RBD mirroring, RGW multisite                                         │
│  └── RPO = secondes (sync) à minutes (async)                              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Matrice des scénarios de sinistre

| Scénario | Impact sans Ceph | Impact avec Ceph correctement configuré |
|----------|-----------------|----------------------------------------|
| Panne 1 disque | Perte données ou service | Transparent (RTO=0) |
| Panne 1 serveur | Perte service | Transparent si CRUSH rack-aware |
| Panne 1 rack | Perte service prolongée | Dégradation temporaire |
| Panne datacenter | Sinistre majeur | Failover vers site DR |
| Corruption données | Restauration backup | Auto-repair via scrubbing |
| Erreur humaine (suppression) | Restauration backup | Restauration snapshot |

### 3.4 Configuration recommandée par niveau de criticité

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CONFIGURATIONS PAR CRITICITÉ                             │
├───────────────┬─────────────────────────────────────────────────────────────┤
│               │                                                             │
│  CRITIQUE     │  • 5 MON, 2+ MGR                                           │
│  (Tier 0)     │  • size=3, min_size=2                                      │
│  SLA 99.99%   │  • CRUSH: datacenter-aware                                 │
│               │  • RBD mirroring synchrone                                 │
│               │  • Snapshots toutes les heures                             │
│               │  • Tests DR trimestriels                                   │
│               │                                                             │
├───────────────┼─────────────────────────────────────────────────────────────┤
│               │                                                             │
│  IMPORTANT    │  • 3 MON, 2 MGR                                            │
│  (Tier 1)     │  • size=3, min_size=2                                      │
│  SLA 99.9%    │  • CRUSH: rack-aware                                       │
│               │  • RBD mirroring asynchrone                                │
│               │  • Snapshots quotidiens                                    │
│               │  • Tests DR semestriels                                    │
│               │                                                             │
├───────────────┼─────────────────────────────────────────────────────────────┤
│               │                                                             │
│  STANDARD     │  • 3 MON, 1 MGR                                            │
│  (Tier 2)     │  • size=2, min_size=1                                      │
│  SLA 99%      │  • CRUSH: host-aware                                       │
│               │  • Backup externe hebdomadaire                             │
│               │  • Tests annuels                                           │
│               │                                                             │
└───────────────┴─────────────────────────────────────────────────────────────┘
```

---

## 4. TP1 : Découverte et Monitoring

### 4.1 Prérequis et déploiement

**Environnement requis :**
- Docker installé
- 4 GB RAM minimum
- 10 GB espace disque

**Déploiement du lab :**

```bash
# Cloner le répertoire des TPs
mkdir -p ~/ceph-pca-training && cd ~/ceph-pca-training

# Lancer le conteneur Ceph demo
docker run -d --name ceph-demo \
    --privileged \
    -e MON_IP=127.0.0.1 \
    -e CEPH_DEMO_UID=training \
    -p 8080:8080 \
    quay.io/ceph/demo:latest demo

# Attendre le démarrage (environ 60 secondes)
sleep 60

# Vérifier le cluster
docker exec ceph-demo ceph status
```

### 4.2 Exercice 1 : Exploration de l'état du cluster

```bash
# Accéder au conteneur
docker exec -it ceph-demo bash

# État général
ceph status

# Exemple de sortie:
#   cluster:
#     id:     xxxxx-xxxx-xxxx-xxxx-xxxxxxxx
#     health: HEALTH_OK
#   services:
#     mon: 1 daemons
#     mgr: demo(active)
#     osd: 1 osds: 1 up, 1 in
```

**Points d'analyse :**
- `health` : HEALTH_OK, HEALTH_WARN, ou HEALTH_ERR
- `mon` : Nombre de monitors actifs
- `osd` : Nombre d'OSD up/in vs total

### 4.3 Exercice 2 : Diagnostic de santé détaillé

```bash
# Détails des alertes
ceph health detail

# Format JSON pour intégration monitoring
ceph health --format json-pretty

# Historique des alertes
ceph health --status json | jq '.checks'
```

### 4.4 Exercice 3 : Topologie CRUSH

```bash
# Arbre des OSD
ceph osd tree

# Exemple de sortie:
# ID  CLASS  WEIGHT   TYPE NAME        STATUS  REWEIGHT
# -1         0.09999  root default
# -3         0.09999      host ceph-demo
#  0    hdd  0.09999          osd.0       up   1.00000

# Exporter la CRUSH map
ceph osd getcrushmap -o crushmap.bin
crushtool -d crushmap.bin -o crushmap.txt
cat crushmap.txt
```

### 4.5 Exercice 4 : Métriques de performance

```bash
# Utilisation disque globale
ceph df

# Détail par OSD
ceph osd df

# Performance des OSD
ceph osd perf

# Statistiques I/O par pool
ceph osd pool stats
```

### 4.6 Exercice 5 : Script de monitoring

```bash
#!/bin/bash
# monitor-ceph.sh - Script de surveillance PS/PCA

ALERT_THRESHOLD_CAPACITY=80
LOG_FILE="/var/log/ceph-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

# Vérification santé
HEALTH=$(ceph health 2>/dev/null)
if [[ "$HEALTH" != *"HEALTH_OK"* ]]; then
    log "ALERTE: $HEALTH"
fi

# Vérification capacité
USAGE=$(ceph df --format json | jq '.stats.total_used_raw_ratio * 100' | cut -d. -f1)
if [ "$USAGE" -gt "$ALERT_THRESHOLD_CAPACITY" ]; then
    log "ALERTE CAPACITÉ: ${USAGE}%"
fi

# Vérification OSD down
OSD_DOWN=$(ceph osd tree --format json | jq '.nodes[] | select(.type=="osd" and .status=="down") | .name')
if [ -n "$OSD_DOWN" ]; then
    log "ALERTE OSD DOWN: $OSD_DOWN"
fi

log "Monitoring terminé - Cluster: $HEALTH"
```

---

## 5. TP2 : Simulation de Pannes et Récupération

### 5.1 Préparation

```bash
# Créer un pool de test
ceph osd pool create pca-test 32 32 replicated
ceph osd pool set pca-test size 3
ceph osd pool set pca-test min_size 2

# Écrire des données de test
for i in {1..100}; do
    echo "Donnée critique $i - $(date)" | rados -p pca-test put object-$i -
done

# Vérifier
rados -p pca-test ls | wc -l
ceph df
```

### 5.2 Scénario 1 : Panne d'un OSD

```bash
# État initial
ceph osd tree

# Simuler une panne (marquer OSD out)
ceph osd out 0

# Observer la réaction
watch -n 2 ceph status

# Les données restent accessibles (réplication)
rados -p pca-test get object-1 /tmp/test
cat /tmp/test

# Restaurer
ceph osd in 0
```

**Observations clés :**
- Le cluster passe en HEALTH_WARN
- La reconstruction (backfill) commence automatiquement
- Les applications ne sont pas impactées

### 5.3 Scénario 2 : Test de quorum Monitor

```
┌─────────────────────────────────────────────────────────────────┐
│                    RÈGLE DU QUORUM                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   Nombre MON    Quorum requis    Pannes tolérées               │
│   ─────────────────────────────────────────────                │
│       1              1                0                         │
│       3              2                1                         │
│       5              3                2                         │
│       7              4                3                         │
│                                                                 │
│   Formule: Quorum = (N / 2) + 1                                │
│                                                                 │
│   Impact perte quorum:                                         │
│   • Cluster en lecture seule                                   │
│   • Pas de modification config                                 │
│   • OSD continuent de servir                                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.4 Scénario 3 : Corruption et scrubbing

```bash
# Lancer un scrub manuel sur un PG
ceph pg scrub 1.0

# Vérifier l'état des PG
ceph pg stat

# PG problématiques
ceph pg dump_stuck inactive
ceph pg dump_stuck unclean

# Réparer un PG
ceph pg repair 1.0
```

### 5.5 Procédure de reprise après sinistre

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PROCÉDURE DE REPRISE APRÈS SINISTRE                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  PHASE 1 : ÉVALUATION (15-30 min)                                          │
│  ├── Identifier les composants affectés                                    │
│  ├── ceph status                                                           │
│  ├── ceph osd tree                                                         │
│  └── Évaluer RPO (données potentiellement perdues)                        │
│                                                                             │
│  PHASE 2 : STABILISATION (30-60 min)                                       │
│  ├── Restaurer quorum MON si nécessaire                                    │
│  ├── ceph osd out <osd_perdus>                                            │
│  ├── ceph osd purge <osd_definitifs> --yes-i-really-mean-it               │
│  └── Vérifier health                                                       │
│                                                                             │
│  PHASE 3 : RECONSTRUCTION (variable)                                        │
│  ├── Ajouter nouveaux OSD si nécessaire                                    │
│  ├── Surveiller: ceph -w                                                   │
│  ├── Vérifier intégrité: ceph pg deep-scrub <pgid>                        │
│  └── Restaurer backups si perte données                                    │
│                                                                             │
│  PHASE 4 : VALIDATION (60 min)                                             │
│  ├── Tests lecture/écriture                                                │
│  ├── Vérification applications                                             │
│  └── Documentation incident                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 6. TP3 : Sécurisation et Chiffrement

### 6.1 Authentification CephX

CephX est le protocole d'authentification natif de Ceph, inspiré de Kerberos.

```
┌─────────────────────────────────────────────────────────────────┐
│                  FLUX AUTHENTIFICATION CEPHX                     │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   Client                    Monitor                  OSD         │
│     │                          │                      │          │
│     │  1. Demande de session   │                      │          │
│     │ ─────────────────────────>                      │          │
│     │                          │                      │          │
│     │  2. Ticket de session    │                      │          │
│     │ <─────────────────────────                      │          │
│     │                          │                      │          │
│     │  3. Requête + Ticket     │                      │          │
│     │ ──────────────────────────────────────────────> │          │
│     │                          │                      │          │
│     │  4. Accès autorisé       │                      │          │
│     │ <────────────────────────────────────────────── │          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 6.2 Gestion des utilisateurs

```bash
# Lister les utilisateurs
ceph auth list

# Créer un utilisateur avec droits limités
ceph auth get-or-create client.app-backup \
    mon 'allow r' \
    osd 'allow rwx pool=backups'

# Créer un utilisateur lecture seule
ceph auth get-or-create client.monitoring \
    mon 'allow r' \
    osd 'allow r'

# Exporter les credentials
ceph auth get client.app-backup -o /etc/ceph/ceph.client.app-backup.keyring

# Supprimer un utilisateur
ceph auth del client.obsolete
```

### 6.3 Chiffrement en transit (TLS)

```ini
# /etc/ceph/ceph.conf

[global]
# Activer messenger v2
ms_bind_msgr2 = true

# Chiffrement client-cluster
ms_client_mode = secure

# Chiffrement entre daemons
ms_cluster_mode = secure

# Certificats
ms_mon_cluster_keyfile = /etc/ceph/ceph.key
ms_mon_cluster_certfile = /etc/ceph/ceph.crt
```

### 6.4 Chiffrement au repos

**Option 1 : dm-crypt (niveau OSD)**

```bash
# Créer un OSD chiffré
ceph-volume lvm create --data /dev/sdX --dmcrypt
```

**Option 2 : Chiffrement applicatif (RGW SSE)**

```ini
# Configuration RGW
[client.rgw.rgw0]
rgw_crypt_s3_kms_backend = vault
rgw_crypt_vault_addr = https://vault.example.com:8200
```

### 6.5 Checklist de sécurité PS/PCA

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CHECKLIST SÉCURITÉ CEPH                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RÉSEAU                                                                     │
│  □ Réseau dédié Ceph (public + cluster séparés)                            │
│  □ Firewall entre zones                                                    │
│  □ TLS activé (ms_client_mode = secure)                                    │
│                                                                             │
│  AUTHENTIFICATION                                                           │
│  □ CephX activé                                                            │
│  □ Un utilisateur par application                                          │
│  □ Rotation des clés planifiée                                             │
│  □ client.admin sécurisé                                                   │
│                                                                             │
│  CHIFFREMENT                                                                │
│  □ Chiffrement au repos (dm-crypt ou applicatif)                          │
│  □ Gestion clés sécurisée (HSM)                                           │
│  □ Backup des clés                                                         │
│                                                                             │
│  MONITORING & AUDIT                                                         │
│  □ Logs centralisés                                                        │
│  □ Alertes sécurité                                                        │
│  □ Export SIEM                                                             │
│                                                                             │
│  HAUTE DISPONIBILITÉ                                                        │
│  □ 3+ MON                                                                  │
│  □ CRUSH multi-rack                                                        │
│  □ size >= 3                                                               │
│  □ Tests DR réguliers                                                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. TP4 : Backup et Réplication Multi-site

### 7.1 Snapshots RBD

```bash
# Créer une image RBD
rbd create rbd-pool/volume-prod --size 10G

# Créer un snapshot
rbd snap create rbd-pool/volume-prod@backup-$(date +%Y%m%d)

# Lister les snapshots
rbd snap ls rbd-pool/volume-prod

# Protéger un snapshot
rbd snap protect rbd-pool/volume-prod@backup-20240101

# Restaurer (rollback)
rbd snap rollback rbd-pool/volume-prod@backup-20240101

# Cloner depuis snapshot
rbd clone rbd-pool/volume-prod@backup-20240101 rbd-pool/volume-restored

# Exporter pour backup externe
rbd export rbd-pool/volume-prod@backup-20240101 /backup/volume-prod.raw
```

### 7.2 Automatisation des snapshots

```bash
# Activer le module snapshot scheduling
ceph mgr module enable rbd_support

# Configurer des snapshots automatiques
rbd snap schedule add --pool rbd-pool --image volume-prod 1h      # Horaire
rbd snap schedule add --pool rbd-pool --image volume-prod 1d 02:00 # Quotidien à 2h

# Configurer la rétention
rbd snap schedule retention add --pool rbd-pool --image volume-prod 24 1h  # 24 horaires
rbd snap schedule retention add --pool rbd-pool --image volume-prod 7 1d   # 7 quotidiens

# Vérifier
rbd snap schedule ls --pool rbd-pool
```

### 7.3 RBD Mirroring

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ARCHITECTURE RBD MIRRORING                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│    SITE PRIMAIRE                          SITE SECONDAIRE                  │
│    ┌──────────────────┐                   ┌──────────────────┐             │
│    │   Cluster Ceph   │                   │   Cluster Ceph   │             │
│    │                  │    Réplication    │                  │             │
│    │  ┌────────────┐  │  ─────────────>   │  ┌────────────┐  │             │
│    │  │  rbd-pool  │  │   Asynchrone      │  │  rbd-pool  │  │             │
│    │  └────────────┘  │                   │  └────────────┘  │             │
│    │                  │                   │                  │             │
│    │  rbd-mirror     │                   │  rbd-mirror     │             │
│    │  daemon          │                   │  daemon          │             │
│    └──────────────────┘                   └──────────────────┘             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Configuration :**

```bash
# Site Primaire
rbd mirror pool enable rbd-pool pool
rbd mirror pool peer bootstrap create --site-name site-paris rbd-pool > /tmp/token

# Site Secondaire
rbd mirror pool enable rbd-pool pool
rbd mirror pool peer bootstrap import --site-name site-lyon rbd-pool /tmp/token

# Activer mirroring sur une image
rbd mirror image enable rbd-pool/volume-prod snapshot

# Vérifier le status
rbd mirror pool status rbd-pool
rbd mirror image status rbd-pool/volume-prod
```

### 7.4 Failover / Failback

**Failover (sinistre site primaire) :**

```bash
# Sur le site secondaire
rbd mirror image promote rbd-pool/volume-prod --force

# Vérifier
rbd mirror image status rbd-pool/volume-prod
# state: primary
```

**Failback (retour au site primaire) :**

```bash
# Démote le site de secours
rbd mirror image demote rbd-pool/volume-prod  # Sur Lyon

# Promote le site primaire
rbd mirror image promote rbd-pool/volume-prod  # Sur Paris
```

### 7.5 Plan de backup PS/PCA

```
┌─────────────────────────────────────────────────────────────────────────────┐
│               STRATÉGIE DE SAUVEGARDE 3-2-1-1                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  3 COPIES                                                                   │
│  ├── Réplication Ceph (2-3 copies internes)                                │
│  └── Backup externe                                                        │
│                                                                             │
│  2 SUPPORTS DIFFÉRENTS                                                      │
│  ├── Ceph (SSD/HDD)                                                        │
│  └── Bande / Cloud / NAS                                                   │
│                                                                             │
│  1 COPIE HORS-SITE                                                         │
│  └── Site de secours ou cloud                                              │
│                                                                             │
│  1 COPIE AIR-GAPPED                                                        │
│  └── Déconnectée du réseau (protection ransomware)                        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│               PLANNING DES SAUVEGARDES                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  DONNÉES CRITIQUES (Tier 0)                                                │
│  ├── Snapshots : toutes les heures                                         │
│  ├── Réplication multi-site : synchrone                                    │
│  ├── Export externe : quotidien                                            │
│  └── Test restauration : mensuel                                           │
│                                                                             │
│  DONNÉES IMPORTANTES (Tier 1)                                              │
│  ├── Snapshots : toutes les 4 heures                                       │
│  ├── Réplication multi-site : asynchrone                                   │
│  ├── Export externe : hebdomadaire                                         │
│  └── Test restauration : trimestriel                                       │
│                                                                             │
│  DONNÉES STANDARD (Tier 2)                                                 │
│  ├── Snapshots : quotidiens                                                │
│  ├── Export externe : mensuel                                              │
│  └── Test restauration : annuel                                            │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 8. Annexes et Références

### 8.1 Commandes essentielles

```bash
# Status
ceph status                    # Vue d'ensemble
ceph health detail             # Détails alertes
ceph -w                        # Suivi temps réel

# OSD
ceph osd tree                  # Topologie
ceph osd df                    # Utilisation
ceph osd perf                  # Performance
ceph osd out/in <id>           # Maintenance

# Pools
ceph osd pool ls               # Lister
ceph osd pool create <name> <pg_num>
ceph osd pool set <pool> size <n>

# RBD
rbd ls <pool>                  # Lister images
rbd snap create/ls/rollback    # Snapshots
rbd mirror pool status         # Mirroring

# PG
ceph pg stat                   # Status
ceph pg dump_stuck             # PG bloqués
ceph pg repair <pgid>          # Réparer

# Auth
ceph auth list                 # Utilisateurs
ceph auth get-or-create        # Créer
ceph auth del                  # Supprimer
```

### 8.2 Fichiers de configuration clés

| Fichier | Description |
|---------|-------------|
| `/etc/ceph/ceph.conf` | Configuration principale |
| `/etc/ceph/ceph.client.admin.keyring` | Clé admin |
| `/var/lib/ceph/` | Données des daemons |
| `/var/log/ceph/` | Logs |

### 8.3 Ports réseau

| Port | Service | Protocole |
|------|---------|-----------|
| 3300 | Monitor (msgr2) | TCP |
| 6789 | Monitor (legacy) | TCP |
| 6800-7300 | OSD | TCP |
| 7480 | RADOS Gateway | TCP |
| 8443 | Dashboard | TCP/HTTPS |
| 9283 | Prometheus metrics | TCP |

### 8.4 Ressources

**Documentation officielle :**
- https://docs.ceph.com/

**Outils de monitoring :**
- Prometheus + Grafana (dashboards Ceph)
- ceph-mgr dashboard module

**Communauté :**
- Mailing list : ceph-users@lists.ceph.com
- IRC : #ceph sur OFTC
- GitHub : https://github.com/ceph/ceph

---

## Évaluation

### QCM de validation

1. Quel est le nombre minimum de MON recommandé pour un cluster Ceph en production ?
   - a) 1
   - b) 2
   - c) 3 ✓
   - d) 5

2. Que signifie un RPO de 0 ?
   - a) Pas de sauvegarde
   - b) Aucune perte de données acceptable ✓
   - c) Restauration instantanée
   - d) Temps de reprise nul

3. Quelle commande permet de simuler une panne d'OSD ?
   - a) ceph osd stop
   - b) ceph osd out ✓
   - c) ceph osd down
   - d) ceph osd remove

4. Quel protocole Ceph utilise-t-il pour l'authentification ?
   - a) Kerberos
   - b) LDAP
   - c) CephX ✓
   - d) RADIUS

5. Quel est le rôle de l'algorithme CRUSH ?
   - a) Chiffrement des données
   - b) Placement des données ✓
   - c) Compression
   - d) Déduplication


