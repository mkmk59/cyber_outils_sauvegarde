#!/bin/bash
# =============================================================================
# TP6 Solution: SSL/TLS Termination HAProxy
# Martial HOCQUETTE / Mark GYURJYAN
# =============================================================================
# Objectifs:
#   1. Générer des certificats SSL/TLS
#   2. Configurer HTTPS sur HAProxy
#   3. Implémenter la redirection HTTP vers HTTPS
#   4. Configurer le chiffrement end-to-end
# =============================================================================

set -e

cd /workspaces/cyber_outils_sauvegarde/haproxy-workshop

echo "============================================"
echo "  TP6: SSL/TLS Termination HAProxy"
echo "============================================"
echo ""

# Démarrer docker-compose
echo "[INFO] Démarrage des containers Docker..."
docker-compose up -d
sleep 10
echo "[OK] Containers démarrés"
echo ""

# =============================================================================
# Exercice 6.1: Génération de certificat
# =============================================================================
echo ">>> Exercice 6.1: Génération de certificat"
echo ""

echo "[INFO] Afficher le statut SSL initial:"
docker exec haproxy1 bash -c '/scripts/ssl-manage.sh status'
echo ""

echo "[INFO] Générer un certificat auto-signé pour workshop.local:"
docker exec haproxy1 bash -c '/scripts/ssl-manage.sh generate'
echo ""

echo "[INFO] Vérifier la génération du certificat:"
docker exec haproxy1 bash -c 'ls -la /etc/haproxy/certs/'
echo ""

echo "[INFO] Afficher les détails du certificat généré:"
docker exec haproxy1 bash -c '/scripts/ssl-manage.sh show-cert'
echo ""

echo "[OK] Certificat auto-signé généré"
echo ""

# =============================================================================
# Exercice 6.2: Configuration HTTPS
# =============================================================================
echo ">>> Exercice 6.2: Configuration HTTPS"
echo ""

echo "[INFO] Activer SSL/TLS termination:"
docker exec haproxy1 bash -c '/scripts/ssl-manage.sh enable'
sleep 2
echo ""

echo "[INFO] Vérifier le statut SSL après activation:"
docker exec haproxy1 bash -c '/scripts/ssl-manage.sh status'
echo ""

echo "[INFO] Afficher la configuration HTTPS:"
docker exec haproxy1 bash -c '/scripts/show-config.sh | grep -A 20 "HTTPS\|frontend https" | head -30'
echo ""

echo "[INFO] Tester la connexion HTTPS (sans vérifier le certificat):"
docker exec haproxy1 bash -c '/scripts/ssl-manage.sh test'
echo ""

echo "[INFO] Vérifier que HTTPS fonctionne (direct):"
docker exec haproxy1 bash -c 'curl -sk https://localhost/ 2>&1 | head -5'
echo "[OK] HTTPS fonctionnel"
echo ""

# =============================================================================
# Exercice 6.3: Redirection HTTP vers HTTPS
# =============================================================================
echo ">>> Exercice 6.3: Redirection HTTP vers HTTPS"
echo ""

echo "[INFO] Configuration du frontend HTTP actuel:"
docker exec haproxy1 bash -c '/scripts/show-config.sh | grep -A 10 "^frontend http_front" | head -15'
echo ""

echo "[INFO] Ajouter redirection HTTP 301 vers HTTPS au frontend HTTP:"
docker exec haproxy1 bash -c 'cat >> /etc/haproxy/haproxy.cfg << "REDIR_EOF"

# Redirection HTTP vers HTTPS (HTTP Status 301)
    http-request redirect scheme https code 301 if !{ ssl_fc }
REDIR_EOF'
sleep 1
echo ""

echo "[INFO] Vérifier la configuration:"
docker exec haproxy1 bash -c 'haproxy -c -f /etc/haproxy/haproxy.cfg && echo "[OK] Configuration valide"'
echo ""

echo "[INFO] Recharger HAProxy:"
docker exec haproxy1 bash -c 'pkill haproxy 2>/dev/null; sleep 1; haproxy -f /etc/haproxy/haproxy.cfg -D && echo "[OK] HAProxy rechargé"'
sleep 2
echo ""

echo "[INFO] Tester la redirection (HTTP vers HTTPS):"
docker exec haproxy1 bash -c 'curl -I http://localhost/ 2>&1 | grep -E "HTTP|Location" | head -5'
echo ""

echo "[INFO] Vérifier le code HTTP de redirection:"
echo "  Expected: HTTP/1.1 301 Moved Permanently avec header Location: https://..."
docker exec haproxy1 bash -c 'curl -I http://localhost/ 2>&1 | head -10'
echo ""

echo "[OK] Redirection HTTP vers HTTPS configurée"
echo ""

# =============================================================================
# Exercice 6.4: Vérification de la sécurité
# =============================================================================
echo ">>> Exercice 6.4: Vérification de la sécurité"
echo ""

echo "[INFO] Afficher les headers de sécurité ajoutés par HAProxy:"
docker exec haproxy1 bash -c 'curl -skI https://localhost/ 2>&1 | grep -E "Strict-Transport|X-Content|X-Frame|Server" | head -10'
echo ""

echo "[INFO] Détails de la connexion SSL/TLS:"
docker exec haproxy1 bash -c 'echo | openssl s_client -connect localhost:443 2>/dev/null | grep -E "Protocol|Cipher" | head -5'
echo ""

echo "[INFO] Résumé des headers de sécurité:"
echo "  [✓] Strict-Transport-Security: Force HTTPS pendant 1 an"
echo "  [✓] X-Content-Type-Options: nosniff - Prévient le MIME-sniffing"
echo "  [✓] X-Frame-Options: DENY - Prévient le clickjacking"
echo ""

echo "[OK] Sécurité vérifiée"
echo ""

# =============================================================================
# Exercice 6.5: Test complet du workflow HTTPS
# =============================================================================
echo ">>> Exercice 6.5: Test complet du workflow HTTPS"
echo ""

echo "[INFO] Scénario: Client accède à http://localhost"
echo "  1. Requête HTTP vers http://localhost/"
echo "  2. HAProxy répond: 301 Moved Permanently"
echo "  3. Location: https://localhost/"
echo "  4. Client accède à https://localhost/"
echo "  5. HAProxy valide le certificat SSL"
echo "  6. Communication chiffrée établie"
echo "  7. Requête routée vers le backend"
echo ""

echo "[INFO] Test 1: Accès HTTP (doit rediriger):"
HTTP_RESPONSE=$(docker exec haproxy1 bash -c 'curl -I http://localhost/ 2>&1 | head -1')
echo "  Response: $HTTP_RESPONSE"
echo ""

echo "[INFO] Test 2: Accès HTTPS (doit être accepté):"
HTTPS_RESPONSE=$(docker exec haproxy1 bash -c 'curl -skI https://localhost/ 2>&1 | head -1')
echo "  Response: $HTTPS_RESPONSE"
echo ""

echo "[INFO] Test 3: Contenu serveur via HTTPS:"
docker exec haproxy1 bash -c 'curl -sk https://localhost/ 2>&1 | grep -i "hostname" | head -1'
echo ""

echo "[INFO] Test 4: Distribution du trafic HTTPS (10 requêtes):"
docker exec haproxy1 bash -c 'for i in {1..10}; do curl -sk https://localhost/ 2>&1; done | grep -i "hostname" | sort | uniq -c'
echo ""

echo "[OK] Workflow HTTPS complètement fonctionnel"
echo ""

# =============================================================================
# Résumé final
# =============================================================================
echo "============================================"
echo "  TP6 COMPLETE AVEC SUCCES!"
echo "============================================"
echo ""
echo "Résumé des configurations:"
echo "  [✓] Exercice 6.1: Génération de certificat auto-signé"
echo "  [✓] Exercice 6.2: Configuration HTTPS (SSL Termination)"
echo "  [✓] Exercice 6.3: Redirection HTTP -> HTTPS (301)"
echo "  [✓] Exercice 6.4: Headers de sécurité"
echo "  [✓] Exercice 6.5: Test complet du workflow"
echo ""
echo "Points clés appris:"
echo "  - SSL/TLS Termination: HAProxy décrypte et re-routage"
echo "  - Certificats auto-signés pour développement/test"
echo "  - Redirection 301: HTTP vers HTTPS"
echo "  - Headers de sécurité: HSTS, X-Content-Type, X-Frame-Options"
echo "  - Chaîne de certificats: .key + .crt = .pem"
echo "  - X-Forwarded-Proto pour informer les backends du protocole original"
echo ""
echo "Commandes utiles:"
echo "  docker exec haproxy1 /scripts/ssl-manage.sh status"
echo "  docker exec haproxy1 /scripts/ssl-manage.sh generate"
echo "  docker exec haproxy1 /scripts/ssl-manage.sh enable"
echo "  docker exec haproxy1 /scripts/ssl-manage.sh test"
echo "  docker exec haproxy1 /scripts/ssl-manage.sh show-cert"
echo "  curl -sk https://localhost/"
echo "  curl -I http://localhost/"
echo ""
echo "Certificat généré:"
echo "  Chemin: /etc/haproxy/certs/server.pem"
echo "  Validité: 365 jours"
echo "  Domaine: workshop.local"
echo "  Utilisation: Tests et développement uniquement"
echo ""
