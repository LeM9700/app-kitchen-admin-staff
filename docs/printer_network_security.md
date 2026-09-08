# Impression reseau locale - dependance et durcissement

## Ce que fait le pilote reseau

`lib/core/printing/printer_driver.dart` (`NetworkTextPrinterDriver`) ouvre une
connexion TCP brute sur le port ESC/POS classique (9100 par defaut) vers
l'imprimante de cuisine ou de comptoir. Ce protocole n'a pas de couche de
chiffrement ni d'authentification : quiconque peut parler a une imprimante en
ouvrant une socket TCP sur ce port. L'application ne peut donc pas "chiffrer"
ce protocole - la seule protection possible est de limiter strictement les
destinations que l'app est autorisee a contacter.

## Dependance reseau (a respecter par l'infra du restaurant)

Le port TCP 9100 (et les autres ports imprimante geres : 9101, 9102, 515,
631) **doit rester sur le VLAN metier local** du restaurant (le meme reseau
que les postes caisse/cuisine) et **ne doit jamais etre routable depuis le
Wi-Fi invite** ni depuis Internet. Si le Wi-Fi invite peut atteindre ce VLAN,
n'importe quel client connecte au Wi-Fi invite peut imprimer des tickets
arbitraires ou perturber le service - ce n'est pas quelque chose que
l'application peut corriger cote client, cela releve de la segmentation
reseau (VLAN + regles de pare-feu inter-VLAN) mise en place par l'exploitant
du reseau du restaurant.

## Ce que le client fait pour limiter le risque

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
   - un restaurant peut etendre l'autorisation a d'autres plages privees via
     `PrinterNetworkPolicy(extraAllowedCidrs: [...])` (par exemple un CGNAT
     `100.64.0.0/10` pour un site multi-etablissements) - jamais a une plage
     publique ;
   - seuls les ports imprimante attendus sont acceptes (9100, 9101, 9102,
     515, 631) ; tout autre port est refuse.
2. **Confirmation explicite de la cible** : `PrinterTarget.confirmed` doit
   etre `true` pour qu'une impression reseau soit tentee. Dans l'ecran de
   configuration (Parametres > Impression), la personne qui enregistre un
   hote reseau doit cocher explicitement "Je confirme que cette adresse
   correspond bien a l'imprimante physique sur le reseau local du
   restaurant" ; sans cette case, l'enregistrement est bloque avec un
   message explicite et le pilote refuse d'imprimer.
3. **Timeout** : la connexion et l'envoi ont un delai maximal (5 secondes par
   defaut) pour ne jamais bloquer indefiniment l'application sur une
   imprimante injoignable.
4. **Erreurs sans divulgation reseau** : les echecs (connexion refusee,
   timeout, DNS, destination interdite) renvoient tous un message generique
   cote UI ("Impossible de contacter cette imprimante...") qui ne contient
   jamais l'IP, le port ni le detail de l'exception systeme.
5. **Journal local minimal** : chaque tentative est journalisee localement
   (`PrinterAuditLogger`) avec seulement le nom de l'imprimante, le resultat
   (succes/echec) et une raison courte (`timeout`, `connect_failed`,
   `destination_not_allowed`, ...). Le contenu du ticket n'est jamais
   journalise.

## Ce que ca ne fait pas

- Ca ne chiffre pas le flux ESC/POS envoye a l'imprimante : une fois la
  connexion autorisee etablie sur le reseau local, le contenu du ticket
  circule toujours en clair, comme avec n'importe quelle imprimante
  thermique reseau du marche. La protection porte sur *qui l'app peut
  contacter*, pas sur le protocole imprimante lui-meme.
- Ca ne remplace pas la segmentation reseau : si le VLAN metier est mal
  isole, ces controles applicatifs restent la seule barriere restante.
