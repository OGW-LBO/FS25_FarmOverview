-- YieldBridge.lua
-- Zeigt im Bereich FELDER, mit welchen Ertragsfaktoren gerade gerechnet wird.
--
-- Die Mod FS25_ErtragsFaktor verstellt zur Laufzeit die Fruchtwerte des Spiels
-- (literPerSqm, windrowLiterPerSqm, seedUsagePerSqm). Die Betriebsuebersicht
-- liest diese Werte ohnehin jedes Mal frisch, rechnet also automatisch mit den
-- verstellten Zahlen - nur sieht man ihnen das nicht an. Diese Datei haengt
-- deshalb ein paar Zeilen unter die Feldliste.
--
-- Gelesen wird nur, nie geschrieben:
--   ErtragsFaktor.CFG, .KAT_CFG, .KAT_ORDER, .MIN_FAKTOR/.MAX_FAKTOR
-- Zugriff ueber die Mod-Umgebung getfenv(0)["FS25_ErtragsFaktor"], Muster aus
-- FinanceBridge. Fehlt die Mod, bleiben die Zeilen weg.

YieldBridge = {}

YieldBridge.MOD_NAME = "FS25_ErtragsFaktor"

-- Gruppen-Schluessel der Fremdmod -> eigener Text. Die Reihenfolge gibt
-- ErtragsFaktor.KAT_ORDER vor, diese Tabelle liefert nur die Beschriftung.
YieldBridge.GRUPPEN_TEXT = {
    getreide = "fa_yf_getreide",
    mais     = "fa_yf_mais",
    oel      = "fa_yf_oel",
    hack     = "fa_yf_hack",
    huelsen  = "fa_yf_huelsen",
    gras     = "fa_yf_gras",
    zwischen = "fa_yf_zwischen",
    obst     = "fa_yf_obst",
    sonder   = "fa_yf_sonder",
}

local FARBE = {
    normal = { 1.00, 1.00, 1.00 },
    grau   = { 0.62, 0.62, 0.62 },
    gelb   = { 1.00, 0.90, 0.30 },
}

local function L(key, fallback)
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        return g_i18n:getText(key)
    end
    return fallback or key
end

--- Mod-Umgebung des ErtragsFaktors, oder nil wenn die Mod nicht laeuft.
function YieldBridge.env()
    local env = nil
    if getfenv ~= nil then
        local global = getfenv(0)
        if type(global) == "table" then
            env = global[YieldBridge.MOD_NAME]
        end
    end
    if env == nil then
        env = _G[YieldBridge.MOD_NAME]
    end
    if type(env) == "table" and type(env.ErtragsFaktor) == "table"
            and type(env.ErtragsFaktor.CFG) == "table"
            and type(env.ErtragsFaktor.KAT_ORDER) == "table" then
        return env
    end
    return nil
end

function YieldBridge.isAvailable()
    return YieldBridge.env() ~= nil
end

local function zahl(f)
    return string.format("x%.2f", f)
end

--- Zeilen fuer die Feldliste. Leer, wenn die Mod fehlt.
-- Aufgefuehrt wird nur, was von 1.00 abweicht - sonst stuenden dort neun
-- Zeilen "x1.00" und die eine interessante ginge darin unter.
function YieldBridge.getRows()
    local out = {}
    local env = YieldBridge.env()
    if env == nil then return out end

    local EF  = env.ErtragsFaktor
    local cfg = EF.CFG

    out[#out + 1] = { section = L("fa_yf_sec", "Yield factors") }

    if cfg.aktiv == false then
        out[#out + 1] = { cells = {
            { t = L("fa_yf_status", "Status"), col = FARBE.grau },
            { t = L("fa_yf_aus", "off - map values"), col = FARBE.grau },
        } }
        return out
    end

    local modus = tonumber(cfg.modus) or 0
    out[#out + 1] = { cells = {
        { t = L("fa_yf_basis", "Basis"), col = FARBE.grau },
        { t = (modus == 1) and L("fa_yf_basisRef", "base game reference")
                           or L("fa_yf_basisKarte", "map values"), col = FARBE.normal },
    } }

    local anzahl = 0
    for _, kat in ipairs(EF.KAT_ORDER) do
        local key = EF.KAT_CFG ~= nil and EF.KAT_CFG[kat] or nil
        local f   = key ~= nil and tonumber(cfg[key]) or nil
        if f ~= nil and math.abs(f - 1.0) > 0.001 then
            anzahl = anzahl + 1
            out[#out + 1] = { cells = {
                { t = L(YieldBridge.GRUPPEN_TEXT[kat] or kat, kat), col = FARBE.grau },
                { t = zahl(f), col = FARBE.gelb },
            } }
        end
    end

    for _, eintrag in ipairs({ { "fStroh", "fa_yf_stroh", "Straw" },
                               { "fSaatgut", "fa_yf_saat", "Seed usage" } }) do
        local f = tonumber(cfg[eintrag[1]])
        if f ~= nil and math.abs(f - 1.0) > 0.001 then
            anzahl = anzahl + 1
            out[#out + 1] = { cells = {
                { t = L(eintrag[2], eintrag[3]), col = FARBE.grau },
                { t = zahl(f), col = FARBE.gelb },
            } }
        end
    end

    -- Modus 1 verstellt die Werte auch bei lauter Faktoren 1.00: dort ist die
    -- Basis die Referenztabelle, nicht die Karte. Deshalb nur im Modus 0 der
    -- Hinweis, dass gar nichts passiert.
    if anzahl == 0 and modus ~= 1 then
        out[#out + 1] = { cells = {
            { t = L("fa_yf_neutral", "all factors 1.00"), col = FARBE.grau },
        } }
    end

    return out
end
