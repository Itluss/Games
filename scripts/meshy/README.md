# Pipeline Meshy — bibliotheque d'assets du POC port maritime

## Etat

Le pipeline est **complet et teste** sur tout ce qui ne consomme pas de credit.
Aucune generation n'a encore ete lancee : la cle Meshy est refusee par l'API
(`401 Invalid API key`). Voir « Debloquer la cle » plus bas.

## Fichiers

| Fichier | Role |
|---|---|
| `catalogue.py` | Source de verite des 35 prompts. Produit `meshy_prompts.json`. |
| `meshy_api.py` | Client HTTP : auth, reprises reseau, creation et suivi de taches. |
| `download_meshy_asset.py` | Telechargement local + verification sur disque. |
| `generate_port_assets.py` | Orchestrateur idempotent. |
| `check_assets.py` | Controle de la bibliotheque, sans appeler Meshy. |

## Commandes

    python scripts/meshy/generate_port_assets.py --liste
    python scripts/meshy/generate_port_assets.py --verifier-cle
    python scripts/meshy/generate_port_assets.py --batch poc_test --dry-run
    python scripts/meshy/generate_port_assets.py --batch poc_test
    python scripts/meshy/generate_port_assets.py --asset port_forklift_01
    python scripts/meshy/check_assets.py --detail

Lots : `poc_test` (3), `poc_core` (27), `poc_extra` (5), `tout` (35).

## Garanties

**Idempotence.** Un asset n'est regenere que si son GLB est absent du disque
ou invalide. Le statut renvoye par Meshy ne suffit jamais : c'est le fichier
qui fait foi.

**Reprise.** L'identifiant de tache est ecrit dans le manifest *avant*
l'attente. Une execution interrompue reprend au telechargement au lieu de
relancer — et de repayer — la generation.

**Preflight gratuit.** Avant toute generation, un appel de liste valide la
cle. Decouvrir une cle morte apres une generation coute la generation.

**Telechargement local obligatoire.** Le stockage Meshy est traite comme
temporaire. Modele, textures et apercu sont recuperes immediatement, ecrits
de facon atomique (`.part` puis renommage), puis verifies : existence,
taille non nulle, signature `glTF` du GLB.

## Secret

La cle est lue dans la variable d'environnement `MESHY_API_KEY`. Elle n'est
jamais affichee, jamais ecrite sur disque, jamais placee dans le manifest.
`meshy_api._masquer()` filtre par principe tout message d'erreur.

## Debloquer la cle

L'API repond `401 Invalid API key`. La cle presente dans l'environnement a le
bon format mais est refusee : expiree, revoquee, ou liee a un autre compte.

1. meshy.ai → Settings → API Keys → generer une nouvelle cle ;
2. la placer dans `MESHY_API_KEY` (variable d'environnement, **pas** un
   fichier du depot) ;
3. `python scripts/meshy/generate_port_assets.py --verifier-cle` ;
4. puis `--batch poc_test`.

## Note sur les workflows existants

`.github/workflows/generer-asset-3d.yml` et `rigger-personnage.yml` appellent
`outils/meshy.py`, `outils/lancer_generation.py`, `outils/meshy_rig.py` et
`outils/alleger_decor.py` — **aucun de ces fichiers n'existe** dans le depot.
Ces workflows sont donc casses en l'etat. Le present pipeline est autonome et
ne les touche pas.
