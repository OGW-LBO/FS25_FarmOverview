-- FruitMemoryEvent.lua
-- Verteilt das Frucht-Gedaechtnis des Servers (FieldAnalyzer.fruitMemory) an die
-- Clients. Das Gedaechtnis haelt je Feld die letzte wirklich gesehene Frucht und
-- dient als VORFRUCHT, sobald ein Feld abgeerntet oder bearbeitet ist.
--
-- Warum ueberhaupt: Die Vorfrucht geht mit bis zu einem Viertel in die
-- Fruchtfolge-Bewertung ein. Bisher sammelte jeder Rechner sein Gedaechtnis
-- selbst (modSettings-Datei) - wer spaeter dazukam, hatte fuer dasselbe Feld
-- keine oder eine andere Vorfrucht und sah deshalb eine ANDERE Empfehlung als
-- die Mitspieler ("Feld 124: Sommerweizen" vs. "Mais"). Jetzt ist der Server
-- die Quelle; sein Stand gilt fuer alle.
--
-- Uebertragen wird in Stuecken: der serialisierte String kann bei Karten mit
-- vielen Feldern mehrere Kilobyte lang werden, und fuer die Laenge eines
-- einzelnen Netzwerk-Strings gibt es keine dokumentierte Zusage. Jedes Stueck
-- traegt deshalb zwei Markierungen: erstes Stueck (Client leert sein
-- Gedaechtnis) und letztes Stueck (Client uebernimmt und rechnet neu).
--
-- Aufbau wie CropSelectionEvent (Class(x, Event), emptyNew/new/writeStream/
-- readStream/run, InitEventClass).

FruitMemoryEvent = {}
local FruitMemoryEvent_mt = Class(FruitMemoryEvent, Event)

InitEventClass(FruitMemoryEvent, "FruitMemoryEvent")

-- Zeichen je Stueck. Bewusst klein gehalten; mehr Stuecke kosten nur ein paar
-- Bytes Kopf, ein zu langer String waere dagegen ein Risiko.
FruitMemoryEvent.STUECK_ZEICHEN = 800

function FruitMemoryEvent.emptyNew()
    return Event.new(FruitMemoryEvent_mt)
end

--- @param text string|nil   Teilstueck des Gedaechtnis-Strings (nil = Anfrage)
--- @param erstes boolean    true = Client leert sein Gedaechtnis vorher
--- @param letztes boolean   true = Client uebernimmt nach diesem Stueck
function FruitMemoryEvent.new(text, erstes, letztes)
    local self = FruitMemoryEvent.emptyNew()
    self.hasData = (text ~= nil)
    self.text    = text or ""
    self.erstes  = (erstes == true)
    self.letztes = (letztes == true)
    return self
end

function FruitMemoryEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.hasData)
    if self.hasData then
        streamWriteBool(streamId, self.erstes)
        streamWriteBool(streamId, self.letztes)
        streamWriteString(streamId, self.text)
    end
end

function FruitMemoryEvent:readStream(streamId, connection)
    self.hasData = streamReadBool(streamId)
    if self.hasData then
        self.erstes  = streamReadBool(streamId)
        self.letztes = streamReadBool(streamId)
        self.text    = streamReadString(streamId)
        if FieldAnalyzer ~= nil and FieldAnalyzer.applyRemoteMemory ~= nil then
            FieldAnalyzer.applyRemoteMemory(self.text, self.erstes, self.letztes)
        end
    end
    self:run(connection)
end

function FruitMemoryEvent:run(connection)
    -- connection:getIsServer() == true  -> Empfaenger ist ein Client
    -- connection:getIsServer() == false -> Empfaenger ist der Server
    local empfaengerIstClient = connection:getIsServer()
    if not self.hasData and not empfaengerIstClient and g_server ~= nil then
        -- Anfrage eines Clients: nur ihm antworten.
        FruitMemoryEvent.sendTo(connection)
    end
end

-- Verbindung des Clients zum Server, oder nil, wenn es (noch) keine gibt.
local function serverConnection()
    if g_client == nil or g_client.getServerConnection == nil then return nil end
    return g_client:getServerConnection()
end

-- Server: eigenes Gedaechtnis in Stuecken an EINE Verbindung schicken.
-- Getrennt wird an einem Semikolon, damit kein Eintrag zerschnitten wird.
function FruitMemoryEvent.sendTo(connection)
    if connection == nil or connection.sendEvent == nil then return end
    if FieldAnalyzer == nil or FieldAnalyzer.serializeFruitMemory == nil then return end
    local text = FieldAnalyzer.serializeFruitMemory() or ""
    local grenze = FruitMemoryEvent.STUECK_ZEICHEN
    local stuecke = {}
    while #text > grenze do
        -- letztes Semikolon innerhalb der Grenze suchen
        local schnitt = nil
        for i = grenze, 1, -1 do
            if string.sub(text, i, i) == ";" then schnitt = i break end
        end
        if schnitt == nil then schnitt = grenze end
        stuecke[#stuecke + 1] = string.sub(text, 1, schnitt)
        text = string.sub(text, schnitt + 1)
    end
    stuecke[#stuecke + 1] = text

    for i, stueck in ipairs(stuecke) do
        connection:sendEvent(FruitMemoryEvent.new(stueck, i == 1, i == #stuecke))
    end
end

-- Kein Broadcast: Der Client fragt selbst (kurz nach dem Beitreten und bei
-- jedem Oeffnen der Seite). Die Liste der Client-Verbindungen am g_server ist
-- im SDK-Auszug nicht belegt, und laufend verteilen muss man das Gedaechtnis
-- nicht - es aendert sich nur bei Ernte und Aussaat, und die aktuell wachsende
-- Frucht liest jeder Rechner ohnehin selbst von der Karte.

-- Client: Gedaechtnis beim Server anfragen.
function FruitMemoryEvent.request()
    if g_server ~= nil then return end
    local verbindung = serverConnection()
    if verbindung ~= nil then
        verbindung:sendEvent(FruitMemoryEvent.new(nil, false, false))
    end
end
