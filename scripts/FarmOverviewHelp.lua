-- FarmOverviewHelp.lua
-- Fuegt der ESC-Menue-Hilfe (Reiter "Hilfe") eine eigene Kategorie mit Seiten
-- hinzu - genau wie das Basisspiel. Die Inhalte stehen in gui/helpLine.xml
-- (Struktur nach shared/xml/schema/helpLine.xsd verifiziert).
--
-- Mechanik: Das Basisspiel laedt die Hilfe ueber HelpLineManager:loadMapData
-- (dort wird die Karten-Hilfe $dataS/helpLine.xml eingelesen). Wir haengen uns
-- an diese Funktion an und laden zusaetzlich unsere Datei per :loadFromXML.
--
-- Defensiv: Fehlt oder aendert sich die HelpLineManager-API, passiert nichts
-- ausser einer Log-Meldung - die Hilfe-Seite fehlt dann einfach, das Spiel
-- crasht nie (Skill-Regel: im Zweifel nichts tun statt abstuerzen).

FarmOverviewHelp = {}

local modDir = g_currentModDirectory
FarmOverviewHelp.xmlPath = modDir .. "gui/helpLine.xml"
FarmOverviewHelp.loaded = false

-- Unsere Hilfe-XML in den HelpLineManager laden.
function FarmOverviewHelp.load(helpLineManager)
    if FarmOverviewHelp.loaded then return end
    if helpLineManager == nil or helpLineManager.loadFromXML == nil then
        Logging.info("[FarmOverview] HelpLineManager.loadFromXML nicht vorhanden - Hilfe uebersprungen.")
        return
    end
    if fileExists ~= nil and not fileExists(FarmOverviewHelp.xmlPath) then
        Logging.warning("[FarmOverview] Hilfe-XML fehlt: %s", tostring(FarmOverviewHelp.xmlPath))
        return
    end

    -- Signatur (stabil seit FS19): loadFromXML(xmlFilename, baseDirectory, customEnvironment)
    -- customEnvironment = nil -> $l10n_-Schluessel werden global aufgeloest
    -- (unsere modDesc-Texte sind global erreichbar, wie im Dialog bewiesen).
    -- Methode und Datei sind oben geprueft; ein Fehler darin soll im Log landen.
    helpLineManager:loadFromXML(FarmOverviewHelp.xmlPath, modDir, nil)
    FarmOverviewHelp.loaded = true
    Logging.info("[FarmOverview] Hilfe-Seiten in die ESC-Menue-Hilfe geladen.")
end

-- Hook auf Datei-Ebene installieren: Die Map-Hilfe wird erst spaeter (beim
-- Missions-Laden) eingelesen, unsere extraSourceFiles laufen davor - der Anhang
-- greift also rechtzeitig.
if HelpLineManager ~= nil and HelpLineManager.loadMapData ~= nil
        and Utils ~= nil and Utils.appendedFunction ~= nil then
    HelpLineManager.loadMapData = Utils.appendedFunction(HelpLineManager.loadMapData,
        function(self, ...)
            FarmOverviewHelp.load(self)
        end)
else
    Logging.info("[FarmOverview] HelpLineManager.loadMapData nicht verfuegbar - Hilfe-Hook nicht gesetzt.")
end
