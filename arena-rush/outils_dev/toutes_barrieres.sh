#!/usr/bin/env bash
# LANCE TOUTES LES BARRIÈRES, DANS L'ORDRE ET LA CONFIGURATION DE LA CI.
#
# POURQUOI CE FICHIER VIT DANS LE DÉPÔT. Il existait jusqu'ici comme script
# jetable dans un dossier temporaire, et il a disparu trois fois de suite —
# à chaque fois que le conteneur de travail a été recréé. Chaque disparition
# coûtait le temps de le réécrire, et surtout le risque de le réécrire
# DIFFÉREMMENT de la CI : une suite locale qui ne lance pas les mêmes bancs
# que l'intégration continue donne un feu vert qui ne vaut rien.
#
# Il est donc versionné, à côté de `barriere.sh` qu'il appelle. La liste
# ci-dessous doit rester le miroir de `.github/workflows/deploy-web.yml` :
# si l'une change, l'autre change.
#
# Usage, depuis la racine du dépôt :
#   arena-rush/outils_dev/toutes_barrieres.sh
set -uo pipefail

export DISPLAY="${DISPLAY:-:77}"

# nom | scène | rendu (1 = xvfb) | arguments supplémentaires
BARRIERES=(
	"Commandes|test_commandes|1|"
	"Plan du monde|test_arene|0|"
	"Dégagement|sonde_occlusion|0|"
	"Repères|sonde_toits|0|"
	"Progression|test_progression|0|"
	"Stabilité|sonde_violet|0|--mobile"
	"Couture|sonde_couture|1|"
	"Enroulement|test_enroulement|1|"
	"Boucle persistante|test_arene_persistante|1|"
	"Étoile Wanted|banc_etoile|1|"
	"Armes|banc_armes|0|"
	"Western|banc_western|0|"
)

ECHECS=0
for ligne in "${BARRIERES[@]}"; do
	IFS='|' read -r nom scene rendu extra <<< "$ligne"
	if [ "$rendu" = "1" ]; then
		SORTIE=$(timeout 700 arena-rush/outils_dev/barriere.sh \
				"res://outils_dev/${scene}.tscn" "$nom" --rendu $extra 2>&1)
	else
		SORTIE=$(timeout 700 arena-rush/outils_dev/barriere.sh \
				"res://outils_dev/${scene}.tscn" "$nom" $extra 2>&1)
	fi
	RESUME=$(echo "$SORTIE" | grep -E 'conforme|échec\(s\)|ne s.est pas exécuté|::error' \
			| tail -2 | tr '\n' ' ')
	echo "RESULTAT ${nom} :: ${RESUME}"
	if echo "$RESUME" | grep -q '::error'; then
		ECHECS=$((ECHECS + 1))
	fi
done

echo "=== ${ECHECS} barrière(s) en échec sur ${#BARRIERES[@]} ==="
echo "GATES-TERMINE"
exit $([ "$ECHECS" -eq 0 ] && echo 0 || echo 1)
