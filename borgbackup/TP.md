# TP Sauvegarde

**Mise en place d’un système de sauvegarde sécurisé pour l’application Ghostfolio avec BorgBackup**

Application cible :
[https://github.com/ghostfolio/ghostfolio](https://github.com/ghostfolio/ghostfolio)

---

# 1. Scénario professionnel

Votre entreprise utilise Ghostfolio pour gérer des données financières internes.
Ces données sont considérées comme sensibles.
La direction cybersécurité vous demande de concevoir un système de sauvegarde répondant aux exigences suivantes :

* Externalisation des sauvegardes sur un serveur dédié.
* Chiffrement obligatoire côté client.
* Isolation complète entre l’application et le serveur de sauvegarde.
* Possibilité de restaurer après un incident majeur (corruption, ransomware).
* Processus automatisé et documenté.
* Respect des bonnes pratiques opérationnelles en cybersécurité.

Vous devez produire un système **fonctionnel** et une **documentation professionnelle**.

---

# 2. Environnement imposé

L’ensemble du projet doit être réalisé dans Docker.
L’architecture minimale doit inclure :

* un conteneur Ghostfolio (application)
* un conteneur PostgreSQL (base)
* un conteneur borg-client
* un conteneur borg-server


# 3. Contraintes générales du TP

1. Aucun mot de passe ne doit apparaître en clair dans un fichier versionné.
2. Le serveur de sauvegarde ne doit jamais avoir accès direct aux données de l’application.
3. L’application doit pouvoir être détruite et restaurée intégralement.
4. Le système doit continuer de fonctionner si le conteneur Ghostfolio est réinstallé.
5. Le serveur de sauvegarde doit être isolé (réseau ou permissions).
6. Il doit exister un plan de rétention documenté pour les sauvegardes.
7. Toutes les actions doivent être reproductibles et documentées.


## Étape 1. Mise en place de l’application Ghostfolio

## Étape 2. Conception de l’architecture de sauvegarde

## Étape 3. Mise en place du serveur borg-server

## Étape 4. Mise en place du conteneur borg-client

## Étape 5. Exécution d’une sauvegarde complète 

## Étape 6. Scénario d’attaque (simulation)

Scénario :

Un ransomware a chiffré les données Ghostfolio.
L’application est inutilisable.

## Étape 7. Restauration complète

## Étape 8. Mise en place de la rotation et automatisation

## Étape 9. Sauvegarder la configuration bogBackup dans un cluser minio

