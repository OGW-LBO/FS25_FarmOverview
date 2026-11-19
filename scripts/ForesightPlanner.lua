-- ForesightPlanner.lua
-- Plant für jedes eigene Feld eine optimale Fruchtfolge über N Saisons voraus.
-- Berücksichtigt dabei kumulierten Lagerbestand, Tierverbrauch und PF-Boni.
--
-- Algorithmus: Greedy-Vorwärtsplanung mit simuliertem Lager-State.
-- Für jede Saison wird die beste Frucht gewählt und der Lager-State
-- entsprechend der geschätzten Ernte + fortlaufendem Verbrauch angepasst.

ForesightPlanner = {}

ForesightPlanner.SEASONS_AHEAD = 3   -- Wie viele Saisons voraus planen

-- Monatlicher Verbrauch simuliert über eine Saison (= 3 Monate Näherung)
local MONTHS_PER_SEASON = 3

-- ─────────────────────────────────────────────────────────────────────────────
-- LAGER-SIMULATION
-- ─────────────────────────────────────────────────────────────────────────────

-- Erstellt eine tiefe Kopie der storageTotals-Tabelle
local function cloneStorage(totals)
    local copy = {}
    for k, v in pairs(totals) do copy[k] = v end
    return copy
end

-- Zieht einen Saison-Verbrauch vom simulierten Lager ab
-- (Tierfutter + Einstreu + Eingangsbedarf aktiver Produktionen)
local function applyConsumption(simStorage, animalNeeds)
    for fillType, monthlyAmount in pairs(animalNeeds.feedNeeds) do
        local key = string.upper(fillType)
        simStorage[key] = math.max(0, (simStorage[key] or 0) - monthlyAmount * MONTHS_PER_SEASON)
    end
    for fillType, monthlyAmount in pairs(animalNeeds.beddingNeeds) do
        local key = string.upper(fillType)
        simStorage[key] = math.max(0, (simStorage[key] or 0) - monthlyAmount * MONTHS_PER_SEASON)
    end
    if animalNeeds.productionNeeds ~= nil then
        for fillType, monthlyAmount in pairs(animalNeeds.productionNeeds) do
            local key = string.upper(fillType)
            simStorage[key] = math.max(0, (simStorage[key] or 0) - monthlyAmount * MONTHS_PER_SEASON)
        end
    end
end

-- Fügt geschätzten Ernte-Ertrag dem simulierten Lager hinzu
local function applyHarvest(simStorage, candidate, fieldArea)
    local products = CropRotationData.FRUIT_PRODUCTS[candidate]
    if products == nil then return end

    -- Ertrag in L/ha aus den Krebach-Map-Daten
    local ha    = (fieldArea or 0) / 10000
    local yield = (CropRotationData.YIELD_L_PER_HA[candidate] or 5000) * ha

    -- Hauptprodukt bekommt volle Menge, Nebenprodukt (Stroh) ~40%
    for i, product in ipairs(products) do
        local key = string.upper(product)
        local amount = (i == 1) and yield or (yield * 0.4)
        simStorage[key] = (simStorage[key] or 0) + amount
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- WÄHLT DIE BESTE FRUCHT FÜR EINE SAISON IN DER SIMULATION
-- ─────────────────────────────────────────────────────────────────────────────

-- Beste Frucht fuer eine Saison.
-- hist1 = Vorfrucht, hist2 = Vorvorfrucht der simulierten Saison.
-- fullHistory (neueste zuerst) deckt Anbaupausen ueber das
-- 2-Saisons-Fenster hinaus ab (z.B. Raps: 4 Saisons Pause).
local function chooseBestCrop(hist1, hist2, fullHistory, simStorage, animalNeeds, fieldArea)
    local recs = RecommendationEngine.recommendForField(
        { prevFruit = hist2, currentFruit = hist1, area = fieldArea },
        simStorage,
        animalNeeds
    )

    local best = nil
    for _, rec in ipairs(recs) do
        local penalty = 0
        local bp = CropRotationData.getBreakPeriods(rec.crop)
        for i = 1, math.min(bp, #fullHistory) do
            if fullHistory[i] == rec.crop then
                penalty = penalty + 0.25
            end
        end
        local score = rec.totalScore - penalty
        if best == nil or score > best._planScore then
            rec._planScore = score
            best = rec
        end
    end

    return best
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HAUPTFUNKTION: Vorausplanung für ein einzelnes Feld
-- ─────────────────────────────────────────────────────────────────────────────
-- Rückgabe: Array von N Einträgen { season, crop, pfBonus, projStorage }

function ForesightPlanner.planField(fieldInfo, storageTotals, animalNeeds)
    local plan       = {}
    local simStorage = cloneStorage(storageTotals)

    -- Rotations-Historie: bei brachem Feld ist prevFruit die eigentliche Vorfrucht
    local hist1 = fieldInfo.currentFruit or fieldInfo.prevFruit
    local hist2 = (fieldInfo.currentFruit ~= nil) and fieldInfo.prevFruit or nil
    -- Volle Historie (neueste zuerst) fuer Anbaupausen-Pruefung
    local fullHistory = {}
    if hist1 ~= nil then table.insert(fullHistory, hist1) end
    if hist2 ~= nil then table.insert(fullHistory, hist2) end

    for season = 1, ForesightPlanner.SEASONS_AHEAD do
        -- Verbrauch dieser Saison abziehen (Tiere fressen kontinuierlich)
        applyConsumption(simStorage, animalNeeds)

        -- Beste Frucht für diese Saison finden
        local best = chooseBestCrop(hist1, hist2, fullHistory, simStorage, animalNeeds, fieldInfo.area)

        if best == nil then
            -- Fallback: erste verfügbare Frucht
            best = {
                crop        = "WHEAT",
                displayName = "Weizen",
                pfBonus     = 0,
                totalScore  = 0,
            }
        end

        -- Ernte dieser Saison dem simulierten Lager hinzufügen
        applyHarvest(simStorage, best.crop, fieldInfo.area)

        -- Kritische Fülltypen nach dieser Saison ermitteln
        local critical = ForesightPlanner.getCriticalProducts(simStorage, animalNeeds)

        table.insert(plan, {
            season      = season,
            crop        = best.crop,
            displayName = best.displayName,
            pfBonus     = best.pfBonus,
            score       = best.totalScore,
            critical    = critical,
        })

        -- Historie weiterschieben
        hist2 = hist1
        hist1 = best.crop
        table.insert(fullHistory, 1, best.crop)
    end

    return plan
end

-- Gibt Produkte zurück deren simulierter Bestand kritisch niedrig ist.
-- Mischfutter-/Trog-Deckung wird angerechnet; Keys bleiben uppercase
-- (Anzeige uebersetzt sie via FruchtfolgeAdvisor.fillName).
function ForesightPlanner.getCriticalProducts(simStorage, animalNeeds)
    local critical = {}
    local mixed    = animalNeeds.mixedCoverMonths or {}
    for fillType, monthlyNeed in pairs(animalNeeds.feedNeeds) do
        local key   = string.upper(fillType)
        local stock = simStorage[key] or 0
        if monthlyNeed > 0 then
            local months = (stock / monthlyNeed) + (mixed[key] or 0)
            if months < 1.5 then
                table.insert(critical, key)
            end
        end
    end
    for fillType, monthlyNeed in pairs(animalNeeds.beddingNeeds) do
        local key   = string.upper(fillType)
        local stock = simStorage[key] or 0
        if monthlyNeed > 0 and (stock / monthlyNeed) < 1.5 then
            local found = false
            for _, c in ipairs(critical) do if c == key then found = true end end
            if not found then table.insert(critical, key) end
        end
    end
    if animalNeeds.productionNeeds ~= nil then
        for fillType, monthlyNeed in pairs(animalNeeds.productionNeeds) do
            local key   = string.upper(fillType)
            local stock = simStorage[key] or 0
            if monthlyNeed > 0 and (stock / monthlyNeed) < 1.5 then
                local found = false
                for _, c in ipairs(critical) do if c == key then found = true end end
                if not found then table.insert(critical, key) end
            end
        end
    end
    return critical
end

-- ─────────────────────────────────────────────────────────────────────────────
-- PLANUNG FÜR ALLE EIGENEN FELDER
-- ─────────────────────────────────────────────────────────────────────────────

function ForesightPlanner.planAllFields()
    local fields        = FieldAnalyzer.getOwnFields()
    local storageTotals = StorageAnalyzer.getTotals()
    local animalNeeds   = AnimalAnalyzer.getNeedsPerMonth(storageTotals)

    -- Wichtig: Die Felder teilen sich den gleichen Gesamtlagerbestand,
    -- aber jedes Feld plant seinen eigenen Rotationspfad unabhängig.
    -- (Für präzisere Planung müsste man alle Felder gemeinsam optimieren —
    -- das wäre NP-schwer; Greedy je Feld ist der praktikable Kompromiss.)

    local allPlans = {}
    for _, fieldInfo in ipairs(fields) do
        if fieldInfo.isOwn then
            local plan = ForesightPlanner.planField(fieldInfo, storageTotals, animalNeeds)
            table.insert(allPlans, {
                fieldInfo = fieldInfo,
                plan      = plan,
            })
        end
    end

    return allPlans, storageTotals, animalNeeds
end
