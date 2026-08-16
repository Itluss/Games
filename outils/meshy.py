#!/usr/bin/env python3
"""FOURNISSEUR D'ASSETS 3D — Meshy.

Descendant direct de `outils/artkit/meshy.py` d'Illuminia, avec trois
differences qui comptent pour un projet neuf :

  1. MODE TEXTURE (`--mode texture`) : reTexture un .glb EXISTANT sans
     regenerer sa geometrie. C'est le mode « je veux des textures »,
     absent de la version Illuminia.
  2. DIRECTION ARTISTIQUE EXTERNALISEE : le style ne vit plus en dur
     dans le code (Illuminia avait son calcaire creme et son toit bleu
     roi cables ici meme). Il vient de `outils/style.json`, donc chaque
     projet a le sien sans toucher au code.
  3. PREFLIGHT + JOURNALISATION : on verifie la cle par un appel GRATUIT
     avant de depenser, et toute tache est ecrite sur disque des qu'elle
     a un identifiant — une generation payee ne peut plus disparaitre
     parce qu'une etape ulterieure a echoue.

La cle d'API n'est JAMAIS ecrite dans le depot : elle vient de la
variable d'environnement MESHY_API_KEY, alimentee par le secret GitHub
au moment de l'execution du workflow.

Usage :
  MESHY_API_KEY=... python3 outils/meshy.py --verifier
  MESHY_API_KEY=... python3 outils/meshy.py --mode image  --nom héros --image ref.png
  MESHY_API_KEY=... python3 outils/meshy.py --mode texte  --nom arbre --prompt "..."
  MESHY_API_KEY=... python3 outils/meshy.py --mode texture --nom héros \\
      --modele-url https://... --prompt "écorce mousse humide"
"""
import argparse
import base64
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.request

API = "https://api.meshy.ai/openapi"

# Repertoires de sortie. Le .glb et le JSON de tache vivent cote a cote :
# le JSON contient les URL signees de TOUTES les cartes produites
# (albedo, normale, rugosite, metallique), pas seulement le modele.
SORTIE_MODELES = "arena-rush/assets/models/"
SORTIE_TACHES = "arena-rush/assets/models/taches/"

# L'API plafonne les descriptions ; le style doit tenir dans le budget
# sans devorer le sujet.
LIMITE_PROMPT = 800

RACINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FICHIER_STYLE = os.path.join(RACINE, "outils", "style.json")


def charger_style():
    """Direction artistique du projet.

    Volontairement un fichier de donnees et non des constantes : changer
    l'identite visuelle du jeu ne doit jamais demander de relire du code.
    """
    if not os.path.exists(FICHIER_STYLE):
        raise SystemExit(
            "outils/style.json est absent — c'est lui qui porte la direction\n"
            "artistique du projet. Cree-le (voir BOOTSTRAP.md) avant de generer."
        )
    with open(FICHIER_STYLE, encoding="utf-8") as f:
        style = json.load(f)
    for champ in ("style_forme", "style_texture", "negatif"):
        if champ not in style:
            raise SystemExit("outils/style.json : champ « %s » manquant." % champ)
    return style


def _decrire(sujet, suffixe):
    """Sujet + style, borne a la limite de l'API.

    Le style est PRESERVE et c'est le sujet qui est tronque : un asset
    hors-style est inutilisable, un asset moins detaille reste bon.
    """
    marge = LIMITE_PROMPT - len(suffixe) - 2
    return sujet.strip()[:marge].strip().rstrip(",") + ", " + suffixe


def _requete(chemin, methode="GET", corps=None, cle=""):
    url = API + chemin
    donnees = json.dumps(corps).encode() if corps is not None else None
    req = urllib.request.Request(url, data=donnees, method=methode)
    req.add_header("Authorization", "Bearer " + cle)
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        detail = e.read().decode()[:500]
        if e.code == 401:
            raise SystemExit("ECHEC AUTH (401) : la cle MESHY_API_KEY est "
                             "absente ou invalide.\n" + detail)
        if e.code in (402, 429):
            raise SystemExit("ECHEC CREDITS/QUOTA (%d) : %s" % (e.code, detail))
        if e.code == 404:
            raise SystemExit(
                "ECHEC 404 sur %s — l'endpoint n'existe pas sous cette forme.\n"
                "L'API Meshy a deja change de surface par le passe : verifie\n"
                "https://docs.meshy.ai et corrige le chemin dans ce fichier.\n%s"
                % (chemin, detail))
        raise SystemExit("ECHEC API Meshy (%d) sur %s :\n%s" % (e.code, chemin, detail))


def _identifiant(reponse):
    """Meshy a renvoye tantot {"result": "<id>"}, tantot {"id": "<id>"}."""
    resultat = reponse.get("result")
    if isinstance(resultat, str):
        return resultat
    if isinstance(resultat, dict) and resultat.get("id"):
        return resultat["id"]
    if reponse.get("id"):
        return reponse["id"]
    raise SystemExit("Aucun identifiant de tache dans la reponse :\n"
                     + json.dumps(reponse, indent=2)[:800])


def _journaliser(nom, tache):
    """Ecrit la tache sur disque. Appele des qu'un identifiant existe, PUIS
    a chaque etat terminal.

    C'est l'assurance anti-perte : les runs 3 et 4 d'Illuminia ont produit
    un modele facture puis l'ont perdu parce que l'etape suivante a
    echoue. Tant que ce JSON existe, les URL signees permettent de
    recuperer le resultat sans repayer (elles expirent — voir expires_at).
    """
    os.makedirs(SORTIE_TACHES, exist_ok=True)
    chemin = os.path.join(SORTIE_TACHES, nom + "-task.json")
    with open(chemin, "w", encoding="utf-8") as f:
        json.dump(tache, f, indent=2, ensure_ascii=False)
    return chemin


def _attendre(chemin_tache, cle, libelle, nom, max_s=1800):
    """Sonde la tache jusqu'a SUCCEEDED en journalisant la progression."""
    debut = time.time()
    dernier = -1
    while time.time() - debut < max_s:
        t = _requete(chemin_tache, cle=cle)
        statut = t.get("status", "?")
        avance = int(t.get("progress", 0))
        if avance != dernier:
            print("  %-10s %3d%%  (%ds)" % (libelle, avance, time.time() - debut),
                  flush=True)
            dernier = avance
        if statut == "SUCCEEDED":
            print("  journal → %s" % _journaliser(nom, t), flush=True)
            return t
        if statut in ("FAILED", "CANCELED", "EXPIRED"):
            _journaliser(nom, t)
            raise SystemExit("Tache %s : %s — %s"
                             % (libelle, statut, t.get("task_error", {})))
        time.sleep(10)
    raise SystemExit("Delai depasse sur %s (%d s)" % (libelle, max_s))


def _data_uri(chemin):
    if not os.path.exists(chemin):
        raise SystemExit("Image de reference introuvable : %s" % chemin)
    type_mime = mimetypes.guess_type(chemin)[0] or "image/png"
    with open(chemin, "rb") as f:
        return "data:%s;base64,%s" % (type_mime, base64.b64encode(f.read()).decode())


def verifier(cle):
    """Appel de LISTE — gratuit. Valide la cle sans consommer de credit.

    A lancer systematiquement avant une serie de generations : une cle
    expiree decouverte apres coup coute un run entier.
    """
    # Controle AVANT tout appel reseau : sans cette garde, une cle absente
    # produisait une trace Python illisible au lieu de dire ce qui manque.
    if not cle:
        raise SystemExit(
            "MESHY_API_KEY absente de l'environnement.\n"
            "En CI : Settings -> Secrets and variables -> Actions ->\n"
            "        New repository secret, nomme MESHY_API_KEY.\n"
            "En local : definis-la dans ton shell avant de lancer ce script.")
    rep = _requete("/v1/image-to-3d?page_num=1&page_size=1", cle=cle)
    # L'endpoint de liste renvoie un TABLEAU JSON directement, quand les
    # endpoints de creation renvoient un objet. Supposer une seule des deux
    # formes faisait echouer le preflight sur une cle pourtant valide.
    if isinstance(rep, list):
        n = len(rep)
    elif isinstance(rep, dict):
        resultat = rep.get("result")
        n = len(resultat) if isinstance(resultat, list) else "?"
    else:
        n = "?"
    print("Cle valide (HTTP 200, %s tache(s) listee(s))." % n, flush=True)
    return True


def _telecharger(fini, nom):
    """Recupere le .glb et toutes les cartes de texture disponibles."""
    lien = (fini.get("model_urls") or {}).get("glb")
    if not lien:
        raise SystemExit("Aucun .glb dans la reponse :\n"
                         + json.dumps(fini, indent=2)[:800])
    os.makedirs(SORTIE_MODELES, exist_ok=True)
    chemin = os.path.join(SORTIE_MODELES, nom + ".glb")
    with urllib.request.urlopen(lien, timeout=600) as r, open(chemin, "wb") as f:
        f.write(r.read())
    print("→ %s (%d Ko)" % (chemin, os.path.getsize(chemin) // 1024), flush=True)

    # Les cartes PBR arrivent separement du .glb : sans elles, impossible
    # de retoucher une matiere sans relancer une generation payante.
    dossier = os.path.join(SORTIE_MODELES, nom + "-textures")
    for i, jeu in enumerate(fini.get("texture_urls") or []):
        for role, url in (jeu or {}).items():
            if not url:
                continue
            os.makedirs(dossier, exist_ok=True)
            dest = os.path.join(dossier, "%s_%d_%s.png" % (nom, i, role))
            try:
                with urllib.request.urlopen(url, timeout=300) as r, open(dest, "wb") as f:
                    f.write(r.read())
                print("  carte → %s" % dest, flush=True)
            except urllib.error.URLError as e:
                print("  carte %s NON recuperee (%s) — l'URL signee du JSON "
                      "de tache reste utilisable." % (role, e), flush=True)
    return chemin


def generer(mode, nom, prompt="", image=None, modele_url="", texturer=True,
            cle=None, polycount=30000, modele_ia="latest"):
    """Produit un .glb (et ses cartes) et retourne son chemin."""
    cle = cle or os.environ.get("MESHY_API_KEY", "")
    if not cle:
        raise SystemExit(
            "MESHY_API_KEY absente de l'environnement.\n"
            "En local : definis-la dans ton shell. En CI : ajoute-la dans\n"
            "Settings → Secrets and variables → Actions du depot.")

    style = charger_style()
    verifier(cle)  # gratuit, et evite de decouvrir une cle morte trop tard

    invite_texture = _decrire(prompt or style.get("sujet_defaut", ""),
                              style["style_texture"])

    if mode == "texture":
        # RETEXTURE d'un modele existant : la geometrie est conservee,
        # seule la matiere est regeneree. C'est le mode le moins cher
        # pour iterer sur l'apparence sans repayer la forme.
        if not modele_url:
            raise SystemExit("--mode texture exige --modele-url (URL publique "
                             "du .glb a retexturer).")
        print("TEXT-TO-TEXTURE sur %s" % modele_url, flush=True)
        rep = _requete("/v1/text-to-texture", "POST", {
            "model_url": modele_url,
            "object_prompt": (prompt or style.get("sujet_defaut", ""))[:LIMITE_PROMPT],
            "style_prompt": style["style_texture"][:LIMITE_PROMPT],
            "negative_prompt": style["negatif"],
            "enable_original_uv": True,
            "enable_pbr": True,
        }, cle)
        tache = _identifiant(rep)
        _journaliser(nom, {"id": tache, "type": "text-to-texture",
                           "status": "SUBMITTED"})
        fini = _attendre("/v1/text-to-texture/" + tache, cle, "texture", nom)

    elif mode == "image":
        # IMAGE-TO-3D des qu'une reference visuelle existe : c'est LE mode
        # fidele a la direction artistique. Le texte produit des formes
        # approximatives.
        print("IMAGE-TO-3D depuis %s (modele %s, PBR, %d tris)"
              % (image, modele_ia, polycount), flush=True)
        rep = _requete("/v1/image-to-3d", "POST", {
            "image_url": _data_uri(image),
            "ai_model": modele_ia,
            "enable_pbr": True,
            "should_remesh": True,
            "should_texture": texturer,
            "symmetry_mode": "auto",
            "topology": "triangle",
            "target_polycount": polycount,
            "texture_prompt": invite_texture,
        }, cle)
        tache = _identifiant(rep)
        _journaliser(nom, {"id": tache, "type": "image-to-3d",
                           "status": "SUBMITTED"})
        fini = _attendre("/v1/image-to-3d/" + tache, cle, "image-3D", nom)

    else:  # texte
        description = _decrire(prompt, style["style_forme"])
        print("TEXT-TO-3D (apercu) — %d caracteres, modele %s"
              % (len(description), modele_ia), flush=True)
        rep = _requete("/v2/text-to-3d", "POST", {
            "mode": "preview",
            "prompt": description,
            "ai_model": modele_ia,
            "art_style": style.get("art_style", "realistic"),
            "should_remesh": True,
            "symmetry_mode": "auto",
            "topology": "triangle",
            "target_polycount": polycount,
        }, cle)
        tache = _identifiant(rep)
        _journaliser(nom, {"id": tache, "type": "text-to-3d/preview",
                           "status": "SUBMITTED"})
        fini = _attendre("/v2/text-to-3d/" + tache, cle, "apercu", nom)
        if texturer:
            print("TEXT-TO-3D (texturage PBR)", flush=True)
            rep2 = _requete("/v2/text-to-3d", "POST", {
                "mode": "refine",
                "preview_task_id": tache,
                "enable_pbr": True,
                "texture_prompt": invite_texture,
            }, cle)
            tache2 = _identifiant(rep2)
            fini = _attendre("/v2/text-to-3d/" + tache2, cle, "texture", nom)

    return _telecharger(fini, nom)


if __name__ == "__main__":
    p = argparse.ArgumentParser(description="Generation d'assets 3D via Meshy.")
    p.add_argument("--verifier", action="store_true",
                   help="Valide la cle par un appel gratuit, puis sort.")
    p.add_argument("--mode", choices=("image", "texte", "texture"), default="image")
    p.add_argument("--nom", default="")
    p.add_argument("--prompt", default="")
    p.add_argument("--image", default="")
    p.add_argument("--modele-url", default="", dest="modele_url")
    p.add_argument("--sans-texture", action="store_true")
    p.add_argument("--polycount", type=int, default=30000)
    p.add_argument("--modele-ia", default="latest", dest="modele_ia")
    a = p.parse_args()

    if a.verifier:
        verifier(os.environ.get("MESHY_API_KEY", ""))
        sys.exit(0)
    if not a.nom:
        sys.exit("--nom est requis pour generer.")
    if a.mode == "image" and not a.image:
        sys.exit("--mode image exige --image")
    if a.mode == "texte" and not a.prompt:
        sys.exit("--mode texte exige --prompt")

    generer(a.mode, a.nom, a.prompt, a.image or None, a.modele_url,
            not a.sans_texture, polycount=a.polycount, modele_ia=a.modele_ia)
