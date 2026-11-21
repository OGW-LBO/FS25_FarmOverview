-- TaskAnalyzer.lua
-- Aufgabenzettel: leitet aus dem Zustand des Hofes ab, was jetzt zu tun ist.
--
-- Zwei Datenquellen:
--   1. der Analyse-Cache der Betriebsuebersicht (FruchtfolgeAdvisor.cache):
--      Reichweiten, Staelle, Produktionen, Empfehlungen, Markt
--   2. eigene Zugriffe auf Spielobjekte, alle gegen gameSource verifiziert:
--      FieldState:update(x, z)            (FieldManager.lua:333)
--        -> fruitTypeIndex, growthState, weedState, sprayLevel, limeLevel,
--           rollerLevel, plowLevel, groundType
--      placeable:getConditionInfos()      (PlaceableHusbandry*.lua)
--        -> Wasser, Stroh, Mist, Guelle, Milch, Paletten mit ratio/invertedBar
--      placeable:getTotalFood/getFoodCapacity (PlaceableHusbandryFood.lua:441)
--      spec_silo.storages -> Storage.fillLevels/capacity/capacities (Storage.lua)
--      ProductionPoint.storage:getCapacity + outputFillTypeIdsDirectSell/AutoDeliver
--      Wearable:getDamageAmount (0..1), Motorized:getConsumerFillUnitIndex +
--      FillUnit:getFillUnitFillLevelPercentage
--
-- Alles wird beim Oeffnen berechnet, lokal auf dem Rechner des Spielers - wie
-- der Rest der Betriebsuebersicht. Auf Mehrspieler-Clients sind Terrain,
-- Lager und Fahrzeugwerte synchron, deshalb stimmen die Ergebnisse dort auch.
-- Nur der Bearbeitungsstatus (uebernommen) kommt vom Server
-- (TaskState.lua).
--
-- Eine Aufgabe:
--   { key, prio (1 dringend, 2 bald, 3 Hinweis), cat, text, value, detail }
-- key ist stabil ueber Oeffnen und Neustart hinweg (Farm + Art + Objekt), damit
-- der Status an der richtigen Aufgabe haengt.

TaskAnalyzer = {}

TaskAnalyzer.PRIO_URGENT = 1
TaskAnalyzer.PRIO_SOON   = 2
TaskAnalyzer.PRIO_INFO   = 3

-- Schwellen
TaskAnalyzer.SAMPLE_SHARE      = 0.4   -- Anteil der Messpunkte, ab dem eine Arbeit ERSCHEINT
-- Anteil, ab dem eine schon gelistete Arbeit STEHEN BLEIBT. Niedriger, weil
-- angefangene Arbeit nicht verschwinden darf: Wer ein Feld zur Haelfte
-- gegrubbert hat, hat drei von fuenf Messpunkten erledigt - mit der
-- Erscheinungs-Schwelle von 40 % fiel die Aufgabe genau dann aus der Liste,
-- obwohl die halbe Flaeche noch offen war (gemeldet 06.10.2026).
-- 0,2 = mindestens ein Messpunkt von fuenf.
TaskAnalyzer.SAMPLE_REST       = 0.2
-- Precision Farming, Duengen: Anteil des Durchschnittsziels, unter dem ein
-- echter Mangel vorliegt. 0,5 = "halb so viel Stickstoff wie im Schnitt
-- gebraucht wird" - das ist ein unduengtes Feld, kein knapp gehaltenes.
TaskAnalyzer.N_MANGEL_ANTEIL   = 0.5
TaskAnalyzer.FILL_LOW          = 0.15  -- Wasser/Stroh/Futter im Stall
TaskAnalyzer.FILL_HIGH         = 0.85  -- Mist/Guelle/Milch/Paletten im Stall
TaskAnalyzer.FILL_FULL         = 0.98
TaskAnalyzer.SILO_HIGH         = 0.90
TaskAnalyzer.OUTPUT_HIGH       = 0.90
TaskAnalyzer.DAMAGE_SOON       = 0.60
TaskAnalyzer.DAMAGE_URGENT     = 0.80
TaskAnalyzer.FUEL_SOON         = 0.20
TaskAnalyzer.FUEL_URGENT       = 0.08
TaskAnalyzer.MARKET_RATIO      = 1.10
TaskAnalyzer.PRODUCTIVITY_LOW  = 0.55

TaskAnalyzer.tasks = {}

-- Reihenfolge der Kategorien innerhalb einer Prioritaet
local CAT_ORDER = { field = 1, animal = 2, production = 3, storage = 4, vehicle = 5, plan = 6, market = 7 }

local function L(key, fallback)
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.L ~= nil then
        return FruchtfolgeAdvisor.L(key, fallback)
    end
    return fallback or key
end

-- Text mit Platzhaltern. Die Vorlagen stammen aus der modDesc und haben genau
-- so viele Platzhalter, wie hier Werte kommen.
local function F(key, fallback, ...)
    return string.format(L(key, fallback), ...)
end

local function fillName(key)
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.fillName ~= nil then
        return FruchtfolgeAdvisor.fillName(key)
    end
    return tostring(key)
end

local function kurz(s, n)
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.truncate ~= nil then
        return FruchtfolgeAdvisor.truncate(s, n)
    end
    return tostring(s or "")
end

local function farmIdLokal()
    if FieldAnalyzer ~= nil and FieldAnalyzer.getLocalFarmId ~= nil then
        return FieldAnalyzer.getLocalFarmId()
    end
    return 1
end

local function missionInfo()
    if g_currentMission ~= nil then
        return g_currentMission.missionInfo
    end
    return nil
end

-- Precision Farming ersetzt Kalk und Duengung durch eigene Karten (pH, N).
-- Dann sagen limeLevel/sprayLevel des Grundspiels nichts Verlaessliches, und
-- diese beiden Aufgaben entfallen.
function TaskAnalyzer.isPrecisionFarmingActive()
    if g_precisionFarming ~= nil then
        return true
    end
    local env = _G["FS25_precisionFarming"] or _G["pdlc_precisionFarming"]
    return env ~= nil and env.g_precisionFarming ~= nil
end

local function besitzerVon(obj)
    if obj == nil then
        return nil
    end
    if obj.getOwnerFarmId ~= nil then
        return obj:getOwnerFarmId()
    end
    return obj.ownerFarmId
end

local function placeableName(p)
    if p ~= nil and p.getName ~= nil then
        local n = p:getName()
        if type(n) == "string" and n ~= "" then
            return n
        end
    end
    return "?"
end

local function objektSchluessel(obj)
    if obj ~= nil and obj.getUniqueId ~= nil then
        local u = obj:getUniqueId()
        if u ~= nil and u ~= "" then
            return tostring(u)
        end
    end
    if obj ~= nil and obj.id ~= nil then
        return tostring(obj.id)
    end
    return tostring(obj)
end

-- ── Sammeln ───────────────────────────────────────────────────
local sammlung = nil
local gesehen  = nil
local aktFarm  = 1

-- Arbeiten, die nicht jeder Betrieb macht (der Walz-Bonus ist vielen zu klein,
-- Kalken/Pfluegen/Duengen haengt am Spielstil). Je Art ein Schalter im
-- Einstellungsbereich; fehlt die Einstellung, gilt die Aufgabe als AN.
TaskAnalyzer.OPTIONALE_ARTEN = {
    weeds = "taskWeeds",
    roll  = "taskRoll",
    fert  = "taskFert",
    lime  = "taskLime",
    plow  = "taskPlow",
}

function TaskAnalyzer.istArtAn(art)
    local key = TaskAnalyzer.OPTIONALE_ARTEN[art]
    if key == nil then return true end
    if Bodengesundheit == nil or Bodengesundheit.cfg == nil then return true end
    -- MP-Client direkt nach dem Beitreten: die Serverwerte sind noch nicht da.
    -- Dann diese freiwilligen Arbeiten WEGLASSEN - sonst stand kurz Walzen in
    -- der Liste, obwohl es auf dem Server abgewaehlt ist. Sobald die
    -- Einstellungen eintreffen, erscheinen sie (falls dort AN).
    if g_server == nil and not Bodengesundheit.cfgEmpfangen then
        return false
    end
    return Bodengesundheit.cfg[key] ~= false
end

-- Arbeitsfolge eines Feldes, wie man es wirklich bearbeitet. Je Art eine
-- Nummer; ein Feld ist immer in genau einer Phase, deshalb reicht EINE Liste:
--   wachsend : Unkraut -> Walzen -> Duengen
--   reif     : Ernten (bzw. verwelkt)
--   Stoppel  : Haeckseln -> Kalken -> Duengen -> Pfluegen -> Bestellen
-- WICHTIG: Die Schritte werden bei jeder Auswertung NEU aus dem Feldzustand
-- abgeleitet, nie aus einer gespeicherten Folge. Wer einen Schritt
-- ueberspringt (direkt bestellen ohne zu pfluegen), hat ihn danach schlicht
-- nicht mehr in der Liste - und was trotzdem noch offen ist (z. B. Kalk),
-- bleibt stehen. Ein Schritt blockiert also keinen spaeteren.
-- Nach der Ernte wird GEGRUBBERT (Stoppelbearbeitung), damit das Feld
-- saefaehig ist; Haeckseln ist die freiwillige Arbeit fuer die Strohreste und
-- steht davor. Pfluegen ersetzt das Grubbern, deshalb steht es vorher und
-- unterdrueckt es (siehe unten).
TaskAnalyzer.SCHRITT_FOLGE = {
    harvest  = 1, withered = 1,
    weeds    = 2,
    roll     = 3,
    shred    = 4,
    plow     = 5,
    till     = 6,
    lime     = 7,
    fert     = 8,
    sow      = 9,
    soil     = 10,
}

-- Kurzname des Schritts fuer die Kopfzeile ("als Naechstes: kalken")
TaskAnalyzer.SCHRITT_NAMEN = {
    harvest  = { "fa_step_harvest",  "harvest" },
    withered = { "fa_step_withered", "withered" },
    weeds    = { "fa_step_weeds",    "weed control" },
    roll     = { "fa_step_roll",     "rolling" },
    shred    = { "fa_step_shred",    "mulch stubble" },
    till     = { "fa_step_till",     "cultivating" },
    lime     = { "fa_step_lime",     "liming" },
    fert     = { "fa_step_fert",     "fertilizing" },
    plow     = { "fa_step_plow",     "plowing" },
    sow      = { "fa_step_sow",      "sowing" },
    soil     = { "fa_step_soil",     "rest soil" },
}

function TaskAnalyzer.schrittName(art)
    local e = TaskAnalyzer.SCHRITT_NAMEN[art]
    if e == nil then return tostring(art) end
    return L(e[1], e[2])
end

-- Anteil der Messpunkte, auf die eine Pruefung zutrifft (0..1).
-- Steht bewusst HIER oben: faellig() unten braucht es, und eine local
-- function ist in Lua erst ab ihrer Definitionszeile sichtbar. Weiter unten
-- definiert war sie beim Aufruf nil -> "attempt to call a nil value"
-- (07.10.2026 im Spiel aufgetreten).
local function anteil(proben, pruefe)
    if #proben == 0 then
        return 0
    end
    local n = 0
    for _, s in ipairs(proben) do
        if pruefe(s) then
            n = n + 1
        end
    end
    return n / #proben
end

-- Schluessel der Aufgaben des LETZTEN Durchlaufs. Daran haengt die Hysterese:
-- was schon in der Liste stand, bleibt mit der niedrigeren Schwelle stehen.
local vorher = {}

-- War diese Arbeit im letzten Durchlauf schon gelistet?
local function warGelistet(art, objKey)
    return vorher[string.format("%d:%s:%s", aktFarm, art, tostring(objKey))] == true
end

-- Ist die Arbeit faellig? Erscheint ab SAMPLE_SHARE, bleibt ab SAMPLE_REST.
local function faellig(proben, pruefe, art, objKey)
    local wert = anteil(proben, pruefe)
    local schwelle = warGelistet(art, objKey)
        and TaskAnalyzer.SAMPLE_REST or TaskAnalyzer.SAMPLE_SHARE
    return wert >= schwelle
end

local function add(art, objKey, prio, cat, text, value, detail)
    if not TaskAnalyzer.istArtAn(art) then
        return
    end
    local key = string.format("%d:%s:%s", aktFarm, art, tostring(objKey))
    if gesehen[key] then
        return
    end
    gesehen[key] = true
    sammlung[#sammlung + 1] = {
        key    = key,
        prio   = prio,
        cat    = cat,
        art    = art,
        -- Feldnummer nur bei Feldarbeiten: daran haengt der Feldblock.
        feld   = (cat == "field") and tostring(objKey) or nil,
        folge  = TaskAnalyzer.SCHRITT_FOLGE[art] or 99,
        text   = text or "",
        value  = value or "",
        detail = detail or "",
    }
end

-- ═══════════════════════════════════════════════════════════════
--  FELDER
-- ═══════════════════════════════════════════════════════════════

-- Messpunkte: Beschriftungspunkt des Feldes (liegt immer im Feld,
-- MathUtil.getPolygonLabel in Field:load) plus vier Punkte auf halbem Weg zu
-- verteilten Eckpunkten. Ein einzelner Punkt verfehlt Teilflaechen - so zaehlt
-- eine Aufgabe erst, wenn ein nennenswerter Teil des Feldes betroffen ist.
local function messpunkte(field)
    local pts = {}
    local cx, cz = field.posX, field.posZ
    if (cx == nil or cz == nil) and field.getCenterOfFieldWorldPosition ~= nil then
        cx, cz = field:getCenterOfFieldWorldPosition()
    end
    if cx == nil or cz == nil then
        return pts
    end
    pts[1] = { cx, cz }
    local poly = field.polygonPoints
    if type(poly) == "table" and #poly >= 4 and getWorldTranslation ~= nil then
        local n = #poly
        for k = 0, 3 do
            local node = poly[math.floor(k * n / 4) + 1]
            if node ~= nil then
                local px, _, pz = getWorldTranslation(node)
                if px ~= nil and pz ~= nil then
                    pts[#pts + 1] = { cx + (px - cx) * 0.5, cz + (pz - cz) * 0.5 }
                end
            end
        end
    end
    return pts
end

local messZustand = nil

-- ── Precision Farming: Stickstoff ────────────────────────────────────────────
-- Mit PF entscheidet nicht die Spritzschicht des Spiels, ob gedueungt werden
-- muss, sondern der Stickstoffwert gegen den Bedarf der Frucht.
--
-- Alles unten ist aus PF selbst gelesen, nichts geraten:
--   * Kartenzugriff wie in precisionFarming/scripts/misc/AdditionalFieldBuyInfo.lua
--     (updateFieldSoilDistributionData): getBitVectorMapSize + getBitVectorMapPoint,
--     Weltkoordinate -> Pixel ueber g_currentMission.terrainSize.
--   * `nitrogenMap.fruitRequirements` liefert je Frucht `fruitTypeName` und
--     `averageTargetLevel` in DERSELBEN Stufenskala wie die Karte (faPF-Ausgabe
--     05.10.2026: WHEAT 35, MAIZE 34, GRASS 31, SOYBEAN 0).
--   * Zielwert 0 heisst "braucht keinen Stickstoff" (Leguminosen, Zwischenfruechte).
local pfStickstoffZiele = nil

local function stickstoffKarte()
    local pf = g_precisionFarming
    if pf == nil then
        local env = _G["FS25_precisionFarming"] or _G["pdlc_precisionFarming"]
        pf = env ~= nil and env.g_precisionFarming or nil
    end
    if pf == nil then return nil end
    return pf.nitrogenMap
end

-- Zielstufe je Fruchtname (GROSS), nil wenn die Frucht keinen Bedarf hat.
local function stickstoffZiel(cropName)
    if cropName == nil then return nil end
    if pfStickstoffZiele == nil then
        pfStickstoffZiele = {}
        local karte = stickstoffKarte()
        local liste = karte ~= nil and karte.fruitRequirements or nil
        if type(liste) == "table" then
            for _, eintrag in pairs(liste) do
                if type(eintrag) == "table" and type(eintrag.fruitTypeName) == "string" then
                    local ziel = tonumber(eintrag.averageTargetLevel)
                    if ziel ~= nil and ziel > 0 then
                        pfStickstoffZiele[string.upper(eintrag.fruitTypeName)] = ziel
                    end
                end
            end
        end
    end
    return pfStickstoffZiele[string.upper(cropName)]
end

-- Stickstoff-Stufe an einer Weltposition, oder nil.
local function stickstoffStufe(wx, wz)
    local karte = stickstoffKarte()
    if karte == nil or karte.bitVectorMap == nil then return nil end
    if getBitVectorMapSize == nil or getBitVectorMapPoint == nil then return nil end
    local ts = g_currentMission ~= nil and g_currentMission.terrainSize or nil
    if ts == nil then return nil end
    local sx, sy = getBitVectorMapSize(karte.bitVectorMap)
    if sx == nil or sx < 2 then return nil end
    local px = math.floor((wx + ts * 0.5) / ts * (sx - 1) + 0.5)
    local py = math.floor((wz + ts * 0.5) / ts * (sy - 1) + 0.5)
    px = math.max(0, math.min(sx - 1, px))
    py = math.max(0, math.min(sy - 1, py))
    return getBitVectorMapPoint(karte.bitVectorMap, px, py,
        karte.firstChannel or 0, karte.numChannels or 1)
end

-- Stickstoff in kg/ha (nur fuer die Anzeige).
local function stickstoffKg(stufe)
    local karte = stickstoffKarte()
    if karte == nil or stufe == nil then return nil end
    if type(karte.getNitrogenValueFromInternalValue) == "function" then
        return karte:getNitrogenValueFromInternalValue(stufe)
    end
    local proStufe = tonumber(karte.amountPerState)
    if proStufe ~= nil then return stufe * proStufe end
    return nil
end

local function feldProben(field)
    if FieldState == nil or FieldState.new == nil then
        return nil
    end
    if messZustand == nil then
        messZustand = FieldState.new()
    end
    local fs = messZustand
    if fs == nil or fs.update == nil then
        return nil
    end
    local keinBoden = 0
    if FieldGroundType ~= nil and FieldGroundType.NONE ~= nil then
        keinBoden = FieldGroundType.NONE
    end
    local out = {}
    for _, p in ipairs(messpunkte(field)) do
        fs:update(p[1], p[2])
        if fs.groundType ~= nil and fs.groundType ~= keinBoden then
            out[#out + 1] = {
                fruit  = fs.fruitTypeIndex or 0,
                growth = fs.growthState or 0,
                weed   = fs.weedState or 0,
                spray  = fs.sprayLevel or 0,
                lime   = fs.limeLevel or 0,
                roller = fs.rollerLevel or 0,
                plow   = fs.plowLevel or 0,
                shred  = fs.stubbleShredLevel or 0,
                boden  = fs.groundType,
                -- nur mit Precision Farming belegt, sonst nil
                stickstoff = stickstoffStufe(p[1], p[2]),
            }
        end
    end
    return out
end

-- Zustands-Pruefungen einer Frucht, EINMAL definiert: feldAufgaben und der
-- faFeld-Dump nutzen dieselben, damit die Diagnose nie etwas anderes sagt als
-- die Auswertung.
--
-- WICHTIG beim Stoppel-Test (06.10.2026 im Spiel gefunden): Nach der Ernte
-- steht auf dem Feld NICHT zwangslaeufig `cutState`. Hafer auf Bergisch Land
-- hat reif 6, verwelkt 7, Schnitt 9 - die Messpunkte zeigten aber 8. Mit der
-- starren Frage "Wachstum == Schnitt" griff deshalb KEIN Zweig, und das
-- abgeerntete Feld bekam gar keine Aufgabe, obwohl die Feldinfo des Spiels
-- "Abgeerntet" anzeigte. Richtig ist: alles JENSEITS der Erntereife, das nicht
-- verwelkt ist, gilt als abgeerntet.
function TaskAnalyzer.zustandsPruefer(desc)
    local fIdx    = desc.index
    local minH    = desc.minHarvestingGrowthState or 0
    local maxH    = desc.maxHarvestingGrowthState or 0
    local welk    = desc.witheredState
    local schnitt = desc.cutState or 0
    -- Hackfruechte haben zwei Reifestufen: ausgewachsen (Kraut steht noch,
    -- isPreparable) und erntereif (Kraut ab, isPrepared + isHarvestReady).
    -- Bei der Zuckerruebe liegt das Kraut-ab-Stadium auf Index 11, das
    -- ausgewachsene auf 8 - mit der Frage nach minHarvestingGrowthState allein
    -- galt eine reife Ruebe als "waechst noch" und bekam keine Ernte-Aufgabe
    -- (gemeldet 13.11.2026). Betroffen sind Kartoffel, Zuckerruebe, Zuckerrohr.
    local minP    = desc.minPreparingGrowthState or -1
    local maxP    = desc.maxPreparingGrowthState or -1
    local p = {}
    local function vorbereitbar(s)
        return minP > 0 and s.growth >= minP and s.growth <= maxP
    end
    function p.reif(s)
        if s.fruit ~= fIdx then return false end
        if minH > 0 and s.growth >= minH and s.growth <= maxH then return true end
        return vorbereitbar(s)
    end
    function p.verwelkt(s)
        return s.fruit == fIdx and welk ~= nil and s.growth == welk
    end
    function p.waechst(s)
        return s.fruit == fIdx and s.growth > 0 and (minH == 0 or s.growth < minH)
            and not vorbereitbar(s)
            and s.growth ~= schnitt and (welk == nil or s.growth ~= welk)
    end
    function p.abgeerntet(s)
        if s.fruit ~= fIdx or s.growth <= 0 then return false end
        if welk ~= nil and s.growth == welk then return false end
        if maxH > 0 and s.growth > maxH then return true end
        return schnitt > 0 and s.growth == schnitt
    end
    return p
end

-- Bodenzustaende, auf denen man saeen kann. Namen aus dem Spielquellcode
-- (FieldGroundType.CULTIVATED/PLOWED/SEEDBED/ROLLED_SEEDBED/SOWN/PLANTED,
-- belegt u. a. in FieldManager.lua und MapOverlayGenerator.lua). Fehlt eine
-- Konstante in einer Spielversion, wird sie einfach ausgelassen.
local saatbereitSet = nil
local function saatbereit(boden)
    if boden == nil then return true end
    if FieldGroundType == nil then return true end
    if saatbereitSet == nil then
        saatbereitSet = {}
        for _, name in ipairs({ "CULTIVATED", "PLOWED", "SEEDBED", "ROLLED_SEEDBED",
                "SOWN", "PLANTED", "RIDGE", "ROLLER_LINES" }) do
            local w = FieldGroundType[name]
            if w ~= nil then saatbereitSet[w] = true end
        end
    end
    return saatbereitSet[boden] == true
end

-- Haeufigste Frucht der Proben (0 = keine).
local function hauptFrucht(proben)
    local zaehler, beste, besteN = {}, 0, 0
    for _, s in ipairs(proben) do
        local f = s.fruit or 0
        if f ~= 0 and (FruitType == nil or f ~= FruitType.UNKNOWN) then
            zaehler[f] = (zaehler[f] or 0) + 1
            if zaehler[f] > besteN then
                beste, besteN = f, zaehler[f]
            end
        end
    end
    return beste
end

-- Unkraut-Zustaende, die ein Herbizid wirklich behandelt (Muster aus
-- WeedSpotSpray:onLoad; Ziel 0 = vorbeugendes Spritzen, zaehlt nicht).
local unkrautZustaende = nil
local function unkrautSet()
    if unkrautZustaende ~= nil then
        return unkrautZustaende
    end
    unkrautZustaende = {}
    local ws = g_currentMission ~= nil and g_currentMission.weedSystem or nil
    if ws ~= nil and ws.getHerbicideReplacements ~= nil then
        local data = ws:getHerbicideReplacements()
        if type(data) == "table" and type(data.weed) == "table" and type(data.weed.replacements) == "table" then
            for quelle, ziel in pairs(data.weed.replacements) do
                if ziel ~= 0 and quelle ~= 0 then
                    unkrautZustaende[quelle] = true
                end
            end
        end
    end
    return unkrautZustaende
end

local function feldAufgaben(cache)
    if cache == nil or cache.fields == nil then
        return
    end
    local mi      = missionInfo() or {}
    local pf      = TaskAnalyzer.isPrecisionFarmingActive()
    local fm      = g_fieldManager
    local maxSpray = (fm ~= nil and fm.sprayLevelMaxValue) or 0
    local maxLime  = (fm ~= nil and fm.limeLevelMaxValue) or 0
    local maxPlow  = (fm ~= nil and fm.plowLevelMaxValue) or 0
    -- Haeckselstufe: Der FieldManager fuehrt dafuer keinen Maximalwert, die
    -- Schicht gibt es aber (verifiziert: FieldDensityMap.STUBBLE_SHRED_LEVEL in
    -- MapOverlayGenerator.lua:341, Schalter Platform.gameplay.useStubbleShred).
    local maxShred = 0
    local fgs = g_currentMission ~= nil and g_currentMission.fieldGroundSystem or nil
    if fgs ~= nil and fgs.getMaxValue ~= nil and FieldDensityMap ~= nil
            and FieldDensityMap.STUBBLE_SHRED_LEVEL ~= nil
            and (Platform == nil or Platform.gameplay == nil
                or Platform.gameplay.useStubbleShred ~= false) then
        maxShred = fgs:getMaxValue(FieldDensityMap.STUBBLE_SHRED_LEVEL) or 0
    end
    local unkraut  = unkrautSet()
    local S = TaskAnalyzer.SAMPLE_SHARE
    local ws = g_currentMission ~= nil and g_currentMission.weedSystem or nil
    local unkrautAn = mi.weedsEnabled == true and ws ~= nil
        and (ws.getMapHasWeed == nil or ws:getMapHasWeed())

    for _, entry in ipairs(cache.fields) do
        local fi    = entry.fieldInfo
        local field = fi.field
        local nr    = tostring(fi.fieldId or "?")
        local ha    = string.format("%.1f ha", (fi.area or 0) / 10000)
        local proben = (field ~= nil) and feldProben(field) or nil

        if proben ~= nil and #proben > 0 then
            local fIdx  = hauptFrucht(proben)
            local desc  = nil
            if fIdx ~= 0 and g_fruitTypeManager ~= nil then
                desc = g_fruitTypeManager:getFruitTypeByIndex(fIdx)
            end
            local fruchtName = ""
            if desc ~= nil and desc.name ~= nil and CropRotationData ~= nil then
                fruchtName = CropRotationData.getCropName(string.upper(desc.name))
            end

            if desc ~= nil then
                local minH = desc.minHarvestingGrowthState or 0
                local maxH = desc.maxHarvestingGrowthState or 0
                local welk = desc.witheredState
                local schnitt = desc.cutState or 0

                -- Pruefungen zentral (siehe TaskAnalyzer.zustandsPruefer)
                local p = TaskAnalyzer.zustandsPruefer(desc)
                local reif, verwelkt, waechst, abgeerntet =
                    p.reif, p.verwelkt, p.waechst, p.abgeerntet

                if faellig(proben, reif, "harvest", nr) then
                    add("harvest", nr, TaskAnalyzer.PRIO_URGENT, "field",
                        F("fa_t_harvest", "Harvest field %s", nr), ha, fruchtName)
                elseif faellig(proben, verwelkt, "withered", nr) then
                    add("withered", nr, TaskAnalyzer.PRIO_URGENT, "field",
                        F("fa_t_withered", "Field %s withered", nr), ha, fruchtName)
                elseif anteil(proben, waechst) >= S then
                    if unkrautAn and faellig(proben, function(s)
                                return waechst(s) and unkraut[s.weed] == true
                            end, "weeds", nr) then
                        add("weeds", nr, TaskAnalyzer.PRIO_SOON, "field",
                            F("fa_t_weeds", "Treat weeds on field %s", nr), ha, fruchtName)
                    end
                    if desc.needsRolling ~= false and faellig(proben, function(s)
                                return waechst(s) and s.roller == 1
                            end, "roll", nr) then
                        add("roll", nr, TaskAnalyzer.PRIO_SOON, "field",
                            F("fa_t_roll", "Roll field %s", nr), ha, fruchtName)
                    end
                    -- Duengen: OHNE Precision Farming entscheidet die Spritzschicht,
                    -- MIT PF der Stickstoffwert gegen den Bedarf der Frucht.
                    if not pf then
                        if maxSpray > 0 and faellig(proben, function(s)
                                    return waechst(s) and s.spray < maxSpray
                                end, "fert", nr) then
                            add("fert", nr, TaskAnalyzer.PRIO_INFO, "field",
                                F("fa_t_fert", "Fertilize field %s", nr), ha, fruchtName)
                        end
                    else
                        local ziel = stickstoffZiel(desc.name)
                        if ziel ~= nil then
                            -- NUR der klare Mangel wird gemeldet.
                            -- Grund: `averageTargetLevel` ist der DURCHSCHNITT ueber
                            -- die ganze Wachstumszeit, nicht der Bedarf im aktuellen
                            -- Stadium, und PF skaliert das Ziel zusaetzlich mit dem
                            -- Ertragspotenzial des Bodens (soilMap: 0,8 bis 1,25).
                            -- Beides koennen wir je Stadium nicht nachrechnen - die
                            -- Funktionen dafuer sind nicht zugaenglich. Gegen das
                            -- volle Ziel gemessen meldete die Liste deshalb Felder,
                            -- auf denen genug Duenger lag (gemeldet 05.10.2026).
                            -- Mit MANGEL_ANTEIL faellt nur auf, was wirklich leer ist.
                            local schwelle = ziel * TaskAnalyzer.N_MANGEL_ANTEIL
                            local unten, summe, anzahl = 0, 0, 0
                            for _, s in ipairs(proben) do
                                if waechst(s) and s.stickstoff ~= nil then
                                    anzahl = anzahl + 1
                                    summe = summe + s.stickstoff
                                    if s.stickstoff < schwelle then unten = unten + 1 end
                                end
                            end
                            -- Hysterese wie bei den anderen Arbeiten: halb gestreut bleibt offen
                            local nSchwelle = warGelistet("fert", nr)
                                and TaskAnalyzer.SAMPLE_REST or S
                            if anzahl > 0 and (unten / anzahl) >= nSchwelle then
                                local kg = stickstoffKg(summe / anzahl)
                                local zielKg = stickstoffKg(ziel)
                                local wert = ha
                                if kg ~= nil and zielKg ~= nil then
                                    wert = string.format("%.0f/%.0f kg", kg, zielKg)
                                end
                                add("fert", nr, TaskAnalyzer.PRIO_SOON, "field",
                                    F("fa_t_fert", "Fertilize field %s", nr), wert, fruchtName)
                            end
                        end
                    end
                elseif anteil(proben, abgeerntet) >= S and desc.regrows ~= true then
                    -- Stoppel: erst haeckseln (falls noch Stroh steht), dann
                    -- die naechste Frucht bestellen. Der Haecksel-Zustand steht
                    -- in derselben Feldschicht wie Kalk und Pflug
                    -- (FieldState.stubbleShredLevel, Spielstand: stubbleShredLevel).
                    if maxShred > 0 and faellig(proben, function(s)
                                return abgeerntet(s) and s.shred == 0
                            end, "shred", nr) then
                        -- Kein Fruchtname: hier waere es die ABGEERNTETE Frucht,
                        -- waehrend Duengen und Bestellen die NAECHSTE nennen.
                        -- Im selben Feldblock standen so zwei Fruechte
                        -- untereinander ("Sonnenblumen" / "Winterweizen"), was
                        -- den Eindruck eines Widerspruchs machte.
                        add("shred", nr, TaskAnalyzer.PRIO_INFO, "field",
                            F("fa_t_shred", "Mulch stubble on field %s", nr), ha, "")
                    end
                    local top = entry.recommendations and entry.recommendations[1]
                    add("sow", nr, TaskAnalyzer.PRIO_SOON, "field",
                        F("fa_t_sow", "Sow field %s", nr), ha,
                        top ~= nil and (top.displayName or "") or "")
                end
            else
                -- Keine Frucht: bearbeitet oder brach -> bestellen
                local top = entry.recommendations and entry.recommendations[1]
                add("sow", nr, TaskAnalyzer.PRIO_SOON, "field",
                    F("fa_t_sow", "Sow field %s", nr), ha,
                    top ~= nil and (top.displayName or "") or "")
            end

            -- Duengen auf Stoppel oder Brache (nur mit Precision Farming).
            -- Oben haengt die Pruefung an einer WACHSENDEN Frucht; ein
            -- abgeerntetes Feld fiel damit durch, obwohl man dort vor der
            -- Aussaat duengt (Feld 66 am 05.10.2026: 0 bis 40 kg bei Ziel 105).
            -- Als Ziel gilt die naechste Frucht: geplante Aussaat, sonst die
            -- eigene Empfehlung.
            -- EINE Quelle fuer "die naechste Frucht": unsere Empfehlung. Vorher
            -- nahm das Duengen die im Spiel geplante Aussaat und das Bestellen
            -- die Empfehlung - im selben Block standen dann zwei verschiedene
            -- Fruechte.
            local waechstWas = false
            if desc ~= nil then
                if desc.regrows == true then
                    -- Wiese, Klee, Luzerne: frisch gemaeht steht der Bestand im
                    -- cutState und zaehlte dadurch als "da waechst nichts". Die
                    -- Folge waren Stoppelarbeiten auf der Wiese - gemeldet am
                    -- 03.11.2026 als "Feld 60/68: grubbern" nach dem Maehen.
                    -- Nachwachsendes kommt von selbst wieder, das Feld ist belegt.
                    waechstWas = true
                else
                    local fIdx = desc.index
                    for _, s in ipairs(proben) do
                        if s.fruit == fIdx and s.growth > 0
                                and s.growth ~= (desc.cutState or 0)
                                and (desc.witheredState == nil or s.growth ~= desc.witheredState) then
                            waechstWas = true
                            break
                        end
                    end
                end
            end
            if pf and not waechstWas then
                local top = entry.recommendations and entry.recommendations[1]
                local naechste = (top ~= nil) and top.crop or nil
                local ziel = stickstoffZiel(naechste)
                if ziel ~= nil then
                    local schwelle = ziel * TaskAnalyzer.N_MANGEL_ANTEIL
                    local unten, summe, anzahl = 0, 0, 0
                    for _, s in ipairs(proben) do
                        if s.stickstoff ~= nil then
                            anzahl = anzahl + 1
                            summe = summe + s.stickstoff
                            if s.stickstoff < schwelle then unten = unten + 1 end
                        end
                    end
                    -- Hysterese wie bei den anderen Arbeiten: halb gestreut bleibt offen
                            local nSchwelle = warGelistet("fert", nr)
                                and TaskAnalyzer.SAMPLE_REST or S
                            if anzahl > 0 and (unten / anzahl) >= nSchwelle then
                        local kg = stickstoffKg(summe / anzahl)
                        local zielKg = stickstoffKg(ziel)
                        local wert = ha
                        if kg ~= nil and zielKg ~= nil then
                            wert = string.format("%.0f/%.0f kg", kg, zielKg)
                        end
                        -- Keine Frucht im Detail: Sie steht beim LETZTEN Schritt
                        -- des Blocks (bestellen). Stand sie auch hier, las man
                        -- dieselbe Frucht zweimal untereinander - fuer die
                        -- Uebersicht reicht sie einmal, naemlich dort, wo sie
                        -- wirklich ausgebracht wird. Der Zielwert in der Spalte
                        -- WERT ist ohnehin der dieser Frucht.
                        add("fert", nr, TaskAnalyzer.PRIO_INFO, "field",
                            F("fa_t_fert", "Fertilize field %s", nr), wert, "")
                    end
                end
            end

            -- Bodenpflege gilt unabhaengig von der Frucht.
            -- Kalk wird AUCH mit Precision Farming geprueft: die Kalkschicht des
            -- Spiels wird beim Kalken weiter gesetzt, und der Spielstand fuehrt
            -- limeRequired. Vorher fiel die Aufgabe mit PF komplett aus - auf
            -- Feld 3 stand limeLevel=0 und trotzdem kam kein Hinweis.
            -- Der Duenger bleibt mit PF ausgespart: dort entscheidet die
            -- Stickstoffkarte, nicht die Spritzschicht.
            if mi.limeRequired == true and maxLime > 0
                    and faellig(proben, function(s) return s.lime == 0 end, "lime", nr) then
                add("lime", nr, TaskAnalyzer.PRIO_SOON, "field",
                    F("fa_t_lime", "Lime field %s", nr), ha, "")
            end
            -- Pfluegen: nach der Ernte und auf der Brache. Frueher galt es NUR
            -- fuer Felder ganz ohne Frucht (desc == nil) - ein frisch
            -- abgeerntetes Feld hat aber sehr wohl eine Fruchtart, die Stoppel
            -- steht nur jenseits von maxHarvestingGrowthState. Dadurch kam dort
            -- immer nur "Grubbern", nie "Pfluegen" (gemeldet 20.10.2026).
            -- Wiesen und anderes Nachwachsendes bleiben aussen vor: nach dem
            -- Maehen wird nicht gepfluegt.
            local frei = (desc == nil)
            local stoppel = false
            if desc ~= nil and desc.regrows ~= true then
                local pz = TaskAnalyzer.zustandsPruefer(desc)
                stoppel = anteil(proben, pz.abgeerntet) >= S
            end
            local pflugFaellig = (mi.plowingRequiredEnabled == true and maxPlow > 0
                and (frei or stoppel)
                and faellig(proben, function(s) return s.plow == 0 end, "plow", nr))
            if pflugFaellig then
                add("plow", nr, TaskAnalyzer.PRIO_INFO, "field",
                    F("fa_t_plow", "Plow field %s", nr), ha, "")
            end

            -- Grubbern (Stoppelbearbeitung): Nach der Ernte muss das Feld
            -- bearbeitet werden, damit man saeen kann - das ist der Schritt,
            -- der in der Praxis auf die Ernte folgt, nicht das Haeckseln.
            -- Erkannt am Bodenzustand (siehe saatbereit), nicht an einer
            -- eigenen Buchhaltung. Ist Pfluegen faellig, entfaellt es: pfluegen
            -- macht das Feld ebenfalls saefaehig.
            if not pflugFaellig and not waechstWas
                    and faellig(proben, function(s) return not saatbereit(s.boden) end, "till", nr) then
                add("till", nr, TaskAnalyzer.PRIO_SOON, "field",
                    F("fa_t_till", "Cultivate field %s", nr), ha, "")
            end
        end

        -- Bodengesundheit schwach: Fruchtwechsel/Leguminose einplanen
        if Bodengesundheit ~= nil and Bodengesundheit.cfg ~= nil and Bodengesundheit.cfg.enabled
                and Bodengesundheit.getHealthForField ~= nil and field ~= nil then
            local h = Bodengesundheit.getHealthForField(field, fi.fieldId)
            if type(h) == "number" and h < 35 then
                add("soil", nr, TaskAnalyzer.PRIO_INFO, "field",
                    F("fa_t_soil", "Rest soil on field %s", nr),
                    string.format("%d%%", math.floor(h + 0.5)),
                    L("fa_d_soil", "legume or grass next"))
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  TIERE
-- ═══════════════════════════════════════════════════════════════

local function tierAufgaben(cache, farmId)
    -- 1. Aus dem Cache: volle/ueberalterte Staelle, geringe Leistung
    local an = (cache ~= nil and cache.animals) or {}
    for i, hub in ipairs(an.husbandries or {}) do
        local wo = kurz(hub.name or tostring(hub.animalType or "?"), 26)
        local objKey = tostring(hub.name or "") .. "#" .. tostring(i)
        -- Eine Lage je Stall statt mehrerer Zeilen nebeneinander: voller Stall
        -- UND Bestpreis ist genau der Moment zum Abverkaufen und gehoert nach
        -- oben, nicht als zwei halbe Hinweise untereinander.
        local lage = AnimalAnalyzer ~= nil and AnimalAnalyzer.stallLage ~= nil
            and AnimalAnalyzer.stallLage(hub) or nil
        local geld = (FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.fmtMoney)
            or function() return "" end

        if lage ~= nil and lage.art == "verkauf" then
            local grund = FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.grundText ~= nil
                and FruchtfolgeAdvisor.grundText(lage.grund, hub.animalType) or ""
            add("sellplan", objKey, lage.dringend and TaskAnalyzer.PRIO_URGENT or TaskAnalyzer.PRIO_SOON, "animal",
                F("fa_t_sellplan", "Sell animals: %s", wo),
                string.format("%d %s", lage.num or 0, L("fa_unit_animals", "animals")),
                grund .. ", " .. geld(lage.wert or 0))

        elseif lage ~= nil and lage.art == "nachkauf" then
            local k = (lage.liste or {})[1] or {}
            local name = AnimalAnalyzer.subtypName ~= nil and AnimalAnalyzer.subtypName(k.idx) or nil
            local grund = FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.nachkaufText ~= nil
                and FruchtfolgeAdvisor.nachkaufText(k.grund, hub.animalType) or ""
            add("buyanimals", objKey, TaskAnalyzer.PRIO_INFO, "animal",
                F("fa_t_buyanimals", "Buy animals: %s", wo),
                string.format("%d x %s", k.num or 0, tostring(name or "?")),
                grund)

        elseif lage ~= nil and lage.art == "voll" then
            add("barnfull", objKey, TaskAnalyzer.PRIO_SOON, "animal",
                F("fa_t_barnfull", "Barn full: %s", wo),
                string.format("%d/%d", hub.count or 0, hub.maxCount or 0),
                L("fa_d_allneeded", "all animals needed, expand the barn"))

        elseif lage ~= nil and lage.art == "quali" then
            add("productivity", objKey, TaskAnalyzer.PRIO_INFO, "animal",
                F("fa_t_productivity", "Low productivity: %s", wo),
                string.format("%.0f%%", (lage.wert or 0) * 100),
                L("fa_d_feedbetter", "feed better - selling does not help"))
        end
    end

    -- 2. Stallzustand direkt vom Placeable: Futter, Wasser, Stroh, Ausgaenge
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps == nil or type(ps.placeables) ~= "table" then
        return
    end
    for _, p in pairs(ps.placeables) do
        if p ~= nil and besitzerVon(p) == farmId and p.getConditionInfos ~= nil then
            local tiere = 0
            if p.getNumOfAnimals ~= nil then
                tiere = p:getNumOfAnimals() or 0
            end
            local name   = kurz(placeableName(p), 26)
            local objKey = objektSchluessel(p)

            -- Futter im Trog (Summe aller Gruppen)
            if tiere > 0 and p.getTotalFood ~= nil and p.getFoodCapacity ~= nil then
                local kap = p:getFoodCapacity() or 0
                if kap > 0 then
                    local r = (p:getTotalFood() or 0) / kap
                    if r < TaskAnalyzer.FILL_LOW then
                        add("food", objKey, TaskAnalyzer.PRIO_URGENT, "animal",
                            F("fa_t_food", "Refill feed: %s", name),
                            string.format("%.0f%%", r * 100), "")
                    end
                end
            end

            for idx, info in ipairs(p:getConditionInfos() or {}) do
                -- Die Produktivitaets-Zeile (valueText) steht oben schon aus dem Cache.
                if type(info) == "table" and info.valueText == nil and info.disabled ~= true
                        and type(info.ratio) == "number" then
                    local titel = tostring(info.title or "?")
                    local teilKey = objKey .. "#" .. titel
                    local prozent = string.format("%.0f%%", info.ratio * 100)
                    if info.invertedBar == true then
                        -- Ausgang (Mist, Guelle, Milch, Paletten): voll ist schlecht
                        if info.ratio >= TaskAnalyzer.FILL_HIGH then
                            local prio = (info.ratio >= TaskAnalyzer.FILL_FULL)
                                and TaskAnalyzer.PRIO_URGENT or TaskAnalyzer.PRIO_SOON
                            add("out", teilKey, prio, "animal",
                                F("fa_t_collect", "Collect %s: %s", titel, name), prozent, "")
                        end
                    elseif tiere > 0 and info.ratio < TaskAnalyzer.FILL_LOW then
                        -- Eingang (Wasser, Stroh): leer ist schlecht
                        add("in", teilKey, TaskAnalyzer.PRIO_URGENT, "animal",
                            F("fa_t_refill", "Refill %s: %s", titel, name), prozent, "")
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  LAGER, PRODUKTION, MARKT, ANBAUPLANUNG
-- ═══════════════════════════════════════════════════════════════

-- Waren, die man am Hof kostenlos zapft und die deshalb NIE im Lager liegen.
-- Ohne diese Ausnahme stand Wasser dauerhaft mit "0.0 Mo" als dringend in der
-- Aufgabenliste, obwohl nichts fehlt. Einen wirklich leeren Wassertank meldet
-- weiterhin die Aufgabe "Produktion: Eingang leer".
local SELBSTVERSORGT = {
    WATER = true,
}

-- Zweite Rueckgabe: nur der Anteil, den PRODUKTIONEN brauchen. Der ist nicht
-- ersetzbar - ein Rezept verlangt genau diesen Fuelltyp. Tiere nehmen dagegen
-- innerhalb ihrer Futtergruppe auch Alternativen.
local function monatsBedarf(an)
    local pNeeds = an.productionNeeds or {}
    local summe, nurProd = {}, {}
    for k, v in pairs(an.feedNeeds or {}) do summe[k] = (summe[k] or 0) + v end
    for k, v in pairs(an.beddingNeeds or {}) do summe[k] = (summe[k] or 0) + v end
    for k, v in pairs(pNeeds) do
        summe[k]   = (summe[k] or 0) + v
        nurProd[k] = (nurProd[k] or 0) + v
    end
    return summe, nurProd
end

-- Ab wie vielen Monaten Vorrat gilt ein Erzeugnis als "satt". Die Eingaenge der
-- erzeugenden Produktion zaehlen dann nicht mehr als Bedarf.
TaskAnalyzer.PRODUKT_SATT_MONATE = 6

-- Eingaenge, die man ignorieren darf: die von Produktionen, deren Erzeugnis auf
-- dem Hof gebraucht wird UND fuer viele Monate reicht.
-- Beispiel Bergisch Land (05.10.2026): Die Mischfutteranlage verbraucht bei
-- voller Leistung 360.000 l Heu und Silage im Monat, im Lager liegen aber
-- 167.420 l fertige Ration = 68 Monate Vorrat fuer die Kuehe. "Knapp: Heu" war
-- rechnerisch richtig und praktisch unbrauchbar - die Anlage muss ja nicht
-- durchlaufen. Erzeugnisse, die nur verkauft werden (kein Verbrauch auf dem
-- Hof), zaehlen NICHT als satt: dort will man die Produktion am Laufen halten.
local function satteEingaenge(cache, storage, bedarf)
    local satt = {}
    for _, p in ipairs(cache.productions or {}) do
        for _, r in ipairs(p.recipes or {}) do
            if r.active and type(r.inputsPerMonth) == "table" then
                local alleSatt, hatVerbrauch = true, false
                for _, out in ipairs(r.outputs or {}) do
                    local verbrauch = bedarf[out.fillKey] or 0
                    if verbrauch > 0 then
                        hatVerbrauch = true
                        local vorrat = (storage[out.fillKey] or 0) / verbrauch
                        if vorrat < TaskAnalyzer.PRODUKT_SATT_MONATE then
                            alleSatt = false
                        end
                    end
                end
                if hatVerbrauch and alleSatt then
                    for key, amt in pairs(r.inputsPerMonth) do
                        satt[key] = (satt[key] or 0) + amt
                    end
                end
            end
        end
    end
    return satt
end

local function lagerAufgaben(cache)
    if cache == nil then
        return
    end
    local an = cache.animals or {}
    local storage = cache.storage or {}
    local bedarf, prodBedarf = monatsBedarf(an)
    local satt = satteEingaenge(cache, storage, bedarf)

    -- Welche Waren liefert ein Feld? Nur dort passt "Anbau einplanen"; Wasser,
    -- Mineralfutter oder Silage kauft oder stellt man her.
    --
    -- Obst, Wein und Oliven wachsen auf Dauerkulturen: `allowsSeeding=false`.
    -- Dort gibt es nichts einzuplanen, man pflanzt Baeume und wartet Jahre
    -- (gemeldet 13.11.2026: "Nachschub bei den Obstbaeumen einplanen, aber das
    -- ist nicht steuerbar"). Deshalb zaehlen sie nicht als Feldware.
    local vomFeld, vonDauerkultur = {}, {}
    local mapInfo = (CropRotationData ~= nil and CropRotationData.mapInfo) or {}
    for crop, produkte in pairs((CropRotationData ~= nil and CropRotationData.FRUIT_PRODUCTS) or {}) do
        local info   = mapInfo[crop]
        local saebar = (info == nil) or (info.seedable ~= false)
        for _, pr in ipairs(produkte) do
            if saebar then
                vomFeld[pr] = true
            else
                vonDauerkultur[pr] = true
            end
        end
    end

    -- Knappe Reichweite (dieselbe Grenze wie der bisherige Report).
    -- Nach ANGEZEIGTEM Namen zusammengefasst: verschiedene Fuelltypen koennen im
    -- Spiel gleich heissen (z. B. zweimal "Grass") und standen sonst doppelt da.
    local nachName = {}
    for key, gesamtBedarf in pairs(bedarf) do
        -- Bedarf satter Produktionen abziehen (siehe satteEingaenge)
        local monatlich = gesamtBedarf - (satt[key] or 0)
        if monatlich > 0 and not SELBSTVERSORGT[key] then
            local name = fillName(key)
            local g = nachName[name]
            if g == nil then
                g = { key = key, monatlich = 0, bestand = 0, vomFeld = false,
                      dauer = false, prod = 0 }
                nachName[name] = g
            end
            if key < g.key then g.key = key end   -- stabiler Schluessel fuer den Status
            g.monatlich = g.monatlich + monatlich
            g.bestand   = g.bestand + (storage[key] or 0)
            g.vomFeld   = g.vomFeld or (vomFeld[key] == true)
            g.dauer     = g.dauer or (vonDauerkultur[key] == true)
            g.prod      = g.prod + math.max(0, (prodBedarf[key] or 0) - (satt[key] or 0))
        end
    end
    -- Deckung durch die uebrigen Sorten derselben Futtergruppe (Silage statt
    -- Heu usw.) zaehlt mit - ABER nur, wenn keine Produktion genau diesen
    -- Fuelltyp braucht. Ein Rezept nimmt keine Alternative: der Mischfutter-
    -- Anlage fehlt Heu, auch wenn Stroh im Ueberfluss daliegt.
    local gruppe = an.mixedCoverMonths or {}
    local hofProdukte = an.hofProdukte or {}
    for name, g in pairs(nachName) do
        local ersatz = (g.prod > 0) and 0 or (gruppe[g.key] or 0)
        local mo = g.bestand / g.monatlich + ersatz
        if mo < (FruchtfolgeAdvisor.KRITISCH_MONATE or 1.5) then
            -- Mist, Guelle, Milch, Wolle fallen im Stall an. Kaufen oder
            -- herstellen geht nicht, also steht so etwas unter HINWEISE statt
            -- ganz oben als dringend - handeln kann man nur ueber die Anlage
            -- oder den Tierbestand.
            -- Dauerkulturen genauso: bis ein neuer Baum traegt, vergehen Jahre.
            local ausDemStall = hofProdukte[g.key] == true
            local dauerkultur = g.dauer and not g.vomFeld
            local prio = (ausDemStall or dauerkultur) and TaskAnalyzer.PRIO_INFO
                or TaskAnalyzer.PRIO_URGENT
            local detail = L("fa_d_buy", "buy or produce")
            if ausDemStall then
                detail = L("fa_d_ownProduce", "from your animals")
            elseif dauerkultur then
                detail = L("fa_d_perennial", "perennial crop")
            elseif g.vomFeld then
                detail = L("fa_plan_supply", "plan supply")
            end
            add("low", g.key, prio, "storage",
                F("fa_t_low", "Running low: %s", name),
                FruchtfolgeAdvisor.fmtReach(mo), detail)
        end
    end

    -- Produktionen: aktiver Eingang leer
    for pi, p in ipairs(cache.productions or {}) do
        for _, r in ipairs(p.recipes or {}) do
            if r.active then
                for _, inp in ipairs(r.inputs or {}) do
                    if (inp.level or 0) <= 0 then
                        add("prodstop", tostring(p.name) .. "#" .. tostring(pi), TaskAnalyzer.PRIO_URGENT, "production",
                            F("fa_t_prodstop", "Production stopped: %s", kurz(FruchtfolgeAdvisor.localizeText(p.name), 26)),
                            "", F("fa_missing", "missing: %s", fillName(inp.fillKey)))
                        break
                    end
                end
            end
        end
    end

    -- Markt: deutlich ueber Basispreis
    for i, tp in ipairs(cache.marketTips or {}) do
        if i > 3 then break end
        if (tp.ratio or 0) >= TaskAnalyzer.MARKET_RATIO then
            add("sell", tp.key, TaskAnalyzer.PRIO_INFO, "market",
                F("fa_t_sell", "Good price: %s", fillName(tp.key)),
                string.format("+%.0f%%", (tp.ratio - 1) * 100),
                tp.station ~= nil and kurz(tp.station, 22) or "")
        end
    end
end

-- Pflicht-Aussaat: Jahresbedarf je Produkt gegen Lager + wachsende Felder.
-- Logik aus dem frueheren Hofreport uebernommen.
-- Produktionsbedarf, der fuer die ANBAUPLANUNG nicht zaehlt.
-- Fuer die Lagerwarnung ist der Durchsatz einer Anlage die richtige Zahl - fuer
-- die Frage "welche Frucht saee ich als Naechstes" nicht. Drei Faelle:
--   1. Ausgang voll     -> die Anlage steht ohnehin.
--   2. Erzeugnis satt    -> dieselbe Regel wie beim Lager (PRODUKT_SATT_MONATE).
--   3. Reiner Verarbeiter -> das Erzeugnis wird nur verkauft, auf dem Hof
--      braucht es niemand. Dafuer stellt man den Anbau nicht um; die Anlage
--      laeuft mit dem, was uebrig ist.
-- Anlass (31.10.2026, Bergisch Land): Der Zuckerrueben-Haecksler ist eine
-- Durchlaufanlage. Aus seiner Rezept-Kapazitaet wurden 644 ha Ruebenbedarf,
-- obwohl 131.143 l im Lager lagen und sein Ausgang mit 67.424 l SUGARBEET_CUT
-- blockiert war.
local function planungsAbzug(cache, storage, bedarf)
    local abzug = {}
    for _, p in ipairs(cache.productions or {}) do
        for _, r in ipairs(p.recipes or {}) do
            if r.active and type(r.inputsPerMonth) == "table" then
                local voll = (ProductionAnalyzer ~= nil
                    and ProductionAnalyzer.istAusgangVoll ~= nil
                    and ProductionAnalyzer.istAusgangVoll(r)) or false

                local hatVerbrauch, alleSatt = false, true
                for _, out in ipairs(r.outputs or {}) do
                    local verbrauch = bedarf[out.fillKey] or 0
                    if verbrauch > 0 then
                        hatVerbrauch = true
                        if (storage[out.fillKey] or 0) / verbrauch
                                < TaskAnalyzer.PRODUKT_SATT_MONATE then
                            alleSatt = false
                        end
                    end
                end

                if voll or not hatVerbrauch or alleSatt then
                    for key, amt in pairs(r.inputsPerMonth) do
                        abzug[key] = (abzug[key] or 0) + amt
                    end
                end
            end
        end
    end
    return abzug
end

local function anbauAufgaben(cache)
    if cache == nil or CropRotationData == nil then
        return
    end
    local an = cache.animals or {}
    local storage = cache.storage or {}
    local bedarf, prodBedarf = monatsBedarf(an)

    -- Produktionsanteile abziehen, die fuer die Planung nicht zaehlen. Nie unter
    -- den Bedarf von Tieren und Einstreu: der bleibt immer stehen.
    local abzug = planungsAbzug(cache, storage, bedarf)
    local planBedarf = {}
    TaskAnalyzer.planDiag = {}
    for key, monatlich in pairs(bedarf) do
        local ohneProd = monatlich - (prodBedarf[key] or 0)
        planBedarf[key] = math.max(ohneProd, monatlich - (abzug[key] or 0))
        if (prodBedarf[key] or 0) > 0 or planBedarf[key] > 0 then
            TaskAnalyzer.planDiag[key] = {
                roh    = monatlich,
                prod   = prodBedarf[key] or 0,
                abzug  = abzug[key] or 0,
                plan   = planBedarf[key],
            }
        end
    end
    bedarf = planBedarf

    -- Gesamte eigene Feldflaeche: die Obergrenze dessen, was der Hof ueberhaupt
    -- anbauen kann. Was darueber liegt, ist keine Planungsaufgabe mehr.
    local eigeneHa = 0
    for _, entry in ipairs(cache.fields or {}) do
        if entry.fieldInfo ~= nil and entry.fieldInfo.isOwn then
            eigeneHa = eigeneHa + (entry.fieldInfo.area or 0) / 10000
        end
    end

    -- Dauerkulturen bleiben aussen vor: fuer Obst, Wein und Oliven laesst sich
    -- keine Flaeche "einplanen", die pflanzt man als Baeume und wartet Jahre.
    -- Erkannt an allowsSeeding (CropRotationData.mapInfo[crop].seedable).
    local mapInfo = CropRotationData.mapInfo or {}
    local produktZuFrucht = {}
    for _, crop in ipairs(CropRotationData.getAllCrops() or {}) do
        local prods  = CropRotationData.FRUIT_PRODUCTS[crop]
        local info   = mapInfo[crop]
        local saebar = (info == nil) or (info.seedable ~= false)
        if prods ~= nil and prods[1] ~= nil and saebar
                and (CropRotationData.isCropEnabled == nil or CropRotationData.isCropEnabled(crop)) then
            local p = prods[1]
            produktZuFrucht[p] = produktZuFrucht[p] or {}
            table.insert(produktZuFrucht[p], crop)
        end
    end

    local waechst = {}
    for _, entry in ipairs(cache.fields or {}) do
        local fi = entry.fieldInfo
        local crop = fi.currentFruit
        if crop ~= nil then
            local prods = CropRotationData.FRUIT_PRODUCTS[crop]
            local ertrag = CropRotationData.YIELD_L_PER_HA[crop] or 0
            if prods ~= nil and prods[1] ~= nil and ertrag > 0 then
                waechst[prods[1]] = (waechst[prods[1]] or 0) + ertrag * (fi.area or 0) / 10000
            end
        end
    end

    for produkt, monatlich in pairs(bedarf) do
        local fruechte = produktZuFrucht[produkt]
        if monatlich > 0 and fruechte ~= nil then
            local fehlt = monatlich * 12 - (storage[produkt] or 0) - (waechst[produkt] or 0)
            if fehlt > 0 then
                local besterErtrag, cropSet = 0, {}
                for _, c in ipairs(fruechte) do
                    cropSet[c] = true
                    local y = CropRotationData.YIELD_L_PER_HA[c] or 0
                    if y > besterErtrag then besterErtrag = y end
                end
                if besterErtrag > 0 then
                    local ha = fehlt / besterErtrag
                    local d = TaskAnalyzer.planDiag[produkt]
                    if d ~= nil then
                        d.bestand = storage[produkt] or 0
                        d.waechst = waechst[produkt] or 0
                        d.fehlt   = fehlt
                        d.ha      = ha
                        d.hofHa   = eigeneHa
                    end
                    -- Freie Felder, auf die diese Frucht passt (Top-3-Empfehlung).
                    -- Jedes davon steht schon als eigene Aufgabe "Feld X bestellen"
                    -- in der Liste. Reicht ihre Flaeche fuer den Jahresbedarf, waere
                    -- eine zusaetzliche Planungszeile nur eine Doppelmeldung - sie
                    -- entsteht deshalb erst, wenn die freie Flaeche NICHT ausreicht.
                    local felder, frei = {}, 0
                    for _, entry in ipairs(cache.fields or {}) do
                        local fi = entry.fieldInfo
                        if fi.currentFruit == nil then
                            for rank, rec in ipairs(entry.recommendations or {}) do
                                if rank > 3 then break end
                                if rec.crop ~= nil and cropSet[rec.crop] then
                                    if #felder < 3 then
                                        felder[#felder + 1] = tostring(fi.fieldId or "?")
                                    end
                                    frei = frei + (fi.area or 0) / 10000
                                    break
                                end
                            end
                        end
                    end
                    -- Mehr, als der ganze Hof tragen kann: Dann ist eine
                    -- Hektarzahl keine Hilfe mehr, sondern nur noch eine grosse
                    -- Zahl. Stattdessen sagt die Zeile, woran es wirklich liegt.
                    if eigeneHa > 0 and ha > eigeneHa then
                        add("plan", produkt, TaskAnalyzer.PRIO_INFO, "plan",
                            F("fa_t_plan", "Area missing: %s",
                                CropRotationData.getCropName(produkt)),
                            "", L("fa_d_plan_over",
                                "production needs more than the farm can grow"))
                    else

                    local luecke = ha - frei
                    if luecke > 0.1 then
                        -- Detail sagt, woran es haengt: gar kein freies Feld, oder
                        -- die freien Felder decken nur einen Teil.
                        local detail
                        if #felder == 0 then
                            detail = L("fa_d_plan_nofield", "no free field fits")
                        else
                            detail = F("fa_d_plan_part", "free: %s = %.1f ha",
                                table.concat(felder, ", "), frei)
                        end
                        local reich = (storage[produkt] or 0) / monatlich
                        local prio = (reich < (FruchtfolgeAdvisor.KNAPP_MONATE or 3)) and TaskAnalyzer.PRIO_SOON
                            or TaskAnalyzer.PRIO_INFO
                        add("plan", produkt, prio, "plan",
                            F("fa_t_plan", "Area missing: %s", CropRotationData.getCropName(produkt)),
                            string.format("%.1f ha", luecke), detail)
                    end
                    end
                end
            end
        end
    end
end

-- Silos: fast voll
local function siloAufgaben(farmId)
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps == nil or type(ps.placeables) ~= "table" then
        return
    end
    for _, p in pairs(ps.placeables) do
        local spec = p ~= nil and p.spec_silo or nil
        if spec ~= nil and type(spec.storages) == "table" and besitzerVon(p) == farmId then
            local hoechst, hauptTyp = 0, nil
            for _, st in ipairs(spec.storages) do
                if type(st) == "table" and type(st.fillLevels) == "table" then
                    local caps = type(st.capacities) == "table" and st.capacities or {}
                    local gesamt, groesste, groessterTyp = 0, 0, nil
                    for ft, lvl in pairs(st.fillLevels) do
                        if type(lvl) == "number" and lvl > 0 then
                            gesamt = gesamt + lvl
                            if lvl > groesste then groesste, groessterTyp = lvl, ft end
                            local capT = caps[ft]
                            if type(capT) == "number" and capT > 0 and lvl / capT > hoechst then
                                hoechst, hauptTyp = lvl / capT, ft
                            end
                        end
                    end
                    if type(st.capacity) == "number" and st.capacity > 0 and next(caps) == nil then
                        local r = gesamt / st.capacity
                        if r > hoechst then hoechst, hauptTyp = r, groessterTyp end
                    end
                end
            end
            if hoechst >= TaskAnalyzer.SILO_HIGH then
                local typName = ""
                if hauptTyp ~= nil and g_fillTypeManager ~= nil then
                    local d = g_fillTypeManager:getFillTypeByIndex(hauptTyp)
                    if d ~= nil then typName = d.title or d.name or "" end
                end
                add("silofull", objektSchluessel(p), TaskAnalyzer.PRIO_SOON, "storage",
                    F("fa_t_silofull", "Storage almost full: %s", kurz(placeableName(p), 26)),
                    string.format("%.0f%%", math.min(hoechst, 1) * 100), typName)
            end
        end
    end
end

-- Produktionsausgang voll (ohne Direktverkauf/Auslieferung)
local function ausgangAufgaben(farmId)
    local pcm = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    if pcm == nil or pcm.getProductionPointsForFarmId == nil then
        return
    end
    for _, pp in pairs(pcm:getProductionPointsForFarmId(farmId) or {}) do
        local st = type(pp) == "table" and pp.storage or nil
        if st ~= nil and st.getCapacity ~= nil and type(pp.productions) == "table" then
            local direkt = type(pp.outputFillTypeIdsDirectSell) == "table" and pp.outputFillTypeIdsDirectSell or {}
            local liefern = type(pp.outputFillTypeIdsAutoDeliver) == "table" and pp.outputFillTypeIdsAutoDeliver or {}
            local geprueft = {}
            for _, prod in pairs(pp.productions) do
                if type(prod) == "table" and type(prod.outputs) == "table" then
                    for _, out in pairs(prod.outputs) do
                        local ft = type(out) == "table" and out.type or nil
                        if type(ft) == "number" and not geprueft[ft] and not direkt[ft] and not liefern[ft] then
                            geprueft[ft] = true
                            local kap = st:getCapacity(ft) or 0
                            local lvl = (type(st.fillLevels) == "table" and st.fillLevels[ft]) or 0
                            if kap > 0 and lvl / kap >= TaskAnalyzer.OUTPUT_HIGH then
                                local typName = fillName(ft)
                                if g_fillTypeManager ~= nil then
                                    local d = g_fillTypeManager:getFillTypeByIndex(ft)
                                    if d ~= nil then typName = d.title or d.name or typName end
                                end
                                local name = placeableName(pp.owningPlaceable)
                                if name == "?" and pp.getName ~= nil then
                                    name = tostring(pp:getName() or "?")
                                end
                                add("prodfull", objektSchluessel(pp.owningPlaceable or pp) .. "#" .. tostring(ft),
                                    (lvl / kap >= TaskAnalyzer.FILL_FULL) and TaskAnalyzer.PRIO_URGENT or TaskAnalyzer.PRIO_SOON,
                                    "production",
                                    F("fa_t_prodfull", "Output full: %s", kurz(FruchtfolgeAdvisor.localizeText(name), 26)),
                                    string.format("%.0f%%", math.min(lvl / kap, 1) * 100), typName)
                            end
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  MASCHINEN
-- ═══════════════════════════════════════════════════════════════

local function kraftstoffIndizes()
    local liste = {}
    if g_fillTypeManager == nil or g_fillTypeManager.getFillTypeIndexByName == nil then
        return liste, nil
    end
    for _, n in ipairs({ "DIESEL", "ELECTRICCHARGE", "METHANE" }) do
        local idx = g_fillTypeManager:getFillTypeIndexByName(n)
        if idx ~= nil then liste[#liste + 1] = idx end
    end
    return liste, g_fillTypeManager:getFillTypeIndexByName("DEF")
end

local function maschinenAufgaben(farmId)
    local vs = g_currentMission ~= nil and g_currentMission.vehicleSystem or nil
    if vs == nil or type(vs.vehicles) ~= "table" then
        return
    end
    local kraftstoffe, adblue = kraftstoffIndizes()
    for _, v in pairs(vs.vehicles) do
        if type(v) == "table" and v.isPallet ~= true and besitzerVon(v) == farmId then
            local name = (v.getName ~= nil) and kurz(v:getName(), 26) or "?"
            local objKey = objektSchluessel(v)

            if v.spec_wearable ~= nil and v.getDamageAmount ~= nil then
                local d = v:getDamageAmount() or 0
                if d >= TaskAnalyzer.DAMAGE_SOON then
                    add("repair", objKey,
                        (d >= TaskAnalyzer.DAMAGE_URGENT) and TaskAnalyzer.PRIO_URGENT or TaskAnalyzer.PRIO_SOON,
                        "vehicle", F("fa_t_repair", "Repair: %s", name),
                        string.format("%.0f%%", d * 100), L("fa_d_damage", "damage"))
                end
            end

            if v.spec_motorized ~= nil and v.getConsumerFillUnitIndex ~= nil
                    and v.getFillUnitFillLevelPercentage ~= nil then
                for _, ft in ipairs(kraftstoffe) do
                    local fu = v:getConsumerFillUnitIndex(ft)
                    if fu ~= nil then
                        local r = v:getFillUnitFillLevelPercentage(fu) or 1
                        if r < TaskAnalyzer.FUEL_SOON then
                            add("fuel", objKey,
                                (r < TaskAnalyzer.FUEL_URGENT) and TaskAnalyzer.PRIO_URGENT or TaskAnalyzer.PRIO_SOON,
                                "vehicle", F("fa_t_refuel", "Refuel: %s", name),
                                string.format("%.0f%%", r * 100), "")
                        end
                        break
                    end
                end
                if adblue ~= nil then
                    local fu = v:getConsumerFillUnitIndex(adblue)
                    if fu ~= nil then
                        local r = v:getFillUnitFillLevelPercentage(fu) or 1
                        if r < TaskAnalyzer.FUEL_URGENT then
                            add("def", objKey, TaskAnalyzer.PRIO_SOON, "vehicle",
                                F("fa_t_def", "Refill DEF: %s", name),
                                string.format("%.0f%%", r * 100), "")
                        end
                    end
                end
            end
        end
    end
end

-- ═══════════════════════════════════════════════════════════════
--  AUFBAU
-- ═══════════════════════════════════════════════════════════════

--- Aufgaben neu berechnen. Erwartet einen frischen Analyse-Cache
--- (FruchtfolgeAdvisor.buildCache vorher aufrufen).
function TaskAnalyzer.build()
    -- Schluessel des letzten Durchlaufs merken (Hysterese, siehe faellig)
    vorher = {}
    for _, t in ipairs(TaskAnalyzer.tasks or {}) do
        if t.key ~= nil then vorher[t.key] = true end
    end
    sammlung = {}
    gesehen  = {}
    aktFarm  = farmIdLokal()
    local cache = FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.cache or nil

    -- Jede Gruppe eigenstaendig: faellt eine aus (fehlende API auf einer
    -- fremden Karte), laufen die anderen weiter.
    feldAufgaben(cache)
    tierAufgaben(cache, aktFarm)
    lagerAufgaben(cache)
    anbauAufgaben(cache)
    siloAufgaben(aktFarm)
    ausgangAufgaben(aktFarm)
    maschinenAufgaben(aktFarm)

    table.sort(sammlung, function(a, b)
        if a.prio ~= b.prio then return a.prio < b.prio end
        local ca, cb = CAT_ORDER[a.cat] or 9, CAT_ORDER[b.cat] or 9
        if ca ~= cb then return ca < cb end
        return a.text < b.text
    end)

    TaskAnalyzer.tasks = sammlung
    sammlung, gesehen = nil, nil

    -- Status erledigter Anlaesse wegraeumen (siehe TaskState.lua, Grundregel)
    if TaskState ~= nil and TaskState.cleanup ~= nil then
        TaskState.cleanup(TaskAnalyzer.tasks, aktFarm)
    end
    return TaskAnalyzer.tasks
end

-- ═══════════════════════════════════════════════════════════════
--  ANZEIGE (gemeinsam fuer F7-Fenster und ESC-Seite)
-- ═══════════════════════════════════════════════════════════════

local PRIO_SECTION = {
    [1] = { key = "fa_task_sec_urgent", fb = "URGENT" },
    [2] = { key = "fa_task_sec_soon",   fb = "SOON" },
    [3] = { key = "fa_task_sec_info",   fb = "NOTES" },
}

-- Der Standardtext im Menue ist fast weiss (fs25_colorMainLight
-- 0.90/0.92/0.81). Helle, blasse Farbtoene gehen daneben unter - bei 16px
-- Schrift auf dunklem Grund wirkte das frueheren Gelb praktisch weiss.
-- Deshalb satte, dunklere Toene: sie heben sich sowohl vom Weiss als auch
-- voneinander ab.
TaskAnalyzer.COL = {
    urgent = { 1.00, 0.30, 0.24 },   -- Rot
    soon   = { 1.00, 0.68, 0.10 },   -- Orange (Gelb wirkte weiss)
    info   = { 0.48, 0.72, 1.00 },   -- Blau
    white  = { 1.00, 1.00, 1.00 },
    grey   = { 0.62, 0.62, 0.62 },
    green  = { 0.60, 0.95, 0.35 },
    taken  = { 0.30, 0.78, 1.00 },
}

local function prioFarbe(p)
    if p == 1 then return TaskAnalyzer.COL.urgent end
    if p == 2 then return TaskAnalyzer.COL.soon end
    return TaskAnalyzer.COL.info
end

-- Bereich einer Aufgabe: eigene Spalte mit eigener Farbe. Innerhalb einer
-- Dringlichkeit stehen so alle Feldarbeiten zusammen, dann die Tiere usw. -
-- vorher lagen Feld, Lager und Markt in der Reihenfolge der Berechnung
-- gemischt untereinander.
TaskAnalyzer.KATEGORIEN = {
    field      = { rang = 1, key = "fa_task_cat_field",      fb = "Field",      col = { 0.45, 0.85, 0.30 } },
    animal     = { rang = 2, key = "fa_task_cat_animal",     fb = "Animals",    col = { 1.00, 0.60, 0.20 } },
    production = { rang = 3, key = "fa_task_cat_production", fb = "Production", col = { 0.30, 0.68, 1.00 } },
    storage    = { rang = 4, key = "fa_task_cat_storage",    fb = "Storage",    col = { 0.70, 0.52, 1.00 } },
    vehicle    = { rang = 5, key = "fa_task_cat_vehicle",    fb = "Machines",   col = { 0.72, 0.74, 0.78 } },
    plan       = { rang = 6, key = "fa_task_cat_plan",       fb = "Planning",   col = { 0.20, 0.82, 0.68 } },
    market     = { rang = 7, key = "fa_task_cat_market",     fb = "Market",     col = { 0.95, 0.78, 0.15 } },
}

local function kategorie(cat)
    return TaskAnalyzer.KATEGORIEN[cat or ""]
        or { rang = 9, key = nil, fb = "", col = TaskAnalyzer.COL.grey }
end

-- Sortierschluessel: Bereich, dann der Text mit auf fuenf Stellen
-- aufgefuellten Zahlen ("Feld 2" vor "Feld 100", nicht umgekehrt).
local function sortSchluessel(t)
    local text = string.gsub(tostring(t.text or ""), "%d+", function(z)
        return string.format("%05d", tonumber(z) or 0)
    end)
    return string.format("%d:%s", kategorie(t.cat).rang, text)
end

--- Status einer Aufgabe: "open" | "taken", dazu der Name.
function TaskAnalyzer.statusOf(task)
    if TaskState ~= nil and TaskState.getEffective ~= nil then
        return TaskState.getEffective(task.key)
    end
    return "open", ""
end

function TaskAnalyzer.statusText(status, wer)
    if status == "taken" then
        return (wer ~= nil and wer ~= "") and wer or L("fa_task_taken", "taken"), TaskAnalyzer.COL.taken
    end
    return L("fa_task_open", "open"), TaskAnalyzer.COL.grey
end

--- Gruppierte Liste fuer beide Ansichten:
--- { {section = text} | {task = t, status = s, who = n}, ... }, zaehler
-- Feldarbeiten werden je FELD zu einem Block zusammengefasst, in der
-- Reihenfolge, in der man ein Feld wirklich bearbeitet (SCHRITT_FOLGE).
-- Der Block steht in dem Dringlichkeits-Abschnitt seines dringendsten
-- Schrittes; die Schritte selbst behalten ihre eigene Einstufung und Farbe.
-- Uebersprungene Schritte brauchen keine Sonderbehandlung: die Schritte
-- entstehen jedes Mal neu aus dem Feldzustand.
-- @param aufgeklappt table|nil  Set { [feldnummer] = true } der Felder, deren
--                               Schritte einzeln ausgeschrieben werden.
-- Vorgabe: EINE Zeile je Feld. Darin stehen die Zahl der Schritte UND die
-- ganze Arbeitsfolge ("haeckseln > kalken > duengen > bestellen") - damit
-- bleibt die Uebersicht auf einen Blick erhalten, ohne dass die Liste bei
-- vielen Feldern zulaeuft. Aufklappen zeigt je Schritt Wert, Detail,
-- "Schritt i von n" und den Uebernahme-Status.
function TaskAnalyzer.getGrouped(aufgeklappt)
    local z = { open = 0, taken = 0 }
    local einzel = { {}, {}, {} }   -- Aufgaben ohne Feldblock, je Dringlichkeit
    local bloecke, reihenfolge = {}, {}

    for _, t in ipairs(TaskAnalyzer.tasks or {}) do
        local st, wer = TaskAnalyzer.statusOf(t)
        z[st] = (z[st] or 0) + 1
        local e = { task = t, status = st, who = wer }
        if t.feld ~= nil then
            local b = bloecke[t.feld]
            if b == nil then
                b = { feld = t.feld, schritte = {}, prio = t.prio }
                bloecke[t.feld] = b
                reihenfolge[#reihenfolge + 1] = b
            end
            b.schritte[#b.schritte + 1] = e
            if t.prio < b.prio then b.prio = t.prio end
        else
            table.insert(einzel[t.prio] or einzel[3], e)
        end
    end

    -- Schritte je Block in die Arbeitsfolge bringen
    for _, b in ipairs(reihenfolge) do
        table.sort(b.schritte, function(a, c)
            if a.task.folge ~= c.task.folge then
                return a.task.folge < c.task.folge
            end
            return tostring(a.task.text) < tostring(c.task.text)
        end)
    end

    -- Bloecke ihrem Abschnitt zuordnen, nach Feldnummer sortiert
    local nachPrio = { {}, {}, {} }
    for _, b in ipairs(reihenfolge) do
        table.insert(nachPrio[b.prio] or nachPrio[3], b)
    end
    for p = 1, 3 do
        table.sort(nachPrio[p], function(a, c)
            return (tonumber(a.feld) or 0) < (tonumber(c.feld) or 0)
        end)
    end

    local out = {}
    for p = 1, 3 do
        local anzahl = #einzel[p]
        for _, b in ipairs(nachPrio[p]) do anzahl = anzahl + #b.schritte end
        if anzahl > 0 then
            out[#out + 1] = { section = string.format("%s (%d)",
                L(PRIO_SECTION[p].key, PRIO_SECTION[p].fb), anzahl), prio = p }
            -- Felder zuerst: sie sind die eigentliche Arbeit draussen
            for _, b in ipairs(nachPrio[p]) do
                local zu = not (aufgeklappt ~= nil and aufgeklappt[b.feld] == true)
                out[#out + 1] = { block = b, zu = zu }
                if not zu then
                    for i, e in ipairs(b.schritte) do
                        out[#out + 1] = {
                            task = e.task, status = e.status, who = e.who,
                            schritt = i, schritte = #b.schritte,
                        }
                    end
                end
            end
            table.sort(einzel[p], function(a, c)
                return sortSchluessel(a.task) < sortSchluessel(c.task)
            end)
            for _, e in ipairs(einzel[p]) do out[#out + 1] = e end
        end
    end
    return out, z
end

--- Zeilen fuer die native Liste im F7-Fenster (generisches 6-Spalten-Format).
function TaskAnalyzer.getRows(aufgeklappt)
    local rows = {}
    local gruppen = TaskAnalyzer.getGrouped(aufgeklappt)
    if #gruppen == 0 then
        rows[#rows + 1] = { cells = {
            { t = L("fa_task_none", "Nothing to do."), col = TaskAnalyzer.COL.green },
            { t = "" }, { t = "" }, { t = "" }, { t = "" }, { t = "" },
        } }
        return rows
    end
    rows[#rows + 1] = { head = {
        L("fa_task_h_task", "TASK"), L("fa_task_h_value", "VALUE"),
        L("fa_task_h_area", "AREA"),
        L("fa_task_h_detail", "DETAIL"), L("fa_task_h_status", "STATUS"), "",
    } }
    for _, g in ipairs(gruppen) do
        if g.section ~= nil then
            -- Abschnittstitel in der Farbe seiner Dringlichkeit (rot/gelb/blau),
            -- damit beim Scrollen sofort klar ist, in welchem Block man steht.
            rows[#rows + 1] = { section = g.section, col = prioFarbe(g.prio) }
        elseif g.block ~= nil then
            -- Kopfzeile eines Feldes: wie viele Schritte offen sind und was als
            -- Naechstes dran ist. Klick klappt die Schritte auf und zu.
            local b = g.block
            local kat = kategorie("field")
            -- Zugeklappt steht die ganze Arbeitsfolge in einer Zeile
            -- ("haeckseln > kalken > duengen > bestellen"), offen nur der
            -- naechste Schritt - darunter stehen sie ja ausgeschrieben.
            local folge, blockFrucht
            if g.zu then
                local teile, frucht = {}, nil
                for _, e in ipairs(b.schritte) do
                    teile[#teile + 1] = TaskAnalyzer.schrittName(e.task.art)
                    -- Die Frucht, die ausgebracht werden soll, haengt am
                    -- Bestell-Schritt. Sie kommt hinten an die Folge, damit sie
                    -- auch in der zugeklappten Zeile steht - genau einmal.
                    if e.task.art == "sow" and e.task.detail ~= "" then
                        frucht = e.task.detail
                    end
                end
                folge = table.concat(teile, " > ")
                -- Die Frucht NICHT an die Folge haengen: In der Spalte DETAIL
                -- (300px) wurde "haeckseln > duengen > bestellen: Winterwei..."
                -- abgeschnitten. Sie steht deshalb in der Spalte rechts daneben,
                -- die bei einer Feldzeile ohnehin leer ist.
                blockFrucht = frucht
            else
                local naechste = b.schritte[1]
                folge = (naechste ~= nil) and string.format(L("fa_task_next", "next: %s"),
                    TaskAnalyzer.schrittName(naechste.task.art)) or ""
            end
            -- Die Arbeitsfolge steht in der Spalte AUFGABE (470px, die
            -- breiteste), die Frucht in DETAIL - dort, wo bei allen anderen
            -- Zeilen auch die Frucht steht. Vorher stand sie unter STATUS,
            -- was die Spalte zweckentfremdet hat, und davor wurde sie in
            -- DETAIL abgeschnitten.
            local kopf = (g.zu and "+ " or "- ") .. L("fa_field", "Field") .. " " .. b.feld
            if g.zu and folge ~= "" then
                kopf = kopf .. ": " .. folge
            end
            rows[#rows + 1] = {
                feldBlock = b.feld,
                cells = {
                    { t = kurz(kopf, 58), col = prioFarbe(b.prio) },
                    -- Singular/Plural: "1 Schritt", nicht "1 Schritte"
                    { t = (#b.schritte == 1) and L("fa_task_step_one", "1 step")
                        or string.format(L("fa_task_steps", "%d steps"), #b.schritte),
                      col = TaskAnalyzer.COL.white },
                    { t = (kat.key ~= nil) and L(kat.key, kat.fb) or "", col = kat.col },
                    -- DETAIL: zugeklappt die Frucht, die ausgebracht werden
                    -- soll; aufgeklappt der naechste Schritt (die Folge steht
                    -- dann ja ausgeschrieben darunter).
                    { t = g.zu and ((blockFrucht ~= nil) and kurz(blockFrucht, 30) or "")
                        or kurz(folge, 34), col = TaskAnalyzer.COL.grey },
                    { t = "" },
                    { t = "" },
                },
            }
        else
            local t = g.task
            local stText, stCol = TaskAnalyzer.statusText(g.status, g.who)
            local kat = kategorie(t.cat)
            -- Schritt eines aufgeklappten Feldes: eingerueckt und mit
            -- "Schritt i von n" im Detail.
            local text = kurz(t.text, 52)
            local detail = kurz(t.detail, 34)
            if g.schritt ~= nil then
                text = "   " .. text
                local nr = string.format(L("fa_task_step_of", "step %d of %d"),
                    g.schritt, g.schritte or g.schritt)
                detail = (detail ~= "") and (nr .. ", " .. detail) or nr
            end
            rows[#rows + 1] = {
                taskKey = t.key,
                cells = {
                    { t = text, col = prioFarbe(t.prio) },
                    { t = t.value, col = TaskAnalyzer.COL.white },
                    { t = (kat.key ~= nil) and L(kat.key, kat.fb) or "", col = kat.col },
                    { t = kurz(detail, 40), col = TaskAnalyzer.COL.grey },
                    { t = kurz(stText, 24), col = stCol },
                    { t = "" },
                },
            }
        end
    end
    return rows
end

--- Kurzzeile ueber der Liste: Zaehler + Bedienhinweis
function TaskAnalyzer.getSummaryLine()
    local _, z = TaskAnalyzer.getGrouped()
    local zaehler = string.format(L("fa_task_count", "%d open, %d taken"),
        z.open or 0, z.taken or 0)
    return zaehler .. "   |   " .. L("fa_task_hint", "Click a task to take it over or hand it back.")
end

--- Konsolen-Ausgabe (faAufgaben)
-- Entscheidungsgrundlage EINES Feldes ausgeben: faFeld <nr>
-- Zeigt je Messpunkt die Rohwerte und darunter, warum eine Aufgabe entsteht
-- oder nicht. Gedacht fuer den Fall "im Spiel fehlt Kalk/Duenger, die Liste
-- sagt aber nichts".
-- Erster Parameter ist das Zielobjekt (addConsoleCommand ruft target:func(...)),
-- deshalb der Platzhalter.
function TaskAnalyzer.fieldDebugDump(_, nrText)
    local gesucht = tonumber(nrText)
    print("=== FA-FELD-DUMP " .. tostring(nrText) .. " ===")
    if gesucht == nil then
        print("  Aufruf: faFeld <Feldnummer>")
        return
    end
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
        FruchtfolgeAdvisor.buildCache()
    end
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or {}
    local fm = g_fieldManager
    print(string.format("  limeRequired=%s limeLevelMaxValue=%s | sprayLevelMaxValue=%s | plowingRequired=%s plowLevelMaxValue=%s",
        tostring(mi.limeRequired), tostring(fm ~= nil and fm.limeLevelMaxValue),
        tostring(fm ~= nil and fm.sprayLevelMaxValue),
        tostring(mi.plowingRequiredEnabled), tostring(fm ~= nil and fm.plowLevelMaxValue)))
    if Platform ~= nil and Platform.gameplay ~= nil then
        print(string.format("  Platform.gameplay: useLimeCounter=%s usePlowCounter=%s",
            tostring(Platform.gameplay.useLimeCounter), tostring(Platform.gameplay.usePlowCounter)))
    end
    print("  Precision Farming aktiv: " .. tostring(TaskAnalyzer.isPrecisionFarmingActive()))

    local cache = FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.cache or nil
    local treffer = nil
    for _, entry in ipairs((cache ~= nil and cache.fields) or {}) do
        if tonumber(entry.fieldInfo.fieldId) == gesucht then treffer = entry end
    end
    if treffer == nil then
        print("  Feld nicht in der Auswertung (gehoert es dir?)")
        return
    end

    local fi = treffer.fieldInfo
    print(string.format("  Feld %s, %.2f ha, aktuelle Frucht %s",
        tostring(fi.fieldId), (fi.area or 0) / 10000, tostring(fi.currentFruit)))

    -- Empfehlung mit Hysterese: zeigt, welche Frucht gemerkt ist und wie weit
    -- der naechste Kandidat entfernt liegt. Springt die Anzeige trotzdem, steht
    -- hier, ob der Abstand ueber der Schwelle lag oder das Gedaechtnis vergessen
    -- wurde (currentFruit/prevFruit geaendert).
    local recs = treffer.recommendations or {}
    local merk = (FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.lastTop or {})[fi.fieldId]
    local rang = {}
    for i = 1, math.min(3, #recs) do
        rang[#rang + 1] = string.format("%d. %s %.3f", i, tostring(recs[i].crop),
            recs[i].totalScore or 0)
    end
    print("  Empfehlung: " .. table.concat(rang, "  "))
    if recs[1] ~= nil and recs[2] ~= nil then
        local abstand = (recs[1].totalScore or 0) - (recs[2].totalScore or 0)
        print(string.format("    Abstand 1./2. = %.3f, Hysterese-Schwelle %.3f%s",
            abstand, FruchtfolgeAdvisor.HYSTERESE_SCORE or 0,
            (abstand < (FruchtfolgeAdvisor.HYSTERESE_SCORE or 0))
                and "  -> dicht beieinander, Gedaechtnis entscheidet" or ""))
    end
    print(string.format("    gemerkt: %s (bei currentFruit=%s prevFruit=%s), jetzt am Feld: currentFruit=%s prevFruit=%s",
        merk ~= nil and tostring(merk.crop) or "-",
        merk ~= nil and tostring(merk.currentFruit) or "-",
        merk ~= nil and tostring(merk.prevFruit) or "-",
        tostring(fi.currentFruit), tostring(fi.prevFruit)))
    if merk ~= nil and merk.gehaltenStatt ~= nil then
        print("    Hysterese hat im letzten Durchlauf gegriffen: " .. tostring(merk.crop)
            .. " gehalten statt " .. tostring(merk.gehaltenStatt))
    end

    local proben = feldProben(fi.field) or {}
    print("  Messpunkte: " .. tostring(#proben) .. " (Schwelle " .. tostring(TaskAnalyzer.SAMPLE_SHARE) .. ")")
    for i, s in ipairs(proben) do
        local kg = stickstoffKg(s.stickstoff)
        print(string.format("    [%d] frucht=%s wachstum=%s boden=%s (saatbereit=%s) unkraut=%s spray=%s kalk=%s walze=%s pflug=%s haecksel=%s N=%s (%s kg)",
            i, tostring(s.fruit), tostring(s.growth), tostring(s.boden),
            tostring(saatbereit(s.boden)), tostring(s.weed), tostring(s.spray),
            tostring(s.lime), tostring(s.roller), tostring(s.plow), tostring(s.shred),
            tostring(s.stickstoff), kg ~= nil and string.format("%.0f", kg) or "-"))
    end

    local idx = hauptFrucht(proben)
    local desc = nil
    if idx ~= 0 and g_fruitTypeManager ~= nil then
        desc = g_fruitTypeManager:getFruitTypeByIndex(idx)
    end
    if desc ~= nil then
        local ziel = stickstoffZiel(desc.name)
        print(string.format("  Hauptfrucht %s, Stickstoff-Ziel %s Stufen (%s kg)",
            tostring(desc.name), tostring(ziel),
            ziel ~= nil and string.format("%.0f", stickstoffKg(ziel) or 0) or "-"))

        -- Welcher Zweig greift? Genau hier entscheidet sich, ob ein Feld
        -- ueberhaupt Aufgaben bekommt (reif / verwelkt / wachsend / Stoppel).
        local minH = desc.minHarvestingGrowthState or 0
        local maxH = desc.maxHarvestingGrowthState or 0
        local welk = desc.witheredState
        local schnitt = desc.cutState or 0
        print(string.format("  Zustaende der Frucht: reif %s-%s, verwelkt %s, Schnitt %s, waechst nach %s",
            tostring(minH), tostring(maxH), tostring(welk), tostring(schnitt),
            tostring(desc.regrows)))
        -- Hackfruechte: ausgewachsen liegt UNTER der Erntereife, siehe zustandsPruefer
        local minP = desc.minPreparingGrowthState or -1
        if minP > 0 then
            print(string.format("  Hackfrucht: ausgewachsen %s-%s (Kraut ab = %s), zaehlt hier als reif",
                tostring(minP), tostring(desc.maxPreparingGrowthState),
                tostring(desc.preparedGrowthState)))
        end
        local p = TaskAnalyzer.zustandsPruefer(desc)
        local reif      = anteil(proben, p.reif)
        local verwelkt  = anteil(proben, p.verwelkt)
        local waechst   = anteil(proben, p.waechst)
        local abgeerntet = anteil(proben, p.abgeerntet)
        print(string.format("  Anteile: reif %.2f, verwelkt %.2f, wachsend %.2f, Stoppel %.2f (Schwelle %.2f)",
            reif, verwelkt, waechst, abgeerntet, TaskAnalyzer.SAMPLE_SHARE))
        if math.max(reif, verwelkt, waechst, abgeerntet) < TaskAnalyzer.SAMPLE_SHARE then
            print("    -> KEIN Zweig greift: das Feld bekommt gar keine Aufgabe")
        end
        if ziel == nil then
            print("    -> keine Duenge-Aufgabe: diese Frucht hat in PF keinen Stickstoffbedarf")
        end
    else
        print("  keine Hauptfrucht erkannt (Feld leer?) -> Duengen/Unkraut/Walzen entfallen")
    end

    local nullKalk = anteil(proben, function(s) return s.lime == 0 end)
    print(string.format("  Anteil Messpunkte mit Kalk 0: %.2f", nullKalk))
    if (fm == nil or (fm.limeLevelMaxValue or 0) <= 0) then
        print("    -> keine Kalk-Aufgabe moeglich: das Spiel fuehrt keinen Kalkzaehler")
    end

    -- Pfluegen: hier stand frueher nichts, obwohl genau diese Aufgabe auf
    -- Stoppelfeldern fehlte. Jetzt ist jeder Teil der Bedingung sichtbar.
    local nullPflug = anteil(proben, function(s) return s.plow == 0 end)
    local stoppelAnteil = 0
    if desc ~= nil and desc.regrows ~= true then
        stoppelAnteil = anteil(proben, TaskAnalyzer.zustandsPruefer(desc).abgeerntet)
    end
    local plowBoden = (desc == nil) or (stoppelAnteil >= TaskAnalyzer.SAMPLE_SHARE)
    print(string.format("  Anteil Messpunkte mit Pflug 0: %.2f (plowingRequiredEnabled=%s, Zaehler max=%s)",
        nullPflug, tostring(mi.plowingRequiredEnabled),
        tostring(fm ~= nil and fm.plowLevelMaxValue)))
    print(string.format("    -> Untergrund %s: %s", plowBoden and "passt" or "passt nicht",
        (desc == nil) and "Feld ohne Frucht (brach oder bearbeitet)"
            or string.format("Stoppel-Anteil %.2f, nachwachsend=%s",
                stoppelAnteil, tostring(desc.regrows))))
    if mi.plowingRequiredEnabled ~= true then
        print("    -> keine Pflug-Aufgabe: Pflicht-Pfluegen ist im Spielstand aus")
    elseif (fm == nil or (fm.plowLevelMaxValue or 0) <= 0) then
        print("    -> keine Pflug-Aufgabe moeglich: das Spiel fuehrt keinen Pflugzaehler")
    elseif plowBoden and nullPflug < TaskAnalyzer.SAMPLE_SHARE then
        print("    -> keine Pflug-Aufgabe: zu wenige Messpunkte mit Pflug 0")
    end
    print("=== FA-FELD-DUMP ENDE ===")
end

-- Was steckt im Cache, aus dem die Aufgaben entstehen? Entscheidend bei
-- "Liste leer, obwohl Felder/Tiere da sind": dann ist nicht die Auswertung
-- schuld, sondern der Cache war beim Aufbau noch leer (MP-Client, Besitzdaten
-- treffen verzoegert ein).
function TaskAnalyzer.cacheUebersicht()
    local c = FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.cache or nil
    if c == nil then
        print("  Cache: NICHT vorhanden")
        return
    end
    local eigene = 0
    for _, e in ipairs(c.fields or {}) do
        if e.fieldInfo ~= nil and e.fieldInfo.isOwn then eigene = eigene + 1 end
    end
    local lager = 0
    for _ in pairs(c.storage or {}) do lager = lager + 1 end
    local an = c.animals or {}
    local bedarf = 0
    for _ in pairs(an.feedNeeds or {}) do bedarf = bedarf + 1 end
    print(string.format("  Cache: Felder %d (eigene %d), Staelle %d, Futterarten %d, Lagerposten %d, Produktionen %d",
        #(c.fields or {}), eigene, #(an.husbandries or {}), bedarf, lager, #(c.productions or {})))
end

function TaskAnalyzer.debugDump()
    -- Erst den Zustand zeigen, mit dem die Liste im Menue gebaut wurde, DANN
    -- neu aufbauen: nur so sieht man, ob ein leerer Cache die Ursache war.
    print("=== FA-AUFGABEN ===")
    print("  Stand der Liste im Menue:")
    TaskAnalyzer.cacheUebersicht()
    print(string.format("  Aufgaben in der Liste: %d", #(TaskAnalyzer.tasks or {})))
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
        FruchtfolgeAdvisor.buildCache()
    end
    TaskAnalyzer.build()
    print("  Nach frischem Aufbau:")
    TaskAnalyzer.cacheUebersicht()
    -- Freiwillige Arbeiten sind auf einem MP-Client gesperrt, solange die
    -- Einstellungen des Servers fehlen. Das ist der haeufigste Grund fuer
    -- "Liste fast leer, obwohl der Cache voll ist".
    local cfgDa = (Bodengesundheit ~= nil) and Bodengesundheit.cfgEmpfangen or false
    local gesperrt = {}
    for art, _ in pairs(TaskAnalyzer.OPTIONALE_ARTEN) do
        if not TaskAnalyzer.istArtAn(art) then gesperrt[#gesperrt + 1] = art end
    end
    table.sort(gesperrt)
    print(string.format("  Server=%s, Einstellungen empfangen=%s, gesperrte Arten: %s",
        tostring(g_server ~= nil), tostring(cfgDa),
        (#gesperrt > 0) and table.concat(gesperrt, ",") or "keine"))
    print(string.format("=== %d Aufgaben (farmId=%s, PF=%s) ===", #TaskAnalyzer.tasks,
        tostring(farmIdLokal()),
        tostring(TaskAnalyzer.isPrecisionFarmingActive())))
    for _, t in ipairs(TaskAnalyzer.tasks) do
        local st, wer = TaskAnalyzer.statusOf(t)
        print(string.format("  [%d] %-10s %-40s %-10s %-24s %s %s", t.prio, t.cat, t.text,
            t.value, t.detail, st, wer or ""))
    end

    -- Anbauplanung nachvollziehbar machen: Hier entstand der 644-ha-Ausreisser
    -- bei den Zuckerrueben. "abzug" ist der Produktionsanteil, der fuer die
    -- Planung nicht zaehlt (voller Ausgang, satt oder reiner Verkauf).
    local diag = TaskAnalyzer.planDiag
    if type(diag) == "table" and next(diag) ~= nil then
        print("  Anbauplanung (Liter je Monat, Flaechen in ha):")
        local keys = {}
        for k in pairs(diag) do keys[#keys + 1] = k end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local d = diag[k]
            print(string.format(
                "    %-18s roh=%.0f davon Produktion=%.0f abzug=%.0f -> Plan=%.0f"
                .. " | Lager=%.0f waechst=%.0f fehlt=%.0f -> %.1f ha (Hof %.1f ha)",
                k, d.roh or 0, d.prod or 0, d.abzug or 0, d.plan or 0,
                d.bestand or 0, d.waechst or 0, d.fehlt or 0, d.ha or 0, d.hofHa or 0))
        end
    end
end
