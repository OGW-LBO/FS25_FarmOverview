AnimalSalePlan = {}

AnimalSalePlan.LEISTUNG_REST = 0.7
AnimalSalePlan.LEISTUNG_AUS  = 0.2
AnimalSalePlan.ZUCHT_ANTEIL  = 0.1
AnimalSalePlan.FREI_ANTEIL   = 0.1

local RANG = { platz = 1, maennchen = 2, leistung = 3, drueber = 4, fenster = 5 }

local function frei(g)
    return (g.num or 0) - (g.verkaufen or 0) - (g.schutz or 0)
end

local function verkaufe(plan, g, anzahl, grund, auchGeschuetzt)
    local rest = (g.num or 0) - (g.verkaufen or 0)
    if not auchGeschuetzt then
        rest = rest - (g.schutz or 0)
    end
    anzahl = math.min(math.floor(anzahl), rest)
    if anzahl <= 0 then
        return 0
    end
    g.verkaufen = (g.verkaufen or 0) + anzahl
    g.schutz = math.min(g.schutz or 0, (g.num or 0) - g.verkaufen)
    if g.grund == nil or RANG[grund] < RANG[g.grund] then
        g.grund = grund
    end
    if plan.haupt == nil or RANG[grund] < RANG[plan.haupt] then
        plan.haupt = grund
    end
    plan.verkaufen = plan.verkaufen + anzahl
    if g.wert ~= nil then
        plan.wert = plan.wert + g.wert * anzahl
    end
    return anzahl
end

local function schuetze(g, anzahl, grund)
    anzahl = math.min(anzahl, (g.num or 0) - (g.verkaufen or 0) - (g.schutz or 0))
    if anzahl <= 0 then
        return 0
    end
    g.schutz = (g.schutz or 0) + anzahl
    if g.behalten == nil then
        g.behalten = grund
    end
    return anzahl
end

local function kopie(liste)
    local neu = {}
    for i, v in ipairs(liste) do
        neu[i] = v
    end
    return neu
end

local function nachAlter(liste, aufsteigend)
    table.sort(liste, function(a, b)
        if aufsteigend then
            return (a.age or 0) < (b.age or 0)
        end
        return (a.age or 0) > (b.age or 0)
    end)
    return liste
end

local function anteil(g)
    if (g.leistungMax or 0) <= 0 then
        return nil
    end
    return (g.leistung or 0) / g.leistungMax
end

local function laesstNach(g)
    local a = anteil(g)
    return a ~= nil and (g.age or 0) > (g.leistungAlter or 0) and a < AnimalSalePlan.LEISTUNG_REST
end

function AnimalSalePlan.planen(hub)
    local plan = { verkaufen = 0, wert = 0, nachkauf = {}, haupt = nil }
    hub.plan = plan

    local gruppen = hub.gruppen or {}
    for _, g in ipairs(gruppen) do
        g.verkaufen, g.schutz, g.grund, g.behalten = 0, 0, nil, nil
    end
    if #gruppen == 0 then
        return plan
    end

    local pferde = hub.animalType == "HORSE"
    local maennchenIdx = nil
    local maenner, leistung, mast = {}, {}, {}
    for _, g in ipairs(gruppen) do
        if not g.maennlich and g.maennchenIdx ~= nil then
            maennchenIdx = g.maennchenIdx
        end
        if pferde then
            schuetze(g, g.num or 0, "pferd")
        elseif g.maennlich then
            maenner[#maenner + 1] = g
        elseif (g.leistungMax or 0) > 0 then
            leistung[#leistung + 1] = g
        else
            mast[#mast + 1] = g
        end
    end
    local leistungsStall = #leistung > 0

    if maennchenIdx ~= nil then
        local reif, jung = {}, {}
        for _, g in ipairs(maenner) do
            if g.zuchtreif then
                reif[#reif + 1] = g
            else
                jung[#jung + 1] = g
            end
        end
        nachAlter(reif, true)
        nachAlter(jung, false)
        local brauche = 2
        if reif[1] ~= nil then
            schuetze(reif[1], 1, "zucht")
            brauche = 1
        end
        for _, g in ipairs(jung) do
            while brauche > 0 and frei(g) > 0 do
                local grund = (brauche == 2) and "zuchtJung" or "ersatz"
                brauche = brauche - schuetze(g, 1, grund)
            end
        end
        if #reif == 0 and #jung == 0 then
            plan.nachkauf[#plan.nachkauf + 1] = { idx = maennchenIdx, num = 1, grund = "maennchen" }
        end
        for _, g in ipairs(maenner) do
            if leistungsStall then
                verkaufe(plan, g, frei(g), "maennchen")
            else
                mast[#mast + 1] = g
            end
        end
    else
        for _, g in ipairs(maenner) do
            mast[#mast + 1] = g
        end
    end

    local ersatz = 0
    local nachlassend = {}
    for _, g in ipairs(leistung) do
        if laesstNach(g) then
            nachlassend[#nachlassend + 1] = g
        elseif (g.age or 0) < (g.leistungAlter or 0) and (anteil(g) or 0) < AnimalSalePlan.LEISTUNG_REST then
            ersatz = ersatz + (g.num or 0)
            schuetze(g, g.num or 0, "nachwuchs")
        else
            schuetze(g, g.num or 0, "leistung")
        end
    end
    table.sort(nachlassend, function(a, b) return (anteil(a) or 0) < (anteil(b) or 0) end)
    for _, g in ipairs(nachlassend) do
        if (anteil(g) or 0) < AnimalSalePlan.LEISTUNG_AUS then
            verkaufe(plan, g, g.num or 0, "leistung")
        else
            local weg = verkaufe(plan, g, math.min(g.num or 0, ersatz), "leistung")
            ersatz = ersatz - weg
            local bleibt = (g.num or 0) - weg
            if bleibt > 0 then
                schuetze(g, bleibt, "ersatzFehlt")
                plan.nachkauf[#plan.nachkauf + 1] = { idx = g.subIndex, num = bleibt, grund = "ersatz" }
            end
        end
    end

    local zuchtZiel = math.max(1, math.ceil((hub.maxCount or 0) * AnimalSalePlan.ZUCHT_ANTEIL))
    local zucht = 0
    local muetter = {}
    for _, g in ipairs(mast) do
        if not g.maennlich and g.tragend then
            zucht = zucht + schuetze(g, g.num or 0, "tragend")
        elseif not g.maennlich and g.zuchtreif then
            muetter[#muetter + 1] = g
        end
    end
    nachAlter(muetter, true)
    for _, g in ipairs(muetter) do
        if zucht >= zuchtZiel then
            break
        end
        if AnimalAnalyzer.verkaufsLage(g.age, g.peakAge) ~= "drueber" then
            zucht = zucht + schuetze(g, zuchtZiel - zucht, "zucht")
        end
    end
    for _, g in ipairs(mast) do
        local lage = AnimalAnalyzer.verkaufsLage(g.age, g.peakAge)
        if lage == "drueber" then
            verkaufe(plan, g, frei(g), "drueber")
        elseif lage == "fenster" then
            verkaufe(plan, g, frei(g), "fenster")
        else
            schuetze(g, frei(g), "jung")
        end
    end

    local ueber = (hub.count or 0) - (hub.maxCount or 0) - plan.verkaufen
    if (hub.maxCount or 0) > 0 and ueber > 0 then
        local reihen = { nachAlter(kopie(maenner), false), nachAlter(kopie(mast), false) }
        local lst = kopie(leistung)
        table.sort(lst, function(a, b) return (anteil(a) or 0) < (anteil(b) or 0) end)
        reihen[#reihen + 1] = lst
        if pferde then
            reihen = { nachAlter(kopie(gruppen), false) }
        end
        for runde = 1, 2 do
            for _, reihe in ipairs(reihen) do
                for _, g in ipairs(reihe) do
                    if ueber <= 0 then
                        break
                    end
                    local n
                    if runde == 1 then
                        n = verkaufe(plan, g, math.min(ueber, frei(g)), "platz")
                        if n == 0 and (g.behalten == "jung" or g.behalten == "leistung"
                                or g.behalten == "nachwuchs" or g.behalten == "pferd") then
                            n = verkaufe(plan, g, ueber, "platz", true)
                        end
                    else
                        n = verkaufe(plan, g, ueber, "platz", true)
                    end
                    ueber = ueber - n
                end
            end
        end
    end

    if leistungsStall and (hub.maxCount or 0) > 0 then
        local platz = (hub.maxCount or 0) - ((hub.count or 0) - plan.verkaufen)
        for _, k in ipairs(plan.nachkauf) do
            platz = platz - (k.num or 0)
        end
        local kommt = ersatz
        for _, g in ipairs(gruppen) do
            if g.tragend then
                kommt = kommt + (g.num or 0)
            end
        end
        if kommt == 0 and platz >= math.max(1, math.ceil(hub.maxCount * AnimalSalePlan.FREI_ANTEIL)) then
            local haeufig, meist = nil, 0
            for _, g in ipairs(leistung) do
                if (g.num or 0) > meist then
                    haeufig, meist = g.subIndex, g.num or 0
                end
            end
            if haeufig ~= nil then
                plan.nachkauf[#plan.nachkauf + 1] = { idx = haeufig, num = platz, grund = "frei" }
            end
        end
    end

    return plan
end
