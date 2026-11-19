-- FieldLedger.lua
-- Deckungsbeitrag je Feld: was ein Feld eingebracht und was es gekostet hat.
--
-- Warum in Mengen und nicht in Buchungen:
-- Das Spiel bucht Geld dort, wo es den Besitzer wechselt - Diesel an der
-- Tankstelle, Saatgut im Shop, den Erloes am Verkaufspunkt. Keine dieser
-- Buchungen weiss, auf welchem Feld sie entstanden ist, und beim Verkauf ist
-- die Herkunft ohnehin verloren: Weizen von zwei Feldern liegt im selben Silo,
-- Chargen fuehrt das Spiel nicht.
--
-- Erfasst wird deshalb beim Arbeiten, in Litern und Hektar, und bewertet wird
-- erst beim Anzeigen. Gezaehlt wird dort, wo die Flaeche bekannt ist:
--   Ernte  - Combine.addCutterArea (Liter + Position)
--   Saat   - SowingMachine.processSowingMachineArea (Flaeche + Frucht)
--   Spritze- Sprayer.processSprayerArea (Liter aus workAreaParameters.usage)
-- Alle drei haengen an den Hooks in Bodengesundheit.installHooks, die vor
-- TypeManager:validateTypes gesetzt werden - spaeter waeren sie wirkungslos.
--
-- Nur der Server zaehlt. Gespeichert wird im Spielstand, je Erntejahr.

FieldLedger = {}

FieldLedger.konten = {}      -- [jahr][feldId] = Konto
FieldLedger.MAX_JAHRE = 10   -- aeltere Jahre fallen beim Speichern weg

local function jetztJahr()
    local env = g_currentMission and g_currentMission.environment
    if env == nil then return 1 end
    local tage = tonumber(env.currentMonotonicDay) or 1
    local proPeriode = tonumber(env.daysPerPeriod) or 1
    if proPeriode < 1 then proPeriode = 1 end
    return math.floor((tage - 1) / (proPeriode * 12)) + 1
end

FieldLedger.jahr = jetztJahr

--- Konto eines Feldes im laufenden Jahr, wird bei Bedarf angelegt.
function FieldLedger.konto(feldId, jahr)
    if feldId == nil then return nil end
    jahr = jahr or jetztJahr()
    local j = FieldLedger.konten[jahr]
    if j == nil then
        j = {}
        FieldLedger.konten[jahr] = j
    end
    local k = j[feldId]
    if k == nil then
        k = { ernte = {}, saat = {}, spray = {}, haGeerntet = 0, haGesaet = 0 }
        j[feldId] = k
    end
    return k
end

local function fruchtName(index)
    if g_fruitTypeManager == nil or type(index) ~= "number" then return nil end
    local desc = g_fruitTypeManager:getFruitTypeByIndex(index)
    if desc ~= nil and type(desc.name) == "string" then
        return string.upper(desc.name)
    end
    return nil
end

local function fuellName(index)
    if g_fillTypeManager == nil or type(index) ~= "number" then return nil end
    local desc = g_fillTypeManager:getFillTypeByIndex(index)
    if desc ~= nil and type(desc.name) == "string" then
        return string.upper(desc.name)
    end
    return nil
end

local function zuHektar(flaeche)
    if type(flaeche) ~= "number" or flaeche <= 0 then return 0 end
    if MathUtil ~= nil and MathUtil.areaToHa ~= nil and g_currentMission ~= nil
            and g_currentMission.getFruitPixelsToSqm ~= nil then
        return MathUtil.areaToHa(flaeche, g_currentMission:getFruitPixelsToSqm())
    end
    return flaeche / 10000
end

-- ── Buchen ───────────────────────────────────────────────────────────────────

function FieldLedger.bucheErnte(feldId, fruitIndex, liter, flaeche)
    if g_server == nil or feldId == nil then return end
    local name = fruchtName(fruitIndex)
    if name == nil or type(liter) ~= "number" or liter <= 0 then return end
    local k = FieldLedger.konto(feldId)
    k.ernte[name] = (k.ernte[name] or 0) + liter
    k.haGeerntet = k.haGeerntet + zuHektar(flaeche)
end

--- Saatgut: die Menge steht nicht im Arbeitsschritt, sie rechnet sich aus der
--- Flaeche (seedUsagePerSqm je Frucht, mal Maschinenfaktor). Siehe
--- SowingMachine.lua:1062 - dieselbe Formel, mit der das Spiel abbucht.
function FieldLedger.bucheSaat(feldId, fruitIndex, flaeche, skala, saatFillType)
    if g_server == nil or feldId == nil then return end
    local name = fruchtName(fruitIndex)
    if name == nil then return end
    local ha = zuHektar(flaeche)
    if ha <= 0 then return end

    local desc = g_fruitTypeManager:getFruitTypeByIndex(fruitIndex)
    local proSqm = desc ~= nil and tonumber(desc.seedUsagePerSqm) or nil
    if proSqm == nil or proSqm <= 0 then return end

    local liter = proSqm * ha * 10000 * (tonumber(skala) or 1)
    -- Gebucht wird unter dem SAATGUT-Fuelltyp, nicht unter der Frucht: Saatgut
    -- hat einen eigenen Preis (die Saemaschine fuehrt ihn als seedFillType).
    -- Unter dem Fruchtnamen abgelegt waere der Posten mit dem Druschpreis
    -- bewertet worden - bei Weizen weniger als ein Drittel des Saatgutpreises.
    local key = fuellName(saatFillType) or name
    local k = FieldLedger.konto(feldId)
    k.saat[key] = (k.saat[key] or 0) + liter
    k.haGesaet = k.haGesaet + ha
end

--- Duenger, Kalk, Spritzmittel, Guelle - was die Spritze ausbringt.
function FieldLedger.bucheSpray(feldId, fillTypeIndex, liter)
    if g_server == nil or feldId == nil then return end
    local name = fuellName(fillTypeIndex)
    if name == nil or type(liter) ~= "number" or liter <= 0 then return end
    local k = FieldLedger.konto(feldId)
    k.spray[name] = (k.spray[name] or 0) + liter
end

-- ── Bewerten ─────────────────────────────────────────────────────────────────

--- Preis je Liter. Fuer Betriebsmittel der Einkaufspreis des Fuelltyps, fuer
--- Erntegut dessen Grundpreis. Beides schwankt im Spiel; hier zaehlt die
--- Groessenordnung, nicht der Tagespreis am Verkaufspunkt.
local function preisJeLiter(name)
    if g_fillTypeManager == nil or name == nil then return 0 end
    local desc = nil
    if g_fillTypeManager.getFillTypeByName ~= nil then
        desc = g_fillTypeManager:getFillTypeByName(string.lower(name))
    end
    if desc == nil and g_fillTypeManager.getFillTypeIndexByName ~= nil then
        local idx = g_fillTypeManager:getFillTypeIndexByName(string.lower(name))
        if idx ~= nil then desc = g_fillTypeManager:getFillTypeByIndex(idx) end
    end
    if desc == nil then return 0 end
    return tonumber(desc.pricePerLiter) or 0
end

FieldLedger.preisJeLiter = preisJeLiter

--- Rechnung eines Feldes: Erloes, Kosten, Deckungsbeitrag - gesamt und je ha.
--- Rueckgabe nil, wenn fuer das Jahr nichts gebucht wurde.
function FieldLedger.rechnung(feldId, jahr)
    jahr = jahr or jetztJahr()
    local j = FieldLedger.konten[jahr]
    local k = j ~= nil and j[feldId] or nil
    if k == nil then return nil end

    local r = { jahr = jahr, feldId = feldId, erloes = 0, saatKosten = 0,
                sprayKosten = 0, haGeerntet = k.haGeerntet, haGesaet = k.haGesaet,
                fruechte = {} }

    for name, liter in pairs(k.ernte) do
        local wert = liter * preisJeLiter(name)
        r.erloes = r.erloes + wert
        r.fruechte[#r.fruechte + 1] = { name = name, liter = liter, wert = wert }
    end
    for name, liter in pairs(k.saat) do
        r.saatKosten = r.saatKosten + liter * preisJeLiter(name)
    end
    for name, liter in pairs(k.spray) do
        r.sprayKosten = r.sprayKosten + liter * preisJeLiter(name)
    end

    r.kosten = r.saatKosten + r.sprayKosten
    r.db     = r.erloes - r.kosten
    local ha = math.max(r.haGeerntet, r.haGesaet)
    if ha > 0.01 then
        r.dbJeHa = r.db / ha
        r.ha     = ha
    end
    return r
end

--- Alle Felder eines Jahres, nach Deckungsbeitrag je Hektar sortiert.
function FieldLedger.alleRechnungen(jahr)
    jahr = jahr or jetztJahr()
    local out = {}
    for feldId in pairs(FieldLedger.konten[jahr] or {}) do
        local r = FieldLedger.rechnung(feldId, jahr)
        if r ~= nil then out[#out + 1] = r end
    end
    table.sort(out, function(a, b)
        return (a.dbJeHa or a.db or 0) > (b.dbJeHa or b.db or 0)
    end)
    return out
end

-- ── Spielstand ───────────────────────────────────────────────────────────────

local function mengenSchreiben(xml, basis, tabelle)
    local i = 0
    for name, liter in pairs(tabelle) do
        if liter > 0 then
            local key = string.format("%s.posten(%d)", basis, i)
            setXMLString(xml, key .. "#name", name)
            setXMLFloat(xml, key .. "#liter", liter)
            i = i + 1
        end
    end
end

local function mengenLesen(xml, basis)
    local out, i = {}, 0
    while true do
        local key = string.format("%s.posten(%d)", basis, i)
        local name = getXMLString(xml, key .. "#name")
        if name == nil then break end
        out[name] = (getXMLFloat(xml, key .. "#liter") or 0)
        i = i + 1
    end
    return out
end

function FieldLedger.writeToXML(xml, basis)
    -- Nur die juengsten Jahre: aelteres interessiert niemanden und blaeht
    -- den Spielstand auf.
    local jahre = {}
    for jahr in pairs(FieldLedger.konten) do jahre[#jahre + 1] = jahr end
    table.sort(jahre, function(a, b) return a > b end)

    local n = 0
    for i, jahr in ipairs(jahre) do
        if i > FieldLedger.MAX_JAHRE then break end
        local f = 0
        for feldId, k in pairs(FieldLedger.konten[jahr]) do
            local key = string.format("%s.jahr(%d).feld(%d)", basis, n, f)
            setXMLInt(xml, key .. "#id", feldId)
            setXMLFloat(xml, key .. "#haGeerntet", k.haGeerntet or 0)
            setXMLFloat(xml, key .. "#haGesaet", k.haGesaet or 0)
            mengenSchreiben(xml, key .. ".ernte", k.ernte)
            mengenSchreiben(xml, key .. ".saat", k.saat)
            mengenSchreiben(xml, key .. ".spray", k.spray)
            f = f + 1
        end
        setXMLInt(xml, string.format("%s.jahr(%d)#nr", basis, n), jahr)
        n = n + 1
    end
end

function FieldLedger.readFromXML(xml, basis)
    FieldLedger.konten = {}
    local n = 0
    while true do
        local jahrKey = string.format("%s.jahr(%d)", basis, n)
        local jahr = getXMLInt(xml, jahrKey .. "#nr")
        if jahr == nil then break end
        local f = 0
        while true do
            local key = string.format("%s.feld(%d)", jahrKey, f)
            local id = getXMLInt(xml, key .. "#id")
            if id == nil then break end
            local k = FieldLedger.konto(id, jahr)
            k.haGeerntet = getXMLFloat(xml, key .. "#haGeerntet") or 0
            k.haGesaet   = getXMLFloat(xml, key .. "#haGesaet") or 0
            k.ernte = mengenLesen(xml, key .. ".ernte")
            k.saat  = mengenLesen(xml, key .. ".saat")
            k.spray = mengenLesen(xml, key .. ".spray")
            f = f + 1
        end
        n = n + 1
    end
end

-- ── Diagnose ─────────────────────────────────────────────────────────────────

function FieldLedger.debugDump(_, jahrArg)
    local jahr = tonumber(jahrArg) or jetztJahr()
    print("=== FA-KONTO-DUMP, Jahr " .. tostring(jahr) .. " ===")
    local liste = FieldLedger.alleRechnungen(jahr)
    if #liste == 0 then
        print("  Noch nichts gebucht. Gezaehlt wird beim Saeen, Duengen und Ernten.")
        return
    end
    print(string.format("  %-6s %7s %11s %11s %11s %11s",
        "Feld", "ha", "Erloes", "Saatgut", "Spritze", "DB/ha"))
    for _, r in ipairs(liste) do
        print(string.format("  %-6s %7.1f %11.0f %11.0f %11.0f %11.0f",
            tostring(r.feldId), r.ha or 0, r.erloes, r.saatKosten, r.sprayKosten,
            r.dbJeHa or 0))
        for _, f in ipairs(r.fruechte) do
            print(string.format("        %-16s %10.0f l = %9.0f",
                f.name, f.liter, f.wert))
        end
    end
end
