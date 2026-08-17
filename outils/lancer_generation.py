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
        # Sans `famille`, on reste sur le style personnage : les demandes
        # deja au depot produisent exactement le meme resultat qu'avant.
        famille=demande.get("famille", ""),
    )


if __name__ == "__main__":
    chemins = [c for c in sys.argv[1:] if c.strip()]
    if not chemins:
        print("Aucune demande à traiter.")
        sys.exit(0)
    # UN ÉCHEC N'ARRÊTE PAS LE LOT. Quinze demandes partent désormais d'un
    # seul coup ; laisser la troisième tuer les douze suivantes gâcherait un
    # run entier alors que les générations réussies, elles, sont DÉJÀ PAYÉES.
    # On isole donc chaque demande, et on ne signale l'échec qu'à la fin —
    # après que tout ce qui pouvait aboutir a abouti.
    produits = []
    echecs = []
    for c in chemins:
        try:
            produits.append(executer(c))
        except SystemExit as e:
            print("\n!! ÉCHEC sur %s : %s\n" % (c, e), flush=True)
            echecs.append((c, str(e)))
        except Exception as e:  # noqa: BLE001 — un imprévu ne doit pas non plus tout emporter
            print("\n!! ERREUR INATTENDUE sur %s : %r\n" % (c, e), flush=True)
            echecs.append((c, repr(e)))

    print()
    print("Assets produits (%d/%d) :" % (len(produits), len(chemins)))
    for p in produits:
        print("  •", p)
    if echecs:
        print()
        print("Demandes en échec (%d) :" % len(echecs))
        for c, msg in echecs:
            print("  ✗ %s — %s" % (c, msg.splitlines()[0] if msg else "?"))
        # Sortie non nulle : le workflow doit virer au rouge. Mais les
        # assets réussis sont déjà sur le disque, donc l'étape d'artefact
        # les récupérera quand même.
        sys.exit(1)
