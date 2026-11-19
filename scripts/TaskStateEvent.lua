-- TaskStateEvent.lua
-- Synchronisiert den Bearbeitungsstatus des Aufgabenzettels (TaskState).
--
--   MODE_REQUEST  Client -> Server: bitte den ganzen Stand schicken
--   MODE_FULL     Server -> Client: ganzer Stand (ersetzt den lokalen)
--   MODE_CHANGE   Client -> Server: Aenderungswunsch
--                 Server -> alle:   bestaetigte Aenderung
--
-- Wire-Format: Modus (UInt8), dann Anzahl (Int32) und je Eintrag
-- key (String), status (UInt8), who (String), day (Int32). Keine Booleans,
-- keine and/or-Kurzformen auf Werten - siehe Stream-Falle bei AOSettingsEvent.
-- Aufbau nach CropSelectionEvent (emptyNew/new/writeStream/readStream/run).

TaskStateEvent = {}
local TaskStateEvent_mt = Class(TaskStateEvent, Event)

InitEventClass(TaskStateEvent, "TaskStateEvent")

TaskStateEvent.MODE_REQUEST = 0
TaskStateEvent.MODE_FULL    = 1
TaskStateEvent.MODE_CHANGE  = 2

TaskStateEvent.MAX_ITEMS = 2000

function TaskStateEvent.emptyNew()
    return Event.new(TaskStateEvent_mt)
end

function TaskStateEvent.new(mode, items)
    local self = TaskStateEvent.emptyNew()
    self.mode  = mode or TaskStateEvent.MODE_REQUEST
    self.items = items or {}
    return self
end

function TaskStateEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.mode)
    if self.mode ~= TaskStateEvent.MODE_REQUEST then
        local n = math.min(#self.items, TaskStateEvent.MAX_ITEMS)
        streamWriteInt32(streamId, n)
        for i = 1, n do
            local it = self.items[i]
            streamWriteString(streamId, tostring(it.key or ""))
            streamWriteUInt8(streamId, it.status or 0)
            streamWriteString(streamId, tostring(it.who or ""))
            streamWriteInt32(streamId, it.day or 0)
        end
    end
end

function TaskStateEvent:readStream(streamId, connection)
    self.mode  = streamReadUInt8(streamId)
    self.items = {}
    if self.mode ~= TaskStateEvent.MODE_REQUEST then
        local n = streamReadInt32(streamId)
        for i = 1, n do
            local it = {}
            it.key    = streamReadString(streamId)
            it.status = streamReadUInt8(streamId)
            it.who    = streamReadString(streamId)
            it.day    = streamReadInt32(streamId)
            self.items[i] = it
        end
    end
    self:run(connection)
end

function TaskStateEvent:run(connection)
    -- connection:getIsServer() == true  -> Empfaenger ist ein Client
    local empfaengerIstClient = connection:getIsServer()

    if self.mode == TaskStateEvent.MODE_REQUEST then
        if not empfaengerIstClient and g_server ~= nil then
            connection:sendEvent(TaskStateEvent.new(TaskStateEvent.MODE_FULL, TaskState.allItems()))
        end
    elseif self.mode == TaskStateEvent.MODE_FULL then
        if empfaengerIstClient then
            TaskState.replaceAll(self.items)
            TaskState.notifyChanged()
        end
    elseif self.mode == TaskStateEvent.MODE_CHANGE then
        if empfaengerIstClient then
            for _, it in ipairs(self.items) do
                TaskState.apply(it.key, it.status, it.who, it.day)
            end
            TaskState.notifyChanged()
        elseif g_server ~= nil then
            -- Server: mit SEINEM Spieltag stempeln, uebernehmen, an alle verteilen
            local heute = TaskState.today()
            for _, it in ipairs(self.items) do
                it.day = heute
                TaskState.apply(it.key, it.status, it.who, heute)
            end
            TaskStateEvent.broadcastChange(self.items)
            TaskState.notifyChanged()
        end
    end
end

local function serverConnection()
    if g_client == nil or g_client.getServerConnection == nil then
        return nil
    end
    return g_client:getServerConnection()
end

--- Client: ganzen Stand beim Server anfragen (beim Oeffnen der Ansichten).
function TaskStateEvent.request()
    if g_server ~= nil then
        return
    end
    local verbindung = serverConnection()
    if verbindung ~= nil then
        verbindung:sendEvent(TaskStateEvent.new(TaskStateEvent.MODE_REQUEST))
    end
end

--- Client: Aenderungswunsch an den Server.
function TaskStateEvent.sendChange(items)
    local verbindung = serverConnection()
    if verbindung ~= nil then
        verbindung:sendEvent(TaskStateEvent.new(TaskStateEvent.MODE_CHANGE, items))
    end
end

--- Server: bestaetigte Aenderung an alle Clients.
function TaskStateEvent.broadcastChange(items)
    if g_server == nil or g_server.broadcastEvent == nil then
        return
    end
    g_server:broadcastEvent(TaskStateEvent.new(TaskStateEvent.MODE_CHANGE, items), false)
end
