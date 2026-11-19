-- FarmOverviewPage.lua
-- Betriebsuebersicht als eigene Seite im ESC-Menue. Ersetzt das fruehere
-- Strg+F7-Fenster.
--
-- Einbau nach dem Muster laufender Mods (siehe init): Seite als Frame laden
-- (g_gui:loadGui(..., true), Gui.lua:280), selbst ins pagingElement haengen,
-- dann registerPage + addPageTab + rebuildTabList. TabbedMenu:addPage allein
-- reicht NICHT (Fehler PagingElement.lua:249).
--
-- Die Logik (Bereiche, Liste, Klicks, Einstellungen, Aufgaben) stammt
-- unveraendert aus FruchtfolgeAdvisorDialog.lua: deren Methoden werden auf
-- diese Seitenklasse uebernommen. Neu geschrieben sind nur die Stellen, die
-- an der Basisklasse haengen (new, onGuiSetupFinished, Oeffnen/Schliessen,
-- update) - aus einem MessageDialog wird ein TabbedMenuFrameElement.
--
-- TabbedMenuFrameElement gibt es beim Laden der Mod-Skripte noch nicht,
-- deshalb entsteht die Klasse erst in init().

FarmOverviewPage = {}

FarmOverviewPage.NAME         = "FarmOverviewPage"
FarmOverviewPage.MAX_VERSUCHE = 60
FarmOverviewPage.LOG          = "[FarmOverview] "

FarmOverviewPage.mt       = nil
FarmOverviewPage.instanz  = nil
FarmOverviewPage.aktiv    = false
FarmOverviewPage.versuche = 0
FarmOverviewPage.fertig   = false

local modDirectory = g_currentModDirectory

local function L(key, fallback)
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.L ~= nil then
        return FruchtfolgeAdvisor.L(key, fallback)
    end
    return fallback or key
end

-- Methoden, die an der Basisklasse des alten Fensters haengen, oder
-- Klassen-Interna: nicht uebernehmen.
local NICHT_UEBERNEHMEN = {
    new = true, copyAttributes = true, onGuiSetupFinished = true,
    onOpen = true, onClose = true, update = true, onClickBack = true,
    superClass = true, class = true, isa = true,
}

local function klasseAnlegen()
    if FarmOverviewPage.mt ~= nil then
        return true
    end
    if TabbedMenuFrameElement == nil or FruchtfolgeAdvisorDialog == nil then
        return false
    end
    FarmOverviewPage.mt = Class(FarmOverviewPage, TabbedMenuFrameElement)
    for name, fn in pairs(FruchtfolgeAdvisorDialog) do
        if type(fn) == "function" and not NICHT_UEBERNEHMEN[name]
                and rawget(FarmOverviewPage, name) == nil then
            FarmOverviewPage[name] = fn
        end
    end
    return true
end

-- ============================================================================
-- Lebenszyklus der Seite
-- ============================================================================

function FarmOverviewPage.new()
    local self = TabbedMenuFrameElement.new(nil, FarmOverviewPage.mt)
    self.rows          = {}
    self.tab           = FruchtfolgeAdvisorDialog.TASKS_TAB   -- Startseite: Aufgaben
    self.expandedField = nil
    self._rebuilding   = false
    self.optInfo       = {}
    self.chkKey        = {}
    self._offen        = false
    return self
end

function FarmOverviewPage:copyAttributes(src)
    FarmOverviewPage:superClass().copyAttributes(self, src)
    self.rows    = {}
    self.tab     = src.tab or 1
    self.optInfo = {}
    self.chkKey  = {}
end

function FarmOverviewPage:onGuiSetupFinished()
    FarmOverviewPage:superClass().onGuiSetupFinished(self)
    if self.faList ~= nil then
        self.faList:setDataSource(self)
        self.faList:setDelegate(self)
    end
    -- Statusaenderungen anderer Spieler sofort im offenen Aufgabenbereich zeigen
    if not self._taskListener and TaskState ~= nil and TaskState.addListener ~= nil then
        self._taskListener = true
        local selbst = self
        TaskState.addListener(function()
            if selbst._offen and selbst.tab == FruchtfolgeAdvisorDialog.TASKS_TAB then
                selbst:refreshTaskRows()
            end
        end)
    end
    -- Einstellungen des Servers eingetroffen: Aufgabenliste sofort neu
    -- auswerten (dort haengt z. B. ab, ob Walzen aufgelistet wird).
    if not self._cfgListener and Bodengesundheit ~= nil and Bodengesundheit.addCfgListener ~= nil then
        self._cfgListener = true
        local selbst = self
        Bodengesundheit.addCfgListener(function()
            if selbst._offen and selbst.tab == FruchtfolgeAdvisorDialog.TASKS_TAB then
                selbst:liveAktualisieren()
            end
        end)
    end
end

function FarmOverviewPage:onFrameOpen()
    FarmOverviewPage:superClass().onFrameOpen(self)

    -- MP-Client: aktuellen Stand beim Server anfragen
    if Bodengesundheit ~= nil and Bodengesundheit.requestSync ~= nil then
        Bodengesundheit.requestSync()
    end
    if Bodengesundheit ~= nil and Bodengesundheit.requestCfgSync ~= nil then
        Bodengesundheit.requestCfgSync()
    end
    -- Frucht-Gedaechtnis (= Vorfrucht) vom Server: gleiche Empfehlung fuer alle
    if FruitMemoryEvent ~= nil and FruitMemoryEvent.request ~= nil then
        FruitMemoryEvent.request()
    end
    if CropSelectionEvent ~= nil and CropSelectionEvent.request ~= nil then
        CropSelectionEvent.request()
    end
    if TaskStateEvent ~= nil and TaskStateEvent.request ~= nil then
        TaskStateEvent.request()
    end

    -- Symbol in der Kopfzeile (weisses Glyph, Muster FS25_CropRotation)
    if not self._iconGesetzt and self.faHeaderIcon ~= nil and self.faHeaderIcon.setImageFilename ~= nil then
        self.faHeaderIcon:setImageFilename(Utils.getFilename("images/menuIcon.dds", modDirectory))
        self._iconGesetzt = true
    end

    -- Bereich Finanzen nur, wenn FarmEconomy geladen ist (liefert die Zahlen)
    local finanzen = FinanceBridge ~= nil and FinanceBridge.isAvailable()
    if self.btnTab8 ~= nil and self.btnTab8.setVisible ~= nil then
        self.btnTab8:setVisible(finanzen)
        if self.faTabBox ~= nil and self.faTabBox.invalidateLayout ~= nil then
            self.faTabBox:invalidateLayout()
        end
    end
    if finanzen then
        FinanceBridge.request()
    elseif self.tab == FruchtfolgeAdvisorDialog.FINANCE_TAB then
        self.tab = FruchtfolgeAdvisorDialog.TASKS_TAB
    end

    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
        FruchtfolgeAdvisor.buildCache()
    end
    self._offen = true
    -- Erste Auffrischung schon nach 1 s statt nach 5 s: Als MP-Client treffen
    -- Besitz- und Stalldaten teils erst nach dem Beitreten ein. Wer die Seite
    -- kurz danach oeffnet, sah sonst eine fast leere Aufgabenliste und musste
    -- bis zur naechsten Auswertung warten (gemeldet 06.10.2026).
    self._liveTimer = math.max(0, FarmOverviewPage.LIVE_INTERVALL - 1000)
    self:setTab(self.tab or 1)
end

function FarmOverviewPage:onFrameClose()
    self._offen = false
    FarmOverviewPage:superClass().onFrameClose(self)
end

-- Aufgabenbereich bei offener Seite alle LIVE_INTERVALL ms neu auswerten:
-- Wer im Mehrspieler arbeitet (oder im Einzelspieler mit laufender Zeit),
-- sieht erledigte Arbeit sofort verschwinden, ohne das Menue neu zu oeffnen.
FarmOverviewPage.LIVE_INTERVALL = 5000

-- Fingerabdruck der Aufgabenzeilen: neu gezeichnet wird nur, wenn sich etwas
-- geaendert hat - sonst spraenge die Liste alle paar Sekunden nach oben.
local function fingerabdruck(rows)
    local teile = {}
    for _, r in ipairs(rows or {}) do
        local c = r.cells or {}
        teile[#teile + 1] = table.concat({
            tostring(r.taskKey or r.feldBlock or r.section or ""),
            tostring(c[1] and c[1].t or ""), tostring(c[2] and c[2].t or ""),
            tostring(c[4] and c[4].t or ""), tostring(c[5] and c[5].t or ""),
        }, "|")
    end
    return table.concat(teile, "#")
end

function FarmOverviewPage:update(dt)
    FarmOverviewPage:superClass().update(self, dt)
    if self._selCooldown ~= nil and self._selCooldown > 0 then
        self._selCooldown = self._selCooldown - (dt or 16)
    end

    -- Finanzen: Im Mehrspieler kommt das Paket per Event nach dem Oeffnen -
    -- sobald es da ist (oder sich aendert), die Liste neu fuellen.
    if self._offen and self.tab == FruchtfolgeAdvisorDialog.FINANCE_TAB and FinanceBridge ~= nil then
        local paket = FinanceBridge.paket()
        if paket ~= self._finanzPaket then
            self._finanzPaket = paket
            self.rows = FinanceBridge.getRows() or {}
            if self.faList ~= nil and self.faList.reloadData ~= nil then
                self.faList:reloadData()
            end
        end
    end

    if self._offen and self.tab == FruchtfolgeAdvisorDialog.TASKS_TAB then
        self._liveTimer = (self._liveTimer or 0) + (dt or 16)
        if self._liveTimer >= FarmOverviewPage.LIVE_INTERVALL then
            self._liveTimer = 0
            self:liveAktualisieren()
        end
    else
        self._liveTimer = 0
    end
end

--- Hof neu auswerten und die Aufgabenliste nur bei Aenderung neu setzen.
function FarmOverviewPage:liveAktualisieren()
    if FruchtfolgeAdvisor == nil or FruchtfolgeAdvisor.buildCache == nil
            or TaskAnalyzer == nil or TaskAnalyzer.build == nil then
        return
    end
    FruchtfolgeAdvisor.buildCache()
    TaskAnalyzer.build()
    local neu = TaskAnalyzer.getRows(self.aufgeklappteFelder) or {}
    if fingerabdruck(neu) ~= fingerabdruck(self.rows) then
        self:refreshTaskRows()
    else
        self:refreshShortageLine(self.tab)
    end
end

-- ============================================================================
-- Einbau ins ESC-Menue
-- ============================================================================

-- Position des ersten Eintrags, fuer den pruefe(eintrag) true liefert, sonst nil.
local function finde(liste, pruefe)
    for i, e in ipairs(liste or {}) do
        if pruefe(e) then
            return i
        end
    end
    return nil
end

-- Eintrag (pruefe) direkt vor den Ziel-Eintrag (ziel) schieben.
local function verschiebeVor(liste, pruefe, ziel)
    local von = finde(liste, pruefe)
    if von == nil or finde(liste, ziel) == nil then
        return
    end
    local eintrag = table.remove(liste, von)
    table.insert(liste, finde(liste, ziel), eintrag)
end

--- Seite ins ESC-Menue einhaengen.
--- Muster der laufenden Mods FS25_CropRotation (fixInGameMenu, lokal in
--- _ref_croprotation/src/UILoader.lua) und FS25_GarageMenu (addShopPage):
--- die Seite MUSS selbst als Element ins pagingElement. rebuildTabList sucht
--- jede registrierte Seite per getPageIdByElement(seite); TabbedMenu:addPage
--- traegt nur das Wurzelelement ein -> PagingElement.lua:249 "attempt to
--- index nil with 'disabled'" (so im Spiel aufgetreten, 27.09.2026).
function FarmOverviewPage.init()
    FarmOverviewPage.aktiv = true
    if FarmOverviewPage.fertig then
        return
    end
    local menu = g_inGameMenu
    if g_gui == nil or g_gui.loadGui == nil or menu == nil or menu.pagingElement == nil
            or menu.registerPage == nil or menu.addPageTab == nil then
        return
    end
    if not klasseAnlegen() then
        return
    end
    FarmOverviewPage.fertig = true

    local name   = FarmOverviewPage.NAME
    local seite  = FarmOverviewPage.new()
    local paging = menu.pagingElement

    -- loadGui stellt den FocusManager auf die neue Seite um (Gui.lua:287);
    -- danach den vorherigen Stand zurueckholen.
    local vorherigeGui = FocusManager.currentGui
    g_gui:loadGui(Utils.getFilename("gui/FarmOverviewPage.xml", modDirectory), name, seite, true)
    if vorherigeGui ~= nil and FocusManager.setGui ~= nil then
        FocusManager:setGui(vorherigeGui)
    end
    if seite.faList == nil then
        Logging.warning(FarmOverviewPage.LOG .. "Seite konnte nicht geladen werden (FarmOverviewPage.xml).")
        return
    end

    if type(menu.controlIDs) == "table" then
        menu.controlIDs[name] = nil
    end
    menu[name] = seite
    paging:addElement(seite)
    if menu.exposeControlsAsFields ~= nil then
        menu:exposeControlsAsFields(name)
    end

    -- Ganz nach vorne: erster Reiter im ESC-Menue (Elemente und Seiten des
    -- Pagings, gleiche Reihenfolge wie pageFrames unten).
    local erstes = menu.pageFrames ~= nil and menu.pageFrames[1] or nil
    if erstes ~= nil then
        verschiebeVor(paging.elements, function(e) return e == seite end,
            function(e) return e == erstes end)
        verschiebeVor(paging.pages, function(e) return e.element == seite end,
            function(e) return e.element == erstes end)
    end
    -- Seitentitel: addElement findet keinen "ui_"-Text fuer uns und setzt "".
    local nr = finde(paging.pages, function(e) return e.element == seite end)
    if nr ~= nil then
        paging.pages[nr].title = L("fa_title", "Farm Overview")
    end
    paging:updateAbsolutePosition()
    paging:updatePageMapping()

    local position = 1
    menu:registerPage(seite, position, nil)
    menu:addPageTab(seite, Utils.getFilename("images/menuIcon.dds", modDirectory),
        GuiUtils.getUVs({ 0, 0, 1024, 1024 }))
    menu:rebuildTabList()

    FarmOverviewPage.instanz = seite
    Logging.info(FarmOverviewPage.LOG .. "Bereich Finanzen: FS25_FarmEconomy %s.",
        (FinanceBridge ~= nil and FinanceBridge.isAvailable()) and "gefunden" or "nicht gefunden - Bereich ausgeblendet")
    Logging.info(FarmOverviewPage.LOG .. "Betriebsuebersicht als Seite im ESC-Menue eingefuegt (Position %s).",
        tostring(position or "Ende"))
end

--- Aus FruchtfolgeAdvisor:update: nachfassen, falls das Menue beim ersten
--- Versuch noch nicht bereit war.
function FarmOverviewPage.retry()
    if not FarmOverviewPage.aktiv or FarmOverviewPage.fertig then
        return
    end
    if FarmOverviewPage.versuche >= FarmOverviewPage.MAX_VERSUCHE then
        return
    end
    FarmOverviewPage.versuche = FarmOverviewPage.versuche + 1
    FarmOverviewPage.init()
end
