# -*- coding: utf-8 -*-
"""Telechargement LOCAL d'un resultat Meshy.

   REGLE CENTRALE : une generation n'est terminee que lorsque ses fichiers
   sont sur le disque et verifies. Le stockage Meshy est TEMPORAIRE -- ses
   URL expirent. Considerer un asset comme acquis parce que l'API dit
   SUCCEEDED, c'est se retrouver plus tard avec un manifest qui pointe vers
   le vide.

   On telecharge donc, dans l'ordre : le GLB (prioritaire), les autres
   formats disponibles s'ils sont utiles, les textures PBR, puis l'apercu
   image. Chaque fichier est ensuite VERIFIE sur disque : existence, taille
   non nulle, et pour le GLB la signature d'entete.
"""
import json
import os
import time
import urllib.error
import urllib.request

TIMEOUT = 180
FORMATS_UTILES = ("glb", "fbx", "obj", "usdz")
FORMATS_PRIORITAIRES = ("glb",)


def _telecharger(url, destination, essais=4, attente=3.0):
    """recupere une URL vers un fichier, avec reprise. Ecriture atomique :
       on passe par un .part, renomme seulement une fois complet -- un
       telechargement coupe ne laisse jamais un fichier d'apparence valide."""
    os.makedirs(os.path.dirname(destination), exist_ok=True)
    part = destination + ".part"
    derniere = None
    for tentative in range(essais):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "port-poc/1"})
            with urllib.request.urlopen(req, timeout=TIMEOUT) as r, \
                    open(part, "wb") as f:
                while True:
                    bloc = r.read(65536)
                    if not bloc:
                        break
                    f.write(bloc)
            taille = os.path.getsize(part)
            if taille == 0:
                raise IOError("fichier vide")
            if os.path.exists(destination):
                os.remove(destination)
            os.rename(part, destination)
            return taille
        except Exception as e:
            derniere = e
            if os.path.exists(part):
                try:
                    os.remove(part)
                except OSError:
                    pass
            if tentative < essais - 1:
                time.sleep(attente * (2 ** tentative))
    raise IOError("telechargement echoue : %s (%s)" % (destination, derniere))


def valider_glb(chemin):
    """un GLB commence par la signature 'glTF' suivie de la version.
       Un HTML d'erreur enregistre sous .glb passerait sans ce controle."""
    try:
        with open(chemin, "rb") as f:
            entete = f.read(12)
        if len(entete) < 12 or entete[:4] != b"glTF":
            return False, "signature glTF absente"
        return True, "glTF v%d, %d octets" % (
            int.from_bytes(entete[4:8], "little"), os.path.getsize(chemin))
    except Exception as e:
        return False, str(e)


def telecharger_tache(tache, dossier, base_nom, journal=print):
    """Telecharge tout ce qu'une tache Meshy terminee expose.
       Renvoie un dictionnaire pret a etre insere dans le manifest."""
    resultat = {"fichiers": {}, "textures": [], "apercu": None,
                "octets_total": 0, "anomalies": []}
    urls = tache.get("model_urls") or {}

    # --- modeles
    for fmt in FORMATS_UTILES:
        url = urls.get(fmt)
        if not url:
            continue
        dest = os.path.join(dossier, "%s.%s" % (base_nom, fmt))
        try:
            taille = _telecharger(url, dest)
            resultat["fichiers"][fmt] = {
                "chemin": os.path.relpath(dest).replace("\\", "/"),
                "octets": taille}
            resultat["octets_total"] += taille
            journal("      %-5s %8.1f Ko" % (fmt, taille / 1024.0))
        except Exception as e:
            resultat["anomalies"].append("format %s : %s" % (fmt, e))
            if fmt in FORMATS_PRIORITAIRES:
                raise

    # --- textures PBR
    dossier_tex = os.path.join(dossier, "%s_textures" % base_nom)
    for i, tex in enumerate(tache.get("texture_urls") or []):
        for role, url in sorted(tex.items()):
            if not url or not isinstance(url, str) or not url.startswith("http"):
                continue
            ext = url.split("?")[0].rsplit(".", 1)[-1][:4] or "png"
            dest = os.path.join(dossier_tex, "%s_%d_%s.%s"
                                % (base_nom, i, role, ext))
            try:
                taille = _telecharger(url, dest)
                resultat["textures"].append({
                    "role": role,
                    "chemin": os.path.relpath(dest).replace("\\", "/"),
                    "octets": taille})
                resultat["octets_total"] += taille
                journal("      texture %-16s %8.1f Ko" % (role, taille / 1024.0))
            except Exception as e:
                resultat["anomalies"].append("texture %s : %s" % (role, e))

    # --- apercu image, utile pour trier la bibliotheque a l'oeil
    ap = tache.get("thumbnail_url")
    if ap:
        prev = os.path.join(os.path.dirname(os.path.dirname(dossier)),
                            "previews", "%s.png" % base_nom)
        try:
            _telecharger(ap, prev)
            resultat["apercu"] = os.path.relpath(prev).replace("\\", "/")
        except Exception as e:
            resultat["anomalies"].append("apercu : %s" % e)

    # --- VERIFICATION sur disque : c'est elle qui autorise a dire "termine"
    glb = resultat["fichiers"].get("glb")
    if not glb:
        resultat["anomalies"].append("aucun GLB telecharge")
        resultat["valide"] = False
        return resultat
    chemin_glb = glb["chemin"]
    ok, detail = valider_glb(chemin_glb)
    resultat["controle_glb"] = detail
    if not ok:
        resultat["anomalies"].append("GLB invalide : %s" % detail)
    # Un GLB Meshy embarque ses textures ; l'absence de fichiers de texture
    # separes n'est donc pas une anomalie en soi, mais elle se signale.
    if not resultat["textures"]:
        resultat["anomalies"].append(
            "aucune texture separee exposee par l'API "
            "(a verifier : textures embarquees dans le GLB ?)")
    resultat["valide"] = ok
    return resultat


if __name__ == "__main__":
    import argparse
    import meshy_api
    ap = argparse.ArgumentParser(description="Telecharge une tache Meshy deja terminee")
    ap.add_argument("id_tache")
    ap.add_argument("--dossier", default="assets/port_poc/generated/divers")
    ap.add_argument("--nom", required=True)
    a = ap.parse_args()
    t = meshy_api.etat(a.id_tache)
    if t.get("status") != "SUCCEEDED":
        raise SystemExit("tache %s : etat %s" % (a.id_tache, t.get("status")))
    r = telecharger_tache(t, a.dossier, a.nom)
    print(json.dumps(r, ensure_ascii=False, indent=2))
