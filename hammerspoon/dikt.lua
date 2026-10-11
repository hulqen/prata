-- Prata: håll in (eller tryck på) en tangent och prata, texten klistras in där markören står.
-- Tangent och läge väljs i menyraden och sparas med hs.settings.
-- Laddas från ~/.hammerspoon/init.lua (se hammerspoon/init.exempel.lua). Startar och övervakar Python-tjänsten själv.

local M = {}

M.VERSION = "1.0.1"  -- höj vid ändringar: tredje siffran för rättningar, andra för nya funktioner

-- Projektmappen räknas fram från var den här filen ligger, så att mappen kan ligga var som helst.
local HEM = debug.getinfo(1, "S").source:sub(2):match("^(.*)/hammerspoon/[^/]*$")
local PYTHON = HEM .. "/.venv/bin/python"
local SERVER = HEM .. "/dikt_server.py"
local LOGG = HEM .. "/logg/dikt.log"
local URL = "http://127.0.0.1:47821"

local MIN_HALLTID = 0.3        -- kortare tryck än så räknas som misstag och kastas
local MELLANSLAG_EFTER = true  -- lägg ett mellanslag efter texten så att nästa diktering inte klistras ihop
local TAPP_MAX = 0.5           -- i läget tryck av/på: längsta tryck som räknas som ett tryck
local MASK = hs.eventtap.event.rawFlagMasks

local TANGENTER = {
  { id = "hogerOption",  namn = "Höger Option (⌥)",  kod = 61, mask = MASK.deviceRightAlternate },
  { id = "hogerCommand", namn = "Höger Command (⌘)", kod = 54, mask = MASK.deviceRightCommand },
  { id = "hogerShift",   namn = "Höger Shift (⇧)",   kod = 60, mask = MASK.deviceRightShift },
  { id = "hogerControl", namn = "Höger Control (⌃)", kod = 62, mask = MASK.deviceRightControl },
  { id = "fn",           namn = "fn / 🌐",            kod = 63, mask = MASK.secondaryFn },
}
local LAGEN = {
  { id = "push",   namn = "Håll in och prata" },
  { id = "toggle", namn = "Tryck för att starta, tryck igen för att stoppa" },
}

local task, redo, spelar, nere, annanTangent, tryckTid, startTid, meny, tap, vakt, manuellOmstart
local omstarter = 0
local vantande = {}  -- timers som väntar på att köras; utan referens kan Lua städa bort dem i förtid

local function senare(sekunder, fn)
  local timer
  timer = hs.timer.doAfter(sekunder, function()
    vantande[timer] = nil
    fn()
  end)
  vantande[timer] = true
end

local MIK = hs.image.imageFromName("NSTouchBarAudioInputTemplate")
local ikoner = {}

-- Mikrofonsymbolen ifylld med en färg (för lägen som ska synas tydligt i menyraden).
local function farglagd(farg)
  local c = hs.canvas.new({ x = 0, y = 0, w = 18, h = 18 })
  c[1] = { type = "image", image = MIK, imageScaling = "scaleProportionally" }
  c[2] = { type = "rectangle", action = "fill", fillColor = farg, compositeRule = "sourceAtop" }
  local bild = c:imageFromCanvas()
  c:delete()
  return bild
end

local function visa(lage)
  if not meny then return end
  if not ikoner.redo then
    ikoner.redo = MIK:copy():size({ w = 18, h = 18 }):template(true)
    ikoner.spelar = farglagd({ red = 0.95, green = 0.2, blue = 0.2 })
    ikoner.tolkar = farglagd({ red = 0.3, green = 0.55, blue = 1 })
    ikoner.fel = farglagd({ red = 1, green = 0.65, blue = 0 })
  end
  local ikon = { laddar = ikoner.redo, redo = ikoner.redo, spelar = ikoner.spelar, tolkar = ikoner.tolkar, fel = ikoner.fel }
  meny:setIcon(ikon[lage] or ikoner.redo, lage == "redo" or lage == "laddar")
  meny:setTitle(lage == "laddar" and "…" or nil)
end

local function post(sokvag, cb)
  hs.http.asyncPost(URL .. sokvag, "", nil, function(status, body)
    if cb then cb(status, body) end
  end)
end

-- Python-tjänsten -----------------------------------------------------------

local function vantaPaRedo(forsok)
  hs.http.asyncGet(URL .. "/ping", nil, function(status)
    if status == 200 then
      redo = true
      omstarter = 0
      visa("redo")
    elseif forsok < 120 then
      senare(0.5, function() vantaPaRedo(forsok + 1) end)
    else
      visa("fel")
      hs.alert.show("Prata: tjänsten startade inte, se loggen")
    end
  end)
end

local function startaTjanst()
  redo = false
  visa("laddar")
  hs.execute("/usr/bin/pkill -f '[d]ikt_server.py'")  -- städa bort en eventuell kvarglömd tjänst
  hs.fs.mkdir(HEM .. "/logg")
  task = hs.task.new("/bin/sh", function(kod)
    task = nil
    redo = false
    if M.avslutar then return end
    if manuellOmstart then manuellOmstart = false; return end
    visa("fel")
    omstarter = omstarter + 1
    if omstarter <= 3 then
      senare(2 * omstarter, startaTjanst)
    else
      hs.alert.show("Prata: tjänsten kraschar upprepade gånger, se loggen")
    end
  end, { "-c", string.format('exec "%s" "%s" >> "%s" 2>&1', PYTHON, SERVER, LOGG) })
  task:start()
  vantaPaRedo(0)
end

-- Inklistring ---------------------------------------------------------------

local function klistraIn(text)
  local sparat = hs.pasteboard.readAllData()
  hs.pasteboard.setContents(text)
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)
  senare(0.5, function()
    if sparat and next(sparat) then hs.pasteboard.writeAllData(sparat) end
  end)
end

-- Tangenten -----------------------------------------------------------------

local function tangent()
  local id = hs.settings.get("prata.tangent")
  for _, t in ipairs(TANGENTER) do if t.id == id then return t end end
  return TANGENTER[1]
end

local function lage()
  return hs.settings.get("prata.lage") == "toggle" and "toggle" or "push"
end

local function borjaSpela()
  if not redo then
    hs.alert.show("Prata laddar fortfarande modellen …", 1)
    return
  end
  spelar, startTid = true, hs.timer.secondsSinceEpoch()
  visa("spelar")
  post("/start")
end

local function avbryt()
  spelar = false
  post("/avbryt")
  visa(redo and "redo" or "fel")
end

local function slutaSpela()
  if hs.timer.secondsSinceEpoch() - startTid < MIN_HALLTID then return avbryt() end
  spelar = false
  visa("tolkar")
  post("/stop", function(status, body)
    visa(redo and "redo" or "fel")
    if status ~= 200 then
      hs.alert.show("Prata: transkriberingen misslyckades")
      return
    end
    local ok, data = pcall(hs.json.decode, body)
    local text = ok and data and data.text or ""
    if text ~= "" then klistraIn(MELLANSLAG_EFTER and (text .. " ") or text) end
  end)
end

local function hanteraHandelse(e)
  local typ = e:getType()
  local t = tangent()
  if typ == hs.eventtap.event.types.flagsChanged then
    if e:getKeyCode() ~= t.kod then return false end
    local arNere = (e:rawFlags() & t.mask) ~= 0
    if arNere and not nere then
      nere, annanTangent, tryckTid = true, false, hs.timer.secondsSinceEpoch()
      if lage() == "push" and not spelar then borjaSpela() end
    elseif not arNere and nere then
      nere = false
      if lage() == "push" then
        if spelar then slutaSpela() end
      elseif not annanTangent and hs.timer.secondsSinceEpoch() - tryckTid < TAPP_MAX then
        if spelar then slutaSpela() else borjaSpela() end
      end
    end
  elseif typ == hs.eventtap.event.types.keyDown then
    if nere then
      -- Tangenten användes tillsammans med en annan (t.ex. ⌥2 = @): det var ingen diktering.
      annanTangent = true
      if lage() == "push" and spelar then avbryt() end
    elseif lage() == "toggle" and spelar and e:getKeyCode() == hs.keycodes.map.escape then
      avbryt()
      return true  -- Esc avbryter dikteringen och skickas inte vidare till appen
    end
  end
  return false
end

local function byt(nyckel, varde)
  if spelar then avbryt() end
  nere = false
  hs.settings.set(nyckel, varde)
end

local function instruktion()
  local namn = tangent().namn:gsub("^Höger", "höger")  -- mitt i meningen: liten bokstav
  if lage() == "push" then return "Håll in " .. namn .. " och prata" end
  return "Tryck på " .. namn .. " för att starta och stoppa, Esc avbryter"
end

-- Lär in rättning -----------------------------------------------------------
-- Markera en felstavning, tryck ⌃⌥R och skriv rätt stavning: texten byts ut och
-- felstavningen sparas i ersattningar.txt via tjänsten.

local LAR_IN_TANGENT = { { "ctrl", "alt" }, "r" }

local function trimma(t) return (t or ""):match("^%s*(.-)%s*$") end

local function larIn()
  local fonster = hs.window.focusedWindow()
  local app = hs.application.frontmostApplication()
  local sparat = hs.pasteboard.readAllData()
  local raknare = hs.pasteboard.changeCount()
  local function aterstall()
    if sparat and next(sparat) then hs.pasteboard.writeAllData(sparat) end
  end
  hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  senare(0.25, function()
    local markerat = hs.pasteboard.changeCount() ~= raknare and hs.pasteboard.getContents() or ""
    -- Skiljetecken och mellanslag runt markeringen hör inte till felstavningen men ska stå kvar.
    local fore, karna, efter = markerat:match("^([%s%p]*)(.-)([%s%p]*)$")
    if not karna or karna == "" then
      aterstall()
      hs.alert.show("Markera felstavningen först", 1.5)
      return
    end
    hs.focus()
    local knapp, ratt = hs.dialog.textPrompt("Lär in rättning", "Vad ska ”" .. karna .. "” bli?", karna, "Spara", "Avbryt")
    ratt = trimma(ratt)
    if fonster then fonster:focus() elseif app then app:activate() end
    if knapp ~= "Spara" or ratt == "" or ratt == karna then
      aterstall()
      return
    end
    hs.http.asyncPost(URL .. "/lar_in", hs.json.encode({ ratt = ratt, fel = karna }),
      { ["Content-Type"] = "application/json" }, function(status, body)
        local ok, data = pcall(hs.json.decode, body)
        data = ok and data or {}
        hs.alert.show(data.meddelande or data.fel or "Prata: kunde inte spara rättningen", 2)
      end)
    senare(0.2, function()
      hs.pasteboard.setContents(fore .. ratt .. efter)
      hs.eventtap.keyStroke({ "cmd" }, "v", 0)
      senare(0.5, aterstall)
    end)
  end)
end

-- Hjälp -----------------------------------------------------------------------

function M.visaHjalp()
  local f = io.open(HEM .. "/hjalp.html", "r")
  if not f then return hs.alert.show("Hittar inte hjalp.html") end
  local html = f:read("*a"):gsub("{{INSTRUKTION}}", function() return instruktion() end)
  html = html:gsub("{{VERSION}}", M.VERSION):gsub("{{MAPP}}", function() return (HEM:gsub("^" .. os.getenv("HOME"), "~")) end)
  f:close()
  if M.hjalp then M.hjalp:delete() end
  local skarm = hs.screen.mainScreen():frame()
  local w, h = 620, math.min(760, skarm.h - 80)
  M.hjalp = hs.webview.new({ x = skarm.x + (skarm.w - w) / 2, y = skarm.y + 40, w = w, h = h })
    -- fullSizeContentView: sidans bakgrund fyller även titelraden. Annars är titelraden genomskinlig,
    -- eftersom Hammerspoons webbfönster saknar egen fönsterbakgrund.
    :windowStyle({ "titled", "closable", "miniaturizable", "resizable", "fullSizeContentView" })
    :windowTitle("Prata – hjälp")
    :level(hs.drawing.windowLevels.normal)  -- ett vanligt fönster, inte ovanpå allt (undvik bringToFront)
    :shadow(true)
    :allowTextEntry(true)
    :html(html)
  hs.focus()
  M.hjalp:show()
end

-- Start ---------------------------------------------------------------------

function M.start()
  -- Verktyget hette Pianissimo-diktering i version 1.0.0: flytta över sparade val.
  for _, nyckel in ipairs({ "tangent", "lage" }) do
    local gammal = hs.settings.get("pianissimo." .. nyckel)
    if gammal ~= nil then
      if hs.settings.get("prata." .. nyckel) == nil then hs.settings.set("prata." .. nyckel, gammal) end
      hs.settings.clear("pianissimo." .. nyckel)
    end
  end
  meny = hs.menubar.new()
  meny:setMenu(function()
    return {
      { title = instruktion(), disabled = true },
      { title = "-" },
      { title = "Tangent", menu = hs.fnutils.imap(TANGENTER, function(t)
          return { title = t.namn, checked = (t.id == tangent().id), fn = function() byt("prata.tangent", t.id) end }
        end) },
      { title = "Läge", menu = hs.fnutils.imap(LAGEN, function(l)
          return { title = l.namn, checked = (l.id == lage()), fn = function() byt("prata.lage", l.id) end }
        end) },
      { title = "-" },
      { title = "Redigera ordlistan", fn = function() hs.execute('open -t "' .. HEM .. '/ordlista.txt"') end },
      { title = "Lär in rättning: markera felstavningen och tryck ⌃⌥R", disabled = true },
      { title = "Redigera ersättningar", fn = function() hs.execute('open -t "' .. HEM .. '/ersattningar.txt"') end },
      { title = "-" },
      { title = "Hjälp …", fn = M.visaHjalp },
      { title = "Visa logg", fn = function() hs.execute('open -a Console "' .. LOGG .. '"') end },
      { title = "Starta om tjänsten", fn = function()
          if task then manuellOmstart = true; task:terminate() end
          omstarter = 0
          senare(0.5, startaTjanst)
        end },
      { title = "-" },
      { title = "Prata " .. M.VERSION, disabled = true },
    }
  end)
  M.larInTangent = hs.hotkey.bind(LAR_IN_TANGENT[1], LAR_IN_TANGENT[2], nil, larIn)
  tap = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged, hs.eventtap.event.types.keyDown }, hanteraHandelse)
  tap:start()
  -- macOS kan stänga av en eventtap som svarat långsamt; slå på den igen.
  vakt = hs.timer.doEvery(5, function() if not tap:isEnabled() then tap:start() end end)
  startaTjanst()
end

function M.status()
  return { redo = redo, spelar = spelar, tangent = tangent().id, lage = lage(), tjanst = task ~= nil }
end

function M.status()
  return { redo = redo, spelar = spelar, tangent = tangent().id, lage = lage(), tjanst = task ~= nil }
end

function M.stopp()
  M.avslutar = true
  if tap then tap:stop() end
  if M.larInTangent then M.larInTangent:delete() end
  if M.hjalp then M.hjalp:delete() end
  if vakt then vakt:stop() end
  if task then task:terminate() end
  if meny then meny:delete() end
end

return M
