-- BodengesundheitSyncEvent.lua
-- Server -> Client: uebertraegt Bodengesundheits-Zustaende (Vollstand beim Beitritt
-- oder Einzelaenderung als Broadcast) inkl. Ertragsgrenzen fuer die HUD-Anzeige.

BodengesundheitSyncEvent = {}
local BodengesundheitSyncEvent_mt = Class(BodengesundheitSyncEvent, Event)

InitEventClass(BodengesundheitSyncEvent, "BodengesundheitSyncEvent")

function BodengesundheitSyncEvent.emptyNew()
    return Event.new(BodengesundheitSyncEvent_mt)
end

-- entries: Array aus { id=farmlandId, health=zahl, lastHarvest=string, phase=string }
function BodengesundheitSyncEvent.new(entries, yieldMin, yieldMax)
    local self = BodengesundheitSyncEvent.emptyNew()
    self.entries = entries or {}
    self.yieldMin = yieldMin or 0.8
    self.yieldMax = yieldMax or 1.05
    return self
end

function BodengesundheitSyncEvent:writeStream(streamId, connection)
    streamWriteFloat32(streamId, self.yieldMin)
    streamWriteFloat32(streamId, self.yieldMax)

    local n = #self.entries
    streamWriteUInt16(streamId, n)
    for i = 1, n do
        local e = self.entries[i]
        streamWriteInt32(streamId, e.id)
        streamWriteFloat32(streamId, e.health)
        streamWriteString(streamId, e.lastHarvest or "")
        streamWriteString(streamId, e.phase or "")
    end
end

function BodengesundheitSyncEvent:readStream(streamId, connection)
    self.yieldMin = streamReadFloat32(streamId)
    self.yieldMax = streamReadFloat32(streamId)

    local n = streamReadUInt16(streamId)
    self.entries = {}
    for i = 1, n do
        local e = {}
        e.id = streamReadInt32(streamId)
        e.health = streamReadFloat32(streamId)
        e.lastHarvest = streamReadString(streamId)
        e.phase = streamReadString(streamId)
        self.entries[i] = e
    end

    self:run(connection)
end

function BodengesundheitSyncEvent:run(connection)
    -- Laeuft auf dem CLIENT (vom Server empfangen).
    if Bodengesundheit ~= nil and Bodengesundheit.applySync ~= nil then
        Bodengesundheit.applySync(self.entries, self.yieldMin, self.yieldMax)
    end
end
