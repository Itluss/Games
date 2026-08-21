#!/usr/bin/env bash
# SIGNE LE BUILD WEB AVEC LA VERSION DU COMMIT, ET REND LA PAGE CAPABLE DE
# S'APERCEVOIR QU'ELLE EST PÉRIMÉE.
#
# POURQUOI CE FICHIER EXISTE. Une publication réussie ne veut pas dire une
# publication VUE. Le problème s'est présenté en deux temps, et la première
# correction n'en réglait que la moitié.
#
# TEMPS 1 — `index.pck` et `index.wasm` gardaient le même nom d'un
# déploiement à l'autre. Le navigateur, et le cache du CDN devant les pages
# GitHub, les traitaient donc comme le même fichier et servaient l'ancien.
# Parade classique : le nom PORTE la version. Une URL neuve ne peut pas
# venir d'un cache.
#
# TEMPS 2 — sauf que c'est `index.html` qui porte ces noms, et LUI garde le
# sien. Un navigateur qui a la page en cache redemande donc l'ancien
# `.pck`, qu'il a aussi. Publication réussie, écran inchangé, une seconde
# fois. On ne peut pas régler d'en-têtes HTTP sur les pages GitHub : la
# page vérifie donc elle-même, en relisant `version.txt` hors cache, et se
# recharge sur une ADRESSE DIFFÉRENTE si elle se découvre en retard.
#
# Le chargeur de Godot construit `<executable>.pck` et `<executable>.wasm`
# à partir du champ `executable` de `GODOT_CONFIG` : renommer les fichiers
# ne suffit pas, il faut réécrire ce champ ET les clés de `fileSizes`, qui
# pilotent la barre de progression.
#
# Usage : empreinte_web.sh <dossier> <version>
set -euo pipefail

DOSSIER="$1"
VERSION="$2"

cd "$DOSSIER"
for ext in js pck wasm; do
	if [ -f "index.$ext" ]; then
		mv "index.$ext" "index.$VERSION.$ext"
	fi
done

# La version publiée seule, dans un fichier d'un octet ou deux : c'est elle
# que la page ira relire pour savoir si elle-même est périmée.
printf '%s' "$VERSION" > version.txt

python3 - "$VERSION" <<'PY'
import sys

v = sys.argv[1]
with open('index.html', encoding='utf-8') as f:
	h = f.read()

h = h.replace('<script src="index.js"', '<script src="index.%s.js"' % v)
h = h.replace('"executable":"index"', '"executable":"index.%s"' % v)
for ext in ('pck', 'wasm'):
	h = h.replace('"index.%s":' % ext, '"index.%s.%s":' % (v, ext))

# LE VEILLEUR. Il tourne au tout début de la page, avant le moteur : si la
# page servie n'est pas la dernière publiée, il repart sur une adresse que
# le cache ne peut pas satisfaire.
#
# Le drapeau de session empêche la boucle. Si la redirection ne suffisait
# pas — un cache intermédiaire vraiment têtu — on n'essaie qu'une fois et
# l'on laisse le joueur jouer, fût-ce sur une version en retard : un jeu
# qui se recharge sans fin serait pire qu'un jeu en retard d'une version.
# ─── PLAFOND DE RÉSOLUTION ──────────────────────────────────────────────
#
# En étirement « canvas_items », Godot rend la 3D à la taille PHYSIQUE du
# canvas : sur un téléphone à densité 3, c'est trois mégapixels de désert
# par image dans un rendu WebGL — le fill-rate, pas les triangles, et
# aucune de nos sondes de géométrie ne pouvait le voir. Le moteur lit
# `window.devicePixelRatio` au démarrage : on le plafonne AVANT qu'il ne
# démarre. À 1,6 sur un écran de six pouces, la perte de piqué est sous le
# seuil de l'œil ; la surface à remplir, elle, est divisée par plus de
# trois. L'interface est mise en page en pixels CSS, elle ne bouge pas.
veilleur = '''<meta http-equiv="Cache-Control" content="no-cache">
<script>
(function () {
	var reel = window.devicePixelRatio || 1;
	var plafond = 1.6;
	if (reel > plafond) {
		Object.defineProperty(window, "devicePixelRatio", {
			get: function () { return plafond; }
		});
	}
})();
</script>
<script>
(function () {
	var attendue = "%s";
	fetch("version.txt?t=" + Date.now(), { cache: "no-store" })
		.then(function (r) { return r.ok ? r.text() : ""; })
		.then(function (t) {
			t = (t || "").trim();
			if (!t || t === attendue) { return; }
			// LE DRAPEAU SE COMPARE À LA VERSION VISÉE, PAS À CELLE DE LA
			// PAGE. Comparé à celle de la page, il ne servait à rien : au
			// rechargement, la page périmée annonçait toujours l'ancienne
			// version, le drapeau ne correspondait jamais, et l'on
			// repartait pour un tour. Boucle infinie observée en essai —
			// exactement le cas qu'il devait empêcher.
			try {
				if (sessionStorage.getItem("maj_tentee") === t) { return; }
				sessionStorage.setItem("maj_tentee", t);
			} catch (e) { return; }
			location.replace(location.pathname + "?v=" + encodeURIComponent(t));
		})
		.catch(function () {});
})();
</script>
</head>''' % v
if '</head>' not in h:
	raise SystemExit('empreinte_web : pas de </head> dans index.html')
h = h.replace('</head>', veilleur, 1)

with open('index.html', 'w', encoding='utf-8') as f:
	f.write(h)

# GARDE-FOU : si le gabarit de Godot change de forme, les remplacements
# ci-dessus deviennent silencieusement sans effet et l'on publierait une
# page qui ne trouve plus son moteur. On refuse plutôt que de livrer ça.
attendus = ('index.%s.js' % v, '"executable":"index.%s"' % v,
		'"index.%s.pck"' % v, '"index.%s.wasm"' % v, 'maj_tentee')
manquants = [m for m in attendus if m not in h]
if manquants:
	raise SystemExit('empreinte_web : gabarit inattendu, absents = %s'
			% ', '.join(manquants))
print('empreinte_web : build signé %s' % v)
PY
