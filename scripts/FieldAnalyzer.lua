-- FieldAnalyzer.lua
-- Bestaeitigte APIs (FS25_CropRotation Referenz):
--   field:getFieldState()                    -> {fruitTypeIndex=int, ...}
--   field:getCenterOfFieldWorldPosition()    -> x, z
--   g_fieldManager:getFields()               -> table (key=feldnr, value=field)
--   g_fruitTypeManager:getFruitTypeByIndex() -> fruitType
--   field.posX, field.posZ, field.areaHa    -> bestaetigt per debugDump
--   field.farmland                           -> Farmland-Objekt (Tabelle, nicht im Flat-Dump)
FieldAnalyzer = {}

-- Frucht-Gedaechtnis: Feld-ID -> letzte real gesehene Frucht.
-- Grund: Nach Grubbern/Pfluegen/Bodenbearbeitung loescht das Spiel den
-- Frucht-Layer. Ohne Gedaechtnis wuerde das Feld als "Brache" gelten und
-- die Vorfrucht fuer die Rotations-Empfehlung verloren gehen.
-- Wird ueber fruchtfolgeAdvisor.xml im Savegame persistiert.
FieldAnalyzer.fruitMemory  = {}
FieldAnalyzer.memoryLoaded = false
FieldAnalyzer.memoryDirty  = false

-- Eigenen modSettings-Ordner beim PARSEN dieses Scripts festhalten.
-- WICHTIG: g_currentModSettingsDirectory zeigt nur waehrend des Ladens
-- dieses Mods auf den eigenen Ordner. Zur Laufzeit (Mission-Load, Speichern)
-- steht die Globale laengst auf dem zuletzt geladenen Mod (z.B. Wardrobe) —
-- dadurch landete die Datei frueher im FREMDEN modSettings-Ordner.
FieldAnalyzer.MOD_NAME            = g_currentModName
FieldAnalyzer.OWN_MODSETTINGS_DIR = g_currentModSettingsDirectory

-- Gedaechtnis -> String "12=WHEAT;7=MAIZE" (fuer Savegame-XML)
function FieldAnalyzer.serializeFruitMemory()
    -- Gespeichert wird immer mit Kennung "fieldId": alte Schluessel also vorher
    -- umrechnen (Dedi-Server ruft getOwnFields evtl. nie auf).
    if FieldAnalyzer.memoryKeysAreIndex and g_fieldManager ~= nil and g_fieldManager.getFields ~= nil then
        local fields = g_fieldManager:getFields()
        if fields ~= nil and next(fields) ~= nil then FieldAnalyzer.migrateMemoryKeys(fields) end
    end
    local parts = {}
    for fid, fruit in pairs(FieldAnalyzer.fruitMemory) do
        table.insert(parts, tostring(fid) .. "=" .. tostring(fruit))
    end
    table.sort(parts)
    return table.concat(parts, ";")
end

function FieldAnalyzer.deserializeFruitMemory(s)
    if type(s) ~= "string" or s == "" then return end
    for fid, fruit in string.gmatch(s, "([^=;]+)=([^=;]+)") do
        FieldAnalyzer.fruitMemory[fid] = fruit
    end
end

-- Client-lokale Persistenz in modSettings (Muster wie NachbarFelder
-- Client-Prefs: eigener modSettings-Ordner + createFolder + XML).
-- Grund: Die Savegame-Persistenz laeuft nur auf dem Server — auf
-- MP-Clients ging das Gedaechtnis sonst bei jedem Neustart verloren
-- und bearbeitete Felder fielen auf "Brache" zurueck.
local function currentMapKey()
    local mapKey = "default"
    local mi = nil
    if g_currentMission ~= nil then mi = g_currentMission.missionInfo end
    if mi ~= nil then
        local raw = mi.mapId or mi.mapTitle
        if raw ~= nil and raw ~= "" then
            mapKey = string.gsub(tostring(raw), "[^%w_-]", "_")
        end
    end
    return mapKey
end

-- Stabiler, mod-eigener modSettings-Ordner (endet auf "/").
local function ownSettingsDir()
    local dir = FieldAnalyzer.OWN_MODSETTINGS_DIR
    if (dir == nil or dir == "") and getUserProfileAppPath ~= nil then
        local modName = FieldAnalyzer.MOD_NAME or "FS25_FruchtfolgeAdvisor"
        dir = getUserProfileAppPath() .. "modSettings/" .. modName .. "/"
    end
    return dir
end

local function memoryFilePath()
    local dir = ownSettingsDir()
    if dir == nil then return nil end
    return dir .. "fruitMemory_" .. currentMapKey() .. ".xml"
end

-- Frueherer (fehlerhafter) Speicherort: die volatile Globale zeigte zur
-- Laufzeit auf den zuletzt geladenen Mod. Nur fuer die einmalige Migration.
local function legacyMemoryFilePath()
    if g_currentModSettingsDirectory == nil then return nil end
    return g_currentModSettingsDirectory .. "fruitMemory_" .. currentMapKey() .. ".xml"
end

function FieldAnalyzer.loadFruitMemoryLocal()
    if FieldAnalyzer.memoryLoaded then return end
    FieldAnalyzer.memoryLoaded = true
    local path = memoryFilePath()
    if path == nil then return end
    local loadPath = path
    local migrated = false
    if not fileExists(path) then
        -- Migration: alte Datei aus fremdem modSettings-Ordner uebernehmen
        local legacy = legacyMemoryFilePath()
        if legacy ~= nil and legacy ~= path and fileExists(legacy) then
            loadPath = legacy
            migrated = true
        else
            return
        end
    end
    local xf = loadXMLFile("faMem", loadPath)
    if xf == nil or xf == 0 then return end
    local s = getXMLString(xf, "faFruitMemory.data")
    local keys = getXMLString(xf, "faFruitMemory#keys")
    delete(xf)
    FieldAnalyzer.deserializeFruitMemory(s)
    -- Aeltere Dateien sind nach der Listenposition geschluesselt, nicht nach der
    -- Feldnummer; migrateMemoryKeys() rechnet sie beim ersten Feldabruf um.
    FieldAnalyzer.markMemoryKeys(s, keys)
    print("[FA] Frucht-Gedaechtnis geladen: " .. tostring(loadPath))
    if migrated then
        FieldAnalyzer.memoryDirty = true
        FieldAnalyzer.saveFruitMemoryLocal()
        print("[FA] Frucht-Gedaechtnis in eigenen Ordner migriert: " .. tostring(path))
    end
end

function FieldAnalyzer.saveFruitMemoryLocal()
    local path = memoryFilePath()
    if path == nil then return end
    local dir = ownSettingsDir()
    if createFolder ~= nil and dir ~= nil then
        createFolder(dir)
    end
    local xf = createXMLFile("faMem", path, "faFruitMemory")
    if xf == nil or xf == 0 then return end
    setXMLString(xf, "faFruitMemory#keys", "fieldId")
    setXMLString(xf, "faFruitMemory.data", FieldAnalyzer.serializeFruitMemory())
    saveXMLFile(xf)
    delete(xf)
end

-- MP-sichere Farm-ID des lokalen Spielers.
-- g_localPlayer ist im Multiplayer der verlaesslichste Weg
-- (Referenz: FS25_CropRotation nutzt g_localPlayer.farmId).
function FieldAnalyzer.getLocalFarmId()
    if g_localPlayer ~= nil then
        local fid = g_localPlayer.farmId
        if type(fid) == "number" and fid > 0 then return fid end
    end
    if g_currentMission ~= nil then
        if g_currentMission.getFarmId ~= nil then
            local fid = g_currentMission:getFarmId()
            if type(fid) == "number" and fid > 0 then return fid end
        end
        if g_currentMission.player ~= nil then
            local fid = g_currentMission.player.farmId
            if type(fid) == "number" and fid > 0 then return fid end
        end
    end
    if g_farmManager ~= nil then
        local fid = g_farmManager.localFarmId
        if type(fid) == "number" and fid > 0 then return fid end
    end
    return 1
end

function FieldAnalyzer.normalizeFruitName(fruitTypeDesc)
    if fruitTypeDesc == nil then return nil end
    local name = fruitTypeDesc.name or fruitTypeDesc
    if type(name) ~= "string" then return nil end
    return string.upper(name)
end

-- Aktuelle Frucht eines Felds — Vier-Stufen-Kette fuer SP, Host und MP-Client:
--   1. field:getFieldState().fruitTypeIndex (bestaetigt, Server/SP)
--   2. field.fieldState als Property
--   3. DensityMap am Feldmittelpunkt (MP-Client: Terrain ist immer synchron;
--      FSDensityMapUtil ist nicht in der LUADOC -> nur bei Existenz aufrufen)
--   4. field.plannedFruitTypeIndex
local function fruitNameByIndex(idx)
    if type(idx) ~= "number" or idx <= 0 then return nil end
    if g_fruitTypeManager == nil or g_fruitTypeManager.getFruitTypeByIndex == nil then
        return nil
    end
    local desc = g_fruitTypeManager:getFruitTypeByIndex(idx)
    if desc == nil then return nil end
    return FieldAnalyzer.normalizeFruitName(desc)
end

-- Feldmittelpunkt in Weltkoordinaten, oder nil, wenn das Feld ihn nicht liefert.
local function fieldCenter(field)
    if field == nil or field.getCenterOfFieldWorldPosition == nil then return nil end
    return field:getCenterOfFieldWorldPosition()
end

function FieldAnalyzer.getCurrentFruit(field)
    if field == nil then return nil end
    local result = nil

    -- Pfad 1: getFieldState()
    if field.getFieldState ~= nil then
        local state = field:getFieldState()
        if state ~= nil then
            result = fruitNameByIndex(state.fruitTypeIndex)
        end
    end
    if result ~= nil then return result end

    -- Pfad 2: fieldState-Property direkt
    local state = field.fieldState
    if type(state) == "table" then
        result = fruitNameByIndex(state.fruitTypeIndex)
    end
    if result ~= nil then return result end

    -- Pfad 3: DensityMap am Feldmittelpunkt (funktioniert auf MP-Clients)
    if FSDensityMapUtil ~= nil and FSDensityMapUtil.getFruitTypeIndexAtWorldPos ~= nil then
        local x, z = fieldCenter(field)
        if x ~= nil and z ~= nil then
            result = fruitNameByIndex(FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z))
        end
    end
    if result ~= nil then return result end

    -- Pfad 4: geplante Frucht
    result = fruitNameByIndex(field.plannedFruitTypeIndex)
    return result
end

-- Vorherige Frucht nur verfuegbar wenn FS25_CropRotation installiert ist.
-- Bestaetigt: getCenterOfFieldWorldPosition() (HistoryStateManager.lua:158)
function FieldAnalyzer.getPreviousFruit(field)
    if g_cropRotation == nil then return nil end
    local hsm = g_cropRotation.historyStateManager
    if hsm == nil or type(hsm.historyStates) ~= "table" or #hsm.historyStates == 0 then
        return nil
    end
    local map = hsm.historyStates[1].map
    if map == nil or map.getStateAtPos == nil then return nil end
    local x, z = fieldCenter(field)
    if x == nil or z == nil then return nil end
    local fruitIdx = map:getStateAtPos(x, z)
    if type(fruitIdx) == "number" and fruitIdx > 0 then
        return fruitNameByIndex(fruitIdx)
    end
    return nil
end

-- Feldnummer wie im Spiel (Karte, Auftraege, Feldkauf): field:getId(), also die
-- Farmland-ID. NICHT die Position in g_fieldManager:getFields() - die weicht auf
-- Karten mit mehr Farmlands als Feldern ab (Bergisch Land: Position 8 = Feld 10).
function FieldAnalyzer.getFieldNumber(field, fallback)
    if field ~= nil then
        if field.getId ~= nil then
            local id = field:getId()
            if id ~= nil then return id end
        end
        if field.farmland ~= nil and field.farmland.id ~= nil then
            return field.farmland.id
        end
    end
    return fallback
end

-- Eigentuemercheck: mehrere Pfade, da field.farmlandId per debugDump nil ist.
-- Primaer: g_farmlandManager:getFarmlandOwner(field.farmland.id) - die Tabelle,
-- die das Spiel selbst beim Kauf/Verkauf pflegt (FarmlandManager.farmlandMapping).
-- Danach: field.farmland.farmId, field.farmlandId -> g_farmlandManager:getFarmlandById()
function FieldAnalyzer.isOwnField(field, farmId)
    if farmId == nil then return false end

    -- Pfad 0: Besitzer-Tabelle des Spiels, dann Besitzer am Feldmittelpunkt
    local fm = g_farmlandManager
    if fm ~= nil and fm.getFarmlandOwner ~= nil then
        if field.farmland ~= nil and field.farmland.id ~= nil then
            return fm:getFarmlandOwner(field.farmland.id) == farmId
        end
        if fm.getOwnerIdAtWorldPosition ~= nil then
            local x, z = fieldCenter(field)
            if x ~= nil and z ~= nil then
                return fm:getOwnerIdAtWorldPosition(x, z) == farmId
            end
        end
    end

    -- Pfad 1: field.farmId direkt (waere im Dump sichtbar gewesen; nil laut Dump)
    if field.farmId ~= nil and field.farmId == farmId then return true end

    -- Pfad 2: field.farmland als Tabellen-Referenz auf das Farmland-Objekt
    if field.farmland ~= nil then
        if field.farmland.farmId == farmId then return true end
        if field.farmland.ownerFarmId == farmId then return true end
    end

    -- Pfad 3: field.farmlandId -> g_farmlandManager
    local farmlandId = field.farmlandId
    if farmlandId ~= nil and g_farmlandManager ~= nil then
        local land = g_farmlandManager:getFarmlandById(farmlandId)
        if land ~= nil then
            if land.farmId == farmId then return true end
            if land.ownerFarmId == farmId then return true end
        end
    end

    -- Pfad 4: Farmland-Manager gesamt iterieren
    if g_farmlandManager ~= nil and g_farmlandManager.farmlands ~= nil then
        for _, land in pairs(g_farmlandManager.farmlands) do
            if land ~= nil and (land.farmId == farmId or land.ownerFarmId == farmId) then
                -- Pruefe ob dieses Farmland das Feld enthaelt
                local lFieldId = land.fieldId or land.firstFieldId
                if lFieldId ~= nil then
                    local fid = field.fieldId or field.id
                    if fid ~= nil and lFieldId == fid then return true end
                end
            end
        end
    end

    return false
end

-- Gedaechtnis des SERVERS uebernehmen (FruitMemoryEvent, stueckweise).
-- Der Server ist die Quelle: die Vorfrucht geht in die Fruchtfolge-Bewertung
-- ein, und ein lokal gesammeltes Gedaechtnis fuehrte bei Mitspielern zu
-- ABWEICHENDEN Empfehlungen fuer dasselbe Feld.
function FieldAnalyzer.applyRemoteMemory(text, erstes, letztes)
    if erstes then
        FieldAnalyzer.fruitMemory      = {}
        FieldAnalyzer.memoryLoaded     = true
        FieldAnalyzer.memoryKeysAreIndex = false
    end
    FieldAnalyzer.deserializeFruitMemory(text)
    if letztes then
        -- lokal sichern, damit der Stand auch nach einem Neustart sofort da ist
        FieldAnalyzer.memoryDirty = false
        FieldAnalyzer.saveFruitMemoryLocal()
        -- Empfehlungen haengen an der Vorfrucht -> Analyse neu aufbauen
        if FruchtfolgeAdvisor ~= nil and FruchtfolgeAdvisor.buildCache ~= nil then
            FruchtfolgeAdvisor.buildCache()
        end
    end
end

-- Gedaechtnis-Quelle (modSettings-Datei oder Spielstand) ohne Kennung "fieldId"
-- stammt aus einer Version, die nach Listenposition geschluesselt hat.
function FieldAnalyzer.markMemoryKeys(data, keys)
    if keys ~= "fieldId" and type(data) == "string" and data ~= "" then
        FieldAnalyzer.memoryKeysAreIndex = true
    end
end

-- Einmalige Umrechnung alter Gedaechtnis-Schluessel (Listenposition -> Feldnummer).
function FieldAnalyzer.migrateMemoryKeys(fields)
    if not FieldAnalyzer.memoryKeysAreIndex then return end
    FieldAnalyzer.memoryKeysAreIndex = false
    local neu = {}
    for key, fruit in pairs(FieldAnalyzer.fruitMemory) do
        local field = fields[tonumber(key)]
        local nr = FieldAnalyzer.getFieldNumber(field, nil)
        if nr ~= nil then neu[tostring(nr)] = fruit end
    end
    FieldAnalyzer.fruitMemory = neu
    FieldAnalyzer.memoryDirty = true
end

-- Gibt alle Felder zurueck (isOwn-Flag gesetzt), sortiert: eigene zuerst, dann nach ID.
function FieldAnalyzer.getOwnFields()
    FieldAnalyzer.loadFruitMemoryLocal()
    local farmId = FieldAnalyzer.getLocalFarmId()
    if g_fieldManager == nil then return {} end
    local fields = g_fieldManager:getFields()
    if fields == nil then return {} end

    FieldAnalyzer.migrateMemoryKeys(fields)

    local result = {}
    for key, field in pairs(fields) do
        local fid = FieldAnalyzer.getFieldNumber(field, (type(key) == "number") and key or (field.fieldId or field.id or "?"))
        local isOwn = FieldAnalyzer.isOwnField(field, farmId)

        local currentFruit = FieldAnalyzer.getCurrentFruit(field)
        local prevFruit    = FieldAnalyzer.getPreviousFruit(field)
        local memKey       = tostring(fid)
        local lastFruit    = nil

        if currentFruit ~= nil then
            -- Echte Frucht sichtbar -> Gedaechtnis aktualisieren
            if FieldAnalyzer.fruitMemory[memKey] ~= currentFruit then
                FieldAnalyzer.fruitMemory[memKey] = currentFruit
                FieldAnalyzer.memoryDirty = true
            end
        else
            -- Feld bearbeitet/leer -> letzte bekannte Frucht bewahren.
            -- Sie dient als Vorfrucht fuer die Rotations-Empfehlung.
            lastFruit = FieldAnalyzer.fruitMemory[memKey]
            if prevFruit == nil then
                prevFruit = lastFruit
            end
        end

        local info = {
            fieldId      = fid,
            fieldName    = field.name or field.fieldName or ("Feld " .. tostring(fid)),
            farmId       = field.farmId,
            prevFruit    = prevFruit,
            currentFruit = currentFruit,
            lastFruit    = lastFruit,
            area         = (field.areaHa or 0) * 10000,
            isOwn        = isOwn,
            field        = field,
        }
        table.insert(result, info)
    end

    table.sort(result, function(a, b)
        if a.isOwn ~= b.isOwn then return a.isOwn end
        return (tonumber(a.fieldId) or 0) < (tonumber(b.fieldId) or 0)
    end)

    -- Gedaechtnis-Aenderungen sofort client-lokal sichern
    if FieldAnalyzer.memoryDirty then
        FieldAnalyzer.memoryDirty = false
        FieldAnalyzer.saveFruitMemoryLocal()
    end

    return result
end
