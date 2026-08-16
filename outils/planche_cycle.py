#!/usr/bin/env python3
"""PLANCHE DE CONTACT + GIF d'un cycle d'animation.

POURQUOI : une animation ne se juge pas sur une image. La planche met le
cycle entier sous les yeux d'un coup — on y voit immédiatement si une
jambe reste tendue, si les deux jambes font la même chose, ou si le corps
ne monte jamais. Le GIF, lui, se juge en mouvement, ce qui reste le seul
verdict qui compte.

Usage :
  python3 outils/planche_cycle.py DOSSIER SORTIE [--prefixe course]
"""
import argparse
import glob
import os
import re
import sys

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("Pillow est requis : pip install Pillow")


def _images(dossier: str, prefixe: str, vue: str):
    motif = os.path.join(dossier, "%s_%s_*.png" % (prefixe, vue))
    fichiers = sorted(glob.glob(motif),
                      key=lambda c: int(re.findall(r"(\d+)\.png$", c)[0]))
    return fichiers


def planche(fichiers, sortie: str, colonnes: int = 8, echelle: float = 0.6):
    if not fichiers:
        return False
    vignettes = []
    for i, c in enumerate(fichiers):
        im = Image.open(c).convert("RGB")
        im = im.resize((int(im.width * echelle), int(im.height * echelle)),
                       Image.LANCZOS)
        d = ImageDraw.Draw(im)
        # Numéroter chaque case : sans repère, impossible de dire de quelle
        # image on parle quand on décrit un défaut.
        d.rectangle([0, 0, 22, 14], fill=(0, 0, 0))
        d.text((4, 3), "%02d" % i, fill=(255, 220, 120))
        vignettes.append(im)

    lignes = (len(vignettes) + colonnes - 1) // colonnes
    w, h = vignettes[0].size
    feuille = Image.new("RGB", (colonnes * w, lignes * h), (24, 26, 32))
    for i, v in enumerate(vignettes):
        feuille.paste(v, ((i % colonnes) * w, (i // colonnes) * h))
    feuille.save(sortie)
    print("Planche : %s (%d images)" % (sortie, len(vignettes)))
    return True


def gif(fichiers, sortie: str, ms: int = 55, echelle: float = 0.75):
    if not fichiers:
        return False
    trames = []
    for c in fichiers:
        im = Image.open(c).convert("RGB")
        im = im.resize((int(im.width * echelle), int(im.height * echelle)),
                       Image.LANCZOS)
        trames.append(im.convert("P", palette=Image.ADAPTIVE, colors=128))
    trames[0].save(sortie, save_all=True, append_images=trames[1:],
                   duration=ms, loop=0, optimize=True)
    print("GIF : %s (%.0f Ko)" % (sortie, os.path.getsize(sortie) / 1024))
    return True


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("dossier")
    p.add_argument("sortie")
    p.add_argument("--prefixe", default="course")
    p.add_argument("--vues", default="profil,jeu")
    a = p.parse_args()

    os.makedirs(a.sortie, exist_ok=True)
    for vue in a.vues.split(","):
        f = _images(a.dossier, a.prefixe, vue)
        if not f:
            print("Aucune image pour la vue « %s »." % vue)
            continue
        planche(f, os.path.join(a.sortie, "%s_%s_planche.png" % (a.prefixe, vue)))
        gif(f, os.path.join(a.sortie, "%s_%s.gif" % (a.prefixe, vue)))
