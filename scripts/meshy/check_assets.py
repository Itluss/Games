# -*- coding: utf-8 -*-
"""Controle de la bibliotheque d'assets telechargee.

   Ce script ne parle PAS a Meshy. Il ne regarde que le disque, et c'est
   volontaire : son role est justement de verifier que la bibliotheque tient
   toute seule, sans dependre du stockage temporaire de Meshy.

   Il verifie, pour chaque asset annonce dans le manifest :
     - que le GLB existe et porte la signature glTF ;
     - que les textures declarees existent ;
     - le nombre de triangles et les dimensions, si trimesh est disponible ;
     - l'ecart entre les dimensions mesurees et les dimensions reelles
       attendues, ce qui donne le facteur de mise a l'echelle a appliquer.

   python scripts/meshy/check_assets.py
   python scripts/meshy/check_assets.py --detail
"""
import argparse
import json
import os
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
RACINE = os.path.dirname(os.path.dirname(ICI))
sys.path.insert(0, ICI)

import download_meshy_asset as dl   # noqa: E402

MANIFEST = os.path.join(RACINE, "assets", "port_poc", "metadata",
                        "assets_manifest.json")


def mesurer(chemin):
    """triangles et dimensions. trimesh est optionnel : son absence degrade
       le rapport, elle ne le fait pas echouer."""
    try:
        import trimesh
    except ImportError:
        return None
    try:
        s = trimesh.load(chemin, force="scene")
        geoms = list(s.geometry.values()) if hasattr(s, "geometry") else []
        tris = sum(len(g.faces) for g in geoms)
        b = s.bounds
        return {"triangles": int(tris), "materiaux": len(geoms),
                "dimensions": [round(float(v), 4) for v in (b[1] - b[0])]}
    except Exception as e:
        return {"erreur": str(e)[:120]}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--detail", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(MANIFEST):
        print("Aucun manifest : %s" % os.path.relpath(MANIFEST, RACINE))
        return 1
    with open(MANIFEST, encoding="utf-8") as f:
        m = json.load(f)
    assets = m.get("assets", {})
    if not assets:
        print("Manifest vide : aucun asset genere pour le moment.")
        return 0

    ok = manquants = incomplets = 0
    print("%-32s %-9s %8s %10s  %s"
          % ("identifiant", "statut", "tris", "Ko", "controle"))
    print("-" * 92)
    for aid in sorted(assets):
        e = assets[aid]
        glb = (e.get("fichiers") or {}).get("glb")
        if not glb:
            print("%-32s %-9s %8s %10s  %s"
                  % (aid, e.get("statut", "?"), "-", "-", "aucun GLB"))
            manquants += 1
            continue
        chemin = os.path.join(RACINE, glb["chemin"])
        if not os.path.exists(chemin):
            print("%-32s %-9s %8s %10s  %s"
                  % (aid, e.get("statut", "?"), "-", "-", "FICHIER ABSENT"))
            manquants += 1
            continue
        valide, detail = dl.valider_glb(chemin)
        mes = mesurer(chemin)
        tris = mes.get("triangles", "-") if mes and "triangles" in mes else "-"
        # textures declarees : existent-elles vraiment ?
        tex_ok = tex_tot = 0
        for t in e.get("textures") or []:
            tex_tot += 1
            if os.path.exists(os.path.join(RACINE, t["chemin"])):
                tex_ok += 1
        note = "ok" if valide else detail
        if tex_tot and tex_ok < tex_tot:
            note += " ; %d/%d textures manquantes" % (tex_tot - tex_ok, tex_tot)
        print("%-32s %-9s %8s %10.0f  %s"
              % (aid, e.get("statut", "?"), tris,
                 glb.get("octets", 0) / 1024.0, note))
        if valide and (not tex_tot or tex_ok == tex_tot):
            ok += 1
        else:
            incomplets += 1
        if a.detail and mes and "dimensions" in mes:
            att = e.get("dimensions_m") or {}
            d = mes["dimensions"]
            print("      mesure %.3f x %.3f x %.3f (unites du fichier)"
                  % tuple(d))
            if att:
                cible = max(att.get("longueur", 0), att.get("largeur", 0),
                            att.get("hauteur", 0))
                plus_grand = max(d) or 1.0
                print("      reel attendu %.2f x %.2f x %.2f m"
                      " -> facteur d'echelle a appliquer : %.3f"
                      % (att.get("longueur", 0), att.get("largeur", 0),
                         att.get("hauteur", 0), cible / plus_grand))
            print("      %d materiau(x), %d texture(s) sur disque"
                  % (mes.get("materiaux", 0), tex_ok))
    print("-" * 92)
    print("%d valides, %d incomplets, %d manquants sur %d annonces."
          % (ok, incomplets, manquants, len(assets)))
    return 0 if manquants == 0 and incomplets == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
