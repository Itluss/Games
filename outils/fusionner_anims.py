#!/usr/bin/env python3
"""FUSION D'ANIMATIONS — réunit plusieurs .glb en un seul.

POURQUOI : Meshy livre UN FICHIER PAR ANIMATION, et chacun réembarque le
maillage complet et sa texture 2048. Quatre animations pèsent donc 27 Mo
pour 27 Mo de doublons — le maillage et la texture sont bit-à-bit
identiques dans les cinq fichiers, ce qui a été vérifié avant d'écrire
cet outil.

Sur un jeu web qui vise le mobile, c'est intenable. On garde donc UN
maillage, UNE texture, et on y greffe toutes les pistes d'animation.

CE QUI EST COPIÉ : pour chaque animation source, ses échantillonneurs
renvoient à des accesseurs (temps en entrée, valeurs en sortie) ; ceux-ci
renvoient à des bufferViews, qui pointent dans le BIN. Il faut donc
recopier cette chaîne entière et renuméroter à chaque étage.

CE QUI NE L'EST PAS : les canaux désignent des NŒUDS. Comme la structure
de nœuds est identique d'un fichier à l'autre — vérifié, empreinte
comparée — les indices restent valables tels quels.

Usage :
  python3 outils/fusionner_anims.py sortie.glb base.glb autre.glb [...]
"""
import argparse
import json
import struct
import sys

MAGIC = 0x46546C67
CHUNK_JSON = 0x4E4F534A
CHUNK_BIN = 0x004E4942


def lire_glb(chemin):
    with open(chemin, "rb") as f:
        d = f.read()
    magic, version, _ = struct.unpack_from("<III", d, 0)
    if magic != MAGIC:
        raise SystemExit("%s n'est pas un .glb binaire." % chemin)
    if version != 2:
        raise SystemExit("Version glTF %d non gérée." % version)
    gltf, binaire, pos = None, b"", 12
    while pos < len(d):
        taille, genre = struct.unpack_from("<II", d, pos)
        pos += 8
        bloc = d[pos:pos + taille]
        pos += taille
        if genre == CHUNK_JSON:
            gltf = json.loads(bloc.decode("utf-8"))
        elif genre == CHUNK_BIN:
            binaire = bloc
    if gltf is None:
        raise SystemExit("Chunk JSON introuvable dans %s." % chemin)
    return gltf, binaire


def _signature_noeuds(g):
    return json.dumps([(n.get("name"), n.get("children"), n.get("mesh"),
                        n.get("skin")) for n in g.get("nodes", [])],
                      sort_keys=True)


def _nom_propre(brut, defaut):
    """« Armature|RunFast|baselayer » → « RunFast »."""
    if not brut:
        return defaut
    morceaux = [m for m in brut.split("|") if m and m.lower() not in
                ("armature", "baselayer", "mixamo.com")]
    return morceaux[-1] if morceaux else defaut


def fusionner(sortie, base_chemin, autres, renommer=None):
    gltf, binaire = lire_glb(base_chemin)
    bin_sortie = bytearray(binaire)
    signature = _signature_noeuds(gltf)

    vues = gltf.setdefault("bufferViews", [])
    accesseurs = gltf.setdefault("accessors", [])
    animations = gltf.setdefault("animations", [])

    # Renommer aussi l'animation de base, pour que toutes portent un nom
    # utilisable tel quel côté moteur.
    for a in animations:
        nom = _nom_propre(a.get("name"), "base")
        a["name"] = renommer.get(nom, nom) if renommer else nom
    print("base %-24s → %s" % (base_chemin, [a["name"] for a in animations]))

    for chemin in autres:
        g2, b2 = lire_glb(chemin)
        if _signature_noeuds(g2) != signature:
            # On refuse plutôt que de produire un fichier qui s'ouvrira
            # sans erreur mais animera les mauvais os.
            raise SystemExit(
                "%s n'a pas la même structure de nœuds que %s — fusion "
                "refusée." % (chemin, base_chemin))

        for anim in g2.get("animations", []):
            nom = _nom_propre(anim.get("name"), "anim%d" % len(animations))
            if renommer and nom in renommer:
                nom = renommer[nom]
            if any(a["name"] == nom for a in animations):
                print("  %s : « %s » déjà présente, ignorée." % (chemin, nom))
                continue

            # 1. accesseurs employés par cette animation
            besoins = set()
            for s in anim.get("samplers", []):
                besoins.add(s["input"])
                besoins.add(s["output"])

            # 2. recopie accesseur → bufferView → octets, en renumérotant
            corresp = {}
            for idx in sorted(besoins):
                acc = dict(g2["accessors"][idx])
                v_idx = acc.get("bufferView")
                if v_idx is not None:
                    vue = dict(g2["bufferViews"][v_idx])
                    debut = vue.get("byteOffset", 0)
                    octets = b2[debut:debut + vue["byteLength"]]
                    while len(bin_sortie) % 4:
                        bin_sortie += b"\x00"
                    vue["byteOffset"] = len(bin_sortie)
                    vue["byteLength"] = len(octets)
                    vue["buffer"] = 0
                    bin_sortie += octets
                    acc["bufferView"] = len(vues)
                    vues.append(vue)
                corresp[idx] = len(accesseurs)
                accesseurs.append(acc)

            neuve = {
                "name": nom,
                "samplers": [
                    {"input": corresp[s["input"]],
                     "output": corresp[s["output"]],
                     "interpolation": s.get("interpolation", "LINEAR")}
                    for s in anim.get("samplers", [])
                ],
                # Les canaux visent des nœuds, dont les indices sont
                # inchangés puisque la structure est identique.
                "channels": [dict(c) for c in anim.get("channels", [])],
            }
            animations.append(neuve)
            print("  %-24s + « %s » (%d canaux)"
                  % (chemin, nom, len(neuve["channels"])))

    while len(bin_sortie) % 4:
        bin_sortie += b"\x00"
    if gltf.get("buffers"):
        gltf["buffers"][0]["byteLength"] = len(bin_sortie)
        gltf["buffers"][0].pop("uri", None)

    corps = bytearray(json.dumps(gltf, separators=(",", ":")).encode("utf-8"))
    while len(corps) % 4:
        corps += b" "

    total = 12 + 8 + len(corps) + 8 + len(bin_sortie)
    with open(sortie, "wb") as f:
        f.write(struct.pack("<III", MAGIC, 2, total))
        f.write(struct.pack("<II", len(corps), CHUNK_JSON))
        f.write(corps)
        f.write(struct.pack("<II", len(bin_sortie), CHUNK_BIN))
        f.write(bin_sortie)
    print("→ %s : %d animation(s), %.2f Mo"
          % (sortie, len(animations), total / 1e6))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("sortie")
    p.add_argument("base")
    p.add_argument("autres", nargs="*")
    p.add_argument("--renommer", default="",
                   help="ancien=nouveau,ancien=nouveau")
    a = p.parse_args()
    ren = {}
    for paire in a.renommer.split(","):
        if "=" in paire:
            k, v = paire.split("=", 1)
            ren[k.strip()] = v.strip()
    fusionner(a.sortie, a.base, a.autres, ren)
