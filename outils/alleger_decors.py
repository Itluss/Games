#!/usr/bin/env python3
"""Allège les décors 3D — la seule optimisation qui compte sur téléphone.

POURQUOI CET OUTIL EXISTE
-------------------------
Meshy livre des modèles denses : une caisse en bois sort à 954 triangles,
un rocher à 4 712. C'est le bon réglage pour une vitrine, pas pour un jeu
qui tourne dans un navigateur de téléphone. Et le réflexe habituel — « le
moteur fera du LOD » — ne s'applique pas ici : la version web tourne en
rendu Compatibility, qui ignore les niveaux de détail générés à l'import.
Mesuré : un rocher à 400 mètres dessine ses 4 712 triangles, comme à 6.

Donc si on veut que ça allège, il faut alléger À LA SOURCE.

CE QUE FAIT L'OUTIL
-------------------
1. Il retire des matériaux la carte de normales et la carte
   métallique-rugosité. Sur un tonneau en bois, la seconde ne décrit rien ;
   la première coûte une lecture de texture par pixel pour un relief qu'on
   ne distingue pas à la distance de jeu. Les retirer sert le rendu ET la
   direction artistique : la référence demandée est franche et lisible,
   pas photoréaliste.
2. Il CUIT LA COULEUR DANS LES SOMMETS avant de décimer, et c'est le
   coeur de l'affaire. Un maillage Meshy est entièrement décousu : 9 824
   sommets pour 4 712 triangles, parce que chaque triangle porte son
   propre morceau de dépliage UV. Tant que la texture est là, le
   simplificateur refuse de souder ces sommets — il ne descend que de
   13 %, et si on le force (option agressive) il soude quand même et le
   dépliage part en morceaux : la couleur est alors lue n'importe où et
   les rochers virent au noir. Vérifié en capture, c'était laid.

   En échantillonnant la texture À CHAQUE SOMMET puis en la jetant, la
   couleur cesse de dépendre du dépliage. Le simplificateur peut souder
   librement, et les teintes se moyennent proprement au passage. C'est le
   procédé des jeux dont on a pris la direction artistique en référence :
   des formes franches, une couleur par sommet, aucune texture à lire.

3. Il décime la géométrie jusqu'à un budget fixé modèle par modèle, avec
   gltfpack (meshoptimizer). Le budget n'est pas un pourcentage uniforme :
   il dépend de la taille du décor à l'écran et de l'importance de sa
   silhouette. Un rocher garde de quoi rester un rocher ; une caisse est
   une caisse à soixante triangles.
4. Les images devenues inutiles disparaissent du fichier — c'est autant de
   moins à télécharger avant la première partie.

L'ORIGINAL N'EST PAS PERDU, mais il n'est plus dans l'arbre de travail :
il est dans l'historique git. Pour rejouer l'outil avec d'autres budgets,
il faut donc d'abord restaurer les sources :

    git checkout <commit-avant-allègement> -- arena-rush/assets/models/
    python3 outils/alleger_decors.py

La garde `_deja_allege` empêche de décimer une sortie déjà allégée — sans
elle, une seconde exécution repartirait du modèle réduit et le réduirait
encore, jusqu'à le faire fondre.

TOUT NOUVEAU DÉCOR SORTI DE MESHY DOIT PASSER PAR ICI avant d'être posé
sur la carte, sinon il rapporte à lui seul plusieurs milliers de triangles.

Usage :
    python3 outils/alleger_decors.py             # applique en place
    python3 outils/alleger_decors.py --verifier  # écrit des .apercu.glb
    python3 outils/alleger_decors.py --planche   # prépare la comparaison
                                                 # A/B/C pour l'aperçu Godot
"""

import json
import shutil
import struct
import subprocess
import sys
from pathlib import Path

RACINE = Path(__file__).resolve().parent.parent
MODELES = RACINE / "arena-rush" / "assets" / "models"
GLTFPACK = "/tmp/node_modules/.bin/gltfpack"

# ── CE QU'ON FAIT À CHAQUE DÉCOR ───────────────────────────────────────
#
# Trois modes, et le choix se fait EN REGARDANT une planche de comparaison
# (outils_dev/apercu_variantes.tscn), jamais au jugé.
#
#   "agressif" : le simplificateur a le droit de souder des sommets que la
#       topologie séparait. C'est le seul mode qui réduit vraiment ces
#       maillages, parce qu'ils sont entièrement décousus — 9 824 sommets
#       pour 4 712 triangles sur un rocher. Il convient aux formes
#       organiques, dont la silhouette survit à la soudure.
#
#   "doux" : soudure interdite à travers les discontinuités. La forme est
#       garantie intacte, le gain est modeste (une quinzaine de pour cent).
#       C'est le mode des objets FABRIQUÉS — caisse, tonneau, barrière,
#       botte de foin, muret. Vu sur planche : en mode agressif la caisse
#       devient un galet, la barrière un tas, le muret un monticule lisse.
#       Ces objets tiennent leur lecture de leurs arêtes vives ; les souder
#       les détruit.
#
#   "aucun" : on ne touche pas à la géométrie.
#
# TOUS passent en revanche par la cuisson de couleur, qui est gratuite à
# l'oeil — vérifié modèle par modèle, la colonne « couleur cuite » de la
# planche est indiscernable de l'original — et qui retire trois textures
# par décor.
MODES = {
    "west_rock_formation_a": ("agressif", 1400),
    "west_rock_formation_b": ("agressif", 1400),
    "west_rock_small": ("agressif", 600),
    "west_cactus_a": ("agressif", 500),
    "west_wagon": ("agressif", 2000),
    "west_crate": ("doux", 0),
    "west_barrel": ("doux", 0),
    "west_haybale": ("doux", 0),
    "west_fence_straight": ("doux", 0),
    "west_sign_wood": ("doux", 0),
    "west_stonewall_short": ("doux", 0),
    "west_stonewall_straight": ("doux", 0),
}
BUDGETS = {nom: b for nom, (_m, b) in MODES.items()}


def _lire_glb(chemin: Path):
    """Rend (json, binaire) d'un .glb."""
    brut = chemin.read_bytes()
    if brut[:4] != b"glTF":
        raise ValueError(f"{chemin.name} n'est pas un .glb")
    pos, morceaux = 12, []
    while pos < len(brut):
        taille, type_ = struct.unpack_from("<II", brut, pos)
        morceaux.append((type_, brut[pos + 8 : pos + 8 + taille]))
        pos += 8 + taille
    j = json.loads(morceaux[0][1].decode("utf-8"))
    binaire = morceaux[1][1] if len(morceaux) > 1 else b""
    return j, binaire


def _ecrire_glb(chemin: Path, j, binaire: bytes) -> None:
    tete = json.dumps(j, separators=(",", ":")).encode("utf-8")
    tete += b" " * ((4 - len(tete) % 4) % 4)
    corps = binaire + b"\0" * ((4 - len(binaire) % 4) % 4)
    total = 12 + 8 + len(tete) + (8 + len(corps) if corps else 0)
    out = bytearray(struct.pack("<4sII", b"glTF", 2, total))
    out += struct.pack("<II", len(tete), 0x4E4F534A) + tete
    if corps:
        out += struct.pack("<II", len(corps), 0x004E4942) + corps
    chemin.write_bytes(out)


def _triangles(j) -> int:
    """Compte les triangles déclarés dans le glTF, sans passer par gltfpack."""
    total = 0
    for maillage in j.get("meshes", []):
        for prim in maillage.get("primitives", []):
            if "indices" in prim:
                total += j["accessors"][prim["indices"]]["count"] // 3
            elif "POSITION" in prim.get("attributes", {}):
                total += j["accessors"][prim["attributes"]["POSITION"]]["count"] // 3
    return total


def _deja_allege(j) -> bool:
    """Un fichier déjà passé porte notre marque : on ne décime pas deux fois.

    Sans cette garde, une seconde exécution partirait de la version allégée
    et la réduirait encore — le décor fondrait à chaque passage.
    """
    return j.get("asset", {}).get("extras", {}).get("arena_rush_allege") is True


def _depouiller_materiaux(j) -> int:
    """Retire TOUTES les textures : la couleur vit maintenant dans les sommets.

    La carte de normales et la métallique-rugosité partent pour le coût —
    trois lectures par pixel sur un GPU de téléphone. La couleur de base
    part parce qu'elle a été recopiée dans les sommets juste avant, et que
    la garder rendrait la soudure impossible.
    """
    n = 0
    for mat in j.get("materials", []):
        if mat.pop("normalTexture", None) is not None:
            n += 1
        mat.pop("occlusionTexture", None)
        mat.pop("emissiveTexture", None)
        pbr = mat.get("pbrMetallicRoughness")
        if pbr and pbr.pop("metallicRoughnessTexture", None) is not None:
            n += 1
        if pbr and pbr.pop("baseColorTexture", None) is not None:
            n += 1
        if pbr is not None:
            # Blanc : la teinte vient des sommets, ce facteur ne doit rien
            # y retrancher.
            pbr["baseColorFactor"] = [1.0, 1.0, 1.0, 1.0]
            # Sans carte, ces deux valeurs décident seules du reflet. Un
            # décor mat et franc lit mieux qu'un décor vaguement luisant.
            pbr["metallicFactor"] = 0.0
            pbr["roughnessFactor"] = 1.0
    return n


def _image_pil(j, binaire: bytes, index: int):
    """Décode une image embarquée du glb."""
    from PIL import Image
    import io
    vue = j["bufferViews"][j["images"][index]["bufferView"]]
    debut = vue.get("byteOffset", 0)
    return Image.open(io.BytesIO(binaire[debut : debut + vue["byteLength"]])).convert("RGB")


def _lire_accesseur(j, binaire: bytes, index: int, composantes: int):
    """Rend la liste plate des flottants d'un accesseur VEC2/VEC3 non entrelacé."""
    acc = j["accessors"][index]
    vue = j["bufferViews"][acc["bufferView"]]
    debut = vue.get("byteOffset", 0) + acc.get("byteOffset", 0)
    n = acc["count"] * composantes
    return struct.unpack_from("<%df" % n, binaire, debut)


def _lire_indices(j, binaire: bytes, index: int):
    acc = j["accessors"][index]
    vue = j["bufferViews"][acc["bufferView"]]
    debut = vue.get("byteOffset", 0) + acc.get("byteOffset", 0)
    format_ = {5121: "B", 5123: "H", 5125: "I"}[acc["componentType"]]
    return struct.unpack_from("<%d%s" % (acc["count"], format_), binaire, debut)


def _cuire_couleurs(j, binaire: bytes) -> tuple:
    """Échantillonne la couleur de base à chaque sommet et l'y inscrit.

    Rend le binaire agrandi. Après cette étape la texture ne sert plus à
    rien : c'est ce qui autorise la soudure agressive de l'étape suivante.
    """
    mat_image = {}
    for i, mat in enumerate(j.get("materials", [])):
        pbr = mat.get("pbrMetallicRoughness") or {}
        tex = pbr.get("baseColorTexture")
        if tex is not None:
            src = j["textures"][tex["index"]].get("source")
            if src is not None:
                mat_image[i] = _image_pil(j, binaire, src)

    ajout = bytearray()
    base = len(binaire)
    for maillage in j.get("meshes", []):
        for prim in maillage.get("primitives", []):
            attrs = prim.get("attributes", {})
            if "TEXCOORD_0" not in attrs:
                continue
            img = mat_image.get(prim.get("material"))
            if img is None:
                continue
            uv = _lire_accesseur(j, binaire, attrs["TEXCOORD_0"], 2)
            lg, ht = img.size
            pix = img.load()
            n = len(uv) // 2

            def prelever(u: float, v: float):
                x = min(int((u % 1.0) * lg), lg - 1)
                y = min(int((v % 1.0) * ht), ht - 1)
                return pix[x, y]

            # ─── ON PRÉLÈVE AU CENTRE DU TRIANGLE, PAS AU SOMMET ───────
            #
            # Un sommet posé sur le bord d'un îlot UV tombe, à un pixel
            # près, dans le vide de l'atlas — qui est noir. En cuisant la
            # couleur au sommet, ces bords semaient des taches noires sur
            # les décors ; vu en capture, c'était le défaut le plus
            # visible du premier essai. Le barycentre d'un triangle est
            # toujours à l'intérieur de son îlot : il ne peut pas tomber
            # dans le vide. Chaque sommet reçoit la moyenne des centres
            # des triangles qui le touchent, ce qui lisse au passage
            # l'occlusion cuite dans la texture.
            somme = [[0.0, 0.0, 0.0] for _ in range(n)]
            compte = [0] * n
            if "indices" in prim:
                idx = _lire_indices(j, binaire, prim["indices"])
                for t in range(0, len(idx) - 2, 3):
                    a, b_, c = idx[t], idx[t + 1], idx[t + 2]
                    u = (uv[2 * a] + uv[2 * b_] + uv[2 * c]) / 3.0
                    v = (uv[2 * a + 1] + uv[2 * b_ + 1] + uv[2 * c + 1]) / 3.0
                    r, vt, bl = prelever(u, v)
                    for s_ in (a, b_, c):
                        somme[s_][0] += r
                        somme[s_][1] += vt
                        somme[s_][2] += bl
                        compte[s_] += 1

            octets = bytearray()
            for k in range(n):
                if compte[k]:
                    r = somme[k][0] / compte[k]
                    vt = somme[k][1] / compte[k]
                    bl = somme[k][2] / compte[k]
                else:
                    r, vt, bl = prelever(uv[2 * k], uv[2 * k + 1])
                # OCTETS NORMALISÉS, pas des flottants : quatre octets par
                # sommet au lieu de seize. Sur un décor peu décimé — une
                # barrière garde 2 700 sommets — l'écart se voit dans le
                # poids du fichier, donc dans le temps de chargement.
                octets += struct.pack("<4B", int(r), int(vt), int(bl), 255)

            offset = base + len(ajout)
            ajout += octets
            j["bufferViews"].append({
                "buffer": 0, "byteOffset": offset, "byteLength": len(octets),
            })
            j["accessors"].append({
                "bufferView": len(j["bufferViews"]) - 1, "componentType": 5121,
                "normalized": True, "count": n, "type": "VEC4",
            })
            attrs["COLOR_0"] = len(j["accessors"]) - 1

    if not ajout:
        return binaire
    binaire = binaire + bytes(ajout)
    j["buffers"][0]["byteLength"] = len(binaire)
    return binaire


def _elaguer_images(j) -> int:
    """Supprime les images que plus aucun matériau n'atteint.

    Retirer la référence ne suffit pas : l'image reste dans le fichier et
    continue d'être téléchargée. Or la carte de normales pèse à elle seule
    529 Ko sur un rocher — plus que toute sa géométrie. C'est ce poste-là
    qui fait attendre le joueur devant l'écran de chargement.

    On ne touche pas aux `bufferViews` : gltfpack reconstruit le tampon de
    zéro derrière nous et ne garde que ce qui est encore référencé.
    """
    textures = j.get("textures", [])
    images = j.get("images", [])
    if not images:
        return 0

    gardees = set()
    for mat in j.get("materials", []):
        for bloc in (mat, mat.get("pbrMetallicRoughness") or {}):
            for cle, val in bloc.items():
                if isinstance(val, dict) and "index" in val and cle.endswith("Texture"):
                    gardees.add(val["index"])
        for cle in ("emissiveTexture", "occlusionTexture"):
            if cle in mat:
                gardees.add(mat[cle]["index"])

    src_gardees = {textures[t]["source"] for t in gardees if "source" in textures[t]}
    ordre_img = sorted(src_gardees)
    remap_img = {vieux: neuf for neuf, vieux in enumerate(ordre_img)}
    ordre_tex = sorted(gardees)
    remap_tex = {vieux: neuf for neuf, vieux in enumerate(ordre_tex)}

    retires = len(images) - len(ordre_img)
    j["images"] = [images[i] for i in ordre_img]
    j["textures"] = [dict(textures[t], source=remap_img[textures[t]["source"]])
                     for t in ordre_tex]
    for mat in j.get("materials", []):
        for bloc in (mat, mat.get("pbrMetallicRoughness") or {}):
            for cle, val in list(bloc.items()):
                if isinstance(val, dict) and "index" in val and cle.endswith("Texture"):
                    val["index"] = remap_tex[val["index"]]
    return retires


def _alleger(source: Path, verifier: bool) -> tuple:
    nom = source.stem
    mode, budget = MODES[nom]
    j, binaire = _lire_glb(source)
    if _deja_allege(j):
        return nom, _triangles(j), _triangles(j), 0.0, "déjà allégé"

    avant = _triangles(j)
    binaire = _cuire_couleurs(j, binaire)
    _depouiller_materiaux(j)
    _elaguer_images(j)
    if mode != "aucun":
        # Les UV ne servent plus à rien une fois la couleur cuite, et tant
        # qu'ils sont là ils découpent le maillage en autant d'îlots que le
        # simplificateur refuse de recoudre.
        for maillage in j.get("meshes", []):
            for prim in maillage.get("primitives", []):
                prim.get("attributes", {}).pop("TEXCOORD_0", None)
    j.setdefault("asset", {}).setdefault("extras", {})["arena_rush_allege"] = True

    intermediaire = source.with_suffix(".depouille.glb")
    _ecrire_glb(intermediaire, j, binaire)

    cible = source if not verifier else source.with_suffix(".apercu.glb")
    args = [GLTFPACK, "-i", str(intermediaire), "-o", str(cible), "-noq"]
    if mode == "agressif":
        args += ["-si", f"{min(1.0, budget / max(avant, 1)):.4f}", "-sa"]
    elif mode == "doux":
        # Un ratio volontairement bas : en mode doux le simplificateur
        # s'arrête de lui-même dès qu'il ne peut plus réduire sans casser
        # une discontinuité. On lui demande donc tout ce qu'il peut donner.
        args += ["-si", "0.05"]
    subprocess.run(args, check=True, capture_output=True)
    intermediaire.unlink()

    j2, _ = _lire_glb(cible)
    return nom, avant, _triangles(j2), cible.stat().st_size / 1024.0, mode


def _planche() -> int:
    """Prépare les trois états de chaque décor pour la planche de contrôle.

    C'est l'instrument qui a décidé des modes : sans lui, le choix entre
    « agressif » et « doux » se serait fait au raisonnement, et le
    raisonnement se trompait — il annonçait la caisse comme le cas le plus
    facile (« c'est un cube »), alors que c'est l'un de ceux que la soudure
    détruit le plus complètement.

    Ensuite : godot --path arena-rush res://outils_dev/apercu_variantes.tscn
    """
    dest = RACINE / "arena-rush" / "outils_dev" / "variantes"
    dest.mkdir(parents=True, exist_ok=True)
    for nom, (mode, budget) in sorted(MODES.items()):
        source = MODELES / f"{nom}.glb"
        if not source.exists():
            continue
        shutil.copy(source, dest / f"{nom}__A.glb")
        j, binaire = _lire_glb(source)
        avant = _triangles(j)
        binaire = _cuire_couleurs(j, binaire)
        _depouiller_materiaux(j)
        _elaguer_images(j)
        _ecrire_glb(dest / f"{nom}__B.glb", j, binaire)
        for maillage in j.get("meshes", []):
            for prim in maillage.get("primitives", []):
                prim.get("attributes", {}).pop("TEXCOORD_0", None)
        tampon = dest / "_tampon.glb"
        _ecrire_glb(tampon, j, binaire)
        args = [GLTFPACK, "-i", str(tampon), "-o", str(dest / f"{nom}__C.glb"), "-noq"]
        if mode == "agressif":
            args += ["-si", f"{min(1.0, budget / max(avant, 1)):.4f}", "-sa"]
        else:
            args += ["-si", "0.05"]
        subprocess.run(args, check=True, capture_output=True)
        tampon.unlink()
        print(f"  {nom}")
    print("\n  godot --path arena-rush res://outils_dev/apercu_variantes.tscn")
    return 0


def main() -> int:
    if "--planche" in sys.argv:
        return _planche()
    verifier = "--verifier" in sys.argv
    if not Path(GLTFPACK).exists():
        print("gltfpack introuvable : npm install --no-save gltfpack", file=sys.stderr)
        return 2

    print(f"\n=== ALLÈGEMENT DES DÉCORS ({'aperçu' if verifier else 'en place'}) ===\n")
    print(f"  {'modèle':<26}{'mode':>10}{'avant':>8}{'après':>8}{'gain':>7}{'poids':>9}")
    total_av = total_ap = 0
    for nom in sorted(MODES):
        source = MODELES / f"{nom}.glb"
        if not source.exists():
            print(f"  {nom:<28}  absent du dépôt")
            continue
        n, av, ap, ko, note = _alleger(source, verifier)
        total_av += av
        total_ap += ap
        gain = 100.0 * (1.0 - ap / max(av, 1))
        print(f"  {n:<26}{note:>10}{av:>8}{ap:>8}{gain:>6.0f}%{ko:>8.0f} Ko")
    print("")
    gain = 100.0 * (1.0 - total_ap / max(total_av, 1))
    print(f"  TOTAL par exemplaire : {total_av} → {total_ap} triangles ({gain:.0f} % de moins)")
    print("")
    return 0


if __name__ == "__main__":
    sys.exit(main())
