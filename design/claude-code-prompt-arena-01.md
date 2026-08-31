# Prompt pour Claude Code — construire Arena 01

Copie-colle tout le bloc ci-dessous dans Claude Code depuis le dossier `C:\Users\camille\Games`.

---

Tu travailles sur le projet Godot 4.3 situé dans `arena-rush/`.

## Objectif

Construis le premier graybox jouable de l'arène **Arena 01 — The Convergence**, prévue pour **12 joueurs**, à partir de ces deux références :

- Plan principal en lignes : `design/arena-01-graybox-lines-v1.svg`
- Mesures et règles : `design/arena-01-the-convergence-spec-v1.md`

Le SVG est la référence pour la forme et la circulation. Le fichier Markdown est la référence pour les dimensions, hauteurs, distances et contraintes de gameplay. En cas de contradiction, suis le Markdown et indique l'écart dans ton compte rendu.

## Contexte du projet existant

- Scène principale : `arena-rush/scenes/main_blockout.tscn`
- Script principal : `arena-rush/scripts/main_blockout.gd`
- Générateur actuel : `arena-rush/scripts/blockout_builder.gd`
- Données actuelles : `arena-rush/scripts/blockout_plan.gd`
- Contrôleur joueur : `arena-rush/scripts/player.gd`
- Caméra : `arena-rush/scripts/arena_camera.gd`

Le blockout existant ne contient que 8 spawns et une arène de 56 m de diamètre. Remplace cette géométrie par la nouvelle carte de 180 m jouables et 12 spawns. Réutilise les systèmes existants lorsqu'ils sont propres et utiles, mais ne conserve pas une structure qui empêche de respecter le nouveau plan.

## Contraintes impératives

1. Reste en graybox pur : uniquement primitives Godot, aplats de couleur et collisions. Aucun modèle, texture, shader décoratif ou asset externe.
2. Ne modifie pas les fichiers situés dans `design/`.
3. Ne casse pas le contrôleur, la caméra ni le lancement de `main_blockout.tscn`.
4. L'arène doit avoir un rayon jouable de 90 m et une enceinte extérieure proche de 95 m.
5. Crée exactement 12 spawns nommés `Spawn_S01` à `Spawn_S12`, trois par secteur.
6. Aucun spawn ne doit avoir une ligne de vue directe vers un autre spawn.
7. Chaque spawn doit avoir deux sorties praticables.
8. Tous les murs et couverts doivent avoir des collisions.
9. Aucun cul-de-sac de plus de 8 m.
10. Chaque plateforme haute doit avoir deux accès distincts.
11. Le joueur doit pouvoir tourner autour du centre sans traverser le Core.
12. Chaque secteur doit offrir au moins trois routes vers le Core : route principale, route latérale et route de flanc.

## Géométrie à construire

### Structure générale

- Enceinte circulaire extérieure.
- Core central de 34 m de diamètre.
- Anneau de rotation autour du Core.
- Quatre rampes cardinales vers le Core.
- Quatre secteurs : Sanctuary au nord, Forge à l'est, Barracks au sud, Rift à l'ouest.
- Routes diagonales entre secteurs voisins.
- Couvertures réparties tous les 8 à 12 m sur les routes principales.

### Hauteurs

- Sol principal : `Y = 0`.
- Couverture basse : 1,2 à 1,5 m.
- Mur bloquant la vision : 3 à 5 m.
- Route surélevée standard : `Y = 3 m`.
- Plateforme haute maximale : `Y = 6 m`.
- Ajoute des rampes praticables ; n'utilise pas d'escaliers purement visuels sans collision correcte.

### Identité graybox des secteurs

Utilise seulement des couleurs debug pour différencier les zones :

- Sanctuary : ivoire et bleu.
- Forge : charbon et orange.
- Barracks : bleu marine et orange.
- Rift : violet et cyan.
- Core : gris neutre avec repère jaune.

Les couleurs servent uniquement à la lecture du blockout. Ne crée aucun décor détaillé.

## Données et architecture attendues

- Fais de `blockout_plan.gd` la source de vérité des dimensions et positions.
- Organise les données par catégories explicites : enceinte, murs, couverts, plateformes, rampes, spawns, loot, soins et sockets de zone finale.
- Évite une longue liste opaque de coordonnées. Crée des fonctions utilitaires pour les rotations, arcs, rectangles, segments et répétitions contrôlées.
- La carte peut utiliser une symétrie globale pour l'équité, mais chaque secteur doit avoir une disposition interne différente conformément au SVG.
- Ajoute des noms explicites aux nœuds générés afin que l'arbre de scène soit inspectable.
- Sépare les collisions statiques des marqueurs sans collision.

## Marqueurs de gameplay

Crée des marqueurs simples et visibles, sans implémenter encore les systèmes complets :

- 12 spawns joueurs.
- 6 emplacements de loot élevé.
- 12 emplacements de loot moyen.
- 16 emplacements de loot commun.
- 4 stations de soin.
- 4 plateformes hautes.
- 1 emplacement de capsule centrale.
- Au moins 5 sockets possibles pour une zone finale, dont plusieurs hors du Core.

Utilise des `Marker3D` groupés avec des groupes Godot explicites, par exemple `player_spawns`, `loot_high`, `loot_medium`, `loot_common`, `heal_stations`, `final_zone_sockets`. Ajoute un petit mesh debug distinct pour les rendre visibles dans le graybox.

## Validation automatique

Ajoute un script de validation exécutable sans interaction qui vérifie au minimum :

- exactement 12 spawns ;
- spawns à l'intérieur de l'enceinte ;
- distance minimale de 18 m entre spawns voisins ;
- nombre exact de marqueurs de loot et de soin ;
- aucune géométrie principale en dehors du rayon extérieur ;
- présence des quatre secteurs et du Core ;
- présence d'au moins deux accès déclarés par plateforme haute.

Le validateur doit retourner un code d'échec ou produire des erreurs explicites si une règle échoue.

## Test visuel

- Conserve la touche `M` pour basculer vers une vue cartographique.
- Dans cette vue, les 12 spawns, les limites du Core, les routes principales et les marqueurs doivent être lisibles.
- Place le joueur de test sur `Spawn_S01`.
- Vérifie que le joueur peut se déplacer sur le sol, les rampes et les plateformes sans traverser les collisions.

## Méthode de travail

1. Inspecte d'abord tous les scripts et scènes concernés ainsi que les deux références de `design/`.
2. Présente un plan d'implémentation court.
3. Implémente directement le graybox.
4. Lance les vérifications disponibles en ligne de commande avec Godot.
5. Corrige les erreurs de parsing, de scène, de collision et de validation.
6. Ne t'arrête pas à une simple proposition de code : termine avec une scène exécutable.

## Livrables

- Scripts et scènes Godot modifiés dans `arena-rush/`.
- Graybox exécutable via `main_blockout.tscn`.
- Validateur automatique.
- Court compte rendu final listant : fichiers modifiés, tests exécutés, résultats, limites restantes.

## Critères d'acceptation

Le travail est terminé uniquement si :

- le projet Godot se charge sans erreur de parsing ;
- la scène principale démarre ;
- l'arène circulaire mesure environ 180 m de diamètre jouable ;
- les quatre secteurs et le Core correspondent au plan SVG ;
- les 12 spawns sont présents et valides ;
- toutes les quantités de marqueurs demandées sont respectées ;
- le joueur et la caméra fonctionnent ;
- le validateur passe ;
- aucun graphisme détaillé n'a été ajouté.

---
