#!/usr/bin/env python3
"""AUTO-RIGGING ET ANIMATION — Meshy.

POURQUOI CE FICHIER EXISTE : le modèle livré par Meshy est un maillage
d'un seul tenant, SANS os. Godot sait très bien animer, mais il n'invente
pas un squelette : il joue celui qui existe. J'avais donc écrit un
auto-riggeur maison (`arena-rush/scripts/player/procedural_rig.gd`) qui
devine l'appartenance de chaque sommet à un os par sa distance. Ça marche
pour un bras qui balance, ça ne tient pas sur un pied qui doit rester
plat : les poids ignorent la topologie, et la chaussure se vrille.

Écrire un auto-riggeur correct est un métier. Meshy en a un, ainsi
qu'une bibliothèque d'animations. C'est la bonne réponse, et elle
supprime purement et simplement le rig procédural.

DEUX ÉTAPES :
  1. RIGGING  — POST /v1/rigging      → squelette humanoïde greffé
  2. ANIMATION— POST /v1/animations   → une action de la bibliothèque

CONTRAINTES DE L'API (relevées dans la doc) :
  • le modèle doit être un humanoïde TEXTURÉ ;
  • s'il est fourni par URL, son visage doit regarder vers +Z. C'est déjà
    le cas de Kael — d'où le demi-tour appliqué côté jeu.
  • `input_task_id` prime sur `model_url`, et évite d'héberger quoi que
    ce soit : on repart de la tâche image-to-3d d'origine, donc du modèle
    PLEINE QUALITÉ, pas de sa version allégée pour le web.

LES IDENTIFIANTS D'ACTION NE SONT PAS CODÉS EN DUR. La documentation
n'est pas accessible depuis l'environnement d'assistance, et deviner un
`action_id` coûterait un run payant pour rien. Le script INTERROGE donc
la bibliothèque et choisit les actions par correspondance de nom. C'est
aussi plus robuste : le catalogue évoluera sans casser ce fichier.

Usage :
  MESHY_API_KEY=... python3 outils/meshy_rig.py --catalogue
  MESHY_API_KEY=... python3 outils/meshy_rig.py --tache <id> --hauteur 1.9 \\
      --actions course,repos
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import meshy  # noqa: E402

SORTIE = "arena-rush/assets/models/"
SORTIE_TACHES = "arena-rush/assets/models/taches/"

# Chemins candidats pour la bibliothèque d'animations. L'API a déjà changé
# de surface par le passé ; on essaie les formes plausibles plutôt que de
# parier sur une seule et d'échouer sans rien apprendre.
CHEMINS_CATALOGUE = [
    "/v1/animation-library",
    "/v1/animations/library",
    "/v1/animation-library?page_num=1&page_size=200",
    "/v1/animations?page_num=1&page_size=200",
    "/v1/actions",
]

# Ce que l'on cherche dans le catalogue, par ordre de préférence. Le
# premier nom qui correspond gagne. Les termes sont en anglais : c'est la
# langue du catalogue.
SYNONYMES = {
    "course": ["running", "run cycle", "run forward", "jog", "run"],
    "repos": ["idle", "breathing idle", "stand", "standing"],
    "marche": ["walking", "walk forward", "walk cycle", "walk"],
    "tir": ["shooting", "aim", "firing", "shoot"],
    "mort": ["death", "dying", "falling back", "die"],
}


def _plat(donnees, sortie=None):
    """Ramasse tous les dictionnaires d'un JSON, quelle que soit sa forme.

    On ne sait pas si le catalogue arrive comme un tableau, un objet avec
    une clé `result`, ou une pagination imbriquée. Plutôt que de parier,
    on aplatit et on cherche les entrées qui ressemblent à une action.
    """
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


def _actions(donnees):
    """Entrées du catalogue : un identifiant et un nom lisible."""
    vues = {}
    for d in _plat(donnees):
        ident = d.get("action_id") or d.get("id")
        nom = d.get("name") or d.get("action_name") or d.get("title")
        if not ident or not nom or not isinstance(nom, str):
            continue
        if not isinstance(ident, (str, int)):
            continue
        vues[str(ident)] = nom
    return vues


def catalogue(cle):
    """Récupère la bibliothèque d'animations. Appel de LISTE : gratuit."""
    for chemin in CHEMINS_CATALOGUE:
        try:
            rep = meshy._requete(chemin, cle=cle)
        except SystemExit as e:
            print("  %-42s → %s" % (chemin, str(e).splitlines()[0][:70]))
            continue
        actes = _actions(rep)
        if actes:
            print("Catalogue trouvé sur %s : %d action(s)." % (chemin, len(actes)))
            return actes, rep
        print("  %-42s → 200 mais aucune action reconnue." % chemin)
    return {}, None


def choisir(actes, role):
    """Meilleure action pour un rôle, par correspondance de nom."""
    for terme in SYNONYMES.get(role, [role]):
        for ident, nom in actes.items():
            if nom.strip().lower() == terme:
                return ident, nom
    for terme in SYNONYMES.get(role, [role]):
        for ident, nom in actes.items():
            if terme in nom.strip().lower():
                return ident, nom
    return None, None


def rigger(cle, tache_source, hauteur, nom):
    """Greffe un squelette humanoïde. ÉTAPE PAYANTE."""
    corps = {"input_task_id": tache_source, "height_meters": float(hauteur)}
    print("RIGGING de %s (hauteur %.2f m)…" % (tache_source, hauteur), flush=True)
    rep = meshy._requete("/v1/rigging", "POST", corps, cle=cle)
    tache = meshy._identifiant(rep)
    print("  tâche de rigging : %s" % tache, flush=True)
    # Journalisation IMMÉDIATE : une tâche payée ne doit jamais être perdue
    # parce qu'une étape ultérieure a échoué.
    meshy._journaliser(nom + "-rig", {"id": tache, "type": "rigging"})
    fini = meshy._attendre("/v1/rigging/" + tache, cle, "rigging", nom + "-rig")
    return tache, fini


def animer(cle, tache_rig, action_id, nom):
    """Applique une action au personnage riggé. ÉTAPE PAYANTE."""
    corps = {"rig_task_id": tache_rig, "action_id": action_id}
    print("ANIMATION %s…" % action_id, flush=True)
    rep = meshy._requete("/v1/animations", "POST", corps, cle=cle)
    tache = meshy._identifiant(rep)
    meshy._journaliser(nom + "-anim", {"id": tache, "type": "animation",
                                       "action_id": action_id})
    return meshy._attendre("/v1/animations/" + tache, cle, "animation", nom + "-anim")


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
    import urllib.request
    with urllib.request.urlopen(url, timeout=300) as r, open(cible, "wb") as f:
        f.write(r.read())
    print("  %s → %s (%.1f Mo)" % (clef, cible, os.path.getsize(cible) / 1e6))
    return cible


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--catalogue", action="store_true",
                   help="liste la bibliothèque d'animations (gratuit)")
    p.add_argument("--tache", default="", help="task_id image-to-3d source")
    p.add_argument("--hauteur", type=float, default=1.9)
    p.add_argument("--nom", default="kael")
    p.add_argument("--actions", default="course,repos",
                   help="rôles à produire, séparés par des virgules")
    a = p.parse_args()

    cle = os.environ.get("MESHY_API_KEY", "")
    if not cle:
        sys.exit("MESHY_API_KEY absente de l'environnement.")

    actes, brut = catalogue(cle)
    if brut is not None:
        os.makedirs(SORTIE_TACHES, exist_ok=True)
        with open(os.path.join(SORTIE_TACHES, "catalogue-animations.json"),
                  "w", encoding="utf-8") as f:
            json.dump(brut, f, indent=2, ensure_ascii=False)
    if actes:
        print("\n--- BIBLIOTHÈQUE ---")
        for ident, nom in sorted(actes.items(), key=lambda kv: kv[1]):
            print("  %-40s %s" % (nom, ident))
        print("--- %d actions ---\n" % len(actes))

    roles = [r.strip() for r in a.actions.split(",") if r.strip()]
    if a.catalogue:
        print("Correspondances qui SERAIENT retenues :")
        for r in roles:
            ident, nom = choisir(actes, r)
            print("  %-10s → %s (%s)" % (r, nom or "AUCUNE", ident or "-"))
        sys.exit(0)

    if not a.tache:
        sys.exit("--tache est requis pour rigger.")
    if not actes:
        sys.exit("Catalogue introuvable : on n'engage aucune dépense à l'aveugle.")

    retenues = []
    for r in roles:
        ident, nom = choisir(actes, r)
        if ident is None:
            print("::warning::Aucune action pour le rôle « %s »." % r)
            continue
        retenues.append((r, ident, nom))
    if not retenues:
        sys.exit("Aucune action retenue — rien à animer.")

    tache_rig, fini_rig = rigger(cle, a.tache, a.hauteur, a.nom)
    telecharger(fini_rig, os.path.join(SORTIE, a.nom + "_rig.glb"))

    for role, ident, nom in retenues:
        print("\n%s → « %s »" % (role, nom), flush=True)
        fini = animer(cle, tache_rig, ident, a.nom)
        telecharger(fini, os.path.join(SORTIE, "%s_%s.glb" % (a.nom, role)))
