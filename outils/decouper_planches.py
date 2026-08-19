#!/usr/bin/env python3
"""DÉCOUPE LES PLANCHES DE RÉFÉRENCE EN SUJETS ISOLÉS.

Meshy `image-to-3d` attend UN sujet par image. Une planche entière —
quatre héros, des titres, des badges, des vignettes — produirait une
bouillie. Ce script en extrait chaque sujet, efface le texte, centre dans
un carré à fond uni, et écrit dans art/references/decoupes/.

    python3 outils/decouper_planches.py

LES COORDONNÉES SONT EN FRACTIONS, jamais en pixels : une planche
regénérée à une autre taille reste découpable sans retoucher une ligne.
"""
from PIL import Image, ImageDraw
import os

PLANCHES = "art/references/planches"
SORTIE = "art/references/decoupes"
FOND = (247, 240, 224)
COTE = 768

# planche -> { nom : (x0, y0, x1, y1) en fractions }
# LA PLANCHE V2 EST DECOUPEE PAR GRILLE, pas par coordonnees ecrites une
# par une : elle est parfaitement reguliere, 3 colonnes sur 2 rangees, et
# chaque cellule place sa grande figure au meme endroit. Une grille tient
# en quatre nombres et ne se desynchronise pas.
GRILLE_V2 = {
    "planche": "planche_heros_v2_detoure.png",
    "fond": (245, 245, 245),
    "colonnes": 3,
    "rangees": 2,
    # Fenetre de la grande figure, en fraction de sa cellule.
    "fenetre": (0.015, 0.155, 0.500, 0.755),
    "noms": [["hero_milo", "hero_poppy", "hero_bruno"],
             ["hero_nox", "hero_ruby", "hero_gus"]],
    "sortie": "heros_v2",
}

DECOUPES = {
    "heros": ("planche_heros.png", FOND, {
        "hero_brute": (0.045, 0.190, 0.495, 0.448),
        "hero_zippy": (0.505, 0.190, 0.955, 0.448),
        "hero_spark": (0.045, 0.608, 0.495, 0.828),
        "hero_bolt":  (0.505, 0.608, 0.955, 0.828),
    }),
}

# Zones de texte à repeindre, en fractions de la découpe.
MASQUES = [
    (0.0, 0.0, 0.44, 0.155),      # badge de rôle, en haut à gauche
    (0.0, 0.87, 1.0, 1.0),        # bandeau « VUE TOP-DOWN / SIGNATURE »
    (0.0, 0.0, 0.012, 1.0),       # liseré gauche de la carte
    (0.988, 0.0, 1.0, 1.0),       # liseré droit
]


def decouper():
    for lot, (fichier, fond, zones) in DECOUPES.items():
        chemin = os.path.join(PLANCHES, fichier)
        src = Image.open(chemin).convert("RGB")
        W, H = src.size
        dossier = os.path.join(SORTIE, lot)
        os.makedirs(dossier, exist_ok=True)
        for nom, (x0, y0, x1, y1) in zones.items():
            c = src.crop((int(x0 * W), int(y0 * H), int(x1 * W), int(y1 * H)))
            d = ImageDraw.Draw(c)
            w, h = c.size
            for mx0, my0, mx1, my1 in MASQUES:
                d.rectangle([int(w * mx0), int(h * my0),
                             int(w * mx1), int(h * my1)], fill=fond)
            cote = max(w, h)
            carre = Image.new("RGB", (cote, cote), fond)
            carre.paste(c, ((cote - w) // 2, (cote - h) // 2))
            carre = carre.resize((COTE, COTE), Image.LANCZOS)
            sortie = os.path.join(dossier, nom + ".png")
            carre.save(sortie)
            print("%-14s -> %s" % (nom, sortie))


def decouper_grille(g):
    """Decoupe une planche reguliere : une figure par cellule."""
    src = Image.open(os.path.join(PLANCHES, g["planche"])).convert("RGB")
    W, H = src.size
    dossier = os.path.join(SORTIE, g["sortie"])
    os.makedirs(dossier, exist_ok=True)
    fx0, fy0, fx1, fy1 = g["fenetre"]
    dx = 1.0 / g["colonnes"]
    dy = 1.0 / g["rangees"]
    for r in range(g["rangees"]):
        for c in range(g["colonnes"]):
            im = src.crop((
                int((c * dx + dx * fx0) * W), int((r * dy + dy * fy0) * H),
                int((c * dx + dx * fx1) * W), int((r * dy + dy * fy1) * H)))
            # Carre a fond uni : Meshy centre mieux un sujet carre, et une
            # image tres haute le pousse a etirer le modele.
            cote = int(max(im.size) * 1.06)
            carre = Image.new("RGB", (cote, cote), g["fond"])
            carre.paste(im, ((cote - im.width) // 2, (cote - im.height) // 2))
            carre = carre.resize((COTE, COTE), Image.LANCZOS)
            sortie = os.path.join(dossier, g["noms"][r][c] + ".png")
            carre.save(sortie)
            print("%-14s -> %s" % (g["noms"][r][c], sortie))


if __name__ == "__main__":
    decouper()
    decouper_grille(GRILLE_V2)
