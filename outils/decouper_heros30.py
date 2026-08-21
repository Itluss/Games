#!/usr/bin/env python3
"""DÉCOUPE LA PLANCHE DES 30 HÉROS-MASCOTTES EN SUJETS ISOLÉS.

La planche heros30_generation est FAITE pour la génération : fond clair
uni, aucun texte, aucun badge, grille régulière 6×5 — la version corrigée
de la planche-bible (fond sombre, textes) après l'analyse d'exploitabilité.
Une figure par cellule, carré 768 sur le fond de la planche elle-même.

    python3 outils/decouper_heros30.py

L'ordre des noms suit la planche-bible heros30_bible, cellule par
cellule, rangée par rangée. Les deux planches partagent le même ordre —
vérifié à l'œil sur les deux avant d'écrire ce tableau.
"""
from PIL import Image
import os

PLANCHE = "art/references/planches/heros30_generation.png"
SORTIE = "art/references/decoupes/heros30"
COTE = 768

# LA GRILLE EST MESURÉE, PAS SUPPOSÉE. La division uniforme en sixièmes
# et cinquièmes coupait les pieds d'une rangée dans la case du dessous :
# les cellules de la planche ne sont pas régulières. Les bandes ci-dessous
# viennent de la détection des gouttières blanches (lignes quasi uniformes
# et claires), en fractions de la planche d'origine (1536 × 1024).
BANDES_X = [(20, 214), (278, 472), (534, 725),
            (777, 977), (1023, 1234), (1285, 1481)]
BANDES_Y = [(25, 227), (245, 434), (455, 619), (638, 799), (818, 982)]
BASE_W = 1536.0
BASE_H = 1024.0

NOMS = [
    ["ruby", "flare", "root", "bone", "ninja", "pixel"],
    ["spore", "corsair", "gizmo", "knight", "prick", "shade"],
    ["frost", "boom", "buzz", "pumpkin", "ram", "tiki"],
    ["wisp", "stone", "scout", "doc", "rex", "potion"],
    ["vik", "brawl", "arrow", "digger", "chef", "slime"],
]


def decouper():
    src = Image.open(PLANCHE).convert("RGB")
    W, H = src.size
    os.makedirs(SORTIE, exist_ok=True)
    # Le fond du carré est celui de la planche : un coin de gouttière,
    # jamais un blanc codé en dur qui jurerait au raccord.
    fond = src.getpixel((4, 4))
    for r, (y0, y1) in enumerate(BANDES_Y):
        for c, (x0, x1) in enumerate(BANDES_X):
            im = src.crop((int(x0 / BASE_W * W), int(y0 / BASE_H * H),
                           int(x1 / BASE_W * W), int(y1 / BASE_H * H)))
            cote = int(max(im.size) * 1.06)
            carre = Image.new("RGB", (cote, cote), fond)
            carre.paste(im, ((cote - im.width) // 2, (cote - im.height) // 2))
            carre = carre.resize((COTE, COTE), Image.LANCZOS)
            chemin = os.path.join(SORTIE, NOMS[r][c] + ".png")
            carre.save(chemin)
            print("%-8s -> %s" % (NOMS[r][c], chemin))


if __name__ == "__main__":
    decouper()
