-- CropSelectionEvent.lua
-- Synchronisiert die abgewaehlten Fruechte (CropRotationData.disabledCrops)
-- zwischen Server und Clients. Die Auswahl gilt fuer den ganzen Hof, damit alle
-- Mitspieler dieselben Empfehlungen sehen.
--   hasData = true  -> Traeger enthaelt die Liste.
--                      * Server empfaengt (von Client): uebernehmen, speichern
--                        und an alle verteilen.
--                      * Client empfaengt (vom Server): autoritative Liste
--                        uebernehmen.
--   hasData = false -> Anfrage eines Clients an den Server nach der Liste.
--
-- Aufbau 1:1 nach BodengesundheitCfgEvent (Class(x, Event), emptyNew/new/
-- writeStream/readStream/run, InitEventClass). Uebertragen wird bewusst EIN
-- String ("WHEAT,MAIZE") und keine Bool-Folge je Frucht: die Liste ist kurz,
-- der Stream damit unabhaengig von der Fruchtzahl der Map, und es gibt keine
-- Reihenfolge-Falle beim Lesen.

CropSelectionEvent = {}
local CropSelectionEvent_mt = Class(CropSelectionEvent, Event)

InitEventClass(CropSelectionEvent, "CropSelectionEvent")

function CropSelectionEvent.emptyNew()
    return Event.new(CropSelectionEvent_mt)
end

--- @param hasData boolean  true = Liste mitschicken, false = nur anfragen
function CropSelectionEvent.new(hasData)
    local self = CropSelectionEvent.emptyNew()
    self.hasData = (hasData == true)
    return self
end

function CropSelectionEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.hasData)
    if self.hasData then
        local liste = ""
        if CropRotationData ~= nil and CropRotationData.serializeDisabled ~= nil then
            liste = CropRotationData.serializeDisabled() or ""
        end
        streamWriteString(streamId, liste)
    end
end

function CropSelectionEvent:readStream(streamId, connection)
    self.hasData = streamReadBool(streamId)
    if self.hasData then
        local liste = streamReadString(streamId)
        if CropRotationData ~= nil and CropRotationData.deserializeDisabled ~= nil then
            CropRotationData.deserializeDisabled(liste)
        end
        -- Empfehlungen haengen an der Fruchtliste -> Analyse neu aufbauen
        if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
            FruchtfolgeAdvisor.buildCache()
        end
    end
    self:run(connection)
end

function CropSelectionEvent:run(connection)
    -- connection:getIsServer() == true  -> Empfaenger ist ein Client
    -- connection:getIsServer() == false -> Empfaenger ist der Server
    local empfaengerIstClient = connection:getIsServer()

    if self.hasData then
        if not empfaengerIstClient then
            -- Server hat eine Aenderung erhalten -> sichern und verteilen.
            if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.saveSettings ~= nil then
                FruchtfolgeAdvisor.saveSettings()
            end
            CropSelectionEvent.broadcast()
        end
        -- Client als Empfaenger: Liste wurde bereits in readStream uebernommen.
    else
        -- Anfrage: nur der Server antwortet der anfragenden Verbindung.
        if not empfaengerIstClient and g_server ~= nil then
            connection:sendEvent(CropSelectionEvent.new(true))
        end
    end
end

-- Verbindung des Clients zum Server, oder nil, wenn es (noch) keine gibt.
local function serverConnection()
    if g_client == nil or g_client.getServerConnection == nil then return nil end
    return g_client:getServerConnection()
end

-- Server: aktuelle Auswahl an alle Clients verteilen.
function CropSelectionEvent.broadcast()
    if g_server == nil or g_server.broadcastEvent == nil then return end
    g_server:broadcastEvent(CropSelectionEvent.new(true), false)
end

-- Client: Auswahl beim Server anfragen (beim Oeffnen des Fensters).
function CropSelectionEvent.request()
    if g_server ~= nil then return end
    local verbindung = serverConnection()
    if verbindung ~= nil then
        verbindung:sendEvent(CropSelectionEvent.new(false))
    end
end

-- Lokale Aenderung melden: Server verteilt und speichert selbst, ein Client
-- schickt seinen Wunsch an den Server (der bleibt autoritativ).
function CropSelectionEvent.send()
    if g_server ~= nil then
        if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.saveSettings ~= nil then
            FruchtfolgeAdvisor.saveSettings()
        end
        CropSelectionEvent.broadcast()
    else
        local verbindung = serverConnection()
        if verbindung ~= nil then
            verbindung:sendEvent(CropSelectionEvent.new(true))
        end
    end
end
