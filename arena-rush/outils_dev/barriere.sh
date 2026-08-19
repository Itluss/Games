#!/usr/bin/env bash
# LANCE UNE BARRIÈRE ET JUGE SON RÉSULTAT.
#
# POURQUOI CE FICHIER EXISTE. La même vingtaine de lignes de vérification
# était recopiée dans chaque étape de la publication : lancer, repérer une
# erreur de compilation, vérifier que le banc s'est VRAIMENT exécuté, puis
# lire le compte d'échecs. Six copies, six occasions de diverger — et la
# règle la plus importante, « un test qui ne compile pas n'est pas un
# problème d'environnement », avait déjà été oubliée une fois.
#
# Usage : barriere.sh <scène> <libellé> [--rendu] [--args…]
set -uo pipefail

SCENE="$1"; shift
NOM="$1"; shift
RENDU=0
if [ "${1:-}" = "--rendu" ]; then RENDU=1; shift; fi
JOURNAL="$(mktemp)"

# `-k 30` N'EST PAS UN DÉTAIL. Sans lui, `timeout` se contente d'un SIGTERM
# et attend indéfiniment que le moteur veuille bien mourir. C'est arrivé :
# une barrière est restée quinze minutes sur une étape qui en prend
# quarante-cinq secondes, bloquant toute la publication derrière elle,
# alors que le même banc passait en trois secondes en local. Après le délai
# de grâce, on tue pour de bon.
if [ "$RENDU" = "1" ]; then
  timeout -k 30 320 xvfb-run -a -s "-screen 0 1280x720x24" ~/godot-bin/godot \
    --path arena-rush "$SCENE" --rendering-driver opengl3 -- --solo "$@" \
    2>&1 | tee "$JOURNAL" || true
else
  timeout -k 30 320 ~/godot-bin/godot --headless --path arena-rush "$SCENE" \
    -- --solo "$@" 2>&1 | tee "$JOURNAL" || true
fi

# UN BANC QUI NE COMPILE PAS N'EST PAS UN PROBLÈME D'ENVIRONNEMENT. Sans
# cette distinction, une erreur de syntaxe le rendait muet, donc « non
# exécutable », donc un simple avertissement — et la publication passait au
# vert sans que rien n'ait été vérifié. C'est arrivé.
if grep -qE "Parse Error|Failed to load script" "$JOURNAL"; then
  echo "::error::$NOM : le banc ne compile pas."
  grep -E "Parse Error|Failed to load script" -A2 "$JOURNAL"
  exit 1
fi
if ! grep -qE "vérifications? ===|échec\(s\) ===" "$JOURNAL"; then
  echo "::error::$NOM : le banc ne s'est pas exécuté jusqu'au bout."
  exit 1
fi
grep -E "^\s+\[(OK|ÉCHEC)\]" "$JOURNAL" || true
if grep -qE "=== [1-9][0-9]* échec\(s\)" "$JOURNAL"; then
  echo "::error::$NOM : régression."
  exit 1
fi
echo "$NOM : conforme."
