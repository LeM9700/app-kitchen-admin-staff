# Impression reseau locale - dependance et durcissement

## Etat actuel du flux d'impression (important)

**Aucun dispatcher reel n'appelle le pilote reseau aujourd'hui.** Le flux
existant s'arrete avant toute connexion TCP :

```
ReceiptBuilder / creation d'un PrintJob
        -> printJobsProvider.enqueue(job)   (file en memoire, cote UI)
        -> Parametres > Impression affiche la file
        -> le staff clique "Terminer" pour retirer le job de la file
```

`PrinterDriverRegistry`, `NetworkTextPrinterDriver` et `PrinterTarget` (dans
`lib/core/printing/printer_driver.dart`) ne sont references nulle part
ailleurs dans `lib/` - ni dans `checkout_page.dart`, ni dans
`orders_board_page.dart`, ni dans `settings_page.dart`. Aucune socket TCP
n'est ouverte par l'application en usage normal. `test/no_printer_dispatcher_wired_test.dart`
verifie mecaniquement cet etat et doit etre mis a jour (avec ce document) le
jour ou un vrai dispatcher est branche.

Autrement dit : `printer_driver.dart` est une **fondation deja durcie**
(validation d'hote/port, timeouts, erreurs sans fuite, journal minimal,
confirmation explicite) prete a etre branchee, mais elle n'est pas encore
appelee par un point d'entree reel de l'application. Ne pas presenter cette
brique comme une impression reseau fonctionnelle tant qu'aucun dispatcher ne
l'invoque.

## Ce que fera le pilote reseau une fois branche

`NetworkTextPrinterDriver` ouvre une connexion TCP brute sur le port ESC/POS
classique (9100 par defaut) vers l'imprimante de cuisine ou de comptoir. Ce
protocole n'a pas de couche de chiffrement ni d'authentification : quiconque
peut parler a une imprimante en ouvrant une socket TCP sur ce port.
L'application ne peut donc pas "chiffrer" ce protocole - la seule protection
possible est de limiter strictement les destinations que l'app est autorisee
a contacter, ce qui est fait au niveau de `PrinterNetworkPolicy` (voir
ci-dessous) independamment du fait qu'un dispatcher l'utilise deja ou non.

## Dependance reseau (a respecter par l'infra du restaurant, des maintenant)

Le port TCP 9100 (et les autres ports imprimante geres : 9101, 9102, 515,
631) **doit rester sur le VLAN metier local** du restaurant (le meme reseau
que les postes caisse/cuisine) et **ne doit jamais etre routable depuis le
Wi-Fi invite** ni depuis Internet. Si le Wi-Fi invite peut atteindre ce VLAN,
n'importe quel client connecte au Wi-Fi invite peut imprimer des tickets
arbitraires ou perturber le service - ce n'est pas quelque chose que
l'application peut corriger cote client, cela releve de la segmentation
reseau (VLAN + regles de pare-feu inter-VLAN) mise en place par l'exploitant
du reseau du restaurant. Cette exigence reste valable meme si aucun
dispatcher n'est encore branche : elle conditionne toute integration future.

## Ce que le pilote fait pour limiter le risque

1. **Validation stricte de l'hote et du port** (`PrinterNetworkPolicy`) :
   - le champ "host" doit etre un hote ou une IP litterale, jamais une URL
     (rejet de tout ce qui contient `://`, `/`, `@` ou des espaces) ;
   - resolution DNS effectuee une seule fois puis connexion directe a
     l'adresse resolue (jamais une re-resolution au moment de la connexion),
     pour eviter un DNS rebinding entre la verification et l'envoi ;
   - toutes les adresses resolues doivent appartenir a une plage privee
     autorisee (par defaut `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`,
     `fc00::/7`) ; `localhost`, la boucle locale, le lien local (dont
     `169.254.169.254`, adresse de metadonnees cloud), le multicast et toute
     adresse publique sont toujours refuses, meme si le restaurant a ajoute
     des plages supplementaires ;
   - seuls les ports imprimante attendus sont acceptes (9100, 9101, 9102,
     515, 631) ; tout autre port est refuse.
2. **Extension de plages (`extraAllowedCidrs`) strictement bornee** : un
   restaurant peut passer `PrinterNetworkPolicy(extraAllowedCidrs: [...])`
   pour couvrir un decoupage LAN non standard, mais chaque entree est
   validee : elle doit etre un sous-reseau exact (prefixe egal ou plus
   specifique) d'une des plages reconnues - les quatre plages privees
   ci-dessus, plus `100.64.0.0/10` (CGNAT, RFC 6598). `100.64.0.0/10`
   **n'est pas** autorise par defaut (il sert aussi parfois cote operateur
   sur l'internet public) : il doit etre ajoute explicitement si un site
   en a besoin. Toute entree qui n'est pas un sous-reseau de ces plages -
   `0.0.0.0/0`, un CIDR public, un prefixe invalide, une plage plus large
   que la plage reconnue - est silencieusement ignoree plutot que d'elargir
   la politique ou de faire planter l'app sur une config corrompue.
3. **Confirmation explicite liee a l'adresse** : `PrinterTarget.confirmed`
   doit etre `true` pour qu'une impression reseau soit tentee. Dans l'ecran
   de configuration (Parametres > Impression), la personne qui enregistre un
   hote reseau doit cocher explicitement "Je confirme que cette adresse
   correspond bien a l'imprimante physique sur le reseau local du
   restaurant" ; sans cette case, l'enregistrement est bloque avec un
   message explicite. Cette confirmation est liee au couple host/port exact
   qu'elle valide (`NetworkPrinterConfirmationTracker`) : modifier l'hote ou
   le port dans le dialogue la remet immediatement a `false`, et toute
   configuration enregistree avant l'existence de ce champ (ou sans valeur
   explicite) est traitee comme non confirmee.
4. **Timeout** : la connexion et l'envoi ont un delai maximal (5 secondes par
   defaut) pour ne jamais bloquer indefiniment l'application sur une
   imprimante injoignable.
5. **Erreurs sans divulgation reseau** : les echecs (connexion refusee,
   timeout, DNS, destination interdite) renvoient tous un message generique
   cote UI ("Impossible de contacter cette imprimante...") qui ne contient
   jamais l'IP, le port ni le detail de l'exception systeme.
6. **Journal local minimal** : chaque tentative est journalisee localement
   (`PrinterAuditLogger`) avec seulement le nom de l'imprimante, le resultat
   (succes/echec) et une raison courte (`timeout`, `connect_failed`,
   `destination_not_allowed`, ...). Le contenu du ticket n'est jamais
   journalise.

## Ce que ca ne fait pas

- Ca ne branche pas l'impression reseau de bout en bout : voir "Etat actuel"
  ci-dessus. Ces controles s'appliquent des qu'un dispatcher appellera
  `PrinterDriverRegistry`, mais rien ne le fait aujourd'hui.
- Ca ne chiffre pas le flux ESC/POS envoye a l'imprimante : une fois la
  connexion autorisee etablie sur le reseau local, le contenu du ticket
  circule toujours en clair, comme avec n'importe quelle imprimante
  thermique reseau du marche. La protection porte sur *qui l'app peut
  contacter*, pas sur le protocole imprimante lui-meme.
- Ca ne remplace pas la segmentation reseau : si le VLAN metier est mal
  isole, ces controles applicatifs restent la seule barriere restante.
