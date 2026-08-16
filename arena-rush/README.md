# Arena Rush — prototype d'arène 3D multijoueur

Prototype jouable de bout en bout : survie en arène, PvE contre des mobs,
loot d'armes, PvP, zone qui se referme, dernier survivant.
Conçu **mobile d'abord** (iOS / Android, téléphone et tablette, paysage).

Moteur : **Godot 4.3**, 100 % GDScript.

## Lancer

```bash
godot --path game            # menu
godot --path game --solo     # partie solo directe (1 joueur + 3 bots)
```

Depuis l'éditeur : ouvrir `game/project.godot` et lancer `scenes/main.tscn`.

### Tester le multijoueur en local

Éditeur → **Débogage → Exécuter plusieurs instances** (2 à 4), puis
« HÉBERGER » sur la première fenêtre et « REJOINDRE » sur les autres.
En build exportée : `--host` et `--join` en ligne de commande.

## Contrôles

|              | Tactile                              | Clavier / souris          |
| ------------ | ------------------------------------ | ------------------------- |
| Déplacement  | Joystick gauche (origine dynamique)  | WASD / ZQSD / flèches     |
| Tirer        | Bouton TIR (maintenir), glisser=viser| Clic gauche ou Espace     |
| Changer d'arme | Bouton ARME ou taper l'emplacement | A / Q ou Tab              |
| Esquive      | Bouton ESQUIVE                       | Maj ou E                  |
| Debug        | —                                    | F1                        |

La **visée est assistée** : le jeu accroche la cible la plus pertinente
dans la direction indiquée. Sans cela, viser au doigt une cible mobile
serait injouable.

## Architecture

```
scripts/
  core/       cfg, registry, pool, fx, match_manager, game_world, main, debug
  data/       weapon_data.gd, mob_data.gd   (Resources personnalisées)
  components/ health_component.gd, health_bar_3d.gd
  player/     player, player_controller, bot_brain, character_visual
  weapons/    weapon.gd, projectile.gd
  mobs/       mob.gd, mob_spawner.gd
  loot/       loot_pickup.gd
  arena/      arena.gd, arena_camera.gd
  ui/         hud.gd, virtual_joystick.gd
  multiplayer/multiplayer_manager.gd
resources/    weapons/*.tres, mobs/*.tres
```

### Partage d'autorité réseau

- Le **client** simule SON déplacement et diffuse sa position. Un joystick
  qui attend un aller-retour réseau donne un jeu mou ; sur mobile c'est
  rédhibitoire.
- Le **serveur** décide de tout le reste : dégâts, santé, mort, loot,
  apparition des mobs, zone, victoire. Un client ne peut qu'envoyer une
  intention de tir — les méthodes qui infligent des dégâts ne s'exécutent
  que côté serveur.

Le mode solo emprunte **le même chemin de code** : le joueur local est le
serveur. Il n'y a donc aucun `if solo` dispersé dans le projet, et jouer
seul teste réellement le code réseau.

## Ajouter du contenu sans écrire de code

Déposer un `.tres` dans `resources/weapons/` ou `resources/mobs/` suffit :
le `Registry` le charge au démarrage et l'indexe par son `id`. Les armes
sont automatiquement classées par puissance pour alimenter la montée en
gamme du butin.

## Contenu actuel

**Armes** — Basic Blaster (départ, munitions infinies), Shotgun (8 plombs,
courte portée, gros recul), Energy Blaster (9 tirs/s, traînée), Grenade
Launcher (arc, rebonds, explosion de zone).

**Mobs** — Charger (anticipation puis ruée, stoppé net par un obstacle),
Shooter (maintient sa distance, tire, se repositionne), Exploder
(poursuit, cercle de danger au sol, explose).

Chaque attaque de mob passe par un **télégraphe visible**. Le joueur doit
perdre parce qu'il a mal réagi, jamais parce qu'il n'a rien vu venir.

## Direction artistique

Aucun modèle 3D externe : tout est construit proceduralement à partir de
primitives (`VisualKit`), avec proportions exagérées, couleurs franches,
liseré lumineux et une seule lumière directionnelle ombrée.

Le visuel est **strictement séparé du gameplay** : chaque entité possède un
nœud visuel autonome exposant `set_state()`, `flash()` et `attach_weapon()`.
Brancher de vrais `.glb` animés revient à remplacer le contenu de ce nœud,
sans toucher une ligne de logique de jeu.

## Performance

Cible : 60 FPS sur tablette moderne. Renderer `mobile`, une seule lumière
ombrée, projectiles recyclés par réservoir d'objets, plafond de 22 mobs
simultanés, particules pilotées par `Cfg.quality` (F1 → « Qualité ↓ »).

## Validation

Le projet a été validé avec Godot 4.3 headless : compilation de tous les
scripts, puis parties complètes jusqu'à la victoire. Deux bugs ont été
trouvés et corrigés par ce test — une boucle d'échange de butin infinie
(412 butins produits pour 25 mobs) et des Exploders qui n'apparaissaient
jamais.

```bash
godot --headless --path game --solo --quit-after 3000
```

## Limites connues

- Les personnages sont des assemblages de primitives animés par le code,
  pas des modèles rigés.
- Aucun son : les emplacements existent dans `WeaponData`, non branchés.
- Le multijoueur passe par ENet en réseau local ; ni relais ni matchmaking.
- L'interpolation des entités distantes est un simple lissage, sans
  réconciliation ni compensation de latence.
