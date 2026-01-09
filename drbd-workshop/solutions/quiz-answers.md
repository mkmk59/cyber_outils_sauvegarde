# Reponses au Quiz Final - Workshop DRBD

---

## Question 1
**Quelle est la principale difference entre DRBD et une replication applicative?**

### Reponse:

DRBD replique au **niveau bloc** (block device), tandis que la replication applicative opere au **niveau applicatif** (logique).

| Aspect | DRBD (Bloc) | Replication Applicative |
|--------|-------------|------------------------|
| **Niveau** | Kernel/Bloc | Application/Logique |
| **Transparence** | Totale - l'application ne sait pas | L'application doit gerer |
| **Donnees** | Tous les blocs | Seulement les donnees applicatives |
| **Performance** | Overhead sur toutes les I/O | Overhead selectif |
| **Coherence** | Garantie par le kernel | Depend de l'implementation |
| **Compatibilite** | Toute application | Specifique a l'application |

**Avantages DRBD:**
- Transparent pour les applications
- Fonctionne avec n'importe quel filesystem/application
- Coherence garantie au niveau bloc

**Avantages Replication Applicative:**
- Plus flexible (replication selective)
- Peut traverser des reseaux WAN plus facilement
- Moins d'overhead si peu de donnees a repliquer

---

## Question 2
**Dans quel cas utiliseriez-vous Protocol A plutot que Protocol C?**

### Reponse:

Utilisez **Protocol A (Asynchrone)** dans les cas suivants:

1. **Latence reseau elevee (>20ms)**
   - Replication entre datacenters distants
   - Liens WAN avec latence variable
   - Protocol C serait trop lent

2. **Performance prioritaire sur securite**
   - Serveurs de logs
   - Donnees de cache
   - Donnees facilement regenerables

3. **Tolerence a la perte de donnees**
   - RPO (Recovery Point Objective) de quelques secondes acceptable
   - Donnees non critiques

4. **Volume d'ecriture tres eleve**
   - Applications de type "big data"
   - Collecte de metriques
   - Streaming de donnees

**Exemple concret:**
```
# Replication de logs entre Paris et New York (80ms RTT)
# Avec Protocol C: chaque write +160ms de latence
# Avec Protocol A: latence normale, RPO ~5s max
```

**A EVITER avec Protocol A:**
- Bases de donnees financieres
- Donnees de configuration critiques
- Tout systeme ou la perte de donnees est inacceptable

---

## Question 3
**Comment DRBD gere-t-il un split-brain par defaut?**

### Reponse:

Par defaut, DRBD **detecte** le split-brain mais **n'agit pas automatiquement**. Il deconnecte les noeuds et attend une intervention manuelle.

**Comportement par defaut:**
```
# Les deux noeuds passent en etat "StandAlone"
# Message dans les logs:
# "Split-Brain detected, dropping connection!"
```

**Configuration par defaut equivalente:**
```
net {
    after-sb-0pri discard-zero-changes;  # Si aucun Primary
    after-sb-1pri discard-secondary;     # Si un Primary
    after-sb-2pri disconnect;            # Si deux Primary -> DECONNEXION
}
```

**Raison de ce comportement:**
- Un split-brain avec deux Primary signifie que les deux noeuds ont ecrit des donnees differentes
- Choisir automatiquement pourrait causer une perte de donnees
- L'administrateur doit decider quel noeud a les "bonnes" donnees

**Resolution manuelle:**
```bash
# Sur le noeud qui doit PERDRE ses donnees:
drbdadm disconnect r0
drbdadm secondary r0
drbdadm -- --discard-my-data connect r0

# Sur le noeud qui GARDE ses donnees:
drbdadm connect r0
```

---

## Question 4
**Pourquoi est-il important de toujours demonter le filesystem avant de changer de role?**

### Reponse:

Il est **critique** de demonter le filesystem avant de passer de Primary a Secondary pour plusieurs raisons:

1. **Coherence des donnees**
   - Le filesystem peut avoir des donnees en cache (buffer cache)
   - `umount` force la synchronisation de toutes les donnees sur le disque
   - Sans cela, des donnees pourraient etre perdues

2. **Integrite du filesystem**
   - Un filesystem monte a des structures en memoire
   - Le changer en Secondary sans demonter corromprait ces structures
   - Au prochain montage, le filesystem serait inconsistent

3. **Eviter les ecritures simultanees**
   - Si le filesystem reste monte sur l'ancien Primary
   - Et qu'un nouveau Primary monte aussi le filesystem
   - Les deux ecriraient simultanement = CORRUPTION

4. **Prevention du split-brain applicatif**
   - Les applications doivent etre arretees avant le failover
   - Demonter le FS force l'arret propre des applications

**Sequence correcte de failover:**
```bash
# 1. Arreter les applications
systemctl stop postgresql

# 2. Synchroniser les caches
sync

# 3. Demonter le filesystem
umount /mnt/drbd

# 4. Changer le role DRBD
drbdadm secondary r0

# 5. Le nouveau Primary peut maintenant prendre le relais
```

**Ce qui se passe si on oublie:**
```
# DRBD refuse le changement de role:
# "Can not change to secondary. Device is held open by someone"

# Ou pire, si force:
# Corruption du filesystem
# Perte de donnees
# Split-brain applicatif
```

---

## Question 5
**Quelle est la difference entre `invalidate` et `invalidate-remote`?**

### Reponse:

Ces deux commandes forcent une resynchronisation, mais dans des directions opposees:

### `drbdadm invalidate r0`
- Execute sur le noeud **local**
- Marque les donnees **locales** comme invalides
- Force une resync **depuis le peer vers ce noeud**
- Ce noeud devient la "cible" de la synchronisation

```
┌─────────────┐                ┌─────────────┐
│   Node A    │                │   Node B    │
│  (Source)   │ ──────────────►│  (Target)   │
│  UpToDate   │   Sync Data    │ Invalidated │
└─────────────┘                └─────────────┘

# Execute sur Node B:
drbdadm invalidate r0
# Node B recevra toutes les donnees de Node A
```

### `drbdadm invalidate-remote r0`
- Execute sur le noeud **local**
- Marque les donnees du **peer** comme invalides
- Force une resync **depuis ce noeud vers le peer**
- Ce noeud devient la "source" de la synchronisation

```
┌─────────────┐                ┌─────────────┐
│   Node A    │                │   Node B    │
│  (Source)   │ ──────────────►│  (Target)   │
│  UpToDate   │   Sync Data    │ Invalidated │
└─────────────┘                └─────────────┘

# Execute sur Node A:
drbdadm invalidate-remote r0
# Node A enverra toutes les donnees vers Node B
```

### Cas d'utilisation:

| Commande | Utiliser quand... |
|----------|-------------------|
| `invalidate` | Vous etes sur le noeud avec les mauvaises donnees |
| `invalidate-remote` | Vous etes sur le noeud avec les bonnes donnees |

### Attention:
```bash
# DANGEREUX si mal utilise!
# invalidate = "jeter mes donnees"
# invalidate-remote = "jeter les donnees du peer"

# Toujours verifier quel noeud a les bonnes donnees
# avant d'utiliser ces commandes!
```

### Exemple pratique:
```bash
# Apres un split-brain, Node A a les bonnes donnees

# Option 1: Sur Node B (mauvaises donnees)
drbdadm invalidate r0

# Option 2: Sur Node A (bonnes donnees)
drbdadm invalidate-remote r0

# Les deux ont le meme effet:
# Node A -> Node B (resync complete)
```

---

## Score et Evaluation

| Score | Niveau |
|-------|--------|
| 5/5 | Expert DRBD |
| 4/5 | Bon niveau, pret pour la production |
| 3/5 | Connaissances de base acquises |
| 2/5 | Revoir les concepts fondamentaux |
| 0-1/5 | Refaire le workshop |

---

*Fin des reponses du Quiz*
