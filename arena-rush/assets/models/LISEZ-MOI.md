# Modèles 3D

## `kael.glb` — le personnage joueur

Maillage, squelette humanoïde de 24 os et quatre animations, réunis en
un seul fichier de 1,3 Mo.

### D'où il vient

1. **Image → 3D** : la planche de Camille (`art/references/`) donne le
   maillage texturé, via `outils/meshy.py`.
2. **Auto-rigging** : `outils/meshy_rig.py` greffe un squelette
   humanoïde et applique les animations de la bibliothèque Meshy.
3. **Fusion** : Meshy livre UN FICHIER PAR ANIMATION, chacun
   réembarquant maillage et texture — 27 Mo pour quatre clips, dont 27 Mo
   de doublons. `outils/fusionner_anims.py` n'en garde qu'un exemplaire.
4. **Allègement** : `outils/alleger_glb.py` ramène la texture à 1024 et
   retire l'émission (voir plus bas).

### Animations

| Clip | Action Meshy | Durée | Rôle |
|---|---|---|---|
| `repos` | `Idle` (0) | 4,03 s | à l'arrêt |
| `course` | `RunFast` (16) | 0,50 s | déplacement |
| `course_tir` | `Run_and_Shoot` (98) | 0,70 s | déplacement en tirant |
| `mort` | `Dead` (8) | 3,00 s | élimination |

Les 678 actions disponibles sont listées dans
`outils/animations_meshy.json`.

### Deux pièges déjà payés

**Métallicité.** L'export riggé ne précise pas `metallicFactor`, et la
valeur par défaut de glTF est **1.0**. Le personnage devenait un miroir
intégral et, sans réflexion d'environnement, se rendait en silhouette
NOIRE — texture pourtant chargée. Corrigé dans `character_visual.gd`.

**Émission.** Le même export branche la texture de couleur en émission à
facteur plein : le personnage s'auto-éclairait et ignorait toute lumière.
Retiré par `alleger_glb.py`.

Aucun des deux ne provoque d'erreur : le modèle se charge sans broncher
et s'affiche mal. D'où cette note.

### Repères mesurés

- origine **aux pieds** (boîte de 0,000 à 1,900) — contrairement au
  maillage non riggé, dont l'origine était au centre ;
- le modèle regarde vers **+Z**, l'avant de Godot est -Z, d'où le
  demi-tour dans `character_visual.gd` ;
- l'arme s'accroche à l'os **`RightHand`**.

## Ce qui n'est PAS versionné

Les cartes brutes de Meshy (2048 px, ~21 Mo). Elles partiraient dans
l'export web et annuleraient tout le travail d'allègement. Les URL
signées pour les récupérer sont dans `taches/*.json`.
