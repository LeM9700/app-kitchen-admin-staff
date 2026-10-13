# Mise en production - Menus admin phase 5

Ce guide concerne uniquement l'interface admin de creation et de publication des
menus. Il n'active pas la section client, qui reste dans la phase 6.

## Prerequis

- L'API doit inclure les phases menus 1 a 4.
- Alembic doit etre a la revision `0081`.
- Les routes `/catalog/admin/menus` doivent etre accessibles depuis
  l'environnement de l'application admin.
- Les roles doivent conserver `catalog:read` pour consulter les menus et
  `catalog:write` pour les modifier.
- Un tenant pilote doit disposer de produits actifs, dont un produit synchronise
  POS si le mode `connected` doit etre verifie.

## Verification avant livraison

Depuis `app-admin-staff/` :

```powershell
C:\Users\melbo\flutter\bin\flutter.bat analyze
C:\Users\melbo\flutter\bin\flutter.bat test test\menu_management_phase5_test.dart test\catalog_responsive_test.dart
```

Construire ensuite l'artefact avec la configuration habituelle de
l'environnement cible. Aucun changement de schema ni variable d'environnement
n'est ajoute par cette phase.

## Ordre de deploiement

1. Verifier que l'API phase 4 et la migration `0081` sont deja deployees.
2. Deployer l'application admin sur l'environnement de recette.
3. Tester avec un admin, puis avec un staff en lecture seule.
4. Creer un menu brouillon, un groupe obligatoire et ajouter des produits.
5. Verifier que la publication reste bloquee tant que le menu est incomplet.
6. Publier le menu complet, modifier sa composition et verifier sa
   depublication automatique.
7. Promouvoir le meme artefact en production apres validation du tenant pilote.

## Smoke tests production

- Le bouton `Menus` ouvre l'ecran depuis le catalogue.
- Un admin peut creer un menu sans saisir d'identifiant technique.
- Le prix accepte la virgule et est envoye comme valeur numerique.
- Les erreurs de validation de l'API sont affichees dans l'interface.
- Un produit POS deja ajoute porte l'indication `POS` et ses donnees produit ne
  sont pas modifiables depuis cet ecran.
- Un staff avec `catalog:read` sans `catalog:write` peut consulter, mais ne voit
  aucune action de creation, modification, publication ou suppression.
- L'apercu client reflete le nom, le prix, les groupes et les produits du menu.

## Surveillance

Pendant le deploiement, surveiller les erreurs `403`, `409`, `422` et `5xx` sur
les routes admin menus. Une hausse des `403` indique en priorite un probleme de
permissions ; les `409` et `422` doivent conserver un message metier lisible.
Verifier aussi qu'aucun menu incomplet n'est actif dans les donnees du tenant.

## Retour arriere

L'application admin peut etre remise a sa version precedente sans migration et
sans perte de menus. Les donnees creees restent gerees par l'API et ne doivent
pas etre supprimees. Ne pas downgrader Alembic `0081` : cette revision contient
egalement l'historique des commandes menus de la phase 4.

En cas d'incident limite a la creation admin, retirer l'acces a la nouvelle
version de l'application suffit. Les endpoints API peuvent rester deployes et
les menus deja publies continuent de fonctionner cote API.
