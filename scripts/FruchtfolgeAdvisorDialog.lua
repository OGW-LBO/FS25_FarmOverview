-- FruchtfolgeAdvisorDialog.lua
-- Nativer modaler Dialog (Muster: FS25_AnimalPlanner, extends MessageDialog).
-- Der Rahmen ist das Fenster, der Inhalt liegt nativ darin -> passt automatisch.
-- Nutzt die vorhandenen Zeilen-Builder (FruchtfolgeAdvisor.getSectionRows).
--
-- TAB 6 "Einstellungen": native Auswahlfelder (◄ Wert ►) je Zeile, Muster aus
-- FS25_additionalGameSettings / FS25_HelferLohn (fs25_multiTextOptionContainer +
-- MultiTextOption/BinaryOption, setState/setIsChecked, onClickMultiOption/onClickCheckbox).
-- Alle Werte laufen ueber Bodengesundheit.setCfgValue + onLocalCfgChange
-- (persistent + Multiplayer-Sync, Server autoritativ).

FruchtfolgeAdvisorDialog = {}
local FruchtfolgeAdvisorDialog_mt = Class(FruchtfolgeAdvisorDialog, MessageDialog)

FruchtfolgeAdvisorDialog.SECTION_KEYS = {
    "fa_tab_fields", "fa_tab_storage", "fa_tab_animals", "fa_tab_production", "fa_tab_tasks",
    "fa_tab_crops", "fa_tab_settings", "fa_tab_finance"
}

FruchtfolgeAdvisorDialog.TASKS_TAB    = 5
-- Finanzen haengt als Index 8 hinten an (Knopf steht optisch hinter Aufgaben),
-- damit die bestehenden Indizes 6/7 unveraendert bleiben.
FruchtfolgeAdvisorDialog.FINANCE_TAB  = 8
FruchtfolgeAdvisorDialog.CROPS_TAB    = 6
FruchtfolgeAdvisorDialog.SETTINGS_TAB = 7

-- Lokalisierter Text mit Fallback
local function L(key, fallback)
    local out = nil
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        out = g_i18n:getText(key)
    end
    return out or fallback or key
end

-- Diskrete Werteliste erzeugen (numerische Auswahlfelder)
local function makeValues(lo, hi, step)
    local v = {}
    local n = math.floor((hi - lo) / step + 0.5)
    for i = 0, n do
        v[#v + 1] = lo + i * step
    end
    return v
end

local function nearestIndex(values, cur)
    local bi, bd = 1, math.huge
    for i, x in ipairs(values) do
        local d = math.abs(x - (cur or 0))
        if d < bd then bd = d; bi = i end
    end
    return bi
end

local function exactIndex(values, cur)
    for i, x in ipairs(values) do
        if x == cur then return i end
    end
    return 1
end

-- Lokalisierter Bereichsname (folgt der Spielsprache)
function FruchtfolgeAdvisorDialog.sectionName(t)
    local key = FruchtfolgeAdvisorDialog.SECTION_KEYS[t]
    if key == nil then return "" end
    return L(key, key)
end

function FruchtfolgeAdvisorDialog.new(i18n)
    local self = FruchtfolgeAdvisorDialog:superClass().new(nil, FruchtfolgeAdvisorDialog_mt)
    self.i18n = i18n or g_i18n
    self.rows = {}
    self.tab = 1
    self.expandedField = nil   -- aktuell aufgeklapptes Feld (Index in cache.fields)
    self._rebuilding = false
    self.optInfo = {}          -- [MultiTextOption] = { key, values }
    self.chkKey  = {}          -- [BinaryOption]   = key
    return self
end

function FruchtfolgeAdvisorDialog:copyAttributes(src)
    FruchtfolgeAdvisorDialog:superClass().copyAttributes(self, src)
    self.i18n = src.i18n or g_i18n
    self.rows = {}
    self.tab = src.tab or 1
    self.optInfo = {}
    self.chkKey  = {}
end

-- Liste als Datenquelle/Delegate anmelden (nach GUI-Aufbau)
function FruchtfolgeAdvisorDialog:onGuiSetupFinished()
    FruchtfolgeAdvisorDialog:superClass().onGuiSetupFinished(self)
    if self.faList ~= nil then
        self.faList:setDataSource(self)
        self.faList:setDelegate(self)
    end
    -- Statusaenderungen anderer Spieler (oder die Bestaetigung des Servers)
    -- sofort im offenen Aufgabenzettel zeigen.
    if not self._taskListener and TaskState ~= nil and TaskState.addListener ~= nil then
        self._taskListener = true
        local selbst = self
        TaskState.addListener(function()
            if selbst._offen and selbst.tab == FruchtfolgeAdvisorDialog.TASKS_TAB then
                selbst:refreshTaskRows()
            end
        end)
    end
end

function FruchtfolgeAdvisorDialog:onOpen()
    FruchtfolgeAdvisorDialog:superClass().onOpen(self)
    -- MP-Client: aktuellen Bodengesundheits-Zustand + Einstellungen beim Server anfordern
    if Bodengesundheit ~= nil and Bodengesundheit.requestSync ~= nil then
        Bodengesundheit.requestSync()
    end
    if Bodengesundheit ~= nil and Bodengesundheit.requestCfgSync ~= nil then
        Bodengesundheit.requestCfgSync()
    end
    -- MP-Client: aktuelle Fruchtauswahl beim Server anfragen
    if CropSelectionEvent ~= nil and CropSelectionEvent.request ~= nil then
        CropSelectionEvent.request()
    end
    -- MP-Client: Bearbeitungsstand des Aufgabenzettels anfragen
    if TaskStateEvent ~= nil and TaskStateEvent.request ~= nil then
        TaskStateEvent.request()
    end
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
        FruchtfolgeAdvisor.buildCache()
    end
    self._offen = true
    self:setTab(self.tab or 1)
end

function FruchtfolgeAdvisorDialog:onClose()
    self._offen = false
    FruchtfolgeAdvisorDialog:superClass().onClose(self)
end

-- kleiner Helfer: Element sichtbar schalten (defensiv)
local function setVis(el, vis)
    if el ~= nil and el.setVisible ~= nil then
        el:setVisible(vis)
    end
end

-- Bedarfszeile ueber der Feldliste fuellen ("Knapp: Mais 1.2 Mo | ..."). Nur im
-- Felder-Bereich sichtbar; Text und Farbe kommen aus dem Analyse-Cache.
function FruchtfolgeAdvisorDialog:refreshShortageLine(tab)
    local el = self.faShortage
    if el == nil then return end

    local istFelder = (tab == 1)
    local istCrops  = (tab == FruchtfolgeAdvisorDialog.CROPS_TAB)
    local istTasks  = (tab == FruchtfolgeAdvisorDialog.TASKS_TAB)
    setVis(el, istFelder or istCrops or istTasks)
    if not (istFelder or istCrops or istTasks) then return end

    local text, col
    if istTasks then
        -- Aufgabenzettel: Zaehler + Bedienhinweis
        text, col = "", { 0.62, 0.62, 0.62 }
        if TaskAnalyzer ~= nil and TaskAnalyzer.getSummaryLine ~= nil then
            text = TaskAnalyzer.getSummaryLine()
        end
    elseif istCrops then
        -- Im Fruechte-Bereich traegt dieselbe Zeile den Bedienhinweis.
        text, col = L("fa_crops_hint", "Click a crop to include or exclude it."),
                    { 0.62, 0.62, 0.62 }
    else
        if FruchtfolgeAdvisor == nil or FruchtfolgeAdvisor.getShortageLine == nil then return end
        text, col = FruchtfolgeAdvisor.getShortageLine()
    end
    if el.setText ~= nil then el:setText(text or "") end
    if col ~= nil and el.setTextColor ~= nil then
        el:setTextColor(col[1], col[2], col[3], 1)
    end
end

-- Bereich setzen + Inhalt umschalten (Liste <-> Einstellungen)
function FruchtfolgeAdvisorDialog:setTab(t)
    local nKeys = #FruchtfolgeAdvisorDialog.SECTION_KEYS
    if t < 1 then t = nKeys end
    if t > nKeys then t = 1 end
    self.tab = t
    local isSettings = (t == FruchtfolgeAdvisorDialog.SETTINGS_TAB)
    if t ~= 1 then self.expandedField = nil end

    if not isSettings then
        if t == 1 then
            self.rows = FruchtfolgeAdvisor.getFieldRows(self.expandedField)
        else
            self.rows = FruchtfolgeAdvisor.getSectionRows(t)
        end
        if self.rows == nil then self.rows = {} end
    else
        self.rows = {}
    end

    -- Inhalt umschalten: Liste + Slider vs. Einstellungs-Layout
    setVis(self.faList, not isSettings)
    setVis(self.faListSlider, not isSettings)
    setVis(self.faListSliderBox, not isSettings)
    setVis(self.faSettingsLayout, isSettings)

    -- Infozeile: Bedarf im Felder-Bereich, Bedienhinweis im Fruechte-Bereich
    self:refreshShortageLine(t)

    if isSettings then
        self:buildSettingsControls()
    else
        if self.faList ~= nil and self.faList.reloadData ~= nil then
            self.faList:reloadData()
        end
    end

    -- Titel aktualisieren
    if self.dialogTitleElement ~= nil and self.dialogTitleElement.setText ~= nil then
        local titleBase = L("fa_title", "Farm Overview")
        self.dialogTitleElement:setText(titleBase .. "  -  "
            .. FruchtfolgeAdvisorDialog.sectionName(t))
    end

    self:updateTabHighlight()
end

-- Aktiven Bereichs-Tab farbig hervorheben (Text gruen), die anderen weiss.
function FruchtfolgeAdvisorDialog:updateTabHighlight()
    for i = 1, #FruchtfolgeAdvisorDialog.SECTION_KEYS do
        local btn = self["btnTab" .. i]
        if btn ~= nil then
            local active = (i == self.tab)
            if btn.setTextColor ~= nil then
                if active then btn:setTextColor(0.42, 0.69, 0.20, 1)
                else btn:setTextColor(1, 1, 1, 1) end
            end
            if btn.setSelected ~= nil then btn:setSelected(active) end
        end
    end
end

function FruchtfolgeAdvisorDialog:onClickNextTab()
    self:setTab((self.tab or 1) + 1)
    return true
end

-- Direkte Bereichs-Auswahl per Button
function FruchtfolgeAdvisorDialog:onClickTabFelder()      self:setTab(1) return true end
function FruchtfolgeAdvisorDialog:onClickTabLager()       self:setTab(2) return true end
function FruchtfolgeAdvisorDialog:onClickTabTiere()       self:setTab(3) return true end
function FruchtfolgeAdvisorDialog:onClickTabProduktion()  self:setTab(4) return true end
function FruchtfolgeAdvisorDialog:onClickTabReport()      self:setTab(FruchtfolgeAdvisorDialog.TASKS_TAB) return true end
function FruchtfolgeAdvisorDialog:onClickTabCrops()       self:setTab(6) return true end
function FruchtfolgeAdvisorDialog:onClickTabSettings()    self:setTab(7) return true end
function FruchtfolgeAdvisorDialog:onClickTabFinanzen()    self:setTab(FruchtfolgeAdvisorDialog.FINANCE_TAB) return true end

function FruchtfolgeAdvisorDialog:onClickBack()
    self:close()
    return true
end

-- ── Einstellungs-Tab: Auswahlfelder befuellen ─────────────────
-- Werteraster
local PRESET_VALUES = { "arcade", "standard", "realistisch", "custom" }
local HEALTH_VALUES = makeValues(0, 100, 5)     -- 0..100 %, Schritt 5
local YIELD_VALUES  = makeValues(0, 2, 0.05)    -- 0.00..2.00, Schritt 0.05
local SCALE_VALUES  = makeValues(0, 2, 0.05)    -- 0.00..2.00, Schritt 0.05

local function presetTexts()
    return {
        L("fa_preset_arcade",      "Arcade"),
        L("fa_preset_standard",    "Standard"),
        L("fa_preset_realistisch", "Realistisch"),
        L("fa_preset_custom",      "Benutzerdefiniert"),
    }
end

local function healthTexts()
    local t = {}
    for i, v in ipairs(HEALTH_VALUES) do t[i] = string.format("%d %%", v) end
    return t
end

local function factorTexts(values)
    local t = {}
    for i, v in ipairs(values) do t[i] = string.format("%.2f", v) end
    return t
end

-- MultiTextOption mit Texten + aktuellem Zustand belegen.
--   numeric=true -> nearestIndex (Wert liegt evtl. nicht exakt auf dem Raster)
function FruchtfolgeAdvisorDialog:setupMulti(el, key, values, texts, curValue, numeric)
    if el == nil then return end
    if el.setTexts ~= nil then el:setTexts(texts) end
    local idx = numeric and nearestIndex(values, curValue) or exactIndex(values, curValue)
    if el.setState ~= nil then el:setState(idx, nil, true) end
    self.optInfo[el] = { key = key, values = values }
end

function FruchtfolgeAdvisorDialog:setupBool(el, key, checked)
    if el == nil then return end
    -- Weg des farbigen Schiebers neu berechnen: BinaryOptionElement rechnet
    -- sliderDelta nur einmal in setElementsByName aus absSize. Eine Seite im
    -- ESC-Menue wird aber erst beim Einhaengen skaliert (Gui.lua:313, Frames
    -- nicht beim Laden) - der alte Wert schob den Schieber bei AN ins Leere.
    -- Formel 1:1 aus BinaryOptionElement.lua:101.
    if el.sliderElement ~= nil and el.absSize ~= nil and el.sliderElement.absSize ~= nil
            and BinaryOptionElement ~= nil and BinaryOptionElement.NUM_SLIDER_STATES ~= nil then
        el.sliderDelta = (el.absSize[1] - el.sliderElement.absSize[1]) / BinaryOptionElement.NUM_SLIDER_STATES
    end
    if el.setIsChecked ~= nil then el:setIsChecked(checked == true, true) end
    -- Schieber sofort auf die richtige Seite stellen (wie update() mit
    -- skipAnimation), damit auch ohne Animation nichts dazwischen haengt.
    if el.sliderElement ~= nil and el.sliderElement.setPosition ~= nil and el.sliderDelta ~= nil
            and BinaryOptionElement ~= nil and BinaryOptionElement.NUM_SLIDER_STATES ~= nil then
        el.sliderState = (checked == true) and BinaryOptionElement.NUM_SLIDER_STATES or 0
        el.sliderMovingDirection = 0
        el.sliderElement:setPosition(el.sliderDelta * el.sliderState)
    end
    self.chkKey[el] = key
end

function FruchtfolgeAdvisorDialog:buildSettingsControls()
    self.optInfo = {}
    self.chkKey  = {}
    local cfg = (Bodengesundheit ~= nil and Bodengesundheit.cfg) or {}

    self:setupBool(self.chkEnabled,     "enabled",     cfg.enabled)
    self:setupBool(self.chkAffectYield, "affectYield", cfg.affectYield)

    -- Optionale Feldarbeiten im Bereich Aufgaben (AUS = Aufgabe wird nicht
    -- aufgelistet). Fehlt der Wert, gilt AN.
    self:setupBool(self.chkTaskRoll,  "taskRoll",  cfg.taskRoll  ~= false)
    self:setupBool(self.chkTaskWeeds, "taskWeeds", cfg.taskWeeds ~= false)
    self:setupBool(self.chkTaskFert,  "taskFert",  cfg.taskFert  ~= false)
    self:setupBool(self.chkTaskLime,  "taskLime",  cfg.taskLime  ~= false)
    self:setupBool(self.chkTaskPlow,  "taskPlow",  cfg.taskPlow  ~= false)

    self:setupMulti(self.optPreset,      "preset",      PRESET_VALUES, presetTexts(),          cfg.preset,      false)
    self:setupMulti(self.optStartHealth, "startHealth", HEALTH_VALUES, healthTexts(),          cfg.startHealth, true)
    self:setupMulti(self.optYieldMin,    "yieldMin",    YIELD_VALUES,  factorTexts(YIELD_VALUES), cfg.yieldMin, true)
    self:setupMulti(self.optYieldMax,    "yieldMax",    YIELD_VALUES,  factorTexts(YIELD_VALUES), cfg.yieldMax, true)
    self:setupMulti(self.optHealthScale, "healthScale", SCALE_VALUES,  factorTexts(SCALE_VALUES), cfg.healthScale, true)

    self:buildCropControls()
    self:applyRowColors(self.faSettingsLayout)
end

FruchtfolgeAdvisorDialog.MAX_CROP_ROWS = 64

-- Fruechte der Karte als AN/AUS-Zeilen im Einstellungsbereich (ersetzt den
-- frueheren Reiter Fruechte). Titel: Name, Familie, Ertrag - dieselben Angaben
-- wie vorher in der Liste. AN = die Frucht wird empfohlen.
function FruchtfolgeAdvisorDialog:buildCropControls()
    if CropRotationData == nil or CropRotationData.getCropName == nil then return end
    local quelle = CropRotationData.mapCrops or {}
    local liste = {}
    for _, c in ipairs(quelle) do liste[#liste + 1] = c end
    table.sort(liste, function(a, b)
        return CropRotationData.getCropName(a) < CropRotationData.getCropName(b)
    end)

    local L = FruchtfolgeAdvisor.L
    for i = 1, FruchtfolgeAdvisorDialog.MAX_CROP_ROWS do
        local zeile = self["cropRow" .. i]
        local opt   = self["cropOpt" .. i]
        local titel = self["cropTitle" .. i]
        local crop  = liste[i]
        if zeile ~= nil then
            if crop == nil or opt == nil then
                zeile:setVisible(false)
            else
                zeile:setVisible(true)
                local info = (CropRotationData.mapInfo or {})[crop] or {}
                local fam = CropRotationData.getFamilyName(info.family) or L("fa_fam_unknown")
                if info.source == "unknown" then fam = L("fa_fam_unknown") end
                local teile = { fam }
                if info.yield ~= nil and info.yield > 0 then
                    teile[#teile + 1] = string.format("%d l/ha", info.yield)
                end
                if info.perennial then teile[#teile + 1] = L("fa_fam_perennial") end
                if titel ~= nil and titel.setText ~= nil then
                    titel:setText(CropRotationData.getCropName(crop) .. "  (" .. table.concat(teile, ", ") .. ")")
                end
                self:setupBool(opt, "crop:" .. crop, CropRotationData.isCropEnabled(crop))
            end
        end
    end
    if #liste > FruchtfolgeAdvisorDialog.MAX_CROP_ROWS then
        Logging.warning("[FarmOverview] Karte hat %d Fruechte, angezeigt werden %d.",
            #liste, FruchtfolgeAdvisorDialog.MAX_CROP_ROWS)
    end
end

-- Eine Frucht per Schalter an- oder abwaehlen (Server speichert und verteilt,
-- ein Client meldet den Wunsch an den Server - wie bisher im Reiter Fruechte).
function FruchtfolgeAdvisorDialog:setCropFromSwitch(crop, an)
    if CropRotationData == nil or CropRotationData.setCropEnabled == nil then return end
    if CropRotationData.isCropEnabled(crop) == an then return end
    CropRotationData.setCropEnabled(crop, an)
    Logging.info("[FarmOverview] Frucht %s (%s) %s.", tostring(crop),
        tostring(CropRotationData.getCropName(crop)),
        an and "wieder in den Empfehlungen" or "aus den Empfehlungen genommen")
    if CropSelectionEvent ~= nil and CropSelectionEvent.send ~= nil then
        CropSelectionEvent.send()
    elseif FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.saveSettings ~= nil then
        FruchtfolgeAdvisor.saveSettings()
    end
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
        FruchtfolgeAdvisor.buildCache()
    end
end

-- Nur die Zahlen-Auswahlfelder aus der cfg neu setzen (nach Preset-Wechsel).
function FruchtfolgeAdvisorDialog:refreshNumberControls()
    local cfg = (Bodengesundheit ~= nil and Bodengesundheit.cfg) or {}
    local function reset(el, values, curValue)
        if el == nil then return end
        if el.setState ~= nil then el:setState(nearestIndex(values, curValue), nil, true) end
    end
    reset(self.optStartHealth, HEALTH_VALUES, cfg.startHealth)
    reset(self.optYieldMin,    YIELD_VALUES,  cfg.yieldMin)
    reset(self.optYieldMax,    YIELD_VALUES,  cfg.yieldMax)
    reset(self.optHealthScale, SCALE_VALUES,  cfg.healthScale)
end

-- Zeilen-Hintergruende einfaerben (dunkel abwechselnd), sonst weisser Default
-- -> heller Titeltext waere unlesbar. Nutzt die echten Menue-Farben, falls da.
function FruchtfolgeAdvisorDialog:applyRowColors(layout)
    if layout == nil or layout.elements == nil then return end
    local cols = (InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.COLOR_ALTERNATING) or nil
    local alt = true
    for _, c in ipairs(layout.elements) do
        if c.name == "sectionHeader" then
            alt = true
        elseif c.setImageColor ~= nil and (c.getIsVisibleNonRec == nil or c:getIsVisibleNonRec()) then
            if cols ~= nil and cols[alt] ~= nil then
                c:setImageColor(nil, unpack(cols[alt]))
            elseif alt then
                c:setImageColor(nil, 0, 0, 0, 0.0)
            else
                c:setImageColor(nil, 1, 1, 1, 0.07)
            end
            alt = not alt
        end
    end
    if layout.invalidateLayout ~= nil then layout:invalidateLayout() end
end

-- ── Callbacks der Auswahlfelder ───────────────────────────────
function FruchtfolgeAdvisorDialog:onClickCheckbox(state, checkboxElement)
    local key = self.chkKey and self.chkKey[checkboxElement]
    if key == nil then return end
    -- AN/AUS direkt beim Schalter abfragen: BinaryOptionElement:getIsChecked()
    -- = rechter Zustand = "AN" (BinaryOptionElement.lua:147). Vorher wurde der
    -- Zustand mit CheckedOptionElement.STATE_CHECKED verglichen - einer
    -- Konstante einer ANDEREN Klasse; passt deren Wert nicht, ist AN/AUS
    -- vertauscht (Frucht abgewaehlt -> blieb in den Empfehlungen).
    local checked
    if checkboxElement ~= nil and checkboxElement.getIsChecked ~= nil then
        checked = checkboxElement:getIsChecked()
    elseif BinaryOptionElement ~= nil and BinaryOptionElement.STATE_RIGHT ~= nil then
        checked = (state == BinaryOptionElement.STATE_RIGHT)
    else
        checked = (state == 2 or state == true)
    end
    if string.sub(key, 1, 5) == "crop:" then
        self:setCropFromSwitch(string.sub(key, 6), checked)
        return
    end
    if Bodengesundheit == nil then return end
    Bodengesundheit.setCfgValue(key, checked)
    Bodengesundheit.onLocalCfgChange()
end

function FruchtfolgeAdvisorDialog:onClickMultiOption(state, optionElement)
    local info = self.optInfo and self.optInfo[optionElement]
    if info == nil or Bodengesundheit == nil then return end
    local v = info.values[state]
    if v == nil then return end
    Bodengesundheit.setCfgValue(info.key, v)
    Bodengesundheit.onLocalCfgChange()
    -- Preset gewechselt -> Zahlen zeigen jetzt die Preset-Werte
    if info.key == "preset" then
        self:refreshNumberControls()
    end
end

-- Auswahländerung im Felder-Bereich:
--   * Klick auf die "[ zuklappen ]"-Zeile -> zuklappen
--   * Klick auf ein anderes Feld -> dieses aufklappen
-- Fruechte-Bereich: eine Zeile an- oder abwaehlen und die Liste neu aufbauen.
-- Nur der Server/Singleplayer schreibt die Auswahl; sie steckt in der
-- Savegame-XML und gilt damit fuer den ganzen Hof.
function FruchtfolgeAdvisorDialog:toggleCrop(crop)
    if crop == nil or CropRotationData == nil then return end
    local neu = not CropRotationData.isCropEnabled(crop)
    CropRotationData.setCropEnabled(crop, neu)

    -- Server speichert und verteilt, ein Client meldet seinen Wunsch an den
    -- Server. saveSettings allein reicht nicht: auf dem Client steigt es
    -- wegen g_server == nil sofort aus, die Auswahl waere nicht persistent.
    if CropSelectionEvent ~= nil and CropSelectionEvent.send ~= nil then
        CropSelectionEvent.send()
    elseif FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.saveSettings ~= nil then
        FruchtfolgeAdvisor.saveSettings()
    end
    -- Empfehlungen haengen an der Fruchtliste -> Analyse neu aufbauen
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
        FruchtfolgeAdvisor.buildCache()
    end

    local merker = (self.faList ~= nil) and self.faList.selectedIndex or nil
    self.rows = FruchtfolgeAdvisor.getSectionRows(FruchtfolgeAdvisorDialog.CROPS_TAB) or {}
    self._selCooldown = 120
    if self.faList ~= nil and self.faList.reloadData ~= nil then
        self.faList:reloadData()
        if merker ~= nil and self.faList.setSelectedIndex ~= nil then
            self.faList:setSelectedIndex(merker)
        end
    end
end

-- Im Fruechte-Bereich wird hier bewusst NICHTS umgeschaltet: die Auswahl
-- aendert sich auch ohne Klick (Neuladen der Liste, erneutes Oeffnen des
-- Fensters mit der zuletzt gewaehlten Zeile). Daran gekoppelt schaltete die
-- zuletzt angeklickte Frucht beim naechsten Oeffnen von selbst zurueck.
-- Umgeschaltet wird nur ueber echte Klicks, siehe onListClick/onListDoubleClick.
function FruchtfolgeAdvisorDialog:onListSelectionChanged(list, section, index)
    if self.tab ~= 1 then return end
    if (self._selCooldown or 0) > 0 then return end   -- Reload-Callback ignorieren
    local row = (self.rows or {})[index]
    if row == nil then return end
    if row.collapse then
        self:setExpanded(nil)
        return
    end
    if row.fieldIndex ~= nil and row.fieldIndex ~= self.expandedField then
        self:setExpanded(row.fieldIndex)
    end
end

-- Echter Klick (feuert auch auf die bereits ausgewaehlte Zeile): offenes Feld zuklappen.
-- Fruechte-Zeile unter dem Index umschalten (nur bei echten Klicks aufgerufen).
function FruchtfolgeAdvisorDialog:toggleCropAt(index)
    if type(index) ~= "number" then return end
    local r = (self.rows or {})[index]
    if r ~= nil and r.cropName ~= nil then self:toggleCrop(r.cropName) end
end

-- Echter Klick. SmoothListElement:notifyClick liefert (list, section, index,
-- element, wasAlreadySelected) und feuert nur auf Maus-/Tasteneingabe, nie beim
-- Neuladen - deshalb haengt das Umschalten der Fruechte hier und nicht an der
-- Auswahl-Aenderung. Auch ein Klick auf die bereits gewaehlte Zeile kommt an.
function FruchtfolgeAdvisorDialog:onListClick(list, section, index)
    if self.tab == FruchtfolgeAdvisorDialog.TASKS_TAB then
        if type(index) ~= "number" and list ~= nil then index = list.selectedIndex end
        self:cycleTaskAt(index)
        return
    end
    if self.tab == FruchtfolgeAdvisorDialog.CROPS_TAB then
        if type(index) ~= "number" and list ~= nil then index = list.selectedIndex end
        self:toggleCropAt(index)
        return
    end
    if self.tab ~= 1 then return end
    if (self._selCooldown or 0) > 0 then return end
    local idx = (list ~= nil and list.selectedIndex) or nil
    if type(idx) ~= "number" then return end
    local row = (self.rows or {})[idx]
    if row ~= nil and row.fieldIndex ~= nil and row.fieldIndex == self.expandedField then
        self:setExpanded(nil)
    end
end

-- Schneller zweiter Klick auf dieselbe Zeile: die Liste meldet ihn NUR als
-- Doppelklick, nicht als Klick. Im Fruechte-Bereich zaehlt er als weiterer
-- Klick - sonst ginge jedes schnelle Zurueckschalten verloren.
function FruchtfolgeAdvisorDialog:onListDoubleClick(list, section, index)
    if self.tab == FruchtfolgeAdvisorDialog.CROPS_TAB then
        if type(index) ~= "number" and list ~= nil then index = list.selectedIndex end
        self:toggleCropAt(index)
    elseif self.tab == FruchtfolgeAdvisorDialog.TASKS_TAB then
        if type(index) ~= "number" and list ~= nil then index = list.selectedIndex end
        self:cycleTaskAt(index)
    end
end

-- Aufgabenzettel: Status der angeklickten Aufgabe weiterschalten
-- (offen <-> uebernommen). Nur echte Klicks, siehe oben.
function FruchtfolgeAdvisorDialog:cycleTaskAt(index)
    if type(index) ~= "number" then return end
    local r = (self.rows or {})[index]
    if r == nil then return end
    -- Kopfzeile eines Feldes: Schritte ein- oder ausklappen. Alles ist
    -- standardmaessig offen; eingeklappt wird nur, was man abgehakt hat.
    if r.feldBlock ~= nil then
        self.aufgeklappteFelder = self.aufgeklappteFelder or {}
        if self.aufgeklappteFelder[r.feldBlock] then
            self.aufgeklappteFelder[r.feldBlock] = nil
        else
            self.aufgeklappteFelder[r.feldBlock] = true
        end
        self:refreshTaskRows()
        return
    end
    if r.taskKey == nil or TaskState == nil or TaskState.cycle == nil then return end
    TaskState.cycle(r.taskKey)
    self:refreshTaskRows()
end

-- Zeilen des Aufgabenzettels neu setzen, ohne neu zu analysieren (nur der
-- Status hat sich geaendert). Die Auswahl bleibt auf derselben Aufgabe.
function FruchtfolgeAdvisorDialog:refreshTaskRows()
    if TaskAnalyzer == nil or TaskAnalyzer.getRows == nil then return end
    local merkKey = nil
    if self.faList ~= nil and type(self.faList.selectedIndex) == "number" then
        local alt = (self.rows or {})[self.faList.selectedIndex]
        if alt ~= nil then merkKey = alt.taskKey end
    end
    self.rows = TaskAnalyzer.getRows(self.aufgeklappteFelder) or {}
    self._selCooldown = 120
    if self.faList ~= nil and self.faList.reloadData ~= nil then
        self.faList:reloadData()
        if merkKey ~= nil and self.faList.setSelectedIndex ~= nil then
            for i, r in ipairs(self.rows) do
                if r.taskKey == merkKey then
                    self.faList:setSelectedIndex(i)
                    break
                end
            end
        end
    end
    self:refreshShortageLine(self.tab)
end

function FruchtfolgeAdvisorDialog:setExpanded(fieldIndex)
    self.expandedField = fieldIndex
    self.rows = FruchtfolgeAdvisor.getFieldRows(fieldIndex) or {}
    self._selCooldown = 120   -- kurze Sperre, damit der Reload nicht sofort neu triggert
    if self.faList ~= nil and self.faList.reloadData ~= nil then
        self.faList:reloadData()
        local target = 1   -- Zuklappen: Auswahl auf die Kopfzeile (kein Feld), damit
                           -- die naechste Feldzeile wieder ein echter Wechsel ist.
        if fieldIndex ~= nil then
            for i, r in ipairs(self.rows) do
                if r.fieldIndex == fieldIndex then target = i break end
            end
        end
        if self.faList.setSelectedIndex ~= nil then self.faList:setSelectedIndex(target) end
    end
end

function FruchtfolgeAdvisorDialog:update(dt)
    FruchtfolgeAdvisorDialog:superClass().update(self, dt)
    if self._selCooldown ~= nil and self._selCooldown > 0 then
        self._selCooldown = self._selCooldown - (dt or 16)
    end
end

-- ── SmoothList-Delegates ──────────────────────────────────────
function FruchtfolgeAdvisorDialog:getNumberOfSections()
    return (#(self.rows or {}) > 0) and 1 or 0
end

function FruchtfolgeAdvisorDialog:getNumberOfItemsInSection(list, section)
    return #(self.rows or {})
end

function FruchtfolgeAdvisorDialog:populateCellForItemInSection(list, section, index, cell)
    local row = (self.rows or {})[index]
    if row == nil then return end

    local COLS = { "colA", "colB", "colC", "colD", "colE", "colF" }
    local function set(attr, text, col)
        if cell == nil or cell.getAttribute == nil then return end
        local el = cell:getAttribute(attr)
        if el ~= nil then
            if el.setText ~= nil then el:setText(text or "") end
            if col ~= nil and el.setTextColor ~= nil then
                el:setTextColor(col[1], col[2], col[3], 1)
                -- TextElement haelt eigene Farben fuer ausgewaehlt/markiert
                -- (TextElement.lua: setTextSelectedColor/HighlightedColor) und
                -- nimmt in diesen Zustaenden die Profilfarbe - die angeklickte
                -- oder ueberfahrene Zeile wurde dadurch wieder fast weiss.
                -- Deshalb alle Zustaende auf dieselbe Farbe setzen.
                if el.setTextSelectedColor ~= nil then
                    el:setTextSelectedColor(col[1], col[2], col[3], 1)
                end
                if el.setTextHighlightedColor ~= nil then
                    el:setTextHighlightedColor(col[1], col[2], col[3], 1)
                end
                if el.setTextHighlightedSelectedColor ~= nil then
                    el:setTextHighlightedSelectedColor(col[1], col[2], col[3], 1)
                end
                if el.setTextFocusedColor ~= nil then
                    el:setTextFocusedColor(col[1], col[2], col[3], 1)
                end
                if el.setTextFocusedSelectedColor ~= nil then
                    el:setTextFocusedSelectedColor(col[1], col[2], col[3], 1)
                end
            end
        end
    end

    -- Abschnittstitel stehen in colS ueber die ganze Zeile; sonst bleibt colS leer
    set("colS", "", nil)
    if row.head ~= nil then
        for i = 1, 6 do set(COLS[i], row.head[i] or "", { 0.62, 0.62, 0.62 }) end
    elseif row.section ~= nil then
        -- row.col setzt der Aufgabenzettel je Dringlichkeit; sonst gruen wie bisher
        set("colS", row.section, row.col or { 0.60, 0.95, 0.35 })
        for i = 1, 6 do set(COLS[i], "", nil) end
    else
        local cells = row.cells or {}
        for i = 1, 6 do
            local cd = cells[i]
            if cd ~= nil then
                set(COLS[i], cd.t or "", cd.col or { 1, 1, 1 })
            else
                set(COLS[i], "", nil)
            end
        end
    end
end
