-- ProductionAnalyzer.lua
-- Liest alle Produktionspunkte der Farm (inkl. Futtermischer-Produktionen).
--
-- Verifiziert per LUADOC (Misc/ProductionChainManager):
--   g_currentMission.productionChainManager:getProductionPointsForFarmId(farmId)
--
-- Die innere Struktur der Produktionspunkte (productions, storage,
-- activeProductions) ist NICHT in der LUADOC dokumentiert — alle Zugriffe
-- daher defensiv (Typ- und Existenzpruefungen). Bekanntes Muster:
--   pp.storage.fillLevels       -> Tabelle FillTypeIndex -> Liter
--   pp.productions              -> Rezepte { name, inputs={ {type,amount} }, outputs={...} }
--   pp.activeProductions        -> aktuell laufende Rezepte
ProductionAnalyzer = {}

function ProductionAnalyzer.getLocalFarmId()
    -- Zentrale MP-sichere Kette in FieldAnalyzer
    if FieldAnalyzer ~= nil and FieldAnalyzer.getLocalFarmId ~= nil then
        return FieldAnalyzer.getLocalFarmId()
    end
    if g_currentMission and g_currentMission.player then
        return g_currentMission.player.farmId
    end
    return 1
end

-- Name eines Produktionspunkts (mehrere Pfade, defensiv)
local function nichtLeer(s)
    return type(s) == "string" and s ~= ""
end

local function resolveName(pp)
    if pp.getName ~= nil then
        local n = pp:getName()
        if nichtLeer(n) then return n end
    end
    local owner = pp.owningPlaceable
    if type(owner) == "table" and owner.getName ~= nil then
        local n = owner:getName()
        if nichtLeer(n) then return n end
    end
    if nichtLeer(pp.name) then return pp.name end
    return "Produktion"
end

-- FillType-Index -> Schluessel in Grossbuchstaben, "?" wenn unbekannt
local function fillInfo(idx)
    if g_fillTypeManager == nil or g_fillTypeManager.getFillTypeByIndex == nil then
        return "?"
    end
    local desc = g_fillTypeManager:getFillTypeByIndex(idx)
    if desc ~= nil and type(desc.name) == "string" then
        return string.upper(desc.name)
    end
    return "?"
end

-- Zyklen pro Monat (Felder nicht in LUADOC dokumentiert).
-- FS25: 1 Monat = 1 Tag = 24 Stunden.
local function zyklenProMonat(prod)
    if type(prod.cyclesPerMonth) == "number" and prod.cyclesPerMonth > 0 then
        return prod.cyclesPerMonth
    elseif type(prod.cyclesPerHour) == "number" and prod.cyclesPerHour > 0 then
        return prod.cyclesPerHour * 24
    elseif type(prod.cyclesPerMinute) == "number" and prod.cyclesPerMinute > 0 then
        return prod.cyclesPerMinute * 60 * 24
    end
    return nil
end

-- Fassungsvermoegen eines Fuelltyps im Lager des Produktionspunkts.
-- Storage:getCapacity(fillType) liefert capacities[fillType] oder capacity
-- (gleicher Weg wie im StorageAnalyzer). Ohne Angabe nil - dann wird nirgends
-- "voll" angenommen.
local function kapazitaetFuer(storage, idx)
    if type(storage) ~= "table" then return nil end
    if type(storage.getCapacity) == "function" then
        local c = storage:getCapacity(idx)
        if type(c) == "number" and c > 0 then return c end
    end
    if type(storage.capacities) == "table" and type(storage.capacities[idx]) == "number"
            and storage.capacities[idx] > 0 then
        return storage.capacities[idx]
    end
    if type(storage.capacity) == "number" and storage.capacity > 0 then
        return storage.capacity
    end
    return nil
end

-- Ein Rezept eines Produktionspunkts in eine flache Struktur lesen.
local function readRecipe(prod, levels, activeSet, storage)
    local r = {
        name           = "Rezept",
        active         = false,
        inputs         = {},
        outputs        = {},
        inputsPerMonth = {},
    }
    if nichtLeer(prod.name) then r.name = prod.name end
    if activeSet[prod] == true or (prod.id ~= nil and activeSet[prod.id] == true) then
        r.active = true
    end

    local cyclesPerMonth = zyklenProMonat(prod)

    if type(prod.inputs) == "table" then
        for _, inp in pairs(prod.inputs) do
            if type(inp) == "table" and type(inp.type) == "number" then
                local key = fillInfo(inp.type)
                local perMonth = 0
                if cyclesPerMonth ~= nil and type(inp.amount) == "number" then
                    perMonth = inp.amount * cyclesPerMonth
                end
                table.insert(r.inputs, {
                    fillKey  = key,
                    level    = levels[inp.type] or 0,
                    perMonth = perMonth,
                })
                if r.active and perMonth > 0 and key ~= "?" then
                    r.inputsPerMonth[key] = (r.inputsPerMonth[key] or 0) + perMonth
                end
            end
        end
    end

    if type(prod.outputs) == "table" then
        for _, out in pairs(prod.outputs) do
            if type(out) == "table" and type(out.type) == "number" then
                table.insert(r.outputs, {
                    fillKey  = fillInfo(out.type),
                    level    = levels[out.type] or 0,
                    -- Nur gesetzt, wenn das Spiel eine Kapazitaet fuehrt. Ein
                    -- voller Ausgang legt die Anlage still - das braucht die
                    -- Bedarfsrechnung (siehe getInputNeedsPerMonth).
                    capacity = kapazitaetFuer(storage, out.type),
                })
            end
        end
    end

    return r
end

-- Liest einen Produktionspunkt in eine flache Struktur.
local function readProductionPoint(pp)
    local entry = {
        name    = resolveName(pp),
        recipes = {},
    }

    -- Punkt-Lager (Ein- und Ausgaenge teilen sich das Storage)
    local levels = {}
    if type(pp.storage) == "table" and type(pp.storage.fillLevels) == "table" then
        for idx, v in pairs(pp.storage.fillLevels) do
            if type(idx) == "number" and type(v) == "number" then
                levels[idx] = v
            end
        end
    end
    entry.levels = levels

    -- Aktive Rezepte als Set (Referenz und id)
    local activeSet = {}
    if type(pp.activeProductions) == "table" then
        for _, ap in pairs(pp.activeProductions) do
            if ap ~= nil then
                activeSet[ap] = true
                if type(ap) == "table" and ap.id ~= nil then activeSet[ap.id] = true end
            end
        end
    end

    -- Rezepte lesen
    if type(pp.productions) == "table" then
        for _, prod in pairs(pp.productions) do
            if type(prod) == "table" then
                table.insert(entry.recipes, readRecipe(prod, levels, activeSet, pp.storage))
            end
        end
    end

    return entry
end

-- Monatlicher Eingangsbedarf aller AKTIVEN Rezepte (Liter/Monat je FillType).
-- Fliesst in die Empfehlungslogik ein: was Produktionen verbrauchen,
-- erzeugt Anbau-Bedarf.
-- Ab diesem Fuellstand des Ausgangs gilt eine Anlage als blockiert. Gleiche
-- Schwelle wie die Aufgabe "Ausgang voll" (TaskAnalyzer.OUTPUT_HIGH).
ProductionAnalyzer.AUSGANG_VOLL = 0.90

-- Laeuft das Rezept gerade gegen einen vollen Ausgang? Dann steht die Anlage
-- und verbraucht nichts - ihr Eingang ist also kein Bedarf. Ohne diese Pruefung
-- meldete der Zuckerrueben-Haecksler auf Bergisch Land weiter seinen vollen
-- Durchsatz als Bedarf, obwohl sein Ausgang randvoll stand (31.10.2026).
function ProductionAnalyzer.istAusgangVoll(recipe)
    for _, out in ipairs((recipe ~= nil and recipe.outputs) or {}) do
        local kap = out.capacity
        if type(kap) == "number" and kap > 0
                and (out.level or 0) / kap >= ProductionAnalyzer.AUSGANG_VOLL then
            return true
        end
    end
    return false
end

function ProductionAnalyzer.getInputNeedsPerMonth(productions)
    local needs = {}
    if productions == nil then return needs end
    for _, p in ipairs(productions) do
        if p.recipes ~= nil then
            for _, r in ipairs(p.recipes) do
                if r.active and r.inputsPerMonth ~= nil
                        and not ProductionAnalyzer.istAusgangVoll(r) then
                    for key, amt in pairs(r.inputsPerMonth) do
                        needs[key] = (needs[key] or 0) + amt
                    end
                end
            end
        end
    end
    return needs
end

-- Besitzer-Farm eines Produktionspunkts (direkt oder ueber das Placeable).
local function besitzerVon(pp)
    if type(pp) ~= "table" then return nil end
    if pp.ownerFarmId ~= nil then return pp.ownerFarmId end
    if type(pp.owningPlaceable) == "table" then return pp.owningPlaceable.ownerFarmId end
    return nil
end

-- Alle Produktionspunkte der Farm.
function ProductionAnalyzer.getProductions(farmId)
    local result = {}
    local pcm = nil
    if g_currentMission ~= nil then pcm = g_currentMission.productionChainManager end
    if pcm == nil then
        print("[FA] ProductionAnalyzer: kein productionChainManager")
        return result
    end

    local points = nil
    if pcm.getProductionPointsForFarmId ~= nil then
        points = pcm:getProductionPointsForFarmId(farmId)
    end
    if points == nil and type(pcm.productionPoints) == "table" then
        -- Fallback: alle Punkte, nach Besitzer filtern
        points = {}
        for _, pp in pairs(pcm.productionPoints) do
            if besitzerVon(pp) == farmId then
                table.insert(points, pp)
            end
        end
    end
    if points == nil then return result end

    for _, pp in pairs(points) do
        if type(pp) == "table" then
            table.insert(result, readProductionPoint(pp))
        end
    end

    return result
end
