# Modèles 3D

Ce dossier ne contient que ce qui est RÉELLEMENT chargé par le jeu.

Tout ce qui s'y trouve est embarqué dans la build exportée. Y laisser une
texture source de 6 Mo, même inutilisée, l'expédie à chaque joueur — et
sur une build web, la facture se paie au premier chargement.

Les sorties brutes de Meshy — cartes en 2048 px, JSON de tâche complet —
vivent sur la branche `assets-3d`, jamais ici. Le `.glb` intégré est passé
par `outils/alleger_glb.py`, qui réencode ses textures embarquées.

Ordre de grandeur, pour Kael : 11,65 Mo bruts contre 0,83 Mo intégrés.
