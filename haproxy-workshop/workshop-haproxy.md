# Workshop HAProxy - Load Balancing et Haute Disponibilite

## Module PS/PCA - Master Cybersecurite

---

## Introduction

### Objectifs du Workshop

Ce workshop vous permettra de maitriser HAProxy, le load balancer open source de reference, dans un contexte de Plan de Secours (PS) et Plan de Continuite d'Activite (PCA).

A l'issue de ce workshop, vous serez capable de:
- Deployer et configurer HAProxy pour la haute disponibilite
- Implementer differents algorithmes de load balancing
- Configurer des health checks avances
- Mettre en place un cluster HAProxy actif/passif avec Keepalived
- Gerer le SSL/TLS termination
- Surveiller et depanner HAProxy en production
- Implementer des strategies de failover automatique

### Architecture du Lab

```
                                    +------------------+
                                    |   Client/Test    |
                                    +--------+---------+
                                             |
                              +--------------+--------------+
                              |                             |
                    +---------+----------+       +----------+---------+
                    |   HAProxy Master   |       |  HAProxy Backup    |
                    |   (haproxy1)       |       |  (haproxy2)        |
                    |   VIP: 172.30.0.100|       |                    |
                    +---------+----------+       +----------+---------+
                              |                             |
                              +--------------+--------------+
                                             |
              +------------------------------+------------------------------+
              |                              |                              |
    +---------+----------+       +-----------+--------+       +-------------+------+
    |   Backend Web 1    |       |   Backend Web 2    |       |   Backend Web 3    |
    |   (backend1)       |       |   (backend2)       |       |   (backend3)       |
    |   172.30.0.21      |       |   172.30.0.22      |       |   172.30.0.23      |
    +--------------------+       +--------------------+       +--------------------+
```

### Composants

| Composant | Role | IP |
|-----------|------|-----|
| haproxy1 | Load Balancer Master | 172.30.0.11 |
| haproxy2 | Load Balancer Backup | 172.30.0.12 |
| backend1 | Serveur Web 1 | 172.30.0.21 |
| backend2 | Serveur Web 2 | 172.30.0.22 |
| backend3 | Serveur Web 3 | 172.30.0.23 |
| VIP | Virtual IP (Keepalived) | 172.30.0.100 |

---

## Prerequis

### Demarrage de l'environnement

```bash
cd haproxy-workshop
docker-compose up -d
docker-compose ps
```

### Connexion aux containers

```bash
# Connexion au HAProxy master
docker exec -it haproxy1 bash

# Connexion au HAProxy backup
docker exec -it haproxy2 bash

# Connexion aux backends
docker exec -it backend1 bash
```

---

## TP1: Decouverte de HAProxy

### Objectifs
- Comprendre l'architecture de HAProxy
- Decouvrir les fichiers de configuration
- Utiliser les commandes de base

### Exercice 1.1: Verification de l'installation

```bash
# Verifier la version de HAProxy
haproxy -v

# Verifier la configuration
haproxy -c -f /etc/haproxy/haproxy.cfg

# Voir le status du service
/scripts/haproxy-status.sh
```

### Exercice 1.2: Structure de la configuration

La configuration HAProxy est divisee en sections:

```bash
# Afficher la configuration
cat /etc/haproxy/haproxy.cfg
```

**Sections principales:**
- `global`: Parametres globaux du processus
- `defaults`: Valeurs par defaut pour les sections suivantes
- `frontend`: Points d'entree (ports d'ecoute)
- `backend`: Pools de serveurs
- `listen`: Combine frontend et backend

### Exercice 1.3: Acces au dashboard

```bash
# Acceder aux statistiques HAProxy
# URL: http://localhost:8404/stats
# Login: admin / admin

# Ou via curl
curl -u admin:admin http://localhost:8404/stats
```

### Questions TP1
1. Quelle version de HAProxy est installee?
2. Combien de backends sont configures?
3. Quel est le mode de load balancing par defaut?

---

## TP2: Configuration des Frontends

### Objectifs
- Configurer des points d'entree
- Comprendre les ACLs
- Gerer plusieurs services

### Exercice 2.1: Frontend HTTP basique

```bash
# Voir la configuration frontend actuelle
/scripts/show-config.sh frontend

# Tester l'acces HTTP
curl http://localhost:80
```

### Exercice 2.2: Configuration ACL

Les ACLs permettent de router le trafic selon des conditions:

```bash
# Exemple d'ACL dans la configuration
# acl is_api path_beg /api
# acl is_static path_end .css .js .png .jpg

# Tester avec differents chemins
curl http://localhost/api/test
curl http://localhost/static/style.css
```

### Exercice 2.3: Frontend multi-ports

```bash
# Creer un frontend sur un nouveau port
/scripts/frontend-manage.sh create test-frontend 8080

# Lister les frontends
/scripts/frontend-manage.sh list

# Tester le nouveau frontend
curl http://localhost:8080
```

### Exercice 2.4: Rate Limiting

```bash
# Configurer un rate limit sur le frontend cree precedemment
/scripts/frontend-manage.sh set-rate-limit test-frontend 100

# Tester le rate limiting
/scripts/stress-test.sh http://localhost 200
```

---

## TP3: Configuration des Backends

### Objectifs
- Configurer des pools de serveurs
- Comprendre les algorithmes de load balancing
- Gerer les poids des serveurs

### Exercice 3.1: Backend basique

```bash
# Voir la configuration backend actuelle
/scripts/show-config.sh backend

# Verifier l'etat des backends
/scripts/backend-status.sh
```

### Exercice 3.2: Algorithmes de Load Balancing

HAProxy supporte plusieurs algorithmes:

| Algorithme | Description |
|------------|-------------|
| roundrobin | Distribution cyclique (defaut) |
| leastconn | Moins de connexions actives |
| source | Hash de l'IP source (sticky) |
| uri | Hash de l'URI |
| hdr | Hash d'un header HTTP |

```bash
# Changer l'algorithme de load balancing
/scripts/backend-manage.sh set-algorithm web-backend roundrobin
/scripts/backend-manage.sh set-algorithm web-backend leastconn
/scripts/backend-manage.sh set-algorithm web-backend source

# Tester la distribution
for i in {1..10}; do curl -s http://localhost | grep "Backend"; done
```

### Exercice 3.3: Poids des serveurs

```bash
# Voir les poids actuels
/scripts/backend-manage.sh show-weights web-backend

# Modifier le poids d'un serveur (plus de trafic)
/scripts/backend-manage.sh set-weight web-backend backend1 200

# Modifier le poids d'un serveur (moins de trafic)
/scripts/backend-manage.sh set-weight web-backend backend3 50

# Tester la distribution
for i in {1..20}; do curl -s http://localhost | grep "Backend"; done | sort | uniq -c
```

### Exercice 3.4: Ajout/Suppression de serveurs

```bash
# Desactiver un serveur temporairement
/scripts/backend-manage.sh disable web-backend backend2

# Verifier l'etat
/scripts/backend-status.sh

# Reactiver le serveur
/scripts/backend-manage.sh enable web-backend backend2
```

---

## TP4: Health Checks

### Objectifs
- Configurer differents types de health checks
- Comprendre les parametres de detection
- Gerer les serveurs defaillants

### Exercice 4.1: Health Check HTTP

```bash
# Voir la configuration des health checks
/scripts/health-check.sh show

# Configuration type:
# server backend1 172.30.0.21:80 check inter 2s fall 3 rise 2
```

**Parametres:**
- `inter`: Intervalle entre les checks (2s)
- `fall`: Nombre d'echecs avant de marquer DOWN (3)
- `rise`: Nombre de succes avant de marquer UP (2)

### Exercice 4.2: Health Check avance

```bash
# Configurer un health check sur un endpoint specifique
/scripts/health-check.sh set web-backend "/health" 200

# Configurer un health check avec timeout
/scripts/health-check.sh set-timeout web-backend 5s
```

### Exercice 4.3: Simulation de panne

```bash
# Simuler une panne sur backend2
/scripts/simulate-failure.sh backend backend2

# Observer le comportement de HAProxy
/scripts/backend-status.sh

# Tester que le trafic est redirige
for i in {1..5}; do curl -s http://localhost | grep "Backend"; done

# Restaurer le backend
/scripts/simulate-failure.sh recover backend2
```

### Exercice 4.4: Health Check TCP

```bash
# Pour les services non-HTTP
/scripts/health-check.sh set-tcp web-backend 80

# Verifier la configuration
/scripts/health-check.sh show
```

---

## TP5: Sticky Sessions

### Objectifs
- Comprendre la persistance de session
- Configurer differents types de sticky sessions
- Tester la persistence

### Exercice 5.1: Cookie-based Persistence

```bash
# Configurer la persistence par cookie
/scripts/sticky-session.sh enable web-backend cookie SERVERID

# Tester la persistence
curl -c cookies.txt -b cookies.txt http://localhost
curl -c cookies.txt -b cookies.txt http://localhost
curl -c cookies.txt -b cookies.txt http://localhost

# Verifier que c'est toujours le meme backend
```

### Exercice 5.2: Source IP Persistence

```bash
# Configurer la persistence par IP source
/scripts/sticky-session.sh enable web-backend source

# Tester (toujours le meme backend pour une IP)
for i in {1..5}; do curl -s http://localhost | grep "Backend"; done
```

### Exercice 5.3: Table de persistence

```bash
# Voir la table de persistence
/scripts/sticky-session.sh show-table

# Vider la table
/scripts/sticky-session.sh clear-table
```

---

## TP6: SSL/TLS Termination

### Objectifs
- Configurer HTTPS sur HAProxy
- Gerer les certificats
- Implementer le redirect HTTP vers HTTPS

### Exercice 6.1: Generation de certificat

```bash
# Generer un certificat auto-signe
/scripts/ssl-manage.sh generate-cert test.local

# Lister les certificats
/scripts/ssl-manage.sh list
```

### Exercice 6.2: Configuration HTTPS

```bash
# Activer HTTPS sur le frontend
/scripts/ssl-manage.sh enable-https web-frontend test.local

# Tester HTTPS
curl -k https://localhost:443
```

### Exercice 6.3: Redirect HTTP vers HTTPS

```bash
# Configurer la redirection
/scripts/ssl-manage.sh enable-redirect web-frontend

# Tester la redirection
curl -I http://localhost
# Doit retourner: 301 Moved Permanently
```

### Exercice 6.4: SSL Backend

```bash
# Configurer SSL vers les backends (end-to-end)
/scripts/ssl-manage.sh enable-backend-ssl web-backend

# Verifier la configuration
/scripts/show-config.sh ssl
```

---

## TP7: Haute Disponibilite avec Keepalived

### Objectifs
- Comprendre le protocole VRRP
- Configurer Keepalived
- Tester le failover

### Exercice 7.1: Architecture HA

```
+------------------+          +------------------+
|   HAProxy 1      |          |   HAProxy 2      |
|   MASTER         |          |   BACKUP         |
|   Priority: 101  |          |   Priority: 100  |
+--------+---------+          +---------+--------+
         |                              |
         +---------- VIP ---------------+
                  172.30.0.100
```

### Exercice 7.2: Verification Keepalived

```bash
# Sur haproxy1 (master)
/scripts/keepalived-status.sh

# Verifier qui a la VIP
ip addr show | grep 172.30.0.100
```

### Exercice 7.3: Test de failover

```bash
# Depuis un terminal, faire des requetes continues
watch -n 1 "curl -s http://172.30.0.100 | grep -E 'Backend|HAProxy'"

# Dans un autre terminal, arreter HAProxy master
docker stop haproxy1

# Observer le failover vers haproxy2
# La VIP bascule automatiquement

# Redemarrer haproxy1
docker start haproxy1

# Observer le failback
```

### Exercice 7.4: Configuration Keepalived

```bash
# Voir la configuration
cat /etc/keepalived/keepalived.conf

# Modifier la priorite
/scripts/keepalived-manage.sh set-priority 150

# Forcer un failover
/scripts/keepalived-manage.sh failover
```

---

## TP8: Monitoring et Statistiques

### Objectifs
- Utiliser le dashboard de statistiques
- Configurer les metriques
- Analyser les logs

### Exercice 8.1: Dashboard Statistiques

```bash
# Acces au dashboard
# URL: http://localhost:8404/stats

# Informations disponibles:
# - Etat des backends
# - Nombre de connexions
# - Temps de reponse
# - Erreurs
```

### Exercice 8.2: Stats via socket

```bash
# Commandes stats via socket Unix
/scripts/stats.sh show-all
/scripts/stats.sh show-backends
/scripts/stats.sh show-servers web-backend

# Stats detaillees
/scripts/stats.sh info
```

### Exercice 8.3: Metriques Prometheus

```bash
# HAProxy expose des metriques Prometheus
curl http://localhost:8405/metrics

# Metriques cles:
# - haproxy_backend_current_sessions
# - haproxy_backend_http_responses_total
# - haproxy_server_status
```

### Exercice 8.4: Analyse des logs

```bash
# Voir les logs HAProxy
/scripts/logs.sh show

# Filtrer par code HTTP
/scripts/logs.sh filter 500
/scripts/logs.sh filter 404

# Statistiques des logs
/scripts/logs.sh stats
```

---

## TP9: Securite

### Objectifs
- Proteger HAProxy contre les attaques
- Configurer les headers de securite
- Mettre en place le rate limiting

### Exercice 9.1: Headers de securite

```bash
# Ajouter des headers de securite
/scripts/security.sh add-headers web-frontend

# Headers ajoutes:
# - X-Frame-Options
# - X-Content-Type-Options
# - X-XSS-Protection
# - Strict-Transport-Security

# Verifier
curl -I http://localhost
```

### Exercice 9.2: Protection DDoS

```bash
# Configurer la protection DDoS
/scripts/security.sh enable-ddos-protection web-frontend

# Parametres:
# - Rate limit par IP
# - Blocage des IPs suspectes
# - Limite de connexions simultanees

# Tester
/scripts/stress-test.sh http://localhost 500
```

### Exercice 9.3: ACL de securite

```bash
# Bloquer une IP
/scripts/security.sh block-ip 192.168.1.100

# Bloquer un user-agent
/scripts/security.sh block-ua "BadBot"

# Lister les regles
/scripts/security.sh list-rules
```

### Exercice 9.4: Authentification

```bash
# Configurer l'authentification basique
/scripts/security.sh enable-auth web-frontend admin secret123

# Tester
curl http://localhost  # Doit echouer
curl -u admin:secret123 http://localhost  # Doit reussir
```

---

## TP10: Scenario PCA Complet

### Objectifs
- Mettre en pratique tous les concepts
- Simuler un scenario de crise
- Documenter les procedures

### Scenario: Panne majeure et recovery

#### Phase 1: Etat initial

```bash
# Verifier l'etat du cluster
/scripts/haproxy-status.sh
/scripts/backend-status.sh
/scripts/keepalived-status.sh

# Documenter l'etat
/scripts/generate-report.sh > /tmp/etat-initial.txt
```

#### Phase 2: Simulation de crise

```bash
# Simuler la panne de 2 backends
/scripts/simulate-failure.sh backend backend1
/scripts/simulate-failure.sh backend backend2

# Observer l'impact
/scripts/haproxy-status.sh

# Tester que le service reste disponible
curl http://localhost
```

#### Phase 3: Panne du HAProxy master

```bash
# Simuler la panne du master
/scripts/simulate-failure.sh haproxy haproxy1

# Verifier le failover
/scripts/keepalived-status.sh

# Le service doit rester disponible
curl http://172.30.0.100
```

#### Phase 4: Recovery

```bash
# Restaurer les backends
/scripts/simulate-failure.sh recover backend1
/scripts/simulate-failure.sh recover backend2

# Verifier le retour a la normale
/scripts/backend-status.sh

# Restaurer HAProxy master
/scripts/simulate-failure.sh recover haproxy1

# Verifier le failback
/scripts/keepalived-status.sh
```

#### Phase 5: Documentation

```bash
# Generer le rapport d'incident
/scripts/generate-report.sh --incident > /tmp/rapport-incident.txt

# Contenu du rapport:
# - Chronologie
# - Actions effectuees
# - Temps de recovery
# - Recommandations
```

---

## Annexes

### A. Commandes HAProxy utiles

```bash
# Recharger la configuration sans interruption
haproxy -c -f /etc/haproxy/haproxy.cfg && \
  kill -USR2 $(cat /var/run/haproxy.pid)

# Voir les connexions actives
echo "show sess" | socat unix:/var/run/haproxy.sock stdio

# Mettre un serveur en maintenance
echo "set server web-backend/backend1 state maint" | \
  socat unix:/var/run/haproxy.sock stdio

# Remettre un serveur en service
echo "set server web-backend/backend1 state ready" | \
  socat unix:/var/run/haproxy.sock stdio
```

### B. Fichiers de configuration

| Fichier | Description |
|---------|-------------|
| /etc/haproxy/haproxy.cfg | Configuration principale |
| /etc/keepalived/keepalived.conf | Configuration Keepalived |
| /etc/haproxy/certs/ | Repertoire des certificats |
| /var/log/haproxy.log | Logs HAProxy |

### C. Ports utilises

| Port | Service |
|------|---------|
| 80 | HTTP Frontend |
| 443 | HTTPS Frontend |
| 8404 | Stats Dashboard |
| 8405 | Prometheus Metrics |

### D. Troubleshooting

**Probleme: Backend marque DOWN**
```bash
# Verifier la connectivite
curl http://backend1:80/health

# Verifier les logs
/scripts/logs.sh show | grep backend1
```

**Probleme: VIP ne bascule pas**
```bash
# Verifier Keepalived
systemctl status keepalived
journalctl -u keepalived

# Verifier la priorite
/scripts/keepalived-status.sh
```

**Probleme: Erreurs 503**
```bash
# Verifier les backends disponibles
/scripts/backend-status.sh

# Verifier les connexions
/scripts/stats.sh show-servers web-backend
```

---

## Solutions

Les solutions sont disponibles dans le repertoire `/solutions/`:
- `tp1-solutions.sh` - Decouverte
- `tp2-solutions.sh` - Frontends
- `tp3-solutions.sh` - Backends
- `tp4-solutions.sh` - Health Checks
- `tp5-solutions.sh` - Sticky Sessions
- `tp6-solutions.sh` - SSL/TLS
- `tp7-solutions.sh` - Haute Disponibilite
- `tp8-solutions.sh` - Monitoring
- `tp9-solutions.sh` - Securite
- `tp10-solutions.sh` - Scenario PCA

---

## Ressources

- Documentation officielle: https://docs.haproxy.org/
- HAProxy Configuration Manual: https://cbonte.github.io/haproxy-dconv/
- Keepalived Documentation: https://keepalived.readthedocs.io/

---

*Workshop HAProxy - Module PS/PCA - Master Cybersecurite*
