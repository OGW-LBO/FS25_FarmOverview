-- =====================================================================================
-- Bodengesundheit.lua  -  Modul des Fruchtfolge-Beraters
-- -------------------------------------------------------------------------------------
-- Macht die Fruchtfolge spuerbar: jedes Farmland hat eine Bodengesundheit 0..100 %.
--   * AUSSAAT: Fruchtfolge wird bewertet - GLEICHES Modell wie die Empfehlung,
--       naemlich CropRotationData.getPFBonus(Vorfrucht, geplante Frucht, Vorvorfrucht).
--       Der Bonus (%) wird mit healthScale in einen Gesundheits-Delta umgerechnet.
--   * ERNTE: der Ertrag (liters) wird mit einem Faktor aus der Gesundheit skaliert
--       (yieldMin .. yieldMax linear ueber 0..100 %).
--
-- Server ist autoritativ (rechnet Gesundheit + Ertrag, nur bei g_server ~= nil).
-- Clients erhalten die Werte fuers HUD per BodengesundheitSyncEvent.
-- Persistenz laeuft ueber den Advisor (fruchtfolgeAdvisor.xml, siehe writeToXML/readFromXML).
--
-- Verifizierte Spiel-APIs:
--   Combine:addCutterArea(area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)
--   SowingMachine:processSowingMachineArea(workArea, dt)  + spec.workAreaParameters.seedsFruitType
--   g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
--   field:getCenterOfFieldWorldPosition()  (Feld -> Farmland-Zuordnung im HUD/Detail)
-- =====================================================================================

Bodengesundheit = {}

-- Laufzeit-Zustand: [farmlandId] = { health, lastHarvest, prevHarvest, plannedFruit, phase, lastDelta }
Bodengesundheit.states = {}

-- Ertragsgrenzen fuer die HUD-Anzeige (auf Clients per Sync gesetzt)
Bodengesundheit.displayYieldMin = 0.80
Bodengesundheit.displayYieldMax = 1.05

Bodengesundheit.hooksInstalled = false
-- Startwerte einmalig aus der vorhandenen Fruchtfolge vorbelegt? (Server, Laufzeit-Flag)
Bodengesundheit.seeded = false

-- Feld -> Farmland Cache (Feldmittelpunkt-Lookup nicht jeden Frame wiederholen)
Bodengesundheit.fieldFarmlandCache = {}

-- -------------------------------------------------------------------------------------
-- Konfiguration + Presets
-- -------------------------------------------------------------------------------------
Bodengesundheit.cfg = {
    enabled     = true,
    affectYield = true,     -- false = nur Anzeige, kein Ertragseingriff
    hudEnabled  = true,
    preset      = "standard",
    startHealth = 80,
    yieldMin    = 0.80,
    yieldMax    = 1.05,
    healthScale = 0.5,      -- getPFBonus(%) * healthScale = Gesundheits-Delta pro Aussaat
    -- Optionale Aufgaben-Arten (Bereich Aufgaben). AN = wird aufgelistet.
    taskWeeds   = true,
    taskRoll    = true,
    taskFert    = true,
    taskLime    = true,
    taskPlow    = true,
}

-- Wurde die Serverfassung der Einstellungen auf diesem Rechner schon
-- uebernommen? Vorher gelten die Vorgaben oben - auf einem MP-Client stand
-- deshalb kurz nach dem Beitreten z. B. Walzen im Aufgabenzettel, obwohl es
-- auf dem Server abgewaehlt ist. Im Einzelspieler/auf dem Server immer wahr.
Bodengesundheit.cfgEmpfangen = false
Bodengesundheit.cfgListeners = {}

function Bodengesundheit.addCfgListener(fn)
    if type(fn) == "function" then
        table.insert(Bodengesundheit.cfgListeners, fn)
    end
end

function Bodengesundheit.notifyCfgListeners()
    for _, fn in ipairs(Bodengesundheit.cfgListeners) do
        fn()
    end
end

-- Schalter, die nur AN/AUS kennen (setCfgValue, Stream, Savegame).
Bodengesundheit.CFG_BOOLS = {
    "enabled", "affectYield", "hudEnabled",
    "taskWeeds", "taskRoll", "taskFert", "taskLime", "taskPlow",
}

Bodengesundheit.PRESETS = {
    arcade      = { startHealth = 85, yieldMin = 0.90, yieldMax = 1.08, healthScale = 0.3 },
    standard    = { startHealth = 80, yieldMin = 0.80, yieldMax = 1.05, healthScale = 0.5 },
    realistisch = { startHealth = 75, yieldMin = 0.65, yieldMax = 1.05, healthScale = 0.7 },
}

-- Startwert-Offset nach AKTUELL wachsender Frucht (falls keine Vorfrucht bekannt).
-- Bodenaufbauer (Gras/Leguminosen) positiv, Zehrer (Hackfruechte/Mais) negativ,
-- Getreide neutral (nicht gelistet = 0). Nur fuer die einmalige Vorbelegung.
Bodengesundheit.CROP_SOIL_SEED = {
    GRASS = 10, MEADOW = 10, FIELDGRASS = 10, ALFALFA = 12, CLOVER = 12,
    SOYBEAN = 8, PEA = 8, GREENBEAN = 8,
    MAIZE = -8, SILAGEMAIZE = -8, SORGHUM = -6,
    POTATO = -10, SUGARBEET = -12, BEETROOT = -10, CARROT = -8, PARSNIP = -8,
    SUNFLOWER = -8, CANOLA = -6,
}

-- =====================================================================================
-- Hilfsfunktionen
-- =====================================================================================
local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function Bodengesundheit.log(msg)
    Logging.info("[Bodengesundheit] " .. tostring(msg))
end

-- Fruchtindex -> Name (GROSSBUCHSTABEN, passend zu CropRotationData) oder nil
function Bodengesundheit.fruitName(index)
    if type(index) ~= "number" or index <= 0 then return nil end
    if g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypeByIndex == nil then
        return nil
    end
    local d = g_fruitTypeManager:getFruitTypeByIndex(index)
    if d ~= nil and type(d.name) == "string" then return string.upper(d.name) end
    return nil
end

-- Weltposition (x,z) eines Fahrzeugs
function Bodengesundheit.getVehicleXZ(vehicle)
    if vehicle == nil then return nil end
    local node = vehicle.rootNode
    if (node == nil or node == 0) and vehicle.components ~= nil and vehicle.components[1] ~= nil then
        node = vehicle.components[1].node
    end
    if node == nil or node == 0 then return nil end
    local x, _, z = getWorldTranslation(node)
    return x, z
end

-- FarmlandId an Weltposition (defensiv)
function Bodengesundheit.getFarmlandId(x, z)
    if x == nil or z == nil then return nil end
    if g_farmlandManager ~= nil and g_farmlandManager.getFarmlandIdAtWorldPosition ~= nil then
        local id = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z)
        if id ~= nil and id > 0 then return id end
    end
    return nil
end

-- Zustand fuer ein Farmland holen/anlegen
function Bodengesundheit.getState(farmlandId)
    local st = Bodengesundheit.states[farmlandId]
    if st == nil then
        st = {
            health = Bodengesundheit.cfg.startHealth,
            lastHarvest = nil,
            prevHarvest = nil,
            plannedFruit = nil,
            phase = "empty",       -- empty | growing | harvested
            lastDelta = 0,
        }
        Bodengesundheit.states[farmlandId] = st
    end
    return st
end

-- Gesundheit -> Ertragsfaktor
function Bodengesundheit.healthToYieldFactor(health, yMin, yMax)
    yMin = yMin or Bodengesundheit.cfg.yieldMin
    yMax = yMax or Bodengesundheit.cfg.yieldMax
    local h = clamp(health, 0, 100) / 100
    return yMin + (yMax - yMin) * h
end

-- Gesundheit fuer ein Feld-Objekt (fuer HUD + Feld-Detail): Feldmittelpunkt -> Farmland -> State.
-- Gibt health (Zahl) und den State (oder nil) zurueck; nie nil fuer health (Fallback startHealth).
function Bodengesundheit.getHealthForField(field, fieldId)
    local farmlandId = nil
    if fieldId ~= nil then
        farmlandId = Bodengesundheit.fieldFarmlandCache[fieldId]
    end
    if farmlandId == nil and field ~= nil and field.getCenterOfFieldWorldPosition ~= nil then
        local fx, fz = field:getCenterOfFieldWorldPosition()
        if fx == nil and field.posX ~= nil then fx, fz = field.posX, field.posZ end
        farmlandId = Bodengesundheit.getFarmlandId(fx, fz)
        if farmlandId ~= nil and fieldId ~= nil then
            Bodengesundheit.fieldFarmlandCache[fieldId] = farmlandId
        end
    end
    if farmlandId == nil then
        return Bodengesundheit.cfg.startHealth, nil
    end
    local st = Bodengesundheit.states[farmlandId]
    if st == nil then
        return Bodengesundheit.cfg.startHealth, nil
    end
    return st.health, st
end

-- =====================================================================================
-- Fruchtfolge-Bewertung (nutzt das GLEICHE Modell wie die Empfehlung)
-- =====================================================================================
function Bodengesundheit.rotationDelta(newFruit, lastFruit, prevFruit)
    if newFruit == nil then return 0 end
    if CropRotationData == nil or CropRotationData.getPFBonus == nil then
        -- Sicherheitsnetz, falls das Datenmodul fehlt: nur grobe Monokultur-Regel
        if lastFruit ~= nil and newFruit == lastFruit then return -12 end
        return 0
    end
    -- getPFBonus(Vorfrucht, Kandidat, Vorvorfrucht) in %
    local bonus = CropRotationData.getPFBonus(lastFruit, newFruit, prevFruit)
    return bonus * Bodengesundheit.cfg.healthScale
end

-- Aussaat: Fruchtfolge bewerten (einmal pro Anbau-Zyklus). Server-Kontext.
function Bodengesundheit.onSow(farmlandId, fruitIndex)
    local name = Bodengesundheit.fruitName(fruitIndex)
    if name == nil then return end

    local st = Bodengesundheit.getState(farmlandId)
    if st.phase == "growing" and st.plannedFruit == name then
        return          -- bereits gezaehlt (laufende Aussaat derselben Frucht)
    end

    local delta = Bodengesundheit.rotationDelta(name, st.lastHarvest, st.prevHarvest)
    st.health = clamp(st.health + delta, 0, 100)
    st.plannedFruit = name
    st.phase = "growing"
    st.lastDelta = delta

    Bodengesundheit.broadcast(farmlandId)
end

-- Ernte: geerntete Frucht als Historie merken (einmal pro Zyklus). Server-Kontext.
function Bodengesundheit.onHarvest(farmlandId, fruitIndex)
    local name = Bodengesundheit.fruitName(fruitIndex)
    if name == nil then return end

    local st = Bodengesundheit.getState(farmlandId)
    if st.phase == "harvested" and st.lastHarvest == name then
        return
    end
    st.prevHarvest = st.lastHarvest
    st.lastHarvest = name
    st.plannedFruit = nil
    st.phase = "harvested"

    Bodengesundheit.broadcast(farmlandId)
end

-- =====================================================================================
-- Synchronisation (Server -> Client)
-- =====================================================================================
function Bodengesundheit.buildFullEntries()
    local entries = {}
    for id, st in pairs(Bodengesundheit.states) do
        entries[#entries + 1] = {
            id = id,
            health = st.health,
            lastHarvest = st.lastHarvest or "",
            phase = st.phase or "empty",
        }
    end
    return entries
end

-- Auf Server: einzelnes Feld an alle Clients broadcasten.
function Bodengesundheit.broadcast(farmlandId)
    if g_server == nil then return end
    if BodengesundheitSyncEvent == nil then return end
    local st = Bodengesundheit.states[farmlandId]
    if st == nil then return end
    local entry = {{
        id = farmlandId,
        health = st.health,
        lastHarvest = st.lastHarvest or "",
        phase = st.phase or "empty",
    }}
    g_server:broadcastEvent(BodengesundheitSyncEvent.new(entry, Bodengesundheit.cfg.yieldMin, Bodengesundheit.cfg.yieldMax))
end

-- Auf Client: empfangene Werte in den Anzeige-Zustand uebernehmen.
function Bodengesundheit.applySync(entries, yieldMin, yieldMax)
    if yieldMin ~= nil then Bodengesundheit.displayYieldMin = yieldMin end
    if yieldMax ~= nil then Bodengesundheit.displayYieldMax = yieldMax end
    if entries == nil then return end
    for _, e in ipairs(entries) do
        local st = Bodengesundheit.states[e.id]
        if st == nil then
            st = { lastDelta = 0 }
            Bodengesundheit.states[e.id] = st
        end
        st.health = e.health
        st.lastHarvest = (e.lastHarvest ~= "" and e.lastHarvest) or nil
        st.phase = e.phase
    end
end

-- =====================================================================================
-- Persistenz (wird vom Advisor in fruchtfolgeAdvisor.xml eingebettet)
-- =====================================================================================
function Bodengesundheit.applyPreset(name)
    local p = Bodengesundheit.PRESETS[name]
    if p == nil then return false end
    local cfg = Bodengesundheit.cfg
    cfg.startHealth = p.startHealth
    cfg.yieldMin    = p.yieldMin
    cfg.yieldMax    = p.yieldMax
    cfg.healthScale = p.healthScale
    return true
end

-- =====================================================================================
-- Einstellungen aendern + Multiplayer-Sync der cfg (Server autoritativ)
-- =====================================================================================
-- Grenzen der numerischen Einstellungen (fuer setCfgValue / Absicherung).
Bodengesundheit.CFG_BOUNDS = {
    startHealth = { 0, 100 },
    yieldMin    = { 0, 2 },
    yieldMax    = { 0, 2 },
    healthScale = { 0, 2 },
}

-- true, wenn dieser Rechner der autoritative Server (bzw. Singleplayer) ist.
function Bodengesundheit.isServer()
    if g_currentMission ~= nil and g_currentMission.getIsServer ~= nil then
        return g_currentMission:getIsServer() == true
    end
    return g_server ~= nil
end

-- Einen Einstellungswert setzen (lokal, ohne Sync).
--   * bool-Schalter direkt setzen
--   * Preset != "custom" -> applyPreset (setzt die 4 Zahlen)
--   * numerische Aenderung -> preset auf "custom"
function Bodengesundheit.setCfgValue(key, value)
    local cfg = Bodengesundheit.cfg
    local istSchalter = false
    for _, k in ipairs(Bodengesundheit.CFG_BOOLS) do
        if k == key then istSchalter = true break end
    end
    if istSchalter then
        cfg[key] = (value == true or value == 1 or value == "true" or value == "1")
        return true
    elseif key == "preset" then
        local name = tostring(value)
        cfg.preset = name
        if name ~= "custom" and Bodengesundheit.PRESETS[name] ~= nil then
            Bodengesundheit.applyPreset(name)
        end
        Bodengesundheit.displayYieldMin = cfg.yieldMin
        Bodengesundheit.displayYieldMax = cfg.yieldMax
        return true
    else
        local b = Bodengesundheit.CFG_BOUNDS[key]
        if b == nil then return false end
        local num = tonumber(value)
        if num == nil then return false end
        cfg[key] = clamp(num, b[1], b[2])
        cfg.preset = "custom"     -- manuelle Zahl -> kein Preset mehr
        Bodengesundheit.displayYieldMin = cfg.yieldMin
        Bodengesundheit.displayYieldMax = cfg.yieldMax
        return true
    end
end

-- Persistenz der Einstellungen (Server schreibt die Savegame-XML ueber den Advisor).
function Bodengesundheit.saveCfg()
    if not Bodengesundheit.isServer() then return end
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.saveSettings ~= nil then
        FruchtfolgeAdvisor.saveSettings()
    end
end

-- Server: aktuelle cfg an alle Clients verteilen.
function Bodengesundheit.broadcastCfg()
    if Bodengesundheit.isServer() and g_server ~= nil and g_server.broadcastEvent ~= nil
            and BodengesundheitCfgEvent ~= nil then
        g_server:broadcastEvent(BodengesundheitCfgEvent.new(true), false)
    end
end

-- Nach einer lokalen Aenderung im Menue aufrufen:
--   Server  -> speichern + an alle verteilen
--   Client  -> Aenderungsvorschlag an den Server schicken (Server ist autoritativ)
function Bodengesundheit.onLocalCfgChange()
    if Bodengesundheit.isServer() then
        Bodengesundheit.saveCfg()
        Bodengesundheit.broadcastCfg()
    elseif g_client ~= nil and g_client.getServerConnection ~= nil
            and BodengesundheitCfgEvent ~= nil then
        local conn = g_client:getServerConnection()
        if conn ~= nil then
            conn:sendEvent(BodengesundheitCfgEvent.new(true))
        end
    end
end

-- Client fordert beim Menue-Oeffnen einmal die aktuellen Einstellungen vom Server an.
function Bodengesundheit.requestCfgSync()
    if Bodengesundheit.isServer() then return end
    if g_client == nil or g_client.getServerConnection == nil then return end
    local conn = g_client:getServerConnection()
    if conn ~= nil and BodengesundheitCfgEvent ~= nil then
        conn:sendEvent(BodengesundheitCfgEvent.new(false))
    end
end

-- Stream-Aufbau der cfg (feste, stabile Reihenfolge). Schreib- und Lese-Seite
-- liegen bewusst in EINER Datei, damit sie garantiert zusammenpassen.
function Bodengesundheit.writeCfgStream(streamId)
    local cfg = Bodengesundheit.cfg
    -- Reihenfolge = CFG_BOOLS (Lesen laeuft ueber dieselbe Liste)
    for _, k in ipairs(Bodengesundheit.CFG_BOOLS) do
        streamWriteBool(streamId, cfg[k] == true)
    end
    streamWriteString(streamId, cfg.preset or "standard")
    streamWriteFloat32(streamId, cfg.startHealth or 80)
    streamWriteFloat32(streamId, cfg.yieldMin or 0.8)
    streamWriteFloat32(streamId, cfg.yieldMax or 1.05)
    streamWriteFloat32(streamId, cfg.healthScale or 0.5)
end

function Bodengesundheit.readCfgStream(streamId)
    local cfg = Bodengesundheit.cfg
    for _, k in ipairs(Bodengesundheit.CFG_BOOLS) do
        cfg[k] = streamReadBool(streamId)
    end
    -- Von den Werten haengt die Anzeige ab (u. a. welche Feldarbeiten im
    -- Aufgabenzettel stehen). Eine offene Seite zieht deshalb sofort nach,
    -- statt bis zur naechsten Live-Auswertung zu warten.
    Bodengesundheit.cfgEmpfangen = true
    Bodengesundheit.notifyCfgListeners()
    local preset    = streamReadString(streamId)
    if preset ~= nil and preset ~= "" then cfg.preset = preset end
    cfg.startHealth = streamReadFloat32(streamId)
    cfg.yieldMin    = streamReadFloat32(streamId)
    cfg.yieldMax    = streamReadFloat32(streamId)
    cfg.healthScale = streamReadFloat32(streamId)
    Bodengesundheit.displayYieldMin = cfg.yieldMin
    Bodengesundheit.displayYieldMax = cfg.yieldMax
end

-- Gedaechtnis-String  "12=73.5:WHEAT:BARLEY:harvested;7=61:MAIZE::growing"
--   je Feld: farmlandId = health : lastHarvest : prevHarvest : phase
function Bodengesundheit.serializeStates()
    local parts = {}
    for id, st in pairs(Bodengesundheit.states) do
        parts[#parts + 1] = string.format("%d=%.1f:%s:%s:%s",
            id, st.health or 0, st.lastHarvest or "", st.prevHarvest or "", st.phase or "empty")
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

function Bodengesundheit.deserializeStates(s)
    Bodengesundheit.states = {}
    if type(s) ~= "string" or s == "" then return end
    for entry in string.gmatch(s, "[^;]+") do
        local id, rest = string.match(entry, "^(%d+)=(.+)$")
        if id ~= nil and rest ~= nil then
            local health, lastH, prevH, phase = string.match(rest, "^([%-%d%.]+):([^:]*):([^:]*):(.*)$")
            local st = {
                health = tonumber(health) or Bodengesundheit.cfg.startHealth,
                lastHarvest = (lastH ~= nil and lastH ~= "") and lastH or nil,
                prevHarvest = (prevH ~= nil and prevH ~= "") and prevH or nil,
                plannedFruit = nil,
                phase = (phase ~= nil and phase ~= "") and phase or "empty",
                lastDelta = 0,
            }
            Bodengesundheit.states[tonumber(id)] = st
        end
    end
end

-- Wird von FruchtfolgeAdvisor.saveSettings aufgerufen (Server-Kontext).
function Bodengesundheit.writeToXML(xml, base)
    local cfg = Bodengesundheit.cfg
    for _, k in ipairs(Bodengesundheit.CFG_BOOLS) do
        setXMLBool(xml, base .. "#" .. k, cfg[k] == true)
    end
    setXMLString(xml, base .. "#preset", cfg.preset)
    setXMLFloat(xml,  base .. "#startHealth", cfg.startHealth)
    setXMLFloat(xml,  base .. "#yieldMin", cfg.yieldMin)
    setXMLFloat(xml,  base .. "#yieldMax", cfg.yieldMax)
    setXMLFloat(xml,  base .. "#healthScale", cfg.healthScale)
    setXMLString(xml, base .. ".states", Bodengesundheit.serializeStates())
end

-- Wird von FruchtfolgeAdvisor.loadSettings aufgerufen (Server-Kontext).
function Bodengesundheit.readFromXML(xml, base)
    local cfg = Bodengesundheit.cfg
    local function b(path, def) local v = getXMLBool(xml, path)  if v ~= nil then return v end return def end
    local function f(path, def) local v = getXMLFloat(xml, path) if v ~= nil then return v end return def end

    for _, k in ipairs(Bodengesundheit.CFG_BOOLS) do
        cfg[k] = b(base .. "#" .. k, cfg[k])
    end
    local preset    = getXMLString(xml, base .. "#preset")
    if preset ~= nil and preset ~= "" then cfg.preset = preset end

    if cfg.preset ~= "custom" and Bodengesundheit.PRESETS[cfg.preset] ~= nil then
        Bodengesundheit.applyPreset(cfg.preset)
    else
        cfg.startHealth = f(base .. "#startHealth", cfg.startHealth)
        cfg.yieldMin    = f(base .. "#yieldMin", cfg.yieldMin)
        cfg.yieldMax    = f(base .. "#yieldMax", cfg.yieldMax)
        cfg.healthScale = f(base .. "#healthScale", cfg.healthScale)
    end

    local s = getXMLString(xml, base .. ".states")
    if s ~= nil then Bodengesundheit.deserializeStates(s) end

    Bodengesundheit.displayYieldMin = cfg.yieldMin
    Bodengesundheit.displayYieldMax = cfg.yieldMax
end

-- =====================================================================================
-- HUD (wird von FruchtfolgeAdvisor:draw aufgerufen)
-- =====================================================================================
-- Lokale Farm-ID (fuer "eigenes Feld"). Nutzt die zentrale Kette des Advisors.
local function localFarmId()
    if FieldAnalyzer ~= nil and FieldAnalyzer.getLocalFarmId ~= nil then
        local id = FieldAnalyzer.getLocalFarmId()
        if type(id) == "number" then return id end
    end
    if g_localPlayer ~= nil and type(g_localPlayer.farmId) == "number" then return g_localPlayer.farmId end
    return 1
end

-- Trend-Pfeil aus der letzten Aenderung (Aussaat/Vorbelegung):
-- hoch = Boden verbessert sich, runter = verschlechtert sich, "" = neutral.
-- UTF-8-Bytes (Lua 5.1 kennt kein \u): U+2191 = 226,134,145 / U+2193 = 226,134,147.
Bodengesundheit.ARROW_UP   = string.char(226, 134, 145)
Bodengesundheit.ARROW_DOWN = string.char(226, 134, 147)
function Bodengesundheit.trendArrow(st)
    if st == nil or st.lastDelta == nil or st.lastDelta == 0 then return "" end
    if st.lastDelta > 0 then return Bodengesundheit.ARROW_UP end
    return Bodengesundheit.ARROW_DOWN
end

function Bodengesundheit.healthLabel(h)
    local key, fallback
    if h >= 90 then key, fallback = "fa_health_verygood", "Sehr gut"
    elseif h >= 75 then key, fallback = "fa_health_good", "Gut"
    elseif h >= 55 then key, fallback = "fa_health_mid", "Mittel"
    elseif h >= 35 then key, fallback = "fa_health_weak", "Schwach"
    else key, fallback = "fa_health_exhausted", "Erschoepft" end
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback
end

-- Die fruehere HUD-Einblendung (Bodengesundheit auf eigenem Feld) ist
-- entfernt: die Bodengesundheit steht nur in der Betriebsuebersicht (Spalte
-- BODENWERTE im Bereich Felder). cfg.hudEnabled bleibt nur fuer alte Spielstaende
-- und das Sync-Format erhalten und hat keine Wirkung.

-- =====================================================================================
-- Spiel-Hooks (Aussaat -> Bewertung, Ernte -> Ertrag skalieren). Nur Server rechnet.
-- =====================================================================================
function Bodengesundheit.installHooks()
    if Bodengesundheit.hooksInstalled then return end
    Bodengesundheit.hooksInstalled = true

    -- ERNTE: Ertrag skalieren + Historie merken
    if Combine ~= nil and Combine.addCutterArea ~= nil then
        Combine.addCutterArea = Utils.overwrittenFunction(Combine.addCutterArea,
            function(self, superFunc, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)
                local cfg = Bodengesundheit.cfg
                if g_server ~= nil and area ~= nil and area > 0 and liters ~= nil and liters > 0 then
                    local x, z = Bodengesundheit.getVehicleXZ(self)
                    local farmlandId = Bodengesundheit.getFarmlandId(x, z)
                    if farmlandId ~= nil then
                        if cfg.enabled then
                            local st = Bodengesundheit.getState(farmlandId)
                            if cfg.affectYield then
                                liters = liters * Bodengesundheit.healthToYieldFactor(st.health)
                            end
                            Bodengesundheit.onHarvest(farmlandId, inputFruitType)
                        end
                        -- Feldkonto zaehlt mit, auch wenn die Bodengesundheit
                        -- abgeschaltet ist: die Ernte gehoert zur Rechnung.
                        -- Gebucht wird der Wert NACH dem Ertragsfaktor, also
                        -- das, was wirklich im Tank landet.
                        if FieldLedger ~= nil and FieldLedger.bucheErnte ~= nil then
                            FieldLedger.bucheErnte(farmlandId, inputFruitType, liters, area)
                        end
                    end
                end
                return superFunc(self, area, liters, inputFruitType, outputFillType, strawRatio, farmId, cutterLoad)
            end)
        Bodengesundheit.log("Hook installiert: Combine.addCutterArea")
    else
        Bodengesundheit.log("WARNUNG: Combine.addCutterArea nicht gefunden - kein Ertragseffekt.")
    end

    -- AUSSAAT: Fruchtfolge bewerten
    local function bewerteAussaat(self, changedArea)
        if g_server == nil then return end
        if changedArea == nil or changedArea <= 0 then return end

        local spec = self.spec_sowingMachine
        if spec == nil or spec.workAreaParameters == nil then return end
        local fruit = spec.workAreaParameters.seedsFruitType
        if fruit == nil then return end

        local x, z = Bodengesundheit.getVehicleXZ(self)
        local farmlandId = Bodengesundheit.getFarmlandId(x, z)
        if farmlandId == nil then return end

        if Bodengesundheit.cfg.enabled then
            Bodengesundheit.onSow(farmlandId, fruit)
        end
        -- Saatgutmenge fuers Feldkonto: der Maschinenfaktor gehoert dazu,
        -- das Spiel bucht damit ebenfalls ab.
        if FieldLedger ~= nil and FieldLedger.bucheSaat ~= nil then
            FieldLedger.bucheSaat(farmlandId, fruit, changedArea,
                spec.seedUsageScale, spec.seedFillType)
        end
    end

    local sowHook = function(self, superFunc, workArea, dt)
        local changedArea, totalArea = superFunc(self, workArea, dt)
        bewerteAussaat(self, changedArea)
        return changedArea, totalArea
    end

    -- Die Duenger-Saemaschine ist selbst schon ein Overwrite (registerOverwrittenFunction),
    -- ihre Funktion traegt deshalb einen eigenen superFunc als ERSTEN Parameter. Der muss
    -- durchgereicht werden, sonst landet er in workArea und dt faellt weg - und dt braucht
    -- sie fuer updateFarmStats("sprayedTime").
    local sowHookFert = function(self, superFunc, innerSuperFunc, workArea, dt)
        local changedArea, totalArea = superFunc(self, innerSuperFunc, workArea, dt)
        bewerteAussaat(self, changedArea)
        return changedArea, totalArea
    end

    if SowingMachine ~= nil and SowingMachine.processSowingMachineArea ~= nil then
        SowingMachine.processSowingMachineArea = Utils.overwrittenFunction(SowingMachine.processSowingMachineArea, sowHook)
        Bodengesundheit.log("Hook installiert: SowingMachine.processSowingMachineArea")
    else
        Bodengesundheit.log("WARNUNG: SowingMachine.processSowingMachineArea nicht gefunden - keine Fruchtfolge-Bewertung.")
    end

    -- SPRITZE: Duenger, Kalk, Guelle, Herbizid fuers Feldkonto. Angehaengt an
    -- onEndWorkAreaProcessing, weil das Spiel GENAU dort abbucht
    -- (Sprayer.lua:1331, nur wenn workAreaParameters.isActive) - die Menge in
    -- usage steht da schon fest. Ein EventListener vertraegt den Hook auch
    -- spaet, er sitzt hier nur mit den anderen zusammen.
    if FieldLedger ~= nil and Sprayer ~= nil and Sprayer.onEndWorkAreaProcessing ~= nil then
        Sprayer.onEndWorkAreaProcessing = Utils.appendedFunction(
            Sprayer.onEndWorkAreaProcessing,
            function(self)
                if g_server == nil then return end
                local spec = self.spec_sprayer
                if spec == nil or spec.workAreaParameters == nil then return end
                local p = spec.workAreaParameters
                if p.isActive ~= true then return end
                local liter = tonumber(p.usage) or 0
                if liter <= 0 then return end

                local x, z = Bodengesundheit.getVehicleXZ(self)
                local farmlandId = Bodengesundheit.getFarmlandId(x, z)
                if farmlandId ~= nil then
                    FieldLedger.bucheSpray(farmlandId, p.sprayFillType, liter)
                end
            end)
        Bodengesundheit.log("Hook installiert: Sprayer.onEndWorkAreaProcessing (Feldkonto)")
    end

    -- Eigener Hook noetig: FertilizingSowingMachine:processSowingMachineArea ruft ihren
    -- superFunc nie auf, sondern rechnet selbst - ueber die Saemaschinen-Kette kaeme bei
    -- einer Duenger-Saemaschine sonst gar nichts an.
    if FertilizingSowingMachine ~= nil and FertilizingSowingMachine.processSowingMachineArea ~= nil then
        FertilizingSowingMachine.processSowingMachineArea =
            Utils.overwrittenFunction(FertilizingSowingMachine.processSowingMachineArea, sowHookFert)
        Bodengesundheit.log("Hook installiert: FertilizingSowingMachine.processSowingMachineArea")
    end
end

-- Startwerte einmalig aus der bereits bekannten Fruchtfolge jedes Feldes vorbelegen,
-- damit die Werte nicht ueberall auf 80 % stehen, sondern die reale Rotation spiegeln.
-- Nur Server, nur Felder ohne bestehenden Zustand (bereits getrackte bleiben unangetastet).
function Bodengesundheit.seedFromFields()
    if Bodengesundheit.seeded then return end
    if g_server == nil then return end
    if g_fieldManager == nil or g_fieldManager.getFields == nil then return end
    local fields = g_fieldManager:getFields()
    if fields == nil then return end

    local scale = Bodengesundheit.cfg.healthScale or 0.5
    local n = 0
    local existing   = 0
    local fieldCount = 0
    for _, field in pairs(fields) do
        if type(field) == "table" then
            fieldCount = fieldCount + 1
            local fx, fz = nil, nil
            if field.getCenterOfFieldWorldPosition ~= nil then
                fx, fz = field:getCenterOfFieldWorldPosition()
            end
            if fx == nil and field.posX ~= nil then fx, fz = field.posX, field.posZ end
            local farmlandId = Bodengesundheit.getFarmlandId(fx, fz)

            if farmlandId ~= nil and Bodengesundheit.states[farmlandId] ~= nil then
                existing = existing + 1
            end
            if farmlandId ~= nil and Bodengesundheit.states[farmlandId] == nil then
                local cur, prev = nil, nil
                if FieldAnalyzer ~= nil then
                    if FieldAnalyzer.getCurrentFruit ~= nil then cur = FieldAnalyzer.getCurrentFruit(field) end
                    if FieldAnalyzer.getPreviousFruit ~= nil then prev = FieldAnalyzer.getPreviousFruit(field) end
                end

                local st = Bodengesundheit.getState(farmlandId)   -- legt Default (startHealth) an
                if cur ~= nil then
                    local delta = 0
                    if prev ~= nil and CropRotationData ~= nil and CropRotationData.getPFBonus ~= nil then
                        -- Vorfrucht bekannt: echte Rotationsbewertung
                        delta = CropRotationData.getPFBonus(prev, cur, nil) * scale
                    else
                        -- keine Vorfrucht: Heuristik nach aktuell wachsender Frucht
                        delta = Bodengesundheit.CROP_SOIL_SEED[cur] or 0
                    end
                    st.health = clamp(st.health + delta, 0, 100)
                    st.lastHarvest  = prev     -- Vorfrucht = bisherige "Ernte"
                    st.plannedFruit = cur      -- aktuell wachsende Frucht
                    st.phase = "growing"
                    st.lastDelta = delta
                elseif prev ~= nil then
                    st.lastHarvest = prev
                    st.phase = "harvested"
                end
                n = n + 1
            end
        end
    end

    -- Felder noch nicht geladen (Dedi: fieldManager fuellt sich erst spaeter)?
    -- Dann NICHT als erledigt markieren — naechster Versuch im update-Zyklus,
    -- sonst waere die Erst-Vorbelegung dauerhaft verpasst.
    if fieldCount == 0 then
        return
    end

    Bodengesundheit.seeded = true
    Bodengesundheit.log(string.format(
        "Startwerte: %d Felder neu vorbelegt, %d mit gespeicherten Werten uebernommen.",
        n, existing))
    -- Clients den Vollstand schicken
    if BodengesundheitSyncEvent ~= nil then
        g_server:broadcastEvent(BodengesundheitSyncEvent.new(
            Bodengesundheit.buildFullEntries(), Bodengesundheit.cfg.yieldMin, Bodengesundheit.cfg.yieldMax))
    end
end

-- Wird von FruchtfolgeAdvisor:loadMap aufgerufen.
function Bodengesundheit.onLoadMap()
    if not Bodengesundheit.hooksInstalled then
        Bodengesundheit.log("WARNUNG: Hooks wurden nicht installiert - Aussaat und Ernte wirken nicht auf die Bodengesundheit.")
    end
    -- WICHTIG: Der Sync-Request wird NICHT hier gesendet. Beim Laden ist die
    -- Netzwerk-Event-Registrierung zwischen Server/Client noch nicht fertig
    -- ("Invalid event id"). Der Client fordert den Zustand stattdessen beim
    -- Oeffnen des Dialogs an (Bodengesundheit.requestSync).
end

-- Reiner MP-Client fordert den kompletten Bodengesundheits-Zustand an.
-- Erst aufrufen, wenn das Netzwerk sicher steht (z. B. beim Dialog-Oeffnen).
function Bodengesundheit.requestSync()
    if g_server ~= nil then return end            -- Server/SP hat die Daten selbst
    if g_dedicatedServerInfo ~= nil then return end
    if g_client == nil or g_client.getServerConnection == nil then return end
    local conn = g_client:getServerConnection()
    if conn ~= nil and BodengesundheitRequestEvent ~= nil then
        conn:sendEvent(BodengesundheitRequestEvent.new())
    end
end

-- Zeitpunkt der Hooks: addCutterArea und processSowingMachineArea sind ueber
-- SpecializationUtil.registerFunction bzw. registerOverwrittenFunction an den Fahrzeugtyp
-- gebunden. validateTypes friert den Wert ein (objectType.functions[name] = func), beim
-- Fahrzeugladen wird genau dieser Wert auf die Instanz kopiert. Aus loadMap heraus - rund
-- 20 Sekunden spaeter - ersetzt man nur noch die Klassentabelle, die niemand mehr liest.
-- Deshalb haengt die Installation vor validateTypes.
if TypeManager ~= nil and TypeManager.validateTypes ~= nil then
    -- validateTypes laeuft fuer mehrere Typ-Manager; welcher zuerst drankommt, ist egal,
    -- weil die Hooks an den Klassen haengen. Gegen mehrfaches Einhaengen schuetzt
    -- hooksInstalled.
    TypeManager.validateTypes = Utils.prependedFunction(TypeManager.validateTypes,
        function()
            Bodengesundheit.installHooks()
        end)
else
    Bodengesundheit.log("WARNUNG: TypeManager.validateTypes nicht gefunden - Hooks koennen nicht gesetzt werden.")
end
