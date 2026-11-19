-- RecommendationEngine.lua
-- Vollautomatische Score-Berechnung: Gewichte werden dynamisch aus dem
-- tatsächlichen Spielzustand abgeleitet — keine manuelle Konfiguration nötig.
--
-- Faktoren:
--   rotationScore  — PF Fruchtfolge-Qualität (vorherige Frucht → Kandidat)
--   storageScore   — wie dringend fehlt dieses Produkt im Lager
--   animalScore    — wie viele Monate Futterdeckung fehlen
--   beddingScore   — Einstreubedarf unter Schwellwert
--   tmrScore       — fehlende TMR-Zutaten
--
-- "Weitblick": Die Scores berücksichtigen einen gleitenden 3-Monats-Verbrauch
-- und extrapolieren ob der Bestand bis zur nächsten Ernte reicht.

RecommendationEngine = {}

-- Ernte-Vorlaufzeit in Monaten: aus CropRotationData (Krebach-Map-Daten)
RecommendationEngine.GROW_TIME_MONTHS = CropRotationData.GROW_TIME_MONTHS

-- Planungsziel: Vorrat soll bis zur naechsten Ernte reichen (~8 Monate).
-- Unter CRITICAL_MONTHS ist ein Produkt akut knapp (Dringlichkeit 1.0),
-- bis TARGET_MONTHS faellt die Dringlichkeit linear auf 0 ab.
-- So werden so viele Felder fuer Futter/Produktionsbedarf eingeplant,
-- bis der Gesamtbedarf (Tiere x Anzahl + Produktionszyklen) gedeckt ist —
-- danach uebernehmen Fruchtfolge und Marktwert die Empfehlung.
local CRITICAL_MONTHS  = 2.0
local WARNING_MONTHS   = 8.0
-- Absoluter Minimalbestand (Liter) ab dem ein Produkt als "vorhanden" gilt
local MIN_STOCK        = 500

-- ── MARKTWERT (Spielspass: Ueberschuss-Felder bauen Verkaufsfruechte an) ──

-- Rueckfallpreise €/L falls der Spielpreis nicht lesbar ist
local FALLBACK_PRICES = {
    WHEAT=0.39, WINTERWHEAT=0.42, BARLEY=0.36, WINTERBARLEY=0.38, RYE=0.36,
    TRITICALE=0.40, SPELT=0.65, OAT=0.45, CANOLA=0.75, SUNFLOWER=0.80,
    SOYBEAN=0.85, MAIZE=0.38, SORGHUM=0.45, POTATO=0.18, SUGARBEET=0.12,
    BEETROOT=0.45, CARROT=0.35, PARSNIP=0.40, GREENBEAN=0.90, PEA=0.60,
    SPINACH=0.55, COTTON=1.25, SILAGE=0.15, GRASS=0.05, DRYGRASS=0.12,
    ALFALFA=0.14, CLOVER=0.13,
}

local function getPricePerLiter(fillKey)
    local price = nil
    if fillKey ~= nil and g_fillTypeManager ~= nil
            and g_fillTypeManager.getFillTypeByName ~= nil then
        local desc = g_fillTypeManager:getFillTypeByName(fillKey)
        if desc ~= nil and type(desc.pricePerLiter) == "number" and desc.pricePerLiter > 0 then
            price = desc.pricePerLiter
        end
    end
    return price or FALLBACK_PRICES[fillKey] or 0
end

-- Erloes/ha je Kandidat, normiert auf den besten (0..1).
-- Einmal berechnet und gecacht — Basispreise aendern sich nicht.
local marketScoreCache = nil

-- Muss aufgerufen werden, wenn sich die Fruchtliste aendert (Fruechte der Map
-- uebernommen oder eine Frucht ab-/angewaehlt). Der Cache ist auf den besten
-- Kandidaten NORMIERT - faellt der weg, sind alle uebrigen Werte falsch, und die
-- Abwahl haette gar keine Wirkung.
function RecommendationEngine.invalidateMarketCache()
    marketScoreCache = nil
end
local function getMarketScore(candidate)
    if marketScoreCache == nil then
        marketScoreCache = {}
        local maxRev = 0
        for _, cand in ipairs(CropRotationData.getAllCrops()) do
            local products = CropRotationData.FRUIT_PRODUCTS[cand]
            local rev = 0
            if products ~= nil and products[1] ~= nil then
                rev = getPricePerLiter(products[1])
                    * (CropRotationData.YIELD_L_PER_HA[cand] or 0)
            end
            marketScoreCache[cand] = rev
            if rev > maxRev then maxRev = rev end
        end
        if maxRev > 0 then
            for k, v in pairs(marketScoreCache) do
                marketScoreCache[k] = v / maxRev
            end
        end
    end
    return marketScoreCache[candidate] or 0
end

-- ─────────────────────────────────────────────────────────────────────────────
-- INTERNE HILFSFUNKTIONEN
-- ─────────────────────────────────────────────────────────────────────────────

-- Monatliche Entnahmerate eines FüllTyps:
-- Tierfutter + Einstreu + Eingangsbedarf aktiver Produktionen.
local function getMonthlyConsumption(fillTypeKey, animalNeeds)
    local feed    = animalNeeds.feedNeeds[fillTypeKey]    or 0
    local bedding = animalNeeds.beddingNeeds[fillTypeKey] or 0
    local prod    = 0
    if animalNeeds.productionNeeds ~= nil then
        prod = animalNeeds.productionNeeds[fillTypeKey] or 0
    end
    return feed + bedding + prod
end

-- Wieviele Monate reicht der aktuelle Bestand bei gegebenem Verbrauch?
local function monthsCoverage(stock, monthlyUse)
    if monthlyUse <= 0 then
        return stock > MIN_STOCK and 99 or 0
    end
    return stock / monthlyUse
end

-- Dringlichkeits-Kurve: 0 = kein Bedarf, 1 = kritisch
-- Fällt weich ab zwischen WARNING_MONTHS und CRITICAL_MONTHS
local function urgency(months)
    if months >= WARNING_MONTHS  then return 0.0 end
    if months <= CRITICAL_MONTHS then return 1.0 end
    return 1.0 - ((months - CRITICAL_MONTHS) / (WARNING_MONTHS - CRITICAL_MONTHS))
end

-- Gibt für einen Kandidaten zurück wie viel Reichweite das Lager nach
-- der erwarteten Ernte haben wird (Weitblick)
local function projectedCoverageAfterHarvest(candidate, storageTotals, animalNeeds, estimatedYieldLiters)
    local products = CropRotationData.FRUIT_PRODUCTS[candidate]
    if products == nil then return 0 end

    local worst = 99
    for _, product in ipairs(products) do
        local key        = string.upper(product)
        local stock      = (storageTotals[key] or 0) + estimatedYieldLiters
        local monthlyUse = getMonthlyConsumption(key, animalNeeds)
        local growMonths = CropRotationData.getGrowTimeMonths(candidate) or 3

        -- Bestand zum Erntezeitpunkt = aktueller Bestand – Verbrauch bis Ernte
        local stockAtHarvest = math.max(0, (storageTotals[key] or 0) - monthlyUse * growMonths)
        local afterHarvest   = stockAtHarvest + estimatedYieldLiters
        local coverage       = monthsCoverage(afterHarvest, monthlyUse)
        worst = math.min(worst, coverage)
    end
    return worst
end

-- Ertragsschätzung in Litern: L/ha aus den Krebach-Map-Daten
local function estimateYield(fieldArea, candidate)
    local ha = (fieldArea or 0) / 10000
    return (CropRotationData.YIELD_L_PER_HA[candidate] or 5000) * ha
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SCORE-BERECHNUNG
-- ─────────────────────────────────────────────────────────────────────────────

-- Fruchtfolge-Score nach dem Referenz-System (FS25_CropRotation):
-- Bei brachem Feld (currentFruit=nil) ist fi.prevFruit (gerade geerntete Frucht)
-- die relevante Vorfrucht. Brache-Bonus greift nur wenn wirklich keine Historie.
local function calcRotationScore(fieldInfo, candidate)
    local rotPrev     = fieldInfo.currentFruit or fieldInfo.prevFruit
    local rotPrevPrev = (fieldInfo.currentFruit ~= nil) and fieldInfo.prevFruit or nil
    local bonus = CropRotationData.getPFBonus(rotPrev, candidate, rotPrevPrev)
    local s = (bonus + 25) / 40
    if s < 0 then s = 0 end
    if s > 1 then s = 1 end
    return s, bonus
end

-- Lagerbedarf-Score: kombiniert aktuellen Bestand + Weitblick nach Ernte
local function calcStorageScore(candidate, storageTotals, animalNeeds, fieldArea)
    local products = CropRotationData.FRUIT_PRODUCTS[candidate]
    if products == nil or #products == 0 then return 0 end

    local yield = estimateYield(fieldArea, candidate)

    -- Schlimmste Deckung über alle Produkte dieser Frucht
    local worstCurrent  = 99
    local worstFuture   = 99

    for _, product in ipairs(products) do
        local key        = string.upper(product)
        local stock      = storageTotals[key] or 0
        local monthlyUse = getMonthlyConsumption(key, animalNeeds)

        local current = monthsCoverage(stock, monthlyUse)
        worstCurrent  = math.min(worstCurrent, current)

        -- Weitblick: Deckung nach Ernte
        local growMonths    = CropRotationData.getGrowTimeMonths(candidate) or 3
        local stockAtHarvest = math.max(0, stock - monthlyUse * growMonths)
        local afterHarvest   = stockAtHarvest + yield
        local future         = monthsCoverage(afterHarvest, monthlyUse)
        worstFuture = math.min(worstFuture, future)
    end

    -- Wird aktuell verbraucht? → Dringlichkeit des aktuellen Bestands zählt mehr
    local hasConsumption = false
    for _, product in ipairs(products) do
        local key = string.upper(product)
        if getMonthlyConsumption(key, animalNeeds) > 0 then
            hasConsumption = true
            break
        end
    end

    if hasConsumption then
        -- 60% aktueller Bedarf, 40% Weitblick nach Ernte
        return urgency(worstCurrent) * 0.6 + urgency(worstFuture) * 0.4
    else
        -- Kein laufender Verbrauch: nur prüfen ob Lager leer ist
        local products2 = CropRotationData.FRUIT_PRODUCTS[candidate]
        local total = 0
        for _, product in ipairs(products2) do
            total = total + (storageTotals[string.upper(product)] or 0)
        end
        if total < MIN_STOCK then return 0.3 end  -- leeres Lager, aber kein Bedarf
        return 0.0
    end
end

-- Tierfutter-Score: direkte Abdeckungslücke pro Tierprodukt.
-- Fertiges Mischfutter (FORAGE/PIGFOOD/CHICKENFOOD) verlängert die Deckung.
local function calcAnimalScore(candidate, animalNeeds, storageTotals)
    if animalNeeds == nil then return 0 end
    local products = CropRotationData.FRUIT_PRODUCTS[candidate]
    if products == nil then return 0 end

    local maxUrgency = 0

    for _, product in ipairs(products) do
        local key        = string.upper(product)
        local feed       = animalNeeds.feedNeeds[key] or 0
        local bedding    = animalNeeds.beddingNeeds[key] or 0
        local totalNeed  = feed + bedding
        if totalNeed > 0 then
            local stock    = storageTotals[key] or 0
            local months   = monthsCoverage(stock, totalNeed)
            local mixed    = animalNeeds.mixedCoverMonths
            if mixed ~= nil and mixed[key] ~= nil then
                months = months + mixed[key]
            end
            maxUrgency = math.max(maxUrgency, urgency(months))
        end
    end

    return maxUrgency
end

-- TMR-Score: anteilige Dringlichkeit fehlender TMR-Zutaten
local function calcTMRScore(candidate, animalNeeds, storageTotals)
    if not animalNeeds.hasTMR then return 0 end

    local products = CropRotationData.FRUIT_PRODUCTS[candidate]
    if products == nil then return 0 end

    local score = 0
    for _, product in ipairs(products) do
        local key      = string.upper(product)
        local tmrShare = AnimalAnalyzer.TMR_RECIPE[key] or 0
        -- Zutaten, die bereits direktes Tierfutter sind (Silage, Heu),
        -- zaehlt calcAnimalScore — hier ueberspringen, sonst zaehlt
        -- dieselbe Luecke doppelt und eine Frucht dominiert.
        if tmrShare > 0 and (animalNeeds.feedNeeds[key] or 0) == 0 then
            local stock    = storageTotals[key] or 0
            -- TMR-Bedarf: monatlicher Bedarf der Kühe × Anteil dieses Ingredients
            local cowFeed  = animalNeeds.feedNeeds["SILAGE"] or 0  -- Proxy: TMR-Menge ≈ Silage-Bedarf
            local tmrMonthNeed = cowFeed * tmrShare
            local months   = monthsCoverage(stock, tmrMonthNeed)
            -- Fertige Mischration im Lager reduziert die Dringlichkeit
            local mixed = animalNeeds.mixedCoverMonths
            if mixed ~= nil and mixed[key] ~= nil then
                months = months + mixed[key]
            end
            score = math.max(score, urgency(months) * tmrShare)
        end
    end
    return math.min(score, 1.0)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- DYNAMISCHE GEWICHTUNG
-- ─────────────────────────────────────────────────────────────────────────────
-- Die Gewichte werden aus dem aktuellen Spielzustand abgeleitet:
-- Gibt es keine Tiere → Tierfutter-Gewicht fällt auf 0.
-- Sind alle Lager voll → Storage-Gewicht sinkt.
-- So bleibt immer das wichtigste Kriterium dominant.

local function computeAutoWeights(animalNeeds, storageTotals)
    local hasAnimals = false
    local hasTMR     = animalNeeds.hasTMR
    local storageEmpty = false

    if animalNeeds.husbandries and #animalNeeds.husbandries > 0 then
        hasAnimals = true
    end

    -- Prüfe ob irgendein Produkt wirklich knapp ist
    local totalStock = 0
    for _, v in pairs(storageTotals) do totalStock = totalStock + v end
    if totalStock < 5000 then storageEmpty = true end

    -- Basisgewichte (Markt = Spielspass: Geld verdienen mit Ueberschussflaechen)
    local w = {
        rotation = 0.32,
        storage  = 0.22,
        animal   = hasAnimals and 0.26 or 0.0,
        tmr      = (hasAnimals and hasTMR) and 0.08 or 0.0,
        market   = 0.12,
    }
    -- Reiner Ackerbau-Betrieb ohne Tiere: Markt deutlich wichtiger
    if not hasAnimals then
        w.market = 0.30
    end

    -- Lager leer: Storage-Gewicht erhöhen
    if storageEmpty then
        w.storage = w.storage + 0.10
        w.rotation = w.rotation - 0.05
    end

    -- Normieren auf Summe 1.0
    local sum = w.rotation + w.storage + w.animal + w.tmr + w.market
    if sum > 0 then
        for k in pairs(w) do w[k] = w[k] / sum end
    end

    return w
end

-- ─────────────────────────────────────────────────────────────────────────────
-- EMPFEHLUNG PRO FELD
-- ─────────────────────────────────────────────────────────────────────────────

-- usageCounts (optional): wie oft eine Frucht bereits als Top-Empfehlung
-- auf anderen Feldern vergeben wurde -> sanfte Abwertung fuer Abwechslung
-- ueber den ganzen Hof.
function RecommendationEngine.recommendForField(fieldInfo, storageTotals, animalNeeds, usageCounts)
    local w          = computeAutoWeights(animalNeeds, storageTotals)
    local candidates = CropRotationData.getAllCrops()
    local results    = {}

    for _, candidate in ipairs(candidates) do
        if candidate ~= fieldInfo.currentFruit then
            local rScore, pfBonus = calcRotationScore(fieldInfo, candidate)
            local sScore = calcStorageScore(candidate, storageTotals, animalNeeds, fieldInfo.area)
            local aScore = calcAnimalScore(candidate, animalNeeds, storageTotals)
            local tScore = calcTMRScore(candidate, animalNeeds, storageTotals)
            local mScore = getMarketScore(candidate)

            local total = rScore * w.rotation
                        + sScore * w.storage
                        + aScore * w.animal
                        + tScore * w.tmr
                        + mScore * (w.market or 0)

            -- Zwischenfruechte (kein Erntegut): als Bodenkur bewerten.
            -- Bonus steigt, je schlechter die Bodengesundheit des Feldes ist
            -- (gesundes Feld -> Verkaufsfruechte gewinnen; ausgelaugtes Feld
            -- -> Zwischenfrucht klettert nach oben). Defensiv, ohne harte
            -- Abhaengigkeit zum Bodengesundheit-Modul.
            if CropRotationData.isCoverCrop(candidate) then
                local health = 70
                if fieldInfo ~= nil and Bodengesundheit ~= nil and Bodengesundheit.cfg ~= nil
                        and Bodengesundheit.cfg.enabled
                        and Bodengesundheit.getHealthForField ~= nil then
                    local h = Bodengesundheit.getHealthForField(
                        fieldInfo.field, fieldInfo.fieldId)
                    if type(h) == "number" then health = h end
                end
                -- Grundgewicht + Kur-Anteil, der bei niedriger Gesundheit waechst
                local cure = 0
                if health < 65 then cure = (65 - health) / 65 end   -- 0..1
                total = 0.30 + cure * 0.55
            end

            -- Abwechslung ueber Felder: oft empfohlene Frucht abwerten
            if usageCounts ~= nil and usageCounts[candidate] ~= nil then
                total = total - math.min(0.25, 0.06 * usageCounts[candidate])
            end

            -- Weitblick: projizierte Deckung nach Ernte (informativer Wert)
            local projCoverage = projectedCoverageAfterHarvest(
                candidate, storageTotals, animalNeeds,
                estimateYield(fieldInfo.area, candidate)
            )

            table.insert(results, {
                crop            = candidate,
                totalScore      = total,
                pfBonus         = pfBonus,
                rotScore        = rScore,
                storScore       = sScore,
                animScore       = aScore,
                tmrScore        = tScore,
                marketScore     = mScore,
                projCoverage    = math.min(projCoverage, 99),
                displayName     = CropRotationData.getCropName(candidate),
                weights         = w,
            })
        end
    end

    table.sort(results, function(a, b) return a.totalScore > b.totalScore end)
    return results
end

-- ─────────────────────────────────────────────────────────────────────────────
-- ALLE FELDER AUF EINMAL
-- ─────────────────────────────────────────────────────────────────────────────

function RecommendationEngine.buildAllRecommendations()
    local fields        = FieldAnalyzer.getOwnFields()
    local storageTotals = StorageAnalyzer.getTotals()
    local animalNeeds   = AnimalAnalyzer.getNeedsPerMonth(storageTotals)

    local allResults = {}
    for _, fieldInfo in ipairs(fields) do
        if fieldInfo.isOwn then
            local recs = RecommendationEngine.recommendForField(fieldInfo, storageTotals, animalNeeds)
            table.insert(allResults, {
                fieldInfo       = fieldInfo,
                recommendations = recs,
                top3            = { recs[1], recs[2], recs[3] },
            })
        end
    end

    return allResults, storageTotals, animalNeeds
end
