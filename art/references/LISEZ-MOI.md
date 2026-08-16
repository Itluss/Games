# Planches de référence pour Meshy

Déposer ici les images servant de base au mode **image-to-3D**. Une bonne
planche fait plus pour la qualité du modèle que n'importe quel réglage.

## Ce qui compte vraiment

**Pose en T ou en A.** Bras écartés, jambes légèrement ouvertes, personnage
debout et droit. C'est la contrainte la plus importante : une pose
dynamique se retrouve *figée dans le maillage*, et le personnage sera
inutilisable dès qu'il faudra l'animer. C'est aussi indispensable si l'on
veut le rigger ensuite.

**Vue de face, cadrage entier.** Des pieds au sommet du crâne, sans coupe,
sans perspective marquée, sans contre-plongée. Le personnage occupe la
hauteur de l'image, centré.

**Fond uni.** Idéalement transparent, sinon une couleur pleine bien
contrastée. Meshy interprète mal un décor et peut l'incorporer au modèle.

**Silhouette lisible.** Le jeu se joue en vue de dessus : ce sont les
épaules, la tête et la masse générale qui portent la lecture. Un
personnage identifiable en ombre chinoise sera identifiable en jeu.

**Aplats de couleur.** Le rendu est en éclairage cellulé. Une planche en
aplats francs s'y intègre ; un rendu photoréaliste ou très ombré jurera.

**Résolution ≥ 1024 px** sur le plus grand côté.

## Ce qui aide beaucoup si tu peux le fournir

Une **deuxième vue** — de profil, ou de trois quarts arrière. Meshy accepte
plusieurs images du même sujet et le dos, invisible sur une vue de face,
cesse alors d'être inventé.

## À éviter

Pose d'action · membres croisés ou superposés · perspective forte · ombres
portées appuyées · fond détaillé · plusieurs personnages sur la même image
· cadrage à mi-corps · texte ou watermark.

## Ensuite

Déposer le fichier ici, puis lancer
`Actions → Générer un asset 3D (Meshy) → Run workflow` avec :

- **mode** : `image`
- **image** : `art/references/mon_fichier.png`
- **nom** : le nom voulu pour le `.glb`

Le fichier doit être versionné dans le dépôt : le runner ne voit que ce
qui s'y trouve.
