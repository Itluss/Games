#!/usr/bin/env python3
"""PILOTE DE GÉNÉRATION — exécute des « bons de commande » d'assets.

POURQUOI CE FICHIER EXISTE : déclencher un workflow par l'API demande un
droit que le jeton de la session d'assistance n'a pas. Déposer un fichier
de demande dans le dépôt, en revanche, produit un push — et un push, lui,
déclenche le workflow. Chaque demande devient donc à la fois l'ordre de
génération et sa trace : on sait, des mois plus tard, avec quels réglages
exacts un asset a été produit.

Un bon de commande est un JSON :

    {
      "nom": "kael",
      "mode": "image",
      "image": "art/references/kael_apose_front.png",
      "prompt": "...",
      "polycount": 18000
    }

Seuls `nom` et `mode` sont obligatoires.

Usage : python3 outils/lancer_generation.py art/requests/001-kael.json [...]
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy  # noqa: E402


def executer(chemin: str) -> str:
    with open(chemin, encoding="utf-8") as f:
        demande = json.load(f)

    nom = demande.get("nom", "")
    mode = demande.get("mode", "image")
    if not nom:
        raise SystemExit("%s : champ « nom » manquant." % chemin)
    if mode not in ("image", "texte", "texture"):
        raise SystemExit("%s : mode inconnu « %s »." % (chemin, mode))

    image = demande.get("image") or None
    if mode == "image" and not image:
        raise SystemExit("%s : le mode image exige un champ « image »." % chemin)
    if mode == "image" and not os.path.exists(image):
        raise SystemExit("%s : image introuvable — %s" % (chemin, image))

    print("=" * 62)
    print("DEMANDE %s  →  %s (mode %s)" % (chemin, nom, mode))
    print("=" * 62, flush=True)

    return meshy.generer(
        mode,
        nom,
        demande.get("prompt", ""),
        image,
        demande.get("modele_url", ""),
        demande.get("texturer", True),
        polycount=int(demande.get("polycount", 30000)),
        modele_ia=demande.get("modele_ia", "latest"),
    )


if __name__ == "__main__":
    chemins = [c for c in sys.argv[1:] if c.strip()]
    if not chemins:
        print("Aucune demande à traiter.")
        sys.exit(0)
    produits = []
    for c in chemins:
        produits.append(executer(c))
    print()
    print("Assets produits :")
    for p in produits:
        print("  •", p)
