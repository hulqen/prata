-- Exempel på ~/.hammerspoon/init.lua. Ändra sökvägen till där du klonade projektet.
-- installera.sh lägger in raderna åt dig om de saknas.
require("hs.ipc")  -- gör att kommandot hs fungerar i terminalen (används av testerna)
pianissimo = dofile(os.getenv("HOME") .. "/pianissimo/hammerspoon/dikt.lua")
pianissimo.start()
hs.shutdownCallback = function() pianissimo.stopp() end
