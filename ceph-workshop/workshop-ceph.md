# Workshop Ceph - Stockage Distribue et Haute Disponibilite

```
    ┌─────────────────────────────────────────────────────────────────────────┐
    │                      ARCHITECTURE CEPH                                   │
    │                                                                          │
    │   ┌─────────────────────────────────────────────────────────────────┐   │
    │   │                        CEPH CLUSTER                              │   │
    │   │                                                                  │   │
    │   │   ┌─────────┐    ┌─────────┐    ┌─────────┐                     │   │
    │   │   │  MON 1  │    │  MON 2  │    │  MON 3  │   <- Monitors       │   │
    │   │   │ (Leader)│    │(Standby)│    │(Standby)│      (Quorum)       │   │
    │   │   └────┬────┘    └────┬────┘    └────┬────┘                     │   │
    │   │        │              │              │                          │   │
    │   │        └──────────────┼──────────────┘                          │   │
    │   │                       │                                         │   │
    │   │   ┌─────────┐    ┌─────────┐    ┌─────────┐                     │   │
    │   │   │  OSD 1  │    │  OSD 2  │    │  OSD 3  │   <- Object Store   │   │
    │   │   │ (Disk1) │    │ (Disk2) │    │ (Disk3) │      Daemons        │   │
    │   │   └─────────┘    └─────────┘    └─────────┘                     │   │
    │   │                                                                  │   │
    │   │   ┌─────────┐                   ┌─────────┐                     │   │
    │   │   │   MDS   │                   │   RGW   │   <- Metadata &     │   │
    │   │   │(CephFS) │                   │ (S3/API)│      Gateway        │   │
    │   │   └─────────┘                   └─────────┘                     │   │
    │   │                                                                  │   │
    │   └─────────────────────────────────────────────────────────────────┘   │
    │                                                                          │
    │   Clients: RBD (Block) | CephFS (File) | RGW (Object S3)                │
    │                                                                          │
    └─────────────────────────────────────────────────────────────────────────┘
```

---

## Contexte PS/PCA - Cybersecurite

Ce workshop s'inscrit dans le cadre du module **Plan de Secours / Plan de Continuite d'Activite** du Master Cybersecurite. Ceph est une solution de stockage distribue essentielle pour:

- **Resilience des donnees**: Replication automatique sur plusieurs noeuds
- **Continuite de service**: Pas de SPOF (Single Point of Failure)
- **Recovery**: Reconstruction automatique apres panne
- **Scalabilite**: Extension sans interruption de service

---

## Table des Matieres

1. [Introduction a Ceph](#1-introduction-a-ceph)
2. [Concepts Fondamentaux](#2-concepts-fondamentaux)
3. [Environnement de Lab Docker](#3-environnement-de-lab-docker)
4. [TP1 - Deploiement du Cluster Ceph](#4-tp1---deploiement-du-cluster-ceph)
5. [TP2 - Stockage Bloc (RBD)](#5-tp2---stockage-bloc-rbd)
6. [TP3 - Systeme de Fichiers (CephFS)](#6-tp3---systeme-de-fichiers-cephfs)
7. [TP4 - Stockage Objet (RGW/S3)](#7-tp4---stockage-objet-rgws3)
8. [TP5 - Haute Disponibilite et Failover](#8-tp5---haute-disponibilite-et-failover)
9. [TP6 - Monitoring et Troubleshooting](#9-tp6---monitoring-et-troubleshooting)
10. [TP7 - Scenarios PCA/PRA](#10-tp7---scenarios-pcapra)
11. [Annexes](#11-annexes)

---

## 1. Introduction a Ceph

### Qu'est-ce que Ceph?

**Ceph** est une plateforme de stockage distribue open-source qui fournit:
- **Stockage Objet** (compatible S3/Swift)
- **Stockage Bloc** (RBD - RADOS Block Device)
- **Systeme de Fichiers** (CephFS)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         CEPH UNIFIED STORAGE                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌───────────────┐    ┌───────────────┐    ┌───────────────┐               │
│   │   BLOCK (RBD) │    │  FILE (CephFS)│    │ OBJECT (RGW)  │               │
│   │               │    │               │    │               │               │
│   │  VM Disks     │    │  NFS/POSIX    │    │  S3/Swift     │               │
│   │  Databases    │    │  Shared Files │    │  Backups      │               │
│   │  Containers   │    │  Home Dirs    │    │  Media        │               │
│   └───────┬───────┘    └───────┬───────┘    └───────┬───────┘               │
│           │                    │                    │                        │
│           └────────────────────┼────────────────────┘                        │
│                                │                                             │
│                    ┌───────────┴───────────┐                                 │
│                    │        LIBRADOS       │                                 │
│                    │   (Native API)        │                                 │
│                    └───────────┬───────────┘                                 │
│                                │                                             │
│                    ┌───────────┴───────────┐                                 │
│                    │         RADOS         │                                 │
│                    │  (Reliable Autonomic  │                                 │
│                    │   Distributed Object  │                                 │
│                    │        Store)         │                                 │
│                    └───────────────────────┘                                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Avantages pour PS/PCA

| Caracteristique | Benefice PS/PCA |
|-----------------|-----------------|
| **Pas de SPOF** | Continuite garantie meme avec pannes multiples |
| **Auto-healing** | Reconstruction automatique des donnees |
| **Scalabilite horizontale** | Extension sans interruption |
| **Replication configurable** | RPO = 0 possible |
| **Snapshots** | Points de restauration instantanes |
| **Geo-replication** | DR multi-site |

### Cas d'Usage en Entreprise

1. **Infrastructure Cloud Privee**
   - Backend pour OpenStack (Cinder, Glance, Nova)
   - Stockage pour Kubernetes (CSI driver)

2. **Backup et Archivage**
   - Compatible S3 pour outils de backup
   - Tiering automatique (chaud/froid)

3. **Big Data et Analytics**
   - Stockage massif haute performance
   - Integration Hadoop/Spark

4. **Virtualisation**
   - Disques VM hautement disponibles
   - Migration a chaud

---

## 2. Concepts Fondamentaux

### 2.1 Composants du Cluster

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      COMPOSANTS CEPH                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  MONITORS (MON)                                                      │    │
│  │  ──────────────                                                      │    │
│  │  - Maintiennent la carte du cluster (cluster map)                   │    │
│  │  - Gerent l'authentification (cephx)                                │    │
│  │  - Consensus Paxos pour la coherence                                │    │
│  │  - Minimum 3 pour le quorum (tolere 1 panne)                        │    │
│  │  - Minimum 5 pour tolerer 2 pannes                                  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  OBJECT STORAGE DAEMONS (OSD)                                        │    │
│  │  ────────────────────────────                                        │    │
│  │  - Stockent les donnees (objets)                                    │    │
│  │  - Gerent la replication                                            │    │
│  │  - Effectuent le recovery                                           │    │
│  │  - Un OSD par disque physique                                       │    │
│  │  - Communiquent entre eux pour la coherence                         │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  METADATA SERVER (MDS)                                               │    │
│  │  ─────────────────────                                               │    │
│  │  - Requis uniquement pour CephFS                                    │    │
│  │  - Gere les metadonnees du filesystem                               │    │
│  │  - Cache les metadonnees en memoire                                 │    │
│  │  - Active/Standby pour la HA                                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  RADOS GATEWAY (RGW)                                                 │    │
│  │  ───────────────────                                                 │    │
│  │  - Interface S3/Swift compatible                                    │    │
│  │  - Stockage objet via HTTP/HTTPS                                    │    │
│  │  - Multi-tenancy                                                    │    │
│  │  - Peut etre load-balance                                           │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │  MANAGER (MGR)                                                       │    │
│  │  ─────────────                                                       │    │
│  │  - Collecte les metriques du cluster                                │    │
│  │  - Dashboard web integre                                            │    │
│  │  - Modules: Prometheus, Grafana, etc.                               │    │
│  │  - Active/Standby                                                   │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Algorithme CRUSH

CRUSH (Controlled Replication Under Scalable Hashing) est l'algorithme de placement des donnees:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ALGORITHME CRUSH                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   Client veut ecrire "fichier.txt"                                          │
│                                                                              │
│   1. Hash(fichier.txt) → Object ID                                          │
│   2. Object ID % num_pg → Placement Group (PG)                              │
│   3. CRUSH(PG) → [OSD.1, OSD.5, OSD.9]  (3 replicas)                        │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    CRUSH MAP (Hierarchie)                            │   │
│   │                                                                      │   │
│   │                         ┌────────┐                                   │   │
│   │                         │  Root  │                                   │   │
│   │                         └────┬───┘                                   │   │
│   │                    ┌─────────┼─────────┐                             │   │
│   │               ┌────┴────┐         ┌────┴────┐                        │   │
│   │               │  DC 1   │         │  DC 2   │   <- Datacenters       │   │
│   │               └────┬────┘         └────┬────┘                        │   │
│   │            ┌───────┼───────┐           │                             │   │
│   │       ┌────┴───┐ ┌─┴──┐ ┌──┴───┐  ┌───┴───┐                          │   │
│   │       │ Rack 1 │ │Rack2│ │Rack 3│  │ Rack 4│   <- Racks              │   │
│   │       └───┬────┘ └──┬─┘ └──┬───┘  └───┬───┘                          │   │
│   │           │         │      │          │                              │   │
│   │       ┌───┴───┐ ┌───┴──┐ ┌─┴──┐   ┌───┴───┐                          │   │
│   │       │Host 1 │ │Host 2│ │Host3│   │Host 4 │   <- Serveurs           │   │
│   │       └───┬───┘ └───┬──┘ └──┬─┘   └───┬───┘                          │   │
│   │           │         │       │         │                              │   │
│   │       ┌───┴───┐ ┌───┴──┐ ┌──┴──┐  ┌───┴───┐                          │   │
│   │       │OSD 0,1│ │OSD 2,3│ │OSD 4│  │OSD 5,6│   <- Disques            │   │
│   │       └───────┘ └──────┘ └─────┘  └───────┘                          │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   Regle: "replicas sur racks differents"                                    │
│   → Garantit la survie meme si un rack tombe                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.3 Pools et Placement Groups

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    POOLS ET PLACEMENT GROUPS                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   POOL = Partition logique du stockage                                       │
│   ─────────────────────────────────────                                      │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Pool "rbd-pool"                                   │   │
│   │                    ───────────────                                   │   │
│   │  Type: Replicated (3 copies)                                        │   │
│   │  PGs: 128                                                           │   │
│   │                                                                      │   │
│   │  ┌─────┐ ┌─────┐ ┌─────┐ ┌─────┐ ... ┌─────┐                        │   │
│   │  │PG 0 │ │PG 1 │ │PG 2 │ │PG 3 │     │PG127│                        │   │
│   │  └──┬──┘ └──┬──┘ └──┬──┘ └──┬──┘     └──┬──┘                        │   │
│   │     │       │       │       │           │                            │   │
│   │     ▼       ▼       ▼       ▼           ▼                            │   │
│   │  [1,3,5] [2,4,6] [1,4,7] [3,5,8]     [2,5,9]  <- OSDs assignes       │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Pool "cephfs-data"                                │   │
│   │                    ─────────────────                                 │   │
│   │  Type: Erasure Coding (k=4, m=2)                                    │   │
│   │  PGs: 64                                                            │   │
│   │  Efficacite: 66% (vs 33% pour 3x replicated)                        │   │
│   │                                                                      │   │
│   │  ┌─────┐ ┌─────┐ ┌─────┐ ... ┌─────┐                                │   │
│   │  │PG 0 │ │PG 1 │ │PG 2 │     │PG 63│                                │   │
│   │  └─────┘ └─────┘ └─────┘     └─────┘                                │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
│   Calcul du nombre de PGs:                                                   │
│   PGs = (OSDs * 100) / replicas                                             │
│   Arrondi a la puissance de 2 superieure                                    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.4 Etats du Cluster

| Etat | Signification | Action |
|------|---------------|--------|
| **HEALTH_OK** | Cluster sain | Aucune |
| **HEALTH_WARN** | Probleme mineur | Investiguer |
| **HEALTH_ERR** | Probleme critique | Action immediate |
| **active+clean** | PG normal | OK |
| **active+degraded** | Replicas manquants | Recovery en cours |
| **peering** | PG en synchronisation | Attendre |
| **recovering** | Reconstruction | Attendre |
| **backfilling** | Rebalancement | Attendre |

---

## 3. Environnement de Lab Docker

### 3.1 Architecture du Lab

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                     ARCHITECTURE DU LAB DOCKER                               │
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Docker Network: ceph_cluster_net                  │   │
│   │                         172.20.0.0/16                                │   │
│   │                                                                      │   │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│   │   │   ceph-mon1 │  │   ceph-mon2 │  │   ceph-mon3 │                 │   │
│   │   │ 172.20.0.11 │  │ 172.20.0.12 │  │ 172.20.0.13 │                 │   │
│   │   │   Monitor   │  │   Monitor   │  │   Monitor   │                 │   │
│   │   │   + MGR     │  │   + MGR     │  │   + MGR     │                 │   │
│   │   └──────┬──────┘  └──────┬──────┘  └──────┬──────┘                 │   │
│   │          │                │                │                         │   │
│   │          └────────────────┼────────────────┘                         │   │
│   │                           │                                          │   │
│   │   ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │   │
│   │   │   ceph-osd1 │  │   ceph-osd2 │  │   ceph-osd3 │                 │   │
│   │   │ 172.20.0.21 │  │ 172.20.0.22 │  │ 172.20.0.23 │                 │   │
│   │   │    OSD 0    │  │    OSD 1    │  │    OSD 2    │                 │   │
│   │   └─────────────┘  └─────────────┘  └─────────────┘                 │   │
│   │                                                                      │   │
│   │   ┌─────────────┐                   ┌─────────────┐                 │   │
│   │   │   ceph-mds  │                   │   ceph-rgw  │                 │   │
│   │   │ 172.20.0.31 │                   │ 172.20.0.41 │                 │   │
│   │   │  Metadata   │                   │  S3 Gateway │                 │   │
│   │   │   Server    │                   │  Port 7480  │                 │   │
│   │   └─────────────┘                   └─────────────┘                 │   │
│   │                                                                      │   │
│   │   ┌─────────────┐                                                   │   │
│   │   │ ceph-client │  <- Client pour les tests                         │   │
│   │   │ 172.20.0.50 │                                                   │   │
│   │   └─────────────┘                                                   │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.2 Structure des Fichiers

```
ceph-workshop/
├── docker-compose.yaml
├── workshop-ceph.md
├── mon1/
│   ├── Dockerfile
│   └── entrypoint.sh
├── mon2/
│   └── ... (similaire)
├── mon3/
│   └── ...
├── osd1/
│   ├── Dockerfile
│   └── entrypoint.sh
├── osd2/
│   └── ...
├── osd3/
│   └── ...
├── mds/
│   ├── Dockerfile
│   └── entrypoint.sh
├── rgw/
│   ├── Dockerfile
│   └── entrypoint.sh
├── scripts/
│   ├── ceph-status.sh
│   ├── ceph-health.sh
│   ├── pool-create.sh
│   ├── rbd-manage.sh
│   ├── cephfs-setup.sh
│   ├── rgw-setup.sh
│   ├── simulate-failure.sh
│   ├── recovery-check.sh
│   ├── benchmark.sh
│   └── backup-restore.sh
└── solutions/
    ├── tp1-solution.sh
    ├── tp2-solution.sh
    └── ...
```

---

## 4. TP1 - Deploiement du Cluster Ceph

### Objectifs
- Comprendre l'architecture Ceph
- Deployer un cluster minimal (3 MON, 3 OSD)
- Verifier l'etat de sante du cluster

### Etape 1: Demarrer l'environnement

```bash
# Se placer dans le repertoire du workshop
cd ceph-workshop

# Demarrer les conteneurs
docker-compose up -d

# Verifier que les conteneurs sont en cours d'execution
docker-compose ps
```

### Etape 2: Explorer le cluster

```bash
# Se connecter au premier monitor
docker exec -it ceph-mon1 bash

# Verifier l'etat du cluster
/scripts/ceph-status.sh

# Voir la sante detaillee
/scripts/ceph-health.sh
```

### Etape 3: Comprendre la configuration

```bash
# Voir la configuration Ceph
cat /etc/ceph/ceph.conf

# Structure attendue:
# [global]
# fsid = <cluster-uuid>
# mon_initial_members = mon1, mon2, mon3
# mon_host = 172.20.0.11, 172.20.0.12, 172.20.0.13
# auth_cluster_required = cephx
# auth_service_required = cephx
# auth_client_required = cephx
# osd_pool_default_size = 3
# osd_pool_default_min_size = 2
```

### Etape 4: Verifier les composants

```bash
# Lister les monitors
ceph mon stat

# Lister les OSDs
ceph osd tree

# Voir la CRUSH map
ceph osd crush tree

# Verifier l'espace disponible
ceph df
```

### Etape 5: Explorer les cartes du cluster

```bash
# Voir la carte des monitors
ceph mon dump

# Voir la carte des OSDs
ceph osd dump

# Exporter la CRUSH map (binaire)
ceph osd getcrushmap -o crushmap.bin

# Decompiler pour lecture
crushtool -d crushmap.bin -o crushmap.txt
cat crushmap.txt
```

### Exercice 1.1: Questions de Comprehension

1. Pourquoi a-t-on besoin de 3 monitors minimum?
2. Que se passe-t-il si 2 monitors tombent?
3. Quelle est la difference entre `osd_pool_default_size` et `osd_pool_default_min_size`?
4. Comment CRUSH garantit-il la repartition des donnees?

### Exercice 1.2: Modification de la CRUSH Map

```bash
# Modifier la CRUSH map pour ajouter des failure domains
# (racks, datacenters)
/scripts/crush-modify.sh add-rack rack1
/scripts/crush-modify.sh move osd.0 rack1
```

---

## 5. TP2 - Stockage Bloc (RBD)

### Objectifs
- Creer et gerer des images RBD
- Monter un volume RBD sur un client
- Effectuer des snapshots et clones

### Concepts RBD

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RBD - RADOS BLOCK DEVICE                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                           Client VM/Host                             │   │
│   │                                                                      │   │
│   │   ┌───────────────────────────────────────────────────────────┐     │   │
│   │   │              Application (Database, etc.)                  │     │   │
│   │   └───────────────────────────────────────────────────────────┘     │   │
│   │                              │                                       │   │
│   │                              ▼                                       │   │
│   │   ┌───────────────────────────────────────────────────────────┐     │   │
│   │   │              Filesystem (ext4, xfs)                        │     │   │
│   │   └───────────────────────────────────────────────────────────┘     │   │
│   │                              │                                       │   │
│   │                              ▼                                       │   │
│   │   ┌───────────────────────────────────────────────────────────┐     │   │
│   │   │              /dev/rbd0 (Block Device)                      │     │   │
│   │   │              Image: rbd-pool/my-disk                       │     │   │
│   │   │              Size: 10GB                                    │     │   │
│   │   └───────────────────────────────────────────────────────────┘     │   │
│   │                              │                                       │   │
│   └──────────────────────────────┼──────────────────────────────────────┘   │
│                                  │                                          │
│                                  │ librbd / kernel rbd                      │
│                                  ▼                                          │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         CEPH CLUSTER                                 │   │
│   │                                                                      │   │
│   │   Image "my-disk" decoupe en objets de 4MB:                         │   │
│   │   ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐                      │   │
│   │   │ obj0 │ │ obj1 │ │ obj2 │ │ obj3 │ │ ...  │                      │   │
│   │   └──────┘ └──────┘ └──────┘ └──────┘ └──────┘                      │   │
│   │      │        │        │        │        │                          │   │
│   │      ▼        ▼        ▼        ▼        ▼                          │   │
│   │   [OSD 1]  [OSD 3]  [OSD 2]  [OSD 1]  [OSD 3]  (+ replicas)         │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Etape 1: Creer un pool RBD

```bash
docker exec -it ceph-mon1 bash

# Creer le pool pour RBD
/scripts/pool-create.sh rbd-pool 64 3

# Ou manuellement:
ceph osd pool create rbd-pool 64 64 replicated
ceph osd pool set rbd-pool size 3
ceph osd pool set rbd-pool min_size 2
ceph osd pool application enable rbd-pool rbd
```

### Etape 2: Creer une image RBD

```bash
# Creer une image de 10GB
rbd create rbd-pool/test-disk --size 10G

# Lister les images
rbd ls rbd-pool

# Voir les details
rbd info rbd-pool/test-disk
```

### Etape 3: Mapper l'image sur le client

```bash
# Sur le client
docker exec -it ceph-client bash

# Mapper l'image RBD
rbd map rbd-pool/test-disk

# Verifier
rbd showmapped

# Formater et monter
mkfs.ext4 /dev/rbd0
mkdir -p /mnt/rbd-disk
mount /dev/rbd0 /mnt/rbd-disk

# Tester
echo "Test RBD $(date)" > /mnt/rbd-disk/test.txt
cat /mnt/rbd-disk/test.txt
```

### Etape 4: Snapshots RBD

```bash
# Creer un snapshot
rbd snap create rbd-pool/test-disk@snap1

# Lister les snapshots
rbd snap ls rbd-pool/test-disk

# Ecrire de nouvelles donnees
echo "Nouvelles donnees" > /mnt/rbd-disk/new-data.txt

# Rollback au snapshot
umount /mnt/rbd-disk
rbd snap rollback rbd-pool/test-disk@snap1
mount /dev/rbd0 /mnt/rbd-disk

# Verifier que new-data.txt n'existe plus
ls /mnt/rbd-disk/
```

### Etape 5: Clones RBD

```bash
# Proteger le snapshot (requis pour le clonage)
rbd snap protect rbd-pool/test-disk@snap1

# Creer un clone
rbd clone rbd-pool/test-disk@snap1 rbd-pool/test-disk-clone

# Le clone est utilisable immediatement (copy-on-write)
rbd map rbd-pool/test-disk-clone
```

### Exercice 2.1: Benchmark RBD

```bash
# Lancer un benchmark
/scripts/benchmark.sh rbd rbd-pool/test-disk

# Comparer les performances avec differentes tailles d'objets
# 4MB (default) vs 8MB vs 16MB
```

### Exercice 2.2: Resize d'image

```bash
# Etendre l'image a 20GB
rbd resize rbd-pool/test-disk --size 20G

# Etendre le filesystem
resize2fs /dev/rbd0

# Verifier
df -h /mnt/rbd-disk
```

---

## 6. TP3 - Systeme de Fichiers (CephFS)

### Objectifs
- Deployer CephFS
- Monter un filesystem partage
- Gerer les quotas et snapshots

### Architecture CephFS

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CephFS                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐                                     │
│   │ Client 1│  │ Client 2│  │ Client 3│                                     │
│   │  mount  │  │  mount  │  │  mount  │                                     │
│   │ /cephfs │  │ /cephfs │  │ /cephfs │                                     │
│   └────┬────┘  └────┬────┘  └────┬────┘                                     │
│        │            │            │                                          │
│        └────────────┼────────────┘                                          │
│                     │                                                        │
│                     ▼                                                        │
│        ┌────────────────────────┐                                           │
│        │      MDS (Active)      │◄───► MDS (Standby)                        │
│        │   Metadata Cache       │                                           │
│        │   - Inodes             │                                           │
│        │   - Directories        │                                           │
│        │   - Permissions        │                                           │
│        └───────────┬────────────┘                                           │
│                    │                                                         │
│        ┌───────────┴───────────┐                                            │
│        │                       │                                             │
│        ▼                       ▼                                             │
│   ┌─────────────┐       ┌─────────────┐                                     │
│   │ Metadata    │       │ Data Pool   │                                     │
│   │ Pool        │       │             │                                     │
│   │ (replicated)│       │ (replicated │                                     │
│   │             │       │  or erasure)│                                     │
│   └─────────────┘       └─────────────┘                                     │
│        │                       │                                             │
│        └───────────┬───────────┘                                            │
│                    │                                                         │
│                    ▼                                                         │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                           OSDs                                       │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Etape 1: Creer les pools CephFS

```bash
docker exec -it ceph-mon1 bash

# Pool pour les metadonnees (toujours replicated)
ceph osd pool create cephfs-metadata 32 32 replicated
ceph osd pool set cephfs-metadata size 3

# Pool pour les donnees
ceph osd pool create cephfs-data 64 64 replicated
ceph osd pool set cephfs-data size 3
```

### Etape 2: Creer le filesystem

```bash
# Creer CephFS
ceph fs new cephfs cephfs-metadata cephfs-data

# Verifier
ceph fs ls
ceph fs status cephfs
```

### Etape 3: Verifier le MDS

```bash
# Voir l'etat du MDS
ceph mds stat

# Details
ceph fs dump
```

### Etape 4: Monter CephFS sur le client

```bash
docker exec -it ceph-client bash

# Recuperer la cle admin
cat /etc/ceph/ceph.client.admin.keyring

# Monter avec le kernel driver
mkdir -p /mnt/cephfs
mount -t ceph mon1,mon2,mon3:/ /mnt/cephfs -o name=admin,secret=<key>

# Ou avec ceph-fuse (userspace)
ceph-fuse /mnt/cephfs

# Tester
echo "Test CephFS $(date)" > /mnt/cephfs/test.txt
```

### Etape 5: Tester le partage multi-clients

```bash
# Sur client 1: creer un fichier
echo "Hello from client 1" > /mnt/cephfs/shared.txt

# Sur client 2 (autre terminal): lire le fichier
docker exec ceph-client2 cat /mnt/cephfs/shared.txt
# Output: Hello from client 1
```

### Etape 6: Quotas CephFS

```bash
# Definir un quota de 1GB sur un repertoire
setfattr -n ceph.quota.max_bytes -v 1073741824 /mnt/cephfs/project1

# Definir un quota de fichiers
setfattr -n ceph.quota.max_files -v 1000 /mnt/cephfs/project1

# Verifier
getfattr -n ceph.quota.max_bytes /mnt/cephfs/project1
```

### Etape 7: Snapshots CephFS

```bash
# Activer les snapshots
ceph fs set cephfs allow_new_snaps true

# Creer un snapshot
mkdir /mnt/cephfs/.snap/backup-$(date +%Y%m%d)

# Lister les snapshots
ls /mnt/cephfs/.snap/

# Restaurer un fichier depuis un snapshot
cp /mnt/cephfs/.snap/backup-20240115/important.txt /mnt/cephfs/
```

### Exercice 3.1: Multi-MDS

```bash
# Ajouter un second MDS actif pour le scaling
ceph fs set cephfs max_mds 2

# Verifier
ceph mds stat
```

### Exercice 3.2: Performance

```bash
# Benchmark CephFS
/scripts/benchmark.sh cephfs /mnt/cephfs

# Comparer avec un stockage local
```

---

## 7. TP4 - Stockage Objet (RGW/S3)

### Objectifs
- Deployer le RADOS Gateway
- Utiliser l'API S3
- Gerer les buckets et objets

### Architecture RGW

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         RADOS GATEWAY (RGW)                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                    Applications / Clients                            │   │
│   │                                                                      │   │
│   │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐               │   │
│   │   │  aws s3 │  │  s3cmd  │  │  boto3  │  │  curl   │               │   │
│   │   │   CLI   │  │         │  │ (Python)│  │         │               │   │
│   │   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘               │   │
│   │        │            │            │            │                     │   │
│   └────────┼────────────┼────────────┼────────────┼─────────────────────┘   │
│            │            │            │            │                         │
│            └────────────┴─────┬──────┴────────────┘                         │
│                               │                                              │
│                               ▼                                              │
│            ┌──────────────────────────────────────┐                         │
│            │         Load Balancer (optional)     │                         │
│            │         (HAProxy / Nginx)            │                         │
│            └─────────────────┬────────────────────┘                         │
│                              │                                              │
│            ┌─────────────────┼─────────────────┐                            │
│            │                 │                 │                            │
│            ▼                 ▼                 ▼                            │
│   ┌────────────────┐ ┌────────────────┐ ┌────────────────┐                  │
│   │    RGW 1       │ │    RGW 2       │ │    RGW 3       │                  │
│   │  Port 7480     │ │  Port 7480     │ │  Port 7480     │                  │
│   │                │ │                │ │                │                  │
│   │  S3 API        │ │  S3 API        │ │  S3 API        │                  │
│   │  Swift API     │ │  Swift API     │ │  Swift API     │                  │
│   │  Admin API     │ │  Admin API     │ │  Admin API     │                  │
│   └───────┬────────┘ └───────┬────────┘ └───────┬────────┘                  │
│           │                  │                  │                           │
│           └──────────────────┼──────────────────┘                           │
│                              │                                              │
│                              ▼                                              │
│   ┌─────────────────────────────────────────────────────────────────────┐   │
│   │                         RADOS / OSDs                                 │   │
│   │                                                                      │   │
│   │   Pools:  .rgw.root  |  default.rgw.buckets.data  |  ...            │   │
│   │                                                                      │   │
│   └─────────────────────────────────────────────────────────────────────┘   │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Etape 1: Verifier le RGW

```bash
docker exec -it ceph-rgw bash

# Verifier que le RGW est en cours d'execution
ceph -s

# Lister les services RGW
ceph orch ls rgw
# ou
radosgw-admin realm list
```

### Etape 2: Creer un utilisateur S3

```bash
# Creer un utilisateur
radosgw-admin user create --uid=workshop --display-name="Workshop User" --email=workshop@example.com

# Noter les credentials:
# "access_key": "XXXXXXXXXXXXXXXXXXXX"
# "secret_key": "YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY"

# Lister les utilisateurs
radosgw-admin user list
```

### Etape 3: Configurer le client S3

```bash
docker exec -it ceph-client bash

# Installer les outils
apt-get update && apt-get install -y awscli s3cmd

# Configurer AWS CLI
aws configure
# AWS Access Key ID: <access_key>
# AWS Secret Access Key: <secret_key>
# Default region name: default
# Default output format: json

# Ou creer ~/.aws/config directement
cat > ~/.aws/credentials << EOF
[default]
aws_access_key_id = <access_key>
aws_secret_access_key = <secret_key>
EOF
```

### Etape 4: Operations S3 de base

```bash
# Definir l'endpoint RGW
export RGW_ENDPOINT="http://ceph-rgw:7480"

# Creer un bucket
aws --endpoint-url=$RGW_ENDPOINT s3 mb s3://my-bucket

# Lister les buckets
aws --endpoint-url=$RGW_ENDPOINT s3 ls

# Uploader un fichier
echo "Hello S3!" > test.txt
aws --endpoint-url=$RGW_ENDPOINT s3 cp test.txt s3://my-bucket/

# Lister le contenu du bucket
aws --endpoint-url=$RGW_ENDPOINT s3 ls s3://my-bucket/

# Telecharger un fichier
aws --endpoint-url=$RGW_ENDPOINT s3 cp s3://my-bucket/test.txt downloaded.txt
```

### Etape 5: Versioning et Lifecycle

```bash
# Activer le versioning
aws --endpoint-url=$RGW_ENDPOINT s3api put-bucket-versioning \
    --bucket my-bucket \
    --versioning-configuration Status=Enabled

# Uploader plusieurs versions
for i in 1 2 3; do
    echo "Version $i - $(date)" > test.txt
    aws --endpoint-url=$RGW_ENDPOINT s3 cp test.txt s3://my-bucket/
done

# Lister les versions
aws --endpoint-url=$RGW_ENDPOINT s3api list-object-versions --bucket my-bucket

# Configurer une politique de lifecycle
cat > lifecycle.json << 'EOF'
{
    "Rules": [
        {
            "ID": "DeleteOldVersions",
            "Status": "Enabled",
            "NoncurrentVersionExpiration": {
                "NoncurrentDays": 30
            }
        }
    ]
}
EOF

aws --endpoint-url=$RGW_ENDPOINT s3api put-bucket-lifecycle-configuration \
    --bucket my-bucket \
    --lifecycle-configuration file://lifecycle.json
```

### Etape 6: Quotas utilisateur

```bash
# Definir un quota utilisateur
radosgw-admin quota set --quota-scope=user --uid=workshop --max-objects=1000 --max-size=1G

# Activer le quota
radosgw-admin quota enable --quota-scope=user --uid=workshop

# Verifier
radosgw-admin user info --uid=workshop
```

### Exercice 4.1: Multi-tenancy

```bash
# Creer un nouveau tenant
radosgw-admin user create --tenant=company1 --uid=user1 --display-name="Company1 User"

# Creer un bucket pour ce tenant
aws --endpoint-url=$RGW_ENDPOINT s3 mb s3://company1-data
```

### Exercice 4.2: Presigned URLs

```bash
# Generer une URL pre-signee (valide 1 heure)
aws --endpoint-url=$RGW_ENDPOINT s3 presign s3://my-bucket/test.txt --expires-in 3600

# Tester l'URL
curl "<presigned_url>"
```

---

## 8. TP5 - Haute Disponibilite et Failover

### Objectifs
- Tester la resilience du cluster
- Simuler des pannes
- Observer le recovery automatique

### 5.1 Panne d'un OSD

```bash
docker exec -it ceph-mon1 bash

# Etat initial
ceph -s
ceph osd tree

# Simuler une panne OSD
/scripts/simulate-failure.sh osd.1

# Observer l'etat
watch ceph -s

# Resultats attendus:
# - HEALTH_WARN puis recovery
# - PGs passent en "active+degraded"
# - Puis "active+recovering"
# - Puis retour a "active+clean"
```

### 5.2 Panne d'un Monitor

```bash
# Arreter un monitor
docker stop ceph-mon2

# Verifier le quorum
docker exec ceph-mon1 ceph mon stat

# Le cluster reste operationnel avec 2/3 monitors
docker exec ceph-mon1 ceph -s

# Redemarrer
docker start ceph-mon2
```

### 5.3 Panne Multiple (Scenario PS/PCA)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SCENARIOS DE PANNE PS/PCA                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   SCENARIO 1: Perte d'un rack                                               │
│   ─────────────────────────────                                              │
│   - 1 MON + 1 OSD tombent                                                   │
│   - Quorum maintenu (2/3)                                                   │
│   - Donnees accessibles (min_size=2)                                        │
│   - Recovery automatique quand OSD revient                                  │
│                                                                              │
│   SCENARIO 2: Perte de 2 OSDs                                               │
│   ──────────────────────────                                                 │
│   - Cluster en HEALTH_WARN                                                  │
│   - Certains PGs degraded                                                   │
│   - Donnees toujours accessibles                                            │
│   - Priority recovery active                                                │
│                                                                              │
│   SCENARIO 3: Perte de 2 MONs (CRITIQUE)                                    │
│   ─────────────────────────────────────                                      │
│   - Perte du quorum!                                                        │
│   - Cluster en read-only                                                    │
│   - Intervention manuelle requise                                           │
│                                                                              │
│   SCENARIO 4: Panne complete d'un datacenter                                │
│   ────────────────────────────────────────────                               │
│   - Avec geo-replication: failover vers DC2                                 │
│   - Sans: PRA depuis backups                                                │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Etape 1: Simuler la perte d'un rack

```bash
# Arreter un OSD et un MON (simule un rack)
docker stop ceph-mon3 ceph-osd3

# Observer
docker exec ceph-mon1 ceph -s
docker exec ceph-mon1 ceph health detail

# Verifier l'accessibilite des donnees
docker exec ceph-client cat /mnt/cephfs/test.txt
# Les donnees restent accessibles!

# Restaurer
docker start ceph-mon3 ceph-osd3

# Observer le recovery
docker exec ceph-mon1 watch ceph -s
```

### Etape 2: Test de l'auto-healing

```bash
# Supprimer un OSD definitivement
docker exec ceph-mon1 ceph osd out osd.2
docker stop ceph-osd3

# Ajouter un nouvel OSD de remplacement
# (Dans un vrai cluster: nouveau disque)
docker start ceph-osd3-new

# Observer le rebalancement
docker exec ceph-mon1 ceph -w
```

### Etape 3: Degradation Graceful

```bash
# Reduire min_size pour continuer avec 1 replica
ceph osd pool set rbd-pool min_size 1

# Maintenant le pool accepte les I/O meme avec 2 OSDs down
# ATTENTION: Risque de perte de donnees!

# Restaurer apres recovery
ceph osd pool set rbd-pool min_size 2
```

### Exercice 5.1: Plan de Recovery

Documentez les etapes de recovery pour:
1. Panne d'un OSD
2. Panne d'un Monitor
3. Panne du MDS actif
4. Corruption de la CRUSH map

### Exercice 5.2: RTO/RPO Analysis

| Scenario | RPO | RTO | Actions |
|----------|-----|-----|---------|
| 1 OSD down | 0 | ~5min | Auto-recovery |
| 1 MON down | 0 | ~1min | Auto-failover |
| 2 OSDs down | 0 | ~10min | Auto-recovery |
| Datacenter down | ? | ? | ? |

---

## 9. TP6 - Monitoring et Troubleshooting

### Objectifs
- Mettre en place le monitoring
- Interpreter les metriques
- Diagnostiquer les problemes

### 6.1 Dashboard Ceph

```bash
# Activer le module dashboard
ceph mgr module enable dashboard

# Creer un certificat SSL
ceph dashboard create-self-signed-cert

# Creer un utilisateur admin
ceph dashboard ac-user-create admin -i /tmp/passwd administrator

# Voir l'URL du dashboard
ceph mgr services
# Output: {"dashboard": "https://172.20.0.11:8443/"}
```

### 6.2 Metriques Importantes

```bash
# Script de monitoring
/scripts/ceph-health.sh

# Metriques cles:
ceph -s                    # Vue d'ensemble
ceph health detail         # Details des warnings
ceph osd df                # Utilisation des OSDs
ceph pg stat               # Etat des PGs
ceph osd perf              # Performance des OSDs
ceph osd pool stats        # Stats par pool
```

### 6.3 Prometheus Integration

```bash
# Activer le module prometheus
ceph mgr module enable prometheus

# Endpoint disponible
curl http://ceph-mon1:9283/metrics | head -50

# Metriques importantes:
# ceph_health_status
# ceph_osd_in
# ceph_osd_up
# ceph_pg_active
# ceph_pool_bytes_used
```

### 6.4 Alertes Recommandees

```yaml
# Exemple de regles Prometheus pour PS/PCA
groups:
  - name: ceph_alerts
    rules:
      - alert: CephHealthError
        expr: ceph_health_status == 2
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Ceph cluster health is ERROR"

      - alert: CephOSDDown
        expr: ceph_osd_up == 0
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Ceph OSD {{ $labels.osd }} is down"

      - alert: CephMonQuorumAtRisk
        expr: count(ceph_mon_quorum_status == 1) < 2
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Ceph monitor quorum at risk"

      - alert: CephPoolNearFull
        expr: ceph_pool_percent_used > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Pool {{ $labels.pool }} is {{ $value }}% full"
```

### 6.5 Troubleshooting Guide

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    GUIDE DE TROUBLESHOOTING CEPH                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  PROBLEME: "HEALTH_WARN: X osds down"                                       │
│  ─────────────────────────────────────                                       │
│  Diagnostic:                                                                 │
│    ceph osd tree                    # Voir quels OSDs sont down             │
│    systemctl status ceph-osd@X     # Verifier le service                    │
│    journalctl -u ceph-osd@X        # Voir les logs                          │
│  Solutions:                                                                  │
│    - Redemarrer l'OSD: systemctl restart ceph-osd@X                         │
│    - Si disque HS: remplacer et ajouter nouvel OSD                          │
│                                                                              │
│  PROBLEME: "HEALTH_WARN: X pgs degraded"                                    │
│  ───────────────────────────────────────                                     │
│  Diagnostic:                                                                 │
│    ceph pg dump_stuck degraded                                              │
│    ceph health detail                                                        │
│  Solution:                                                                   │
│    - Attendre le recovery automatique                                        │
│    - Verifier que les OSDs sont up                                          │
│                                                                              │
│  PROBLEME: "HEALTH_ERR: X pgs inconsistent"                                 │
│  ────────────────────────────────────────────                                │
│  Diagnostic:                                                                 │
│    ceph pg dump | grep inconsistent                                         │
│    ceph pg repair <pg_id>                                                   │
│  Solution:                                                                   │
│    - Reparer les PGs: ceph pg repair X.Y                                    │
│    - Verifier les logs OSD                                                  │
│                                                                              │
│  PROBLEME: "HEALTH_WARN: clock skew"                                        │
│  ─────────────────────────────────────                                       │
│  Diagnostic:                                                                 │
│    ceph time-sync-status                                                    │
│  Solution:                                                                   │
│    - Configurer NTP sur tous les noeuds                                     │
│    - Verifier: timedatectl status                                           │
│                                                                              │
│  PROBLEME: "HEALTH_WARN: pool X has no replicas"                            │
│  ─────────────────────────────────────────────────                           │
│  Solution:                                                                   │
│    ceph osd pool set X size 3                                               │
│                                                                              │
│  PROBLEME: Performances degradees                                            │
│  ─────────────────────────────────                                           │
│  Diagnostic:                                                                 │
│    ceph osd perf                    # Latence OSDs                          │
│    ceph osd pool stats              # IOPS par pool                         │
│    iostat -x 1                      # I/O systeme                           │
│  Solutions:                                                                  │
│    - Verifier la charge reseau                                              │
│    - Verifier les disques (SMART)                                           │
│    - Augmenter le nombre de PGs si necessaire                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Exercice 6.1: Diagnostic de Panne

```bash
# Lancer le scenario de panne
/scripts/simulate-failure.sh random

# Diagnostiquer et resoudre
ceph health detail
# ... votre diagnostic ...
```

---

## 10. TP7 - Scenarios PCA/PRA

### Objectifs
- Mettre en pratique les concepts PS/PCA
- Executer un plan de reprise
- Documenter les procedures

### 7.1 Backup et Restore

```bash
# Backup d'un pool RBD
/scripts/backup-restore.sh backup rbd-pool

# Export d'une image RBD
rbd export rbd-pool/test-disk /backup/test-disk.img

# Backup incrementiel avec snapshots
rbd snap create rbd-pool/test-disk@backup-daily
rbd export-diff rbd-pool/test-disk@backup-daily /backup/test-disk-diff.img

# Restore
rbd import /backup/test-disk.img rbd-pool/test-disk-restored
```

### 7.2 Disaster Recovery - Site Secondaire

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ARCHITECTURE DR MULTI-SITE                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   SITE PRINCIPAL (Paris)              SITE DR (Lyon)                         │
│   ┌─────────────────────┐             ┌─────────────────────┐               │
│   │                     │             │                     │               │
│   │  ┌─────┐ ┌─────┐   │   RBD       │  ┌─────┐ ┌─────┐   │               │
│   │  │ MON │ │ MON │   │  Mirror     │  │ MON │ │ MON │   │               │
│   │  └─────┘ └─────┘   │◄───────────►│  └─────┘ └─────┘   │               │
│   │                     │  (Async)    │                     │               │
│   │  ┌─────┐ ┌─────┐   │             │  ┌─────┐ ┌─────┐   │               │
│   │  │ OSD │ │ OSD │   │   RGW       │  │ OSD │ │ OSD │   │               │
│   │  └─────┘ └─────┘   │  Multisite  │  └─────┘ └─────┘   │               │
│   │                     │◄───────────►│                     │               │
│   │  ┌─────┐           │             │  ┌─────┐           │               │
│   │  │ RGW │           │             │  │ RGW │           │               │
│   │  └─────┘           │             │  └─────┘           │               │
│   │                     │             │                     │               │
│   └─────────────────────┘             └─────────────────────┘               │
│                                                                              │
│   RTO: ~15 minutes (temps de promotion du site DR)                          │
│   RPO: Depends de la frequence de sync (secondes a minutes)                 │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 7.3 RBD Mirroring

```bash
# Activer le mirroring sur le pool
rbd mirror pool enable rbd-pool pool

# Configurer le peer (site distant)
rbd mirror pool peer bootstrap create --site-name site-a rbd-pool > token.txt
# Sur le site distant:
rbd mirror pool peer bootstrap import --site-name site-b rbd-pool < token.txt

# Activer le mirroring sur une image
rbd mirror image enable rbd-pool/critical-data snapshot

# Verifier le status
rbd mirror pool status rbd-pool
rbd mirror image status rbd-pool/critical-data
```

### 7.4 Procedure de Failover DR

```bash
# 1. Constater la panne du site principal
# (monitoring, alertes)

# 2. Sur le site DR: promouvoir les images
rbd mirror image promote rbd-pool/critical-data --force

# 3. Les applications peuvent maintenant utiliser le site DR

# 4. Apres recovery du site principal:
# Demote sur le site principal pour resynchroniser
rbd mirror image demote rbd-pool/critical-data

# 5. Resynchronisation automatique

# 6. Si retour au site principal souhaite:
rbd mirror image promote rbd-pool/critical-data  # sur site principal
rbd mirror image demote rbd-pool/critical-data   # sur site DR
```

### Exercice 7.1: Simulation PRA Complete

1. Documenter l'etat initial du cluster
2. Simuler une panne majeure (2 OSDs + 1 MON)
3. Executer le plan de recovery
4. Documenter le temps de recovery (RTO reel)
5. Verifier l'integrite des donnees

### Exercice 7.2: Redaction du Document PS/PCA

Redigez un document PS/PCA incluant:
- Inventaire des composants critiques
- Analyse des risques
- Procedures de recovery detaillees
- Matrice RTO/RPO
- Plan de test periodique

---

## 11. Annexes

### A. Commandes Ceph Essentielles

```bash
# Cluster
ceph -s                          # Status du cluster
ceph health detail               # Details sante
ceph -w                          # Watch en temps reel
ceph df                          # Espace disque
ceph tell mon.* version          # Version des monitors

# OSDs
ceph osd tree                    # Arbre des OSDs
ceph osd df                      # Utilisation par OSD
ceph osd pool ls detail          # Liste des pools
ceph osd perf                    # Performance
ceph osd out osd.X               # Marquer out
ceph osd in osd.X                # Marquer in
ceph osd crush reweight osd.X Y  # Changer le poids

# Pools
ceph osd pool create NAME PGs    # Creer un pool
ceph osd pool set NAME size N    # Changer la replication
ceph osd pool delete NAME NAME --yes-i-really-really-mean-it

# PGs
ceph pg stat                     # Stats PGs
ceph pg dump                     # Dump complet
ceph pg dump_stuck               # PGs bloques
ceph pg repair X.Y               # Reparer un PG

# RBD
rbd create POOL/IMAGE --size XG  # Creer une image
rbd ls POOL                      # Lister
rbd info POOL/IMAGE              # Details
rbd map POOL/IMAGE               # Mapper
rbd unmap /dev/rbdX              # Demapper
rbd snap create POOL/IMAGE@SNAP  # Snapshot
rbd snap rollback POOL/IMAGE@SNAP # Rollback

# CephFS
ceph fs ls                       # Lister les FS
ceph fs status                   # Status
ceph mds stat                    # Status MDS

# RGW
radosgw-admin user list          # Liste utilisateurs
radosgw-admin user create --uid=X --display-name=Y
radosgw-admin bucket list        # Liste buckets
radosgw-admin bucket stats --bucket=X
```

### B. Configuration de Reference

```ini
# /etc/ceph/ceph.conf - Configuration production

[global]
fsid = <uuid>
mon_initial_members = mon1, mon2, mon3
mon_host = 10.0.0.11, 10.0.0.12, 10.0.0.13

# Authentification
auth_cluster_required = cephx
auth_service_required = cephx
auth_client_required = cephx

# Reseau
public_network = 10.0.0.0/24
cluster_network = 10.0.1.0/24

# Pools
osd_pool_default_size = 3
osd_pool_default_min_size = 2
osd_pool_default_pg_num = 128
osd_pool_default_pgp_num = 128

# Performance
osd_memory_target = 4294967296
bluestore_cache_size = 3221225472

[mon]
mon_allow_pool_delete = true
mon_osd_full_ratio = .95
mon_osd_nearfull_ratio = .85

[osd]
osd_scrub_begin_hour = 2
osd_scrub_end_hour = 6
osd_recovery_max_active = 3
osd_max_backfills = 1

[mds]
mds_cache_memory_limit = 4294967296

[client]
rbd_cache = true
rbd_cache_size = 134217728
```

### C. Checklist Production PS/PCA

**Pre-deploiement:**
- [ ] Dimensionnement valide (MONs, OSDs, reseau)
- [ ] CRUSH map reflete la topologie physique
- [ ] Reseaux separes (public/cluster)
- [ ] NTP configure sur tous les noeuds

**Haute Disponibilite:**
- [ ] Minimum 3 MONs sur failure domains differents
- [ ] Minimum 3 OSDs pour size=3
- [ ] MGR actif/standby
- [ ] MDS actif/standby (si CephFS)
- [ ] RGW multi-instances (si utilise)

**Monitoring:**
- [ ] Dashboard Ceph actif
- [ ] Integration Prometheus/Grafana
- [ ] Alertes configurees
- [ ] Logs centralises

**Backup/DR:**
- [ ] Snapshots automatises
- [ ] RBD mirroring configure (si DR)
- [ ] Procedures de restore testees
- [ ] Documentation a jour

**Securite:**
- [ ] Cephx active
- [ ] Certificats SSL pour dashboard/RGW
- [ ] Acces restreints
- [ ] Audit logs actives

### D. Ressources Supplementaires

- Documentation officielle: https://docs.ceph.com/
- Quick Start: https://docs.ceph.com/en/latest/start/
- Architecture: https://docs.ceph.com/en/latest/architecture/
- Operations: https://docs.ceph.com/en/latest/rados/operations/
- Troubleshooting: https://docs.ceph.com/en/latest/rados/troubleshooting/

---

## Quiz Final

1. Expliquez le role de l'algorithme CRUSH dans la haute disponibilite de Ceph.
2. Quel est le nombre minimum de monitors pour tolerer 2 pannes?
3. Quelle est la difference entre Erasure Coding et Replication?
4. Comment Ceph garantit-il un RPO de 0?
5. Decrivez les etapes d'un failover RBD mirroring.
6. Pourquoi ne doit-on jamais avoir moins de `min_size` replicas disponibles?
7. Comment le scrubbing contribue-t-il a l'integrite des donnees?
8. Quel est l'impact du nombre de PGs sur les performances?

---

**Felicitations!** Vous avez termine le workshop Ceph sur le stockage distribue et la haute disponibilite pour PS/PCA.
