-- BodengesundheitRequestEvent.lua
-- Client -> Server: fordert beim Laden einmalig den kompletten Zustand an.
-- Der Server antwortet der anfragenden Verbindung mit einem BodengesundheitSyncEvent.

BodengesundheitRequestEvent = {}
local BodengesundheitRequestEvent_mt = Class(BodengesundheitRequestEvent, Event)

InitEventClass(BodengesundheitRequestEvent, "BodengesundheitRequestEvent")

function BodengesundheitRequestEvent.emptyNew()
    return Event.new(BodengesundheitRequestEvent_mt)
end

function BodengesundheitRequestEvent.new()
    return BodengesundheitRequestEvent.emptyNew()
end

function BodengesundheitRequestEvent:writeStream(streamId, connection)
    -- keine Nutzdaten
end

function BodengesundheitRequestEvent:readStream(streamId, connection)
    self:run(connection)
end

function BodengesundheitRequestEvent:run(connection)
    -- Laeuft auf dem SERVER: Vollstand an die anfragende Verbindung zuruecksenden.
    if g_server ~= nil and Bodengesundheit ~= nil and Bodengesundheit.buildFullEntries ~= nil then
        local entries = Bodengesundheit.buildFullEntries()
        connection:sendEvent(BodengesundheitSyncEvent.new(entries, Bodengesundheit.cfg.yieldMin, Bodengesundheit.cfg.yieldMax))
    end
end
