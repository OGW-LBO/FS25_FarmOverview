-- FruchtfolgeAdvisor.lua
local modDir = g_currentModDirectory

FruchtfolgeAdvisor = {}

-- ── Lokalisierung ─────────────────────────────────────────────
-- Text aus den i18n-Dateien (folgt automatisch der Spielsprache).
-- Fehlt der Key, wird der Fallback (oder der Key) zurueckgegeben — nie ein
-- "Missing"-Platzhalter, und dank hasText-Pruefung kein Log-Warnungsspam.
local function L(key, fallback)
    local out = nil
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        out = g_i18n:getText(key)
    end
    if out == nil or out == "" then return fallback or key end
    return out
end
FruchtfolgeAdvisor.L = L

-- Text mit Platzhaltern, gleiche Schreibweise wie im TaskAnalyzer. Muss hier
-- oben stehen: eine local function ist in Lua erst ab ihrer Definitionszeile
-- sichtbar, und benutzt wird sie weiter unten in den Listenzeilen.
local function F(key, fallback, ...)
    return string.format(L(key, fallback), ...)
end

-- ObsoleteFiles/l10n-Nachweis: Der ModHub-TestRunner erkennt nur LITERALE
-- getText("...")-Aufrufe. Da alle echten Zugriffe ueber L(key) mit einer
-- Variablen laufen, werden hier einmalig alle i18n-Keys literal referenziert,
-- damit i18n_de/en.xml als benutzt gelten (und fehlende Texte frueh auffallen).
function FruchtfolgeAdvisor.referenceL10n()
    if g_i18n == nil or g_i18n.getText == nil then return end
    g_i18n:getText("fa_title")
    g_i18n:getText("fa_tab_fields")
    g_i18n:getText("fa_tab_storage")
    g_i18n:getText("fa_tab_animals")
    g_i18n:getText("fa_tab_production")
    g_i18n:getText("fa_tab_report")
    g_i18n:getText("fa_h_field")
    g_i18n:getText("fa_h_area")
    g_i18n:getText("fa_h_current")
    g_i18n:getText("fa_h_soil")
    g_i18n:getText("fa_h_recommend")
    g_i18n:getText("fa_h_bonus")
    g_i18n:getText("fa_h_goods")
    g_i18n:getText("fa_h_stock")
    g_i18n:getText("fa_h_demand")
    g_i18n:getText("fa_h_demandmo")
    g_i18n:getText("fa_h_range")
    g_i18n:getText("fa_h_market")
    g_i18n:getText("fa_h_animal")
    g_i18n:getText("fa_h_count")
    g_i18n:getText("fa_h_age")
    g_i18n:getText("fa_h_note")
    g_i18n:getText("fa_h_feed")
    g_i18n:getText("fa_grp_feed")
    g_i18n:getText("fa_grp_crops")
    g_i18n:getText("fa_grp_animalprod")
    g_i18n:getText("fa_grp_supplies")
    g_i18n:getText("fa_grp_other")
    g_i18n:getText("fa_sec_herd")
    g_i18n:getText("fa_sec_feeddemand")
    g_i18n:getText("fa_sec_tmr")
    g_i18n:getText("fa_sec_todo")
    g_i18n:getText("fa_field")
    g_i18n:getText("fa_fallow")
    g_i18n:getText("fa_worked")
    g_i18n:getText("fa_collapse")
    g_i18n:getText("fa_lbl_score")
    g_i18n:getText("fa_outlook")
    g_i18n:getText("fa_unit_mo")
    g_i18n:getText("fa_unit_lmo")
    g_i18n:getText("fa_unit_day")
    g_i18n:getText("fa_unit_days")
    g_i18n:getText("fa_unit_month")
    g_i18n:getText("fa_unit_months")
    g_i18n:getText("fa_unit_years")
    g_i18n:getText("fa_reach_max")
    g_i18n:getText("fa_active")
    g_i18n:getText("fa_off")
    g_i18n:getText("fa_input")
    g_i18n:getText("fa_output")
    g_i18n:getText("fa_empty")
    g_i18n:getText("fa_production")
    g_i18n:getText("fa_recipe")
    g_i18n:getText("fa_barn_full")
    g_i18n:getText("fa_overaged")
    g_i18n:getText("fa_overaged_sell")
    g_i18n:getText("fa_low")
    g_i18n:getText("fa_plan_supply")
    g_i18n:getText("fa_d_plan_over")
    g_i18n:getText("fa_sell_expand")
    g_i18n:getText("fa_sell_now")
    g_i18n:getText("fa_input_empty")
    g_i18n:getText("fa_missing")
    g_i18n:getText("fa_no_action")
    g_i18n:getText("fa_health_verygood")
    g_i18n:getText("fa_health_good")
    g_i18n:getText("fa_health_mid")
    g_i18n:getText("fa_health_weak")
    g_i18n:getText("fa_health_exhausted")
    g_i18n:getText("fa_animal_COW")
    g_i18n:getText("fa_animal_PIG")
    g_i18n:getText("fa_animal_SHEEP")
    g_i18n:getText("fa_animal_HORSE")
    g_i18n:getText("fa_animal_CHICKEN")
end

-- ── Zustand ──────────────────────────────────────────────────
FruchtfolgeAdvisor.open       = false
FruchtfolgeAdvisor.tab        = 1
FruchtfolgeAdvisor.selField   = 1
FruchtfolgeAdvisor.scroll     = 1
FruchtfolgeAdvisor.prodSel    = 1
FruchtfolgeAdvisor.prodScroll = 1
FruchtfolgeAdvisor.prodDetailScroll = 1
FruchtfolgeAdvisor.prodDetailMax    = 1
FruchtfolgeAdvisor.prodSplitX       = nil
FruchtfolgeAdvisor.storScroll = 1
FruchtfolgeAdvisor.storMaxScroll = 1
FruchtfolgeAdvisor.animScroll = 1
FruchtfolgeAdvisor.animMaxScroll = 1
FruchtfolgeAdvisor.reportScroll = 1
FruchtfolgeAdvisor.reportMax    = 1
FruchtfolgeAdvisor.soilCache  = {}
FruchtfolgeAdvisor.planCache  = {}
-- Fertig aufgebaute Zeilenlisten pro Tab (Neuaufbau nur bei neuem
-- cacheStamp statt jeden Frame — spart Tabellen/String-Allokationen)
FruchtfolgeAdvisor.lineCache  = {}
FruchtfolgeAdvisor.cache      = nil
FruchtfolgeAdvisor.cacheStamp = 0
-- true, wenn die native SmoothList den Lager-Tab anzeigt (Screen setzt das)
FruchtfolgeAdvisor.nativeStorListActive = false
-- true, wenn die generische native Liste den aktuellen Bereich anzeigt (Screen setzt das).
-- Dann unterdrueckt das Overlay seinen eigenen Inhalt fuer diesen Bereich.
FruchtfolgeAdvisor.nativeListActive = false
FruchtfolgeAdvisor.overlay    = nil
-- Klickbare Bereiche (jede Frame beim Zeichnen neu gefuellt):
-- { x=, y=, w=, h=, kind="tab"|"field", index= }
FruchtfolgeAdvisor.clickRegions = {}

local TAB_NAMES     = { "Felder", "Lager", "Tiere", "Produktion", "Report" }
local VISIBLE_FIELDS = 15

-- Ab wie vielen Monaten Reichweite gilt eine Frucht als knapp. Unter 1.5
-- Monaten wird sie rot, darunter bis zu diesem Wert gelb - dieselbe Schwelle,
-- die auch der Handlungsbedarf-Report benutzt.
FruchtfolgeAdvisor.KNAPP_MONATE = 3.0
FruchtfolgeAdvisor.KRITISCH_MONATE = 1.5

-- So viele Tiergruppen zeigt ein Stall; der Rest steht als "+ n weitere".
-- Jede Rasse-Alter-Kombination ist eine eigene Gruppe, bei grossen Herden
-- werden das sonst zwanzig Zeilen fuer einen Stall.
FruchtfolgeAdvisor.MAX_TIERGRUPPEN = 6

-- ── Empfehlungs-Gedaechtnis (gegen Springen der Saatfrucht) ──────────────────
-- buildCache rechnet alle 5 s neu. Lagerverbrauch, frische Ernten und die Kette
-- usage/plannedStorage ueber die Felder verschieben die Punkte staendig ein
-- wenig; liegen zwei Fruechte dicht beieinander, tauschten sie dadurch laufend
-- die Spitze, obwohl sich am Feld nichts geaendert hat.
--   [fieldId] = { crop = "OAT", currentFruit = …, prevFruit = … }
-- Die gemerkte Frucht bleibt vorn, solange der neue Spitzenreiter nicht
-- mindestens HYSTERESE_SCORE besser ist. Vergessen wird sie nur, wenn sich am
-- Feld wirklich etwas tut (bestellt oder abgeerntet -> currentFruit/prevFruit).
-- Rein lokal und ohne Zufall: Jeder Client rechnet mit denselben Werten und
-- kommt auf dasselbe Ergebnis, es wird also nichts uebers Netz geschickt.
FruchtfolgeAdvisor.lastTop = {}
FruchtfolgeAdvisor.HYSTERESE_SCORE = 0.05
-- Wie viele knappe Fruechte die Bedarfszeile nennt. Gilt auch fuer das "!" in
-- den Feldzeilen, damit Zeile und Markierung dieselben Fruechte meinen.
FruchtfolgeAdvisor.KNAPP_MAX_ANZEIGE = 5

-- ── Farben ───────────────────────────────────────────────────
-- Farbpalette wie die Giants-Menues (Vorbild: PREISE-Seite):
-- dunkles Blaugrau als Grund, sattes Giants-Gruen fuer die Auswahl
-- (mit dunkler Schrift darauf), Zahlen weiss, Sekundaeres grau.
local C = {
    card   = {0.055, 0.075, 0.095, 0.92},  -- Panelflaeche mit Blaustich
    tabOn  = {0.435, 0.690, 0.200, 1.00},  -- Giants-Gruen
    selRow = {0.435, 0.690, 0.200, 0.92},  -- Auswahl: sattes Gruen
    dark   = {0.04, 0.06, 0.04, 1.00},     -- dunkle Schrift auf Auswahl-Gruen
    white  = {1.00, 1.00, 1.00, 1.00},
    green  = {0.60, 0.95, 0.35, 1.00},     -- Akzentgruen (Texte)
    yellow = {1.00, 0.90, 0.30, 1.00},
    red    = {1.00, 0.35, 0.30, 1.00},
    grey   = {0.62, 0.62, 0.62, 1.00},
    lblue  = {0.78, 0.87, 1.00, 1.00},
}

-- ── Overlay-Helfer ────────────────────────────────────────────
-- WICHTIG: reinweisse Textur als Rechteck-Basis. Vorher wurde icon.dds
-- getintet — dessen gruene Pfeil-Grafik erschien als Schlieren/Streifen
-- auf allen Flaechen (auf Screenshots klar sichtbar).
local function ensureOverlay()
    if FruchtfolgeAdvisor.overlay ~= nil then return end
    FruchtfolgeAdvisor.overlay = createImageOverlay(modDir .. "images/white.dds")
    if FruchtfolgeAdvisor.overlay == nil then
        FruchtfolgeAdvisor.overlay = createImageOverlay(modDir .. "icon.dds")
    end
end

local function rect(x, y, w, h, col)
    if FruchtfolgeAdvisor.overlay == nil then return end
    setOverlayColor(FruchtfolgeAdvisor.overlay, col[1], col[2], col[3], col[4])
    renderOverlay(FruchtfolgeAdvisor.overlay, x, y, w, h)
end

local function txt(x, y, size, str, col, bold, align)
    if str == nil or str == "" then return end
    setTextColor(col[1], col[2], col[3], col[4])
    setTextBold(bold == true)
    setTextAlignment(align or RenderText.ALIGN_LEFT)
    renderText(x, y, getCorrectTextSize(size), tostring(str))
    setTextBold(false)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

-- Grafischer Fortschrittsbalken: dunkler Hintergrund + farbige Fuellung
-- (Optik wie die Vanilla-Menues, gezeichnet per renderOverlay).
-- Wiederverwendete Farbtabellen: laeuft jeden Frame, keine Allokationen.
local hbarBg   = { 0, 0, 0, 0.45 }
local hbarFill = { 1, 1, 1, 0.90 }
local function hbar(x, y, w, h, frac, col)
    frac = math.max(0, math.min(1, frac or 0))
    rect(x, y, w, h, hbarBg)
    if frac > 0 then
        hbarFill[1], hbarFill[2], hbarFill[3] = col[1], col[2], col[3]
        rect(x, y, w * frac, h, hbarFill)
    end
end

local function statusColor(months)
    if months >= 3.0 then return C.green end
    if months >= 1.5 then return C.yellow end
    return C.red
end

-- Haelt die Empfehlung eines Feldes stabil (siehe FruchtfolgeAdvisor.lastTop).
-- Gibt die Frucht zurueck, die fuer dieses Feld gilt, und sortiert sie dabei in
-- `recs` nach vorn. Rueckgabe nil nur, wenn es gar keine Empfehlung gibt.
function FruchtfolgeAdvisor.stabilisiereEmpfehlung(fi, recs)
    local neu = recs[1]
    local key = fi ~= nil and fi.fieldId or nil
    if neu == nil or key == nil then return neu end

    -- Wer ohne Gedaechtnis oben staende - nur fuer die Diagnose (faFeld).
    local rohCrop = neu.crop

    local merk = FruchtfolgeAdvisor.lastTop[key]

    -- Am Feld hat sich etwas getan (bestellt, geerntet, Vorfrucht gewandert):
    -- dann ist die alte Empfehlung gegenstandslos.
    if merk ~= nil and (merk.currentFruit ~= fi.currentFruit
            or merk.prevFruit ~= fi.prevFruit) then
        merk = nil
    end

    if merk ~= nil and merk.crop ~= neu.crop then
        -- Die gemerkte Frucht in der neuen Rangliste suchen. Fehlt sie (in den
        -- Einstellungen abgeschaltet oder inzwischen selbst die Feldfrucht),
        -- gewinnt der neue Spitzenreiter.
        local alt, altIdx = nil, nil
        for i, r in ipairs(recs) do
            if r.crop == merk.crop then
                alt, altIdx = r, i
                break
            end
        end
        if alt ~= nil and (neu.totalScore or 0) - (alt.totalScore or 0)
                < FruchtfolgeAdvisor.HYSTERESE_SCORE then
            table.remove(recs, altIdx)
            table.insert(recs, 1, alt)
            neu = alt
        end
    end

    FruchtfolgeAdvisor.lastTop[key] = {
        crop         = neu.crop,
        currentFruit = fi.currentFruit,
        prevFruit    = fi.prevFruit,
        -- gesetzt, wenn die Hysterese gerade gegriffen hat
        gehaltenStatt = (neu.crop ~= rohCrop) and rohCrop or nil,
    }
    return neu
end

-- ── Cache aufbauen ────────────────────────────────────────────
function FruchtfolgeAdvisor.buildCache()
    -- Nachziehen, falls die Map ihre Fruechte erst NACH unserem loadMap
    -- registriert hat. Auf Beuren wurde 'onion' rund 0,3 s nach initFromMap
    -- geladen - dort war der FruitType schon registriert, verlassen sollte man
    -- sich darauf aber nicht. Billiger Vergleich der Anzahl, kein Dauerlauf.
    local function fruechteNachziehen()
        if CropRotationData == nil or CropRotationData.initFromMap == nil then return end
        if g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypes == nil then return end
        local n = 0
        for _ in pairs(g_fruitTypeManager:getFruitTypes() or {}) do n = n + 1 end
        if n > 0 and n ~= (FruchtfolgeAdvisor._knownFruitCount or -1) then
            FruchtfolgeAdvisor._knownFruitCount = n
            CropRotationData.initFromMap()
        end
    end
    fruechteNachziehen()

    -- Ertraege frisch lesen: ErtragsFaktor u.a. aendern sie zur Laufzeit.
    if CropRotationData ~= nil and CropRotationData.refreshYields ~= nil then
        CropRotationData.refreshYields()
    end

    -- Eigene Funktion: ein fruehes return beendet nur den Aufbau. Ein Fehler
    -- darin landet mit Stacktrace im Log; der Cache behaelt dann seinen
    -- letzten Stand (getFieldRows faengt einen fehlenden Cache ab).
    local function baueCache()
        -- Gemeinsame Basis: einmal laden
        local allFields     = FieldAnalyzer.getOwnFields()
        local storageTotals = StorageAnalyzer.getTotals()
        -- Fassungsvermoegen je Fuelltyp fuer die Anzeige "Menge / Kapazitaet"
        local storageCaps   = (StorageAnalyzer.getCapacities ~= nil)
            and StorageAnalyzer.getCapacities() or {}
        local productions   = ProductionAnalyzer.getProductions(FieldAnalyzer.getLocalFarmId())
        local animalNeeds   = AnimalAnalyzer.getNeedsPerMonth(storageTotals)
        -- Eingangsbedarf aktiver Produktionen fliesst in alle
        -- Verbrauchs-/Reichweiten-Rechnungen ein
        animalNeeds.productionNeeds = ProductionAnalyzer.getInputNeedsPerMonth(productions)
        -- Echte Verkaufspreis-Kurven (Peak-Preis + Peak-Alter je Tierart)
        if AnimalAnalyzer.getPeakPrices ~= nil then
            animalNeeds.peakPrices = AnimalAnalyzer.getPeakPrices() or {}
        end
        -- Was die eigenen Staelle selbst liefern (Mist, Guelle, Milch, Wolle)
        if AnimalAnalyzer.getHofProdukte ~= nil then
            animalNeeds.hofProdukte = AnimalAnalyzer.getHofProdukte(FieldAnalyzer.getLocalFarmId()) or {}
        end

        -- Nur eigene Felder
        local ownFields = {}
        for _, fi in ipairs(allFields) do
            if fi.isOwn then table.insert(ownFields, fi) end
        end

        -- Empfehlungen - zwei Mechanismen fuer Abwechslung ueber den Hof:
        -- 1. usage-Zaehler wertet bereits vergebene Top-Empfehlungen ab.
        -- 2. plannedStorage rechnet die erwartete Ernte bereits empfohlener
        --    Felder dem Lager virtuell zu: ist der Silage-/Futterbedarf durch
        --    2-3 Felder gedeckt, verliert dieselbe Frucht ihre Dringlichkeit.
        local fieldResults   = {}
        local usage          = {}
        local plannedStorage = {}
        for _, fi in ipairs(ownFields) do
            local virtualStorage = {}
            for k, v in pairs(storageTotals) do virtualStorage[k] = v end
            for k, v in pairs(plannedStorage) do
                virtualStorage[k] = (virtualStorage[k] or 0) + v
            end

            local recs = RecommendationEngine.recommendForField(fi, virtualStorage, animalNeeds, usage)
            -- Hysterese: haelt die zuletzt gezeigte Frucht oben, solange der
            -- neue Spitzenreiter nicht deutlich besser ist. Sortiert sie in der
            -- Rangliste nach vorn, damit Anzeige, usage und plannedStorage
            -- dieselbe Frucht meinen - sonst wuerden die folgenden Felder mit
            -- einer anderen Planung rechnen als angezeigt wird.
            local top = FruchtfolgeAdvisor.stabilisiereEmpfehlung(fi, recs)

            -- Weitblick-Plan wird NICHT mehr fuer alle Felder vorgerechnet
            -- (nur noch eine Zeile im Feld-Detail sichtbar) — er entsteht
            -- lazy pro ausgewaehltem Feld in getPlanFor(). Spart ~100
            -- planField-Laeufe pro Menue-Oeffnen.

            if top ~= nil then
                usage[top.crop] = (usage[top.crop] or 0) + 1
                -- Geplante Ernte dem virtuellen Lager gutschreiben
                local products = CropRotationData.FRUIT_PRODUCTS[top.crop]
                if products ~= nil then
                    local yield = (CropRotationData.YIELD_L_PER_HA[top.crop] or 5000)
                        * ((fi.area or 0) / 10000)
                    for pi, product in ipairs(products) do
                        local amt = (pi == 1) and yield or (yield * 0.4)
                        plannedStorage[product] = (plannedStorage[product] or 0) + amt
                    end
                end
            end
            table.insert(fieldResults, {
                fieldInfo       = fi,
                recommendations = recs,
                top3            = { recs[1], recs[2], recs[3] },
            })
        end

        -- Markt-Tipps (defensiv; leere Liste wenn API nicht verfuegbar)
        local marketTips = {}
        if StorageAnalyzer.getMarketTips ~= nil then
            marketTips = StorageAnalyzer.getMarketTips(storageTotals) or {}
        end

        -- Anzahl roter Handlungsbedarf-Punkte (Badge an der Report-Tab)
        local alerts = 0
        local pNeeds = animalNeeds.productionNeeds or {}
        for key, amount in pairs(storageTotals) do
            if type(amount) == "number" and amount > 0 then
                local monthly = (animalNeeds.feedNeeds[key] or 0)
                    + (animalNeeds.beddingNeeds[key] or 0) + (pNeeds[key] or 0)
                if monthly > 0 and (amount / monthly) < 1.5 then
                    alerts = alerts + 1
                end
            end
        end
        for _, hub in ipairs(animalNeeds.husbandries or {}) do
            if (hub.maxCount or 0) > 0 and (hub.count or 0) >= hub.maxCount then
                alerts = alerts + 1
            end
            local pp = animalNeeds.peakPrices
                and animalNeeds.peakPrices[hub.animalType]
            if pp ~= nil and hub.avgAge ~= nil and pp.peakHigh ~= nil
                    and hub.avgAge > pp.peakHigh then
                alerts = alerts + 1
            end
        end
        for _, p in ipairs(productions or {}) do
            for _, r in ipairs(p.recipes or {}) do
                if r.active then
                    for _, inp in ipairs(r.inputs or {}) do
                        if (inp.level or 0) <= 0 then
                            alerts = alerts + 1
                            break
                        end
                    end
                end
            end
        end
        FruchtfolgeAdvisor.reportAlerts = alerts

        -- Knappe Fruechte: was geht zur Neige und laesst sich nachbauen?
        -- Gleiche Rechnung wie oben bei den Alarmen (Bestand / Monatsbedarf),
        -- nur zusaetzlich auf saebare Fruechte zurueckgerechnet. Dient allein
        -- der Anzeige - die Empfehlung selbst gewichtet den Bedarf schon.
        -- Gezaehlt wird pro PRODUKT (Fuelltyp), nicht pro Frucht: FRUIT_PRODUCTS
        -- bildet mehrere Anbaufruechte auf dasselbe Produkt ab (GRASS,
        -- FIELDGRASS, MEADOW, VETCHRYE und GREENRYE liefern alle GRASS). Ueber
        -- die Fruechte zu iterieren zaehlte einen einzigen Grasmangel fuenfmal
        -- und verdraengte damit die echten Engpaesse aus der Zeile.
        local knappheiten = {}
        local knappProdukte = {}    -- produkt -> Eintrag (fuer die Anzeige)
        local function schritt()
            local pNeeds   = animalNeeds.productionNeeds or {}
            local fruechte = CropRotationData.FRUIT_PRODUCTS or {}
            for crop, produkte in pairs(fruechte) do
                local produkt = produkte[1]
                if produkt ~= nil and knappProdukte[produkt] == nil then
                    local monatlich = (animalNeeds.feedNeeds[produkt] or 0)
                        + (animalNeeds.beddingNeeds[produkt] or 0)
                        + (pNeeds[produkt] or 0)
                    if monatlich > 0 then
                        local bestand = storageTotals[produkt] or 0
                        -- Deckung durch die uebrigen Sorten derselben
                        -- Futtergruppe zaehlt mit (Silage statt Heu usw.) -
                        -- aber nicht, wenn eine Produktion genau diesen
                        -- Fuelltyp braucht: ein Rezept nimmt keine Alternative.
                        local gruppe = 0
                        if (pNeeds[produkt] or 0) <= 0 then
                            gruppe = (animalNeeds.mixedCoverMonths or {})[produkt] or 0
                        end
                        local monate  = bestand / monatlich + gruppe
                        if monate < FruchtfolgeAdvisor.KNAPP_MONATE then
                            local eintrag = {
                                produkt = produkt,
                                -- Benannt wird das knappe PRODUKT, nicht eine der
                                -- Fruechte, die es liefern - "Grass" statt je nach
                                -- pairs-Reihenfolge "Meadow" oder "Vetchrye".
                                -- getCropName holt den lokalisierten Titel aus dem
                                -- FillTypeManager (DISPLAY_NAMES ist nur der
                                -- deutsche Fallback: sonst stuende in der
                                -- englischen UI "Weizen" statt "Wheat").
                                name    = CropRotationData.getCropName(produkt),
                                monate  = monate,
                                bedarf  = monatlich,
                            }
                            knappProdukte[produkt] = eintrag
                            table.insert(knappheiten, eintrag)
                        end
                    end
                end
            end
            -- Zweitschluessel Bedarfsmenge: hat man von mehreren Produkten gar
            -- nichts, stehen alle bei 0.0 Monaten. Dann entscheidet, wovon am
            -- meisten gebraucht wird - sonst waere die Reihenfolge zufaellig.
            table.sort(knappheiten, function(a, b)
                if a.monate ~= b.monate then return a.monate < b.monate end
                return (a.bedarf or 0) > (b.bedarf or 0)
            end)
        end
        schritt()

        -- Schnellzugriff fuer die Feldzeilen: knapp[crop] = Monate. Nur die
        -- Produkte, die auch in der Bedarfszeile stehen - sonst tragen bei einem
        -- Betrieb mit vielen Eingangsstoffen fast alle Felder ein "!" und die
        -- Markierung sagt nichts mehr aus. Markiert werden dafuer ALLE Fruechte,
        -- die ein knappes Produkt liefern: gegen Grasmangel hilft eben Gras,
        -- Ackergras, Wiese, Wickroggen oder Gruenroggen gleichermassen.
        local knappNachCrop = {}
        local top = {}
        for i, k in ipairs(knappheiten) do
            if i > FruchtfolgeAdvisor.KNAPP_MAX_ANZEIGE then break end
            top[k.produkt] = k.monate
        end
        for crop, produkte in pairs(CropRotationData.FRUIT_PRODUCTS or {}) do
            local produkt = produkte[1]
            if produkt ~= nil and top[produkt] ~= nil then
                knappNachCrop[crop] = top[produkt]
            end
        end

        FruchtfolgeAdvisor.cache = {
            fields        = fieldResults,
            storage       = storageTotals,
            storageCaps   = storageCaps,
            animals       = animalNeeds,
            productions   = productions,
            marketTips    = marketTips,
            knappheiten   = knappheiten,
            knappNachCrop = knappNachCrop,
        }
        FruchtfolgeAdvisor.prodSel    = 1
        FruchtfolgeAdvisor.prodScroll = 1
        FruchtfolgeAdvisor.prodDetailScroll = 1
        FruchtfolgeAdvisor.storScroll = 1
        FruchtfolgeAdvisor.animScroll = 1
        FruchtfolgeAdvisor.reportScroll = 1
        FruchtfolgeAdvisor.soilCache  = {}
        FruchtfolgeAdvisor.planCache  = {}
        FruchtfolgeAdvisor.cacheStamp = (FruchtfolgeAdvisor.cacheStamp or 0) + 1

    end
    baueCache()
end

-- Weitblick-Plan lazy pro Feld (statt fuer alle Felder in buildCache).
-- Hinweis: rechnet mit dem realen Lager statt dem virtuellen — fuer die
-- eine Hinweiszeile im Feld-Detail voellig ausreichend.
function FruchtfolgeAdvisor.getPlanFor(idx)
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.fields == nil then return nil end
    local cached = FruchtfolgeAdvisor.planCache[idx]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    local entry = c.fields[idx]
    if entry == nil then
        return nil
    end
    local plan = nil
    plan = ForesightPlanner.planField(entry.fieldInfo, c.storage, c.animals)
    FruchtfolgeAdvisor.planCache[idx] = plan or false
    return plan
end

-- Die Oberflaeche ist eine Seite im ESC-Menue: siehe FarmOverviewPage.lua.
-- Das fruehere Strg+F7-Fenster (MessageDialog) entfaellt; seine Logik lebt in
-- FruchtfolgeAdvisorDialog.lua weiter und wird von der Seite uebernommen.

-- ── Navigation ───────────────────────────────────────────────
function FruchtfolgeAdvisor.moveSel(delta)
    local c = FruchtfolgeAdvisor.cache
    if c == nil or #c.fields == 0 then return end
    FruchtfolgeAdvisor.selField = math.max(1, math.min(#c.fields, FruchtfolgeAdvisor.selField + delta))
    local sel = FruchtfolgeAdvisor.selField
    if sel < FruchtfolgeAdvisor.scroll then
        FruchtfolgeAdvisor.scroll = sel
    elseif sel > FruchtfolgeAdvisor.scroll + VISIBLE_FIELDS - 1 then
        FruchtfolgeAdvisor.scroll = sel - VISIBLE_FIELDS + 1
    end
end

function FruchtfolgeAdvisor.moveTab(delta)
    local n = #TAB_NAMES
    local t = FruchtfolgeAdvisor.tab + delta
    if t > n then t = 1 end
    if t < 1 then t = n end
    FruchtfolgeAdvisor.tab = t
end

-- Produktion direkt anwaehlen (Mausklick/Mausrad), Scrollfenster nachziehen
local VISIBLE_PRODS = 15
function FruchtfolgeAdvisor.selectProd(index)
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.productions == nil or #c.productions == 0 then return end
    FruchtfolgeAdvisor.prodSel = math.max(1, math.min(#c.productions, index))
    FruchtfolgeAdvisor.prodDetailScroll = 1
    local sel = FruchtfolgeAdvisor.prodSel
    if sel < FruchtfolgeAdvisor.prodScroll then
        FruchtfolgeAdvisor.prodScroll = sel
    elseif sel > FruchtfolgeAdvisor.prodScroll + VISIBLE_PRODS - 1 then
        FruchtfolgeAdvisor.prodScroll = sel - VISIBLE_PRODS + 1
    end
end

-- Mausrad: blaettert je nach aktivem Tab (und Mausposition)
function FruchtfolgeAdvisor.wheel(delta, posX, posY)
    local tab = FruchtfolgeAdvisor.tab
    if tab == 5 then
        FruchtfolgeAdvisor.reportScroll = math.max(1,
            math.min(FruchtfolgeAdvisor.reportMax or 1,
                FruchtfolgeAdvisor.reportScroll + delta))
    elseif tab == 4 then
        -- Rechts der Trennlinie: Rezept-Details blaettern, links: Produktion waehlen
        if posX ~= nil and FruchtfolgeAdvisor.prodSplitX ~= nil
                and posX > FruchtfolgeAdvisor.prodSplitX then
            FruchtfolgeAdvisor.prodDetailScroll = math.max(1,
                math.min(FruchtfolgeAdvisor.prodDetailMax or 1,
                    FruchtfolgeAdvisor.prodDetailScroll + delta))
        else
            FruchtfolgeAdvisor.selectProd(FruchtfolgeAdvisor.prodSel + delta)
        end
    elseif tab == 3 then
        FruchtfolgeAdvisor.animScroll = math.max(1,
            math.min(FruchtfolgeAdvisor.animMaxScroll or 1,
                FruchtfolgeAdvisor.animScroll + delta))
    elseif tab == 2 then
        FruchtfolgeAdvisor.storScroll = math.max(1,
            math.min(FruchtfolgeAdvisor.storMaxScroll or 1,
                FruchtfolgeAdvisor.storScroll + delta))
    else
        FruchtfolgeAdvisor.moveSel(delta)
    end
end

-- Feld direkt anwaehlen (Mausklick) und Scrollfenster nachziehen
function FruchtfolgeAdvisor.selectField(index)
    local c = FruchtfolgeAdvisor.cache
    if c == nil or #c.fields == 0 then return end
    FruchtfolgeAdvisor.selField = math.max(1, math.min(#c.fields, index))
    local sel = FruchtfolgeAdvisor.selField
    if sel < FruchtfolgeAdvisor.scroll then
        FruchtfolgeAdvisor.scroll = sel
    elseif sel > FruchtfolgeAdvisor.scroll + VISIBLE_FIELDS - 1 then
        FruchtfolgeAdvisor.scroll = sel - VISIBLE_FIELDS + 1
    end
end

-- Mausklick auf gespeicherte Regionen anwenden (GUI-Koordinaten 0..1)
function FruchtfolgeAdvisor.handleClick(x, y)
    if x == nil or y == nil then return false end
    for _, r in ipairs(FruchtfolgeAdvisor.clickRegions) do
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
            if r.kind == "tab" then
                FruchtfolgeAdvisor.tab = r.index
                return true
            elseif r.kind == "field" then
                FruchtfolgeAdvisor.selectField(r.index)
                return true
            elseif r.kind == "prod" then
                FruchtfolgeAdvisor.selectProd(r.index)
                return true
            elseif r.kind == "gotofield" then
                -- Aus dem Report zum vorgeschlagenen Feld springen
                FruchtfolgeAdvisor.tab = 1
                FruchtfolgeAdvisor.selectField(r.index)
                return true
            elseif r.kind == "refresh" then
                FruchtfolgeAdvisor.buildCache()
                return true
            end
        end
    end
    return false
end

-- ── DRAW ──────────────────────────────────────────────────────
function FruchtfolgeAdvisor.drawOverlay(ppx, ppy, ppw, pph)
    ensureOverlay()
    local c = FruchtfolgeAdvisor.cache
    if c == nil then return end

    local px = ppx or 0.08
    local py = ppy or 0.06
    local pw = ppw or 0.84
    local ph = pph or 0.88

    -- Klick-Regionen fuer diese Frame neu aufbauen
    FruchtfolgeAdvisor.clickRegions = {}

    -- Kein eigener Fensterhintergrund und keine eigene Titelleiste mehr:
    -- Das ESC-Menue zeigt den Seitentitel bereits — die Seite zeichnet
    -- direkt auf den Menue-Hintergrund (Giants-Standard-Optik).

    -- Tab-Leiste kompakt + zentriert (wie die Original-Menues), buendig ueber
    -- der nativen Tabelle. Aktiver Tab: helle Box + gruene Unterkante.
    local tabRowY = py + ph - 0.036
    local bandW   = 0.46
    local bandX   = 0.5 - bandW / 2
    local tabW    = bandW / #TAB_NAMES
    for i, name in ipairs(TAB_NAMES) do
        local tx     = bandX + (i - 1) * tabW
        local active = (i == FruchtfolgeAdvisor.tab)
        if active then
            rect(tx + tabW * 0.08, tabRowY - 0.012, tabW * 0.84, 0.034, {1, 1, 1, 0.07})
            rect(tx + tabW * 0.08, tabRowY - 0.012, tabW * 0.84, 0.0030, C.tabOn)
        end
        -- Warn-Badge: Anzahl roter Handlungsbedarf-Punkte am Report-Tab
        local label  = name
        local labCol = active and C.white or C.grey
        if name == "Report" and (FruchtfolgeAdvisor.reportAlerts or 0) > 0 then
            label = string.format("Report (%d)", FruchtfolgeAdvisor.reportAlerts)
            if not active then labCol = C.red end
        end
        txt(tx + tabW / 2, tabRowY, 0.016, label,
            labCol, active, RenderText.ALIGN_CENTER)
        table.insert(FruchtfolgeAdvisor.clickRegions, {
            x = tx, y = tabRowY - 0.010, w = tabW, h = 0.034,
            kind = "tab", index = i,
        })
    end

    -- [ Neu laden ] rechts neben der kompakten Tab-Leiste
    local rfX = bandX + bandW + 0.015
    txt(rfX, tabRowY, 0.0140, "[ Neu laden ]", C.yellow)
    table.insert(FruchtfolgeAdvisor.clickRegions, {
        x = rfX - 0.003, y = tabRowY - 0.010, w = 0.084, h = 0.032,
        kind = "refresh",
    })

    -- Trennlinie unter der Tab-Leiste, ueber der Tabellenbreite
    rect(bandX, tabRowY - 0.014, bandW, 0.0012, {1, 1, 1, 0.12})

    -- Inhaltsflaeche als leicht abgesetzte Karte — bei aktiver nativer Liste
    -- entfaellt sie, damit die Tabelle wie die PREISE-Seite direkt auf dem
    -- Menuehintergrund sitzt (kein blauer Block im leeren linken Rand).
    local contentTop = py + ph - 0.056
    if not FruchtfolgeAdvisor.nativeListActive then
        rect(px, py + 0.004, pw, contentTop - py - 0.008, C.card)
    end

    -- Tab-Inhalt. Bei aktiver nativer Liste (Felder/Lager) zeichnet die GUI die
    -- Tabelle selbst; das Overlay unterdrueckt dann seinen eigenen Inhalt.
    local native = FruchtfolgeAdvisor.nativeListActive
    if     FruchtfolgeAdvisor.tab == 1 then
        if native then
            -- Master-Detail: linke Liste ist nativ; rechts das Detail des gewaehlten Feldes.
            -- Dazwischen eine senkrechte Trennlinie (wie die Original-Menues).
            local sepX = px + pw * 0.36
            rect(sepX, py + 0.03, 0.0012, contentTop - py - 0.02, { 1, 1, 1, 0.20 })
            FruchtfolgeAdvisor.drawFieldDetail(px + pw * 0.37, py, pw * 0.44, contentTop, c)
        else
            FruchtfolgeAdvisor.drawTabFields(px, py, pw, contentTop, c)
        end
    elseif FruchtfolgeAdvisor.tab == 2 then
        -- Lager: Warn-/Marktzeilen zeichnet das Overlay weiter (self-suppress der Tabelle)
        FruchtfolgeAdvisor.drawTabStorage(px, py, pw, contentTop, c)
    elseif FruchtfolgeAdvisor.tab == 3 then
        if not native then FruchtfolgeAdvisor.drawTabAnimals(px, py, pw, contentTop, c) end
    elseif FruchtfolgeAdvisor.tab == 4 then
        if not native then FruchtfolgeAdvisor.drawTabProductions(px, py, pw, contentTop, c) end
    elseif FruchtfolgeAdvisor.tab == 5 then
        if not native then FruchtfolgeAdvisor.drawTabReport(px, py, pw, contentTop, c) end
    end
end

-- ── TAB 1: FELDER ─────────────────────────────────────────────
function FruchtfolgeAdvisor.drawTabFields(px, py, pw, top, c)
    local lx     = px + 0.012
    local splitX = px + pw * 0.38
    local lineH  = 0.038

    -- Bedarfszeile: was geht zur Neige und sollte als naechstes in den Boden?
    -- Die Empfehlungsspalte gewichtet den Bedarf zwar schon, aber man sieht ihr
    -- nicht an, WARUM etwas vorgeschlagen wird. Diese Zeile macht es sichtbar,
    -- damit keine knappe Frucht vergessen wird.
    local bedarf = c.knappheiten or {}
    if #bedarf == 0 then
        txt(lx, top - 0.014, 0.0135,
            "Vorraete reichen - kein dringender Anbaubedarf.", C.grey)
    else
        local teile = {}
        for i = 1, math.min(#bedarf, 6) do
            table.insert(teile, string.format("%s %.1f Mo",
                FruchtfolgeAdvisor.truncate(bedarf[i].name, 12), bedarf[i].monate))
        end
        local rest = ""
        if #bedarf > 6 then
            rest = string.format("   (+%d weitere)", #bedarf - 6)
        end
        local farbe = C.yellow
        if bedarf[1].monate < FruchtfolgeAdvisor.KRITISCH_MONATE then
            farbe = C.red
        end
        txt(lx, top - 0.014, 0.0135,
            "Knapp: " .. table.concat(teile, "  |  ") .. rest, farbe)
    end

    txt(lx,             top - 0.042, 0.013, "Feld   Aktuell  ->  Empfehlung #1", C.grey)
    txt(px + pw * 0.30, top - 0.042, 0.013, "PF-Bonus", C.grey)

    if #c.fields == 0 then
        txt(lx, top - 0.084, 0.018, "Keine Felder auf dieser Karte gefunden.", C.yellow)
        return
    end

    -- Trennlinie unter dem Spaltenkopf (wie die Original-Tabellen)
    rect(lx, top - 0.051, pw * 0.36 - 0.016, 0.0010, {1, 1, 1, 0.14})

    local listTop  = top - 0.080
    local fieldEnd = math.min(#c.fields, FruchtfolgeAdvisor.scroll + VISIBLE_FIELDS - 1)
    for i = FruchtfolgeAdvisor.scroll, fieldEnd do
        local entry = c.fields[i]
        local fi    = entry.fieldInfo
        local top3  = entry.top3
        local yy    = listTop - (i - FruchtfolgeAdvisor.scroll) * lineH

        if i == FruchtfolgeAdvisor.selField then
            rect(px + 0.005, yy - 0.006, pw * 0.36 - 0.01, lineH - 0.004, C.selRow)
        end

        -- Zeile klickbar machen
        table.insert(FruchtfolgeAdvisor.clickRegions, {
            x = px + 0.005, y = yy - 0.006, w = pw * 0.36 - 0.01, h = lineH - 0.004,
            kind = "field", index = i,
        })

        -- Bearbeitet: Gedaechtnis, sonst CropRotation-Historie als Quelle
        local workedFruit = fi.lastFruit or fi.prevFruit
        local currName
        if fi.currentFruit ~= nil then
            currName = CropRotationData.DISPLAY_NAMES[fi.currentFruit] or fi.currentFruit
        elseif workedFruit ~= nil then
            local ln = CropRotationData.DISPLAY_NAMES[workedFruit] or workedFruit
            currName = "(" .. FruchtfolgeAdvisor.truncate(ln, 10) .. ")"
        else
            currName = "Brache"
        end
        local isSel    = (i == FruchtfolgeAdvisor.selField)
        local rec1     = top3[1] and top3[1].displayName or "-"
        local bonus1   = top3[1] and top3[1].pfBonus     or 0
        -- Auswahl wie im Original: sattes Gruen mit dunkler Schrift
        local bonusCol = isSel and C.dark
            or (bonus1 >= 10 and C.green or (bonus1 >= 0 and C.white or C.red))
        local rowCol   = isSel and C.dark or C.lblue

        -- Deckt die Empfehlung einen knappen Bestand? Dann Ausrufezeichen und
        -- Farbe, damit die dringenden Felder aus der Liste herausstechen.
        local knappMonate = nil
        if top3[1] ~= nil and c.knappNachCrop ~= nil then
            knappMonate = c.knappNachCrop[top3[1].crop]
        end
        if knappMonate ~= nil then
            rec1 = "! " .. rec1
            if not isSel then
                rowCol = (knappMonate < FruchtfolgeAdvisor.KRITISCH_MONATE)
                    and C.red or C.yellow
            end
        end

        -- Gruener Punkt: Feld ist bearbeitet/frei -> bereit zur Aussaat
        if fi.currentFruit == nil then
            txt(lx - 0.007, yy + 0.004, 0.0150, "•", isSel and C.dark or C.green)
        end
        -- Text vertikal im Auswahlbalken zentriert (+0.004)
        txt(lx, yy + 0.004, 0.0150,
            string.format("%-3s  %-12s ->  %s",
                tostring(fi.fieldId or "?"), currName, rec1),
            rowCol, isSel)
        -- PF-Spalte relativ zur Panelbreite (sonst Ueberlauf in Detailbereich)
        txt(px + pw * 0.30, yy + 0.004, 0.0140, string.format("PF %+d%%", bonus1), bonusCol)
    end

    local hint = "(x) = bearbeitet, zuletzt Frucht x   |   • = bereit zur Aussaat"
        .. "   |   ! = deckt einen knappen Bestand"
    if #c.fields > VISIBLE_FIELDS then
        hint = string.format("%d / %d Felder   |   %s",
            FruchtfolgeAdvisor.selField, #c.fields, hint)
    end
    txt(lx, py + 0.015, 0.013, hint, C.grey)

    FruchtfolgeAdvisor.drawFieldDetail(splitX + 0.01, py, pw - (splitX - px) - 0.02, top, c)
    rect(splitX, py + 0.02, 0.002, top - py - 0.02, {0.25, 0.35, 0.25, 1})
end

function FruchtfolgeAdvisor.drawFieldDetail(x, py, w, top, c)
    local idx = FruchtfolgeAdvisor.selField
    if idx < 1 or idx > #c.fields then return end

    local entry = c.fields[idx]
    local fi    = entry.fieldInfo
    local recs  = entry.recommendations

    local y = top - 0.025
    txt(x, y, 0.020, string.format("Feld %s  (%.1f ha)",
        tostring(fi.fieldId or "?"), (fi.area or 0) / 10000), C.white, true)
    y = y - 0.028

    local workedFruit = fi.lastFruit or fi.prevFruit
    local aktText
    if fi.currentFruit ~= nil then
        aktText = CropRotationData.DISPLAY_NAMES[fi.currentFruit] or fi.currentFruit
    elseif workedFruit ~= nil then
        aktText = string.format("bearbeitet - zuletzt %s",
            CropRotationData.DISPLAY_NAMES[workedFruit] or workedFruit)
    else
        aktText = "Brache"
    end
    txt(x, y, 0.0145, string.format("Aktuell:  %s", aktText), C.lblue)
    y = y - 0.022
    txt(x, y, 0.0145, string.format("Vorjahr:  %s",
        (fi.prevFruit and CropRotationData.DISPLAY_NAMES[fi.prevFruit]) or "unbekannt"), C.grey)
    y = y - 0.022

    -- Bodengesundheit (Fruchtfolge-Modul): Wert, Zustand und Ertragseffekt fuer dieses Feld
    if Bodengesundheit ~= nil and Bodengesundheit.cfg.enabled and Bodengesundheit.getHealthForField ~= nil then
        local health, hst = Bodengesundheit.getHealthForField(fi.field, fi.fieldId)
        local hCol = C.green
        if health < 35 then hCol = C.red
        elseif health < 55 then hCol = C.lblue
        elseif health < 75 then hCol = C.white end
        local arrow = Bodengesundheit.trendArrow(hst)
        if arrow ~= "" then arrow = " " .. arrow end
        local hLine
        if Bodengesundheit.cfg.affectYield then
            local factor = Bodengesundheit.healthToYieldFactor(health,
                Bodengesundheit.displayYieldMin, Bodengesundheit.displayYieldMax)
            hLine = string.format("Boden:  %d%% (%s)%s   Ertrag %+.0f%%",
                math.floor(health + 0.5), Bodengesundheit.healthLabel(health), arrow, (factor - 1.0) * 100)
        else
            hLine = string.format("Boden:  %d%% (%s)%s",
                math.floor(health + 0.5), Bodengesundheit.healthLabel(health), arrow)
        end
        txt(x, y, 0.0145, hLine, hCol)
        y = y - 0.022
    end

    -- PF Bodenart am Feldmittelpunkt.
    -- Per faPF-Dump bestaetigt: soilMap.bitVectorMap + typeFirstChannel +
    -- typeNumChannels + soilTypes. Gelesen per DensityMapModifier
    -- (Muster aus AutoResetPF verifiziert).
    -- Ergebnis wird pro Feld gecacht — die DensityMap-Lesung ist zu teuer,
    -- um sie jeden Frame zu wiederholen (drawFieldDetail laeuft pro Frame).
    local soilKey    = tostring(fi.fieldId or "?")
    local soilCached = FruchtfolgeAdvisor.soilCache[soilKey]
    local soilName   = nil
    if soilCached ~= nil then
        if soilCached ~= false then soilName = soilCached end
    else
    local function schritt()
        local pf = g_precisionFarming
        if pf == nil then
            local env = _G["FS25_precisionFarming"] or _G["pdlc_precisionFarming"]
            pf = env and env.g_precisionFarming or nil
        end
        if pf == nil or pf.soilMap == nil then return end
        local sm = pf.soilMap
        if sm.bitVectorMap == nil or DensityMapModifier == nil
                or DensityCoordType == nil then
            return
        end

        local field = fi.field
        local fx, fz = nil, nil
        if field ~= nil and field.getCenterOfFieldWorldPosition ~= nil then
            fx, fz = field:getCenterOfFieldWorldPosition()
        end
        if fx == nil and field ~= nil then
            fx, fz = field.posX, field.posZ
        end
        if fx == nil or fz == nil then return end

        local first = sm.typeFirstChannel or 0
        local num   = sm.typeNumChannels  or 3
        local hs    = 2
        local modifier = DensityMapModifier.new(sm.bitVectorMap, first, num, g_terrainNode)
        modifier:setParallelogramWorldCoords(
            fx - hs, fz - hs, fx + hs, fz - hs, fx - hs, fz + hs,
            DensityCoordType.POINT_POINT_POINT)
        local acc, nPix, _ = modifier:executeGet()
        if type(acc) ~= "number" or type(nPix) ~= "number" or nPix <= 0 then return end

        local idx = math.floor(acc / nPix + 0.5)
        if idx <= 0 or type(sm.soilTypes) ~= "table" then return end
        local st = sm.soilTypes[idx]
        if st == nil then st = sm.soilTypes[idx + 1] end
        if st ~= nil then
            local raw = st.name or st.title or st.label
            if type(raw) == "string" then
                soilName = FruchtfolgeAdvisor.localizeText(raw)
            end
        end
    end
    schritt()
    FruchtfolgeAdvisor.soilCache[soilKey] = soilName or false
    end
    if soilName ~= nil and soilName ~= "" then
        txt(x, y, 0.0145, string.format("PF Bodenart:  %s", soilName), C.lblue)
        y = y - 0.022
    end
    y = y - 0.008

    txt(x, y, 0.0155, "EMPFEHLUNG FÜR DIE NÄCHSTE AUSSAAT", C.green, true)
    y = y - 0.024

    -- Spaltenkopf (gleiche absolute Spalten wie die Datenzeilen)
    txt(x,         y, 0.0128, "Frucht", C.grey)
    txt(x + 0.100, y, 0.0128, "Bewertung", C.grey)
    txt(x + 0.205, y, 0.0128, "Bonus", C.grey)
    txt(x + 0.250, y, 0.0128, "Vorrat n. Ernte", C.grey)
    y = y - 0.020

    for rank, rec in ipairs(recs) do
        if rank > 7 then break end
        local proj = rec.projCoverage >= 99 and ">99" or string.format("%.1f", rec.projCoverage)
        local col  = rank == 1 and C.green or (rank == 2 and C.white or C.grey)
        txt(x, y, 0.0145,
            string.format("%d.  %s", rank, FruchtfolgeAdvisor.truncate(rec.displayName, 14)),
            col, rank == 1)
        hbar(x + 0.100, y - 0.0015, 0.072, 0.0115, rec.totalScore, col)
        txt(x + 0.178, y, 0.0145,
            string.format("%.0f%%", rec.totalScore * 100), col)
        local bonusCol = rec.pfBonus > 0 and C.green or (rec.pfBonus < 0 and C.red or C.grey)
        txt(x + 0.205, y, 0.0145, string.format("%+d%%", rec.pfBonus), bonusCol)
        txt(x + 0.250, y, 0.0145, proj .. " Mo", col)
        y = y - 0.020
        if rank <= 3 then
            txt(x + 0.020, y, 0.0118,
                string.format("Rot: %.0f%%  Bed: %.0f%%  Tier: %.0f%%  Markt: %.0f%%",
                    (rec.rotScore    or 0) * 100,
                    (rec.storScore   or 0) * 100,
                    (rec.animScore   or 0) * 100,
                    (rec.marketScore or 0) * 100),
                C.grey)
            y = y - 0.018
        end
    end

    -- Weitblick kompakt: geplante Rotation der naechsten Saisons
    -- (lazy nur fuer das ausgewaehlte Feld berechnet)
    local plan = FruchtfolgeAdvisor.getPlanFor(idx)
    if type(plan) == "table" and #plan > 0 then
        local parts = {}
        for _, step in ipairs(plan) do
            table.insert(parts, step.displayName or "?")
        end
        y = y - 0.006
        txt(x, y, 0.0135,
            "Weitblick: " .. table.concat(parts, "  ->  "), C.grey)
    end
end

-- ── TAB 2: LAGER ──────────────────────────────────────────────
-- Gruppen-Zuordnung fuer die Lageransicht
local STORAGE_FEED_SET = {
    GRASS=true, DRYGRASS=true, SILAGE=true, STRAW=true, CHAFF=true,
    FORAGE=true, FORAGE_MIXING=true, PIGFOOD=true, PIGFOODWF=true,
    CHICKENFOOD=true, ALFALFA=true, DRYALFALFA=true, CLOVER=true,
    DRYCLOVER=true, MEADOW=true,
}
local STORAGE_ANIMAL_SET = {
    MILK=true, GOATMILK=true, BUFFALOMILK=true, EGG=true, WOOL=true,
    HONEY=true, MANURE=true, LIQUIDMANURE=true, DIGESTATE=true,
    COMPOST=true, COMPOSTRAW=true, COMPOST_BOXED=true,
}
local STORAGE_SUPPLY_SET = {
    FERTILIZER=true, LIQUIDFERTILIZER=true, HERBICIDE=true, LIME=true,
    SEEDS=true, DIESEL=true, DEF=true, WATER=true, ROADSALT=true,
    TREESAPLINGS=true,
}

local VISIBLE_STOR = 24

-- Futter-Erkennung: Set-Treffer ODER typische Namensmuster in Key/Anzeigename.
-- Noetig weil Maps (z.B. Krebach) eigene FillType-Keys nutzen, deren
-- Anzeigename zwar "Gras"/"Heu" ist, der Key aber nicht im Set steht.
local FEED_PATTERNS = { "GRAS", "HAY", "HEU", "STRAW", "STROH", "SILAGE", "FORAGE", "FUTTER", "FOOD" }
local function isFeedItem(key)
    if STORAGE_FEED_SET[key] then return true end
    local disp = string.upper(tostring(FruchtfolgeAdvisor.fillName(key)))
    for _, pat in ipairs(FEED_PATTERNS) do
        if string.find(key, pat, 1, true) ~= nil
                or string.find(disp, pat, 1, true) ~= nil then
            return true
        end
    end
    return false
end

-- 123456 -> "123.456" (Tausenderpunkte fuer Liter-Angaben)
local function fmtL(n)
    local s = string.format("%d", math.floor((tonumber(n) or 0) + 0.5))
    local k
    repeat s, k = s:gsub("^(-?%d+)(%d%d%d)", "%1.%2") until k == 0
    return s
end

-- Reichweite in Worten statt "19.9 Mo": unter einem Monat in Tagen (da wird es
-- dringend, und "0.4 Mo" sagt niemandem etwas), bis zwei Jahre in Monaten, dann
-- in Jahren. Der alte Deckel "99.0 Mo" sah aus wie ein echter Messwert.
-- Zahlen ueber g_i18n:formatNumber, damit im Deutschen ein Komma steht
-- (verifiziert in TextElement.lua / PlaceableHusbandryAnimals.lua).
--- Geldbetrag kurz und lesbar: ab tausend ohne Nachkommastellen, ab einer
--- Million mit einer. In der Tabelle zaehlt die Groessenordnung, nicht der Cent.
function FruchtfolgeAdvisor.fmtMoney(v)
    if type(v) ~= "number" or v ~= v then return "" end
    local zeichen = (v < 0) and "-" or ""
    local a = math.abs(v)
    if a >= 1000000 then
        return string.format("%s%.1f M", zeichen, a / 1000000)
    end
    if a >= 1000 then
        return string.format("%s%.1f k", zeichen, a / 1000)
    end
    return string.format("%s%d", zeichen, math.floor(a + 0.5))
end

function FruchtfolgeAdvisor.fmtReach(mo)
    if type(mo) ~= "number" or mo ~= mo or mo < 0 then return "-" end

    if mo < 1 then
        local tage = math.max(1, math.floor(mo * 30 + 0.5))
        if tage == 1 then return "1 " .. L("fa_unit_day", "day") end
        return string.format("%d %s", tage, L("fa_unit_days", "days"))
    end

    if mo < 24 then
        if mo < 1.05 then return "1 " .. L("fa_unit_month", "month") end
        -- Ab einem Jahr ist die Nachkommastelle nur Schein-Genauigkeit:
        -- "20 Monate" ist ehrlicher als "19,9 Monate".
        if mo >= 12 then
            return string.format("%d %s", math.floor(mo + 0.5),
                L("fa_unit_months", "months"))
        end
        local zahl
        if g_i18n ~= nil and g_i18n.formatNumber ~= nil then
            zahl = g_i18n:formatNumber(mo, 1)
        else
            zahl = string.format("%.1f", mo)
        end
        return zahl .. " " .. L("fa_unit_months", "months")
    end

    local jahre = math.floor(mo / 12)
    if jahre >= 10 then return L("fa_reach_max", "> 10 years") end
    return string.format("%d %s", jahre, L("fa_unit_years", "years"))
end

-- Zeilen fuer die native SmoothList des Lager-Tabs (Screen-Klasse).
-- Gleiche Gruppierung wie drawTabStorage, aber als reine Datentabelle.
function FruchtfolgeAdvisor.getStorageRows()
    local rows = {}
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.storage == nil then return rows end
    local an = c.animals
    local prodNeeds = (an and an.productionNeeds) or {}

    local groups = {
        { title = L("fa_grp_feed"),       items = {} },
        { title = L("fa_grp_crops"),      items = {} },
        { title = L("fa_grp_animalprod"), items = {} },
        { title = L("fa_grp_supplies"),   items = {} },
        { title = L("fa_grp_other"),      items = {} },
    }
    for key, amount in pairs(c.storage) do
        if type(amount) == "number" and amount > 0 then
            local monthly = ((an and an.feedNeeds[key]) or 0)
                + ((an and an.beddingNeeds[key]) or 0)
                + (prodNeeds[key] or 0)
            -- Kapazitaet nur zeigen, wenn sie den Bestand auch fassen kann.
            -- Ballen-/Palettenlager, Fahrsilos und Stall-Troege fuehren keine
            -- Kapazitaet in Litern; liegt dort Ware, waere "725.570 / 139.000 L"
            -- schlicht falsch. Dann bleibt es bei der Menge.
            local kap = (c.storageCaps or {})[key]
            if kap ~= nil and amount > kap * 1.001 then kap = nil end
            local item = { key = key, amount = amount, monthly = monthly,
                kapazitaet = kap }

            -- Futter ist auch, was die eigenen Staelle tatsaechlich fressen.
            -- Karten bringen eigene Futtersorten mit (Bergisch Land z. B.
            -- PROTEINGRIST/GRAINGRIST/CCM in der Kuhration), die in keiner Liste
            -- und in keinem Namensmuster stehen. Feldfruechte bleiben aber bei
            -- den Feldfruechten, auch wenn Huehner Weizen picken.
            local istFutter = isFeedItem(key)
            if not istFutter and an ~= nil
                    and CropRotationData.DISPLAY_NAMES[key] == nil then
                istFutter = ((an.feedNeeds[key] or 0) > 0)
                    or ((an.beddingNeeds[key] or 0) > 0)
            end

            if istFutter then
                table.insert(groups[1].items, item)
            elseif CropRotationData.DISPLAY_NAMES[key] ~= nil then
                table.insert(groups[2].items, item)
            elseif STORAGE_ANIMAL_SET[key] then
                table.insert(groups[3].items, item)
            elseif STORAGE_SUPPLY_SET[key] then
                table.insert(groups[4].items, item)
            else
                table.insert(groups[5].items, item)
            end
        end
    end

    local tipByKey = {}
    if c.marketTips ~= nil then
        for _, tp in ipairs(c.marketTips) do
            if tp.ratio >= 1.05 then tipByKey[tp.key] = tp.ratio end
        end
    end

    -- Spaltenkopf als erste Zeile (wie WARE/LAGER auf der PREISE-Seite)
    table.insert(rows, { heads = true })

    for _, g in ipairs(groups) do
        if #g.items > 0 then
            table.sort(g.items, function(a, b) return a.amount > b.amount end)
            table.insert(rows, { header = g.title })
            for _, it in ipairs(g.items) do
                local mo = nil
                if it.monthly > 0 then mo = it.amount / it.monthly end
                local markt = ""
                if tipByKey[it.key] ~= nil then
                    markt = string.format("€ +%.0f%%", (tipByKey[it.key] - 1) * 100)
                end
                table.insert(rows, {
                    name   = FruchtfolgeAdvisor.fillName(it.key),
                    -- "33.268 / 100.000 L": Kapazitaet mit anzeigen, wenn das
                    -- Spiel eine fuehrt. Ballen-/Palettenlager und Fahrsilos
                    -- haben keine in Litern - dort bleibt es bei der Menge.
                    lager  = (it.kapazitaet ~= nil and it.kapazitaet > 0)
                        and (fmtL(it.amount) .. " / " .. fmtL(it.kapazitaet) .. " L")
                        or (fmtL(it.amount) .. " L"),
                    voll   = (it.kapazitaet ~= nil and it.kapazitaet > 0)
                        and (it.amount / it.kapazitaet) or nil,
                    -- Die Spalte heisst BEDARF/MONAT - die Einheit "L/Mo" im Feld
                    -- sagte dasselbe ein zweites Mal.
                    bedarf = mo ~= nil and (fmtL(it.monthly) .. " L") or "",
                    reich  = mo ~= nil and FruchtfolgeAdvisor.fmtReach(mo) or "",
                    mo     = mo,
                    markt  = markt,
                })
            end
        end
    end
    return rows
end

-- ═══════════════════════════════════════════════════════════════
--  NATIVE LISTEN — generisches Zeilenformat fuer die SmoothList
--  Zeilenarten:
--    { head = {a,b,c,d,e,f} }   -> graue Spaltenkoepfe
--    { section = "TITEL" }      -> gruener Bereichs-Titel (Spalte A)
--    { cells = { {t=,col=}, ... bis 6 } }  -> Datenzeile (col = {r,g,b} optional)
-- ═══════════════════════════════════════════════════════════════
local NR = {
    white  = {1.00, 1.00, 1.00},
    grey   = {0.62, 0.62, 0.62},
    green  = {0.60, 0.95, 0.35},
    yellow = {1.00, 0.90, 0.30},
    red    = {1.00, 0.35, 0.30},
    lblue  = {0.78, 0.87, 1.00},
}

local function reachColRGB(mo)
    if mo == nil then return NR.white end
    if mo >= 3.0 then return NR.green end
    if mo >= 1.5 then return NR.yellow end
    return NR.red
end

-- Lager-Zeilen (getStorageRows) ins generische Format uebersetzen
local function storageRowsUnified()
    local out = {}
    for _, r in ipairs(FruchtfolgeAdvisor.getStorageRows()) do
        if r.heads then
            out[#out + 1] = { head = {
                L("fa_h_goods"), L("fa_h_stock"), L("fa_h_demand"),
                L("fa_h_range"), L("fa_h_market"), L("fa_h_full", "FULL"),
            } }
        elseif r.header then
            out[#out + 1] = { section = r.header }
        else
            -- Fuellstand in Prozent in der letzten, sonst leeren Spalte.
            -- Ab 95 % rot: dann nimmt das Lager kaum noch etwas auf.
            local vollText, vollFarbe = "", NR.grey
            if r.voll ~= nil then
                vollText = string.format("%.0f%%", math.min(r.voll, 1) * 100)
                if r.voll >= 0.95 then vollFarbe = NR.red end
            end
            out[#out + 1] = { cells = {
                { t = r.name,   col = NR.white },
                { t = r.lager,  col = NR.white },
                { t = r.bedarf, col = NR.grey },
                { t = r.reich,  col = reachColRGB(r.mo) },
                { t = r.markt,  col = NR.green },
                { t = vollText, col = vollFarbe },
            } }
        end
    end
    return out
end

-- Felder-Zeilen: eine Zeile je Feld (mit fieldIndex getaggt). Ist expandedIdx
-- gesetzt, klappt unter diesem Feld die Rangliste (Top-Fruechte) + Weitblick auf.
-- Text + Farbe fuer die Bedarfszeile ueber der Feldliste. Die Empfehlungsspalte
-- gewichtet den Bedarf zwar schon, aber man sieht ihr nicht an, WARUM etwas
-- vorgeschlagen wird - diese Zeile macht es sichtbar. Der Dialog holt sich das
-- Ergebnis bei jedem Wechsel in den Felder-Bereich.
-- Rueckgabe: text, {r,g,b}
function FruchtfolgeAdvisor.getShortageLine()
    local c = FruchtfolgeAdvisor.cache
    local liste = (c ~= nil and c.knappheiten) or {}

    if #liste == 0 then
        return L("fa_shortage_none", "Stocks are sufficient."), NR.grey
    end

    -- 5 Eintraege passen bei 16px sicher in die 1100px breite Zeile; der Rest
    -- wird als "(+n more)" angehaengt, damit nichts abgeschnitten wirkt.
    local MAX = FruchtfolgeAdvisor.KNAPP_MAX_ANZEIGE
    local teile = {}
    for i = 1, math.min(#liste, MAX) do
        table.insert(teile, string.format("%s %s",
            FruchtfolgeAdvisor.truncate(liste[i].name, 14),
            FruchtfolgeAdvisor.fmtReach(liste[i].monate)))
    end

    local text = L("fa_low", "Low:") .. " " .. table.concat(teile, "   |   ")
    if #liste > MAX then
        text = text .. "   " .. string.format(L("fa_shortage_more", "(+%d more)"), #liste - MAX)
    end

    local col = NR.yellow
    if liste[1].monate < FruchtfolgeAdvisor.KRITISCH_MONATE then col = NR.red end
    return text, col
end

function FruchtfolgeAdvisor.getFieldRows(expandedIdx)
    local out = {}
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.fields == nil then return out end

    out[#out + 1] = { head = {
        L("fa_h_field"), L("fa_h_area"), L("fa_h_current"),
        L("fa_h_soil"), L("fa_h_recommend"), L("fa_h_bonus"),
    } }

    for i, entry in ipairs(c.fields) do
        local fi  = entry.fieldInfo
        local top = entry.recommendations and entry.recommendations[1]

        local aktText
        if fi.currentFruit ~= nil then
            aktText = CropRotationData.getCropName(fi.currentFruit)
        else
            local worked = fi.lastFruit or fi.prevFruit
            if worked ~= nil then
                aktText = string.format(L("fa_worked"), CropRotationData.getCropName(worked))
            else
                aktText = L("fa_fallow")
            end
        end

        local bodenT, bodenC = "-", NR.grey
        if Bodengesundheit ~= nil and Bodengesundheit.cfg.enabled
                and Bodengesundheit.getHealthForField ~= nil then
            local h, st = Bodengesundheit.getHealthForField(fi.field, fi.fieldId)
            bodenT = string.format("%d%% %s", math.floor(h + 0.5), Bodengesundheit.healthLabel(h))
            local arrow = Bodengesundheit.trendArrow(st)
            if arrow ~= "" then bodenT = bodenT .. " " .. arrow end
            if h < 35 then bodenC = NR.red
            elseif h < 55 then bodenC = NR.yellow
            elseif h < 75 then bodenC = NR.lblue
            else bodenC = NR.green end
        end

        local expanded = (expandedIdx == i)
        local marker = expanded and "- " or "+ "
        local empf  = (top and (top.displayName or "?")) or "-"
        local bonus = ""
        local bonusC = NR.grey
        if top ~= nil then
            bonus = string.format("%+d%%", top.pfBonus or 0)
            if (top.pfBonus or 0) > 0 then bonusC = NR.green
            elseif (top.pfBonus or 0) < 0 then bonusC = NR.red end
        end

        -- Deckt die Empfehlung einen knappen Bestand? Dann Ausrufezeichen vor den
        -- Feldnamen und die Empfehlung einfaerben, damit die dringenden Felder aus
        -- der Liste herausstechen. Das "!" steht bewusst in colA (280px) und nicht
        -- vor der Frucht - colE hat nur 110px und liefe sonst in die Bonus-Spalte.
        local empfC = NR.green
        local knappMark = ""
        if top ~= nil and c.knappNachCrop ~= nil then
            local knappMonate = c.knappNachCrop[top.crop]
            if knappMonate ~= nil then
                knappMark = "! "
                empfC = (knappMonate < FruchtfolgeAdvisor.KRITISCH_MONATE)
                    and NR.red or NR.yellow
            end
        end

        out[#out + 1] = {
            fieldIndex = i,
            cells = {
                { t = marker .. knappMark .. L("fa_field") .. " " .. tostring(fi.fieldId or "?"), col = NR.white },
                { t = string.format("%.1f ha", (fi.area or 0) / 10000), col = NR.white },
                { t = aktText, col = NR.lblue },
                { t = bodenT,  col = bodenC },
                { t = empf,    col = empfC },
                { t = bonus,   col = bonusC },
            },
        }

        -- Aufgeklappt: Rangliste der Fruchtvorschlaege + Weitblick
        if expanded and entry.recommendations ~= nil then
            out[#out + 1] = { collapse = true, cells = {
                { t = "      " .. L("fa_collapse"), col = NR.yellow },
                { t = "" }, { t = "" }, { t = "" }, { t = "" }, { t = "" },
            } }
            for rank, rec in ipairs(entry.recommendations) do
                if rank > 7 then break end
                local rankCol = (rank == 1 and NR.green) or (rank == 2 and NR.white) or NR.grey
                local bC = ((rec.pfBonus or 0) > 0 and NR.green)
                    or ((rec.pfBonus or 0) < 0 and NR.red) or NR.grey
                local proj = (rec.projCoverage and rec.projCoverage >= 99) and ">99"
                    or string.format("%.1f", rec.projCoverage or 0)
                out[#out + 1] = { cells = {
                    { t = string.format("      %d. %s", rank, rec.displayName or "?"), col = rankCol },
                    { t = "" }, { t = "" },
                    { t = string.format("%s %.0f%%", L("fa_lbl_score"), (rec.totalScore or 0) * 100), col = NR.lblue },
                    { t = string.format("%+d%%", rec.pfBonus or 0), col = bC },
                    { t = proj .. " " .. L("fa_unit_mo"), col = NR.grey },
                } }
            end
            local plan = FruchtfolgeAdvisor.getPlanFor(i)
            if type(plan) == "table" and #plan > 0 then
                local parts = {}
                for _, step in ipairs(plan) do parts[#parts + 1] = step.displayName or "?" end
                out[#out + 1] = { cells = {
                    { t = "      " .. L("fa_outlook") .. " " .. table.concat(parts, " -> "), col = NR.grey },
                    { t = "" }, { t = "" }, { t = "" }, { t = "" }, { t = "" },
                } }
            end
        end
    end

    -- Unter der Liste: mit welchen Ertragsfaktoren gerechnet wird, falls
    -- FS25_ErtragsFaktor laeuft (YieldBridge.lua). Bewusst ans Ende, die
    -- Feldzeilen finden sich ueber row.fieldIndex, nicht ueber die Position.
    if YieldBridge ~= nil and YieldBridge.getRows ~= nil then
        for _, r in ipairs(YieldBridge.getRows()) do
            out[#out + 1] = r
        end
    end

    return out
end

-- Lokalisierter Tierart-Name (COW -> Kühe/Cows); Fallback: Rohtyp.
-- Volle l10n-Keys als Literale, damit der ModHub-ObsoleteFiles-Check sie findet.
local ANIMAL_L10N = {
    COW     = "fa_animal_COW",
    PIG     = "fa_animal_PIG",
    SHEEP   = "fa_animal_SHEEP",
    HORSE   = "fa_animal_HORSE",
    CHICKEN = "fa_animal_CHICKEN",
}
local function animalName(t)
    if t == nil then return "?" end
    local key = ANIMAL_L10N[tostring(t)]
    if key ~= nil then return L(key, tostring(t)) end
    return tostring(t)
end

-- Tiere: Bestand + Futterbedarf/Reichweite + TMR (Troege/Ration hier gebuendelt).
local function animalRowsUnified()
    local out = {}
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.animals == nil then return out end
    local an = c.animals
    local storage = c.storage or {}

    if an.husbandries ~= nil and #an.husbandries > 0 then
        out[#out + 1] = { section = L("fa_sec_herd") }

        -- Kopfzahl vor der Tabelle: was die Herde wert ist und wie viele Tiere
        -- gerade im besten Preisfenster stehen. Das ist die Zahl, wegen der man
        -- den Bereich ueberhaupt oeffnet.
        local herdeWert, imFenster, fensterWert = nil, 0, 0
        for _, hub in ipairs(an.husbandries) do
            for _, g in ipairs(hub.gruppen or {}) do
                if g.wertGesamt ~= nil then herdeWert = (herdeWert or 0) + g.wertGesamt end
                local lage = AnimalAnalyzer.verkaufsLage ~= nil
                    and AnimalAnalyzer.verkaufsLage(g.age, g.peakAge) or nil
                if lage == "fenster" then
                    imFenster   = imFenster + (g.num or 0)
                    fensterWert = fensterWert + (g.wertGesamt or 0)
                end
            end
        end
        if herdeWert ~= nil then
            local rechts = ""
            if imFenster > 0 then
                rechts = F("fa_herd_ready", "%d animals at best price = %s",
                    imFenster, FruchtfolgeAdvisor.fmtMoney(fensterWert))
            end
            out[#out + 1] = { cells = {
                { t = L("fa_herd_value", "Herd value"), col = NR.grey },
                { t = "" },
                { t = FruchtfolgeAdvisor.fmtMoney(herdeWert), col = NR.white },
                { t = "" },
                { t = rechts, col = (imFenster > 0) and NR.green or NR.grey },
                { t = "" },
            } }
        end

        out[#out + 1] = { head = {
            L("fa_h_animal"), L("fa_h_count"), L("fa_h_value"), L("fa_h_age"),
            L("fa_h_sell"), "",
        } }
        for _, hub in ipairs(an.husbandries) do
            local best = string.format("%d / %d", hub.count or 0, hub.maxCount or 0)
            local age  = hub.avgAge ~= nil and string.format("%.0f %s", hub.avgAge, L("fa_unit_months", "months")) or "-"
            -- Eine Quelle fuer Tabelle und Aufgabenzettel (AnimalAnalyzer.stallLage)
            local hint, hintCol = "", NR.grey
            local lage = AnimalAnalyzer.stallLage ~= nil and AnimalAnalyzer.stallLage(hub) or nil
            if lage ~= nil then
                if lage.art == "zualt" then
                    hint, hintCol = F("fa_lage_zualt", "%d past peak", lage.num), NR.red
                    if (lage.verlust or 0) > 0 then
                        hint = hint .. " (-" .. FruchtfolgeAdvisor.fmtMoney(lage.verlust) .. ")"
                    end
                elseif lage.art == "peakvoll" then
                    hint, hintCol = F("fa_lage_peakvoll", "sell now: %d at best price, barn full",
                        lage.num), NR.green
                elseif lage.art == "peak" then
                    hint, hintCol = F("fa_lage_peak", "%d at best price", lage.num), NR.green
                elseif lage.art == "voll" then
                    hint, hintCol = L("fa_barn_full"), NR.yellow
                elseif lage.art == "quali" then
                    hint, hintCol = F("fa_lage_quali", "low output %d%% - feed better",
                        math.floor((lage.wert or 0) * 100 + 0.5)), NR.yellow
                end
            end

            -- Stallwert: Summe ueber die Gruppen, solange das Spiel Preise liefert
            local stallWert = nil
            for _, g in ipairs(hub.gruppen or {}) do
                if g.wertGesamt ~= nil then stallWert = (stallWert or 0) + g.wertGesamt end
            end

            -- Der Stallname statt der Tierart: wer drei Kuhstaelle hat, sah
            -- sonst dreimal "Kuehe" und wusste nicht, welcher gemeint ist.
            local wo = hub.name
            if wo == nil or wo == "" then wo = animalName(hub.animalType) end

            out[#out + 1] = { cells = {
                { t = FruchtfolgeAdvisor.truncate(wo, 34), col = NR.white },
                { t = best, col = NR.white },
                { t = stallWert ~= nil and FruchtfolgeAdvisor.fmtMoney(stallWert) or "", col = NR.white },
                { t = age, col = NR.lblue },
                { t = hint, col = hintCol },
                { t = "" },
            } }

            -- Darunter nur die Gruppen, bei denen etwas zu entscheiden ist:
            -- verkaufsreif oder schon darueber. Die jungen Tiere stehen als
            -- eine Sammelzeile dahinter - sie brauchen nur Zeit, keine Zeile
            -- je Jahrgang. Ohne das waren es auf einem gewachsenen Hof ueber
            -- vierzig Zeilen, und der Tabellenkopf war weggescrollt.
            local zeigen, jung, jungWert = {}, 0, 0
            for _, g in ipairs(hub.gruppen or {}) do
                local lage = AnimalAnalyzer.verkaufsLage ~= nil
                    and AnimalAnalyzer.verkaufsLage(g.age, g.peakAge) or nil
                if lage == "drueber" or lage == "fenster" then
                    zeigen[#zeigen + 1] = { g = g, lage = lage }
                else
                    jung = jung + (g.num or 0)
                    jungWert = jungWert + (g.wertGesamt or 0)
                end
            end

            for i, eintrag in ipairs(zeigen) do
                if i > FruchtfolgeAdvisor.MAX_TIERGRUPPEN then
                    local rest = #zeigen - FruchtfolgeAdvisor.MAX_TIERGRUPPEN
                    out[#out + 1] = { cells = {
                        { t = string.format("      %s", F("fa_more_groups", "+ %d more", rest)),
                          col = NR.grey },
                        { t = "" }, { t = "" }, { t = "" }, { t = "" }, { t = "" },
                    } }
                    break
                end

                local g, lage = eintrag.g, eintrag.lage
                local rat, ratCol = "", NR.grey
                if lage == "fenster" then
                    rat, ratCol = L("fa_sell_peak", "best price now"), NR.green
                else
                    rat, ratCol = L("fa_sell_late_short", "past peak"), NR.red
                end

                out[#out + 1] = { cells = {
                    { t = string.format("      %d x %s", g.num or 0,
                        g.rasse or L("fa_unknown_breed", "unknown")), col = NR.lblue },
                    { t = "" },
                    { t = g.wert ~= nil and (FruchtfolgeAdvisor.fmtMoney(g.wert) .. L("fa_per_head", "/head")) or "",
                      col = NR.grey },
                    { t = string.format("%d %s", g.age or 0, L("fa_unit_months", "months")), col = NR.grey },
                    { t = rat, col = ratCol },
                    -- Spalte ist schmal, deshalb nur die Zahl mit Pfeil
                    { t = g.wurfIn ~= nil
                        and F("fa_calving_short", "+%d mo", math.floor(g.wurfIn + 0.5))
                        or "", col = NR.lblue },
                } }
            end

            -- Die noch wachsenden Tiere in einer Zeile - aber nur, wenn darueber
            -- ueberhaupt etwas steht. Wachsen ALLE, sagt die Stallzeile das
            -- schon mit Bestand und Durchschnittsalter.
            if jung > 0 and #zeigen > 0 then
                out[#out + 1] = { cells = {
                    { t = string.format("      %s", F("fa_growing", "%d still growing", jung)),
                      col = NR.grey },
                    { t = "" },
                    { t = jungWert > 0 and FruchtfolgeAdvisor.fmtMoney(jungWert) or "", col = NR.grey },
                    { t = "" }, { t = "" }, { t = "" },
                } }
            end
        end
    end

    -- Nach angezeigtem Namen zusammenfassen: verschiedene Fuelltypen koennen im
    -- Spiel gleich heissen (z. B. zweimal "Grass") und standen sonst doppelt da.
    local feed = an.feedNeeds or {}
    local list = {}
    local nachName = {}
    for key, need in pairs(feed) do
        if type(need) == "number" and need > 0 then
            local name = FruchtfolgeAdvisor.fillName(key)
            local e = nachName[name]
            if e == nil then
                e = { key = key, name = name, need = 0, stock = 0 }
                nachName[name] = e
                list[#list + 1] = e
            end
            e.need  = e.need + need
            e.stock = e.stock + (storage[key] or 0)
        end
    end
    for _, e in ipairs(list) do
        e.mo = (e.need > 0) and (e.stock / e.need) or nil
    end
    if #list > 0 then
        table.sort(list, function(a, b) return (a.mo or 999) < (b.mo or 999) end)
        out[#out + 1] = { section = L("fa_sec_feeddemand") }
        out[#out + 1] = { head = {
            L("fa_h_feed"), L("fa_h_demand"), L("fa_h_stock"), L("fa_h_range"), "", "",
        } }
        for _, it in ipairs(list) do
            out[#out + 1] = { cells = {
                { t = FruchtfolgeAdvisor.fillName(it.key), col = NR.white },
                { t = fmtL(it.need) .. " L", col = NR.grey },
                { t = fmtL(it.stock) .. " L", col = NR.white },
                { t = it.mo and FruchtfolgeAdvisor.fmtReach(it.mo) or "-", col = reachColRGB(it.mo) },
                { t = "" }, { t = "" },
            } }
        end
    end

    if an.hasTMR and AnimalAnalyzer ~= nil and AnimalAnalyzer.TMR_RECIPE ~= nil then
        out[#out + 1] = { section = L("fa_sec_tmr") }
        for ing, share in pairs(AnimalAnalyzer.TMR_RECIPE) do
            out[#out + 1] = { cells = {
                { t = FruchtfolgeAdvisor.fillName(ing), col = NR.white },
                { t = string.format("%.0f%%", (share or 0) * 100), col = NR.grey },
                { t = fmtL(storage[ing] or 0) .. " L", col = NR.white },
                { t = "" }, { t = "" }, { t = "" },
            } }
        end
    end

    return out
end

-- Produktion: je Produktionspunkt ein Titel, dann je Rezept eine Statuszeile
-- und darunter jede Zutat (Ein-/Ausgang) auf einer EIGENEN Zeile — damit nichts
-- abgeschnitten wird, sondern alles voll ausgeschrieben in eigener Spalte steht.
local function productionRowsUnified()
    local out = {}
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.productions == nil or #c.productions == 0 then return out end
    for _, p in ipairs(c.productions) do
        out[#out + 1] = { section = tostring(p.name or L("fa_production")) }
        for _, r in ipairs(p.recipes or {}) do
            local status, sCol = L("fa_off"), NR.grey
            if r.active then status, sCol = L("fa_active"), NR.green end
            out[#out + 1] = { cells = {
                { t = tostring(r.name or L("fa_recipe")), col = NR.white },
                { t = status, col = sCol },
                { t = "" }, { t = "" }, { t = "" }, { t = "" },
            } }
            for _, inp in ipairs(r.inputs or {}) do
                local lvl = inp.level or 0
                local lowActive = (lvl <= 0 and r.active)
                out[#out + 1] = { cells = {
                    { t = "    " .. L("fa_input"), col = NR.grey },
                    { t = "" }, { t = "" },
                    { t = FruchtfolgeAdvisor.fillName(inp.fillKey), col = lowActive and NR.red or NR.lblue },
                    { t = fmtL(lvl) .. " L", col = lowActive and NR.red or NR.white },
                    { t = lowActive and L("fa_empty") or "", col = NR.red },
                } }
            end
            for _, o in ipairs(r.outputs or {}) do
                out[#out + 1] = { cells = {
                    { t = "    " .. L("fa_output"), col = NR.grey },
                    { t = "" }, { t = "" },
                    { t = FruchtfolgeAdvisor.fillName(o.fillKey), col = NR.green },
                    { t = fmtL(o.level or 0) .. " L", col = NR.white },
                    { t = "" },
                } }
            end
        end
    end
    return out
end

-- Report: nur Handlungsbedarf (knappe Reichweiten, volle/ueberalterte Staelle,
-- Produktionen mit leerem Eingang). Details stehen in den jeweiligen Bereichen.
local function reportRowsUnified()
    local out = {}
    local c = FruchtfolgeAdvisor.cache
    if c == nil then return out end
    local an = c.animals or {}
    local storage = c.storage or {}
    local pNeeds = an.productionNeeds or {}

    out[#out + 1] = { section = L("fa_sec_todo") }
    local any = false

    local low = {}
    for key, amount in pairs(storage) do
        if type(amount) == "number" and amount > 0 then
            local monthly = ((an.feedNeeds and an.feedNeeds[key]) or 0)
                + ((an.beddingNeeds and an.beddingNeeds[key]) or 0) + (pNeeds[key] or 0)
            if monthly > 0 then
                local mo = amount / monthly
                if mo < 1.5 then low[#low + 1] = { key = key, mo = mo } end
            end
        end
    end
    table.sort(low, function(a, b) return a.mo < b.mo end)
    for _, it in ipairs(low) do
        any = true
        out[#out + 1] = { cells = {
            { t = L("fa_low") .. " " .. FruchtfolgeAdvisor.fillName(it.key), col = NR.red },
            { t = FruchtfolgeAdvisor.fmtReach(it.mo), col = NR.red },
            { t = "" },
            { t = L("fa_plan_supply"), col = NR.grey },
            { t = "" }, { t = "" },
        } }
    end

    for _, hub in ipairs(an.husbandries or {}) do
        if (hub.maxCount or 0) > 0 and (hub.count or 0) >= hub.maxCount then
            any = true
            out[#out + 1] = { cells = {
                { t = animalName(hub.animalType) .. " - " .. L("fa_barn_full"), col = NR.yellow },
                { t = string.format("%d/%d", hub.count or 0, hub.maxCount or 0), col = NR.yellow },
                { t = "" }, { t = L("fa_sell_expand"), col = NR.grey }, { t = "" }, { t = "" },
            } }
        end
        local pp = an.peakPrices and an.peakPrices[hub.animalType]
        if pp ~= nil and hub.avgAge ~= nil and pp.peakHigh ~= nil and hub.avgAge > pp.peakHigh then
            any = true
            out[#out + 1] = { cells = {
                { t = animalName(hub.animalType) .. " - " .. L("fa_overaged"), col = NR.red },
                { t = string.format("%.0f %s", hub.avgAge, L("fa_unit_months", "months")), col = NR.red },
                { t = "" }, { t = L("fa_sell_now"), col = NR.grey }, { t = "" }, { t = "" },
            } }
        end
    end

    for _, p in ipairs(c.productions or {}) do
        for _, r in ipairs(p.recipes or {}) do
            if r.active then
                for _, inp in ipairs(r.inputs or {}) do
                    if (inp.level or 0) <= 0 then
                        any = true
                        out[#out + 1] = { cells = {
                            { t = string.format(L("fa_input_empty"), tostring(p.name)), col = NR.red },
                            { t = "" }, { t = "" },
                            { t = string.format(L("fa_missing"), FruchtfolgeAdvisor.fillName(inp.fillKey)), col = NR.grey },
                            { t = "" }, { t = "" },
                        } }
                        break
                    end
                end
            end
        end
    end

    if not any then
        out[#out + 1] = { cells = {
            { t = L("fa_no_action"), col = NR.green },
            { t = "" }, { t = "" }, { t = "" }, { t = "" }, { t = "" },
        } }
    end
    return out
end

-- Master-Detail: Zeilen der schmalen Feldliste (links). 1:1 zu cache.fields,
-- damit der Auswahlindex direkt auf selField zeigt. Nur Feldname + Bodengesundheit.
function FruchtfolgeAdvisor.getFieldListRows()
    local out = {}
    local c = FruchtfolgeAdvisor.cache
    if c == nil or c.fields == nil then return out end
    for _, entry in ipairs(c.fields) do
        local fi = entry.fieldInfo
        local bodenT, bodenC = "-", NR.grey
        if Bodengesundheit ~= nil and Bodengesundheit.cfg.enabled
                and Bodengesundheit.getHealthForField ~= nil then
            local h, st = Bodengesundheit.getHealthForField(fi.field, fi.fieldId)
            bodenT = string.format("%d%%", math.floor(h + 0.5))
            local arrow = Bodengesundheit.trendArrow(st)
            if arrow ~= "" then bodenT = bodenT .. " " .. arrow end
            if h < 35 then bodenC = NR.red
            elseif h < 55 then bodenC = NR.yellow
            elseif h < 75 then bodenC = NR.lblue
            else bodenC = NR.green end
        end
        out[#out + 1] = {
            name = "Feld " .. tostring(fi.fieldId or "?"),
            boden = bodenT,
            col = bodenC,
        }
    end
    return out
end

-- Generische Zeilen fuer die native Liste je Bereich; nil = Overlay-Fallback.
-- Fruechte-Bereich: eine Zeile je Frucht der Map, per Klick an- oder abwaehlbar.
-- Dient zugleich als Kontrollansicht dafuer, was die Mod aus der Map gelesen hat
-- (Ertrag, Familie und woher die Familie stammt).
local function cropRowsUnified()
    local rows = {}
    rows[#rows + 1] = { head = {
        L("fa_h_crop"), L("fa_h_yieldha"), "", L("fa_h_family"), L("fa_h_use"), "",
    } }

    local quelle = CropRotationData.mapCrops
    if quelle == nil or #quelle == 0 then
        rows[#rows + 1] = { section = L("fa_crops_none") }
        return rows
    end

    -- Nach dem ANGEZEIGTEN Namen sortieren, nicht nach dem internen Schluessel:
    -- mapCrops ist nach GREENRYE/HUMUSACTIVE/MAIZE… sortiert, in der Liste stehen
    -- aber Gruenroggen/Humusaktiv/Mais - die Reihenfolge wirkt sonst zufaellig.
    local liste = {}
    for _, c in ipairs(quelle) do liste[#liste + 1] = c end
    table.sort(liste, function(a, b)
        return CropRotationData.getCropName(a) < CropRotationData.getCropName(b)
    end)

    for _, crop in ipairs(liste) do
        local info    = (CropRotationData.mapInfo or {})[crop] or {}
        local aktiv   = CropRotationData.isCropEnabled(crop)
        local ertrag  = info.yield

        -- Woher die Familie stammt, offen ausweisen: "table" ist gepflegtes
        -- Wissen, "category"/"name" wurde aus den Map-Daten abgeleitet.
        -- Angezeigt wird immer der uebersetzte Familienname - die Schluessel
        -- ("cereal", "root", …) sind interne Bezeichner.
        local famText = CropRotationData.getFamilyName(info.family) or L("fa_fam_unknown")
        if info.source == "unknown" then
            famText = L("fa_fam_unknown")
        elseif info.source == "category" or info.source == "name" then
            famText = famText .. " " .. L("fa_fam_derived")
        end
        if info.perennial then
            famText = famText .. " " .. L("fa_fam_perennial")
        end

        rows[#rows + 1] = {
            cropName = crop,
            cells = {
                { t = (aktiv and "[x] " or "[  ] ") .. CropRotationData.getCropName(crop),
                  col = aktiv and NR.white or NR.grey },
                { t = (ertrag ~= nil and ertrag > 0)
                        and string.format("%d l/ha", ertrag) or "-",
                  col = NR.grey },
                { t = "" },
                { t = famText, col = info.cover and NR.green or NR.lblue },
                { t = aktiv and L("fa_crop_on") or L("fa_crop_off"),
                  col = aktiv and NR.green or NR.grey },
                { t = "" },
            },
        }
    end
    return rows
end

function FruchtfolgeAdvisor.getSectionRows(tab)
    local rows = nil
    if tab == 1 then rows = FruchtfolgeAdvisor.getFieldRows(nil)
    elseif tab == 2 then rows = storageRowsUnified()
    elseif tab == 3 then rows = animalRowsUnified()
    elseif tab == 4 then rows = productionRowsUnified()
    elseif tab == 5 then
        -- Aufgabenzettel (ersetzt den frueheren Report). Die Aufgaben werden bei
        -- jedem Wechsel in den Bereich frisch aus dem Cache und dem Spiel gelesen.
        if TaskAnalyzer ~= nil and TaskAnalyzer.build ~= nil then
            TaskAnalyzer.build()
            rows = TaskAnalyzer.getRows()
        else
            rows = reportRowsUnified()
        end
    elseif tab == 6 then rows = cropRowsUnified()
    elseif tab == 8 then
        -- Finanzen: Jahresvergleich aus FS25_FarmEconomy (FinanceBridge.lua)
        if FinanceBridge ~= nil and FinanceBridge.getRows ~= nil then
            FinanceBridge.request()
            rows = FinanceBridge.getRows()
        end
    end
    if rows == nil or #rows == 0 then return nil end
    return rows
end

function FruchtfolgeAdvisor.drawTabStorage(px, py, pw, top, c)
    -- Native Tabelle aktiv? Dann zeichnet die GUI alles (inkl. Reichweite/Markt-
    -- Spalten). Die frueheren, links versetzten Warn-/Markt-Overlayzeilen entfallen
    -- (waren redundant zur Tabelle und zum Report-Tab).
    if FruchtfolgeAdvisor.nativeListActive then return end

    local lx = px + 0.012
    local an = c.animals

    -- Aufbau (Gruppen, Zeilen, Warn-/Marktzeilen) nur bei neuem Cache —
    -- lief sonst jeden Frame, selbst wenn die native Liste die Tabelle zeigt.
    local sc = FruchtfolgeAdvisor.lineCache.stor
    if sc == nil or sc.stamp ~= FruchtfolgeAdvisor.cacheStamp then
        sc = { stamp = FruchtfolgeAdvisor.cacheStamp }

        local groups = {
            { title = "FUTTER & EINSTREU",        items = {} },
            { title = "FELDFRÜCHTE",              items = {} },
            { title = "TIERPRODUKTE & DÜNGER",    items = {} },
            { title = "BETRIEBSMITTEL",           items = {} },
            { title = "PRODUKTE & SONSTIGES",     items = {} },
        }

        local prodNeeds = an.productionNeeds or {}
        for key, amount in pairs(c.storage) do
            if type(amount) == "number" and amount > 0 then
                local monthly = (an.feedNeeds[key] or 0)
                    + (an.beddingNeeds[key] or 0)
                    + (prodNeeds[key] or 0)
                local item = { key = key, amount = amount, monthly = monthly }
                if isFeedItem(key) then
                    table.insert(groups[1].items, item)
                elseif CropRotationData.DISPLAY_NAMES[key] ~= nil then
                    table.insert(groups[2].items, item)
                elseif STORAGE_ANIMAL_SET[key] then
                    table.insert(groups[3].items, item)
                elseif STORAGE_SUPPLY_SET[key] then
                    table.insert(groups[4].items, item)
                else
                    table.insert(groups[5].items, item)
                end
            end
        end

        -- Zeilenliste: Gruppentitel + Eintraege (groesste zuerst)
        local lines = {}
        for _, g in ipairs(groups) do
            if #g.items > 0 then
                table.sort(g.items, function(a, b) return a.amount > b.amount end)
                table.insert(lines, { header = g.title })
                for _, it in ipairs(g.items) do
                    table.insert(lines, it)
                end
            end
        end
        sc.lines = lines

        -- Kritisch-Zeile (< 1.5 Mo Reichweite)
        local critParts = {}
        for _, g in ipairs(groups) do
            for _, it in ipairs(g.items) do
                if it.monthly > 0 and (it.amount / it.monthly) < 1.5 then
                    table.insert(critParts, string.format("%s %.1fMo",
                        FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(it.key), 10),
                        it.amount / it.monthly))
                end
            end
        end
        if #critParts > 0 then
            sc.critText = "!!  Kritisch: " .. table.concat(critParts, "   ")
        end

        -- Markt-Zeile + Aufschlaege je FillType
        sc.tipByKey = {}
        local tips = c.marketTips
        if tips ~= nil and #tips > 0 then
            local good = {}
            for _, tp in ipairs(tips) do
                if tp.ratio >= 1.05 then
                    table.insert(good, tp)
                    sc.tipByKey[tp.key] = tp.ratio
                end
            end
            if #good > 0 then
                local parts = {}
                for ti = 1, math.min(3, #good) do
                    local tp = good[ti]
                    local nm = FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(tp.key), 10)
                    if tp.station ~= nil then
                        table.insert(parts, string.format("%s +%.0f%% (%s)",
                            nm, (tp.ratio - 1) * 100,
                            FruchtfolgeAdvisor.truncate(tp.station, 14)))
                    else
                        table.insert(parts, string.format("%s +%.0f%%", nm, (tp.ratio - 1) * 100))
                    end
                end
                sc.marketText = "€ Verkaufen: " .. table.concat(parts, "   ")
                sc.marketCol  = C.green
            else
                local parts = {}
                for ti = 1, math.min(3, #tips) do
                    local tp = tips[ti]
                    table.insert(parts, string.format("%s %+.0f%%",
                        FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(tp.key), 10),
                        (tp.ratio - 1) * 100))
                end
                sc.marketText = "€ Markt: kein Aufschlag - " .. table.concat(parts, "   ")
                sc.marketCol  = C.grey
            end
        end

        FruchtfolgeAdvisor.lineCache.stor = sc
    end

    local lines = sc.lines
    if lines == nil or #lines == 0 then
        txt(lx, top - 0.040, 0.016, "Kein Bestand im Lager.", C.grey)
        return
    end

    FruchtfolgeAdvisor.storMaxScroll = math.max(1, #lines - VISIBLE_STOR + 1)
    if FruchtfolgeAdvisor.storScroll > FruchtfolgeAdvisor.storMaxScroll then
        FruchtfolgeAdvisor.storScroll = FruchtfolgeAdvisor.storMaxScroll
    end

    local extraOffset = 0
    if sc.critText ~= nil then
        txt(lx, top - 0.018, 0.013, sc.critText, C.red)
        extraOffset = 0.026
    end
    if sc.marketText ~= nil then
        txt(lx, top - 0.018 - extraOffset, 0.013, sc.marketText, sc.marketCol)
        extraOffset = extraOffset + 0.026
    end

    -- Native SmoothList aktiv? Dann zeichnet die GUI die Tabelle selbst —
    -- das Overlay liefert nur die Warn-/Marktzeilen oberhalb der Liste.
    if FruchtfolgeAdvisor.nativeStorListActive then
        return
    end

    local tipByKey = sc.tipByKey or {}

    -- Spaltenpositionen (kompakt, keine grosse Luecke)
    local colBestand = lx + pw * 0.115
    local colBedarf  = lx + pw * 0.245
    local colReich   = lx + pw * 0.375
    local colMarkt   = lx + pw * 0.465

    -- Rechtsbuendige Zahlen-Anker (Original-Optik der PREISE-Seite)
    local bestandR = colBedarf - pw * 0.020
    local bedarfR  = colReich  - pw * 0.020
    local headerY  = top - 0.018 - extraOffset
    txt(lx,       headerY, 0.013, "WARE", C.grey)
    txt(bestandR, headerY, 0.013, "LAGER", C.grey, false, RenderText.ALIGN_RIGHT)
    txt(bedarfR,  headerY, 0.013, "BEDARF/MONAT", C.grey, false, RenderText.ALIGN_RIGHT)
    txt(colReich, headerY, 0.013, "REICHWEITE", C.grey)
    txt(colMarkt, headerY, 0.013, "MARKT", C.grey)
    txt(lx + pw * 0.60, headerY, 0.013, "Mausrad: blättern", C.grey)
    rect(lx, headerY - 0.008, pw - 0.024, 0.0010, {1, 1, 1, 0.14})

    local y = top - 0.044 - extraOffset
    local shown = 0
    local dataRow = 0
    for i = FruchtfolgeAdvisor.storScroll, #lines do
        if shown >= VISIBLE_STOR or y < py + 0.030 then break end
        local ln = lines[i]
        if ln.header ~= nil then
            y = y - 0.006
            txt(lx, y, 0.0150, ln.header, C.green, true)
            rect(lx, y - 0.0065, pw * 0.55, 0.0012, {0.55, 1.00, 0.45, 0.25})
            y = y - 0.024
            dataRow = 0
        else
            dataRow = dataRow + 1
            if dataRow % 2 == 1 then
                rect(lx - 0.004, y - 0.0055, pw - 0.034, 0.0215, {1, 1, 1, 0.045})
            end
            txt(lx, y, 0.0145,
                FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(ln.key), 18),
                C.white)
            txt(bestandR, y, 0.0145,
                fmtL(ln.amount) .. " L", C.white, false, RenderText.ALIGN_RIGHT)
            if ln.monthly > 0 then
                local mo = ln.amount / ln.monthly
                txt(bedarfR, y, 0.0145,
                    fmtL(ln.monthly) .. " L/Mo", C.grey, false, RenderText.ALIGN_RIGHT)
                hbar(colReich, y - 0.0015, 0.058, 0.0115,
                    math.min(mo / 3.0, 1), statusColor(mo))
                txt(colReich + 0.004, y, 0.0130,
                    string.format("%.1f Mo", math.min(mo, 99)), C.white)
            end
            local ratio = tipByKey[ln.key]
            if ratio ~= nil then
                txt(colMarkt, y, 0.0145,
                    string.format("€ +%.0f%%", (ratio - 1) * 100), C.green)
            end
            y = y - 0.022
        end
        shown = shown + 1
    end

    if #lines > VISIBLE_STOR then
        txt(lx, py + 0.012, 0.013,
            string.format("Zeile %d / %d", FruchtfolgeAdvisor.storScroll, #lines), C.grey)
    end
end

-- ── TAB 3: TIERE ──────────────────────────────────────────────
-- Scrollbare Zeilenliste (Mausrad), damit nichts unten abgeschnitten wird.
local VISIBLE_ANIM = 23

function FruchtfolgeAdvisor.drawTabAnimals(px, py, pw, top, c)
    local lx = px + 0.012
    local an = c.animals

    if an.husbandries == nil or #an.husbandries == 0 then
        txt(lx, top - 0.040, 0.016, "Keine Tiere auf dem Hof erkannt.", C.yellow)
        return
    end

    -- Zeilenliste nur bei neuem Cache aufbauen, nicht jeden Frame —
    -- spart pro Frame dutzende Tabellen-/String-Allokationen.
    local cachedLines = FruchtfolgeAdvisor.lineCache.anim
    local lines
    if cachedLines ~= nil and cachedLines.stamp == FruchtfolgeAdvisor.cacheStamp then
        lines = cachedLines.lines
    else
    lines = {}
    local function add(t, col, bold, size)
        table.insert(lines, { t = t, col = col or C.white, bold = bold == true, size = size or 0.0148 })
    end
    local function gap()
        table.insert(lines, { gapline = true })
    end
    -- Zeile mit positionierten Spalten (dx relativ zum linken Rand)
    local function addC(cols, size)
        table.insert(lines, { cols = cols, size = size or 0.0145 })
    end

    -- Futter ausreichend? (Heuristik: <2 Mo Reichweite = Mangel)
    local allFedOk = true
    for fillType, amount in pairs(an.feedNeeds) do
        if amount > 0 then
            local key  = string.upper(fillType)
            local have = c.storage[key] or 0
            local mo   = have / amount
            if an.mixedCoverMonths ~= nil and an.mixedCoverMonths[key] ~= nil then
                mo = mo + an.mixedCoverMonths[key]
            end
            if mo < 2.0 then allFedOk = false; break end
        end
    end

    -- Spaltenpositionen Auslastungs-Tabelle (pro Gebaeude/Weide eine Zeile)
    local cTier  = pw * 0.155
    local cBest  = pw * 0.235
    local cAusl  = pw * 0.305
    local cEmpf  = pw * 0.480

    add("STALLAUSLASTUNG & VERKAUFSEMPFEHLUNG", C.green, true, 0.0150)
    addC({
        { dx = 0,     t = "Gebäude/Weide", col = C.grey },
        { dx = cTier, t = "Tierart",       col = C.grey },
        { dx = cBest, t = "Bestand",       col = C.grey },
        { dx = cAusl, t = "Auslastung",    col = C.grey },
        { dx = cEmpf, t = "Empfehlung",    col = C.grey },
    }, 0.0125)
    for _, hub in ipairs(an.husbandries) do
        local tierName = (AnimalAnalyzer.ANIMAL_DISPLAY_NAMES and AnimalAnalyzer.ANIMAL_DISPLAY_NAMES[hub.animalType])
            or hub.animalType
        local name = hub.name or tierName
        local cur = hub.count    or 0
        local mx  = hub.maxCount or 0
        if mx > 0 then
            local pct  = cur / mx
            local col  = pct >= 0.90 and C.red or (pct >= 0.75 and C.yellow or C.green)
            local sell = math.max(0, math.floor(cur - mx * 0.70))
            local rec
            if cur >= mx then
                rec = string.format("!! VOLL - %d verk.", sell)
            elseif sell > 0 then
                rec = string.format("~ %d verk. empf.", sell)
            else
                rec = "OK - Platz frei"
            end
            addC({
                { dx = 0,     t = FruchtfolgeAdvisor.truncate(name, 18), col = col },
                { dx = cTier, t = FruchtfolgeAdvisor.truncate(tierName, 9), col = col },
                { dx = cBest, t = string.format("%d/%d", cur, mx), col = col },
                { dx = cAusl, bar = math.min(pct, 1), barw = 0.085,
                  t = string.format("%.0f%%", pct * 100), col = col },
                { dx = cEmpf, t = rec, col = col },
            })
            -- Produktivitaet & Verkaufszeitpunkt (Preisqualitaet)
            local prod    = hub.productivity
            local prodEst = false
            if prod == nil then
                -- Fallback: Schaetzung aus minimaler Futterabdeckung
                local minMo = 99
                for fillType, amount in pairs(an.feedNeeds) do
                    if amount > 0 then
                        local key  = string.upper(fillType)
                        local have = c.storage[key] or 0
                        local mo   = have / amount
                        if an.mixedCoverMonths ~= nil
                                and an.mixedCoverMonths[key] ~= nil then
                            mo = mo + an.mixedCoverMonths[key]
                        end
                        if mo < minMo then minMo = mo end
                    end
                end
                if minMo < 99 then
                    if     minMo >= 3 then prod = 0.90
                    elseif minMo >= 2 then prod = 0.75
                    elseif minMo >= 1 then prod = 0.55
                    else                   prod = 0.35
                    end
                    prodEst = true
                end
            end
            -- Peak-Fenster vorziehen (echte Preiskurve, Fallback statisch) —
            -- steuert Prod-Signal UND Altersempfehlung, damit sich die
            -- Zeilen nicht widersprechen ("JETZT verkaufen" vs "zu jung").
            local optAge = AnimalAnalyzer.OPTIMAL_SELL_AGE
                       and AnimalAnalyzer.OPTIMAL_SELL_AGE[hub.animalType]
            local ppHub = an.peakPrices and an.peakPrices[hub.animalType]
            if ppHub ~= nil and ppHub.peakHigh ~= nil and ppHub.peakHigh > 0 then
                optAge = { low = ppHub.peakLow or 0, high = ppHub.peakHigh }
            end
            local optStr = nil
            if optAge ~= nil then
                optStr = (optAge.low == optAge.high)
                    and string.format("%d Mo", optAge.high)
                    or  string.format("%d-%d Mo", optAge.low, optAge.high)
            end
            local tooYoung = optAge ~= nil and hub.avgAge ~= nil
                and hub.avgAge < optAge.low

            if prod ~= nil then
                local pPct    = prod * 100
                local prodStr = prodEst
                    and string.format("~%2.0f%%", pPct)
                    or  string.format("%3.0f%%", pPct)
                local signal, sigCol
                if tooYoung and cur < mx then
                    -- Preis-Peak liegt noch vor den Tieren: Verkauf jetzt
                    -- verschenkt Wert — Alter uebersteuert das Prod-Signal.
                    local wait = optAge.low - math.floor(hub.avgAge + 0.5)
                    signal = string.format(
                        "Warten: Peak-Alter in ~%d Mo (Wert steigt noch)", wait)
                    sigCol = C.lblue
                elseif prod >= 0.80 and pct >= 0.80 then
                    signal = "JETZT verkaufen! Toppreis + Stall fast voll"
                    sigCol = C.green
                elseif prod >= 0.80 and pct < 0.80 then
                    signal = "Qualitaet sehr gut - warten bis Stall voller"
                    sigCol = C.lblue
                elseif prod >= 0.55 and pct >= 0.80 then
                    signal = "Stall ~voll - verkaufen (Qualitaet mittel)"
                    sigCol = C.yellow
                elseif prod < 0.55 and allFedOk then
                    signal = "!! Quali niedrig trotz Futter - Tiere evt. zu alt!"
                    sigCol = C.red
                else
                    signal = "Erst besser fuettern, dann verkaufen"
                    sigCol = C.yellow
                end
                add(string.format("    Prod: %s   %s", prodStr, signal),
                    sigCol, false, 0.0130)
            end
            -- Altersempfehlung nur bei echtem Alter (Optimum steht
            -- bereits in der fixen Peak-Referenzzeile oben).
            if optAge ~= nil and hub.avgAge ~= nil then
                local hubAge = hub.avgAge
                local ageMo  = math.floor(hubAge + 0.5)
                local ageLine, ageCol
                if hubAge < optAge.low then
                    ageLine = string.format(
                        "    Alter: %d Mo   Optimum: %s   Noch zu jung",
                        ageMo, optStr)
                    ageCol = C.lblue
                elseif hubAge <= optAge.high then
                    ageLine = string.format(
                        "    Alter: %d Mo   Optimum: %s   Im Peak-Fenster!",
                        ageMo, optStr)
                    ageCol = C.green
                else
                    ageLine = string.format(
                        "    Alter: %d Mo   Optimum: %s   Zu alt - jetzt verk.!",
                        ageMo, optStr)
                    ageCol = C.red
                end
                add(ageLine, ageCol, false, 0.0130)
            end
        else
            addC({
                { dx = 0,     t = FruchtfolgeAdvisor.truncate(name, 18), col = C.grey },
                { dx = cTier, t = FruchtfolgeAdvisor.truncate(tierName, 9), col = C.grey },
                { dx = cBest, t = string.format("%d Tiere  (Kapazitaet unbekannt)", cur), col = C.grey },
            })
            local prod = hub.productivity
            if prod ~= nil then
                local pCol2 = (prod >= 0.80) and C.green or ((prod >= 0.55) and C.yellow or C.red)
                add(string.format("    Prod: %3.0f%%", prod * 100), pCol2, false, 0.0130)
            end
        end
    end
    gap()

    -- Spaltenpositionen fuer alle Futter-Tabellen (einheitlich)
    local cBedarf = pw * 0.145
    local cVorrat = pw * 0.275
    local cReich  = pw * 0.400

    if an.mixedStocks ~= nil and next(an.mixedStocks) ~= nil then
        add("MISCHFUTTER IM LAGER", C.lblue, true, 0.0150)
        for mk, stock in pairs(an.mixedStocks) do
            addC({
                { dx = 0,       t = FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(mk), 16), col = C.lblue },
                { dx = cBedarf, t = fmtL(stock) .. " L", col = C.white },
            })
        end
        gap()
    end

    -- Trog pro Gebaeude/Weide — so sieht man, WO Futter fehlt
    local anyTrough = false
    for _, hub in ipairs(an.husbandries) do
        if (hub.trough or 0) > 0 then anyTrough = true end
    end
    if anyTrough then
        add("FUTTER IM STALL (TROG)", C.lblue, true, 0.0150)
        for _, hub in ipairs(an.husbandries) do
            local tn = (AnimalAnalyzer.ANIMAL_DISPLAY_NAMES and AnimalAnalyzer.ANIMAL_DISPLAY_NAMES[hub.animalType])
                or hub.animalType
            local bn = hub.name or tn
            local tr = hub.trough or 0
            addC({
                { dx = 0,       t = FruchtfolgeAdvisor.truncate(bn, 18), col = C.lblue },
                { dx = cTier,   t = FruchtfolgeAdvisor.truncate(tn, 9), col = C.grey },
                { dx = cBedarf, t = fmtL(tr) .. " L", col = tr > 0 and C.white or C.red },
            })
        end
        gap()
    end

    -- Futter-/Einstreu-Reichweiten stehen im Lager-Tab (Spalte Reichweite)
    -- und im Report (Pflicht-Aussaat) — hier bewusst nicht doppelt.
    add("Futter-/Einstreu-Reichweiten: siehe Lager-Tab und Report.",
        C.grey, false, 0.0125)

    if an.hasTMR then
        gap()
        add("TMR-MISCHUNG - ZUTATEN", C.yellow, true, 0.0150)
        for ingredient, share in pairs(AnimalAnalyzer.TMR_RECIPE) do
            local key  = string.upper(ingredient)
            local have = c.storage[key] or 0
            addC({
                { dx = 0,       t = FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(ingredient), 14), col = C.lblue },
                { dx = cBedarf, t = string.format("%.0f%%", share * 100), col = C.grey },
                { dx = cVorrat, t = fmtL(have) .. " L", col = C.white },
            })
        end
    end

    FruchtfolgeAdvisor.lineCache.anim = {
        stamp = FruchtfolgeAdvisor.cacheStamp,
        lines = lines,
    }
    end

    -- Fenster rendern
    FruchtfolgeAdvisor.animMaxScroll = math.max(1, #lines - VISIBLE_ANIM + 1)
    if FruchtfolgeAdvisor.animScroll > FruchtfolgeAdvisor.animMaxScroll then
        FruchtfolgeAdvisor.animScroll = FruchtfolgeAdvisor.animMaxScroll
    end

    txt(lx, top - 0.018, 0.018, "TIERE & FUTTERBEDARF", C.white, true)
    if #lines > VISIBLE_ANIM then
        txt(px + pw - 0.16, top - 0.016, 0.013, "Mausrad: blättern", C.grey)
    end

    -- Kompakte Referenz: Peak-Alter + Hoechstpreis je Tierart.
    -- Echte Kurven aus dem animalSystem, Fallback statische Richtwerte.
    local peakParts = {}
    for _, aType in ipairs({"COW", "PIG", "SHEEP", "HORSE", "CHICKEN"}) do
        local dName = AnimalAnalyzer.ANIMAL_DISPLAY_NAMES
                  and AnimalAnalyzer.ANIMAL_DISPLAY_NAMES[aType] or aType
        local pp  = an.peakPrices and an.peakPrices[aType]
        local opt = AnimalAnalyzer.OPTIMAL_SELL_AGE
                and AnimalAnalyzer.OPTIMAL_SELL_AGE[aType]
        if pp ~= nil then
            local price
            if pp.peakPrice >= 1000 then
                price = string.format("%.1fk€", pp.peakPrice / 1000)
            else
                price = string.format("%.0f€", pp.peakPrice)
            end
            local win = (pp.peakLow == pp.peakHigh)
                and (tostring(pp.peakHigh) .. "Mo")
                or  (tostring(pp.peakLow) .. "-" .. tostring(pp.peakHigh) .. "Mo")
            table.insert(peakParts,
                string.format("%s %s ~%s", dName, win, price))
        elseif opt ~= nil then
            table.insert(peakParts,
                string.format("%s %d-%dMo", dName, opt.low, opt.high))
        end
    end
    if #peakParts > 0 then
        txt(lx, top - 0.040, 0.0120,
            "Peak (Alter/Preis):  " .. table.concat(peakParts, "  |  "), C.grey)
    end

    local y = top - 0.062
    local shown = 0
    local lastIndex = 0
    for i = FruchtfolgeAdvisor.animScroll, #lines do
        if shown >= VISIBLE_ANIM or y < py + 0.030 then break end
        local ln = lines[i]
        if ln.gapline then
            y = y - 0.010
        elseif ln.cols ~= nil then
            for _, cc in ipairs(ln.cols) do
                local cx = lx + cc.dx
                if cc.bar ~= nil then
                    local bw = cc.barw or 0.085
                    hbar(cx, y - 0.0015, bw, 0.0115, cc.bar, cc.col or C.white)
                    if cc.t ~= nil then
                        txt(cx + bw + 0.008, y, ln.size, cc.t, cc.col or C.white, cc.bold)
                    end
                else
                    txt(cx, y, ln.size, cc.t, cc.col or C.white, cc.bold)
                end
            end
            y = y - 0.022
        else
            txt(lx, y, ln.size, ln.t, ln.col, ln.bold)
            if ln.bold then
                rect(lx, y - 0.0065, pw * 0.55, 0.0012, {0.55, 1.00, 0.45, 0.25})
            end
            y = y - 0.022
        end
        shown = shown + 1
        lastIndex = i
    end

    if lastIndex < #lines then
        txt(lx, py + 0.012, 0.013,
            string.format("... weitere Einträge - Mausrad  (Zeile %d / %d)",
                FruchtfolgeAdvisor.animScroll, #lines),
            C.yellow)
    elseif FruchtfolgeAdvisor.animScroll > 1 then
        txt(lx, py + 0.012, 0.013,
            string.format("Zeile %d / %d", FruchtfolgeAdvisor.animScroll, #lines), C.grey)
    end
end

-- ── TAB 4: PRODUKTIONEN ───────────────────────────────────────
-- Layout wie Felder-Tab: Liste links (klickbar), Details rechts.
function FruchtfolgeAdvisor.drawTabProductions(px, py, pw, top, c)
    local lx     = px + 0.012
    local splitX = px + pw * 0.38
    local lineH  = 0.038
    FruchtfolgeAdvisor.prodSplitX = splitX

    txt(lx,             top - 0.018, 0.013, "Produktion", C.grey)
    txt(px + pw * 0.30, top - 0.018, 0.013, "aktiv", C.grey)

    local prods = c.productions
    if prods == nil or #prods == 0 then
        txt(lx, top - 0.06, 0.018, "Keine eigenen Produktionen gefunden.", C.yellow)
        return
    end

    -- Trennlinie unter dem Spaltenkopf (wie die Original-Tabellen)
    rect(lx, top - 0.027, pw * 0.36 - 0.016, 0.0010, {1, 1, 1, 0.14})

    -- Linke Liste
    local listTop = top - 0.056
    local prodEnd = math.min(#prods, FruchtfolgeAdvisor.prodScroll + VISIBLE_PRODS - 1)
    for i = FruchtfolgeAdvisor.prodScroll, prodEnd do
        local p  = prods[i]
        local yy = listTop - (i - FruchtfolgeAdvisor.prodScroll) * lineH

        if i == FruchtfolgeAdvisor.prodSel then
            rect(px + 0.005, yy - 0.006, pw * 0.36 - 0.01, lineH - 0.004, C.selRow)
        end
        table.insert(FruchtfolgeAdvisor.clickRegions, {
            x = px + 0.005, y = yy - 0.006, w = pw * 0.36 - 0.01, h = lineH - 0.004,
            kind = "prod", index = i,
        })

        local activeCount = 0
        local hasEmptyInp = false
        local hasLowInp   = false
        for _, r in ipairs(p.recipes) do
            if r.active then
                activeCount = activeCount + 1
                for _, inp in ipairs(r.inputs) do
                    if inp.level <= 0 then
                        hasEmptyInp = true
                    elseif inp.perMonth ~= nil and inp.perMonth > 0
                           and (inp.level / inp.perMonth) < 1.5 then
                        hasLowInp = true
                    end
                end
            end
        end
        local dotCol
        if     activeCount == 0 then dotCol = C.grey
        elseif hasEmptyInp      then dotCol = C.red
        elseif hasLowInp        then dotCol = C.yellow
        else                         dotCol = C.green
        end

        local isSel  = (i == FruchtfolgeAdvisor.prodSel)
        local name   = FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.localizeText(p.name), 24)
        local rowCol = isSel and C.dark or C.lblue
        if activeCount == 0 and not isSel then rowCol = C.grey end

        -- Text vertikal im Auswahlbalken zentriert (+0.004)
        txt(lx,         yy + 0.004, 0.0150, "●", isSel and C.dark or dotCol)
        txt(lx + 0.018, yy + 0.004, 0.0150, name, rowCol, isSel)
        txt(px + pw * 0.30, yy + 0.004, 0.0140,
            string.format("%d/%d", activeCount, #p.recipes),
            isSel and C.dark or (activeCount > 0 and C.green or C.grey))
    end

    if #prods > VISIBLE_PRODS then
        txt(lx, py + 0.015, 0.013,
            string.format("%d / %d Produktionen", FruchtfolgeAdvisor.prodSel, #prods), C.grey)
    end

    -- Rechte Detailansicht
    FruchtfolgeAdvisor.drawProdDetail(splitX + 0.01, py, pw - (splitX - px) - 0.02, top, c)
    rect(splitX, py + 0.02, 0.002, top - py - 0.02, {0.25, 0.35, 0.25, 1})
end

function FruchtfolgeAdvisor.drawProdDetail(x, py, w, top, c)
    local prods = c.productions
    local idx   = FruchtfolgeAdvisor.prodSel
    if prods == nil or idx < 1 or idx > #prods then return end
    local p = prods[idx]

    FruchtfolgeAdvisor.prodDetailMax = math.max(1, #p.recipes)
    if FruchtfolgeAdvisor.prodDetailScroll > FruchtfolgeAdvisor.prodDetailMax then
        FruchtfolgeAdvisor.prodDetailScroll = FruchtfolgeAdvisor.prodDetailMax
    end

    local y = top - 0.025
    txt(x, y, 0.020, FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.localizeText(p.name), 40), C.white, true)
    y = y - 0.032

    if #p.recipes == 0 then
        txt(x, y, 0.0150, "Keine Rezepte vorhanden.", C.grey)
        return
    end

    local truncated = false
    for ri = FruchtfolgeAdvisor.prodDetailScroll, #p.recipes do
        local r = p.recipes[ri]
        if y < py + 0.05 then
            truncated = true
            break
        end

        -- Rezeptname: $l10n aufloesen, Fallback = erstes Ausgangsprodukt
        local rName = FruchtfolgeAdvisor.localizeText(r.name)
        if (rName == nil or rName == "" or rName == "Rezept") and #r.outputs > 0 then
            rName = FruchtfolgeAdvisor.fillName(r.outputs[1].fillKey)
        end

        local stateCol = r.active and C.green or C.grey
        txt(x, y, 0.0160,
            FruchtfolgeAdvisor.truncate(rName, 32)
                .. (r.active and "   [AKTIV]" or "   [aus]"),
            stateCol, r.active)
        y = y - 0.025

        -- Eingaenge: eine Zeile pro Zutat, rot wenn leer und Rezept aktiv
        if #r.inputs > 0 then
            txt(x + 0.008, y, 0.0135, "Eingang", C.grey)
            y = y - 0.020
            for _, inp in ipairs(r.inputs) do
                if y < py + 0.04 then break end
                local col = (r.active and inp.level <= 0) and C.red or C.lblue
                txt(x + 0.020, y, 0.0145,
                    FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(inp.fillKey), 18),
                    col)
                txt(x + w * 0.30, y, 0.0145, fmtL(inp.level) .. " L", col)
                if inp.perMonth ~= nil and inp.perMonth > 0 then
                    txt(x + w * 0.48, y, 0.0135,
                        "Bedarf " .. fmtL(inp.perMonth) .. " L/Mo", C.grey)
                end
                if r.active and inp.level <= 0 then
                    txt(x + w * 0.74, y, 0.0145, "LEER!", C.red)
                end
                y = y - 0.020
            end
        end

        -- Ausgaenge
        if #r.outputs > 0 then
            txt(x + 0.008, y, 0.0135, "Ausgang", C.grey)
            y = y - 0.020
            for _, out in ipairs(r.outputs) do
                if y < py + 0.04 then break end
                txt(x + 0.020, y, 0.0145,
                    FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(out.fillKey), 18),
                    C.white)
                txt(x + w * 0.30, y, 0.0145, fmtL(out.level) .. " L", C.white)
                y = y - 0.020
            end
        end

        y = y - 0.012
    end

    if truncated or FruchtfolgeAdvisor.prodDetailScroll > 1 then
        txt(x, py + 0.012, 0.013,
            string.format("... Rezept %d / %d - Mausrad über der Detailansicht blättert",
                FruchtfolgeAdvisor.prodDetailScroll, #p.recipes),
            truncated and C.yellow or C.grey)
    end
end

-- ── TAB 5: REPORT (Hofreport im Menue) ────────────────────────
-- Nachbau des Offline-Hofreports mit Live-Spieldaten:
-- Handlungsbedarf, Feldbelegung, Rations-Engpass je Komponente.
local VISIBLE_REPORT = 26

function FruchtfolgeAdvisor.drawTabReport(px, py, pw, top, c)
    local lx = px + 0.012
    local an = c.animals

    -- Zeilenliste nur bei neuem Cache aufbauen (Feld-Suche der
    -- Pflicht-Aussaat lief sonst jeden Frame!)
    local cachedLines = FruchtfolgeAdvisor.lineCache.report
    local lines
    if cachedLines ~= nil and cachedLines.stamp == FruchtfolgeAdvisor.cacheStamp then
        lines = cachedLines.lines
    else
    lines = {}
    local function add(t, col, bold, size)
        table.insert(lines, { t = t, col = col or C.white, bold = bold == true, size = size or 0.0145 })
    end
    local function addC(cols, size)
        table.insert(lines, { cols = cols, size = size or 0.0145 })
    end
    local function gap()
        table.insert(lines, { gapline = true })
    end

    -- ── 1. HANDLUNGSBEDARF ────────────────────────────────────
    add("HANDLUNGSBEDARF", C.green, true, 0.0155)
    local actions = 0

    -- Lager: kritische Reichweiten (< 1.5 Monate)
    local prodNeeds = an.productionNeeds or {}
    for key, amount in pairs(c.storage) do
        if type(amount) == "number" and amount > 0 then
            local monthly = (an.feedNeeds[key] or 0)
                + (an.beddingNeeds[key] or 0) + (prodNeeds[key] or 0)
            if monthly > 0 and (amount / monthly) < 1.5 then
                actions = actions + 1
                add(string.format("  !! %s reicht nur noch %.1f Monate - nachschieben!",
                    FruchtfolgeAdvisor.fillName(key), amount / monthly), C.red)
            end
        end
    end

    -- Tiere: uebervolle Staelle, zu alte Tiere, schwache Versorgung
    -- (pro Gebaeude/Weide, damit klar ist WO gehandelt werden muss)
    for _, hub in ipairs(an.husbandries or {}) do
        local tName = (AnimalAnalyzer.ANIMAL_DISPLAY_NAMES
            and AnimalAnalyzer.ANIMAL_DISPLAY_NAMES[hub.animalType]) or hub.animalType
        local dName = hub.name or tName
        if hub.name ~= nil then
            dName = string.format("%s (%s)",
                FruchtfolgeAdvisor.truncate(hub.name, 20), tName)
        end
        local cur = hub.count or 0
        local mx  = hub.maxCount or 0
        if mx > 0 and cur >= mx then
            actions = actions + 1
            add(string.format("  !! %s: Stall voll (%d/%d) - verkaufen oder erweitern",
                dName, cur, mx), C.red)
        end
        local pp = an.peakPrices and an.peakPrices[hub.animalType]
        if pp ~= nil and hub.avgAge ~= nil and pp.peakHigh ~= nil
                and hub.avgAge > pp.peakHigh then
            actions = actions + 1
            add(string.format("  !! %s: ueber Peak-Alter (%d Mo) - Wert sinkt, jetzt verkaufen",
                dName, math.floor(hub.avgAge + 0.5)), C.red)
        end
        if hub.productivity ~= nil and hub.productivity < 0.55 then
            actions = actions + 1
            add(string.format("  ~  %s: Produktivitaet nur %.0f%% - Futter/Wasser pruefen",
                dName, hub.productivity * 100), C.yellow)
        end
    end

    -- Produktionen: aktive Rezepte mit leerem Eingang
    for _, p in ipairs(c.productions or {}) do
        for _, r in ipairs(p.recipes or {}) do
            if r.active then
                for _, inp in ipairs(r.inputs or {}) do
                    if (inp.level or 0) <= 0 then
                        actions = actions + 1
                        add(string.format("  !! %s: Eingang %s leer - Produktion steht",
                            FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.localizeText(p.name), 20),
                            FruchtfolgeAdvisor.fillName(inp.fillKey)), C.red)
                        break
                    end
                end
            end
        end
    end

    -- Markt-Chancen (deutlich ueber Basispreis)
    if c.marketTips ~= nil then
        for ti = 1, math.min(2, #c.marketTips) do
            local tp = c.marketTips[ti]
            if tp.ratio >= 1.10 then
                actions = actions + 1
                local st = ""
                if tp.station ~= nil then
                    st = "  (" .. FruchtfolgeAdvisor.truncate(tp.station, 16) .. ")"
                end
                add(string.format("  €  %s jetzt +%.0f%% ueber Basispreis%s",
                    FruchtfolgeAdvisor.fillName(tp.key), (tp.ratio - 1) * 100, st),
                    C.green)
            end
        end
    end

    if actions == 0 then
        add("  Keine dringenden Punkte - alles im gruenen Bereich.", C.green)
    end
    gap()

    -- ── 2. PFLICHT-AUSSAAT (Bedarf vs. Lager + wachsende Felder) ──
    -- Jahresbedarf (12 Monate) je verbrauchtem Produkt gegen Lagerbestand
    -- UND bereits wachsende Ernte gerechnet. Was fehlt, muss gesaet werden.
    add("PFLICHT-AUSSAAT - WAS MUSS AUFS FELD", C.green, true, 0.0155)

    -- Gesamtverbrauch je Produkt (Tiere + Einstreu + Produktionen)
    local monthlyAll = {}
    for k, v in pairs(an.feedNeeds) do
        monthlyAll[k] = (monthlyAll[k] or 0) + v
    end
    for k, v in pairs(an.beddingNeeds) do
        monthlyAll[k] = (monthlyAll[k] or 0) + v
    end
    for k, v in pairs(prodNeeds) do
        monthlyAll[k] = (monthlyAll[k] or 0) + v
    end

    -- Rueckwaerts-Mapping: Produkt -> anbaubare Fruechte
    local productToCrops = {}
    for _, crop in ipairs(CropRotationData.getAllCrops()) do
        local prods = CropRotationData.FRUIT_PRODUCTS[crop]
        if prods ~= nil then
            for pi, prod in ipairs(prods) do
                productToCrops[prod] = productToCrops[prod] or {}
                table.insert(productToCrops[prod], { crop = crop, isMain = (pi == 1) })
            end
        end
    end

    -- Erwartete Ernte aus bereits wachsenden eigenen Feldern
    local growingL  = {}
    local growingHa = {}
    for _, entry in ipairs(c.fields or {}) do
        local fi   = entry.fieldInfo
        local crop = fi.currentFruit
        if crop ~= nil then
            local prods = CropRotationData.FRUIT_PRODUCTS[crop]
            local ha    = (fi.area or 0) / 10000
            local yield = CropRotationData.YIELD_L_PER_HA[crop] or 0
            if prods ~= nil and yield > 0 then
                for pi, prod in ipairs(prods) do
                    local amt = ha * yield * (pi == 1 and 1 or 0.4)
                    growingL[prod]  = (growingL[prod] or 0) + amt
                    growingHa[prod] = (growingHa[prod] or 0) + ha
                end
            end
        end
    end

    -- Bedarfszeilen: nur anbaubare Produkte mit Verbrauch
    local sowRows = {}
    local coveredCount = 0
    for key, monthly in pairs(monthlyAll) do
        if monthly > 0 and productToCrops[key] ~= nil then
            local stock    = c.storage[key] or 0
            local reach    = stock / monthly
            local yearNeed = monthly * 12
            local covered  = stock + (growingL[key] or 0)
            local deficit  = yearNeed - covered
            if deficit > 0 then
                -- beste Haupt-Frucht (hoechster Ertrag) fuer die ha-Schaetzung
                local bestYield = 0
                local cropNames = {}
                local cropSet   = {}
                for _, cc in ipairs(productToCrops[key]) do
                    if cc.isMain then
                        local yld = CropRotationData.YIELD_L_PER_HA[cc.crop] or 0
                        if yld > bestYield then bestYield = yld end
                        cropSet[cc.crop] = true
                        if #cropNames < 2 then
                            table.insert(cropNames,
                                CropRotationData.DISPLAY_NAMES[cc.crop] or cc.crop)
                        end
                    end
                end
                if bestYield == 0 then
                    for _, cc in ipairs(productToCrops[key]) do
                        local yld = CropRotationData.YIELD_L_PER_HA[cc.crop] or 0
                        if yld > bestYield then bestYield = yld end
                        cropSet[cc.crop] = true
                        if #cropNames < 2 then
                            table.insert(cropNames,
                                CropRotationData.DISPLAY_NAMES[cc.crop] or cc.crop)
                        end
                    end
                end
                if bestYield > 0 then
                    table.insert(sowRows, {
                        key     = key,
                        reach   = reach,
                        deficit = deficit,
                        needHa  = deficit / bestYield,
                        growHa  = growingHa[key] or 0,
                        crops   = table.concat(cropNames, ", "),
                        cropSet = cropSet,
                    })
                end
            else
                coveredCount = coveredCount + 1
            end
        end
    end
    table.sort(sowRows, function(a, b) return a.reach < b.reach end)

    if #sowRows > 0 then
        local sReich = pw * 0.150
        local sFehlt = pw * 0.270
        local sHa    = pw * 0.400
        local sCrop  = pw * 0.500
        addC({
            { dx = 0,      t = "Produkt",        col = C.grey },
            { dx = sReich, t = "Reichweite",     col = C.grey },
            { dx = sFehlt, t = "fehlt (12 Mo)",  col = C.grey },
            { dx = sHa,    t = "noch saeen",     col = C.grey },
            { dx = sCrop,  t = "Frucht",         col = C.grey },
        }, 0.0125)
        -- Jetzt saebare Felder (bearbeitet/Brache) finden, deren Top-3-
        -- Empfehlung zur fehlenden Frucht passt — Klick springt zum Feld.
        local function findSowFields(cropSet, needHa)
            local cands = {}
            for fIdx, entry in ipairs(c.fields or {}) do
                local fi = entry.fieldInfo
                if fi.currentFruit == nil then
                    local bestRank = nil
                    for rank, rec in ipairs(entry.recommendations or {}) do
                        if rank > 3 then break end
                        if rec.crop ~= nil and cropSet[rec.crop] then
                            bestRank = rank
                            break
                        end
                    end
                    if bestRank ~= nil then
                        table.insert(cands, {
                            idx  = fIdx,
                            fi   = fi,
                            rank = bestRank,
                            ha   = (fi.area or 0) / 10000,
                        })
                    end
                end
            end
            table.sort(cands, function(a, b)
                if a.rank ~= b.rank then return a.rank < b.rank end
                return a.ha > b.ha
            end)
            local picked, sum = {}, 0
            for _, cd in ipairs(cands) do
                if sum >= needHa or #picked >= 4 then break end
                table.insert(picked, cd)
                sum = sum + cd.ha
            end
            return picked
        end

        for _, row in ipairs(sowRows) do
            local rCol = statusColor(row.reach)
            local growInfo = ""
            if row.growHa > 0.05 then
                growInfo = string.format("  (%.1f ha wachsen)", row.growHa)
            end
            addC({
                { dx = 0,      t = FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(row.key), 14), col = C.white },
                { dx = sReich, bar = math.min(row.reach / 3.0, 1), barw = 0.045,
                  t = string.format("%.1f Mo", math.min(row.reach, 99)), col = rCol },
                { dx = sFehlt, t = fmtL(row.deficit) .. " L", col = rCol },
                { dx = sHa,    t = string.format("~%.1f ha", row.needHa), col = C.white, bold = true },
                { dx = sCrop,  t = FruchtfolgeAdvisor.truncate(row.crops .. growInfo, 34), col = C.lblue },
            })
            local picked = findSowFields(row.cropSet or {}, row.needHa)
            if #picked > 0 then
                local parts = {}
                for _, cd in ipairs(picked) do
                    table.insert(parts, string.format("Feld %s (%.1f ha)",
                        tostring(cd.fi.fieldId or "?"), cd.ha))
                end
                table.insert(lines, {
                    t     = "      -> säen auf: " .. table.concat(parts, ", "),
                    col   = C.lblue,
                    size  = 0.0128,
                    click = { index = picked[1].idx },
                })
            end
        end
    else
        add("  Lager + wachsende Felder decken den Jahresbedarf.", C.green)
    end
    if coveredCount > 0 and #sowRows > 0 then
        add(string.format("  %d weitere Bedarfe sind durch Lager/Felder gedeckt.", coveredCount),
            C.grey, false, 0.0125)
    end
    gap()

    -- ── 3. FELDBELEGUNG ───────────────────────────────────────
    add("FELDBELEGUNG (EIGENE FELDER)", C.green, true, 0.0155)
    local byFruit = {}
    local anyGrowthRead = false
    for _, entry in ipairs(c.fields or {}) do
        local fi = entry.fieldInfo
        local key, disp
        if fi.currentFruit ~= nil then
            key  = fi.currentFruit
            disp = CropRotationData.DISPLAY_NAMES[fi.currentFruit] or fi.currentFruit
        elseif (fi.lastFruit or fi.prevFruit) ~= nil then
            local wf = fi.lastFruit or fi.prevFruit
            key  = "WORKED_" .. tostring(wf)
            disp = "bearbeitet (" .. (CropRotationData.DISPLAY_NAMES[wf] or wf) .. ")"
        else
            key  = "FALLOW"
            disp = "Brache"
        end
        local b = byFruit[key]
        if b == nil then
            b = { disp = disp, count = 0, ha = 0, ready = 0 }
            byFruit[key] = b
        end
        b.count = b.count + 1
        b.ha    = b.ha + ((fi.area or 0) / 10000)

        -- Erntereif? (getFieldState verifiziert; Wachstums-Grenzen aus
        -- fruitTypeDesc wie in AutoResetPF)
        local function schritt()
            if fi.currentFruit == nil then return end
            local field = fi.field
            if field == nil then return end
            local fs = nil
            if field.getFieldState ~= nil then fs = field:getFieldState() end
            if fs == nil then fs = field.fieldState end
            if fs == nil or fs.growthState == nil or fs.fruitTypeIndex == nil then return end
            if g_fruitTypeManager == nil then return end
            local fruit = g_fruitTypeManager:getFruitTypeByIndex(fs.fruitTypeIndex)
            if fruit == nil or fruit.minHarvestingGrowthState == nil
                    or fruit.maxHarvestingGrowthState == nil then return end
            anyGrowthRead = true
            -- Ueber TaskAnalyzer geprueft, damit Hackfruechte hier genauso
            -- zaehlen wie in der Aufgabenliste: eine ausgewachsene Zuckerruebe
            -- traegt noch ihr Kraut und liegt unter minHarvestingGrowthState.
            local reif = false
            if TaskAnalyzer ~= nil and TaskAnalyzer.zustandsPruefer ~= nil then
                local pr = TaskAnalyzer.zustandsPruefer(fruit)
                reif = pr.reif({ fruit = fs.fruitTypeIndex, growth = fs.growthState })
            else
                reif = fs.growthState >= fruit.minHarvestingGrowthState
                    and fs.growthState <= fruit.maxHarvestingGrowthState
            end
            if reif then
                b.ready = b.ready + 1
            end
        end
        schritt()
    end

    local cCnt  = pw * 0.22
    local cHa   = pw * 0.30
    local cReif = pw * 0.40
    addC({
        { dx = 0,     t = "Frucht",    col = C.grey },
        { dx = cCnt,  t = "Felder",    col = C.grey },
        { dx = cHa,   t = "Flaeche",   col = C.grey },
        { dx = cReif, t = "erntereif", col = C.grey },
    }, 0.0125)
    local fruitList = {}
    for _, b in pairs(byFruit) do table.insert(fruitList, b) end
    table.sort(fruitList, function(a, b) return a.ha > b.ha end)
    for _, b in ipairs(fruitList) do
        local reifText, reifCol
        if not anyGrowthRead then
            reifText, reifCol = "?", C.grey
        elseif b.ready > 0 then
            reifText, reifCol = tostring(b.ready) .. " reif", C.green
        else
            reifText, reifCol = "-", C.grey
        end
        addC({
            { dx = 0,     t = FruchtfolgeAdvisor.truncate(b.disp, 24), col = C.lblue },
            { dx = cCnt,  t = tostring(b.count), col = C.white },
            { dx = cHa,   t = string.format("%.1f ha", b.ha), col = C.white },
            { dx = cReif, t = reifText, col = reifCol },
        })
    end
    gap()

    -- ── 4. RATION JE KOMPONENTE (ENGPASS) ─────────────────────
    -- Wie der Offline-Hofreport: Mischverhaeltnis aus den Trogfuellstaenden
    -- abgeleitet; mischbare Ration je Komponente = Hoflager-Vorrat / Anteil.
    -- Die kleinste Menge ist der Engpass, der die gesamte Ration begrenzt.
    add("MISCHBARE RATION JE KOMPONENTE", C.green, true, 0.0155)
    local anyRation = false
    for _, hub in ipairs(an.husbandries or {}) do
        local mixTbl = hub.troughMix
        if type(mixTbl) == "table" and next(mixTbl) ~= nil then
            local totalTrough = 0
            for _, v in pairs(mixTbl) do totalTrough = totalTrough + v end
            if totalTrough > 0 then
                anyRation = true
                local tName = (AnimalAnalyzer.ANIMAL_DISPLAY_NAMES
                    and AnimalAnalyzer.ANIMAL_DISPLAY_NAMES[hub.animalType]) or hub.animalType
                local dName = tName
                if hub.name ~= nil then
                    dName = string.format("%s (%s)",
                        FruchtfolgeAdvisor.truncate(hub.name, 20), tName)
                end
                add("  " .. dName .. "  (Anteile aus Trog abgeleitet)", C.lblue, false, 0.0135)

                local comps = {}
                local maxVal = 0
                for k, v in pairs(mixTbl) do
                    local share = v / totalTrough
                    if share > 0.01 then
                        local avail   = c.storage[k] or 0
                        local mixable = avail / share
                        table.insert(comps, { key = k, share = share, mixable = mixable })
                        if mixable > maxVal then maxVal = mixable end
                    end
                end
                table.sort(comps, function(a, b) return a.mixable < b.mixable end)
                for ci, comp in ipairs(comps) do
                    local isBottleneck = (ci == 1 and #comps > 1)
                    local colC = isBottleneck and C.red or C.white
                    local tag  = isBottleneck and "  << ENGPASS" or ""
                    addC({
                        { dx = 0.010,      t = FruchtfolgeAdvisor.truncate(FruchtfolgeAdvisor.fillName(comp.key), 14), col = colC },
                        { dx = pw * 0.145, t = string.format("%.0f%%", comp.share * 100), col = C.grey },
                        { dx = pw * 0.215, bar = maxVal > 0 and (comp.mixable / maxVal) or 0, barw = 0.16,
                          t = fmtL(comp.mixable) .. " L mischbar" .. tag, col = colC },
                    }, 0.0135)
                end
            end
        end
    end
    if not anyRation then
        add("  Keine Trogdaten verfuegbar - erst Futter in den Stall fuellen.", C.grey)
    end

    FruchtfolgeAdvisor.lineCache.report = {
        stamp = FruchtfolgeAdvisor.cacheStamp,
        lines = lines,
    }
    end

    -- Fenster rendern (Scroll wie Tiere-Tab)
    FruchtfolgeAdvisor.reportMax = math.max(1, #lines - VISIBLE_REPORT + 1)
    if FruchtfolgeAdvisor.reportScroll > FruchtfolgeAdvisor.reportMax then
        FruchtfolgeAdvisor.reportScroll = FruchtfolgeAdvisor.reportMax
    end

    txt(lx, top - 0.018, 0.018, "HOFREPORT", C.white, true)
    if #lines > VISIBLE_REPORT then
        txt(px + pw - 0.16, top - 0.016, 0.013, "Mausrad: blättern", C.grey)
    end

    local y = top - 0.046
    local shown = 0
    for i = FruchtfolgeAdvisor.reportScroll, #lines do
        if shown >= VISIBLE_REPORT or y < py + 0.030 then break end
        local ln = lines[i]
        if ln.gapline then
            y = y - 0.012
        elseif ln.cols ~= nil then
            for _, cc in ipairs(ln.cols) do
                local cx = lx + cc.dx
                if cc.bar ~= nil then
                    local bw = cc.barw or 0.085
                    hbar(cx, y - 0.0015, bw, 0.0115, cc.bar, cc.col or C.white)
                    if cc.t ~= nil then
                        txt(cx + bw + 0.008, y, ln.size, cc.t, cc.col or C.white, cc.bold)
                    end
                else
                    txt(cx, y, ln.size, cc.t, cc.col or C.white, cc.bold)
                end
            end
            y = y - 0.022
        else
            txt(lx, y, ln.size, ln.t, ln.col, ln.bold)
            if ln.bold then
                rect(lx, y - 0.0065, pw * 0.55, 0.0012, {0.55, 1.00, 0.45, 0.25})
            end
            if ln.click ~= nil then
                table.insert(FruchtfolgeAdvisor.clickRegions, {
                    x = lx, y = y - 0.004, w = pw * 0.70, h = 0.020,
                    kind = "gotofield", index = ln.click.index,
                })
            end
            y = y - 0.022
        end
        shown = shown + 1
    end
end

-- ── HILFSFUNKTIONEN ───────────────────────────────────────────
-- Deutsche Namen fuer Nicht-Frucht-FillTypes (Fruechte kommen aus
-- CropRotationData.DISPLAY_NAMES). Krebach-Spezialtypen enthalten.
local FILL_NAMES = {
    STRAW        = "Stroh",
    DRYGRASS     = "Heu",
    SILAGE       = "Silage",
    CHAFF        = "Häckselgut",
    FORAGE       = "Mischration",
    PIGFOOD      = "Schweinefutter",
    PIGFOODWF    = "Schweinefutter WF",
    CHICKENFOOD  = "Hühnerfutter",
    DRYALFALFA   = "Luzerneheu",
    DRYCLOVER    = "Kleeheu",
    MILK         = "Milch",
    EGG          = "Eier",
    WOOL         = "Wolle",
    MANURE       = "Mist",
    LIQUIDMANURE = "Gülle",
    DIGESTATE    = "Gärrest",
    FERTILIZER   = "Dünger",
    LIQUIDFERTILIZER = "Flüssigdünger",
    HERBICIDE    = "Herbizid",
    LIME         = "Kalk",
    SEEDS        = "Saatgut",
    DIESEL       = "Diesel",
    WATER        = "Wasser",
    WOODCHIPS    = "Hackschnitzel",
    COMPOST      = "Kompost",
    GRAIN_DRY    = "Getreide (getrocknet)",
}
function FruchtfolgeAdvisor.fillName(n)
    local key = string.upper(tostring(n))
    -- Lokalisierter Spielname ZUERST (folgt der Spielsprache; verifiziert:
    -- getFillTypeByName -> .title). Nur wenn das Spiel keinen Titel liefert,
    -- greifen die eingebauten deutschen Namen als Fallback.
    local title = nil
    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByName ~= nil then
        local desc = g_fillTypeManager:getFillTypeByName(key)
        if desc ~= nil and type(desc.title) == "string" and desc.title ~= "" then
            title = desc.title
        end
    end
    if title ~= nil then return title end
    if FILL_NAMES[key] ~= nil then
        return FILL_NAMES[key]
    end
    if CropRotationData ~= nil and CropRotationData.DISPLAY_NAMES ~= nil
            and CropRotationData.DISPLAY_NAMES[key] ~= nil then
        return CropRotationData.DISPLAY_NAMES[key]
    end
    return n
end

-- "$l10n_xyz"-Schluessel in lesbaren Text aufloesen (Produktions-/Rezeptnamen)
function FruchtfolgeAdvisor.localizeText(s)
    if type(s) ~= "string" then return tostring(s) end
    if string.sub(s, 1, 6) == "$l10n_" then
        local key = string.sub(s, 7)
        local out = nil
        if g_i18n ~= nil and g_i18n.getText ~= nil then
            out = g_i18n:getText(key)
        end
        if out ~= nil and out ~= "" then return out end
        return key
    end
    return s
end

-- Text auf Maximallaenge kuerzen (UTF-8-sicher am Bytefuss abschneiden)
function FruchtfolgeAdvisor.truncate(s, maxLen)
    s = tostring(s or "")
    if #s <= maxLen then return s end
    local cut = string.sub(s, 1, maxLen - 2)
    -- angeschnittene UTF-8-Folgebytes entfernen
    while #cut > 0 do
        local b = string.byte(cut, #cut)
        if b ~= nil and b >= 0x80 and b < 0xC0 then
            cut = string.sub(cut, 1, #cut - 1)
        else
            if b ~= nil and b >= 0xC0 then
                cut = string.sub(cut, 1, #cut - 1)
            end
            break
        end
    end
    return cut .. ".."
end

-- ── EINSTELLUNGEN ─────────────────────────────────────────────
function FruchtfolgeAdvisor.getSavePath()
    local mi = g_currentMission and g_currentMission.missionInfo
    if mi ~= nil and mi.savegameDirectory ~= nil then
        return mi.savegameDirectory .. "/fruchtfolgeAdvisor.xml"
    end
    return nil
end

function FruchtfolgeAdvisor.saveSettings()
    if g_server == nil then return end
    local path = FruchtfolgeAdvisor.getSavePath()
    if path == nil then return end
    local xml = createXMLFile("faXML", path, "fruchtfolgeAdvisor")
    local lst = (RecommendationEngine and RecommendationEngine.LOW_STOCK_THRESHOLD) or 0.2
    local sa  = (ForesightPlanner and ForesightPlanner.SEASONS_AHEAD) or 3
    setXMLFloat(xml, "fruchtfolgeAdvisor.lowStockThreshold", lst)
    setXMLInt(xml, "fruchtfolgeAdvisor.seasonsAhead", sa)
    if FieldAnalyzer ~= nil and FieldAnalyzer.serializeFruitMemory ~= nil then
        setXMLString(xml, "fruchtfolgeAdvisor.fruitMemory",
            FieldAnalyzer.serializeFruitMemory())
        setXMLString(xml, "fruchtfolgeAdvisor.fruitMemory#keys", "fieldId")
    end
    if CropRotationData ~= nil and CropRotationData.serializeDisabled ~= nil then
        setXMLString(xml, "fruchtfolgeAdvisor.disabledCrops",
            CropRotationData.serializeDisabled())
    end
    if Bodengesundheit ~= nil and Bodengesundheit.writeToXML ~= nil then
        Bodengesundheit.writeToXML(xml, "fruchtfolgeAdvisor.bodengesundheit")
    end
    if TaskState ~= nil and TaskState.writeToXML ~= nil then
        TaskState.writeToXML(xml, "fruchtfolgeAdvisor.aufgaben")
    end
    if FieldLedger ~= nil and FieldLedger.writeToXML ~= nil then
        FieldLedger.writeToXML(xml, "fruchtfolgeAdvisor.feldkonto")
    end
    saveXMLFile(xml)
    delete(xml)
end

function FruchtfolgeAdvisor.loadSettings()
    local path = FruchtfolgeAdvisor.getSavePath()
    if path == nil or not fileExists(path) then return end
    local xml = loadXMLFile("faXML", path)
    local t = getXMLFloat(xml, "fruchtfolgeAdvisor.lowStockThreshold")
    if t ~= nil and t > 0 then RecommendationEngine.LOW_STOCK_THRESHOLD = t end
    local s = getXMLInt(xml, "fruchtfolgeAdvisor.seasonsAhead")
    if s ~= nil and s >= 1 and s <= 6 then ForesightPlanner.SEASONS_AHEAD = s end
    local fm = getXMLString(xml, "fruchtfolgeAdvisor.fruitMemory")
    if fm ~= nil and FieldAnalyzer ~= nil
            and FieldAnalyzer.deserializeFruitMemory ~= nil then
        FieldAnalyzer.deserializeFruitMemory(fm)
        FieldAnalyzer.markMemoryKeys(fm, getXMLString(xml, "fruchtfolgeAdvisor.fruitMemory#keys"))
    end
    -- hasXMLProperty statt "dc ~= nil": wer alle Fruechte anwaehlt, speichert
    -- einen LEEREN String. Der muss als bewusste Auswahl gelten, sonst kaeme
    -- die Vorgabe (Sonderkulturen aus) bei jedem Laden zurueck.
    if CropRotationData ~= nil and CropRotationData.deserializeDisabled ~= nil
            and hasXMLProperty(xml, "fruchtfolgeAdvisor.disabledCrops") then
        CropRotationData.deserializeDisabled(
            getXMLString(xml, "fruchtfolgeAdvisor.disabledCrops") or "")
    end
    if Bodengesundheit ~= nil and Bodengesundheit.readFromXML ~= nil then
        Bodengesundheit.readFromXML(xml, "fruchtfolgeAdvisor.bodengesundheit")
    end
    if TaskState ~= nil and TaskState.readFromXML ~= nil then
        TaskState.readFromXML(xml, "fruchtfolgeAdvisor.aufgaben")
    end
    if FieldLedger ~= nil and FieldLedger.readFromXML ~= nil then
        FieldLedger.readFromXML(xml, "fruchtfolgeAdvisor.feldkonto")
    end
    delete(xml)
end

-- ── LIFECYCLE ─────────────────────────────────────────────────
-- Eigene Texte in die GLOBALE Textliste nachtragen.
-- Grund: `text="$l10n_fa_..."` in einer GUI-Datei wird gegen die globale Liste
-- aufgeloest, nicht gegen die Texte der Mod. Bei FS25_FarmEconomy hat die
-- GIANTS-Zertifizierung daraus eine Beanstandung gemacht
-- ("DevWarning: Missing 'ao_tabTitle' in l10n_de.xml"), siehe
-- [[fs25-modhub-einreichung]]. Nachgetragen wird nur, was global FEHLT -
-- Spieltexte werden also nie ueberschrieben. Unsere Schluessel tragen
-- ohnehin alle das Praefix fa_.
-- Texte der Mod pruefen, statt sie global nachzutragen.
--
-- Hintergrund (05.10.2026 geklaert): `text="$l10n_..."` in einer GUI-Datei
-- loest `TextElement:loadFromXML` mit `g_i18n:getText(key, self.customEnvironment)`
-- auf - also ueber dasselbe I18N-Objekt, das auch aus Lua erreichbar ist
-- (`getfenv(0).g_i18n == g_i18n`, von der FarmEconomy-Sitzung im Spiel
-- gemessen). Weil unsere Texte INLINE in der modDesc stehen, landen sie in
-- genau dieser Liste, bevor die Seite in loadMap geladen wird. Deshalb
-- funktionieren die Verweise, und das Log zeigt keine fehlenden Schluessel.
-- Ein globales setText konnte folgerichtig nie etwas nachtragen (immer 0).
--
-- Was bleibt, ist die Gefahr einer Reihenfolge-Falle: Wird eine GUI-Datei
-- geladen, BEVOR die Texte da sind, meldet das Spiel "Missing '<key>' in
-- l10n_de.xml" und zeigt den Schluessel statt des Textes. Diese Stichprobe
-- schlaegt genau dann im Log Alarm.
FruchtfolgeAdvisor.GUI_TEXT_STICHPROBE = {
    "fa_title", "fa_tab_tasks", "fa_tab_settings",
    "fa_set_section_tasks", "fa_set_enabled", "fa_help_p1_title",
}

function FruchtfolgeAdvisor.pruefeTexte()
    if g_i18n == nil or g_i18n.hasText == nil then
        print("[FA] l10n: g_i18n nicht verfuegbar")
        return false
    end
    local fehlen = {}
    for _, key in ipairs(FruchtfolgeAdvisor.GUI_TEXT_STICHPROBE) do
        if not g_i18n:hasText(key) then
            fehlen[#fehlen + 1] = key
        end
    end
    if #fehlen > 0 then
        Logging.warning("[FarmOverview] Texte fehlen beim Laden: %s - GUI-Dateien zeigen dann den Schluessel.",
            table.concat(fehlen, ", "))
        return false
    end
    return true
end

function FruchtfolgeAdvisor:loadMap()
    -- Stichprobe, BEVOR die Seite samt GUI-Datei geladen wird: sind die
    -- eigenen Texte da, loesen die $l10n-Verweise in den GUI-Dateien auf.
    FruchtfolgeAdvisor.pruefeTexte()

    -- Fruechte der geladenen Map uebernehmen, BEVOR Einstellungen gelesen werden
    -- (die Abwahlliste bezieht sich auf diese Fruechte). Schlaegt es fehl, greift
    -- in getAllCrops die Vanilla-Liste - die Mod laeuft dann wie bisher.
    if CropRotationData ~= nil and CropRotationData.initFromMap ~= nil then
        local n = CropRotationData.initFromMap()
        print(string.format("FarmOverview: %d saebare Fruechte von der Map uebernommen.", n or 0))
    end

    if g_server ~= nil then FruchtfolgeAdvisor.loadSettings() end

    -- Bodengesundheits-Modul: Hooks installieren (Server) bzw. Zustand anfordern (Client)
    if Bodengesundheit ~= nil and Bodengesundheit.onLoadMap ~= nil then
        Bodengesundheit.onLoadMap()
    end

    -- Die Oberflaeche ist eine Seite im ESC-Menue (FarmOverviewPage), das
    -- fruehere Strg+F7-Fenster entfaellt.
    addConsoleCommand("faDump",   "FA Debug-Dump", "debugDump", FruchtfolgeAdvisor)
    addConsoleCommand("faLager",  "FA Lager-Dump (jede Quelle einzeln)", "debugDump", StorageAnalyzer)
    addConsoleCommand("faMarkt",  "FA Markt-Debug-Dump (Verkaufsstationen)", "marketDebugDump", StorageAnalyzer)
    addConsoleCommand("faPF",     "FA PF-Debug-Dump (Bodenqualitaet-API)", "pfDebugDump", FruchtfolgeAdvisor)
    addConsoleCommand("faCrops",  "FA Frucht-Dump (was von der Map gelesen wurde)", "cropDebugDump", FruchtfolgeAdvisor)
    addConsoleCommand("faTiere",  "FA Tier-Debug-Dump (Alter/Produktivitaet-API)", "animalDebugDump", AnimalAnalyzer)
    addConsoleCommand("faPreise", "FA Tierpreis-Dump (Verkaufspreis-Kurven)", "priceDebugDump", AnimalAnalyzer)
    addConsoleCommand("faAufgaben", "FA Aufgabenzettel-Dump", "debugDump", TaskAnalyzer)
    addConsoleCommand("faKonto",  "FA Feldkonto (Deckungsbeitrag je Feld)", "debugDump", FieldLedger)
    addConsoleCommand("faFeld",   "FA Feld-Dump: faFeld <Feldnummer>", "fieldDebugDump", TaskAnalyzer)

    -- Betriebsuebersicht als Seite im ESC-Menue. Erst bauen, wenn der eigene
    -- Spieler die Welt betreten hat - vorher ist das Menue nicht fertig.
    -- Kein Dedicated Server (keine Oberflaeche).
    if g_dedicatedServerInfo == nil and g_client ~= nil and FarmOverviewPage ~= nil then
        if g_messageCenter ~= nil and MessageType ~= nil and MessageType.OWN_PLAYER_ENTERED ~= nil then
            g_messageCenter:subscribeOneshot(MessageType.OWN_PLAYER_ENTERED, function()
                FarmOverviewPage.init()
            end, nil)
        else
            FarmOverviewPage.init()
        end
    end

    -- Speichern
    FSCareerMissionInfo.saveToXMLFile = Utils.appendedFunction(
        FSCareerMissionInfo.saveToXMLFile, FruchtfolgeAdvisor.saveSettings)
end

-- Hintergrund-Scan: alle 5 Minuten Felder lesen, damit das
-- Frucht-Gedaechtnis auch ohne Menuebesuch aktuell bleibt
-- (sonst: Ernte + Grubbern ohne Menue = Frucht nie gesehen -> "Brache").
FruchtfolgeAdvisor.memTimer = 0

function FruchtfolgeAdvisor:update(dt)
    -- ESC-Seite nachfassen, falls das Menue beim ersten Versuch nicht bereit war
    if FarmOverviewPage ~= nil and FarmOverviewPage.retry ~= nil then
        FarmOverviewPage.retry()
    end

    -- MP-Client: Einstellungen und Fruchtauswahl EINMAL kurz nach dem Beitreten
    -- beim Server anfragen, nicht erst beim Oeffnen der Seite. Sonst zeigte der
    -- Aufgabenzettel beim ersten Blick die Vorgaben (z. B. Walzen, obwohl auf
    -- dem Server abgewaehlt) und sprang erst Sekunden spaeter um. Beim Laden
    -- selbst geht es nicht: die Netzwerk-Events sind da noch nicht registriert
    -- ("Invalid event id"), darum die Wartezeit.
    if g_server == nil and not FruchtfolgeAdvisor._syncAngefragt then
        FruchtfolgeAdvisor._syncTimer = (FruchtfolgeAdvisor._syncTimer or 0) + dt
        if FruchtfolgeAdvisor._syncTimer > 3000 then
            FruchtfolgeAdvisor._syncAngefragt = true
            if Bodengesundheit ~= nil and Bodengesundheit.requestCfgSync ~= nil then
                Bodengesundheit.requestCfgSync()
            end
            if CropSelectionEvent ~= nil and CropSelectionEvent.request ~= nil then
                CropSelectionEvent.request()
            end
            -- Bodenwerte und Frucht-Gedaechtnis (Vorfrucht) ebenfalls holen:
            -- beides geht in die Empfehlung ein, sonst zeigen Mitspieler fuer
            -- dasselbe Feld unterschiedliche Fruechte an.
            if Bodengesundheit ~= nil and Bodengesundheit.requestSync ~= nil then
                Bodengesundheit.requestSync()
            end
            if FruitMemoryEvent ~= nil and FruitMemoryEvent.request ~= nil then
                FruitMemoryEvent.request()
            end
        end
    end

    FruchtfolgeAdvisor.memTimer = FruchtfolgeAdvisor.memTimer + dt
    if FruchtfolgeAdvisor.memTimer >= 300000 then
        FruchtfolgeAdvisor.memTimer = 0
        if FieldAnalyzer ~= nil and FieldAnalyzer.getOwnFields ~= nil then
            FieldAnalyzer.getOwnFields()
        end
    end

    -- Bodengesundheit: Startwerte einmalig aus der Fruchtfolge vorbelegen (Server),
    -- kurz nach dem Laden, wenn die Felddaten bereitstehen. Timer-Reset nach
    -- jedem Versuch: falls die Felder noch nicht geladen sind (Dedi), wird
    -- alle 4 s erneut probiert statt jeden Frame.
    if g_server ~= nil and Bodengesundheit ~= nil and Bodengesundheit.seeded == false then
        FruchtfolgeAdvisor._seedTimer = (FruchtfolgeAdvisor._seedTimer or 0) + dt
        if FruchtfolgeAdvisor._seedTimer > 4000 then
            FruchtfolgeAdvisor._seedTimer = 0
            if Bodengesundheit ~= nil and Bodengesundheit.seedFromFields ~= nil then
                Bodengesundheit.seedFromFields()
            end
        end
    end
end

function FruchtfolgeAdvisor:draw()
    -- Kein In-Welt-HUD: die Bodengesundheit wird ausschliesslich im F7-Menue
    -- angezeigt (Feld-Detail + BODEN-Spalte der Feldliste).
end

-- Konsolen-Dump: zeigt die Mitglieder von g_precisionFarming und soilMap.
-- Aufruf im Spiel: Konsole (~) und "faPF" eingeben.
-- Konsolen-Dump der Fruechte, die von der Map uebernommen wurden. Zeigt je
-- Frucht, was gelesen wurde und WOHER die Familie stammt - damit laesst sich auf
-- einer fremden Map pruefen, ob die Ableitung sinnvolle Ergebnisse liefert.
-- Aufruf im Spiel: Konsole (~) und "faCrops" eingeben.
function FruchtfolgeAdvisor.cropDebugDump()
    print("=== FA-CROPS-DUMP ===")
    local liste = CropRotationData.mapCrops
    if liste == nil then
        print("  initFromMap lief nicht (oder lieferte nichts) -> Vanilla-Liste aktiv")
        liste = {}
    end

    local proQuelle = {}
    print(string.format("  %-22s %-10s %-12s %-10s %s",
        "FRUCHT", "ERTRAG", "FAMILIE", "HERKUNFT", "PRODUKTE"))
    for _, crop in ipairs(liste) do
        local info = (CropRotationData.mapInfo or {})[crop] or {}
        local prod = table.concat(CropRotationData.FRUIT_PRODUCTS[crop] or {}, "+")
        local q    = info.source or "?"
        proQuelle[q] = (proQuelle[q] or 0) + 1
        print(string.format("  %-22s %-10s %-12s %-10s %s%s%s",
            crop,
            tostring(info.yield or "-"),
            tostring(info.family or "-"),
            q,
            prod,
            info.cover and "  [Zwischenfrucht]" or "",
            (info.perennial and "  [waechst nach]" or "")
                .. (CropRotationData.isCropEnabled(crop) and "" or "  [ABGEWAEHLT]")))
    end

    print(string.format("  ---- %d saebare Fruechte ----", #liste))
    for q, n in pairs(proQuelle) do
        print(string.format("    Familie aus '%s': %d", q, n))
    end

    -- Nicht saebares separat, damit klar ist, was bewusst fehlt.
    local raus = {}
    for name, info in pairs(CropRotationData.mapInfo or {}) do
        if info.seedable == false then table.insert(raus, name) end
    end
    table.sort(raus)
    if #raus > 0 then
        print("  nicht saebar (allowsSeeding=false): " .. table.concat(raus, ", "))
    end
end

-- Kurze PF-Diagnose: ist Precision Farming da, und welche Werte stehen an der
-- eigenen Position? Die frueheren seitenlangen Auflistungen aller Kartenfelder
-- haben ihren Zweck erfuellt (05.10.2026, siehe fs25-precision-farming-zugriff)
-- und sind raus; fuer die Entscheidung je Feld gibt es faFeld.
function FruchtfolgeAdvisor.pfDebugDump()
    print("=== FA-PF-DUMP ===")
    local pf = g_precisionFarming
    if pf == nil then
        local env = _G["FS25_precisionFarming"] or _G["pdlc_precisionFarming"]
        pf = env and env.g_precisionFarming or nil
    end
    if pf == nil then
        print("  Precision Farming nicht aktiv - Kalk und Duenger laufen ueber die Spielschichten.")
        print("=== FA-PF-DUMP ENDE ===")
        return
    end

    -- eigene Position: Fahrzeug, sonst Spieler
    local x, z = nil, nil
    if g_localPlayer ~= nil then
        if g_localPlayer.getCurrentVehicle ~= nil then
            local fz = g_localPlayer:getCurrentVehicle()
            if fz ~= nil and fz.rootNode ~= nil then
                local vx, _, vz = getWorldTranslation(fz.rootNode)
                x, z = vx, vz
            end
        end
        if x == nil and g_localPlayer.getPosition ~= nil then
            local px, _, pz = g_localPlayer:getPosition()
            x, z = px, pz
        end
    end

    -- Zustandswert einer PF-Karte an einer Weltposition. Umrechnung 1:1 nach
    -- dem PF-eigenen Muster in AdditionalFieldBuyInfo.updateFieldSoilDistributionData.
    local function karteWert(karte)
        if karte == nil or karte.bitVectorMap == nil or x == nil then return nil end
        if getBitVectorMapSize == nil or getBitVectorMapPoint == nil then return nil end
        local ts = g_currentMission ~= nil and g_currentMission.terrainSize or nil
        if ts == nil then return nil end
        local sx, sy = getBitVectorMapSize(karte.bitVectorMap)
        if sx == nil or sx < 2 then return nil end
        local px = math.max(0, math.min(sx - 1, math.floor((x + ts * 0.5) / ts * (sx - 1) + 0.5)))
        local py = math.max(0, math.min(sy - 1, math.floor((z + ts * 0.5) / ts * (sy - 1) + 0.5)))
        return getBitVectorMapPoint(karte.bitVectorMap, px, py,
            karte.firstChannel or 0, karte.numChannels or 1)
    end

    local ph = karteWert(pf.pHMap)
    if ph ~= nil and type(pf.pHMap.getPhValueFromInternalValue) == "function" then
        print(string.format("  pH an der eigenen Position: %s (Stufe %s)",
            tostring(pf.pHMap:getPhValueFromInternalValue(ph)), tostring(ph)))
    end
    local n = karteWert(pf.nitrogenMap)
    if n ~= nil and type(pf.nitrogenMap.getNitrogenValueFromInternalValue) == "function" then
        print(string.format("  Stickstoff an der eigenen Position: %s kg/ha (Stufe %s)",
            tostring(pf.nitrogenMap:getNitrogenValueFromInternalValue(n)), tostring(n)))
    end

    -- Stickstoffziele je Frucht (Quelle der Duenge-Aufgabe)
    local ziele = pf.nitrogenMap ~= nil and pf.nitrogenMap.fruitRequirements or nil
    if type(ziele) == "table" then
        local teile = {}
        for _, e in pairs(ziele) do
            if type(e) == "table" and e.fruitTypeName ~= nil then
                teile[#teile + 1] = string.format("%s=%s", tostring(e.fruitTypeName),
                    tostring(e.averageTargetLevel))
            end
        end
        table.sort(teile)
        print("  Stickstoff-Ziele (Stufen je Frucht): " .. table.concat(teile, " "))
    end
    print("=== FA-PF-DUMP ENDE ===")
end

function FruchtfolgeAdvisor.debugDump()
    print("===== FA DEBUG DUMP =====")
    local farmId = FieldAnalyzer.getLocalFarmId()
    print("[FA] farmId=" .. tostring(farmId))

    -- Lager-Totals
    local tots = StorageAnalyzer.getTotals()
    local n = 0
    for k, v in pairs(tots) do
        if v > 0 then
            print("[FA] Lager " .. k .. "=" .. string.format("%.0f", v))
            n = n + 1
        end
    end
    if n == 0 then print("[FA] Lager: leer") end

    -- Tiere + Trog-Futter
    local function schritt()
        local placeables = g_currentMission.placeableSystem.placeables
        if placeables == nil then return end
        for _, p in pairs(placeables) do
            if p ~= nil and p.ownerFarmId == farmId then
                local spec = p.spec_husbandryAnimals or p.spec_animalHusbandry
                if spec ~= nil then
                    local count, typeIdx = 0, 0
                    if p.getNumOfAnimals ~= nil then count = p:getNumOfAnimals() or 0 end
                    if p.getAnimalTypeIndex ~= nil then typeIdx = p:getAnimalTypeIndex() or 0 end
                    print("[FA] Tier: typeIdx=" .. tostring(typeIdx)
                        .. " count=" .. tostring(count))
                    -- Trog-Futter diagnostizieren
                    local function schritt()
                        local fspec = p.spec_husbandryFood
                        if fspec == nil then
                            print("[FA]   kein spec_husbandryFood")
                            return
                        end
                        if type(fspec.fillLevels) == "table" then
                            local any = false
                            for k, v in pairs(fspec.fillLevels) do
                                local desc = nil
                                if g_fillTypeManager ~= nil then
                                    desc = g_fillTypeManager:getFillTypeByIndex(k)
                                end
                                print("[FA]   Trog[" .. tostring(k) .. "]=" .. tostring(v)
                                    .. " [" .. tostring(desc and desc.name) .. "]")
                                any = true
                            end
                            if not any then print("[FA]   Trog leer (fillLevels ohne Eintraege)") end
                        else
                            print("[FA]   fillLevels type=" .. type(fspec.fillLevels))
                        end
                    end
                    schritt()
                end
            end
        end
    end
    schritt()

    -- Eigene Felder
    local allFields = FieldAnalyzer.getOwnFields()
    local own = 0
    local withFruit = 0
    for _, f in ipairs(allFields) do
        if f.isOwn then
            own = own + 1
            if f.currentFruit ~= nil then withFruit = withFruit + 1 end
        end
    end
    print("[FA] Eigene Felder: " .. own .. " / " .. #allFields)
    print("[FA] Eigene Felder mit erkannter Frucht: " .. withFruit .. " / " .. own
        .. " (MP-Client-Diagnose)")
    for i = 1, math.min(5, #allFields) do
        local f = allFields[i]
        if f.isOwn then
            print("[FA]  Feld " .. tostring(f.fieldId)
                .. " aktuell=" .. tostring(f.currentFruit)
                .. " area=" .. string.format("%.2f", (f.area or 0)/10000) .. "ha")
        end
    end

    -- Produktionen
    local prods = ProductionAnalyzer.getProductions(farmId)
    for _, p in ipairs(prods) do
        print("[FA] Produktion: " .. tostring(p.name) .. " Rezepte=" .. #p.recipes)
        for _, r in ipairs(p.recipes) do
            local ins, outs = {}, {}
            for _, i2 in ipairs(r.inputs)  do table.insert(ins,  i2.fillKey .. "=" .. string.format("%.0f", i2.level)) end
            for _, o2 in ipairs(r.outputs) do table.insert(outs, o2.fillKey .. "=" .. string.format("%.0f", o2.level)) end
            print("[FA]   " .. tostring(r.name) .. " aktiv=" .. tostring(r.active)
                .. " IN[" .. table.concat(ins, ",") .. "]"
                .. " OUT[" .. table.concat(outs, ",") .. "]")
        end
    end

    print("===== FA DEBUG END =====")
end

function FruchtfolgeAdvisor:deleteMap()
    if FruchtfolgeAdvisor.overlay ~= nil then
        delete(FruchtfolgeAdvisor.overlay)
        FruchtfolgeAdvisor.overlay = nil
    end
    if removeConsoleCommand ~= nil then
        removeConsoleCommand("faDump")
        removeConsoleCommand("faAufgaben")
    end
end

addModEventListener(FruchtfolgeAdvisor)
