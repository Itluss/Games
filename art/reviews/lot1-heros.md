# CONTRÔLE QUALITÉ — LOT 1, HÉROS

Jugé en rendu, deux vues par héros : 3/4 (fiche de sélection) et **dessus**
(la seule qui compte en jeu, puisque la caméra plonge).

## Mesures

| modèle | dimensions | tris | matériaux | verdict |
|---|---|---|---|---|
| `hero_brute` | 1,93 × 2,15 × 1,31 m | 11 330 | 1 | **écarté** |
| `hero_zippy` | 0,73 × 1,72 × 1,45 m |  9 338 | 1 | **retenu** |
| `hero_spark` | 0,76 × 1,62 × 0,89 m |  9 360 | 1 | **repris** |
| `hero_bolt`  | 1,04 × 1,88 × 0,77 m | 10 359 | 1 | **retenu** |

Budget demandé : 4 000 à 12 000 tris, peu de matériaux. **Les quatre le
respectent, et chacun n'a qu'un seul matériau** — c'est exactement ce qu'on
voulait pour du mobile.

## BRUTE — écarté, deux échecs durs

**Il portait une arme.** Un tube long en bandoulière, fondu dans le
maillage. Les six armes sont un lot à part et doivent toutes pouvoir être
portées par les quatre héros : une arme fondue dans le corps rend le héros
inutilisable avec les cinq autres. « no weapon » figurait pourtant dans le
prompt *et* dans le négatif.

**Le style avait dérivé vers le réaliste.** Environ cinq têtes de haut,
visage d'homme adulte buriné, finition métallique brillante. La planche
impose du chibi mat et chaleureux, et le cahier des charges interdit
explicitement le réalisme.

## SPARK — repris, silhouette incomplète

Le modèle est **mignon et lisible**, mais il a perdu ses deux éléments
signature : ni sac techno, ni drone d'épaule. Et il est sorti presque
entièrement orange, alors que sa couleur assignée est le vert.

**Pourquoi c'est grave alors que le modèle est joli :** vu de dessus, à la
distance de la caméra, il ne reste qu'une casquette orange. Le sac était ce
qui lui donnait sa silhouette rectangulaire — la seule chose qui le
distingue d'un autre petit personnage — et le drone disait « ingénieur »
sans qu'on ait besoin de regarder son visage.

## ZIPPY et BOLT — retenus

Zippy : proportions chibi justes, cheveux cyan en pointes épaisses, visière
violette, écharpe qui part en arrière, baskets cyan/violet, mains vides.
Très proche de la planche.

Bolt : cheveux rouges, bandeau bleu, lunettes relevées, écharpe orange,
mains vides. Le bas du corps est plus sombre que sur la planche — noté,
pas rédhibitoire.

## LA LEÇON, ET ELLE VAUT POUR LES TROIS LOTS SUIVANTS

**Ce qui est en tête de prompt gagne.** Dans la v1 de Brute,
« heavily armored tank hero » ouvrait la description et « no weapon » la
fermait. Un générateur pondère ce qui vient en premier : l'armure lourde a
gagné, le reste a été lu comme du détail.

Les v2 ouvrent donc par **le style** et par **les mains vides**, et ne
décrivent le personnage qu'ensuite. La contrainte est aussi répétée sous
plusieurs formes — rien tenu, rien en bandoulière, aucun tube — parce
qu'une seule formulation peut être ignorée, cinq beaucoup moins.

## Coût

4 générations au premier jet, 2 reprises. Les modèles écartés ne sont pas
supprimés du dépôt tant que leur remplaçant n'est pas validé : on ne jette
pas ce qu'on a payé avant d'avoir mieux.
