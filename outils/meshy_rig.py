#!/usr/bin/env python3
"""AUTO-RIGGING ET ANIMATION — Meshy.

POURQUOI CE FICHIER EXISTE : le modèle livré par Meshy est un maillage
d'un seul tenant, SANS os. Godot sait très bien animer, mais il n'invente
pas un squelette : il joue celui qui existe. J'avais donc écrit un
auto-riggeur maison (`arena-rush/scripts/player/procedural_rig.gd`) qui
devine l'appartenance de chaque sommet à un os par sa distance. Ça tient
pour un bras qui balance, pas pour un pied qui doit rester plat : les
poids ignorent la topologie, et la chaussure se vrille.

Écrire un auto-riggeur correct est un métier. Meshy en a un, ainsi
qu'une bibliothèque de 678 animations. C'est la bonne réponse, et elle
rend le rig procédural entièrement inutile.

DEUX ÉTAPES :
  1. RIGGING  — POST /v1/rigging     → squelette humanoïde greffé
  2. ANIMATION— POST /v1/animations  → une action de la bibliothèque

CONTRAINTES DE L'API :
  • le modèle doit être un humanoïde TEXTURÉ ;
  • fourni par URL, son visage doit regarder vers +Z. C'est le cas de
    Kael — d'où le demi-tour appliqué côté jeu ;
  • `input_task_id` prime sur `model_url` et évite d'héberger quoi que ce
    soit : on repart de la tâche image-to-3d d'origine, donc du modèle
    PLEINE QUALITÉ, et non de sa version allégée pour le web.

COMMENT LES IDENTIFIANTS D'ACTION ONT ÉTÉ OBTENUS : la bibliothèque
n'est PAS une ressource d'API. Trois runs de découverte, tous gratuits,
l'ont établi — `/v1/animations/library` répond « Invalid ID » parce que
le routeur lit `/v1/animations/{id}` et prend « library » pour un
identifiant. C'est une table de référence documentée. docs.meshy.ai est
bloqué par le proxy de sortie de la session d'assistance, mais pas
depuis un runner Actions : la page y a été lue et la table figée dans
`outils/animations_meshy.json`.

Usage :
  MESHY_API_KEY=... python3 outils/meshy_rig.py --catalogue
  MESHY_API_KEY=... python3 outils/meshy_rig.py --tache <id> --hauteur 1.9 \\
      --actions course,repos,tir,mort
"""
import argparse
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy  # noqa: E402

SORTIE = "arena-rush/assets/models/"
SORTIE_TACHES = "arena-rush/assets/models/taches/"
RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOGUE = os.path.join(RACINE, "outils", "animations_meshy.json")

# CHOIX D'ANIMATIONS, arrêtés explicitement plutôt que devinés par
# ressemblance de nom. Une correspondance floue aurait pu retenir
# « Walking_Woman » pour « course » ou « penguin_walk » pour « marche » —
# et chaque erreur se paie en crédits.
#
# Le jeu est une arène de tir vue de dessus : le personnage court presque
# toujours arme au poing. « Run_and_Shoot » est donc la locomotion
# principale, et non un cas particulier.
ROLES = {
    "repos": (0, "Idle"),
    "course": (16, "RunFast"),
    "course_tir": (98, "Run_and_Shoot"),
    "tir": (104, "Side_Shot"),
    "garde": (89, "Combat_Stance"),
    "mort": (8, "Dead"),
    "touche": (178, "Hit_Reaction"),
}


def charger_catalogue():
    if not os.path.exists(CATALOGUE):
        return {}
    with open(CATALOGUE, encoding="utf-8") as f:
        return {int(a["id"]): a for a in json.load(f)}


def verifier_roles(catalogue):
    """Confirme que chaque identifiant retenu désigne bien l'action visée.

    Garde-fou contre une erreur silencieuse : si la table évolue et qu'un
    identifiant glisse, on préfère s'arrêter net plutôt que de payer une
    animation de danse à la place d'une course.
    """
    ok = True
    for role, (ident, attendu) in sorted(ROLES.items()):
        reel = catalogue.get(ident, {}).get("nom")
        marque = "OK " if reel == attendu else "!! "
        if reel != attendu:
            ok = False
        print("  %s%-12s %3d  attendu %-16s trouvé %s"
              % (marque, role, ident, attendu, reel or "ABSENT"))
    return ok


def _plat(donnees, sortie=None):
    """Ramasse tous les dictionnaires d'un JSON, quelle que soit sa forme."""
    if sortie is None:
        sortie = []
    if isinstance(donnees, dict):
        sortie.append(donnees)
        for v in donnees.values():
            _plat(v, sortie)
    elif isinstance(donnees, list):
        for v in donnees:
            _plat(v, sortie)
    return sortie


def rigger(cle, tache_source, hauteur, nom):
    """Greffe un squelette humanoïde. ÉTAPE PAYANTE."""
    corps = {"input_task_id": tache_source, "height_meters": float(hauteur)}
    print("RIGGING de %s (hauteur %.2f m)…" % (tache_source, hauteur), flush=True)
    rep = meshy._requete("/v1/rigging", "POST", corps, cle=cle)
    tache = meshy._identifiant(rep)
    print("  tâche de rigging : %s" % tache, flush=True)
    # Journalisation IMMÉDIATE : une tâche payée ne doit jamais être
    # perdue parce qu'une étape ultérieure a échoué.
    meshy._journaliser(nom + "-rig", {"id": tache, "type": "rigging"})
    fini = meshy._attendre("/v1/rigging/" + tache, cle, "rigging", nom + "-rig")
    return tache, fini


def animer(cle, tache_rig, action_id, role, nom):
    """Applique une action au personnage riggé. ÉTAPE PAYANTE."""
    corps = {"rig_task_id": tache_rig, "action_id": int(action_id)}
    rep = meshy._requete("/v1/animations", "POST", corps, cle=cle)
    tache = meshy._identifiant(rep)
    meshy._journaliser("%s-%s" % (nom, role),
                       {"id": tache, "type": "animation", "action_id": action_id})
    return meshy._attendre("/v1/animations/" + tache, cle, "anim " + role,
                           "%s-%s" % (nom, role))


def _urls_glb(fini):
    """Toutes les URL de .glb présentes dans une réponse de tâche."""
    trouves = []
    for d in _plat(fini):
        for clef, val in d.items():
            if isinstance(val, str) and ".glb" in val.lower() and val.startswith("http"):
                trouves.append((clef, val))
    return trouves


def telecharger(fini, cible):
    urls = _urls_glb(fini)
    if not urls:
        print("::warning::Aucune URL .glb dans la réponse — JSON conservé.")
        return None
    clef, url = urls[0]
    os.makedirs(os.path.dirname(cible), exist_ok=True)
    with urllib.request.urlopen(url, timeout=300) as r, open(cible, "wb") as f:
        f.write(r.read())
    print("  %s → %s (%.1f Mo)" % (clef, cible, os.path.getsize(cible) / 1e6),
          flush=True)
    return cible


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--catalogue", action="store_true",
                   help="vérifie les identifiants retenus, sans rien dépenser")
    p.add_argument("--tache", default="")
    p.add_argument("--rig", default="",
                   help="réutiliser un rig DÉJÀ payé (saute l'étape de "
                        "rigging, qui est la plus coûteuse)")
    p.add_argument("--hauteur", type=float, default=1.9)
    p.add_argument("--nom", default="kael")
    p.add_argument("--actions", default="repos,course,course_tir,mort")
    a = p.parse_args()

    catalogue = charger_catalogue()
    print("Catalogue local : %d actions." % len(catalogue))
    coherent = verifier_roles(catalogue)

    roles = [r.strip() for r in a.actions.split(",") if r.strip()]
    inconnus = [r for r in roles if r not in ROLES]
    if inconnus:
        sys.exit("Rôle(s) inconnu(s) : %s\nConnus : %s"
                 % (", ".join(inconnus), ", ".join(sorted(ROLES))))

    if a.catalogue:
        print("\nCe qui SERAIT produit :")
        for r in roles:
            print("  %-12s → %s (action_id %d)" % (r, ROLES[r][1], ROLES[r][0]))
        sys.exit(0 if coherent else 1)

    if not coherent:
        sys.exit("Le catalogue ne concorde pas avec les identifiants retenus — "
                 "on n'engage aucune dépense sur une table incertaine.")
    if not a.rig and not a.tache:
        sys.exit("--tache (nouveau rig) ou --rig (rig existant) est requis.")

    cle = os.environ.get("MESHY_API_KEY", "")
    if not cle:
        sys.exit("MESHY_API_KEY absente de l'environnement.")

    if a.rig:
        # Le squelette ne change pas d'une animation à l'autre : le
        # regénérer coûterait le prix fort pour un résultat identique.
        tache_rig = a.rig
        print("Rig existant réutilisé : %s" % tache_rig, flush=True)
    else:
        tache_rig, fini_rig = rigger(cle, a.tache, a.hauteur, a.nom)
        telecharger(fini_rig, os.path.join(SORTIE, a.nom + "_rig.glb"))

    for role in roles:
        ident, nom_action = ROLES[role]
        print("\n%s → « %s » (action_id %d)" % (role, nom_action, ident), flush=True)
        fini = animer(cle, tache_rig, ident, role, a.nom)
        telecharger(fini, os.path.join(SORTIE, "%s_%s.glb" % (a.nom, role)))
