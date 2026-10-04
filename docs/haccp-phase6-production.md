# Mise en production — HACCP phase 6 admin/staff

## Fonctionnement

Le dashboard admin/staff affiche une carte HACCP prioritaire pour l'établissement sélectionné.
Elle récupère le statut strict côté serveur et propose directement le parcours HACCP lorsque des
blocages existent. Le statut et la sélection de site sont rechargés séparément ; aucun état local
« prêt » ne peut autoriser une commande.

## Déploiement

1. Déployer l'application avec l'API de phase 4 et vérifier la permission `haccp:read`.
2. Tester un admin, un staff habilité et un staff sans affectation sur deux établissements.
3. Vérifier le changement d'établissement, le rechargement du statut et le bouton
   « Préparer l'ouverture ».
4. Tester les états chargement, erreur API et HACCP bloqué sur mobile et tablette.

## Retour arrière

Revenir à l'ancien bundle frontend ne modifie aucune preuve HACCP ni aucun état serveur. En cas
d'erreur d'affichage, conserver le garde backend et désactiver uniquement la carte frontend via le
déploiement précédent ; ne jamais utiliser l'interface locale pour contourner un blocage.
