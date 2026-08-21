#!/usr/bin/env python3
"""DÉCOUPES DE REPRISE (r2) DU KIT DE L'ÎLE — les recalés du lot n° 1.

Le premier lot avait quinze découpes ; huit modèles sont revenus
inexploitables et n'ont PAS été intégrés (consigne : un asset aux bords
coupés ou de mauvaise qualité ne se pose pas). Ces boîtes-ci sont
recalibrées sur planche de contrôle pour la deuxième commande :

  - les trois cubes de mur, cadrés LARGES sur l'icône isolée de la bande
    « assets principaux » — le premier lot les a rendus en doubles 1×2,
    le prompt de reprise martèle « un seul cube, proportions 1:1:1 » ;
  - le puits et le palmier, mêmes icônes, marges élargies aux pointes ;
  - la cabane, prise sur la carte elle-même (la seule vue où elle a
    des MURS — la vignette « compositions » ne montre qu'un auvent).

Le tonneau ne repart pas d'une image : sa seule occurrence sur la
planche fait 37 pixels et a produit un pot sombre — il repart en mode
TEXTE avec la palette de la planche dans le prompt. La plateforme reste
procédurale (sa vignette ne montre que l'étoile).

    python3 outils/decouper_blocs_r2.py

LES COORDONNÉES SONT EN FRACTIONS de la planche (1536×1024 à l'origine) :
une planche regénérée à une autre taille reste découpable telle quelle.
"""
from PIL import Image
import os

PLANCHE = "art/references/planches/arene_blocs_v1.png"
SORTIE = "art/references/decoupes/blocs"
COTE = 768

# nom -> (x0, y0, x1, y1) en fractions, calibrées le 21/08 sur planche
# de contrôle (boîtes tracées puis vérifiées au zoom, sujet entier,
# marges franches, aucun voisin dans le cadre).
BOITES = {
    "bloc_rouge_r2":  (546 / 1536, 714 / 1024, 592 / 1536, 770 / 1024),
    "bloc_vert_r2":   (594 / 1536, 713 / 1024, 641 / 1536, 771 / 1024),
    "bloc_violet_r2": (642 / 1536, 713 / 1024, 686 / 1536, 771 / 1024),
    "puits_r2":       (686 / 1536, 712 / 1024, 748 / 1536, 772 / 1024),
    "palmier_r2":     (902 / 1536, 708 / 1024, 958 / 1536, 772 / 1024),
    "cabane_r2":      (1052 / 1536, 242 / 1024, 1122 / 1536, 314 / 1024),
}


def decouper():
    src = Image.open(PLANCHE).convert("RGB")
    W, H = src.size
    os.makedirs(SORTIE, exist_ok=True)
    for nom, (x0, y0, x1, y1) in BOITES.items():
        c = src.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H)))
        # Fond du carré : le coin de la découpe elle-même — bande navy
        # pour les icônes, tuiles orangées pour la cabane. Un fond
        # cohérent avec le sujet évite le halo de détourage.
        fond = c.getpixel((1, 1))
        cote = int(max(c.size) * 1.10)
        carre = Image.new("RGB", (cote, cote), fond)
        carre.paste(c, ((cote - c.width) // 2, (cote - c.height) // 2))
        carre = carre.resize((COTE, COTE), Image.LANCZOS)
        chemin = os.path.join(SORTIE, nom + ".png")
        carre.save(chemin)
        print("%-16s -> %s" % (nom, chemin))


if __name__ == "__main__":
    decouper()
