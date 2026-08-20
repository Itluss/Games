#!/usr/bin/env bash
# SIGNE LES FICHIERS DU BUILD WEB AVEC LA VERSION DU COMMIT.
#
# POURQUOI CE FICHIER EXISTE. Une publication réussie ne veut pas dire une
# publication VUE. `index.pck` et `index.wasm` gardent le même nom d'un
# déploiement à l'autre ; le navigateur — et le cache du CDN devant les
# pages GitHub — les considère donc comme le même fichier et sert
# l'ancien. Constaté en vrai : un build vert, déployé, et un joueur qui ne
# voit aucun changement. Un rechargement forcé s'en sort parfois ; sur
# téléphone, souvent pas.
#
# La parade est celle de tout le web : le nom PORTE la version. `index.js`
# devient `index.<sha>.js`, et une URL neuve ne peut pas être servie
# depuis un cache. Seul `index.html` garde son nom — il pèse cinq
# kilo-octets et c'est lui qui désigne les autres.
#
# Le chargeur de Godot construit `<executable>.pck` et `<executable>.wasm`
# à partir du champ `executable` de `GODOT_CONFIG` : renommer les fichiers
# ne suffit pas, il faut réécrire ce champ ET les clés de `fileSizes`, qui
# servent à la barre de progression.
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

python3 - "$VERSION" <<'PY'
import re, sys
v = sys.argv[1]
with open('index.html', encoding='utf-8') as f:
	h = f.read()
h = h.replace('<script src="index.js"', '<script src="index.%s.js"' % v)
h = h.replace('"executable":"index"', '"executable":"index.%s"' % v)
for ext in ('pck', 'wasm'):
	h = h.replace('"index.%s":' % ext, '"index.%s.%s":' % (v, ext))
with open('index.html', 'w', encoding='utf-8') as f:
	f.write(h)
# GARDE-FOU : si le gabarit de Godot change de forme, les remplacements
# ci-dessus deviennent silencieusement sans effet et l'on publierait une
# page qui ne trouve plus son moteur. On refuse plutôt que de livrer ça.
manquants = [m for m in ('index.%s.js' % v, '"executable":"index.%s"' % v,
		'"index.%s.pck"' % v, '"index.%s.wasm"' % v) if m not in h]
if manquants:
	raise SystemExit('empreinte_web : gabarit inattendu, absents = %s'
			% ', '.join(manquants))
print('empreinte_web : build signé %s' % v)
PY
