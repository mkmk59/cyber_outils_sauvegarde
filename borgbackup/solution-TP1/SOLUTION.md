# Solution TP Sauvegarde - Ghostfolio avec BorgBackup

## Table des matieres

1. [Vue d'ensemble](#1-vue-densemble)
2. [Architecture](#2-architecture)
3. [Etape 1: Mise en place de Ghostfolio](#etape-1-mise-en-place-de-lapplication-ghostfolio)
4. [Etape 2: Conception de l'architecture](#etape-2-conception-de-larchitecture-de-sauvegarde)
5. [Etape 3: Mise en place du borg-server](#etape-3-mise-en-place-du-serveur-borg-server)
6. [Etape 4: Mise en place du borg-client](#etape-4-mise-en-place-du-conteneur-borg-client)
7. [Etape 5: Sauvegarde complete](#etape-5-execution-dune-sauvegarde-complete)
8. [Etape 6: Simulation d'attaque](#etape-6-scenario-dattaque-simulation)
9. [Etape 7: Restauration](#etape-7-restauration-complete)
10. [Etape 8: Automatisation](#etape-8-mise-en-place-de-la-rotation-et-automatisation)
11. [Etape 9: Sauvegarde config Borg vers MinIO](#etape-9-sauvegarde-de-la-configuration-borgbackup-vers-minio)

---

## 1. Vue d'ensemble

Cette solution met en place un systeme de sauvegarde securise pour l'application Ghostfolio en utilisant BorgBackup. Elle repond aux exigences de securite suivantes:

| Exigence | Implementation |
|----------|----------------|
| Externalisation | Serveur borg-server dedie sur reseau isole |
| Chiffrement cote client | BorgBackup avec encryption repokey-blake2 |
| Isolation | Deux reseaux Docker separes (app/backup) |
| Restauration post-incident | Scripts de restauration automatises |
| Automatisation | Cron job pour sauvegardes planifiees |
| Secrets non versions | Fichier .env + .gitignore |

---

## 2. Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        RESEAU APP_NETWORK                        │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐            │
│  │  Ghostfolio │   │  PostgreSQL │   │    Redis    │            │
│  │   :3333     │──▶│    :5432    │   │    :6379    │            │
│  └─────────────┘   └──────┬──────┘   └─────────────┘            │
│                           │                                      │
│                    ┌──────┴──────┐                               │
│                    │ borg-client │                               │
│                    │  (pg_dump)  │                               │
│                    └──────┬──────┘                               │
└───────────────────────────┼─────────────────────────────────────┘
                            │ SSH (cle)
┌───────────────────────────┼─────────────────────────────────────┐
│                    ┌──────┴──────┐     RESEAU BACKUP_NETWORK     │
│                    │ borg-server │     (internal: true)          │
│                    │    :22      │                               │
│                    └──────┬──────┘                               │
│                           │                                      │
│                    ┌──────┴──────┐                               │
│                    │  Volume     │                               │
│                    │  borg_repo  │                               │
│                    └─────────────┘                               │
└─────────────────────────────────────────────────────────────────┘
```

### Composants

| Conteneur | Role | Reseau |
|-----------|------|--------|
| ghostfolio | Application web | app_network |
| postgres | Base de donnees | app_network |
| redis | Cache | app_network |
| borg-client | Effectue les sauvegardes | app_network + backup_network |
| borg-server | Stocke les sauvegardes | backup_network (isole) |

---

## Etape 1: Mise en place de l'application Ghostfolio

### 1.1 Generation des secrets

```bash
# Rendre les scripts executables
chmod +x generate-secrets.sh generate-ssh-keys.sh

# Generer le fichier .env avec des secrets securises
./generate-secrets.sh
```

Le script genere automatiquement:
- `POSTGRES_PASSWORD`: Mot de passe PostgreSQL
- `ACCESS_TOKEN_SALT`: Salt pour les tokens Ghostfolio
- `JWT_SECRET_KEY`: Cle secrete JWT
- `BORG_PASSPHRASE`: Passphrase de chiffrement des sauvegardes

### 1.2 Generation des cles SSH

```bash
./generate-ssh-keys.sh
```

Cree une paire de cles RSA 4096 bits pour l'authentification sans mot de passe.

### 1.3 Demarrage de l'application

```bash
# Construire et demarrer tous les conteneurs
docker-compose up -d

# Verifier le statut
docker-compose ps

# Consulter les logs
docker-compose logs -f ghostfolio
```

### 1.4 Verification

Accedez a http://localhost:3333 pour verifier que Ghostfolio fonctionne.

---

## Etape 2: Conception de l'architecture de sauvegarde

### Principes de securite appliques

1. **Chiffrement cote client**: Les donnees sont chiffrees par `borg-client` AVANT d'etre envoyees au serveur. Le serveur ne voit jamais les donnees en clair.

2. **Isolation reseau**: Le `borg-server` est sur un reseau `internal: true`, sans acces a Internet ni aux conteneurs applicatifs.

3. **Authentification par cle SSH**: Aucun mot de passe n'est utilise pour la connexion SSH, uniquement des cles cryptographiques.

4. **Separation des privileges**:
   - `borg-client` a acces en lecture seule aux donnees
   - `borg-server` n'a aucun acces aux donnees sources

5. **Secrets non versions**: Le fichier `.env` et les cles SSH sont exclus de Git via `.gitignore`.

### Flux de sauvegarde

```
1. borg-client execute pg_dump sur PostgreSQL
2. Le dump est stocke temporairement dans /tmp/backup
3. borg-client chiffre et compresse les donnees
4. Les donnees chiffrees sont envoyees via SSH au borg-server
5. borg-server stocke les blocs chiffres (deduplication)
6. Le repertoire temporaire est nettoye
```

---

## Etape 3: Mise en place du serveur borg-server

### Configuration (borg-server/Dockerfile)

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    openssh-server \
    borgbackup

# Securisation SSH
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

# Utilisateur dedie
RUN useradd -m -d /home/borg -s /bin/bash borg
RUN mkdir -p /var/borg/repos && chown -R borg:borg /var/borg
```

### Points cles de securite

- **PasswordAuthentication no**: Seule l'authentification par cle est permise
- **PermitRootLogin no**: Connexion root interdite
- **Utilisateur dedie**: L'utilisateur `borg` a des privileges limites

---

## Etape 4: Mise en place du conteneur borg-client

### Configuration (borg-client/Dockerfile)

```dockerfile
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    borgbackup \
    openssh-client \
    postgresql-client

# Configuration SSH
RUN echo "Host borg-server" > /root/.ssh/config
RUN echo "    StrictHostKeyChecking accept-new" >> /root/.ssh/config
```

### Scripts disponibles

| Script | Description |
|--------|-------------|
| `init-repo.sh` | Initialise le depot BorgBackup |
| `backup.sh` | Execute une sauvegarde complete |
| `restore.sh` | Restaure une archive |
| `list-backups.sh` | Liste les archives disponibles |
| `simulate-attack.sh` | Simule une attaque ransomware |

---

## Etape 5: Execution d'une sauvegarde complete

### 5.1 Initialisation du depot

```bash
# Acceder au client
docker exec -it borg-client bash

# Initialiser le depot (une seule fois)
./init-repo.sh
```

Sortie attendue:
```
[INFO] Test de connexion SSH...
Connexion SSH OK
[INFO] Initialisation du depot avec chiffrement...
[OK] Depot initialise avec succes
```

### 5.2 Premiere sauvegarde

```bash
./backup.sh
```

Sortie attendue:
```
==============================================
 Sauvegarde Ghostfolio - ghostfolio-2024-01-15_10-30-00
==============================================
[INFO] Dump de la base de donnees PostgreSQL...
[OK] Dump PostgreSQL cree: ghostfolio.dump
[INFO] Creation de l'archive BorgBackup...
[OK] Archive creee avec succes
[INFO] Application de la politique de retention...
==============================================
 Sauvegarde terminee avec succes
==============================================
```

### 5.3 Verification

```bash
./list-backups.sh
```

---

## Etape 6: Scenario d'attaque (simulation)

### Contexte

Un ransomware a chiffre les donnees Ghostfolio. L'application est inutilisable.

### Simulation

```bash
# Dans le conteneur borg-client
./simulate-attack.sh
```

Ce script:
1. Vide toutes les tables de la base de donnees
2. Insere un message de rancon
3. Rend l'application inutilisable

### Verification de l'attaque

```bash
# L'application ne repond plus correctement
curl http://localhost:3333

# Dans la base, on voit le message de rancon
docker exec -it postgres psql -U ghostfolio -d ghostfolio -c "SELECT * FROM ransom_note;"
```

---

## Etape 7: Restauration complete

### 7.1 Lister les archives disponibles

```bash
docker exec -it borg-client ./list-backups.sh
```

### 7.2 Restaurer une archive

```bash
docker exec -it borg-client bash

# Restaurer la derniere archive
./restore.sh $(borg list --short --last 1 $BORG_REPO)

# OU specifier une archive precise
./restore.sh ghostfolio-2024-01-15_10-30-00
```

### 7.3 Redemarrer l'application

```bash
docker-compose restart ghostfolio
```

### 7.4 Verification

```bash
# L'application fonctionne a nouveau
curl http://localhost:3333
```

---

## Etape 8: Mise en place de la rotation et automatisation

### Politique de retention

La politique definie dans `backup.sh`:

| Type | Retention | Description |
|------|-----------|-------------|
| Journalier | 7 | Garde les 7 dernieres sauvegardes journalieres |
| Hebdomadaire | 4 | Garde 4 sauvegardes hebdomadaires |
| Mensuel | 6 | Garde 6 sauvegardes mensuelles |

```bash
borg prune \
    --keep-daily=7 \
    --keep-weekly=4 \
    --keep-monthly=6 \
    "$BORG_REPO"
```

### Automatisation avec cron

#### Option 1: Cron dans le conteneur

Ajoutez au Dockerfile du borg-client:

```dockerfile
# Ajout de la tache cron
RUN echo "0 2 * * * /backup-scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/backup
RUN chmod 0644 /etc/cron.d/backup
RUN crontab /etc/cron.d/backup
```

#### Option 2: Cron sur l'hote

```bash
# Ajouter a crontab de l'hote
0 2 * * * docker exec borg-client /backup-scripts/backup.sh >> /var/log/ghostfolio-backup.log 2>&1
```

### Verification de l'automatisation

```bash
# Verifier les logs
tail -f /var/log/backup.log

# Verifier la derniere sauvegarde
docker exec -it borg-client ./list-backups.sh
```

---

## Resume des commandes

### Demarrage initial

```bash
./generate-secrets.sh
./generate-ssh-keys.sh
docker-compose up -d
docker exec -it borg-client ./init-repo.sh
```

### Sauvegarde manuelle

```bash
docker exec -it borg-client ./backup.sh
```

### Restauration

```bash
docker exec -it borg-client ./list-backups.sh
docker exec -it borg-client ./restore.sh <nom_archive>
docker-compose restart ghostfolio
```

### Verification

```bash
docker-compose ps
docker exec -it borg-client ./list-backups.sh
curl http://localhost:3333
```

---

## Checklist de conformite

- [x] Aucun mot de passe en clair dans les fichiers versiones
- [x] Serveur de sauvegarde isole (reseau interne)
- [x] Chiffrement cote client (repokey-blake2)
- [x] Application destructible et restaurable
- [x] Fonctionnement apres reinstallation de Ghostfolio
- [x] Plan de retention documente (7/4/6)
- [x] Actions reproductibles et documentees
- [x] Sauvegarde externalisee de la configuration Borg vers MinIO/S3

---

## Etape 9: Sauvegarde de la configuration BorgBackup vers MinIO

### 9.1 Objectif

Sauvegarder la configuration BorgBackup (cles SSH, repository) vers un stockage objet S3 compatible (MinIO) en utilisant Restic. Cela permet une recuperation complete meme si le serveur de sauvegarde principal est perdu.

### 9.2 Architecture etendue

```
┌─────────────────────────────────────────────────────────────────┐
│                     RESEAU BACKUP_NETWORK                       │
│  ┌─────────────┐   ┌─────────────┐   ┌─────────────┐           │
│  │ borg-server │   │    MinIO    │   │restic-client│           │
│  │    :22      │   │ :9000/:9001 │◀──│   (backup)  │           │
│  └──────┬──────┘   └──────┬──────┘   └─────────────┘           │
│         │                 │                                     │
│  ┌──────┴──────┐   ┌──────┴──────┐                             │
│  │   Volume    │   │   Volume    │                             │
│  │  borg_repo  │   │ minio_data  │                             │
│  └─────────────┘   └─────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

### 9.3 Composants ajoutes

| Conteneur | Role | Description |
|-----------|------|-------------|
| minio | Stockage S3 | Serveur de stockage objet compatible S3 |
| minio-init | Initialisation | Cree le bucket pour Restic |
| restic-client | Sauvegarde | Sauvegarde la config Borg vers MinIO |

### 9.4 Configuration MinIO

MinIO est configure dans `docker-compose.yaml`:

```yaml
minio:
  image: minio/minio:latest
  command: server /data --console-address ":9001"
  environment:
    - MINIO_ROOT_USER=${MINIO_ROOT_USER:-minioadmin}
    - MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD:-minioadmin123}
  ports:
    - "9000:9000"   # API S3
    - "9001:9001"   # Console Web
  volumes:
    - minio_data:/data
```

### 9.5 Demarrage de MinIO et Restic

```bash
# Mettre a jour le fichier .env avec les credentials MinIO
# MINIO_ROOT_USER=minioadmin
# MINIO_ROOT_PASSWORD=votre_mot_de_passe_securise
# RESTIC_PASSWORD=votre_passphrase_restic

# Demarrer tous les services
docker-compose up -d

# Verifier que MinIO est accessible
curl http://localhost:9000/minio/health/live
```

### 9.6 Initialisation du repository Restic

```bash
# Acceder au client Restic
docker exec -it restic-client bash

# Initialiser le repository (une seule fois)
./init-repo.sh
```

Sortie attendue:
```
==========================================
INITIALISATION DU REPOSITORY RESTIC
==========================================
[INFO] Verification de la connexion a MinIO...
[INFO] MinIO est accessible
[INFO] Initialisation du nouveau repository Restic...
[OK] Repository Restic initialise avec succes
```

### 9.7 Sauvegarde de la configuration Borg

```bash
# Dans le conteneur restic-client
./backup.sh
```

Ce script sauvegarde:
- `/backup-source/borg-client-ssh` - Cles SSH du client
- `/backup-source/borg-server-ssh` - Cles SSH du serveur (authorized_keys)
- `/backup-source/borg-repo` - Repository BorgBackup complet

Sortie attendue:
```
==========================================
SAUVEGARDE CONFIGURATION BORG VERS MINIO
==========================================
[INFO] Fichiers a sauvegarder:
  - /backup-source/borg-client-ssh (cles SSH client)
  - /backup-source/borg-server-ssh (cles SSH serveur)
  - /backup-source/borg-repo (repository Borg)

[INFO] Demarrage de la sauvegarde...
[OK] Sauvegarde terminee avec succes!

[INFO] Dernier snapshot:
ID        Time                 Host          Tags
abc123    2024-01-15 10:30:00  restic-client borg-config,20240115
```

### 9.8 Lister les snapshots

```bash
./list.sh
```

### 9.9 Restauration depuis MinIO

```bash
# Restaurer le dernier snapshot
./restore.sh latest

# OU restaurer un snapshot specifique
./restore.sh abc123def456
```

Les fichiers sont restaures dans `/tmp/restore-<timestamp>/`.

### 9.10 Acces a la console MinIO

Accedez a http://localhost:9001 pour visualiser les donnees stockees:
- **Username**: valeur de `MINIO_ROOT_USER`
- **Password**: valeur de `MINIO_ROOT_PASSWORD`

### 9.11 Politique de retention Restic

Le script `backup.sh` applique automatiquement une retention de 7 snapshots:

```bash
restic forget --keep-last 7 --prune
```

### 9.12 Scripts Restic disponibles

| Script | Description |
|--------|-------------|
| `init-repo.sh` | Initialise le repository Restic sur MinIO |
| `backup.sh` | Sauvegarde la configuration Borg |
| `restore.sh` | Restaure depuis un snapshot |
| `list.sh` | Liste les snapshots disponibles |

### 9.13 Automatisation

Pour automatiser la sauvegarde Restic, ajoutez a crontab:

```bash
# Sauvegarde quotidienne a 3h du matin
0 3 * * * docker exec restic-client /backup-scripts/backup.sh >> /var/log/restic-backup.log 2>&1
```

### 9.14 Scenario de reprise apres sinistre

En cas de perte totale du serveur de sauvegarde:

1. **Reinstaller l'infrastructure**:
   ```bash
   docker-compose up -d minio
   ```

2. **Restaurer la configuration Borg**:
   ```bash
   docker exec -it restic-client ./restore.sh latest
   ```

3. **Copier les fichiers restaures**:
   ```bash
   # Depuis le conteneur restic-client
   cp -r /tmp/restore-*/backup-source/borg-client-ssh/* /chemin/vers/borg-client/ssh-keys/
   cp -r /tmp/restore-*/backup-source/borg-server-ssh/* /chemin/vers/borg-server/ssh-keys/
   ```

4. **Redemarrer les services Borg**:
   ```bash
   docker-compose up -d borg-server borg-client
   ```

---

## Resume des commandes (mis a jour)

### Demarrage initial complet

```bash
./generate-secrets.sh
./generate-ssh-keys.sh
docker-compose up -d
docker exec -it borg-client ./init-repo.sh
docker exec -it restic-client ./init-repo.sh
```

### Sauvegarde complete (Borg + Restic)

```bash
# Sauvegarde des donnees applicatives
docker exec -it borg-client ./backup.sh

# Sauvegarde de la configuration Borg vers MinIO
docker exec -it restic-client ./backup.sh
```

### Verification

```bash
docker-compose ps
docker exec -it borg-client ./list-backups.sh
docker exec -it restic-client ./list.sh
curl http://localhost:9000/minio/health/live
```
