# -*- coding: utf-8 -*-
"""Client bas niveau de l'API Meshy.

   SECRET : la cle est lue dans la variable d'environnement MESHY_API_KEY et
   n'est jamais journalisee, jamais ecrite sur disque, jamais incluse dans le
   manifest. Les seules traces conservees sont l'identifiant de tache et le
   prompt, qui ne sont pas secrets. Les erreurs HTTP sont recopiees telles
   quelles SAUF si elles contiennent la cle -- elles ne la contiennent jamais,
   mais on filtre par principe.

   RESEAU : toute requete est retentee sur les erreurs transitoires (5xx,
   429, coupures). Les erreurs definitives (401, 400, 404) ne sont PAS
   retentees : insister sur une cle invalide ne fait que perdre du temps.
"""
import json
import os
import time
import urllib.error
import urllib.request

BASE = "https://api.meshy.ai/openapi"
TIMEOUT = 60

# Codes qui meritent une nouvelle tentative. Le reste est definitif.
TRANSITOIRES = {408, 425, 429, 500, 502, 503, 504}


class ErreurMeshy(Exception):
    def __init__(self, code, message):
        self.code = code
        self.message = message
        super(ErreurMeshy, self).__init__("HTTP %s : %s" % (code, message))


def _cle():
    c = os.environ.get("MESHY_API_KEY", "").strip()
    if not c:
        raise ErreurMeshy(
            "config",
            "MESHY_API_KEY absente de l'environnement. "
            "Elle ne doit jamais etre ecrite dans un fichier du depot.")
    return c


def _masquer(texte):
    """garde-fou : jamais de cle dans un message affiche"""
    c = os.environ.get("MESHY_API_KEY", "")
    if c and c in texte:
        texte = texte.replace(c, "***")
    return texte


def appel(methode, chemin, corps=None, essais=4, attente=3.0):
    """requete authentifiee, avec reprise sur erreur transitoire"""
    url = chemin if chemin.startswith("http") else BASE + chemin
    donnees = json.dumps(corps).encode("utf-8") if corps is not None else None
    entetes = {"Authorization": "Bearer " + _cle()}
    if donnees:
        entetes["Content-Type"] = "application/json"
    derniere = None
    for tentative in range(essais):
        req = urllib.request.Request(url, data=donnees, headers=entetes,
                                     method=methode)
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
                brut = r.read().decode("utf-8", "replace")
                return json.loads(brut) if brut.strip() else {}
        except urllib.error.HTTPError as e:
            msg = _masquer(e.read().decode("utf-8", "replace")[:500])
            derniere = ErreurMeshy(e.code, msg)
            if e.code not in TRANSITOIRES:
                raise derniere
        except Exception as e:
            derniere = ErreurMeshy("reseau", _masquer(str(e))[:300])
        if tentative < essais - 1:
            time.sleep(attente * (2 ** tentative))
    raise derniere


def verifier():
    """Appel de LISTE, gratuit : valide la cle sans consommer un credit.
       Decouvrir une cle morte apres une generation coute la generation."""
    appel("GET", "/v2/text-to-3d?page_num=1&page_size=1")
    return True


def creer_apercu(prompt, polycount=30000, art_style="realistic",
                 symetrie="auto", topologie="triangle"):
    """Lance l'etape APERCU (geometrie sans texture). C'est la premiere des
       deux etapes du texte-vers-3D : on ne peut texturer qu'un apercu."""
    corps = {
        "mode": "preview",
        "prompt": prompt,
        "art_style": art_style,
        "should_remesh": True,
        "topology": topologie,
        "target_polycount": int(polycount),
        "symmetry_mode": symetrie,
    }
    r = appel("POST", "/v2/text-to-3d", corps)
    return r.get("result") or r.get("id")


def creer_texture(id_apercu, prompt=None, enable_pbr=True):
    """Lance l'etape AFFINAGE : c'est elle qui produit les textures PBR."""
    corps = {"mode": "refine", "preview_task_id": id_apercu,
             "enable_pbr": bool(enable_pbr)}
    if prompt:
        corps["texture_prompt"] = prompt
    r = appel("POST", "/v2/text-to-3d", corps)
    return r.get("result") or r.get("id")


def etat(id_tache):
    return appel("GET", "/v2/text-to-3d/%s" % id_tache)


def attendre(id_tache, pas=10, plafond=1800, journal=None):
    """Suit une tache jusqu'a son terme. Renvoie l'objet complet.
       plafond : garde-fou en secondes, pour ne pas boucler indefiniment."""
    debut = time.time()
    dernier = None
    while True:
        t = etat(id_tache)
        st = t.get("status")
        pr = t.get("progress", 0)
        if journal and (st, pr) != dernier:
            journal("      %s %s%%" % (st, pr))
            dernier = (st, pr)
        if st in ("SUCCEEDED", "FAILED", "CANCELED", "EXPIRED"):
            return t
        if time.time() - debut > plafond:
            raise ErreurMeshy("delai",
                              "tache %s toujours %s apres %d s"
                              % (id_tache, st, plafond))
        time.sleep(pas)
