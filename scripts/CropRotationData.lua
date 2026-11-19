-- CropRotationData.lua
-- Eigene Fruchtfolge-Logik (KEINE fremden Daten): Bewertung ergibt sich aus
-- Frucht-FAMILIE + ROLLE (Bodenaufbauer / Zehrer / neutral) nach allgemeiner
-- Agronomie. Ertraege/Anzeigenamen/Produkte stammen aus der Krebach-Map bzw.
-- sind allgemeine FS25-Daten.

CropRotationData = {}

-- ── Familie je Frucht (fuer "enge Verwandte" = zu aehnlich hintereinander) ──
CropRotationData.FAMILY = {
    WHEAT = "cereal", WINTERWHEAT = "cereal", BARLEY = "cereal", WINTERBARLEY = "cereal",
    OAT = "cereal", RYE = "cereal", TRITICALE = "cereal", SPELT = "cereal",
    GREENRYE = "cereal", VETCHRYE = "cereal", SORGHUM = "cereal",
    RICE = "cereal", RICELONGGRAIN = "cereal",
    SOYBEAN = "legume", GREENBEAN = "legume", PEA = "legume", ALFALFA = "legume", CLOVER = "legume",
    GRASS = "grass", FIELDGRASS = "grass", MEADOW = "grass",
    MAIZE = "maize", SILAGEMAIZE = "maize",
    POTATO = "root", SUGARBEET = "root", BEETROOT = "root", CARROT = "root", PARSNIP = "root", SPINACH = "root",
    CANOLA = "brassica",
    SUNFLOWER = "oil",
    SUGARCANE = "cane", COTTON = "cotton",
    -- Reine Zwischenfruechte/Gruenduenger (kein Erntegut) -> Bodenaufbauer.
    -- Oelrettich/Senf sind botanisch Kreuzblueter, werden hier aber als
    -- Gruenduenger genutzt (untergepfluegt), daher "cover" statt "brassica".
    OILSEEDRADISH = "cover", MUSTARD = "cover",
    HUMUSACTIVE = "cover", FLOWERINGCATCHCROP = "cover",
}

-- Reine Zwischenfruechte: liefern kein Lagerprodukt, dienen dem Bodenaufbau.
CropRotationData.COVER_CROPS = {
    OILSEEDRADISH = true, MUSTARD = true,
    HUMUSACTIVE = true, FLOWERINGCATCHCROP = true,
}
function CropRotationData.isCoverCrop(c)
    return c ~= nil and CropRotationData.COVER_CROPS[c] == true
end

-- ── Rolle je Familie: builder = baut Boden auf, feeder = zehrt, neutral ──
CropRotationData.FAMILY_ROLE = {
    cereal = "neutral", legume = "builder", grass = "builder", cover = "builder",
    maize = "feeder", root = "feeder", brassica = "feeder", oil = "feeder",
    cane = "feeder", cotton = "feeder",
}

-- ── Empfohlene Anbaupause (Saisons) je Familie ──
CropRotationData.FAMILY_BREAK = {
    cereal = 1, legume = 2, grass = 0, cover = 0,
    maize = 1, root = 3, brassica = 4, oil = 4, cane = 1, cotton = 2,
}

local function familyOf(fruit)
    return (fruit ~= nil) and CropRotationData.FAMILY[fruit] or nil
end

local function roleOf(fruit)
    local fam = familyOf(fruit)
    return (fam ~= nil and CropRotationData.FAMILY_ROLE[fam]) or "neutral"
end

local function sameFamily(a, b)
    local fa, fb = familyOf(a), familyOf(b)
    return fa ~= nil and fa == fb
end

-- ── Frucht -> Lagerprodukte (echte FS25/Krebach-FillType-Namen) ──
CropRotationData.FRUIT_PRODUCTS = {
    WHEAT        = { "WHEAT", "STRAW" },
    WINTERWHEAT  = { "WINTERWHEAT", "STRAW" },
    BARLEY       = { "BARLEY", "STRAW" },
    WINTERBARLEY = { "WINTERBARLEY", "STRAW" },
    RYE          = { "RYE", "STRAW" },
    TRITICALE    = { "TRITICALE", "STRAW" },
    SPELT        = { "SPELT", "STRAW" },
    OAT          = { "OAT", "STRAW" },
    CANOLA       = { "CANOLA" },
    SUNFLOWER    = { "SUNFLOWER" },
    SOYBEAN      = { "SOYBEAN" },
    MAIZE        = { "MAIZE" },
    SILAGEMAIZE  = { "SILAGE" },
    SORGHUM      = { "SORGHUM" },
    POTATO       = { "POTATO" },
    SUGARBEET    = { "SUGARBEET" },
    BEETROOT     = { "BEETROOT" },
    CARROT       = { "CARROT" },
    PARSNIP      = { "PARSNIP" },
    GREENBEAN    = { "GREENBEAN" },
    PEA          = { "PEA" },
    SPINACH      = { "SPINACH" },
    COTTON       = { "COTTON" },
    RICE         = { "RICE" },
    RICELONGGRAIN = { "RICELONGGRAIN" },
    SUGARCANE    = { "SUGARCANE" },
    GRASS        = { "GRASS", "DRYGRASS", "SILAGE" },
    FIELDGRASS   = { "GRASS", "DRYGRASS", "SILAGE" },
    MEADOW       = { "GRASS", "DRYGRASS", "SILAGE" },
    ALFALFA      = { "ALFALFA", "DRYALFALFA" },
    CLOVER       = { "CLOVER", "DRYCLOVER" },
    VETCHRYE     = { "GRASS", "SILAGE" },
    GREENRYE     = { "GRASS", "SILAGE" },
    OILSEEDRADISH      = {},
    MUSTARD            = {},
    HUMUSACTIVE        = {},
    FLOWERINGCATCHCROP = {},
}

-- ── Deutsche Anzeigenamen ─────────────────────────────────────
CropRotationData.DISPLAY_NAMES = {
    WHEAT        = "Weizen",
    WINTERWHEAT  = "Winterweizen",
    BARLEY       = "Gerste",
    WINTERBARLEY = "Wintergerste",
    RYE          = "Roggen",
    TRITICALE    = "Triticale",
    SPELT        = "Dinkel",
    OAT          = "Hafer",
    CANOLA       = "Raps",
    SUNFLOWER    = "Sonnenblume",
    SOYBEAN      = "Sojabohne",
    MAIZE        = "Mais",
    SILAGEMAIZE  = "Silomais",
    SORGHUM      = "Sorghumhirse",
    POTATO       = "Kartoffel",
    SUGARBEET    = "Zuckerrübe",
    BEETROOT     = "Rote Bete",
    CARROT       = "Karotte",
    PARSNIP      = "Pastinake",
    GREENBEAN    = "Grüne Bohne",
    PEA          = "Erbse",
    SPINACH      = "Spinat",
    COTTON       = "Baumwolle",
    RICE         = "Reis",
    RICELONGGRAIN = "Langkornreis",
    SUGARCANE    = "Zuckerrohr",
    GRASS        = "Gras",
    FIELDGRASS   = "Ackergras",
    MEADOW       = "Wiese",
    ALFALFA      = "Luzerne",
    CLOVER       = "Klee",
    OILSEEDRADISH      = "Ölrettich",
    MUSTARD            = "Senf",
    HUMUSACTIVE        = "Humusaktiv",
    FLOWERINGCATCHCROP = "Blühmischung",
    VETCHRYE           = "Wickroggen",
    GREENRYE           = "Grünroggen",
}

-- Lokalisierter Familienname fuer die Anzeige. Die Familien-Schluessel selbst
-- ("cereal", "root", …) sind interne Bezeichner und duerfen nicht in der UI
-- landen. Fuer eine Frucht, deren Familie nur geraten wurde, ist der Schluessel
-- der Fruchtname selbst - dafuer gibt es keinen Text, dann faellt es auf den
-- Aufrufer zurueck (der zeigt "eigene Familie").
function CropRotationData.getFamilyName(fam)
    if fam == nil then return nil end
    local key = "fa_famname_" .. string.lower(tostring(fam))
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return nil
end

-- Lokalisierter Fruchtname: bevorzugt den Spielnamen (folgt der Spielsprache),
-- faellt sonst auf die eingebauten deutschen Namen bzw. den Key zurueck.
function CropRotationData.getCropName(key)
    if key == nil then return "?" end
    local k = string.upper(tostring(key))
    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByName ~= nil then
        local desc = g_fillTypeManager:getFillTypeByName(k)
        if desc ~= nil and type(desc.title) == "string" and desc.title ~= "" then
            return desc.title
        end
    end
    return CropRotationData.DISPLAY_NAMES[k] or key
end

-- ── Ertraege in L/ha (Krebach litersPerSqm x 10000) ───────────
CropRotationData.YIELD_L_PER_HA = {
    WHEAT = 3250, WINTERWHEAT = 4500, BARLEY = 4000, WINTERBARLEY = 4800,
    RYE = 3500, TRITICALE = 4200, SPELT = 3600, OAT = 4750,
    CANOLA = 2400, SUNFLOWER = 1650, SOYBEAN = 2100,
    MAIZE = 7100, SILAGEMAIZE = 9200, SORGHUM = 1625,
    POTATO = 29420, SUGARBEET = 57800, BEETROOT = 28560,
    CARROT = 43480, PARSNIP = 28580,
    GREENBEAN = 4762, PEA = 5278, SPINACH = 23100,
    COTTON = 4970, RICE = 6600, RICELONGGRAIN = 9000, SUGARCANE = 113400,
    GRASS = 22500, FIELDGRASS = 25500, MEADOW = 19500,
    ALFALFA = 24800, CLOVER = 23700,
    VETCHRYE = 5332, GREENRYE = 5332,
    OILSEEDRADISH = 0, MUSTARD = 0, HUMUSACTIVE = 0, FLOWERINGCATCHCROP = 0,
}

-- ── Anbaudauer in Monaten (Pflanzung -> Ernte, aus Map-Perioden) ──
CropRotationData.GROW_TIME_MONTHS = {
    WHEAT = 5, WINTERWHEAT = 9, BARLEY = 5, WINTERBARLEY = 9,
    RYE = 9, TRITICALE = 9, SPELT = 9, OAT = 4,
    CANOLA = 10, SUNFLOWER = 5, SOYBEAN = 5,
    MAIZE = 5, SILAGEMAIZE = 5, SORGHUM = 5,
    POTATO = 5, SUGARBEET = 6, BEETROOT = 4, CARROT = 4, PARSNIP = 5,
    GREENBEAN = 3, PEA = 3, SPINACH = 2,
    COTTON = 8, RICE = 5, RICELONGGRAIN = 6, SUGARCANE = 9,
    GRASS = 2, FIELDGRASS = 2, MEADOW = 2, ALFALFA = 2, CLOVER = 2,
    VETCHRYE = 6, GREENRYE = 6,
    OILSEEDRADISH = 2, MUSTARD = 2, HUMUSACTIVE = 2, FLOWERINGCATCHCROP = 2,
}

-- ── Saisonales Wachstum ───────────────────────────────────────
--
-- Die Anbaudauern oben gelten nur MIT saisonalem Wachstum: Winterweizen
-- braucht dort neun Monate, weil er ueberwintert. Ist die Saison
-- ausgeschaltet, waechst jede Frucht ihre Wachstumsstufen einfach durch -
-- Winterweizen ist dann so schnell fertig wie Sommerweizen, und die
-- Empfehlungen des Advisors waeren zu vorsichtig.
--
-- Erkennung ohne Kenntnis der growthMode-Konstanten: Eine Frucht, die in
-- JEDER der zwoelf Perioden gesaet werden darf, kann keiner Saison
-- unterliegen. Verifiziert: fruitDesc:getIsPlantableInPeriod(growthMode,
-- periode) wird so auch von SowingMachine.lua:857 und PlaceableVine.lua:390
-- benutzt.

CropRotationData.saisonalesWachstum = true   -- bis zur Pruefung angenommen
CropRotationData.saisonGeprueft     = false

-- Anzahl der Monate, in denen Winterweizen (ersatzweise Weizen) NICHT saebar
-- ist - oder nil, wenn sich das (noch) nicht pruefen laesst. Eigene Funktion,
-- damit die fruehen Ausstiege nur diese Pruefung beenden und nicht den Aufrufer.
local function gesperrteMonate()
    local mi = nil
    if g_currentMission ~= nil then mi = g_currentMission.missionInfo end
    local ftm = g_fruitTypeManager
    if mi == nil or ftm == nil or mi.growthMode == nil
            or ftm.getFruitTypeByName == nil then
        return nil
    end

    -- Eine Winterfrucht ist der schaerfste Test; ersatzweise Weizen.
    local desc = ftm:getFruitTypeByName("WINTERWHEAT")
    if desc == nil then desc = ftm:getFruitTypeByName("WHEAT") end
    if desc == nil or desc.getIsPlantableInPeriod == nil then
        return nil
    end

    local gesperrt = 0
    for periode = 1, 12 do
        if not desc:getIsPlantableInPeriod(mi.growthMode, periode) then
            gesperrt = gesperrt + 1
        end
    end
    return gesperrt
end

--- @return boolean true = mit Saison, false = jederzeit anbaubar
function CropRotationData.hatSaisonalesWachstum()
    if CropRotationData.saisonGeprueft then
        return CropRotationData.saisonalesWachstum
    end

    -- Kein einziger gesperrter Monat -> keine Saison. Nicht pruefbar -> Saison
    -- annehmen (sicherer Standard, wie bisher).
    local ergebnis = true
    local gesperrt = gesperrteMonate()
    if gesperrt ~= nil then ergebnis = (gesperrt > 0) end

    CropRotationData.saisonalesWachstum = ergebnis
    CropRotationData.saisonGeprueft     = true

    Logging.info("[Bodengesundheit] Saisonales Wachstum: %s",
        ergebnis and "AN (Anbaufenster gelten)"
                 or "AUS (jede Frucht jederzeit saebar)")

    return ergebnis
end

--- Anbaudauer einer Frucht in Monaten.
---
--- Ohne saisonales Wachstum entfaellt die Ueberwinterung: Winterfruechte
--- brauchen dann nicht laenger als ihre Sommer-Gegenstuecke. Statt einer
--- zweiten Tabelle wird die hinterlegte Dauer auf das Mass der schnellsten
--- Getreideart gedeckelt - das trifft die Realitaet naeher als neun Monate
--- und haelt die Reihenfolge der Fruechte untereinander erhalten.
function CropRotationData.getGrowTimeMonths(crop)
    local basis = CropRotationData.GROW_TIME_MONTHS[crop] or 5

    if CropRotationData.hatSaisonalesWachstum() then
        return basis
    end

    -- Ohne Saison: Deckel bei 6 Monaten. Alles darueber ist reine
    -- Ueberwinterungszeit (Winterweizen 9, Raps 10, Zuckerrohr 9).
    if basis > 6 then
        return 6
    end
    return basis
end

-- ── API ───────────────────────────────────────────────────────

-- Empfohlene Anbaupause (Saisons) einer Frucht.
function CropRotationData.getBreakPeriods(candidate)
    local fam = familyOf(candidate)
    return (fam ~= nil and CropRotationData.FAMILY_BREAK[fam]) or 1
end

-- Fruchtfolge-Bonus in Prozent (eigenes, familienbasiertes System).
--   prevFruit     = Vorfrucht (steht/stand auf dem Feld)
--   candidate     = geplante Frucht
--   prevPrevFruit = Vorvorfrucht (optional)
function CropRotationData.getPFBonus(prevFruit, candidate, prevPrevFruit)
    if candidate == nil or CropRotationData.FAMILY[candidate] == nil then return 0 end
    if prevFruit == nil then return 5 end   -- Brache / Bodenruhe

    local bonus = 0

    if prevFruit == candidate then
        bonus = bonus - 20                  -- Monokultur
    elseif sameFamily(prevFruit, candidate) then
        bonus = bonus - 10                  -- enge Verwandte (z. B. Getreide nach Getreide)
    else
        local pr, cr = roleOf(prevFruit), roleOf(candidate)
        if pr == "builder" then
            bonus = bonus + 12              -- nach Leguminose/Gras/Zwischenfrucht: sehr gut
        elseif pr == "feeder" and cr == "feeder" then
            bonus = bonus - 6               -- zwei Zehrer hintereinander
        elseif pr == "feeder" then
            bonus = bonus + 8               -- nach Zehrer eine leichtere Frucht: gut
        elseif pr == "neutral" and cr == "feeder" then
            bonus = bonus + 5               -- Getreide -> Zehrer: ok
        else
            bonus = bonus + 4               -- sonstiger Wechsel
        end
    end

    -- Vorvorfrucht wirkt schwaecher
    if prevPrevFruit ~= nil and prevPrevFruit ~= prevFruit then
        if prevPrevFruit == candidate and CropRotationData.getBreakPeriods(candidate) >= 2 then
            bonus = bonus - 8               -- Anbaupause (auch ueber die Vorvorfrucht) verletzt
        elseif sameFamily(prevPrevFruit, candidate) then
            bonus = bonus - 4
        elseif roleOf(prevPrevFruit) == "builder" then
            bonus = bonus + 5
        end
    end

    return bonus
end

-- =====================================================================================
-- Fruechte der geladenen Map uebernehmen
-- =====================================================================================
-- Die Tabellen oben bleiben die Wissensbasis: Familie, Rolle und Anbaupause sind
-- Agronomie und stehen in KEINER Spieldatei. Alles, was die Map selbst weiss -
-- welche Fruechte es gibt, wie sie heissen, was sie liefern, wie viel sie bringen
-- und ob sie Zwischenfrucht sind - wird beim Laden von dort geholt und
-- ueberschreibt die Vorgabewerte. Dadurch arbeitet die Mod auch auf Maps mit
-- eigenen Fruechten vollstaendig, ohne dass hier etwas gepflegt werden muss.
--
-- Verifiziert gegen dataS/scripts/fruits/FruitTypeDesc.lua + FruitTypeManager.lua:
--   ft.name                 Frucht-Schluessel (bereits GROSS)
--   ft.fillType             Haupt-Erntegut (FillTypeDesc)
--   ft.windrowFillType      Schwad-Produkt, z.B. GRASS -> DRYGRASS
--   ft.literPerSqm          Ertrag in l/m^2  (".harvest#litersPerSqm")
--   ft.isCatchCrop          echte Zwischenfrucht-Flagge (".#isCatchCrop")
--   ft.allowsSeeding        ob die Frucht ueberhaupt saebar ist (".seeding#isAvailable")

-- Sonderkulturen, die zwar saebar sind, aber nicht zum Ackerbau-Alltag gehoeren:
-- Energieholz im Kurzumtrieb, Faserpflanzen, Nassfeld- und Dauerkulturen. Sie
-- stehen weiter in der Liste und sind mit einem Klick anwaehlbar - nur als
-- VORGABE sind sie aus, damit die Empfehlungen nicht von einer Kultur dominiert
-- werden, die die wenigsten anbauen. Die Vorgabe greift nur beim allerersten
-- Start eines Savegames; sobald einmal eine Auswahl gespeichert wurde, gilt die.
CropRotationData.DEFAULT_OFF = {
    POPLAR = true,          -- Kurzumtrieb, Hackschnitzel
    COTTON = true,          -- Faserpflanze
    SUGARCANE = true,       -- mehrjaehrig, Sonderflaeche
    RICE = true, RICELONGGRAIN = true,   -- Nassfeld
    GRAPE = true, OLIVE = true,          -- Dauerkulturen
}

CropRotationData.mapCrops = nil     -- alle saebaren Fruechte der Map (sortiert)
CropRotationData.mapInfo  = {}      -- crop -> { family=, source=, yield=, cover= }
CropRotationData.disabledCrops = {} -- vom Spieler abgewaehlt: crop -> true

-- Map-Kategorie -> eigene Familie (erste Stufe des Fallbacks). Deckt die
-- ueblichen Basis-Kategorien ab; alles andere faellt auf die Namensmuster.
local CATEGORY_FAMILY = {
    CEREALS = "cereal", GRAIN = "cereal", GRAINS = "cereal",
    OILSEEDS = "oil", OILSEED = "oil",
    ROOTCROPS = "root", ROOTCROP = "root", VEGETABLES = "root", VEGETABLE = "root",
    GRASSES = "grass", GRASS = "grass",
    LEGUMES = "legume", LEGUME = "legume",
    CATCHCROPS = "cover", COVERCROPS = "cover",
}

-- Namensbestandteil -> Familie (zweite Stufe). Reihenfolge zaehlt: laengere und
-- spezifischere Muster zuerst, damit z.B. SILAGEMAIZE als maize erkannt wird und
-- OILSEEDRADISH nicht faelschlich als Oelfrucht statt Gruenduenger landet.
local NAME_FAMILY = {
    { "OILSEEDRADISH", "cover" }, { "CATCHCROP", "cover" }, { "MUSTARD", "cover" },
    { "MAIZE", "maize" }, { "CORN", "maize" },
    { "WHEAT", "cereal" }, { "BARLEY", "cereal" }, { "RYE", "cereal" },
    { "OAT", "cereal" }, { "SPELT", "cereal" }, { "TRITICALE", "cereal" },
    { "SORGHUM", "cereal" }, { "MILLET", "cereal" }, { "RICE", "cereal" },
    { "SOY", "legume" }, { "BEAN", "legume" }, { "PEA", "legume" },
    { "LENTIL", "legume" }, { "LUPIN", "legume" }, { "CLOVER", "legume" },
    { "ALFALFA", "legume" }, { "VETCH", "legume" },
    { "GRASS", "grass" }, { "MEADOW", "grass" }, { "HAY", "grass" },
    { "POTATO", "root" }, { "BEET", "root" }, { "CARROT", "root" },
    { "PARSNIP", "root" }, { "ONION", "root" }, { "TURNIP", "root" },
    { "CABBAGE", "brassica" }, { "CANOLA", "brassica" }, { "RAPE", "brassica" },
    { "SUNFLOWER", "oil" }, { "OLIVE", "oil" }, { "PEANUT", "oil" },
    { "COTTON", "cotton" }, { "CANE", "cane" },
}

-- Schnappschuss der GEPFLEGTEN Familientabelle, angelegt vor der ersten
-- Uebernahme aus der Map. Noetig, weil initFromMap seine abgeleiteten Familien
-- nach CropRotationData.FAMILY zurueckschreibt: ein zweiter Lauf (der Nachzieher
-- aus buildCache) wuerde die eigene Ausgabe sonst als gepflegtes Wissen lesen
-- und "unknown" faelschlich zu "table" machen - die Frucht saehe im Fruechte-Tab
-- dann nach sicherer Zuordnung aus, obwohl nur geraten wurde.
local function baseFamily()
    if CropRotationData._baseFamily == nil then
        local kopie = {}
        for k, v in pairs(CropRotationData.FAMILY) do kopie[k] = v end
        CropRotationData._baseFamily = kopie
    end
    return CropRotationData._baseFamily
end

-- Familie einer Frucht bestimmen. Rueckgabe: familie, quelle
-- ("table" = gepflegtes Wissen, "category"/"name" = abgeleitet, nil = unbekannt).
local function deriveFamily(name, categories)
    local known = baseFamily()[name]
    if known ~= nil then return known, "table" end

    for _, cat in ipairs(categories or {}) do
        local fam = CATEGORY_FAMILY[cat]
        if fam ~= nil then return fam, "category" end
    end

    for _, eintrag in ipairs(NAME_FAMILY) do
        if string.find(name, eintrag[1], 1, true) ~= nil then
            return eintrag[2], "name"
        end
    end

    return nil, "unknown"
end

-- Die Erloes-Normierung der Engine haengt an der Fruchtliste - aendert die sich,
-- muss der Cache weg (er ist auf den besten Kandidaten normiert; faellt der
-- weg, sind alle uebrigen Werte falsch und eine Abwahl bliebe wirkungslos).
-- Steht bewusst VOR initFromMap: eine local function ist in Lua erst ab ihrer
-- Definition sichtbar, weiter oben waere sie beim Aufruf nil.
local function invalidateEngineCache()
    if RecommendationEngine ~= nil and RecommendationEngine.invalidateMarketCache ~= nil then
        RecommendationEngine.invalidateMarketCache()
    end
end

-- fruitTypeIndex -> Liste der Kategorienamen, in denen die Frucht steht.
local function buildCategoryMap(ftm)
    local out = {}
    if ftm == nil then return out end
    local zuordnung = ftm.categoryIndexToFruitTypeIndex or {}
    for catName, catIndex in pairs(ftm.categories or {}) do
        local liste = zuordnung[catIndex]
        if type(liste) == "table" then
            for _, fIdx in ipairs(liste) do
                out[fIdx] = out[fIdx] or {}
                table.insert(out[fIdx], string.upper(tostring(catName)))
            end
        end
    end
    return out
end

-- Einmalig beim Laden der Map aufrufen. Ergaenzt/ueberschreibt die Tabellen
-- oben, damit alle Aufrufer (RecommendationEngine, StorageAnalyzer, Advisor)
-- unveraendert weiterarbeiten. Rueckgabe: Anzahl uebernommener Fruechte.
function CropRotationData.initFromMap()
    local ftm = g_fruitTypeManager
    if ftm == nil or ftm.getFruitTypes == nil then return 0 end

    baseFamily()   -- Schnappschuss sichern, BEVOR FAMILY ueberschrieben wird

    local fruits = ftm:getFruitTypes()
    if fruits == nil then return 0 end

    local catMap = buildCategoryMap(ftm)
    local crops, info = {}, {}

    -- Eine Frucht uebernehmen. Eigene Funktion, damit ein fruehes return nur
    -- diese Frucht ueberspringt und nicht die ganze Uebernahme abbricht.
    local function uebernehmeFrucht(ft)
        if type(ft) ~= "table" or type(ft.name) ~= "string" or ft.name == "" then return end
        local name = string.upper(ft.name)

        -- Erntegut + Schwadprodukt (GRASS -> DRYGRASS). Reihenfolge zaehlt:
        -- produkte[1] ist ueberall das Hauptprodukt.
        local produkte = {}
        if ft.fillType ~= nil and type(ft.fillType.name) == "string" then
            table.insert(produkte, string.upper(ft.fillType.name))
        end
        if ft.windrowFillType ~= nil and type(ft.windrowFillType.name) == "string" then
            local w = string.upper(ft.windrowFillType.name)
            if w ~= produkte[1] then table.insert(produkte, w) end
        end
        if #produkte > 0 then
            CropRotationData.FRUIT_PRODUCTS[name] = produkte
        end

        -- literPerSqm ist l/m^2 -> mal 10000 = l/ha
        local lps = tonumber(ft.literPerSqm)
        if lps ~= nil and lps > 0 then
            CropRotationData.YIELD_L_PER_HA[name] = math.floor(lps * 10000 + 0.5)
        end

        if ft.isCatchCrop == true then
            CropRotationData.COVER_CROPS[name] = true
        end

        local fam, quelle = deriveFamily(name, catMap[ft.index])
        if fam == nil then
            -- Unbekannt: eigene Familie. Dann gilt sie nur zu sich selbst als
            -- verwandt - Monokultur wird also weiterhin erkannt -, bekommt
            -- aber keine erfundene Bodenwirkung.
            fam = name
            if CropRotationData.FAMILY_ROLE[fam] == nil then
                CropRotationData.FAMILY_ROLE[fam] = "neutral"
            end
            if CropRotationData.FAMILY_BREAK[fam] == nil then
                CropRotationData.FAMILY_BREAK[fam] = 1
            end
        end
        CropRotationData.FAMILY[name] = fam

        -- allowsSeeding entscheidet, ob die Frucht ueberhaupt planbar ist.
        -- Standard ist true; nur ausdruecklich nicht saebare Fruechte
        -- (z.B. Dauergruenland) fallen heraus.
        local saebar = (ft.allowsSeeding ~= false)
        info[name] = {
            family = fam,
            source = quelle,
            yield  = CropRotationData.YIELD_L_PER_HA[name],
            cover  = CropRotationData.COVER_CROPS[name] == true,
            seedable = saebar,
            -- regrows = die Frucht waechst nach dem Schnitt nach, liefert
            -- also mehrere Ernten je Aussaat (Gras, Luzerne, Klee, aber auch
            -- Zwischenfruechte und Kurzumtrieb wie Pappel). NICHT mit
            -- "mehrjaehrig" gleichsetzen - auf Beuren tragen es auch Senf und
            -- Humusaktiv. Wird ausgewiesen, weil der Erloesvergleich je Ernte
            -- rechnet und solche Kulturen dort ueberzeichnet wirken.
            perennial = (ft.regrows == true),
        }
        if saebar then table.insert(crops, name) end
    end

    for _, ft in pairs(fruits) do
        uebernehmeFrucht(ft)
    end

    table.sort(crops)
    CropRotationData.mapCrops = crops
    CropRotationData.mapInfo  = info

    -- Vorgabe nur EINMAL setzen. Sonst wuerde der Nachzieh-Aufruf aus buildCache
    -- eine bewusste Anwahl des Spielers wieder ueberschreiben. Eine gespeicherte
    -- Auswahl aus dem Savegame kommt spaeter ueber deserializeDisabled und
    -- ersetzt diese Vorgabe vollstaendig.
    if not CropRotationData._defaultsApplied then
        CropRotationData._defaultsApplied = true
        for _, crop in ipairs(crops) do
            local i = info[crop] or {}
            -- Bekannte Sonderkultur, oder eine der Map unbekannte Frucht, die
            -- nachwaechst - das trifft Energieholz-Kulturen fremder Maps, ohne
            -- normale Fruechte zu erwischen.
            if CropRotationData.DEFAULT_OFF[crop] == true
                    or (i.source == "unknown" and i.perennial == true) then
                CropRotationData.disabledCrops[crop] = true
            end
        end
    end

    invalidateEngineCache()
    return #crops
end

-- Ertraege frisch aus der Karte nachlesen. Andere Mods (z.B. ErtragsFaktor)
-- setzen literPerSqm zur Laufzeit neu - beim Laden der Karte, aber auch, wenn
-- jemand im Menue einen Regler verstellt oder der Server die Einstellung an die
-- Clients verteilt. Ohne Nachlesen zeigte die Uebersicht dann veraltete Werte,
-- und die Erloesbewertung der Empfehlungen rechnete damit. Rund 40 Zahlen,
-- daher bei jedem Neuaufbau der Analyse vertretbar.
-- Rueckgabe: true, wenn sich mindestens ein Ertrag geaendert hat.
function CropRotationData.refreshYields()
    local ftm = g_fruitTypeManager
    if ftm == nil or ftm.getFruitTypes == nil then return false end
    local fruits = ftm:getFruitTypes()
    if fruits == nil then return false end

    local geaendert = false
    for _, ft in pairs(fruits) do
        if type(ft) == "table" and type(ft.name) == "string" then
            local lps = tonumber(ft.literPerSqm)
            if lps ~= nil and lps > 0 then
                local name = string.upper(ft.name)
                local neu = math.floor(lps * 10000 + 0.5)
                if CropRotationData.YIELD_L_PER_HA[name] ~= neu then
                    CropRotationData.YIELD_L_PER_HA[name] = neu
                    local info = CropRotationData.mapInfo[name]
                    if info ~= nil then info.yield = neu end
                    geaendert = true
                end
            end
        end
    end
    if geaendert then invalidateEngineCache() end
    return geaendert
end

-- Planbare Fruechte fuer Empfehlungen. Bevorzugt die Fruechte der geladenen Map
-- (siehe initFromMap); nur wenn die noch nicht vorliegen, greift die
-- Vanilla-Liste als Notnagel. Vom Spieler abgewaehlte Fruechte fallen heraus.
function CropRotationData.getAllCrops()
    local liste = CropRotationData.mapCrops
    if liste == nil or #liste == 0 then
        liste = {
            "WHEAT", "WINTERWHEAT", "BARLEY", "WINTERBARLEY",
            "RYE", "TRITICALE", "SPELT", "OAT",
            "CANOLA", "SUNFLOWER", "SOYBEAN",
            "MAIZE", "SILAGEMAIZE", "SORGHUM",
            "POTATO", "SUGARBEET", "BEETROOT", "CARROT", "PARSNIP",
            "GREENBEAN", "PEA", "SPINACH", "COTTON",
            "GRASS", "ALFALFA", "CLOVER",
            "OILSEEDRADISH", "MUSTARD", "HUMUSACTIVE", "FLOWERINGCATCHCROP",
        }
    end

    local disabled = CropRotationData.disabledCrops or {}
    local out = {}
    for _, c in ipairs(liste) do
        if disabled[c] ~= true then table.insert(out, c) end
    end
    return out
end

-- Abwahl setzen/lesen (UI + Persistenz).
function CropRotationData.setCropEnabled(crop, enabled)
    if type(crop) ~= "string" then return end
    CropRotationData.disabledCrops[crop] = (enabled == false) or nil
    invalidateEngineCache()
end

function CropRotationData.isCropEnabled(crop)
    return CropRotationData.disabledCrops[crop] ~= true
end

-- Abwahlliste als "A,B,C" fuer die Savegame-XML.
function CropRotationData.serializeDisabled()
    local out = {}
    for crop, aus in pairs(CropRotationData.disabledCrops or {}) do
        if aus == true then table.insert(out, crop) end
    end
    table.sort(out)
    return table.concat(out, ",")
end

function CropRotationData.deserializeDisabled(str)
    CropRotationData.disabledCrops = {}
    -- Eine gespeicherte Auswahl schlaegt die Vorgabe - auch die leere Auswahl
    -- "der Spieler will wirklich alles". Ohne diese Sperre wuerde ein spaeteres
    -- initFromMap die Sonderkulturen wieder abwaehlen.
    CropRotationData._defaultsApplied = true
    if type(str) == "string" and str ~= "" then
        for crop in string.gmatch(str, "[^,]+") do
            local c = string.upper((string.gsub(crop, "%s", "")))
            if c ~= "" then CropRotationData.disabledCrops[c] = true end
        end
    end
    -- Auch beim Laden aus dem Savegame und beim MP-Sync: die Fruchtliste hat
    -- sich geaendert, die normierten Erloes-Werte sind damit hinfaellig.
    invalidateEngineCache()
end
