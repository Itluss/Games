#!/usr/bin/env python3
"""ALLÈGEMENT D'UN .glb — réencode les textures embarquées.

POURQUOI : Meshy livre des cartes en 2048 px, soit une douzaine de Mo par
personnage. Sur un jeu web dont la build entière pèse 34 Mo, et qui vise
le mobile, c'est intenable — et parfaitement inutile : la caméra est en
plongée, un personnage occupe une centaine de pixels à l'écran.

CE QUI EST FAIT :
  • les cartes sont ramenées à une taille raisonnable ;
  • la carte NORMALE est supprimée par défaut, car l'éclairage cellulé du
    jeu ne l'exploite quasiment pas — c'est le plus gros gain pour la
    perte la moins visible ;
  • les cartes métallique et rugosité sont réduites très fortement : elles
    ne portent pratiquement aucun détail sur un rendu en aplats.

Un .glb est un conteneur binaire : en-tête, chunk JSON, chunk BIN. Les
images vivent dans le BIN, désignées par des « bufferViews ». Réécrire
une image oblige donc à reconstruire tout le BIN et à recalculer les
décalages de CHAQUE bufferView, y compris ceux de la géométrie.

Usage :
  python3 outils/alleger_glb.py entree.glb sortie.glb [--taille 1024]
"""
import argparse
import io
import json
import struct
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow est requis : pip install Pillow")

MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def lire_glb(chemin: str):
    with open(chemin, "rb") as f:
        donnees = f.read()
    magic, version, _total = struct.unpack_from("<III", donnees, 0)
    if magic != MAGIC:
        raise SystemExit("%s n'est pas un .glb binaire." % chemin)
    if version != 2:
        raise SystemExit("Version glTF %d non gérée." % version)

    gltf, binaire = None, b""
    pos = 12
    while pos < len(donnees):
        taille, genre = struct.unpack_from("<II", donnees, pos)
        pos += 8
        bloc = donnees[pos:pos + taille]
        pos += taille
        if genre == CHUNK_JSON:
            gltf = json.loads(bloc.decode("utf-8"))
        elif genre == CHUNK_BIN:
            binaire = bloc
    if gltf is None:
        raise SystemExit("Chunk JSON introuvable dans %s." % chemin)
    return gltf, binaire


def _aligner(donnees: bytearray, octet: bytes = b"\x00") -> None:
    while len(donnees) % 4 != 0:
        donnees += octet


def _roles_images(gltf: dict) -> dict:
    """Associe chaque index d'image au rôle qu'elle joue dans un matériau.

    C'est ce qui permet de traiter une carte normale autrement qu'une
    carte de couleur : elles n'ont ni le même poids visuel ni le même
    intérêt sur un rendu en aplats.
    """
    textures = gltf.get("textures", [])

    def image_de(info):
        if not info:
            return None
        t = textures[info["index"]] if info.get("index", -1) < len(textures) else None
        return t.get("source") if t else None

    roles = {}
    for mat in gltf.get("materials", []):
        pbr = mat.get("pbrMetallicRoughness", {}) or {}
        for info, role in (
            (pbr.get("baseColorTexture"), "base_color"),
            (pbr.get("metallicRoughnessTexture"), "metallic_roughness"),
            (mat.get("normalTexture"), "normal"),
            (mat.get("occlusionTexture"), "occlusion"),
            (mat.get("emissiveTexture"), "emissive"),
        ):
            idx = image_de(info)
            if idx is not None:
                roles[idx] = role
    return roles


def _retirer_normale(gltf: dict) -> int:
    retirees = 0
    for mat in gltf.get("materials", []):
        if mat.pop("normalTexture", None) is not None:
            retirees += 1
    return retirees


def alleger(entree: str, sortie: str, taille: int = 1024,
            garder_normale: bool = False, qualite: int = 88) -> None:
    gltf, binaire = lire_glb(entree)
    vues = gltf.get("bufferViews", [])
    images = gltf.get("images", [])
    roles = _roles_images(gltf)

    if not garder_normale:
        n = _retirer_normale(gltf)
        if n:
            print("Carte normale retirée de %d matériau(x)." % n)

    # Recalcul des rôles APRÈS suppression : une image devenue orpheline
    # ne sera plus référencée et pourra être réduite au minimum.
    roles_actifs = _roles_images(gltf)

    nouvelles = {}
    for i, img in enumerate(images):
        vue = img.get("bufferView")
        if vue is None:
            continue
        v = vues[vue]
        debut = v.get("byteOffset", 0)
        brut = binaire[debut:debut + v["byteLength"]]
        role = roles.get(i, "?")

        if i not in roles_actifs:
            # Image orpheline : réduite à un pixel plutôt que supprimée,
            # ce qui éviterait de renuméroter tout le document.
            im = Image.new("RGB", (1, 1), (128, 128, 255))
        else:
            im = Image.open(io.BytesIO(brut)).convert("RGB")
            cible = taille
            if role in ("metallic_roughness", "occlusion"):
                # Aucun détail fin à préserver sur un rendu en aplats.
                cible = min(256, taille)
            if max(im.size) > cible:
                ratio = cible / max(im.size)
                im = im.resize((max(1, int(im.width * ratio)),
                                max(1, int(im.height * ratio))), Image.LANCZOS)

        tampon = io.BytesIO()
        im.save(tampon, format="JPEG", quality=qualite, optimize=True)
        nouvelles[i] = tampon.getvalue()
        img["mimeType"] = "image/jpeg"
        print("  image %d (%-18s) %8d → %7d octets  %s"
              % (i, role, len(brut), len(nouvelles[i]), im.size))

    # Reconstruction complète du BIN : chaque bufferView est recopiée dans
    # l'ordre, avec un décalage recalculé. Les vues d'images prennent leur
    # nouveau contenu, les autres — géométrie, animations — sont intactes.
    remplacement = {}
    for i, octets in nouvelles.items():
        remplacement[images[i]["bufferView"]] = octets

    nouveau_bin = bytearray()
    for idx, v in enumerate(vues):
        _aligner(nouveau_bin)
        if idx in remplacement:
            contenu = remplacement[idx]
        else:
            d = v.get("byteOffset", 0)
            contenu = binaire[d:d + v["byteLength"]]
        v["byteOffset"] = len(nouveau_bin)
        v["byteLength"] = len(contenu)
        nouveau_bin += contenu
    _aligner(nouveau_bin)

    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(nouveau_bin)
        gltf["buffers"][0].pop("uri", None)

    json_bytes = bytearray(json.dumps(gltf, separators=(",", ":")).encode("utf-8"))
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total = 12 + 8 + len(json_bytes) + 8 + len(nouveau_bin)
    with open(sortie, "wb") as f:
        f.write(struct.pack("<III", MAGIC, 2, total))
        f.write(struct.pack("<II", len(json_bytes), CHUNK_JSON))
        f.write(json_bytes)
        f.write(struct.pack("<II", len(nouveau_bin), CHUNK_BIN))
        f.write(nouveau_bin)


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("entree")
    p.add_argument("sortie")
    p.add_argument("--taille", type=int, default=1024)
    p.add_argument("--garder-normale", action="store_true")
    p.add_argument("--qualite", type=int, default=88)
    a = p.parse_args()
    alleger(a.entree, a.sortie, a.taille, a.garder_normale, a.qualite)
