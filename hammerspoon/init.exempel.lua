-- Exempel på ~/.hammerspoon/init.lua. Ändra sökvägen till där du klonade projektet.
-- installera.sh lägger in raderna åt dig om de saknas.
require("hs.ipc")  -- gör att kommandot hs fungerar i terminalen (används av testerna)
prata = dofile(os.getenv("HOME") .. "/prata/hammerspoon/dikt.lua")
prata.start()
hs.shutdownCallback = function() prata.stopp() end
