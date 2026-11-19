-- FinanceBridge.lua
-- Bereich "Finanzen": zeigt den Jahresvergleich der Mod FS25_FarmEconomy
-- (Agrar-Oekonomie) - Stand des Betriebs, Einnahmen, Ausgaben, Ergebnis,
-- jeweils gegen denselben Zeitraum des Vorjahres.
--
-- Die Zahlen erfasst FarmEconomy (AOBericht.lua, Geld-Hook + Monatssummen,
-- Server autoritativ, MP-Event). Diese Datei liest nur:
--   AOBericht.paket, AOBericht.GRUPPEN, AOBericht.STAND,
--   AOBericht.anfordern(), AOBericht.monatsName(p),
--   AOSettingsPage.getText(key)   (Texte liegen in FarmEconomys l10n),
--   AgrarOekonomie.formatGeld(v)
-- Zugriff ueber die Mod-Umgebung getfenv(0)["FS25_FarmEconomy"] (Muster
-- CabCinematic ModHelper). Fehlt FarmEconomy, ist der Bereich ausgeblendet.
--
-- Aufbau und Rechenregeln 1:1 aus der frueheren AOBerichtPage.lua.

FinanceBridge = {}

FinanceBridge.MOD_NAME = "FS25_FarmEconomy"

local FARBE = {
    gut      = { 0.45, 0.80, 0.30 },
    schlecht = { 0.95, 0.40, 0.30 },
    normal   = { 1, 1, 1 },
    grau     = { 0.62, 0.62, 0.62 },
    gruen    = { 0.60, 0.95, 0.35 },
}

--- Mod-Umgebung von FarmEconomy, oder nil wenn nicht geladen.
function FinanceBridge.env()
    local env = nil
    if getfenv ~= nil then
        local global = getfenv(0)
        if type(global) == "table" then
            env = global[FinanceBridge.MOD_NAME]
        end
    end
    if env == nil then
        env = _G[FinanceBridge.MOD_NAME]
    end
    if type(env) == "table" and type(env.AOBericht) == "table"
            and type(env.AOBericht.GRUPPEN) == "table" and type(env.AOBericht.STAND) == "table" then
        return env
    end
    return nil
end

function FinanceBridge.isAvailable()
    return FinanceBridge.env() ~= nil
end

--- Aktuelles Paket anfordern (Einzelspieler/Host: sofort, Client: per Event).
function FinanceBridge.request()
    local env = FinanceBridge.env()
    if env ~= nil and env.AOBericht.anfordern ~= nil then
        env.AOBericht.anfordern()
    end
end

--- Zuletzt erhaltenes Paket (zum Erkennen, ob neu gezeichnet werden muss).
function FinanceBridge.paket()
    local env = FinanceBridge.env()
    if env == nil then
        return nil
    end
    return env.AOBericht.paket
end

local function t(env, key)
    if env ~= nil and env.AOSettingsPage ~= nil and env.AOSettingsPage.getText ~= nil then
        return env.AOSettingsPage.getText(key)
    end
    return key
end

local function geld(env, v)
    if env ~= nil and env.AgrarOekonomie ~= nil and env.AgrarOekonomie.formatGeld ~= nil then
        return env.AgrarOekonomie.formatGeld(v or 0)
    end
    return string.format("%d", math.floor((v or 0) + 0.5))
end

local function index(liste, wert)
    for i, v in ipairs(liste) do
        if v == wert then
            return i
        end
    end
    return nil
end

local function wertText(env, v, einheit)
    if einheit == "ha" then
        return string.format("%.1f ha", v or 0)
    end
    return geld(env, v)
end

--- Text und Farbe der Veraenderung. invers: weniger ist besser (Kredit).
local function veraenderung(env, jetzt, vor, hatVor, einheit, invers)
    if not hatVor then
        return "-", FARBE.grau
    end
    local diff = jetzt - vor
    if einheit == "ha" then
        if math.abs(diff) < 0.05 then
            return "0.0 ha", FARBE.grau
        end
        return string.format("%+.1f ha", diff), FARBE.normal
    end
    if math.abs(diff) < 1 then
        return "0 %", FARBE.grau
    end
    local besser = diff > 0
    if invers then
        besser = not besser
    end
    local farbe = besser and FARBE.gut or FARBE.schlecht
    if math.abs(vor) < 1 then
        return t(env, "ao_rep_neu"), farbe
    end
    -- Vorzeichenwechsel: Prozent sagt nichts, Differenz zeigen
    if (jetzt > 0) ~= (vor > 0) then
        local txt = geld(env, diff)
        if diff > 0 then
            txt = "+" .. txt
        end
        return txt, farbe
    end
    local prozent = (math.abs(jetzt) - math.abs(vor)) / math.abs(vor) * 100
    return string.format("%+.0f %%", prozent), farbe
end

local function zeile(a, aCol, b, c, d, dCol)
    return { cells = {
        { t = a or "", col = aCol or FARBE.normal },
        { t = b or "", col = FARBE.normal },
        { t = c or "", col = FARBE.grau },
        { t = d or "", col = dCol or FARBE.grau },
        { t = "" }, { t = "" },
    } }
end

local function kopf(env, spalten)
    return { head = { "", t(env, spalten[1]), t(env, spalten[2]), t(env, spalten[3]), "", "" } }
end

local function abschnittText(env, B, p, schluessel)
    local vorlage = t(env, schluessel)
    local von = B.monatsName ~= nil and B.monatsName(p.von) or tostring(p.von)
    local bis = B.monatsName ~= nil and B.monatsName(p.bis) or tostring(p.bis)
    -- Nur formatieren, wenn die Vorlage genau zwei %s hat
    local _, n = string.gsub(vorlage, "%%s", "")
    local ohneProzent = (string.gsub(vorlage, "%%%%", ""))
    local _, alle = string.gsub(ohneProzent, "%%", "")
    if n == 2 and alle == 2 then
        return string.format(vorlage, tostring(von), tostring(bis))
    end
    return vorlage
end

--- Zeilen fuer die Liste der Betriebsuebersicht (6-Spalten-Format).
function FinanceBridge.getRows()
    local rows = {}
    local env = FinanceBridge.env()
    if env == nil then
        rows[#rows + 1] = zeile(FruchtfolgeAdvisor.L("fa_fin_none", "Farm Economy is not installed."), FARBE.grau)
        return rows
    end
    local B = env.AOBericht
    local p = B.paket
    if p == nil then
        rows[#rows + 1] = { section = t(env, "ao_rep_secLaden") }
        return rows
    end

    local kopfStand = { "ao_rep_colJetzt", "ao_rep_colVorEinemJahr", "ao_rep_colAenderung" }
    local kopfJahr  = { "ao_rep_colJahr",  "ao_rep_colVorjahr", "ao_rep_colAenderung" }

    -- Stand des Betriebs
    rows[#rows + 1] = { section = t(env, p.standVergleich and "ao_rep_secStand" or "ao_rep_secStandOhne") }
    rows[#rows + 1] = kopf(env, kopfStand)
    local STAND_ZEILEN = {
        { key = "vermoegen", label = "ao_rep_vermoegen", fett = true },
        { key = "geld",      label = "ao_rep_geld" },
        { key = "kredit",    label = "ao_rep_kredit", invers = true },
        { key = "fahrzeuge", label = "ao_rep_fahrzeuge" },
        { key = "gebaeude",  label = "ao_rep_gebaeude" },
        { key = "land",      label = "ao_rep_land" },
        { key = "landHa",    label = "ao_rep_landHa", einheit = "ha" },
        { key = "feldHa",    label = "ao_rep_feldHa", einheit = "ha" },
    }
    for _, def in ipairs(STAND_ZEILEN) do
        local i = index(B.STAND, def.key)
        if i ~= nil then
            local jetzt = p.stand[i] or 0
            local vor   = p.standVorjahr[i] or 0
            local diff, farbe = veraenderung(env, jetzt, vor, p.standVergleich, def.einheit, def.invers)
            rows[#rows + 1] = zeile(t(env, def.label), def.fett and FARBE.gruen or FARBE.normal,
                wertText(env, jetzt, def.einheit),
                p.standVergleich and wertText(env, vor, def.einheit) or "-",
                diff, farbe)
        end
    end

    local function summe(art, feld)
        local s = 0
        for i, g in ipairs(B.GRUPPEN) do
            if (art == "ergebnis" and (g.art == "ein" or g.art == "aus")) or g.art == art then
                s = s + (p.gruppen[i] and p.gruppen[i][feld] or 0)
            end
        end
        return s
    end

    local function gruppenZeilen(art)
        for i, g in ipairs(B.GRUPPEN) do
            if g.art == art then
                local gr = p.gruppen[i] or {}
                local jetzt, vor = gr.jetzt or 0, gr.vorjahr or 0
                -- Leere Gruppen ausblenden (z. B. Biogas ohne Anlage)
                if math.abs(jetzt) >= 0.5 or (p.vergleich and math.abs(vor) >= 0.5) then
                    local diff, farbe = veraenderung(env, jetzt, vor, p.vergleich, nil, false)
                    rows[#rows + 1] = zeile("  " .. t(env, g.label), FARBE.normal,
                        geld(env, jetzt), p.vergleich and geld(env, vor) or "-", diff, farbe)
                end
            end
        end
    end

    local function summenZeile(art, label, fett)
        local jetzt, vor = summe(art, "jetzt"), summe(art, "vorjahr")
        local diff, farbe = veraenderung(env, jetzt, vor, p.vergleich, nil, false)
        rows[#rows + 1] = zeile(t(env, label), fett and FARBE.gruen or FARBE.normal,
            geld(env, jetzt), p.vergleich and geld(env, vor) or "-", diff, farbe)
    end

    for _, block in ipairs({
        { id = "ao_rep_secEinnahmen", art = "ein", summe = "ao_rep_summeEin" },
        { id = "ao_rep_secAusgaben",  art = "aus", summe = "ao_rep_summeAus" },
    }) do
        rows[#rows + 1] = { section = abschnittText(env, B, p, block.id) }
        rows[#rows + 1] = kopf(env, kopfJahr)
        gruppenZeilen(block.art)
        summenZeile(block.art, block.summe, true)
    end

    rows[#rows + 1] = { section = abschnittText(env, B, p, "ao_rep_secErgebnis") }
    rows[#rows + 1] = kopf(env, kopfJahr)
    summenZeile("ergebnis", "ao_rep_ergebnis", true)
    gruppenZeilen("inv")
    summenZeile("inv", "ao_rep_investSumme", false)

    -- Erloes je Feldhektar (Ernte + Produkte)
    local iHa = index(B.STAND, "feldHa")
    if iHa ~= nil then
        local haJ, haV = p.stand[iHa] or 0, p.standVorjahr[iHa] or 0
        local erlJ = (p.gruppen[1] and p.gruppen[1].jetzt or 0) + (p.gruppen[2] and p.gruppen[2].jetzt or 0)
        local erlV = (p.gruppen[1] and p.gruppen[1].vorjahr or 0) + (p.gruppen[2] and p.gruppen[2].vorjahr or 0)
        local jetzt = haJ > 0 and erlJ / haJ or 0
        local vor   = haV > 0 and erlV / haV or 0
        local hatVor = p.vergleich and p.standVergleich and haV > 0
        local diff, farbe = veraenderung(env, jetzt, vor, hatVor, nil, false)
        rows[#rows + 1] = zeile(t(env, "ao_rep_proHa"), FARBE.normal,
            geld(env, jetzt), hatVor and geld(env, vor) or "-", diff, farbe)
    end
    return rows
end
