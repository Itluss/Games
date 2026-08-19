# PLANCHES DE RÉFÉRENCE

Source de vérité de la direction artistique. **Ne pas les modifier** : les
découpes en dérivent, et les bons de commande Meshy pointent vers les
découpes.

| fichier | contenu |
|---|---|
| `planche_heros.png` | BRUTE, ZIPPY, SPARK, BOLT |
| `planche_mobs.png`  | BRUTE, SHOOTER, BOMBER, DRONE, SCOUT/SLIME |
| `planche_armes.png` | les 6 armes |
| `planche_props.png` | le map kit, 12 éléments |

## Les découpes

`art/references/decoupes/<lot>/<nom>.png` — un sujet par image, 768 × 768,
fond crème uni.

**Pourquoi découper.** Meshy `image-to-3d` attend UN sujet. Lui donner la
planche entière — quatre héros, des titres, des vignettes, des badges —
produirait une bouillie, ou une carte en 3D.

**Pourquoi effacer plutôt que rogner.** Les badges de rôle et le bandeau
« VUE TOP-DOWN » sont repeints au fond de la carte. Resserrer le cadre
sous les badges aurait coupé le fanion de Brute et les pointes de cheveux
de Zippy — c'est-à-dire justement les éléments de silhouette qu'on veut
que Meshy voie.

## Le script

`outils/decouper_planches.py` refait toutes les découpes depuis les
planches. Si un cadrage est mauvais, on corrige les coordonnées là et on
relance : les découpes ne sont jamais retouchées à la main, sans quoi
personne ne saurait plus d'où elles viennent.
