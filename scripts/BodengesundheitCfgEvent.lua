-- BodengesundheitCfgEvent.lua
-- Synchronisiert Bodengesundheit.cfg (die Einstellungen) zwischen Server und Clients.
--   hasData = true  -> Traeger enthaelt alle Einstellungswerte.
--                      * Server empfaengt (von Client): Vorschlag uebernehmen,
--                        speichern und an alle verteilen.
--                      * Client empfaengt (vom Server): autoritative Werte
--                        uebernehmen.
--   hasData = false -> Anfrage eines Clients an den Server nach den Werten.
--
-- Aufbau 1:1 nach dem verifizierten Muster von HelferLohnSettingsEvent
-- (Class(x, Event), emptyNew/new/writeStream/readStream/run, InitEventClass).
-- Der eigentliche Stream-Aufbau liegt in Bodengesundheit.writeCfgStream/readCfgStream
-- (eine Stelle, damit Schreib- und Lese-Reihenfolge garantiert identisch sind).

BodengesundheitCfgEvent = {}
local BodengesundheitCfgEvent_mt = Class(BodengesundheitCfgEvent, Event)

InitEventClass(BodengesundheitCfgEvent, "BodengesundheitCfgEvent")

function BodengesundheitCfgEvent.emptyNew()
    return Event.new(BodengesundheitCfgEvent_mt)
end

--- @param hasData boolean  true = Werte mitschicken, false = nur anfragen
function BodengesundheitCfgEvent.new(hasData)
    local self = BodengesundheitCfgEvent.emptyNew()
    self.hasData = (hasData == true)
    return self
end

function BodengesundheitCfgEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.hasData)
    if self.hasData then
        if Bodengesundheit ~= nil and Bodengesundheit.writeCfgStream ~= nil then
            Bodengesundheit.writeCfgStream(streamId)
        end
    end
end

function BodengesundheitCfgEvent:readStream(streamId, connection)
    self.hasData = streamReadBool(streamId)
    if self.hasData then
        if Bodengesundheit ~= nil and Bodengesundheit.readCfgStream ~= nil then
            Bodengesundheit.readCfgStream(streamId)
        end
    end
    self:run(connection)
end

function BodengesundheitCfgEvent:run(connection)
    -- connection:getIsServer() == true  -> Empfaenger ist ein Client
    -- connection:getIsServer() == false -> Empfaenger ist der Server
    local empfaengerIstClient = connection:getIsServer()

    if self.hasData then
        if not empfaengerIstClient then
            -- Server hat einen Aenderungsvorschlag erhalten -> sichern und verteilen.
            if Bodengesundheit ~= nil then
                if Bodengesundheit.saveCfg ~= nil then Bodengesundheit.saveCfg() end
                if Bodengesundheit.broadcastCfg ~= nil then Bodengesundheit.broadcastCfg() end
            end
        end
        -- Client als Empfaenger: cfg wurde bereits in readStream uebernommen.
    else
        -- Anfrage: nur der Server antwortet der anfragenden Verbindung.
        if not empfaengerIstClient and g_server ~= nil then
            connection:sendEvent(BodengesundheitCfgEvent.new(true))
        end
    end
end
