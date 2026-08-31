# Prompt Claude Code — correction topologique Arena 01 V2

Copie-colle le bloc ci-dessous dans Claude Code depuis `C:\Users\camille\Games`.

---

Tu travailles sur le projet Godot 4.3 `arena-rush/`. Le premier graybox d'Arena 01 existe déjà, mais sa topologie de gameplay doit être corrigée. Ne repars pas de zéro et ne travaille pas sur les graphismes. Inspecte d'abord l'implémentation actuelle, puis modifie-la et teste-la réellement.

## Références

- Plan conceptuel : `design/arena-01-graybox-lines-v1.svg`
- Spécifications initiales : `design/arena-01-the-convergence-spec-v1.md`
- Capture actuelle fournie par l'utilisateur dans la conversation.

Le SVG n'est plus à reproduire littéralement lorsqu'il contredit les nouvelles règles de circulation ci-dessous. Les règles V2 de ce prompt sont prioritaires.

## Problèmes observés

### 1. Le joueur disparaît sous certaines structures

Des passerelles sont construites comme des dalles suspendues et le joueur peut circuler dessous. Avec la caméra isométrique, la dalle masque alors complètement le joueur.

### 2. Les joueurs rejoignent le Core directement

Les quatre couloirs cardinaux relient actuellement chaque base au centre. Une équipe peut donc courir en ligne droite jusqu'au Core sans rencontrer ses adversaires. Les quatre équipes restent isolées dans leur secteur au lieu de se croiser.

### 3. La carte est trop compartimentée

Elle ressemble à quatre bases rectangulaires posées autour d'un cercle vide. Il manque des routes diagonales, des zones de friction et des boucles de contournement.

## Objectif de gameplay

La partie accueille quatre équipes de trois joueurs, soit 12 joueurs.

Le début de partie doit suivre ce flux :

`SPAWN D'EQUIPE -> choix gauche/droite -> zone de rencontre avec une équipe voisine -> anneau intermédiaire -> accès indirect au Core`

Une équipe ne doit jamais pouvoir aller de son spawn au Core par une route droite et sûre. Pour rejoindre le centre, elle doit traverser au moins une zone susceptible d'être empruntée par une équipe voisine.

## Nouvelle topologie obligatoire

### Secteurs de départ

- Conserve trois spawns par secteur et exactement 12 spawns.
- Chaque secteur est une zone de départ ouverte, pas un bâtiment fermé.
- Retire les grands contours rectangulaires qui enferment chaque faction.
- Chaque groupe de trois spawns débouche sur deux sorties principales : une sortie horaire et une sortie antihoraire.
- La sortie centrale apparente doit être bloquée ou déviée par un gros obstacle afin d'empêcher la course droite vers le Core.
- Depuis un spawn, le joueur doit choisir gauche ou droite dans les premières secondes.

### Quatre zones de rencontre

Crée quatre hubs de confrontation entre les secteurs, centrés approximativement sur les diagonales :

- Hub NE entre Sanctuary et Forge, autour de `(42, 0, 42)`.
- Hub SE entre Forge et Barracks, autour de `(42, 0, -42)`.
- Hub SW entre Barracks et Rift, autour de `(-42, 0, -42)`.
- Hub NW entre Rift et Sanctuary, autour de `(-42, 0, 42)`.

Chaque hub doit :

- recevoir une route provenant de chacun des deux secteurs voisins ;
- offrir au moins deux sorties vers l'anneau intermédiaire ;
- contenir du loot intéressant et plusieurs couvertures ;
- proposer une boucle locale, jamais un simple couloir ;
- mélanger lignes de vue courtes et moyennes ;
- ne pas posséder une position dominante qui couvre toutes les entrées ;
- permettre le repli sans créer de cul-de-sac.

Les joueurs peuvent choisir l'un des deux hubs voisins, mais ils ne peuvent pas éviter tous les espaces partagés.

### Anneau intermédiaire

- Conserve un anneau de rotation continu autour du Core, approximativement entre 28 et 43 m du centre.
- Relie les quatre hubs diagonaux à cet anneau.
- Supprime les quatre autoroutes cardinales droites allant de `R_SECTEUR_IN` au Core.
- Décale les accès au Core d'environ 35 à 45 degrés par rapport aux axes des spawns.
- Crée quatre entrées du Core placées près des diagonales, pas face aux bases.
- Chaque entrée doit être visible depuis au moins deux directions et comporter des couvertures contestables.

### Core

- Le Core ne doit pas être accessible directement depuis un spawn.
- Distance parcourue minimale spawn -> entrée du Core : 75 m.
- Le trajet doit comporter au moins deux changements de direction significatifs.
- Aucun rayon droit et dégagé ne doit relier un spawn à une entrée du Core.
- Le Core doit rester une zone risquée, avec peu de couverture permanente.
- Conserve une circulation permettant de contourner le Core sans y entrer.

## Résolution de l'occlusion

Applique les deux règles suivantes.

### Règle de level design

- Aucun espace jouable ne doit passer sous une plateforme, un pont ou une toiture opaque.
- Une plateforme surélevée doit être construite sur un socle plein ou au-dessus d'une zone explicitement inaccessible.
- Supprime ou transforme les passerelles actuelles sous lesquelles le joueur peut marcher.
- Les rampes peuvent monter sur les plateformes, mais leur projection au sol ne doit pas créer un tunnel praticable.
- Le graybox doit rester lisible depuis la caméra isométrique à tout instant.

### Protection de caméra

Ajoute une protection générique dans `arena_camera.gd` :

- effectue un raycast ou un shapecast entre la caméra et le joueur ;
- détecte les `MeshInstance3D` statiques qui masquent le joueur ;
- rends uniquement leur matériau visuel temporairement transparent, ou masque leur mesh, sans désactiver leur collision ;
- restaure leur affichage dès qu'ils ne sont plus entre la caméra et le joueur ;
- ne modifie pas définitivement les matériaux partagés ; duplique les matériaux nécessaires ou utilise une stratégie sûre ;
- évite les clignotements lorsque plusieurs obstacles se succèdent ;
- le joueur doit toujours rester visible.

La protection de caméra est une sécurité. Elle ne justifie pas la présence de tunnels ou de grandes structures opaques au-dessus des routes.

## Couvertures et lignes de vue

- Place une couverture utile tous les 8 à 12 m sur les routes actives.
- Alterne couvertures basses et bloqueurs de vision hauts.
- N'utilise pas de longs murs continus formant des bâtiments rectangulaires.
- Préfère de petits groupes de murs en L, arcs courts et blocs décalés.
- Chaque groupe de couverture doit laisser au moins deux chemins autour.
- Largeur minimale d'une route principale : 6 m.
- Largeur minimale d'une route secondaire : 4 m.
- Aucun cul-de-sac de plus de 8 m.
- Limite les grandes lignes de vue à environ 45–55 m.

## Répartition du loot pour provoquer les rencontres

- Place les 6 loots élevés dans les quatre hubs diagonaux et sur deux positions contestées de l'anneau.
- Ne place aucun loot élevé à côté des spawns.
- Place davantage de loot moyen sur les sorties gauche/droite que dans les bases.
- Le Core peut contenir la capsule centrale, mais ne doit pas être l'unique destination rentable.
- Les soins doivent se trouver dans ou près des hubs afin d'encourager les rotations entre équipes.

## Changements attendus dans le code

Travaille principalement dans :

- `arena-rush/scripts/blockout_plan.gd`
- `arena-rush/scripts/blockout_builder.gd`
- `arena-rush/scripts/arena_camera.gd`
- le validateur existant associé au graybox

Dans `blockout_plan.gd` :

- retire les quatre rampes cardinales directes ;
- remplace-les par les routes courbes ou segmentées vers les hubs diagonaux ;
- remplace les grands murs de bases par de petits groupes de couvertures ;
- définis explicitement les quatre hubs et leurs connexions ;
- ajoute des données permettant de valider les routes de chaque équipe.

Dans `blockout_builder.gd` :

- élimine les passerelles avec espace praticable dessous ;
- construis les plateformes comme des socles pleins ou condamne leur empreinte au sol ;
- garde les collisions cohérentes avec les meshes visibles ;
- conserve le graybox en primitives et couleurs unies.

Dans `arena_camera.gd` :

- ajoute le système anti-occlusion décrit plus haut ;
- conserve la vue cartographique avec la touche `M`.

## Validation obligatoire

Étends le validateur pour vérifier automatiquement :

1. Exactement 12 spawns.
2. Deux sorties déclarées pour chaque secteur de départ.
3. Quatre hubs diagonaux présents.
4. Chaque hub reçoit des routes depuis exactement deux secteurs voisins.
5. Chaque secteur atteint deux hubs différents.
6. Aucun lien direct déclaré entre un spawn et le Core.
7. Chaque chemin spawn -> Core passe par un hub puis par l'anneau.
8. Longueur minimale spawn -> entrée Core de 75 m.
9. Au moins deux changements de direction sur chaque chemin spawn -> Core.
10. Aucun passage jouable sous une plateforme.
11. Deux accès pour chaque plateforme haute.
12. Aucun cul-de-sac supérieur à 8 m.
13. Le nombre de marqueurs de loot et de soin reste conforme aux spécifications.

Si la validation géométrique complète nécessite un petit graphe de navigation abstrait, crée ce graphe dans les données du plan et valide-le avec une recherche de chemins. Ne prétends pas avoir vérifié une règle si elle ne l'est pas réellement.

## Test avec des bots de circulation

Ajoute un test de simulation léger ou des agents debug sans combat :

- 12 capsules, une par spawn ;
- chaque capsule choisit aléatoirement le hub gauche ou droit de son secteur ;
- elle se déplace ensuite vers l'anneau puis vers une entrée du Core ;
- affiche ou journalise le hub traversé ;
- vérifie qu'au moins deux équipes peuvent converger dans chaque hub ;
- le test ne doit pas remplacer le joueur contrôlable.

Si un système de navigation complet est disproportionné, utilise des waypoints et des segments de trajet visibles en vue cartographique.

## Tests visuels à effectuer

1. Lance `main_blockout.tscn` et parcours au moins une route gauche et une route droite depuis `Spawn_S01`.
2. Vérifie qu'aucune de ces routes n'atteint directement le Core.
3. Traverse un hub diagonal puis l'anneau avant d'entrer dans le Core.
4. Monte sur chaque type de plateforme.
5. Essaie de passer sous chaque plateforme : cela doit être impossible.
6. Place le joueur derrière des murs hauts par rapport à la caméra et vérifie qu'il reste visible grâce à l'anti-occlusion.
7. Active la vue `M` et vérifie que les quatre hubs et toutes les routes sont clairement visibles.

## Critères d'acceptation

Le correctif est terminé uniquement si :

- le joueur ne peut jamais circuler sous une structure qui le masque ;
- la caméra garde toujours le joueur visible ;
- aucune équipe ne possède de route directe spawn -> Core ;
- chaque équipe choisit entre deux zones de rencontre partagées avec ses voisines ;
- les quatre hubs diagonaux produisent des croisements possibles entre équipes ;
- l'anneau permet encore les rotations et les replis ;
- les 12 spawns et tous les marqueurs restent valides ;
- la scène démarre sans erreur ;
- le validateur passe réellement ;
- aucun graphisme détaillé ou asset externe n'est ajouté.

## Compte rendu final demandé

À la fin, donne :

- la liste des fichiers modifiés ;
- un résumé de la nouvelle circulation ;
- les anciennes routes directes supprimées ;
- la solution anti-occlusion choisie ;
- les tests exécutés et leurs résultats exacts ;
- toute limite qui n'a pas pu être validée automatiquement.

Ne t'arrête pas après une analyse ou un plan : implémente, lance les tests, corrige les erreurs et livre une scène jouable.

---
