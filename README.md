# Games

Jeux d'Itluss. Dépôt public — GitHub Pages y est gratuit, ce qui permet de
publier un lien jouable dans le navigateur.

## Arena Rush

Prototype d'arène 3D multijoueur : survie, PvE contre des mobs, loot
d'armes, PvP, zone qui se referme, dernier survivant. Conçu mobile d'abord
(paysage, contrôles tactiles), en **Godot 4.3** et 100 % GDScript.

Sources dans [`arena-rush/`](arena-rush/) — voir son
[README](arena-rush/README.md) pour l'architecture et les choix techniques.

### Jouer dans le navigateur

Le workflow [`deploy-web.yml`](.github/workflows/deploy-web.yml) construit
l'export WebAssembly et le publie sur GitHub Pages.

**À faire une seule fois** : `Settings` → `Pages` → `Source` =
**GitHub Actions**. Ensuite, onglet `Actions` → « Publier le jeu sur le
web » → `Run workflow`. Le lien s'affiche dans le résumé du run, puis
reste disponible dans `Settings → Pages`.

Le premier chargement télécharge ~34 Mo de WebAssembly : compter quelques
secondes d'attente avant que le menu n'apparaisse.

En web, jouer en **SOLO contre 3 bots**. Le multijoueur repose sur ENet
(sockets UDP), qui n'existe pas dans un navigateur ; il fonctionne sur les
builds Windows et Linux.

### Jouer en local, ou modifier le jeu

Installer [Godot 4.3](https://godotengine.org/download) — un seul
exécutable, rien à installer — puis ouvrir `arena-rush/project.godot`.

```bash
godot --path arena-rush            # menu
godot --path arena-rush --solo     # partie solo directe
```

Pour tester le multijoueur sans second appareil :
`Débogage → Exécuter plusieurs instances`, puis « HÉBERGER » sur la
première fenêtre et « REJOINDRE » sur les autres.

### Contrôles

| | Tactile | Clavier / souris |
|---|---|---|
| Déplacement | Joystick gauche | WASD / ZQSD / flèches |
| Tirer | Bouton TIR (maintenir), glisser = viser | Clic gauche ou Espace |
| Changer d'arme | Bouton ARME ou taper l'emplacement | A / Q ou Tab |
| Esquive | Bouton ESQUIVE | Maj ou E |
| Debug | — | F1 |
