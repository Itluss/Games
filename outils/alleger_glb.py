#!/usr/bin/env python3
"""ALLÈGE UN .glb EN RÉDUISANT LES TEXTURES QU'IL EMBARQUE.

POURQUOI CET OUTIL EXISTE. Le lot HÉROS est sorti à 10 Mo par personnage,
soit 64 Mo à six, pour un build web qui en fait douze au total. On a
d'abord cru pouvoir réutiliser la récupération de lot, qui « allège les
textures » — sans effet. La mesure a dit pourquoi : les props Meshy
livrent leurs cartes PBR dans un dossier `-textures` À CÔTÉ du modèle,
alors que les personnages les EMBARQUENT dans le .glb lui-même. Sur
hero_bruno, le morceau binaire pèse 10,2 Mo dont 9,7 d'images. Réduire des
fichiers voisins ne pouvait rien y changer.

CE QUE FAIT CET OUTIL. Il ouvre le conteneur, décode chaque image
embarquée, la réduit, la ré-encode, et réécrit le .glb avec un tampon
binaire reconstruit. La géométrie n'est pas touchée : un modèle allégé a
exactement les mêmes sommets que l'original.

    python3 outils/alleger_glb.py fichier.glb [...] [--taille 512]

POURQUOI 512 PIXELS. La caméra du jeu est à 10,4 m au-dessus du joueur ;
un héros y occupe quelques centaines de pixels de haut sur un écran de
téléphone. Une texture 4K sur cette surface, c'est payer seize fois le
prix d'un détail que personne ne verra jamais.
"""
import io
import json
import os
import struct
import sys

from PIL import Image

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def _lire(chemin):
    d = open(chemin, "rb").read()
    magic, version, total = struct.unpack("<III", d[:12])
    if magic != 0x46546C67:
        raise SystemExit("%s : ce n'est pas un .glb" % chemin)
    off, morceaux = 12, {}
    while off < total:
        longueur, typ = struct.unpack("<II", d[off:off + 8])
        morceaux[typ] = d[off + 8:off + 8 + longueur]
        off += 8 + longueur
    return json.loads(morceaux[JSON_CHUNK]), bytearray(morceaux.get(BIN_CHUNK, b""))


def _reduire(brut, mime, taille):
    """Réduit une image, en gardant son format d'origine.

    LE FORMAT EST CONSERVÉ, ET CE N'EST PAS UN DÉTAIL. Une carte de
    normales ré-encodée en JPEG se couvre d'artefacts de compression qui
    se lisent comme des bosses : le relief devient sale. Les normales
    restent donc en PNG, l'albédo et la rugosité en JPEG.
    """
    im = Image.open(io.BytesIO(brut))
    if max(im.size) <= taille:
        return brut, im.size, im.size
    avant = im.size
    ratio = taille / float(max(im.size))
    im = im.resize((max(1, int(im.width * ratio)), max(1, int(im.height * ratio))),
                   Image.LANCZOS)
    sortie = io.BytesIO()
    if mime == "image/png":
        im.save(sortie, "PNG", optimize=True)
    else:
        im.convert("RGB").save(sortie, "JPEG", quality=88, optimize=True)
    return sortie.getvalue(), avant, im.size


def alleger(chemin, taille=512):
    g, binaire = _lire(chemin)
    images = g.get("images", [])
    if not images:
        print("%-28s aucune image embarquée" % os.path.basename(chemin))
        return

    # Nouvelles données par bufferView d'image.
    remplacements = {}
    for im in images:
        bv = im.get("bufferView")
        if bv is None:
            continue
        vue = g["bufferViews"][bv]
        deb = vue.get("byteOffset", 0)
        brut = bytes(binaire[deb:deb + vue["byteLength"]])
        neuf, avant, apres = _reduire(brut, im.get("mimeType", "image/png"), taille)
        remplacements[bv] = neuf
        print("    %-22s %sx%s → %sx%s   %.2f → %.2f Mo"
              % (im.get("name", "?"), avant[0], avant[1], apres[0], apres[1],
                 len(brut) / 1e6, len(neuf) / 1e6))

    # RECONSTRUCTION DU TAMPON, vue par vue, dans l'ordre des index.
    #
    # On ne peut pas se contenter de remplacer les octets sur place : une
    # image réduite est plus courte, et tout ce qui la suit se décale. On
    # réécrit donc chaque vue à la queue leu leu en recalculant son
    # décalage. Les accesseurs, eux, ne bougent pas : ils désignent une
    # vue par son INDEX et un décalage À L'INTÉRIEUR de cette vue, deux
    # choses que cette opération préserve.
    neuf = bytearray()
    for i, vue in enumerate(g.get("bufferViews", [])):
        deb = vue.get("byteOffset", 0)
        donnees = (remplacements[i] if i in remplacements
                   else bytes(binaire[deb:deb + vue["byteLength"]]))
        # Alignement sur quatre octets : la spécification l'exige pour les
        # vues lues par un accesseur, et un tampon désaligné plante des
        # moteurs sans message clair.
        while len(neuf) % 4:
            neuf.append(0)
        vue["byteOffset"] = len(neuf)
        vue["byteLength"] = len(donnees)
        neuf.extend(donnees)
    while len(neuf) % 4:
        neuf.append(0)
    if g.get("buffers"):
        g["buffers"][0]["byteLength"] = len(neuf)

    corps = json.dumps(g, separators=(",", ":")).encode("utf-8")
    corps += b" " * ((4 - len(corps) % 4) % 4)
    total = 12 + 8 + len(corps) + 8 + len(neuf)
    with open(chemin, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(corps), JSON_CHUNK))
        f.write(corps)
        f.write(struct.pack("<II", len(neuf), BIN_CHUNK))
        f.write(neuf)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    t = 512
    if "--taille" in sys.argv:
        t = int(sys.argv[sys.argv.index("--taille") + 1])
    for chemin in args:
        avant = os.path.getsize(chemin)
        print("%s (%.1f Mo)" % (os.path.basename(chemin), avant / 1e6))
        alleger(chemin, t)
        apres = os.path.getsize(chemin)
        print("  → %.1f Mo  (−%.0f %%)\n" % (apres / 1e6, 100 * (1 - apres / avant)))
