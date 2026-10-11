#!/bin/sh
# Installerar Prata. Kör från projektmappen: ./installera.sh
# Kan köras om, till exempel för att bygga om Python-miljön.
set -e
MAPP="$(cd "$(dirname "$0")" && pwd)"
cd "$MAPP"

[ "$(uname -m)" = "arm64" ] || { echo "Kräver en Mac med Apple silicon (M1 eller senare)."; exit 1; }
command -v brew >/dev/null || { echo "Homebrew saknas. Installera från https://brew.sh och kör igen."; exit 1; }

command -v uv >/dev/null || { echo "Installerar uv …"; brew install uv; }
[ -d /Applications/Hammerspoon.app ] || { echo "Installerar Hammerspoon …"; brew install --cask hammerspoon; }

echo "Bygger Python-miljön (Python 3.12) i $MAPP/.venv …"
uv venv --python 3.12 --allow-existing .venv
uv pip install --python .venv/bin/python -r requirements.txt

echo "Hämtar modellen (cirka 0,7 GB första gången) …"
.venv/bin/python -c "import dikt_server; dikt_server.hamta_modell()"  # den låsta versionen, se MODELL_VERSION

for namn in ordlista ersattningar; do
  [ -f "$namn.txt" ] || cp "$namn.exempel.txt" "$namn.txt"
done

INIT="$HOME/.hammerspoon/init.lua"
if grep -qs "hammerspoon/dikt.lua" "$INIT"; then
  echo "Hammerspoon är redan inställt i $INIT."
else
  mkdir -p "$HOME/.hammerspoon"
  cat >> "$INIT" <<LUA

-- Prata (diktering)
require("hs.ipc")
prata = dofile("$MAPP/hammerspoon/dikt.lua")
prata.start()
hs.shutdownCallback = function() prata.stopp() end
LUA
  echo "Lade till Prata i $INIT."
fi

cat <<TEXT

Klart. Kvar att göra:
1. Starta Hammerspoon (eller välj Reload Config i dess meny om det redan körs).
2. Ge Hammerspoon behörighet under Systeminställningar > Integritet och säkerhet > Hjälpmedel.
3. Håll in höger Option och prata i valfri textruta. Godkänn mikrofonfrågan första gången.
4. Valfritt: slå på "Launch Hammerspoon at login" i Hammerspoons inställningar.
Hjälp finns i menyraden under mikrofonsymbolen > Hjälp …
TEXT
