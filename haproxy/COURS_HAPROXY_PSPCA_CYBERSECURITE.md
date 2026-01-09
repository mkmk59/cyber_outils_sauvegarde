# HAProxy pour la Cybersécurité
## Module PS/PCA (Plan de Secours / Plan de Continuité d'Activité)


---

## Table des Matières

1. [Introduction à HAProxy](#1-introduction-à-haproxy)
2. [Architecture et Concepts](#2-architecture-et-concepts)
3. [HAProxy et les Enjeux PS/PCA](#3-haproxy-et-les-enjeux-pspca)
4. [TP1 : Installation et Configuration de Base](#4-tp1-installation-et-configuration-de-base)
5. [TP2 : Haute Disponibilité et Failover](#5-tp2-haute-disponibilité-et-failover)
6. [TP3 : Sécurisation et Hardening](#6-tp3-sécurisation-et-hardening)
7. [TP4 : Monitoring et Observabilité](#7-tp4-monitoring-et-observabilité)
8. [Annexes et Références](#8-annexes-et-références)

---

## 1. Introduction à HAProxy

### 1.1 Qu'est-ce que HAProxy ?

HAProxy (High Availability Proxy) est un répartiteur de charge (load balancer) et proxy inverse open source, reconnu pour ses performances exceptionnelles et sa fiabilité. Créé en 2000 par Willy Tarreau, il est utilisé par des géants du web comme GitHub, Stack Overflow, Twitter, et Reddit.

**Caractéristiques clés :**

- **Performance** : Capable de gérer des millions de connexions simultanées
- **Fiabilité** : Conçu pour fonctionner 24/7 sans interruption
- **Flexibilité** : Support TCP (Layer 4) et HTTP (Layer 7)
- **Sécurité** : Protection DDoS, WAF basique, terminaison SSL/TLS
- **Observabilité** : Statistiques détaillées, logs, métriques Prometheus

### 1.2 Positionnement dans l'infrastructure

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└─────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                    ┌───────────────────────────────┐
                    │         FIREWALL / WAF        │
                    └───────────────────────────────┘
                                    │
                                    ▼
            ┌───────────────────────────────────────────────┐
            │                   HAProxy                      │
            │            (Load Balancer / Proxy)            │
            │                                               │
            │  • Terminaison SSL/TLS                       │
            │  • Répartition de charge                     │
            │  • Health checks                             │
            │  • Rate limiting                             │
            │  • Routing applicatif                        │
            └───────────────────────────────────────────────┘
                    │               │               │
                    ▼               ▼               ▼
            ┌───────────┐   ┌───────────┐   ┌───────────┐
            │  Server 1 │   │  Server 2 │   │  Server 3 │
            │  (Active) │   │  (Active) │   │  (Standby)│
            └───────────┘   └───────────┘   └───────────┘
```

### 1.3 Modes de fonctionnement

| Mode | Couche OSI | Cas d'usage |
|------|------------|-------------|
| **TCP (Layer 4)** | Transport | Bases de données, SMTP, LDAP, tout protocole TCP |
| **HTTP (Layer 7)** | Application | Applications web, API REST, microservices |

---

## 2. Architecture et Concepts

### 2.1 Structure de configuration HAProxy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    STRUCTURE DE CONFIGURATION                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  GLOBAL                                                              │  │
│   │  Paramètres globaux du processus HAProxy                            │  │
│   │  • Logs, utilisateur, chroot, tuning performance                    │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │  DEFAULTS                                                            │  │
│   │  Valeurs par défaut pour frontends et backends                      │  │
│   │  • Timeouts, mode, options communes                                 │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
│                                    │                                        │
│   ┌──────────────────────┐        │        ┌──────────────────────┐       │
│   │      FRONTEND        │        │        │      FRONTEND        │       │
│   │  Point d'entrée      │        │        │  Point d'entrée      │       │
│   │  • Bind (IP:port)    │        │        │  • Bind (IP:port)    │       │
│   │  • ACL               │        │        │  • ACL               │       │
│   │  • use_backend       │        │        │  • use_backend       │       │
│   └──────────┬───────────┘        │        └──────────┬───────────┘       │
│              │                    │                    │                    │
│              ▼                    ▼                    ▼                    │
│   ┌──────────────────────┐ ┌──────────────────────┐ ┌──────────────────┐  │
│   │      BACKEND         │ │      BACKEND         │ │    BACKEND       │  │
│   │  Groupe de serveurs  │ │  Groupe de serveurs  │ │ Groupe serveurs  │  │
│   │  • server 1          │ │  • server A          │ │ • server X       │  │
│   │  • server 2          │ │  • server B          │ │ • server Y       │  │
│   │  • balance algorithm │ │  • balance algorithm │ │ • health check   │  │
│   └──────────────────────┘ └──────────────────────┘ └──────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Algorithmes de répartition de charge

| Algorithme | Description | Cas d'usage PS/PCA |
|------------|-------------|-------------------|
| **roundrobin** | Distribution circulaire | Standard, serveurs homogènes |
| **leastconn** | Vers le serveur le moins chargé | Connexions longues (DB, WebSocket) |
| **source** | Hash IP source (sticky) | Sessions non partagées |
| **uri** | Hash de l'URI | Cache distribué |
| **first** | Premier serveur disponible | Active/Passive failover |
| **random** | Aléatoire pondéré | Distribution uniforme |

### 2.3 Health Checks

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TYPES DE HEALTH CHECKS                              │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  LAYER 4 (TCP)                                                             │
│  ├── Connexion TCP réussie = serveur UP                                    │
│  └── check inter 2000 fall 3 rise 2                                        │
│       │         │       │      │                                           │
│       │         │       │      └── 2 checks OK pour remonter               │
│       │         │       └── 3 échecs pour déclarer DOWN                    │
│       │         └── Intervalle 2 secondes                                  │
│       └── Activer le check                                                 │
│                                                                             │
│  LAYER 7 (HTTP)                                                            │
│  ├── Requête HTTP + validation réponse                                     │
│  ├── option httpchk GET /health HTTP/1.1                                   │
│  └── http-check expect status 200                                          │
│                                                                             │
│  AVANCÉ                                                                     │
│  ├── agent-check : Agent externe sur le serveur                           │
│  ├── mysql-check : Protocole MySQL natif                                  │
│  ├── pgsql-check : Protocole PostgreSQL natif                             │
│  └── ldap-check : Protocole LDAP natif                                    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.4 États des serveurs

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ÉTATS DES SERVEURS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────┐  Health Check OK   ┌─────┐                                        │
│  │ UP  │ ◄────────────────► │DOWN │                                        │
│  └──┬──┘  Health Check FAIL └──┬──┘                                        │
│     │                          │                                            │
│     │ disable server           │ enable server                              │
│     ▼                          ▼                                            │
│  ┌─────────┐              ┌─────────┐                                      │
│  │  MAINT  │              │ DRAIN   │ ◄── Arrêt gracieux                   │
│  └─────────┘              └─────────┘     (nouvelles connexions refusées)  │
│                                                                             │
│  Commandes Runtime API:                                                    │
│  • disable server backend/server1                                          │
│  • enable server backend/server1                                           │
│  • set server backend/server1 state drain                                  │
│  • set server backend/server1 weight 0                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 3. HAProxy et les Enjeux PS/PCA

### 3.1 Rôle dans la continuité d'activité

HAProxy est un composant critique pour le PS/PCA car il assure :

1. **Élimination des SPOF** : Répartition sur plusieurs serveurs
2. **Détection automatique des pannes** : Health checks
3. **Basculement transparent** : Failover sans intervention
4. **Maintenance sans interruption** : Drain et rolling updates
5. **Protection contre les surcharges** : Rate limiting, queuing

### 3.2 Architectures haute disponibilité

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ARCHITECTURE 1 : ACTIVE/PASSIVE                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                         VIP: 192.168.1.100                                 │
│                              │                                              │
│               ┌──────────────┴──────────────┐                              │
│               │         Keepalived          │                              │
│               │      (VRRP Protocol)        │                              │
│               └──────────────┬──────────────┘                              │
│                              │                                              │
│         ┌────────────────────┼────────────────────┐                        │
│         │                    │                    │                         │
│         ▼                    │                    ▼                         │
│   ┌───────────┐              │             ┌───────────┐                   │
│   │  HAProxy  │              │             │  HAProxy  │                   │
│   │  MASTER   │◄─────────────┴────────────►│  BACKUP   │                   │
│   │           │         VRRP               │           │                   │
│   │ 192.168.1.10          Heartbeat        │ 192.168.1.11                  │
│   └─────┬─────┘                            └─────┬─────┘                   │
│         │                                        │                          │
│         └────────────┬───────────────────────────┘                         │
│                      │                                                      │
│         ┌────────────┼────────────┐                                        │
│         ▼            ▼            ▼                                         │
│     [Server1]    [Server2]    [Server3]                                    │
│                                                                             │
│  Avantages: Simple, IP flottante unique                                    │
│  RPO: 0 | RTO: 1-3 secondes (failover VRRP)                               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                    ARCHITECTURE 2 : ACTIVE/ACTIVE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                              DNS                                            │
│                    app.example.com                                          │
│                    ┌─────┴─────┐                                           │
│                    │ A: IP1    │                                           │
│                    │ A: IP2    │                                           │
│                    └─────┬─────┘                                           │
│                          │                                                  │
│         ┌────────────────┼────────────────┐                                │
│         ▼                                 ▼                                 │
│   ┌───────────┐                    ┌───────────┐                           │
│   │  HAProxy  │                    │  HAProxy  │                           │
│   │  NODE 1   │                    │  NODE 2   │                           │
│   │  ACTIVE   │                    │  ACTIVE   │                           │
│   │  IP1      │                    │  IP2      │                           │
│   └─────┬─────┘                    └─────┬─────┘                           │
│         │                                │                                  │
│         └────────────┬───────────────────┘                                 │
│                      │                                                      │
│         ┌────────────┼────────────┐                                        │
│         ▼            ▼            ▼                                         │
│     [Server1]    [Server2]    [Server3]                                    │
│                                                                             │
│  Avantages: Capacité doublée, pas de ressource inactive                   │
│  Inconvénient: Sessions sticky à gérer                                    │
│  RPO: 0 | RTO: ~30s (TTL DNS)                                             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3.3 Métriques PS/PCA avec HAProxy

| Scénario | Sans HAProxy | Avec HAProxy (bien configuré) |
|----------|--------------|------------------------------|
| Panne 1 serveur applicatif | Interruption service | RTO = 0 (transparent) |
| Panne HAProxy (sans HA) | Interruption totale | N/A |
| Panne HAProxy (avec Keepalived) | N/A | RTO = 1-3 secondes |
| Maintenance serveur | Interruption planifiée | RTO = 0 (drain) |
| Pic de charge | Saturation/crash | Queue + rate limiting |
| Attaque DDoS | Service indisponible | Protection L4/L7 |

### 3.4 Scénarios de failover

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    SCÉNARIOS DE FAILOVER                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SCÉNARIO 1 : Panne serveur backend                                        │
│  ─────────────────────────────────────                                     │
│  T+0s    : Server2 ne répond plus au health check                         │
│  T+2s    : 1er check échoué (inter 2000)                                  │
│  T+4s    : 2ème check échoué                                              │
│  T+6s    : 3ème check échoué → Server2 marqué DOWN (fall 3)               │
│  T+6s    : Trafic redirigé vers Server1 et Server3                        │
│  Impact  : Aucun pour les utilisateurs (connections existantes OK)        │
│                                                                             │
│  SCÉNARIO 2 : Maintenance planifiée                                        │
│  ─────────────────────────────────────                                     │
│  T+0s    : Admin: set server backend/server2 state drain                  │
│  T+0s    : Nouvelles connexions vers autres serveurs                      │
│  T+Xs    : Attente fin des connexions existantes                          │
│  T+Xs    : Admin effectue la maintenance                                   │
│  T+Ys    : Admin: set server backend/server2 state ready                  │
│  T+Ys    : Server2 réintègre le pool après health check OK                │
│  Impact  : Aucun                                                           │
│                                                                             │
│  SCÉNARIO 3 : Panne HAProxy primaire (avec Keepalived)                    │
│  ─────────────────────────────────────                                     │
│  T+0s    : HAProxy Master crash                                           │
│  T+1s    : Keepalived détecte la panne (check haproxy process)            │
│  T+2s    : VRRP Advertisement timeout                                      │
│  T+3s    : HAProxy Backup devient Master, prend la VIP                    │
│  Impact  : Connexions TCP en cours perdues, nouvelles OK                  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 4. TP1 : Installation et Configuration de Base

### 4.1 Architecture du lab

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ARCHITECTURE LAB TP1                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                        Docker Network: haproxy-net                          │
│                              172.20.0.0/16                                  │
│                                                                             │
│                         ┌────────────────────┐                             │
│                         │      HAProxy       │                             │
│                         │    172.20.0.10     │                             │
│                         │                    │                             │
│                         │  :80  → HTTP       │                             │
│                         │  :443 → HTTPS      │                             │
│                         │  :8404 → Stats     │                             │
│                         └─────────┬──────────┘                             │
│                                   │                                         │
│              ┌────────────────────┼────────────────────┐                   │
│              │                    │                    │                    │
│              ▼                    ▼                    ▼                    │
│      ┌──────────────┐    ┌──────────────┐    ┌──────────────┐             │
│      │    web1      │    │    web2      │    │    web3      │             │
│      │ 172.20.0.21  │    │ 172.20.0.22  │    │ 172.20.0.23  │             │
│      │   nginx      │    │   nginx      │    │   nginx      │             │
│      └──────────────┘    └──────────────┘    └──────────────┘             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4.2 Configuration de base expliquée

```haproxy
# =============================================================================
# CONFIGURATION HAPROXY - FORMATION PS/PCA
# =============================================================================

# -----------------------------------------------------------------------------
# SECTION GLOBAL
# Paramètres du processus HAProxy
# -----------------------------------------------------------------------------
global
    # Logging vers syslog
    log stdout format raw local0 info
    
    # Sécurité : chroot et utilisateur non-root
    # chroot /var/lib/haproxy
    # user haproxy
    # group haproxy
    
    # Performance : nombre de connexions max
    maxconn 50000
    
    # SSL/TLS : paramètres par défaut
    ssl-default-bind-ciphersuites TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384
    ssl-default-bind-options ssl-min-ver TLSv1.2 no-tls-tickets
    
    # Runtime API (pour administration dynamique)
    stats socket /var/run/haproxy.sock mode 660 level admin
    stats timeout 30s

# -----------------------------------------------------------------------------
# SECTION DEFAULTS
# Valeurs par défaut pour tous les frontends/backends
# -----------------------------------------------------------------------------
defaults
    mode http                          # Mode HTTP (Layer 7)
    log global                         # Utiliser la config log globale
    
    # Options HTTP
    option httplog                     # Logs détaillés HTTP
    option dontlognull                 # Ne pas logger les health checks
    option http-server-close           # Fermer connexion serveur après réponse
    option forwardfor except 127.0.0.0/8   # Ajouter X-Forwarded-For
    option redispatch                  # Réessayer sur autre serveur si échec
    
    # Timeouts (CRITIQUES pour la stabilité)
    timeout connect 5s                 # Timeout connexion vers backend
    timeout client  30s                # Timeout inactivité client
    timeout server  30s                # Timeout inactivité serveur
    timeout http-request 10s           # Timeout réception requête HTTP
    timeout http-keep-alive 10s        # Timeout keep-alive
    timeout queue 60s                  # Timeout file d'attente
    
    # Retries
    retries 3                          # Nombre de tentatives avant échec
    
    # Comportement erreur
    errorfile 400 /etc/haproxy/errors/400.http
    errorfile 403 /etc/haproxy/errors/403.http
    errorfile 408 /etc/haproxy/errors/408.http
    errorfile 500 /etc/haproxy/errors/500.http
    errorfile 502 /etc/haproxy/errors/502.http
    errorfile 503 /etc/haproxy/errors/503.http
    errorfile 504 /etc/haproxy/errors/504.http

# -----------------------------------------------------------------------------
# FRONTEND : Point d'entrée HTTP
# -----------------------------------------------------------------------------
frontend http_front
    bind *:80
    
    # Redirection HTTPS (en production)
    # http-request redirect scheme https unless { ssl_fc }
    
    # ACL pour routage
    acl is_api path_beg /api
    acl is_static path_beg /static /images /css /js
    
    # Routage vers backends
    use_backend api_servers if is_api
    use_backend static_servers if is_static
    default_backend web_servers

# -----------------------------------------------------------------------------
# FRONTEND : Point d'entrée HTTPS
# -----------------------------------------------------------------------------
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    
    # Headers sécurité
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    
    # Même logique de routage
    acl is_api path_beg /api
    use_backend api_servers if is_api
    default_backend web_servers

# -----------------------------------------------------------------------------
# FRONTEND : Page de statistiques
# -----------------------------------------------------------------------------
frontend stats
    bind *:8404
    mode http
    stats enable
    stats uri /stats
    stats refresh 10s
    stats auth admin:secure_password_here
    stats admin if TRUE

# -----------------------------------------------------------------------------
# BACKEND : Serveurs Web
# -----------------------------------------------------------------------------
backend web_servers
    balance roundrobin                 # Algorithme de répartition
    
    # Health check HTTP
    option httpchk GET /health HTTP/1.1
    http-check expect status 200
    
    # Sticky sessions (optionnel)
    # cookie SERVERID insert indirect nocache
    
    # Serveurs
    server web1 172.20.0.21:80 check inter 2000 fall 3 rise 2
    server web2 172.20.0.22:80 check inter 2000 fall 3 rise 2
    server web3 172.20.0.23:80 check inter 2000 fall 3 rise 2 backup

# -----------------------------------------------------------------------------
# BACKEND : Serveurs API
# -----------------------------------------------------------------------------
backend api_servers
    balance leastconn                  # Moins de connexions actives
    
    option httpchk GET /api/health HTTP/1.1
    http-check expect status 200
    
    # Timeout plus long pour API
    timeout server 60s
    
    server api1 172.20.0.31:8080 check inter 2000 fall 3 rise 2
    server api2 172.20.0.32:8080 check inter 2000 fall 3 rise 2

# -----------------------------------------------------------------------------
# BACKEND : Serveurs Statiques (cache)
# -----------------------------------------------------------------------------
backend static_servers
    balance uri                        # Même URI → même serveur (cache)
    hash-type consistent               # Cohérence lors ajout/retrait serveur
    
    server static1 172.20.0.41:80 check
    server static2 172.20.0.42:80 check
```

### 4.3 Commandes essentielles

```bash
# Vérifier la syntaxe de la configuration
haproxy -c -f /etc/haproxy/haproxy.cfg

# Démarrer HAProxy
haproxy -f /etc/haproxy/haproxy.cfg

# Rechargement sans interruption (graceful reload)
haproxy -f /etc/haproxy/haproxy.cfg -sf $(pidof haproxy)

# Via systemd (en production)
systemctl reload haproxy

# Voir les statistiques en CLI
echo "show stat" | socat stdio /var/run/haproxy.sock

# Voir les informations générales
echo "show info" | socat stdio /var/run/haproxy.sock

# Désactiver un serveur (maintenance)
echo "disable server web_servers/web1" | socat stdio /var/run/haproxy.sock

# Réactiver un serveur
echo "enable server web_servers/web1" | socat stdio /var/run/haproxy.sock

# Drain (arrêt gracieux)
echo "set server web_servers/web1 state drain" | socat stdio /var/run/haproxy.sock
```

---

## 5. TP2 : Haute Disponibilité et Failover

### 5.1 Architecture HA avec Keepalived

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    ARCHITECTURE HA - KEEPALIVED + HAPROXY                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│                              VIP: 172.20.0.100                             │
│                                    │                                        │
│                    ┌───────────────┴───────────────┐                       │
│                    │                               │                        │
│         ┌──────────┴──────────┐       ┌──────────┴──────────┐             │
│         │    haproxy-master   │       │    haproxy-backup   │             │
│         │    172.20.0.10      │       │    172.20.0.11      │             │
│         │                     │       │                     │             │
│         │  ┌───────────────┐  │       │  ┌───────────────┐  │             │
│         │  │   HAProxy     │  │       │  │   HAProxy     │  │             │
│         │  └───────────────┘  │       │  └───────────────┘  │             │
│         │  ┌───────────────┐  │       │  ┌───────────────┐  │             │
│         │  │  Keepalived   │  │ VRRP  │  │  Keepalived   │  │             │
│         │  │  MASTER       │◄─┼───────┼─►│  BACKUP       │  │             │
│         │  │  Priority 101 │  │       │  │  Priority 100 │  │             │
│         │  └───────────────┘  │       │  └───────────────┘  │             │
│         └─────────────────────┘       └─────────────────────┘             │
│                    │                               │                        │
│                    └───────────────┬───────────────┘                       │
│                                    │                                        │
│              ┌─────────────────────┼─────────────────────┐                 │
│              ▼                     ▼                     ▼                  │
│         [web1]                 [web2]                [web3]                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Configuration Keepalived

```bash
# /etc/keepalived/keepalived.conf (MASTER)

global_defs {
    router_id HAPROXY_MASTER
    script_user root
    enable_script_security
}

# Script de vérification HAProxy
vrrp_script check_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    priority 101
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass secretpassword
    }
    
    virtual_ipaddress {
        172.20.0.100/24
    }
    
    track_script {
        check_haproxy
    }
    
    # Notification scripts
    notify_master "/etc/keepalived/notify.sh master"
    notify_backup "/etc/keepalived/notify.sh backup"
    notify_fault  "/etc/keepalived/notify.sh fault"
}
```

```bash
# /etc/keepalived/keepalived.conf (BACKUP)

global_defs {
    router_id HAPROXY_BACKUP
    script_user root
    enable_script_security
}

vrrp_script check_haproxy {
    script "/usr/bin/killall -0 haproxy"
    interval 2
    weight -20
    fall 3
    rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 51
    priority 100
    advert_int 1
    
    authentication {
        auth_type PASS
        auth_pass secretpassword
    }
    
    virtual_ipaddress {
        172.20.0.100/24
    }
    
    track_script {
        check_haproxy
    }
    
    notify_master "/etc/keepalived/notify.sh master"
    notify_backup "/etc/keepalived/notify.sh backup"
    notify_fault  "/etc/keepalived/notify.sh fault"
}
```

```bash
#!/bin/bash
# /etc/keepalived/notify.sh

STATE=$1
DATETIME=$(date '+%Y-%m-%d %H:%M:%S')

case $STATE in
    master)
        echo "[$DATETIME] Transition to MASTER state" >> /var/log/keepalived-state.log
        # Actions spécifiques : notification, restart services...
        ;;
    backup)
        echo "[$DATETIME] Transition to BACKUP state" >> /var/log/keepalived-state.log
        ;;
    fault)
        echo "[$DATETIME] Transition to FAULT state" >> /var/log/keepalived-state.log
        # Alerting critique
        ;;
esac
```

### 5.3 Tests de failover

```bash
# Test 1 : Arrêt HAProxy sur le master
docker exec haproxy-master pkill haproxy
# Observer : VIP migre vers backup en ~3 secondes

# Test 2 : Arrêt complet du master
docker stop haproxy-master
# Observer : VIP migre vers backup

# Test 3 : Simulation panne réseau
docker network disconnect haproxy-net haproxy-master
# Observer : VIP migre vers backup

# Test 4 : Retour du master
docker start haproxy-master
# Observer : VIP revient sur master (preempt)

# Monitoring continu
watch -n 1 'echo "show stat" | socat stdio /var/run/haproxy.sock | cut -d"," -f1,2,18'
```

### 5.4 Sticky Sessions pour la continuité

```haproxy
backend web_servers
    balance roundrobin
    
    # Option 1 : Cookie applicatif
    cookie SERVERID insert indirect nocache
    server web1 172.20.0.21:80 check cookie web1
    server web2 172.20.0.22:80 check cookie web2
    
    # Option 2 : Sticky table (IP source)
    stick-table type ip size 200k expire 30m
    stick on src
    
    # Option 3 : Sticky sur header/cookie existant
    stick on req.cook(JSESSIONID)
    stick-table type string len 52 size 200k expire 30m
```

---

## 6. TP3 : Sécurisation et Hardening

### 6.1 Terminaison SSL/TLS

```haproxy
frontend https_front
    # Certificat unique
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    
    # Ou certificats multiples (SNI)
    bind *:443 ssl crt /etc/haproxy/certs/ alpn h2,http/1.1
    
    # Force TLS 1.2 minimum
    bind *:443 ssl crt /etc/haproxy/certs/server.pem ssl-min-ver TLSv1.2
    
    # Ciphers sécurisés
    ssl-default-bind-ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256
    
    # HSTS
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
```

### 6.2 Protection contre les attaques

```haproxy
# =============================================================================
# PROTECTION DDOS ET ABUSE
# =============================================================================

frontend http_front
    bind *:80
    
    # --- RATE LIMITING ---
    # Table pour tracking des IPs
    stick-table type ip size 200k expire 5m store http_req_rate(10s),conn_cur,conn_rate(10s)
    
    # Tracker l'IP source
    http-request track-sc0 src
    
    # Bloquer si > 100 requêtes/10s
    http-request deny deny_status 429 if { sc_http_req_rate(0) gt 100 }
    
    # Bloquer si > 20 connexions simultanées
    http-request deny deny_status 429 if { sc_conn_cur(0) gt 20 }
    
    # --- PROTECTION HEADERS ---
    # Bloquer si pas de Host header
    http-request deny deny_status 400 unless { req.hdr(host) -m found }
    
    # Limiter taille des headers
    http-request deny deny_status 431 if { req.fhdr_cnt(any) gt 50 }
    
    # Bloquer User-Agents suspects
    acl bad_ua hdr_sub(User-Agent) -i nikto sqlmap nmap
    http-request deny deny_status 403 if bad_ua
    
    # --- PROTECTION MÉTHODES HTTP ---
    acl valid_method method GET HEAD POST PUT DELETE OPTIONS
    http-request deny deny_status 405 unless valid_method
    
    # --- PROTECTION PATH TRAVERSAL ---
    acl path_traversal path_sub -i ../ ..\
    http-request deny deny_status 403 if path_traversal
    
    # --- PROTECTION SQL INJECTION BASIQUE ---
    acl sql_injection url_sub -i select insert update delete drop union
    http-request deny deny_status 403 if sql_injection

    default_backend web_servers
```

### 6.3 ACL et contrôle d'accès

```haproxy
frontend http_front
    bind *:80
    
    # --- ACL PAR IP ---
    acl internal_network src 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16
    acl admin_ips src 192.168.1.100 192.168.1.101
    
    # --- ACL PAR PATH ---
    acl is_admin path_beg /admin /management
    acl is_api path_beg /api
    acl is_health path /health /ready /live
    
    # --- ACL PAR HEADER ---
    acl has_api_key req.hdr(X-API-Key) -m found
    acl valid_api_key req.hdr(X-API-Key) -m str secretkey123
    
    # --- RÈGLES D'ACCÈS ---
    # Admin uniquement depuis IPs autorisées
    http-request deny deny_status 403 if is_admin !admin_ips
    
    # API requiert clé valide
    http-request deny deny_status 401 if is_api !has_api_key
    http-request deny deny_status 403 if is_api !valid_api_key
    
    # Health checks publics
    use_backend health_backend if is_health
    
    default_backend web_servers
```

### 6.4 Headers de sécurité

```haproxy
frontend https_front
    bind *:443 ssl crt /etc/haproxy/certs/server.pem
    
    # Supprimer headers révélant l'infrastructure
    http-response del-header Server
    http-response del-header X-Powered-By
    
    # Headers de sécurité
    http-response set-header X-Frame-Options "SAMEORIGIN"
    http-response set-header X-Content-Type-Options "nosniff"
    http-response set-header X-XSS-Protection "1; mode=block"
    http-response set-header Referrer-Policy "strict-origin-when-cross-origin"
    http-response set-header Content-Security-Policy "default-src 'self'"
    http-response set-header Permissions-Policy "geolocation=(), microphone=(), camera=()"
    
    # HSTS
    http-response set-header Strict-Transport-Security "max-age=31536000; includeSubDomains"
    
    default_backend web_servers
```

### 6.5 Checklist de sécurité

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    CHECKLIST SÉCURITÉ HAPROXY                               │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  RÉSEAU                                                                     │
│  □ HAProxy dans DMZ ou segment dédié                                       │
│  □ Accès stats/admin restreint par IP                                      │
│  □ Socket runtime protégé (permissions Unix)                               │
│  □ Firewall limitant les ports exposés                                     │
│                                                                             │
│  TLS/SSL                                                                    │
│  □ TLS 1.2 minimum (désactiver SSLv3, TLS 1.0, 1.1)                       │
│  □ Ciphers sécurisés uniquement                                            │
│  □ HSTS activé                                                             │
│  □ Certificats à jour et monitoring expiration                             │
│  □ OCSP stapling activé                                                    │
│                                                                             │
│  PROTECTION APPLICATIVE                                                    │
│  □ Rate limiting configuré                                                 │
│  □ Connexions max par IP                                                   │
│  □ Headers de sécurité (X-Frame-Options, CSP...)                          │
│  □ User-Agents malveillants bloqués                                        │
│  □ Méthodes HTTP restreintes                                               │
│                                                                             │
│  HARDENING SYSTÈME                                                         │
│  □ HAProxy en chroot                                                       │
│  □ Utilisateur non-root dédié                                              │
│  □ Limites ulimit configurées                                              │
│  □ Logs centralisés et surveillés                                          │
│                                                                             │
│  MONITORING                                                                 │
│  □ Métriques exportées (Prometheus)                                        │
│  □ Alertes sur erreurs 5xx                                                 │
│  □ Alertes sur backend DOWN                                                │
│  □ Alertes sur rate limiting déclenché                                     │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 7. TP4 : Monitoring et Observabilité

### 7.1 Page de statistiques

```haproxy
frontend stats
    bind *:8404
    mode http
    
    # Activer les stats
    stats enable
    stats uri /stats
    stats refresh 10s
    
    # Authentification
    stats auth admin:secure_password
    stats auth readonly:viewonly
    
    # Permettre les actions admin
    stats admin if TRUE
    
    # Cacher les infos sensibles
    stats hide-version
    
    # Scope (limiter à certains backends)
    # stats scope web_servers
    # stats scope api_servers
```

### 7.2 Métriques Prometheus

```haproxy
frontend prometheus
    bind *:8405
    mode http
    http-request use-service prometheus-exporter if { path /metrics }
```

```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'haproxy'
    static_configs:
      - targets: ['haproxy:8405']
    metrics_path: /metrics
```

### 7.3 Logging avancé

```haproxy
global
    # Format de log détaillé
    log stdout format raw local0 info
    
defaults
    mode http
    log global
    
    # Log HTTP détaillé
    option httplog
    
    # Format personnalisé
    log-format "%ci:%cp [%tr] %ft %b/%s %TR/%Tw/%Tc/%Tr/%Ta %ST %B %CC %CS %tsc %ac/%fc/%bc/%sc/%rc %sq/%bq %hr %hs %{+Q}r"

# Capture des headers pour debug
frontend http_front
    capture request header Host len 50
    capture request header User-Agent len 100
    capture request header X-Forwarded-For len 50
    capture response header Content-Type len 50
```

### 7.4 Alertes et seuils

```yaml
# alertmanager rules pour HAProxy (Prometheus)
groups:
  - name: haproxy
    rules:
      # Alerte si backend DOWN
      - alert: HAProxyBackendDown
        expr: haproxy_backend_up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "HAProxy backend {{ $labels.backend }} is down"
          
      # Alerte si trop d'erreurs 5xx
      - alert: HAProxyHighError5xxRate
        expr: rate(haproxy_backend_http_responses_total{code="5xx"}[5m]) > 10
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High 5xx error rate on {{ $labels.backend }}"
          
      # Alerte si queue backend trop longue
      - alert: HAProxyHighQueueLength
        expr: haproxy_backend_current_queue > 100
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "High queue length on {{ $labels.backend }}"
          
      # Alerte si connexions saturées
      - alert: HAProxyHighConnectionRate
        expr: haproxy_frontend_current_sessions / haproxy_frontend_limit_sessions > 0.8
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Frontend {{ $labels.frontend }} approaching connection limit"
```

### 7.5 Script de monitoring PS/PCA

```bash
#!/bin/bash
# haproxy-health-check.sh
# Script de vérification santé pour PS/PCA

HAPROXY_SOCKET="/var/run/haproxy.sock"
ALERT_EMAIL="admin@example.com"
LOG_FILE="/var/log/haproxy-monitor.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a $LOG_FILE
}

alert() {
    log "ALERT: $1"
    echo "$1" | mail -s "HAProxy Alert" $ALERT_EMAIL
}

# Vérifier que HAProxy répond
check_haproxy_process() {
    if ! pgrep -x haproxy > /dev/null; then
        alert "HAProxy process not running!"
        return 1
    fi
    return 0
}

# Vérifier les backends
check_backends() {
    local stats=$(echo "show stat" | socat stdio $HAPROXY_SOCKET 2>/dev/null)
    
    if [ -z "$stats" ]; then
        alert "Cannot connect to HAProxy socket"
        return 1
    fi
    
    # Vérifier chaque backend
    echo "$stats" | grep -E "^[^#]" | while IFS=',' read -r pxname svname status rest; do
        if [ "$svname" != "FRONTEND" ] && [ "$svname" != "BACKEND" ]; then
            if [ "$status" = "DOWN" ]; then
                log "WARNING: Server $pxname/$svname is DOWN"
            fi
        fi
    done
}

# Vérifier les métriques
check_metrics() {
    local info=$(echo "show info" | socat stdio $HAPROXY_SOCKET 2>/dev/null)
    
    # Connexions actuelles
    local curr_conn=$(echo "$info" | grep "CurrConns:" | cut -d: -f2 | tr -d ' ')
    local max_conn=$(echo "$info" | grep "Maxconn:" | cut -d: -f2 | tr -d ' ')
    
    if [ -n "$curr_conn" ] && [ -n "$max_conn" ]; then
        local usage=$((curr_conn * 100 / max_conn))
        if [ $usage -gt 80 ]; then
            alert "Connection usage at ${usage}% (${curr_conn}/${max_conn})"
        fi
        log "Connections: ${curr_conn}/${max_conn} (${usage}%)"
    fi
}

# Main
main() {
    log "=== HAProxy Health Check Started ==="
    
    check_haproxy_process || exit 1
    check_backends
    check_metrics
    
    log "=== Health Check Completed ==="
}

main
```

---

## 8. Annexes et Références

### 8.1 Commandes Runtime API essentielles

```bash
# Connexion au socket
socat stdio /var/run/haproxy.sock

# Statistiques
echo "show stat" | socat stdio /var/run/haproxy.sock
echo "show stat -1 4 -1" | socat stdio /var/run/haproxy.sock  # Format CSV

# Informations générales
echo "show info" | socat stdio /var/run/haproxy.sock

# Gestion des serveurs
echo "disable server backend/server1" | socat stdio /var/run/haproxy.sock
echo "enable server backend/server1" | socat stdio /var/run/haproxy.sock
echo "set server backend/server1 state drain" | socat stdio /var/run/haproxy.sock
echo "set server backend/server1 state ready" | socat stdio /var/run/haproxy.sock
echo "set server backend/server1 weight 50" | socat stdio /var/run/haproxy.sock

# Sessions
echo "show sess" | socat stdio /var/run/haproxy.sock
echo "shutdown sessions server backend/server1" | socat stdio /var/run/haproxy.sock

# Tables de stick
echo "show table" | socat stdio /var/run/haproxy.sock
echo "show table web_servers" | socat stdio /var/run/haproxy.sock
echo "clear table web_servers" | socat stdio /var/run/haproxy.sock

# Erreurs
echo "show errors" | socat stdio /var/run/haproxy.sock

# Maps (pour ACL dynamiques)
echo "show map" | socat stdio /var/run/haproxy.sock
echo "add map /etc/haproxy/blocked_ips.map 1.2.3.4 blocked" | socat stdio /var/run/haproxy.sock
```

### 8.2 Timeouts expliqués

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         TIMEOUTS HAPROXY                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Client ──────────────────── HAProxy ──────────────────── Backend          │
│                                                                             │
│  │                           │                            │                 │
│  │◄─── timeout client ──────►│                            │                 │
│  │     (inactivité client)   │                            │                 │
│  │                           │                            │                 │
│  │                           │◄── timeout connect ───────►│                 │
│  │                           │    (établissement TCP)     │                 │
│  │                           │                            │                 │
│  │                           │◄─── timeout server ───────►│                 │
│  │                           │     (inactivité serveur)   │                 │
│  │                           │                            │                 │
│  │                           │                            │                 │
│  │◄───────── timeout http-request ─────────►│             │                 │
│  │           (réception requête HTTP)       │             │                 │
│  │                           │                            │                 │
│  │◄───────── timeout http-keep-alive ──────►│             │                 │
│  │           (entre requêtes keep-alive)    │             │                 │
│  │                           │                            │                 │
│  │                           │◄── timeout queue ─────────►│                 │
│  │                           │    (attente en file)       │                 │
│  │                           │                            │                 │
│  │◄─────────────── timeout tunnel ─────────────────────────────────────►   │
│  │                 (pour WebSocket/tunnel après upgrade)                   │
│                                                                             │
│  Recommandations PS/PCA:                                                   │
│  • timeout connect: 5s (éviter attente trop longue vers backend mort)     │
│  • timeout client: 30-60s (selon application)                              │
│  • timeout server: 30-60s (selon temps de réponse backend)                │
│  • timeout http-request: 10s (protection slowloris)                       │
│  • timeout queue: 60s (éviter pertes en cas de pic)                       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 8.3 Algorithmes de load balancing détaillés

| Algorithme | Sticky | Distribution | Cas d'usage |
|------------|--------|--------------|-------------|
| `roundrobin` | Non | Circulaire avec poids | Défaut, serveurs stateless |
| `static-rr` | Non | Circulaire fixe | Quand ordre prévisible requis |
| `leastconn` | Non | Moins de connexions | Connexions longues (DB, WS) |
| `first` | Non | Premier disponible | Active/Passive strict |
| `source` | Oui | Hash IP source | Sessions sans cookie |
| `uri` | Oui | Hash URI | Cache distribué |
| `url_param` | Oui | Hash paramètre URL | Routing applicatif |
| `hdr` | Oui | Hash header HTTP | Routing par tenant |
| `rdp-cookie` | Oui | Cookie RDP | Terminal Server |
| `random` | Non | Aléatoire pondéré | Distribution uniforme |

### 8.4 Ressources

**Documentation officielle :**
- https://www.haproxy.org/
- https://docs.haproxy.org/

**Configuration de référence :**
- https://github.com/haproxy/haproxy/tree/master/examples

**Communauté :**
- Discourse : https://discourse.haproxy.org/
- GitHub : https://github.com/haproxy/haproxy

---

## Évaluation

### QCM de validation

1. Quel algorithme de load balancing est recommandé pour des connexions WebSocket longues ?
   - a) roundrobin
   - b) leastconn ✓
   - c) source
   - d) first

2. Que fait la commande `set server backend/web1 state drain` ?
   - a) Supprime le serveur
   - b) Redémarre le serveur
   - c) Refuse les nouvelles connexions mais termine les existantes ✓
   - d) Force l'arrêt immédiat

3. Quel protocole utilise Keepalived pour la haute disponibilité ?
   - a) HSRP
   - b) VRRP ✓
   - c) CARP
   - d) BGP

4. Quel timeout protège contre les attaques Slowloris ?
   - a) timeout connect
   - b) timeout client
   - c) timeout http-request ✓
   - d) timeout server

5. Quel est le RTO typique lors d'un failover HAProxy avec Keepalived ?
   - a) 0 seconde
   - b) 1-3 secondes ✓
   - c) 30 secondes
   - d) 5 minutes

6. Quelle ACL bloque les requêtes avec plus de 100 req/10s depuis une même IP ?
   - a) `http-request deny if { src_conn_rate gt 100 }`
   - b) `http-request deny if { sc_http_req_rate(0) gt 100 }` ✓
   - c) `http-request deny if { fe_conn gt 100 }`
   - d) `http-request deny if { be_conn gt 100 }`

---

**Fin du cours**

*Document créé pour la formation PS/PCA Cybersécurité*
