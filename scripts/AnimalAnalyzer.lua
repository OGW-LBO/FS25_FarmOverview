-- AnimalAnalyzer.lua
-- Bestaetigt per debugDump:
--   spec_husbandryAnimals  -> vorhanden
--   p:getNumOfAnimals()    -> Funktion (liefert echte Tierzahl)
--   p:getAnimalTypeIndex() -> Funktion (integer)
--
-- Alle Futter-Keys = echte FS25/Krebach-FillType-Namen
-- (MAIZE statt CORN, DRYGRASS statt DRYGR — bestaetigt per FillType-Dump).
--
-- Futterdeckung beruecksichtigt drei Quellen:
--   1. Hoflager (storageTotals, z.B. Silo)
--   2. Fertiges Mischfutter im Lager (FORAGE, PIGFOOD/PIGFOODWF, CHICKENFOOD)
--   3. Futter im Stall-Trog (spec_husbandryFood — defensiv gelesen, da
--      nicht in der LUADOC dokumentiert; Typ- und Existenzpruefungen)
AnimalAnalyzer = {}

AnimalAnalyzer.ANIMAL_DISPLAY_NAMES = {
    COW     = "Kühe",
    PIG     = "Schweine",
    SHEEP   = "Schafe",
    HORSE   = "Pferde",
    CHICKEN = "Hühner",
}

-- Optimales Verkaufsalter je Tierart (Spiel-Monate; Naeherung FS25-Vanilla)
-- Quelle: FS25-Tierkurven; Tiere im Fenster erzielen Hoechstpreis.
AnimalAnalyzer.OPTIMAL_SELL_AGE = {
    COW     = { low = 24, high = 48 },
    PIG     = { low =  4, high =  8 },
    SHEEP   = { low = 12, high = 24 },
    HORSE   = { low = 36, high = 60 },
    CHICKEN = { low =  4, high = 10 },
}

-- FillType-Index -> Schluessel in Grossbuchstaben (oder nil).
-- Alle Fuelltypen kommen so von der geladenen Karte, nie aus einer Namensliste.
local function ftKey(idx)
    if type(idx) ~= "number" or idx <= 0 then return nil end
    if g_fillTypeManager == nil or g_fillTypeManager.getFillTypeByIndex == nil then
        return nil
    end
    local desc = g_fillTypeManager:getFillTypeByIndex(idx)
    if desc ~= nil and type(desc.name) == "string" then
        return string.upper(desc.name)
    end
    return nil
end

-- Fertige Mischfuttersorten, die diese Tierart frisst - von der Karte, nicht
-- aus einer Liste. Verifiziert in PlaceableHusbandryFood:onPostLoad:
--   g_currentMission.animalFoodSystem:getMixturesByAnimalTypeIndex(typeIndex)
-- liefert die FillType-Indizes (Vanilla FORAGE, auf anderen Karten z. B.
-- PIGFOOD, PIGFOODWF oder CHICKENFOOD).
local function mischfutterTypen(typeIdx)
    local liste = {}
    local afs = g_currentMission ~= nil and g_currentMission.animalFoodSystem or nil
    if afs == nil or afs.getMixturesByAnimalTypeIndex == nil or typeIdx == nil then
        return liste
    end
    local mixturen = afs:getMixturesByAnimalTypeIndex(typeIdx)
    if type(mixturen) ~= "table" then return liste end
    for _, idx in pairs(mixturen) do
        local k = ftKey(idx)
        if k ~= nil then liste[#liste + 1] = k end
    end
    return liste
end

-- Monatlicher Bedarf pro Tier in Litern - NUR NOCH NOTNAGEL.
-- Der echte Verbrauch kommt vom Stall selbst (siehe getHusbandries:
-- getFoodLitersPerHour / inputLitersPerHour / litersPerHour). Diese Tabelle
-- greift erst, wenn ein Stall keine Rate liefert, und nennt dann bewusst
-- Vanilla-Fuelltypen; Karten mit eigenen Futtersorten laufen ueber den
-- echten Weg.
AnimalAnalyzer.ANIMAL_NEEDS = {
    COW     = { feeds = { GRASS=300, DRYGRASS=200, SILAGE=400 },           bedding = { STRAW=150 }, tmr=true  },
    PIG     = { feeds = { WHEAT=200, BARLEY=200, MAIZE=150, SOYBEAN=100, POTATO=100 }, bedding = { STRAW=100 }, tmr=false },
    SHEEP   = { feeds = { GRASS=200, DRYGRASS=150 },                        bedding = { STRAW=80  }, tmr=false },
    HORSE   = { feeds = { GRASS=200, DRYGRASS=200, OAT=100 },               bedding = { STRAW=200 }, tmr=false },
    CHICKEN = { feeds = { WHEAT=50, MAIZE=50 },                             bedding = {},            tmr=false },
}

-- FS25-Basisrezept Mischration (TMR): Silage + Heu + Stroh
AnimalAnalyzer.TMR_RECIPE = {
    SILAGE   = 0.50,
    DRYGRASS = 0.25,
    STRAW    = 0.25,
}

-- Welche fertigen Mischfuttersorten es gibt, steht NICHT mehr hier: das liest
-- mischfutterTypen() je Tierart von der geladenen Karte (siehe oben).

-- Mischungsverhaeltnis der Ration von der Karte uebernehmen, wenn moeglich.
-- Das Futtersystem ist im SDK-Auszug nicht enthalten, die Feldnamen sind also
-- nicht belegt - deshalb streng defensiv: nur wenn sich fuer eine Mischung
-- mindestens zwei Bestandteile MIT Gewicht finden, ersetzt das Ergebnis die
-- Vanilla-Werte oben. Sonst bleibt es bei ihnen.
AnimalAnalyzer._recipeChecked = false

local function bestandteileVon(mix)
    local raw = mix.ingredients or mix.ingredient or mix.components
    if type(raw) ~= "table" then return nil end
    local anteile, summe = {}, 0
    for _, ing in pairs(raw) do
        if type(ing) == "table" then
            local gewicht = tonumber(ing.weight or ing.ratio or ing.minPercentage
                or ing.percentage or ing.amount)
            local typen = ing.fillTypes
            if type(typen) ~= "table" then
                local einzel = ing.fillTypeIndex or ing.fillType
                typen = (einzel ~= nil) and { einzel } or nil
            end
            if gewicht ~= nil and gewicht > 0 and type(typen) == "table" then
                for _, idx in pairs(typen) do
                    local k = ftKey(idx)
                    if k ~= nil then
                        anteile[k] = (anteile[k] or 0) + gewicht
                        summe = summe + gewicht
                    end
                end
            end
        end
    end
    local anzahl = 0
    for _ in pairs(anteile) do anzahl = anzahl + 1 end
    if anzahl < 2 or summe <= 0 then return nil end
    for k, v in pairs(anteile) do anteile[k] = v / summe end
    return anteile
end

-- Fuelltyp-Schluessel der Mischung selbst (Feldnamen nicht belegt -> mehrere Pfade).
local function mischungKey(mix)
    return ftKey(mix.fillTypeIndex or mix.fillType or mix.index)
end

-- @param zielMischungen table|nil  Set der Mischfutter-Schluessel, die zaehlen
--                                  (z. B. die der Kuehe). nil = erste brauchbare.
function AnimalAnalyzer.refreshMixtureRecipe(zielMischungen)
    if AnimalAnalyzer._recipeChecked then return end
    local afs = g_currentMission ~= nil and g_currentMission.animalFoodSystem or nil
    if afs == nil then return end
    local mixturen = afs.mixtures
    if type(mixturen) ~= "table" and afs.getMixtures ~= nil then
        mixturen = afs:getMixtures()
    end
    if type(mixturen) ~= "table" then return end

    -- Ohne Ziel warten: Die erste Mischung der Karte ist NICHT zwangslaeufig die
    -- Ration der Kuehe. Auf Bergisch Land war die erste das Schweinefutter mit
    -- 20 Getreidesorten - als "Mischration" angezeigt war das schlicht falsch.
    if zielMischungen == nil or next(zielMischungen) == nil then return end

    for _, mix in pairs(mixturen) do
        if type(mix) == "table" and zielMischungen[mischungKey(mix) or ""] then
            local anteile = bestandteileVon(mix)
            if anteile ~= nil then
                AnimalAnalyzer._recipeChecked = true
                AnimalAnalyzer.TMR_RECIPE = anteile
                local teile = {}
                for k, v in pairs(anteile) do
                    teile[#teile + 1] = string.format("%s %.0f%%", k, v * 100)
                end
                table.sort(teile)
                print("[FA] Mischration von der Karte (" .. tostring(mischungKey(mix))
                    .. "): " .. table.concat(teile, ", "))
                return
            end
        end
    end
end

-- Notfall-Mapping falls animalSystem keinen Namen liefert.
local FALLBACK_TYPE_NAMES = {
    [1]="COW", [2]="PIG", [3]="SHEEP", [4]="HORSE", [5]="CHICKEN",
}

function AnimalAnalyzer.getLocalFarmId()
    -- Zentrale MP-sichere Kette in FieldAnalyzer
    if FieldAnalyzer ~= nil and FieldAnalyzer.getLocalFarmId ~= nil then
        return FieldAnalyzer.getLocalFarmId()
    end
    if g_currentMission and g_currentMission.player then
        return g_currentMission.player.farmId
    end
    return 1
end

-- Tiertyp-Index -> Name (Lookup ueber animalSystem, Fallback-Tabelle als Netz)
local function resolveAnimalTypeName(typeIdx)
    if typeIdx == nil or typeIdx == 0 then return nil end

    local anSys = g_currentMission and g_currentMission.animalSystem
    if anSys ~= nil then
        local name = nil

        if type(anSys.animalTypes) == "table" then
            local at = anSys.animalTypes[typeIdx]
            if at ~= nil then
                name = at.name or at.typeName or at.type
            end
        end
        if name ~= nil then return string.upper(tostring(name)) end

        if anSys.getTypeByIndex ~= nil then
            local t = anSys:getTypeByIndex(typeIdx)
            if t ~= nil then
                name = t.name or t.typeName
            end
        end
        if name ~= nil then return string.upper(tostring(name)) end

        if type(anSys.typeIndexToName) == "table" then
            name = anSys.typeIndexToName[typeIdx]
        end
        if name ~= nil then return string.upper(tostring(name)) end
    end

    local fb = FALLBACK_TYPE_NAMES[typeIdx]
    if fb ~= nil then
        return fb
    end

    print("[FA] AnimalAnalyzer: unbekannter Tiertyp-Index " .. tostring(typeIdx))
    return nil
end

-- Liest das Futter im Stall-Trog eines Husbandry-Placeables (defensiv).
-- Rueckgabe: Gesamtliter UND Aufschluesselung { FILLTYPE_KEY = Liter }
-- (Aufschluesselung noetig fuer die Rations-Engpass-Analyse im Report-Tab).
local function readTroughFood(p)
    local total = 0
    local mix   = {}

    -- Pfad 1: spec_husbandryFood.fillLevels (Tabelle FillTypeIndex -> Liter)
    local fspec = p.spec_husbandryFood
    if fspec ~= nil and type(fspec.fillLevels) == "table" then
        for idx, v in pairs(fspec.fillLevels) do
            if type(v) == "number" and v > 0 then
                total = total + v
                local desc = nil
                if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByIndex ~= nil then
                    desc = g_fillTypeManager:getFillTypeByIndex(idx)
                end
                if desc ~= nil and type(desc.name) == "string" then
                    local key = string.upper(desc.name)
                    mix[key] = (mix[key] or 0) + v
                end
            end
        end
    end
    if total > 0 then return total, mix end

    -- Pfad 2: p:getTotalFood() falls vorhanden (ohne Aufschluesselung)
    if p.getTotalFood ~= nil then
        local v = p:getTotalFood()
        if type(v) == "number" and v > 0 then
            total = v
        end
    end

    return total, mix
end

-- ── RASSEN, STUECKWERT UND PEAK-FENSTER JE GRUPPE ────────────────────────────
-- Tiere haben keine Nummer. Wiedererkennbar sind sie nur als Gruppe aus Rasse
-- und Alter - genau so fuehrt das Spiel sie auch (ein Cluster je Rasse+Alter).
-- Diese Tabellen beschriften die Gruppen und sagen, wann sie am meisten wert
-- sind. Peak je SUBTYP, nicht je Tierart: Ziegen stehen im selben Block wie
-- Schafe, haben ihren Hoechstpreis aber 14 Monate frueher.
AnimalAnalyzer._subCache = nil

local function subtypInfo(idx)
    if type(idx) ~= "number" then return nil end
    if AnimalAnalyzer._subCache == nil then
        AnimalAnalyzer._subCache = {}
        local as = g_currentMission and g_currentMission.animalSystem
        if as ~= nil and type(as.subTypes) == "table" then
            for i, sub in pairs(as.subTypes) do
                local eintrag = { name = nil, peakPrice = 0, peakAge = nil,
                                  wurfDauer = tonumber(sub.reproductionDurationMonth) }

                if sub.fillTypeIndex ~= nil and g_fillTypeManager ~= nil
                        and g_fillTypeManager.getFillTypeTitleByIndex ~= nil then
                    eintrag.name = g_fillTypeManager:getFillTypeTitleByIndex(sub.fillTypeIndex)
                end
                if eintrag.name == nil and type(sub.name) == "string" then
                    eintrag.name = sub.name
                end

                local curve = sub.sellPrice
                if type(curve) == "table" and curve.get ~= nil then
                    for age = 0, 120 do
                        local pr = curve:get(age)
                        if type(pr) == "number" and pr > eintrag.peakPrice then
                            eintrag.peakPrice = pr
                            eintrag.peakAge   = age
                        end
                    end
                end
                AnimalAnalyzer._subCache[i] = eintrag
            end
        end
    end
    return AnimalAnalyzer._subCache[idx]
end

--- Gruppen beschriften, bewerten und nach Alter ordnen (aelteste zuerst - die
--- stehen beim Verkauf als Erstes an). Rueckgabe: Liste oder nil.
---
--- Gleiche Rasse im gleichen Alter wird zu EINER Zeile zusammengezogen. Das
--- Spiel fuehrt dafuer oft mehrere Cluster (Zukauf, Nachwuchs, Umstallung);
--- fuer den Spieler ist das dieselbe Gruppe und stand sonst dreimal
--- untereinander ("7 x Holstein Kuh / 2 x Holstein Kuh / 1 x Holstein Kuh").
function AnimalAnalyzer.gruppenAufbereiten(gruppen)
    if type(gruppen) ~= "table" or #gruppen == 0 then return nil end

    local zusammen, reihenfolge = {}, {}
    for _, g in ipairs(gruppen) do
        local schluessel = string.format("%s#%s", tostring(g.subIndex), tostring(g.age))
        local z = zusammen[schluessel]
        if z == nil then
            zusammen[schluessel] = g
            reihenfolge[#reihenfolge + 1] = schluessel
        else
            z.num = (z.num or 0) + (g.num or 0)
            -- Naechster Wurf: der weiteste Fortschritt zaehlt, denn dieses
            -- Tier wirft als Erstes. Gerechnet wird daraus weiter unten.
            if g.seitWurf ~= nil and (z.seitWurf == nil or g.seitWurf > z.seitWurf) then
                z.seitWurf = g.seitWurf
            end
            if g.repro ~= nil and (z.repro == nil or g.repro > z.repro) then
                z.repro = g.repro
            end
            if z.inseminiert ~= true then z.inseminiert = g.inseminiert end
        end
    end
    gruppen = {}
    for _, schluessel in ipairs(reihenfolge) do
        gruppen[#gruppen + 1] = zusammen[schluessel]
    end

    for _, g in ipairs(gruppen) do
        local info = subtypInfo(g.subIndex)
        if info ~= nil then
            g.rasse     = info.name
            g.peakAge   = info.peakAge
            g.peakPrice = info.peakPrice
        end
        -- Ohne getSellPrice bleibt der Wert leer; geraten wird nichts.
        if g.wert ~= nil and g.num > 0 then
            g.wertGesamt = g.wert * g.num
        end

        -- Monate bis zum naechsten Wurf, sofern die Daten dafuer da sind.
        -- Zwei Wege, weil zwei Zaehlweisen im Umlauf sind (siehe oben).
        local dauer = info ~= nil and info.wurfDauer or nil
        if dauer ~= nil and dauer > 0 then
            if g.inseminiert == true and g.seitWurf ~= nil then
                g.wurfIn = math.max(0, dauer - g.seitWurf)
            elseif g.repro ~= nil and g.repro > 0 then
                g.wurfIn = math.max(0, dauer * (1 - g.repro / 100))
            end
        end
    end

    table.sort(gruppen, function(a, b)
        if a.age ~= b.age then return a.age > b.age end
        return (a.num or 0) > (b.num or 0)
    end)
    return gruppen
end

--- Was ist mit diesem Stall gerade los? EINE Quelle fuer Aufgabenliste und
--- Tabelle, damit beide dasselbe sagen. Reihenfolge nach Dringlichkeit:
---   zualt    - eine Gruppe ist ueber dem Hoechstpreis, der Wert verfaellt
---   peakvoll - Bestpreis UND Stall voll: der eine Moment zum Abverkauf
---   peak     - eine Gruppe steht im Preisfenster
---   voll     - Stall voll, aber Preis noch nicht so weit
---   quali    - Leistung niedrig; da hilft Futter, kein Verkauf
--- Die Leistungsschwellen stammen aus dem alten Tier-Renderer, der seit der
--- Umstellung auf die Tabelle nicht mehr gezeichnet wird.
AnimalAnalyzer.LEISTUNG_NIEDRIG = 0.55

function AnimalAnalyzer.stallLage(hub)
    if type(hub) ~= "table" then return nil end

    local voll = (hub.maxCount or 0) > 0 and (hub.count or 0) >= hub.maxCount

    local alt, altVerlust, altNum = nil, 0, 0
    local peak, peakNum, peakWert = nil, 0, 0
    for _, g in ipairs(hub.gruppen or {}) do
        local lage = AnimalAnalyzer.verkaufsLage(g.age, g.peakAge)
        if lage == "drueber" then
            alt = true
            altNum = altNum + (g.num or 0)
            -- Was der Wartezeit zum Opfer gefallen ist: Abstand zum Hoechstpreis
            if g.peakPrice ~= nil and g.wert ~= nil and g.peakPrice > g.wert then
                altVerlust = altVerlust + (g.peakPrice - g.wert) * (g.num or 0)
            end
        elseif lage == "fenster" then
            peak = true
            peakNum  = peakNum + (g.num or 0)
            peakWert = peakWert + (g.wertGesamt or 0)
        end
    end

    if alt then
        return { art = "zualt", num = altNum, verlust = altVerlust }
    end
    if peak and voll then
        return { art = "peakvoll", num = peakNum, wert = peakWert }
    end
    if peak then
        return { art = "peak", num = peakNum, wert = peakWert }
    end
    if voll then
        return { art = "voll" }
    end
    if hub.productivity ~= nil and (hub.count or 0) > 0
            and hub.productivity < AnimalAnalyzer.LEISTUNG_NIEDRIG then
        return { art = "quali", wert = hub.productivity }
    end
    return nil
end

--- Wo steht eine Gruppe im Preisverlauf? "jung" | "fenster" | "drueber"
--- Das Fenster beginnt drei Monate vor dem Hoechstpreis: Dort liegt der Wert
--- schon bei rund 92 % und der Stall ist meist voll genug zum Abverkauf.
AnimalAnalyzer.PEAK_VORLAUF = 3

function AnimalAnalyzer.verkaufsLage(age, peakAge)
    if type(age) ~= "number" or type(peakAge) ~= "number" or peakAge <= 0 then
        return nil
    end
    if age > peakAge then return "drueber" end
    if age >= peakAge - AnimalAnalyzer.PEAK_VORLAUF then return "fenster" end
    return "jung"
end

-- ── WAS DIE EIGENEN STAELLE SELBST ERZEUGEN ──────────────────────────────────
-- Mist, Guelle, Milch, Wolle, Eier fallen in der Tierhaltung an. Man kauft sie
-- nicht und stellt sie auch nicht her - wird so etwas knapp, hilft nur eine
-- kleinere Produktion oder mehr Vieh. Die Aufgabenliste braucht das, um nicht
-- "Kaufen oder herstellen" darunter zu schreiben (gemeldet 05.11.2026:
-- "Knapp: Guelle - Kaufen oder herstellen").
--
-- Gelesen wird es aus den Stall-Spezialisierungen, nicht aus einer Namensliste:
--   spec_husbandryStraw.outputFillType        -> Mist (PlaceableHusbandryStraw.lua:76)
--   spec_husbandryLiquidManure.fillType       -> Guelle (…LiquidManure.lua:55)
--   spec_husbandryMilk.fillTypes              -> Milch (Liste)
--   spec_husbandryPallets.fillTypes           -> Wolle, Eier (Liste)
-- So greift es auch bei Mod-Staellen und Karten mit eigenen Tierarten.
-- Rueckgabe: { [FUELLTYP] = true }
function AnimalAnalyzer.getHofProdukte(farmId)
    local result = {}
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps == nil or ps.placeables == nil then
        return result
    end

    local function merke(idx)
        if type(idx) ~= "number" or idx <= 0 then return end
        if g_fillTypeManager == nil or g_fillTypeManager.getFillTypeByIndex == nil then return end
        local desc = g_fillTypeManager:getFillTypeByIndex(idx)
        if desc ~= nil and type(desc.name) == "string" then
            result[string.upper(desc.name)] = true
        end
    end

    for _, p in pairs(ps.placeables) do
        if p ~= nil and p.ownerFarmId == farmId then
            local straw = p.spec_husbandryStraw
            if straw ~= nil then merke(straw.outputFillType) end

            local guelle = p.spec_husbandryLiquidManure
            if guelle ~= nil then merke(guelle.fillType) end

            -- Einzeln abgefragt: eine Liste { a, b } mit nil an erster Stelle
            -- bricht ipairs sofort ab, der zweite Stall-Ausgang fiele weg.
            local function listeMerken(spec)
                if spec ~= nil and type(spec.fillTypes) == "table" then
                    for _, idx in pairs(spec.fillTypes) do merke(idx) end
                end
            end
            listeMerken(p.spec_husbandryMilk)
            listeMerken(p.spec_husbandryPallets)
        end
    end

    return result
end

-- ── VERKAUFSPREIS-KURVEN ─────────────────────────────────────────────────────
-- Liest die echten Verkaufspreis-Kurven aus g_currentMission.animalSystem
-- (subTypes[i].sellPrice, Kurve nach Alter in Monaten). API nicht in der
-- LUADOC dokumentiert -> komplett defensiv; liefert leere Tabelle im Zweifel.
-- Rueckgabe: { [typeName] = { subName, peakPrice, peakLow, peakHigh } }
-- peakLow/peakHigh = Altersfenster, in dem der Preis >= 95% des Maximums ist.
function AnimalAnalyzer.getPeakPrices()
    -- Preiskurven sind pro Spielsitzung statisch -> einmal berechnen
    if AnimalAnalyzer._peakCache ~= nil then
        return AnimalAnalyzer._peakCache
    end
    local result = {}
    local function schritt()
        local as = g_currentMission and g_currentMission.animalSystem
        if as == nil or type(as.subTypes) ~= "table" then return end

        for _, sub in pairs(as.subTypes) do
            local typeName = resolveAnimalTypeName(sub.typeIndex)
            local curve    = sub.sellPrice
            if typeName ~= nil and type(curve) == "table" then
                -- Kurve 0..60 Monate abtasten
                local prices  = {}
                local best    = 0
                local bestAge = 0
                for age = 0, 60 do
                    local pr = nil
                    if curve.get ~= nil then pr = curve:get(age) end
                    if type(pr) == "number" then
                        prices[age] = pr
                        if pr > best then
                            best    = pr
                            bestAge = age
                        end
                    end
                end

                -- Fallback: Keyframes direkt (falls curve:get fehlt)
                if best == 0 and type(curve.keyframes) == "table" then
                    for _, kf in pairs(curve.keyframes) do
                        if type(kf) == "table" then
                            local pr = tonumber(kf[1] or kf.v or kf.value)
                            local ag = tonumber(kf.time or kf.age or kf.t)
                            if pr ~= nil and pr > best then
                                best    = pr
                                bestAge = ag or 0
                            end
                        end
                    end
                end

                if best > 0 then
                    -- Fenster mit >= 95% des Maximums bestimmen
                    local lo, hi = bestAge, bestAge
                    for age = 0, 60 do
                        local pr = prices[age]
                        if type(pr) == "number" and pr >= best * 0.95 then
                            if age < lo then lo = age end
                            if age > hi then hi = age end
                        end
                    end
                    local cur = result[typeName]
                    if cur == nil or best > cur.peakPrice then
                        result[typeName] = {
                            subName   = tostring(sub.name or typeName),
                            peakPrice = best,
                            peakLow   = lo,
                            peakHigh  = hi,
                        }
                    end
                end
            end
        end
    end
    schritt()
    -- Nur cachen, wenn wirklich Daten kamen (sonst spaeter erneut versuchen)
    if next(result) ~= nil then
        AnimalAnalyzer._peakCache = result
    end
    return result
end

-- Konsolen-Dump: Verkaufspreis-Kurven aller Tier-Subtypen. Aufruf: "faPreise".
function AnimalAnalyzer.priceDebugDump()
    print("=== FA-PREISE-DUMP ===")
    local function schritt()
        local as = g_currentMission and g_currentMission.animalSystem
        if as == nil then
            print("  animalSystem: nil")
            return
        end
        if type(as.subTypes) ~= "table" then
            print("  subTypes: " .. type(as.subTypes))
            return
        end
        local sampleAges = { 0, 3, 6, 9, 12, 18, 24, 36, 48, 60 }
        for i, sub in pairs(as.subTypes) do
            local nm = tostring(sub.name or i)
            print("  SUB " .. nm
                .. "  typeIdx=" .. tostring(sub.typeIndex)
                .. "  sellPrice=" .. type(sub.sellPrice))
            local curve = sub.sellPrice
            if type(curve) == "table" then
                local samples = {}
                for _, age in ipairs(sampleAges) do
                    local pr = nil
                    if curve.get ~= nil then pr = curve:get(age) end
                    if type(pr) == "number" then
                        table.insert(samples,
                            tostring(age) .. "Mo=" .. string.format("%.0f", pr))
                    end
                end
                if #samples > 0 then
                    print("    " .. table.concat(samples, "  "))
                end
            end
        end
        local peaks = AnimalAnalyzer.getPeakPrices()
        for t, pp in pairs(peaks) do
            print(string.format("  PEAK %s: %.0f EUR bei %d-%d Mo (%s)",
                t, pp.peakPrice, pp.peakLow, pp.peakHigh, pp.subName))
        end
    end
    schritt()
    print("=== FA-PREISE-DUMP ENDE ===")
end

-- Konsolen-Dump: echte Feldnamen der Husbandry-Specs und Tier-Cluster
-- (Grundlage fuer Alter/Produktivitaet-API). Aufruf im Spiel: "faTiere".
function AnimalAnalyzer.animalDebugDump()
    print("=== FA-TIERE-DUMP ===")
    local function schritt()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil or type(ps.placeables) ~= "table" then
            print("  placeableSystem nicht verfuegbar")
            return
        end
        local farmId = AnimalAnalyzer.getLocalFarmId()
        local n = 0
        for _, p in pairs(ps.placeables) do
            if p ~= nil and p.ownerFarmId == farmId and n < 3 then
                local spec = p.spec_husbandryAnimals or p.spec_animalHusbandry
                if type(spec) == "table" then
                    n = n + 1
                    print("  HUSBANDRY #" .. n)
                    local keys = {}
                    for k, v in pairs(spec) do
                        table.insert(keys, tostring(k) .. "(" .. type(v) .. ")")
                    end
                    table.sort(keys)
                    for _, k in ipairs(keys) do print("    spec." .. k) end

                    -- Erstes Cluster-/Tier-Element im Detail
                    local list = nil
                    if p.getClusters ~= nil then list = p:getClusters() end
                    if type(list) ~= "table" then
                        list = spec.clusters or spec.animalClusters or spec.animals
                    end
                    if type(list) == "table" then
                        for _, el in pairs(list) do
                            if type(el) ~= "table" then break end
                            print("    Erstes Element:")
                            local ek = {}
                            for k, v in pairs(el) do
                                if type(v) == "number" or type(v) == "string"
                                        or type(v) == "boolean" then
                                    table.insert(ek, tostring(k) .. "=" .. tostring(v))
                                else
                                    table.insert(ek, tostring(k) .. "(" .. type(v) .. ")")
                                end
                            end
                            table.sort(ek)
                            for _, k in ipairs(ek) do print("      " .. k) end
                            local mt = getmetatable(el)
                            if mt ~= nil and type(mt.__index) == "table" then
                                local mk = {}
                                for k in pairs(mt.__index) do
                                    table.insert(mk, tostring(k))
                                end
                                table.sort(mk)
                                print("      Methoden: " .. table.concat(mk, ", "))
                            end
                            break
                        end
                    end

                    -- Relevante Placeable-Methoden
                    local fns = { "getAnimals", "getClusters",
                        "getProductivity", "getProductionFactor",
                        "getGlobalProductionFactor", "getNumOfAnimals",
                        "getMaxNumOfAnimals" }
                    for _, fn in ipairs(fns) do
                        print("    p." .. fn .. " vorhanden: " .. tostring(p[fn] ~= nil))
                    end
                end
            end
        end
        print("  eigene Husbandries gefunden: " .. n)

        -- Placeable-Sweep: ALLE Placeables mit Tier-Bezug zeigen (auch die,
        -- die getHusbandries nicht erfasst — z.B. Weiden mit eigenem Spec)
        print("  === Placeable-Sweep (alle Tier-Specs) ===")
        for _, p in pairs(ps.placeables) do
            if type(p) == "table" then
                local function schritt()
                    local hits = {}
                    for k, v in pairs(p) do
                        if type(k) == "string" and k:sub(1, 5) == "spec_"
                                and type(v) == "table" then
                            local lk = string.lower(k)
                            if lk:find("animal", 1, true) ~= nil
                                    or lk:find("husbandry", 1, true) ~= nil
                                    or lk:find("pasture", 1, true) ~= nil
                                    or lk:find("livestock", 1, true) ~= nil
                                    or lk:find("weide", 1, true) ~= nil then
                                table.insert(hits, k)
                            end
                        end
                    end
                    if #hits > 0 then
                        local name = "?"
                        local raw = p.configFileName or p.xmlFilename
                        if type(raw) == "string" then
                            name = raw:match("[^/\\]+$") or raw
                        end
                        local cnt = "?"
                        if p.getNumOfAnimals ~= nil then
                            cnt = tostring(p:getNumOfAnimals())
                        end
                        local clInfo = "-"
                        local function schritt()
                            if p.getClusters == nil then return end
                            local cls = p:getClusters()
                            if type(cls) ~= "table" then return end
                            local nCl, sum = 0, 0
                            for _, cl in pairs(cls) do
                                nCl = nCl + 1
                                local cn = cl.numAnimals or cl.count or 0
                                if cl.getNumAnimals ~= nil then
                                    cn = cl:getNumAnimals() or cn
                                end
                                if type(cn) == "number" then sum = sum + cn end
                            end
                            clInfo = tostring(nCl) .. " Cluster / " .. tostring(sum) .. " Tiere"
                        end
                        schritt()
                        local typeIdx = "?"
                        if p.getAnimalTypeIndex ~= nil then
                            typeIdx = tostring(p:getAnimalTypeIndex())
                        end
                        print("  SWEEP " .. name
                            .. "  farm=" .. tostring(p.ownerFarmId)
                            .. "  typeIdx=" .. typeIdx
                            .. "  getNumOfAnimals=" .. cnt
                            .. "  " .. clInfo)
                        table.sort(hits)
                        print("    specs: " .. table.concat(hits, ", "))
                    end
                end
                schritt()
            end
        end
    end
    schritt()
    print("=== FA-TIERE-DUMP ENDE ===")
end

-- Liest alle Tierhaltungen des Spielers (inkl. Trog-Futter).
function AnimalAnalyzer.getHusbandries(farmId)
    local result = {}
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps == nil then
        print("[FA] AnimalAnalyzer: kein placeableSystem")
        return result
    end

    -- Eigener Abschnitt: das fruehe return (keine Placeables) beendet nur
    -- das Einsammeln, die Sortierung darunter laeuft trotzdem.
    local function sammleStaelle()
        local placeables = ps.placeables
        if placeables == nil then
            print("[FA] AnimalAnalyzer: placeables = nil")
            return
        end

        for _, p in pairs(placeables) do
            if p ~= nil and p.ownerFarmId == farmId then
                local spec = p.spec_husbandryAnimals
                if spec == nil then
                    spec = p.spec_animalHusbandry
                end

                if spec ~= nil then
                    local count = 0
                    if p.getNumOfAnimals ~= nil then
                        count = p:getNumOfAnimals() or 0
                    end
                    -- Fallback: Cluster-Summe. Weide-Placeables liefern die
                    -- Tierzahl teils nur ueber das Cluster-System.
                    if count == 0 then
                        local function schritt()
                            if p.getClusters == nil then return end
                            local cls = p:getClusters()
                            if type(cls) ~= "table" then return end
                            for _, cl in pairs(cls) do
                                local n = nil
                                if cl.getNumAnimals ~= nil then
                                    n = cl:getNumAnimals()
                                end
                                if n == nil then
                                    n = cl.numAnimals or cl.count
                                end
                                if type(n) == "number" then
                                    count = count + n
                                end
                            end
                        end
                        schritt()
                    end

                    local typeIdx = nil
                    if p.getAnimalTypeIndex ~= nil then
                        typeIdx = p:getAnimalTypeIndex()
                    end
                    if typeIdx == nil then
                        typeIdx = spec.animalTypeIndex
                    end

                    local animalTypeName = resolveAnimalTypeName(typeIdx)

                    if animalTypeName ~= nil and count > 0 then
                        local trough, troughMix = readTroughFood(p)

                        -- Maximale Stallkapazitaet. Per faTiere-Dump bestaetigt:
                        -- p:getMaxNumOfAnimals() und spec.maxNumAnimals existieren.
                        local maxCount = 0
                        if p.getMaxNumOfAnimals ~= nil then
                            maxCount = p:getMaxNumOfAnimals() or 0
                        end
                        if maxCount == 0 and spec.maxNumAnimals ~= nil then
                            maxCount = tonumber(spec.maxNumAnimals) or 0
                        end

                        -- Produktivitaet 0-1. Per faTiere-Dump bestaetigt:
                        -- p:getProductionFactor() existiert -> primaerer Pfad.
                        local productivity = nil
                        if p.getProductionFactor ~= nil then
                            productivity = tonumber(p:getProductionFactor())
                        end
                        if productivity == nil and p.getGlobalProductionFactor ~= nil then
                            productivity = tonumber(p:getGlobalProductionFactor())
                        end
                        if productivity == nil and spec.productionFactor ~= nil then
                            productivity = tonumber(spec.productionFactor)
                        end
                        -- Normalisieren (manche APIs liefern 0-100)
                        if productivity ~= nil and productivity > 1 then
                            productivity = productivity / 100.0
                        end

                        -- Durchschnittsalter der Tiere in Spiel-Monaten.
                        -- Per faTiere-Dump bestaetigt: p:getClusters() existiert;
                        -- Tiere haengen im ClusterSystem (nicht spec.animals).
                        local totalAgeM = 0
                        local ageCount  = 0
                        -- Jede Altersgruppe einzeln merken. Tiere tragen keine
                        -- Nummer; im Stall stehen sie als Cluster aus Rasse und
                        -- Alter, und genau daran erkennt man sie wieder.
                        -- Stueckwert direkt vom Spiel (cluster:getSellPrice(),
                        -- belegt in LivestockTrailer.lua:508).
                        local gruppen = {}
                        local function schritt()
                            if p.getClusters == nil then return end
                            local clusters = p:getClusters()
                            if type(clusters) ~= "table" then return end
                            for _, cl in pairs(clusters) do
                                local cAge, cNum = nil, nil
                                if cl.getAge ~= nil then cAge = cl:getAge() end
                                if cAge == nil then
                                    cAge = cl.age or cl.ageInMonths
                                end
                                if cl.getNumAnimals ~= nil then cNum = cl:getNumAnimals() end
                                if cNum == nil then
                                    cNum = cl.numAnimals or cl.count or 1
                                end
                                if type(cAge) == "number" and type(cNum) == "number"
                                        and cNum > 0 then
                                    totalAgeM = totalAgeM + cAge * cNum
                                    ageCount  = ageCount + cNum

                                    local idx = nil
                                    if cl.getSubTypeIndex ~= nil then idx = cl:getSubTypeIndex() end
                                    if idx == nil then idx = cl.subTypeIndex end
                                    local wert = nil
                                    if cl.getSellPrice ~= nil then wert = cl:getSellPrice() end
                                    gruppen[#gruppen + 1] = {
                                        age = cAge, num = cNum, subIndex = idx, wert = wert,
                                        -- Nachwuchs: das Basisspiel fuehrt einen
                                        -- Fortschritt in Prozent, EnhancedAnimalSystem
                                        -- zaehlt stattdessen Monate seit dem letzten
                                        -- Wurf. Beides wird gelesen, keines verlangt.
                                        repro       = tonumber(cl.reproduction),
                                        inseminiert = cl.isInseminated,
                                        seitWurf    = tonumber(cl.monthsSinceLastBirth),
                                    }
                                end
                            end
                        end
                        schritt()
                        -- Fallback: clusterSystem direkt (falls getClusters leer)
                        local function schritt()
                            if ageCount > 0 then return end
                            local cs = spec.clusterSystem
                            if cs == nil then return end
                            local clusters = nil
                            if cs.getClusters ~= nil then clusters = cs:getClusters() end
                            if clusters == nil and type(cs.clusters) == "table" then
                                clusters = cs.clusters
                            end
                            if type(clusters) ~= "table" then return end
                            for _, cl in pairs(clusters) do
                                local cAge = cl.age or cl.ageInMonths
                                local cNum = cl.numAnimals or cl.count or 1
                                if type(cAge) == "number" and cNum > 0 then
                                    totalAgeM = totalAgeM + cAge * cNum
                                    ageCount  = ageCount + cNum
                                end
                            end
                        end
                        schritt()
                        local avgAge = ageCount > 0 and (totalAgeM / ageCount) or nil

                        -- Gebaeude-/Weiden-Name: eine Zeile PRO Placeable,
                        -- damit sichtbar ist, WO Tiere/Futter fehlen
                        local hubName = nil
                        if p.getName ~= nil then
                            local nm = p:getName()
                            if type(nm) == "string" and nm ~= "" then
                                hubName = nm
                            end
                        end
                        if hubName == nil then
                            local raw = p.configFileName or p.xmlFilename
                            if type(raw) == "string" then
                                hubName = raw:match("([^/\\]+)%.xml$")
                                    or raw:match("[^/\\]+$")
                            end
                        end

                        -- ECHTER Verbrauch und ECHTE Futtersorten dieses Stalls.
                        -- Quelle ist der Stall selbst, damit die Auswertung zu
                        -- jeder Karte passt - auch zu Staellen, die erst spaeter
                        -- gebaut werden, und zu eigenen Futtersorten.
                        -- Verifiziert im Spielquellcode:
                        --   PlaceableHusbandryFood: getFoodLitersPerHour(),
                        --     spec.litersPerHour, spec.fillTypes (inkl. Mischfutter)
                        --   PlaceableHusbandryStraw: spec.inputLitersPerHour,
                        --     spec.inputFillType
                        --   PlaceableHusbandryWater: spec.litersPerHour, spec.fillType
                        -- FS25: 1 Monat = 1 Tag = 24 Stunden.
                        local function proMonat(lph)
                            local v = tonumber(lph)
                            if v == nil or v <= 0 then return 0 end
                            return v * 24
                        end

                        local foodPerMonth, foodTypes = 0, {}
                        local fspec = p.spec_husbandryFood
                        if fspec ~= nil then
                            local lph = nil
                            if p.getFoodLitersPerHour ~= nil then
                                lph = p:getFoodLitersPerHour()
                            end
                            if lph == nil then lph = fspec.litersPerHour end
                            foodPerMonth = proMonat(lph)
                            if type(fspec.fillTypes) == "table" then
                                for _, idx in pairs(fspec.fillTypes) do
                                    local k = ftKey(idx)
                                    if k ~= nil then foodTypes[#foodTypes + 1] = k end
                                end
                            end
                        end

                        local beddingPerMonth, beddingType = 0, nil
                        local sspec = p.spec_husbandryStraw
                        if sspec ~= nil then
                            beddingPerMonth = proMonat(sspec.inputLitersPerHour)
                            beddingType     = ftKey(sspec.inputFillType)
                        end

                        local waterPerMonth, waterType = 0, nil
                        local wspec = p.spec_husbandryWater
                        if wspec ~= nil then
                            waterPerMonth = proMonat(wspec.litersPerHour)
                            waterType     = ftKey(wspec.fillType)
                        end

                        table.insert(result, {
                            name            = hubName,
                            animalType      = animalTypeName,
                            count           = count,
                            maxCount        = maxCount,
                            trough          = trough,
                            troughMix       = troughMix,
                            productivity    = productivity,
                            avgAge          = avgAge,
                            gruppen         = AnimalAnalyzer.gruppenAufbereiten(gruppen),
                            foodPerMonth    = foodPerMonth,
                            foodTypes       = foodTypes,
                            mixtureTypes    = mischfutterTypen(typeIdx),
                            beddingPerMonth = beddingPerMonth,
                            beddingType     = beddingType,
                            waterPerMonth   = waterPerMonth,
                            waterType       = waterType,
                        })
                    end
                end
            end
        end
    end
    sammleStaelle()

    -- Gleiche Tierarten untereinander gruppieren
    table.sort(result, function(a, b)
        if a.animalType ~= b.animalType then
            return tostring(a.animalType) < tostring(b.animalType)
        end
        return tostring(a.name) < tostring(b.name)
    end)

    return result
end

-- Gesamtbedarf pro Monat. storageTotals (optional) wird genutzt um
-- fertiges Mischfutter auf die Komponenten-Deckung anzurechnen.
function AnimalAnalyzer.getNeedsPerMonth(storageTotals)
    local farmId       = AnimalAnalyzer.getLocalFarmId()
    local hubs         = AnimalAnalyzer.getHusbandries(farmId)

    -- Mischungsverhaeltnis der Ration: nur die Mischungen der RATIONS-Tierarten
    -- zaehlen (die mit TMR-Trog, in FS25 die Kuehe). hub.mixtureTypes kommt vom
    -- Stall selbst, ist also auch auf fremden Karten richtig.
    local zielMischungen = {}
    for _, hub in ipairs(hubs) do
        if hub.animalType == "COW" then
            for _, k in ipairs(hub.mixtureTypes or {}) do zielMischungen[k] = true end
            -- Zweiter Weg: die Futtersorten des Stalls selbst. Auf Bergisch Land
            -- lieferte getMixturesByAnimalTypeIndex nichts, der Trog kennt die
            -- Mischung aber (FORAGE steht in spec.fillTypes). Eine Mischung wird
            -- nur genommen, wenn ihr Fuelltyp hier auftaucht - das Schweinefutter
            -- ist also weiter ausgeschlossen.
            for _, k in ipairs(hub.foodTypes or {}) do zielMischungen[k] = true end
        end
    end
    AnimalAnalyzer.refreshMixtureRecipe(zielMischungen)
    local feedNeeds    = {}
    local beddingNeeds = {}
    local hasTMR       = false

    local lager = storageTotals or {}

    -- Den Monatsbedarf eines Stalls auf seine Futtersorten verteilen.
    -- Reihenfolge: was im Trog liegt (das fressen die Tiere gerade), sonst
    -- was im Hoflager liegt, sonst gleichmaessig. Damit entstehen keine
    -- Bedarfe fuer Sorten, die der Hof gar nicht nutzt, und die Verteilung
    -- passt sich jeder Karte an.
    local function verteile(gesamt, typen, trogMix)
        local anteile, summe = {}, 0
        for _, k in ipairs(typen) do
            local w = (trogMix ~= nil and trogMix[k]) or 0
            if w > 0 then
                anteile[k] = (anteile[k] or 0) + w
                summe = summe + w
            end
        end
        if summe <= 0 then
            for _, k in ipairs(typen) do
                local w = lager[k] or 0
                if w > 0 then
                    anteile[k] = (anteile[k] or 0) + w
                    summe = summe + w
                end
            end
        end
        if summe <= 0 then
            for _, k in ipairs(typen) do
                anteile[k] = 1
                summe = summe + 1
            end
        end
        local out = {}
        if summe <= 0 then return out end
        for k, w in pairs(anteile) do
            out[k] = gesamt * (w / summe)
        end
        return out
    end

    -- Mischration: Das Spiel zerlegt eine eingefuellte Mischung sofort in die
    -- Rationsgruppen und bucht jede Gruppe auf ihre ERSTE Sorte (verifiziert in
    -- PlaceableHusbandryFood:addFood). Im Trog steht deshalb nicht "TMR",
    -- sondern z. B. Silage/Heu/Gras/Proteinschrot - und die Verteilung oben
    -- macht daraus einen Bedarf an Sorten, die der Hof nie kauft. Wer die
    -- Mischung fuettert und sie auch lagert, braucht sie nicht einzeln: ihr
    -- Anteil wandert zurueck auf die Mischung. Eine Sorte, die der Hof sehr wohl
    -- lagert (Heu, Silage, Gras), bleibt unangetastet - ein echter Engpass dort
    -- muss sichtbar bleiben.
    local function aufMischungUmlegen(anteile, typen)
        local afs = g_currentMission ~= nil and g_currentMission.animalFoodSystem or nil
        if afs == nil or afs.getMixtureByFillType == nil
                or g_fillTypeManager == nil then
            return anteile
        end

        local mixKey, zutaten = nil, nil
        for _, k in ipairs(typen) do
            if (lager[k] or 0) > 0 then
                local idx = g_fillTypeManager:getFillTypeIndexByName(k)
                if idx ~= nil then
                    local mix = afs:getMixtureByFillType(idx)
                    if mix ~= nil then
                        local z = bestandteileVon(mix)
                        if z ~= nil then
                            mixKey, zutaten = k, z
                            break
                        end
                    end
                end
            end
        end
        if mixKey == nil then return anteile end

        local umgelegt = 0
        for k, v in pairs(anteile) do
            if k ~= mixKey and zutaten[k] ~= nil and (lager[k] or 0) <= 0 then
                umgelegt = umgelegt + v
                anteile[k] = nil
            end
        end
        if umgelegt > 0 then
            anteile[mixKey] = (anteile[mixKey] or 0) + umgelegt
        end
        return anteile
    end

    for _, hub in ipairs(hubs) do
        local notnagel = AnimalAnalyzer.ANIMAL_NEEDS[hub.animalType]

        -- Futter: echte Rate des Stalls, sonst Notnagel-Tabelle
        if (hub.foodPerMonth or 0) > 0 and #(hub.foodTypes or {}) > 0 then
            local anteile = verteile(hub.foodPerMonth, hub.foodTypes, hub.troughMix)
            for k, amt in pairs(aufMischungUmlegen(anteile, hub.foodTypes)) do
                feedNeeds[k] = (feedNeeds[k] or 0) + amt
            end
        elseif notnagel ~= nil then
            for fillType, amt in pairs(notnagel.feeds) do
                feedNeeds[fillType] = (feedNeeds[fillType] or 0) + amt * hub.count
            end
        end

        -- Einstreu: Fuelltyp und Rate stehen am Stall (meist Stroh)
        if (hub.beddingPerMonth or 0) > 0 and hub.beddingType ~= nil then
            beddingNeeds[hub.beddingType] =
                (beddingNeeds[hub.beddingType] or 0) + hub.beddingPerMonth
        elseif notnagel ~= nil then
            for fillType, amt in pairs(notnagel.bedding) do
                beddingNeeds[fillType] = (beddingNeeds[fillType] or 0) + amt * hub.count
            end
        end

        if #(hub.mixtureTypes or {}) > 0 then hasTMR = true end
        if not hasTMR and notnagel ~= nil and notnagel.tmr then hasTMR = true end
    end

    -- Deckung je TIERART ueber ALLE Sorten ihrer Futtergruppe plus Trog.
    -- Tiere nehmen innerhalb ihrer Gruppe auch Alternativen: ist kein Heu da,
    -- aber reichlich Silage, ist das kein Engpass. Gerechnet wird pro Tierart
    -- (hubs ist pro GEBAEUDE), sonst waere derselbe Vorrat mehrfach angerechnet.
    local mixedCoverMonths = {}
    local mixedStocks      = {}
    local troughStocks     = {}

    local typeAgg = {}
    for _, hub in ipairs(hubs) do
        local agg = typeAgg[hub.animalType]
        if agg == nil then
            agg = { feedPerMonth = 0, trough = 0, typen = {}, mischungen = {} }
            typeAgg[hub.animalType] = agg
        end
        if (hub.foodPerMonth or 0) > 0 then
            agg.feedPerMonth = agg.feedPerMonth + hub.foodPerMonth
        else
            local notnagel = AnimalAnalyzer.ANIMAL_NEEDS[hub.animalType]
            if notnagel ~= nil then
                for _, amt in pairs(notnagel.feeds) do
                    agg.feedPerMonth = agg.feedPerMonth + amt * hub.count
                end
            end
        end
        agg.trough = agg.trough + (hub.trough or 0)
        for _, k in ipairs(hub.foodTypes or {}) do agg.typen[k] = true end
        for _, k in ipairs(hub.mixtureTypes or {}) do agg.mischungen[k] = true end
        local notnagel = AnimalAnalyzer.ANIMAL_NEEDS[hub.animalType]
        if next(agg.typen) == nil and notnagel ~= nil then
            for k, _ in pairs(notnagel.feeds) do agg.typen[k] = true end
        end
    end

    for animalType, agg in pairs(typeAgg) do
        local stock = 0
        for k, _ in pairs(agg.typen) do
            stock = stock + (lager[k] or 0)
        end
        for k, _ in pairs(agg.mischungen) do
            local s = lager[k] or 0
            if s > 0 then mixedStocks[k] = s end
        end
        if agg.trough > 0 then
            stock = stock + agg.trough
            troughStocks[animalType] = agg.trough
        end
        if agg.feedPerMonth > 0 and stock > 0 then
            -- Je Sorte die Deckung OHNE deren eigenen Vorrat: die Aufrufer
            -- addieren diesen Wert zur eigenen Reichweite, der eigene Vorrat
            -- wuerde sonst doppelt zaehlen.
            for k, _ in pairs(agg.typen) do
                local andere = stock - (lager[k] or 0)
                if andere > 0 then
                    local months = andere / agg.feedPerMonth
                    mixedCoverMonths[k] = math.max(mixedCoverMonths[k] or 0, months)
                end
            end
        end
    end

    return {
        feedNeeds        = feedNeeds,
        beddingNeeds     = beddingNeeds,
        hasTMR           = hasTMR,
        husbandries      = hubs,
        mixedCoverMonths = mixedCoverMonths,
        mixedStocks      = mixedStocks,
        troughStocks     = troughStocks,
    }
end
