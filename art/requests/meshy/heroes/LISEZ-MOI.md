# LOT 1 — HÉROS

Quatre héros, quatre styles de jeu, d'après la planche **HÉROS**.

## Ce qui est demandé à Meshy, et pourquoi

| fichier | nom produit | hauteur | tris | couleur dominante |
|---|---|---|---|---|
| `040-hero-brute.json`  | `hero_brute` | 2,15 m | 11 000 | orange / rouille / acier chaud |
| `041-hero-zippy.json`  | `hero_zippy` | 1,72 m |  9 000 | cyan / violet |
| `042-hero-spark.json`  | `hero_spark` | 1,62 m |  9 000 | vert / jaune / orange |
| `043-hero-bolt.json`   | `hero_bolt`  | 1,88 m | 10 000 | rouge / bleu / orange |

Les hauteurs ne sont pas décoratives : **elles portent le rôle**. Brute
dépasse Bolt de 27 cm et Spark lui arrive à l'épaule. Vue de dix mètres de
haut, la taille est la première chose qu'on lit — avant la couleur, avant
la forme du casque.

## Trois décisions qui valent pour les quatre

**A-POSE, MAINS VIDES, AUCUNE ARME.** Les six armes sont un lot à part et
doivent toutes pouvoir être portées par les quatre héros. Un modèle généré
une arme à la main obligerait à la découper, ou à renoncer aux cinq
autres. Le point d'ancrage sera posé au riggage, pas ici.

**LES FORMES EFFILÉES DE LA PLANCHE DEVIENNENT ÉPAISSES.** Les pointes de
cheveux de Zippy, son écharpe, le fanion de Brute : dessinés fins, ils
disparaissent à la distance de la caméra et coûtent des triangles pour
rien. On garde la *direction* du mouvement, en volumes francs.

**LE DRONE DE SPARK EST DANS LE MODÈLE**, posé sur l'épaule. Généré à
part, il faudrait l'attacher par du code — or ce lot ne doit créer aucun
système. Sur l'épaule, il fait partie de la silhouette, et c'est
justement ce qui distingue Spark de loin.

## Ce que je n'ai PAS pu faire, et il faut le savoir

**Les prompts sont écrits en mode TEXTE, pas en mode IMAGE.** Meshy sait
partir d'une planche (`--mode image`), et ce serait plus fidèle. Mais le
mode image exige un fichier versionné dans `art/references/`, et les
planches m'ont été transmises dans la conversation : je n'ai aucun moyen
d'en écrire les pixels sur le disque.

**Ce que cela change concrètement :** la fidélité passe par ma *lecture*
des planches, consignée dans le champ `_lecture_de_la_planche` de chaque
bon de commande. C'est une interprétation, aussi précise soit-elle.

**Comment le corriger :** déposer les quatre planches dans
`art/references/` (par exemple `planche_heros.png`), et les bons de
commande basculent en `"mode": "image"` avec `"image": "art/references/…"`.
La ressemblance sera alors bien meilleure. Si vous les déposez, je
regénère.
