# -*- coding: utf-8 -*-
"""Generation de la bibliotheque d'assets du POC port maritime.

   IDEMPOTENT. Relancer la commande ne regenere rien de ce qui est deja
   valide sur disque : c'est la seule facon de ne pas payer deux fois la
   meme piece. Un asset n'est considere comme acquis que si son entree
   existe dans le manifest AVEC un GLB present et valide -- pas simplement
   parce que Meshy a repondu SUCCEEDED.

   REPRISE. Si une execution est interrompue entre la generation et le
   telechargement, l'identifiant de tache est deja ecrit dans le manifest :
   la relance reprend au telechargement au lieu de relancer la generation.

   Exemples :
     python scripts/meshy/generate_port_assets.py --liste
     python scripts/meshy/generate_port_assets.py --verifier-cle
     python scripts/meshy/generate_port_assets.py --batch poc_test
     python scripts/meshy/generate_port_assets.py --asset port_forklift_01
     python scripts/meshy/generate_port_assets.py --batch poc_core --dry-run
"""
import argparse
import datetime
import json
import os
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.dirname(os.path.dirname(ICI))
sys.path.insert(0, ICI)

import catalogue                      # noqa: E402
import download_meshy_asset as dl     # noqa: E402
import meshy_api                      # noqa: E402

BASE_ASSETS = os.path.join(RACINE, "assets", "port_poc")
MANIFEST = os.path.join(BASE_ASSETS, "metadata", "assets_manifest.json")

# Budget de triangles demande a Meshy. On ne degrade pas pour mobile a ce
# stade : on veut d'abord juger la qualite. L'allegement viendra apres, sous
# forme de LOD produits dans Blender depuis ce master.
POLYCOUNT = 30000


def maintenant():
    return datetime.datetime.now().replace(microsecond=0).isoformat()


def charger_manifest():
    if os.path.exists(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as f:
            return json.load(f)
    return {"version": 1, "projet": "POC port maritime", "unite": "metre",
            "cree": maintenant(), "assets": {}}


def ecrire_manifest(m):
    m["modifie"] = maintenant()
    os.makedirs(os.path.dirname(MANIFEST), exist_ok=True)
    tmp = MANIFEST + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(m, f, ensure_ascii=False, indent=2)
    if os.path.exists(MANIFEST):
        os.remove(MANIFEST)
    os.rename(tmp, MANIFEST)


def deja_valide(entree):
    """Un asset est acquis si son GLB EXISTE reellement et porte la bonne
       signature. Le statut declare par Meshy ne suffit pas."""
    if not entree or entree.get("statut") != "telecharge":
        return False
    glb = (entree.get("fichiers") or {}).get("glb")
    if not glb:
        return False
    chemin = os.path.join(RACINE, glb["chemin"])
    if not os.path.exists(chemin) or os.path.getsize(chemin) == 0:
        return False
    ok, _ = dl.valider_glb(chemin)
    return ok


def dossier_de(asset):
    return os.path.join(BASE_ASSETS, "generated", asset["categorie"])


def generer_un(asset, manifest, journal=print, polycount=POLYCOUNT):
    aid = asset["id"]
    entree = manifest["assets"].get(aid, {})
    journal("[%s] %s" % (aid, asset["nom"]))

    # --- reprise : une tache d'affinage deja lancee n'est pas relancee
    id_texture = entree.get("meshy_id_texture")
    id_apercu = entree.get("meshy_id_apercu")

    if not id_apercu:
        journal("   apercu (geometrie)...")
        id_apercu = meshy_api.creer_apercu(asset["prompt"], polycount=polycount)
        entree.update({"id": aid, "nom": asset["nom"],
                       "categorie": asset["categorie"], "lot": asset["lot"],
                       "dimensions_m": asset["dimensions_m"],
                       "prompt": asset["prompt"],
                       "meshy_id_apercu": id_apercu,
                       "parametres": {"art_style": "realistic",
                                      "target_polycount": polycount,
                                      "topology": "triangle",
                                      "symmetry_mode": "auto",
                                      "enable_pbr": True},
                       "statut": "apercu_en_cours",
                       "genere_le": maintenant()})
        manifest["assets"][aid] = entree
        ecrire_manifest(manifest)
    t = meshy_api.attendre(id_apercu, journal=journal)
    if t.get("status") != "SUCCEEDED":
        entree["statut"] = "echec_apercu"
        entree["erreur"] = t.get("task_error") or t.get("status")
        ecrire_manifest(manifest)
        journal("   ECHEC apercu : %s" % entree["erreur"])
        return False

    if not id_texture:
        journal("   texturage PBR...")
        id_texture = meshy_api.creer_texture(id_apercu)
        entree["meshy_id_texture"] = id_texture
        entree["statut"] = "texture_en_cours"
        ecrire_manifest(manifest)
    t = meshy_api.attendre(id_texture, journal=journal)
    if t.get("status") != "SUCCEEDED":
        entree["statut"] = "echec_texture"
        entree["erreur"] = t.get("task_error") or t.get("status")
        ecrire_manifest(manifest)
        journal("   ECHEC texturage : %s" % entree["erreur"])
        return False

    # --- telechargement LOCAL immediat : les URL Meshy expirent
    journal("   telechargement...")
    dossier = dossier_de(asset)
    r = dl.telecharger_tache(t, dossier, aid, journal=journal)
    entree.update({
        "statut": "telecharge" if r["valide"] else "telecharge_incomplet",
        "fichiers": r["fichiers"],
        "formats": sorted(r["fichiers"].keys()),
        "textures": r["textures"],
        "apercu": r["apercu"],
        "octets_total": r["octets_total"],
        "controle_glb": r.get("controle_glb"),
        "anomalies": r["anomalies"],
        "triangles": t.get("polycount") or (t.get("model_statistics") or {}).get("triangle_count"),
        "telecharge_le": maintenant(),
    })
    manifest["assets"][aid] = entree
    ecrire_manifest(manifest)
    journal("   %s" % ("OK" if r["valide"] else "INCOMPLET : %s" % r["anomalies"]))
    return r["valide"]


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--asset", action="append", default=[],
                    help="identifiant precis, repetable")
    ap.add_argument("--batch", help="poc_test | poc_core | poc_extra | tout")
    ap.add_argument("--liste", action="store_true", help="affiche le catalogue")
    ap.add_argument("--verifier-cle", action="store_true",
                    help="appel de liste gratuit, ne consomme aucun credit")
    ap.add_argument("--dry-run", action="store_true",
                    help="montre ce qui serait genere, sans rien lancer")
    ap.add_argument("--force", action="store_true",
                    help="regenere meme si deja valide localement")
    ap.add_argument("--polycount", type=int, default=POLYCOUNT)
    a = ap.parse_args()

    cat = catalogue.construire()["assets"]
    index = {x["id"]: x for x in cat}

    if a.liste:
        for x in cat:
            d = x["dimensions_m"]
            print("%-32s %-11s %-10s %4.1f x %4.1f x %4.1f m"
                  % (x["id"], x["lot"], x["categorie"],
                     d["longueur"], d["largeur"], d["hauteur"]))
        print("\n%d assets." % len(cat))
        return 0

    if a.verifier_cle:
        try:
            meshy_api.verifier()
            print("Cle valide (appel de liste gratuit, aucun credit consomme).")
            return 0
        except meshy_api.ErreurMeshy as e:
            print("Cle REFUSEE : %s" % e)
            return 2

    if a.asset:
        choix = []
        for aid in a.asset:
            if aid not in index:
                print("identifiant inconnu : %s" % aid)
                return 2
            choix.append(index[aid])
    elif a.batch:
        if a.batch == "tout":
            choix = cat
        else:
            choix = [x for x in cat if x["lot"] == a.batch]
        if not choix:
            print("lot inconnu ou vide : %s" % a.batch)
            return 2
    else:
        ap.print_help()
        return 2

    manifest = charger_manifest()
    a_faire, deja = [], []
    for x in choix:
        if not a.force and deja_valide(manifest["assets"].get(x["id"])):
            deja.append(x)
        else:
            a_faire.append(x)

    print("Selection : %d asset(s). Deja valides localement : %d. A generer : %d."
          % (len(choix), len(deja), len(a_faire)))
    for x in deja:
        print("   deja la  %s" % x["id"])
    for x in a_faire:
        print("   a faire  %s" % x["id"])
    if a.dry_run:
        print("\n--dry-run : rien n'a ete lance.")
        return 0
    if not a_faire:
        print("\nRien a faire.")
        return 0

    # Preflight : une cle morte decouverte APRES une generation coute la
    # generation. L'appel de liste est gratuit.
    try:
        meshy_api.verifier()
    except meshy_api.ErreurMeshy as e:
        print("\nArret avant toute generation — cle refusee par Meshy : %s" % e)
        return 2

    ok = 0
    for x in a_faire:
        try:
            if generer_un(x, manifest, polycount=a.polycount):
                ok += 1
        except meshy_api.ErreurMeshy as e:
            print("   ERREUR API : %s" % e)
            manifest["assets"].setdefault(x["id"], {"id": x["id"]})
            manifest["assets"][x["id"]]["statut"] = "echec_api"
            manifest["assets"][x["id"]]["erreur"] = str(e)
            ecrire_manifest(manifest)
        except Exception as e:
            print("   ERREUR : %s" % e)
    print("\n%d/%d asset(s) telecharge(s) et valide(s)." % (ok, len(a_faire)))
    print("Manifest : %s" % os.path.relpath(MANIFEST, RACINE))
    return 0 if ok == len(a_faire) else 1


if __name__ == "__main__":
    sys.exit(main())
