-- TaskState.lua
-- Bearbeitungsstatus des Aufgabenzettels: wer hat eine Aufgabe uebernommen. Der Server haelt den Stand fuer alle Farmen, speichert ihn
-- mit dem Spielstand (fruchtfolgeAdvisor.xml, Knoten "aufgaben") und verteilt
-- jede Aenderung an alle Clients (TaskStateEvent).
--
-- Eintrag: entries[key] = { status = 1 (uebernommen), who, day }
-- day ist environment.currentMonotonicDay zum Zeitpunkt der Aenderung.
--
-- Grundregel: OB eine Aufgabe besteht, entscheidet allein der Spielzustand.
-- Ist die Arbeit getan (Feld geerntet, Trog gefuellt, Silo geleert), erzeugt
-- TaskAnalyzer die Aufgabe nicht mehr - sie verschwindet von selbst. Ein
-- Status kann eine erledigte Arbeit also nie zurueckholen.
-- Der einzige Status ist "uebernommen": jemand kuemmert sich, sein Name
-- steht bei allen Mitspielern dabei. Ein Klick schaltet offen <-> uebernommen.
-- Verschwindet der Anlass, raeumt cleanup() den Status weg - es wird nichts
-- gesammelt. Tritt derselbe
-- Anlass spaeter neu auf (naechste Ernte), beginnt die Aufgabe wieder offen.
-- Beim Speichern verwirft der Server zusaetzlich Eintraege, die aelter als
-- KEEP_DAYS sind (z. B. von Hoefen, deren Spieler nie mehr hineinschauen).

TaskState = {}

TaskState.STATUS_OPEN  = 0
TaskState.STATUS_TAKEN = 1
-- 2 war frueher "ausgeblendet"; alte Eintraege im Spielstand zaehlen als offen.
TaskState.STATUS_OLD_HIDDEN = 2

TaskState.KEEP_DAYS  = 30

TaskState.entries   = {}
TaskState.listeners = {}

function TaskState.today()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env ~= nil and type(env.currentMonotonicDay) == "number" then
        return env.currentMonotonicDay
    end
    return 0
end

--- Name des lokalen Spielers fuer "uebernommen von".
function TaskState.localName()
    if g_localPlayer ~= nil and g_localPlayer.getNickname ~= nil then
        local n = g_localPlayer:getNickname()
        if type(n) == "string" and n ~= "" then
            return n
        end
    end
    if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.L ~= nil then
        return FruchtfolgeAdvisor.L("fa_task_me", "me")
    end
    return "me"
end

--- Wirksamer Status einer Aufgabe: "open" | "taken", Name.
function TaskState.getEffective(key)
    local e = TaskState.entries[key]
    if e == nil then
        return "open", ""
    end
    if e.status == TaskState.STATUS_TAKEN then
        return "taken", e.who or ""
    end
    return "open", ""
end

--- Einen Eintrag setzen (lokal, ohne Netzwerk).
function TaskState.apply(key, status, who, day)
    if type(key) ~= "string" or key == "" then
        return
    end
    if status == TaskState.STATUS_TAKEN then
        TaskState.entries[key] = { status = status, who = who or "", day = day or TaskState.today() }
    else
        TaskState.entries[key] = nil
    end
end

--- Alle Eintraege als Liste (fuer Voll-Sync und Speichern).
function TaskState.allItems()
    local liste = {}
    for key, e in pairs(TaskState.entries) do
        liste[#liste + 1] = { key = key, status = e.status, who = e.who or "", day = e.day or 0 }
    end
    return liste
end

function TaskState.replaceAll(items)
    TaskState.entries = {}
    for _, it in ipairs(items or {}) do
        TaskState.apply(it.key, it.status, it.who, it.day)
    end
end

-- ── Aenderungen melden ────────────────────────────────────────
function TaskState.addListener(fn)
    if type(fn) == "function" then
        table.insert(TaskState.listeners, fn)
    end
end

function TaskState.notifyChanged()
    for _, fn in ipairs(TaskState.listeners) do
        fn()
    end
end

--- Klick auf eine Aufgabe: offen <-> uebernommen (ich).
function TaskState.cycle(key)
    local st = TaskState.getEffective(key)
    local neu = TaskState.STATUS_TAKEN
    if st == "taken" then
        neu = TaskState.STATUS_OPEN
    end
    TaskState.request(key, neu, TaskState.localName())
end

--- Aenderung ausfuehren: der Server setzt und verteilt selbst, ein Client
--- schickt den Wunsch an den Server (der bleibt autoritativ).
function TaskState.request(key, status, who)
    if g_server ~= nil then
        TaskState.apply(key, status, who, TaskState.today())
        if TaskStateEvent ~= nil and TaskStateEvent.broadcastChange ~= nil then
            TaskStateEvent.broadcastChange({ { key = key, status = status, who = who or "", day = TaskState.today() } })
        end
        TaskState.notifyChanged()
    elseif TaskStateEvent ~= nil and TaskStateEvent.sendChange ~= nil then
        -- Sofort lokal anzeigen; die Bestaetigung des Servers ueberschreibt es.
        TaskState.apply(key, status, who, TaskState.today())
        TaskStateEvent.sendChange({ { key = key, status = status, who = who or "", day = 0 } })
        TaskState.notifyChanged()
    end
end

--- Status von Aufgaben entfernen, deren Anlass nicht mehr besteht.
--- aufgaben = aktuelle Liste aus TaskAnalyzer.build(), farmId = eigener Hof.
--- Nur Schluessel des eigenen Hofes werden geprueft (Praefix "<farmId>:").
function TaskState.cleanup(aufgaben, farmId)
    local aktuell = {}
    for _, t in ipairs(aufgaben or {}) do
        aktuell[t.key] = true
    end
    local praefix = tostring(farmId) .. ":"
    local weg = {}
    for key, _ in pairs(TaskState.entries) do
        if string.sub(key, 1, #praefix) == praefix and not aktuell[key] then
            weg[#weg + 1] = { key = key, status = TaskState.STATUS_OPEN, who = "", day = 0 }
        end
    end
    if #weg == 0 then
        return
    end
    for _, it in ipairs(weg) do
        TaskState.entries[it.key] = nil
    end
    if g_server ~= nil then
        if TaskStateEvent ~= nil and TaskStateEvent.broadcastChange ~= nil then
            TaskStateEvent.broadcastChange(weg)
        end
    elseif TaskStateEvent ~= nil and TaskStateEvent.sendChange ~= nil then
        TaskStateEvent.sendChange(weg)
    end
end

-- ── Speichern / Laden (nur Server) ────────────────────────────
function TaskState.writeToXML(xml, base)
    local heute = TaskState.today()
    local i = 0
    for key, e in pairs(TaskState.entries) do
        if heute - (e.day or 0) <= TaskState.KEEP_DAYS then
            local pfad = string.format("%s.task(%d)", base, i)
            setXMLString(xml, pfad .. "#key", key)
            setXMLInt(xml, pfad .. "#status", e.status or 0)
            setXMLString(xml, pfad .. "#who", e.who or "")
            setXMLInt(xml, pfad .. "#day", e.day or 0)
            i = i + 1
        end
    end
end

function TaskState.readFromXML(xml, base)
    TaskState.entries = {}
    local i = 0
    while true do
        local pfad = string.format("%s.task(%d)", base, i)
        if not hasXMLProperty(xml, pfad .. "#key") then
            break
        end
        TaskState.apply(getXMLString(xml, pfad .. "#key"),
            getXMLInt(xml, pfad .. "#status") or 0,
            getXMLString(xml, pfad .. "#who") or "",
            getXMLInt(xml, pfad .. "#day") or 0)
        i = i + 1
    end
end
