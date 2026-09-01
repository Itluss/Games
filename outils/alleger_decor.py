#!/usr/bin/env python3
"""ALLÈGEMENT DU MOBILIER D'ARÈNE — applique alleger_glb.py à tout le kit.

POURQUOI CE FICHIER EXISTE : Meshy livre ses cartes en 2048 px. Pour Kael,
cela faisait déjà 27 Mo à lui seul, ramenés à 1,3 Mo. Le kit de décor
compte QUINZE pièces : livrées telles quelles, elles pèseraient plus que
la build web entière (34 Mo), qui doit se télécharger avant que le joueur
ne voie quoi que ce soit.

POURQUOI LE DÉCOR PEUT DESCENDRE PLUS BAS QUE LE PERSONNAGE : la caméra
est en plongée et l'arène fait 68 m de large. Un abri de 2 m occupe donc
quelques dizaines de pixels à l'écran, contre une centaine pour le
personnage — qui, lui, est au centre de l'attention en permanence. Une
carte de 512 px y est déjà généreuse.

Le script est IDEMPOTENT au sens utile du terme : il écrit à côté puis
remplace, donc une interruption ne laisse jamais un .glb à moitié écrit.

Usage :
  python3 outils/alleger_decor.py [--taille 512]
"""
import argparse
import glob
import os
import subprocess
import sys

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MODELES = os.path.join(RACINE, "arena-rush", "assets", "models")
ALLEGER = os.path.join(RACINE, "outils", "alleger_glb.py")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--taille", type=int, default=512,
                   help="Côté maximal des cartes de texture (défaut 512).")
    p.add_argument("--motif", default="deco_*.glb",
                   help="Modèles à traiter (défaut : tout le kit de décor).")
    a = p.parse_args()

    fichiers = sorted(glob.glob(os.path.join(MODELES, a.motif)))
    if not fichiers:
        print("Aucun modèle ne correspond à « %s » dans %s." % (a.motif, MODELES))
        return 0

    avant_total = 0
    apres_total = 0
    echecs = []
    for src in fichiers:
        avant = os.path.getsize(src)
        tmp = src + ".tmp"
        r = subprocess.run(
            [sys.executable, ALLEGER, src, tmp, "--taille", str(a.taille)],
            capture_output=True, text=True)
        if r.returncode != 0 or not os.path.exists(tmp):
            # On NE TOUCHE PAS à l'original quand l'allègement échoue : un
            # modèle lourd reste infiniment préférable à un modèle absent.
            print("  ✗ %s — allègement échoué, original conservé"
                  % os.path.basename(src))
            print((r.stderr or r.stdout or "").strip()[:300])
            echecs.append(src)
            if os.path.exists(tmp):
                os.remove(tmp)
            continue
        apres = os.path.getsize(tmp)
        os.replace(tmp, src)
        avant_total += avant
        apres_total += apres
        print("  %-24s %6d Ko → %5d Ko"
              % (os.path.basename(src), avant // 1024, apres // 1024))

    if avant_total:
        print("\nTotal : %d Ko → %d Ko (%.0f %% économisés) sur %d modèle(s)."
              % (avant_total // 1024, apres_total // 1024,
                 100.0 * (1.0 - apres_total / float(avant_total)),
                 len(fichiers) - len(echecs)))
    if echecs:
        print("%d modèle(s) non allégé(s)." % len(echecs))
    return 0


if __name__ == "__main__":
    sys.exit(main())
