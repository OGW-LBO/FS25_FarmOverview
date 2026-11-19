-- StorageAnalyzer.lua
-- Drei Quellen:
--   1. storageSystem    -> Silos, Produktionslager (farmId + farmId 0)
--   2. nodeToObject     -> Ballen/Paletten die physisch auf dem Hof liegen
--   3. Placeables       -> Ballen- und Palettenlager: dynamische Spec-Suche
--                         (spec_objectStorage / objectInfos / baleAttributes)
StorageAnalyzer = {}

function StorageAnalyzer.getLocalFarmId()
    if FieldAnalyzer ~= nil and FieldAnalyzer.getLocalFarmId ~= nil then
        return FieldAnalyzer.getLocalFarmId()
    end
    if g_currentMission and g_currentMission.player then
        return g_currentMission.player.farmId
    end
    return 1
end

-- ─── HILFSFUNKTIONEN ─────────────────────────────────────────────────────────

-- FillType-Beschreibung per Name, oder nil, wenn der Manager (noch) fehlt.
local function fillTypeByName(name)
    if g_fillTypeManager == nil or g_fillTypeManager.getFillTypeByName == nil then
        return nil
    end
    return g_fillTypeManager:getFillTypeByName(name)
end

local function ftKey(idx)
    if type(idx) ~= "number" or idx <= 0 then return nil end
    if g_fillTypeManager == nil or g_fillTypeManager.getFillTypeByIndex == nil then
        return nil
    end
    local desc = g_fillTypeManager:getFillTypeByIndex(idx)
    if desc ~= nil and type(desc.name) == "string" then
        return string.upper(desc.name)
    end
    return nil
end

-- ─── 0. FAHRSILOS UND PRODUKTIONSLAGER ───────────────────────────────────────
-- Beide Bestaende fehlten der Auswertung komplett, was zu falschen Meldungen
-- fuehrte: "Knapp: Silage", obwohl das Fahrsilo voll war, und "Knapp: Aepfel",
-- obwohl die Mosterei gut gefuellt ist. Welche Lager eine Karte nutzt, ist von
-- Karte zu Karte verschieden - deshalb werden jetzt ALLE Orte gelesen, an denen
-- Ware der Farm liegen kann.

-- Fahrsilo (Gras/Haeckselgut -> Silage). Verifiziert in
-- dataS/scripts/objects/BunkerSilo.lua + placeables/specializations/
-- PlaceableBunkerSilo.lua: spec_bunkerSilo.bunkerSilo mit fillLevel,
-- inputFillType, outputFillType und state (STATE_FILL/CLOSED/FERMENTED).
-- Solange das Silo offen oder noch am Gaeren ist, liegt dort das EINGANGSgut
-- (Haeckselgut); fertig gegoren zaehlt es als AUSGANG (Silage).
local function readBunkerSilos(farmId, totals)
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps == nil or type(ps.placeables) ~= "table" then return 0 end
    local anzahl = 0
    for _, p in pairs(ps.placeables) do
        local spec = p ~= nil and p.spec_bunkerSilo or nil
        local silo = spec ~= nil and spec.bunkerSilo or nil
        if silo ~= nil and type(silo.fillLevel) == "number" and silo.fillLevel > 0
                and (p.ownerFarmId == farmId or silo.ownerFarmId == farmId) then
            local fertig = (BunkerSilo ~= nil and BunkerSilo.STATE_FERMENTED ~= nil
                and silo.state == BunkerSilo.STATE_FERMENTED)
            local key = ftKey(fertig and silo.outputFillType or silo.inputFillType)
            if key ~= nil then
                totals[key] = (totals[key] or 0) + silo.fillLevel
                anzahl = anzahl + 1
            end
        end
    end
    return anzahl
end

-- Ein- und Ausgangslager der eigenen Produktionen. Was in der Mosterei liegt,
-- gehoert dem Hof und deckt deren Bedarf - fuer die Reichweite ist es also
-- Bestand. Die Produktions-Storages werden in readStorages ausgelassen, hier
-- also kein Doppelzaehlen.
local function readProductionBuffers(farmId, totals)
    local pcm = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    if pcm == nil then return 0 end
    local points = nil
    if pcm.getProductionPointsForFarmId ~= nil then
        points = pcm:getProductionPointsForFarmId(farmId)
    end
    if points == nil then return 0 end
    local gesehen, anzahl = {}, 0
    for _, pp in pairs(points) do
        local st = (type(pp) == "table") and pp.storage or nil
        if st ~= nil and not gesehen[st] and type(st.fillLevels) == "table" then
            gesehen[st] = true
            anzahl = anzahl + 1
            for idx, amount in pairs(st.fillLevels) do
                if type(idx) == "number" and type(amount) == "number" and amount > 0 then
                    local key = ftKey(idx)
                    if key ~= nil then
                        totals[key] = (totals[key] or 0) + amount
                    end
                end
            end
        end
    end
    return anzahl
end

-- Futter in den Stall-Troegen. PlaceableHusbandryFood fuehrt KEIN Storage,
-- sondern eine eigene Tabelle spec_husbandryFood.fillLevels (FillTypeIndex ->
-- Liter) - verifiziert in PlaceableHusbandryFood.lua. Dieser Bestand fehlte dem
-- Lager-Tab deshalb komplett, obwohl es Ware des Hofes ist (auf Bergisch Land
-- z. B. rund 20.000 l Gras und 10.000 l Silage in den Troegen).
--
-- `nurBekannte` filtert Sorten heraus, die der Hof sonst nirgends lagert. Das
-- ist noetig, weil `PlaceableHusbandryFood:addFood` eine eingefuellte MISCHUNG
-- (TMR) in die Rationsgruppen zerlegt und jede Gruppe auf ihre ERSTE Sorte
-- bucht (`ingredient.fillTypes[1]`). Auf Bergisch Land steht in der
-- Getreidegruppe PROTEINGRIST vorn - 10 % jeder TMR-Ladung tauchten dadurch als
-- „Proteinschrot" im Lager auf, das nie jemand gekauft hat.
local function readHusbandryFood(farmId, totals, nurBekannte)
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps == nil then return 0 end
    local placeables = nil
    if type(ps.getPlaceables) == "function" then placeables = ps:getPlaceables() end
    if placeables == nil and type(ps.placeables) == "table" then
        placeables = ps.placeables
    end
    if placeables == nil then return 0 end

    local anzahl = 0
    for _, p in pairs(placeables) do
        if p ~= nil and (p.ownerFarmId or p.farmId) == farmId then
            local spec = p.spec_husbandryFood
            if spec ~= nil and type(spec.fillLevels) == "table" then
                for idx, amount in pairs(spec.fillLevels) do
                    if type(idx) == "number" and type(amount) == "number"
                            and amount > 0 then
                        local key = ftKey(idx)
                        if key ~= nil
                                and (nurBekannte == nil or nurBekannte[key] == true) then
                            totals[key] = (totals[key] or 0) + amount
                            anzahl = anzahl + 1
                        end
                    end
                end
            end
        end
    end
    return anzahl
end

-- ─── 1. SILOS (OHNE Produktions-Ein/Ausgangslager) ───────────────────────────

-- Sammelt die Storage-Objekte ALLER Produktionspunkte. Diese sind zwar im
-- storageSystem registriert (gleiche Objekt-Referenz wie pp.storage), gehoeren
-- aber NICHT zum frei verfuegbaren Hoflager — sonst wuerde der Ein-/Ausgang der
-- Produktionen (z. B. Mineralfutter, Mehl, eingelagertes Getreide) doppelt im
-- Lager-Tab auftauchen. Rueckgabe: Set { [storageObj] = true }.
local function collectProductionStorages()
    local set = {}
    local function schritt()
        local pcm = g_currentMission and g_currentMission.productionChainManager
        if pcm == nil then return end
        local points = pcm.productionPoints
        if type(points) ~= "table" then return end
        for _, pp in pairs(points) do
            if pp ~= nil and pp.storage ~= nil then
                set[pp.storage] = true
            end
        end
    end
    schritt()
    return set
end

-- Besitzer eines Storage-Objekts. PlaceableSilo und PlaceableHusbandry setzen
-- ihn beim Platzieren/Kaufen (storage:setOwnerFarmId), Karten-Silos mit
-- storagePerFarm fuehren je Hof ein eigenes Storage mit ownerFarmId = Hofnummer.
-- nil heisst "keine Angabe" (exotische Mod-Lager) - solche zaehlen weiter mit.
local function storageFarmId(storage)
    local f = nil
    if type(storage.getOwnerFarmId) == "function" then f = storage:getOwnerFarmId() end
    if f == nil then f = storage.ownerFarmId end
    return f
end

local function readStorages(ss, farmId, totals, excludeSet, seenSet)
    if ss == nil then return 0 end
    local storages = nil
    if ss.getStorages ~= nil then storages = ss:getStorages(farmId) end
    if storages == nil and type(ss.storages) == "table" then
        storages = ss.storages
    end
    if storages == nil then return 0 end

    local count = 0
    for _, storage in pairs(storages) do
        -- Auslassen, wenn (a) Produktions-Ein/Ausgangslager, (b) dieses
        -- Storage-Objekt bereits gezaehlt wurde oder (c) es einem ANDEREN Hof
        -- gehoert. Punkt (c) ist entscheidend: getStorages liefert je nach
        -- Karte/Version alle Silos des Servers. Auf Bergisch Land landeten so
        -- 80.000 l Einstreu und 57.842 l Getreide des Nachbarhofs im eigenen
        -- Lager.
        local sFarm = storageFarmId(storage)
        if (excludeSet ~= nil and excludeSet[storage] == true)
                or (seenSet ~= nil and seenSet[storage] == true)
                or (sFarm ~= nil and sFarm ~= farmId) then
            -- skip
        else
        if seenSet ~= nil then seenSet[storage] = true end
        count = count + 1
        if type(storage.fillLevels) == "table" then
            for idx, amount in pairs(storage.fillLevels) do
                if type(idx) == "number" and type(amount) == "number" and amount > 0 then
                    local key = ftKey(idx)
                    if key ~= nil then
                        totals[key] = (totals[key] or 0) + amount
                    end
                end
            end
        end
        end
    end
    return count
end

-- ─── 2. PHYSISCHE BALLEN/PALETTEN (nodeToObject) ─────────────────────────────

local function readNodeObjects(farmId, totals)
    local nto = g_currentMission and g_currentMission.nodeToObject
    if nto == nil then
        print("[FA] Storage: nodeToObject nicht verfuegbar")
        return 0
    end

    local count = 0
    local seen = {}

    for _, obj in pairs(nto) do
        if obj ~= nil and not seen[obj] then
            seen[obj] = true

            local ftIdx  = nil
            local amount = 0
            ftIdx  = obj.fillType or obj.fillTypeIndex
            amount = obj.fillLevel or 0

            if type(ftIdx) == "number" and ftIdx > 0
                    and type(amount) == "number" and amount > 0 then

                local bFarm = nil
                if obj.getOwnerFarmId ~= nil then bFarm = obj:getOwnerFarmId() end
                if bFarm == nil then bFarm = obj.farmId or obj.ownerFarmId end

                if bFarm == farmId then
                    local key = ftKey(ftIdx)
                    if key ~= nil then
                        totals[key] = (totals[key] or 0) + amount
                        count = count + 1
                    end
                elseif bFarm == nil then
                    local key = ftKey(ftIdx)
                    if key ~= nil then
                        totals[key] = (totals[key] or 0) + amount
                        count = count + 1
                    end
                end
            end
        end
    end

    return count
end

-- ─── 3. BALLEN- UND PALETTENLAGER (PLACEABLES) ───────────────────────────────

local function readBaleList(baleList, totals)
    if type(baleList) ~= "table" then return 0 end
    local n = 0
    for _, entry in pairs(baleList) do
        if entry ~= nil then
            local ftIdx  = nil
            local amount = 0
            ftIdx  = entry.fillType or entry.fillTypeIndex
            amount = entry.fillLevel or 0
            if type(ftIdx) == "number" and ftIdx > 0
                    and type(amount) == "number" and amount > 0 then
                local key = ftKey(ftIdx)
                if key ~= nil then
                    totals[key] = (totals[key] or 0) + amount
                    n = n + 1
                end
            end
        end
    end
    return n
end

-- Liest FillType + FillLevel aus einem gespeicherten Ballen-Objekt.
-- Pfad 1: baleAttributes.fillType + baleAttributes.fillLevel  (lsfmBaleStorage)
-- Pfad 2: direkte Properties (fillType, fillLevel)            (Standard-Ballen)
-- Pfad 3: spec_fillUnit.fillUnits[1]
-- Pfad 4: spec_bale
-- Pfad 5: Methoden-Aufruf (getFillType / getFillTypeIndex)
local function readObjFillData(obj)
    if obj == nil then return nil, 0 end
    local ft = nil
    local fl = 0

    -- Pfad 1: baleAttributes (lsfmBaleStorage)
    if type(obj.baleAttributes) == "table" then
        local ba = obj.baleAttributes
        ft = ba.fillTypeIndex or ba.fillType
        local lv = ba.fillLevel or ba.capacity or ba.amount or 0
        fl = type(lv) == "number" and lv or 0
    end

    -- Pfad 2: direkte Properties
    if type(ft) ~= "number" or ft <= 0 then
        ft = obj.fillType or obj.fillTypeIndex
        local lv = obj.fillLevel or 0
        fl = type(lv) == "number" and lv or 0
    end

    -- Pfad 3: spec_fillUnit
    if (type(ft) ~= "number" or ft <= 0) and type(obj.spec_fillUnit) == "table" then
        local units = obj.spec_fillUnit.fillUnits
        if type(units) == "table" then
            for _, funit in pairs(units) do
                if type(funit) == "table" then
                    ft = funit.fillTypeIndex or funit.fillType
                    fl = type(funit.fillLevel) == "number" and funit.fillLevel or 0
                    break
                end
            end
        end
    end

    -- Pfad 4: spec_bale
    if (type(ft) ~= "number" or ft <= 0) and type(obj.spec_bale) == "table" then
        ft = obj.spec_bale.fillTypeIndex or obj.spec_bale.fillType
        fl = type(obj.spec_bale.fillLevel) == "number" and obj.spec_bale.fillLevel or 0
    end

    -- Pfad 5: Methoden-Aufruf
    if type(ft) ~= "number" or ft <= 0 then
        if type(obj.getFillType) == "function" then ft = obj:getFillType() end
    end
    if type(ft) ~= "number" or ft <= 0 then
        if type(obj.getFillTypeIndex) == "function" then
            ft = obj:getFillTypeIndex()
        end
    end
    if (type(fl) ~= "number" or fl <= 0) and type(ft) == "number" and ft > 0 then
        if type(obj.getFillLevel) == "function" then fl = obj:getFillLevel(1) end
    end

    -- Pfad 6 (allgemein): Paletten in einem Objektlager haengen ihre Daten an
    -- einen anderen Schluessel als Ballen (abstraktes Fahrzeug-Objekt statt
    -- baleAttributes). Statt Namen zu raten, wird eine Ebene tief nach einer
    -- Tabelle gesucht, die Fuelltyp UND Fuellstand fuehrt - das funktioniert
    -- auch fuer Lager-Mods, die es wieder anders benennen.
    if type(ft) ~= "number" or ft <= 0 then
        for _, v in pairs(obj) do
            if type(v) == "table" then
                local kand = v.fillTypeIndex or v.fillType
                if type(kand) ~= "number" and type(v.fillTypeName) == "string"
                        and g_fillTypeManager ~= nil
                        and g_fillTypeManager.getFillTypeIndexByName ~= nil then
                    kand = g_fillTypeManager:getFillTypeIndexByName(v.fillTypeName)
                end
                local lv = v.fillLevel
                if type(kand) == "number" and kand > 0
                        and type(lv) == "number" and lv > 0 then
                    ft, fl = kand, lv
                    break
                end
            end
        end
    end

    if type(ft) ~= "number" or ft <= 0 then return nil, 0 end
    if type(fl) ~= "number" then fl = 0 end
    return ft, fl
end

-- Liest spec_objectStorage (Ballen- und Palettenlager, auch FS25_lsfmBaleStorage).
-- Zwei Wege, weil der Mehrspieler-Client nicht alle Objekte kennt - siehe unten.
local function readObjectStorageInfos(spec, totals)
    if spec == nil then return 0 end

    -- Weg 1 (genau): storedObjects haelt JEDES eingelagerte Objekt einzeln.
    -- Verifiziert in PlaceableObjectStorage.lua (addAbstactObjectToObjectStorage).
    -- Diese Liste fuehrt nur der Server/das Einzelspiel.
    if type(spec.storedObjects) == "table" and #spec.storedObjects > 0 then
        local n = 0
        for _, obj in ipairs(spec.storedObjects) do
            if obj ~= nil then
                local ft, fl = readObjFillData(obj)
                if type(ft) == "number" and ft > 0
                        and type(fl) == "number" and fl > 0 then
                    local fkey = ftKey(ft)
                    if fkey ~= nil then
                        totals[fkey] = (totals[fkey] or 0) + fl
                        n = n + 1
                    end
                end
            end
        end
        if n > 0 then return n end
    end

    -- Weg 2 (Mehrspieler-Client): objectInfos fasst gleiche Objekte zu Gruppen
    -- zusammen. Der Client bekommt je Gruppe nur EINEN Vertreter uebertragen
    -- (PlaceableObjectStorage:onReadStream -> objects = {readStream(...)}), die
    -- Stueckzahl steht separat in numObjects. Ohne diesen Faktor wurde je Gruppe
    -- nur ein einziger Ballen gezaehlt: 86 Strohballen ergaben 15.075 l statt
    -- 596.075 l.
    local oInfos = spec.objectInfos
    if type(oInfos) ~= "table" then return 0 end

    local n = 0
    for _, iv in pairs(oInfos) do
        if type(iv) == "table" and type(iv.objects) == "table" then
            local nObjs = type(iv.numObjects) == "number" and iv.numObjects or 0
            local posten, gelesen = {}, 0
            for _, obj in pairs(iv.objects) do
                if obj ~= nil then
                    local ft, fl = readObjFillData(obj)
                    if type(ft) == "number" and ft > 0
                            and type(fl) == "number" and fl > 0 then
                        local fkey = ftKey(ft)
                        if fkey ~= nil then
                            posten[fkey] = (posten[fkey] or 0) + fl
                            gelesen = gelesen + 1
                        end
                    end
                end
            end
            if gelesen > 0 then
                local faktor = 1
                if nObjs > gelesen then faktor = nObjs / gelesen end
                for fkey, fl in pairs(posten) do
                    totals[fkey] = (totals[fkey] or 0) + fl * faktor
                end
                n = n + math.max(nObjs, gelesen)
            end
        end
    end
    return n
end

local function getPlaceableName(p)
    local name = nil
    local raw = p.configFileName or p.xmlFilename or p.xmlFile
             or p.customEnvironment or p.filename
    if type(raw) == "string" then
        name = raw:match("[^/\\]+$") or raw
    end
    return name or "?"
end

local function readBalenLagerPlaceables(farmId, totals)
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps == nil then return 0 end

    local placeables = nil
    if type(ps.getPlaceables) == "function" then
        placeables = ps:getPlaceables()
    end
    if placeables == nil and type(ps.placeables) == "table" then
        placeables = ps.placeables
    end
    if placeables == nil then return 0 end

    local total = 0
    for _, p in pairs(placeables) do
        if p ~= nil then
            local pFarm = p.ownerFarmId or p.farmId
            if pFarm == farmId then
                for key, spec in pairs(p) do
                    if type(key) == "string" and key:sub(1, 5) == "spec_"
                            and type(spec) == "table" then
                        total = total + readBaleList(spec.bales, totals)
                        total = total + readBaleList(spec.items, totals)
                        if spec.objectInfos ~= nil then
                            total = total + readObjectStorageInfos(spec, totals)
                        end
                    end
                end
            end
        end
    end

    return total
end

-- ─── DIAGNOSE-DUMP ────────────────────────────────────────────────────────────

function StorageAnalyzer.debugDump()
    local farmId = StorageAnalyzer.getLocalFarmId()
    print("=== FA-STORAGE-DUMP farmId=" .. tostring(farmId) .. " ===")

    -- Fahrsilos und Produktionslager einzeln ausweisen: beides fehlte frueher
    -- ganz, bei falschen Knapp-Meldungen zuerst hier nachsehen.
    local fsilo, pbuf = {}, {}
    local nSilos = readBunkerSilos(farmId, fsilo)
    local nProds = readProductionBuffers(farmId, pbuf)
    print("  Fahrsilos mit Inhalt: " .. tostring(nSilos))
    for key, amount in pairs(fsilo) do
        print("    FAHRSILO: " .. key .. "=" .. string.format("%.0f", amount))
    end
    print("  Produktionslager: " .. tostring(nProds))
    for key, amount in pairs(pbuf) do
        print("    PRODUKTION: " .. key .. "=" .. string.format("%.0f", amount))
    end

    -- Silos und Stall-Lager des EIGENEN Hofes (fremde werden uebersprungen)
    local silos, gesehenSilo = {}, {}
    local nSilo = readStorages(g_currentMission and g_currentMission.storageSystem,
        farmId, silos, collectProductionStorages(), gesehenSilo)
    print("  Eigene Silo-/Stall-Lager: " .. tostring(nSilo))
    for key, amount in pairs(silos) do
        print("    SILO: " .. key .. "=" .. string.format("%.0f", amount))
    end

    local trog = {}
    local nTrog = readHusbandryFood(farmId, trog)
    print("  Stall-Troege mit Futter: " .. tostring(nTrog)
        .. " (roh; ins Lager zaehlt nur, was der Hof auch sonst lagert -"
        .. " eingefuellte Mischrationen werden vom Spiel auf die erste Sorte"
        .. " jeder Rationsgruppe gebucht)")
    for key, amount in pairs(trog) do
        print("    TROG: " .. key .. "=" .. string.format("%.0f", amount))
    end

    -- nodeToObject
    local nto = g_currentMission and g_currentMission.nodeToObject
    if nto ~= nil then
        local n = 0
        local seen = {}
        for _, obj in pairs(nto) do
            if obj ~= nil and not seen[obj] then
                seen[obj] = true
                local ftIdx  = obj.fillType or obj.fillTypeIndex
                local amount = obj.fillLevel or 0
                if type(ftIdx) == "number" and ftIdx > 0
                        and type(amount) == "number" and amount > 0 then
                    local bFarm = nil
                    if obj.getOwnerFarmId ~= nil then bFarm = obj:getOwnerFarmId() end
                    if bFarm == nil then bFarm = obj.farmId or obj.ownerFarmId end
                    local key = ftKey(ftIdx) or ("idx" .. tostring(ftIdx))
                    print("  FILL-OBJ: " .. key .. "=" .. string.format("%.0f", amount)
                        .. " farm=" .. tostring(bFarm))
                    n = n + 1
                end
            end
        end
        print("  nodeToObject: " .. n .. " unique Fill-Objekte")
    else
        print("  nodeToObject: nil")
    end

    -- spec_objectStorage: Zusammenfassung pro Lager
    local ps = g_currentMission and g_currentMission.placeableSystem
    if ps ~= nil then
        local placeables = nil
        if type(ps.getPlaceables) == "function" then
            placeables = ps:getPlaceables()
        end
        if placeables == nil and type(ps.placeables) == "table" then
            placeables = ps.placeables
        end
        if placeables ~= nil then
            for _, p in pairs(placeables) do
                if p ~= nil then
                    local pFarm = p.ownerFarmId or p.farmId
                    if pFarm == farmId then
                        local function schritt()
                            local spec = p.spec_objectStorage
                            if type(spec) ~= "table" then return end
                            local name = getPlaceableName(p)
                            local nStored = spec.numStoredObjects or 0
                            local slotTotals = {}
                            local readCount = readObjectStorageInfos(spec, slotTotals)
                            local nStored2 = (type(spec.storedObjects) == "table")
                                and #spec.storedObjects or 0
                            local nInfos = (type(spec.objectInfos) == "table")
                                and #spec.objectInfos or 0
                            local parts = {}
                            for k, v in pairs(slotTotals) do
                                table.insert(parts, k .. "=" .. string.format("%.0f", v))
                            end
                            table.sort(parts)
                            print("  OBJSTORAGE " .. name
                                .. " n=" .. tostring(nStored)
                                .. " stored=" .. tostring(nStored2)
                                .. " gruppen=" .. tostring(nInfos)
                                .. " read=" .. tostring(readCount)
                                .. " [" .. table.concat(parts, " ") .. "]")

                            -- Nicht gelesene Objekte: Aufbau des ersten Objekts
                            -- zeigen, damit ein neuer Lager-Typ ohne Raten
                            -- nachgeruestet werden kann.
                            if readCount < nStored and type(spec.objectInfos) == "table" then
                                for _, iv in pairs(spec.objectInfos) do
                                    local obj = type(iv) == "table"
                                        and type(iv.objects) == "table" and iv.objects[1] or nil
                                    if obj ~= nil then
                                        local felder = {}
                                        for k, v in pairs(obj) do
                                            local t = type(v)
                                            if t == "table" then
                                                local unter = {}
                                                for k2, v2 in pairs(v) do
                                                    table.insert(unter, tostring(k2)
                                                        .. "=" .. tostring(v2))
                                                end
                                                table.sort(unter)
                                                table.insert(felder, tostring(k) .. "{"
                                                    .. table.concat(unter, ",") .. "}")
                                            elseif t ~= "function" then
                                                table.insert(felder, tostring(k)
                                                    .. "=" .. tostring(v))
                                            end
                                        end
                                        table.sort(felder)
                                        print("    UNGELESEN: " .. table.concat(felder, " "))
                                        break
                                    end
                                end
                            end
                        end
                        schritt()
                    end
                end
            end
        end
    end

    -- Endsumme so, wie sie im Bereich LAGER landet - damit laesst sich sofort
    -- sehen, ob die Summe zu den Einzelquellen darueber passt.
    local tots = StorageAnalyzer.getTotals()
    local kaps = StorageAnalyzer.getCapacities()
    local keys = {}
    for key, amount in pairs(tots) do
        if amount > 0 then table.insert(keys, key) end
    end
    table.sort(keys, function(a, b) return tots[a] > tots[b] end)
    for _, key in ipairs(keys) do
        print("  SUMME: " .. key .. "=" .. string.format("%.0f", tots[key])
            .. " kapazitaet=" .. string.format("%.0f", kaps[key] or 0))
    end

    print("=== FA-STORAGE-DUMP ENDE ===")
end

-- ─── MARKT-TIPPS (aktuelle Verkaufspreise) ───────────────────────────────────
-- SellingStation ist nicht in der LUADOC dokumentiert -> komplett defensiv:
--   Pfad 1: placeable.spec_sellingStation.sellingStation
--   Pfad 2: g_currentMission.storageSystem:getUnloadingStations()
-- Preisabfrage: station:getEffectiveFillTypePrice(fillTypeIndex)
-- Vergleich gegen Basispreis fillTypeDesc.pricePerLiter (verifiziert).
-- Liefert die Abfrage nichts Plausibles, gibt es einfach keine Tipps.

local function getStationName(station, placeable)
    local name = nil
    if station ~= nil and type(station.stationName) == "string" then
        name = station.stationName
    end
    if name == nil and station ~= nil and station.getName ~= nil then
        local n = station:getName()
        if type(n) == "string" then name = n end
    end
    if name == nil and placeable ~= nil and placeable.getName ~= nil then
        local n = placeable:getName()
        if type(n) == "string" then name = n end
    end
    return name
end

local function collectSellStations()
    local stations = {}
    local seen = {}

    -- Pfad 1: Placeables mit spec_sellingStation
    local function schritt()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil or type(ps.placeables) ~= "table" then return end
        for _, p in pairs(ps.placeables) do
            if p ~= nil and type(p.spec_sellingStation) == "table" then
                local st = p.spec_sellingStation.sellingStation
                if st ~= nil and not seen[st]
                        and st.getEffectiveFillTypePrice ~= nil then
                    seen[st] = true
                    table.insert(stations, { station = st, placeable = p })
                end
            end
        end
    end
    schritt()

    -- Pfad 2: UnloadingStations des storageSystems (Funktion oder Property)
    local function schritt()
        local ss = g_currentMission and g_currentMission.storageSystem
        if ss == nil then return end
        local us = nil
        if ss.getUnloadingStations ~= nil then
            us = ss:getUnloadingStations()
        end
        if type(us) ~= "table" then
            us = ss.unloadingStations
        end
        if type(us) ~= "table" then return end
        for _, st in pairs(us) do
            if st ~= nil and not seen[st]
                    and st.getEffectiveFillTypePrice ~= nil then
                seen[st] = true
                table.insert(stations, { station = st, placeable = st.owningPlaceable })
            end
        end
    end
    schritt()

    return stations
end

-- Akzeptiert die Station diesen FillType? Nur dann darf
-- getEffectiveFillTypePrice aufgerufen werden — sonst spammt die Engine
-- "Missing filltype ..." mit Callstack ins Log (siehe log.txt-Analyse).
local function stationAcceptsFillType(st, idx)
    local ok = false
    if type(st.acceptedFillTypes) == "table"
            and st.acceptedFillTypes[idx] == true then
        ok = true
    end
    if not ok and st.getIsFillTypeSupported ~= nil then
        ok = st:getIsFillTypeSupported(idx) == true
    end
    if not ok and type(st.fillTypePrices) == "table"
            and st.fillTypePrices[idx] ~= nil then
        ok = true
    end
    if not ok and type(st.supportedFillTypes) == "table"
            and st.supportedFillTypes[idx] == true then
        ok = true
    end
    return ok
end

-- Markt-Bewertung aller nennenswerten Bestaende (>= 1000 L):
-- bester aktueller Verkaufspreis im Verhaeltnis zum Basispreis.
-- Rueckgabe sortiert nach ratio absteigend:
-- { { key, amount, ratio, station }, ... }  (ratio 1.0 = Basispreis)
function StorageAnalyzer.getMarketTips(storageTotals)
    local tips = {}
    local function schritt()
        local stations = collectSellStations()
        if #stations == 0 then return end

        for key, amount in pairs(storageTotals) do
            if type(amount) == "number" and amount >= 1000 then
                local idx, base = nil, nil
                local desc = fillTypeByName(key)
                if desc ~= nil then
                    idx = desc.index
                    if type(desc.pricePerLiter) == "number"
                            and desc.pricePerLiter > 0 then
                        base = desc.pricePerLiter
                    end
                end

                if idx ~= nil and base ~= nil then
                    local bestPrice, bestStation = nil, nil
                    for _, entry in ipairs(stations) do
                        local function schritt()
                            local st = entry.station
                            if not stationAcceptsFillType(st, idx) then return end
                            if st.getEffectiveFillTypePrice == nil then return end
                            local price = st:getEffectiveFillTypePrice(idx)
                            if type(price) == "number" and price > 0 then
                                if bestPrice == nil or price > bestPrice then
                                    bestPrice   = price
                                    bestStation = getStationName(st, entry.placeable)
                                end
                            end
                        end
                        schritt()
                    end

                    if bestPrice ~= nil then
                        local ratio = bestPrice / base
                        -- Plausibilitaet: 0.2x .. 3x, sonst falsche Einheit
                        if ratio >= 0.2 and ratio <= 3.0 then
                            table.insert(tips, {
                                key     = key,
                                amount  = amount,
                                ratio   = ratio,
                                station = bestStation,
                            })
                        end
                    end
                end
            end
        end

        table.sort(tips, function(a, b) return a.ratio > b.ratio end)
    end
    schritt()
    return tips
end

-- Konsolen-Dump: zeigt welche Verkaufsstationen/Preise gefunden werden.
-- Aufruf im Spiel: Konsole oeffnen (~) und "faMarkt" eingeben.
function StorageAnalyzer.marketDebugDump()
    print("=== FA-MARKT-DUMP ===")

    -- 1) Placeables mit "sell" im Spec-Namen
    local nSell = 0
    local function schritt()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil or type(ps.placeables) ~= "table" then
            print("  placeableSystem/placeables: nicht verfuegbar")
            return
        end
        for _, p in pairs(ps.placeables) do
            if p ~= nil then
                for key, v in pairs(p) do
                    if type(key) == "string" and key:sub(1, 5) == "spec_"
                            and type(v) == "table"
                            and string.find(string.lower(key), "sell") ~= nil then
                        nSell = nSell + 1
                        local st = v.sellingStation
                        print("  PLACEABLE " .. getPlaceableName(p)
                            .. "  " .. key
                            .. "  sellingStation=" .. tostring(st ~= nil))
                        if st ~= nil then
                            print("    getEffectiveFillTypePrice="
                                .. tostring(st.getEffectiveFillTypePrice ~= nil)
                                .. "  acceptedFillTypes=" .. type(st.acceptedFillTypes))
                            local d = fillTypeByName("WHEAT")
                            if d ~= nil and st.getEffectiveFillTypePrice ~= nil then
                                if stationAcceptsFillType(st, d.index) then
                                    print("    WHEAT Preis="
                                        .. tostring(st:getEffectiveFillTypePrice(d.index))
                                        .. "  Basis=" .. tostring(d.pricePerLiter))
                                else
                                    print("    WHEAT nicht akzeptiert")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    schritt()
    print("  Placeables mit sell-Spec: " .. tostring(nSell))

    -- 2) storageSystem-Stationen
    local function schritt()
        local ss = g_currentMission and g_currentMission.storageSystem
        if ss == nil then
            print("  storageSystem: nil")
            return
        end
        print("  storageSystem: getUnloadingStations="
            .. tostring(ss.getUnloadingStations ~= nil)
            .. "  unloadingStations=" .. type(ss.unloadingStations))
        local us = nil
        if ss.getUnloadingStations ~= nil then us = ss:getUnloadingStations() end
        if type(us) ~= "table" then us = ss.unloadingStations end
        if type(us) ~= "table" then return end
        local n = 0
        for _, st in pairs(us) do
            n = n + 1
            if n <= 10 and st ~= nil then
                print("  STATION " .. tostring(getStationName(st, st.owningPlaceable))
                    .. "  getEffPrice=" .. tostring(st.getEffectiveFillTypePrice ~= nil)
                    .. "  isSellingPoint=" .. tostring(st.isSellingPoint))
                local d = fillTypeByName("WHEAT")
                if d ~= nil and st.getEffectiveFillTypePrice ~= nil then
                    if stationAcceptsFillType(st, d.index) then
                        print("    WHEAT Preis="
                            .. tostring(st:getEffectiveFillTypePrice(d.index))
                            .. "  Basis=" .. tostring(d.pricePerLiter))
                    else
                        print("    WHEAT nicht akzeptiert")
                    end
                end
            end
        end
        print("  Stationen gesamt: " .. tostring(n))
    end
    schritt()

    print("=== FA-MARKT-DUMP ENDE ===")
end

-- ─── GESAMT ───────────────────────────────────────────────────────────────────

-- Fassungsvermoegen je Fuelltyp (Liter), damit im Lager "33.268 / 100.000"
-- stehen kann statt nur der Menge.
-- Verifiziert in dataS/scripts/objects/Storage.lua:
--   `Storage:getCapacity(fillType)` -> `self.capacities[fillType] or self.capacity`
--   `Storage.fillTypes[idx] == true` -> welche Fuelltypen das Lager annimmt
-- Ein Silo fuer mehrere Fruechte teilt sich SEINE Kapazitaet; sie zaehlt
-- deshalb bei jeder Frucht voll mit - genauso zeigt es das Spiel selbst an.
-- Fahrsilos und Ballen-/Palettenlager bleiben aussen vor: der Spielcode fuehrt
-- fuer sie kein Fassungsvermoegen in Litern (BunkerSilo hat keins, Objektlager
-- zaehlen Objekte).
local function sammleKapazitaet(storage, kapazitaeten, gesehen)
    if storage == nil or gesehen[storage] then return end
    gesehen[storage] = true
    local typen = storage.fillTypes
    if type(typen) ~= "table" then return end
    for idx, erlaubt in pairs(typen) do
        if erlaubt == true and type(idx) == "number" then
            local key = ftKey(idx)
            if key ~= nil then
                local kap = nil
                if storage.getCapacity ~= nil then
                    kap = storage:getCapacity(idx)
                end
                if kap == nil then
                    kap = (type(storage.capacities) == "table" and storage.capacities[idx])
                        or storage.capacity
                end
                if type(kap) == "number" and kap > 0 then
                    kapazitaeten[key] = (kapazitaeten[key] or 0) + kap
                end
            end
        end
    end
end

function StorageAnalyzer.getCapacities()
    local farmId = StorageAnalyzer.getLocalFarmId()
    local kapazitaeten, gesehen = {}, {}

    local ss = g_currentMission and g_currentMission.storageSystem
    if ss ~= nil then
        local storages = nil
        if ss.getStorages ~= nil then storages = ss:getStorages(farmId) end
        if storages == nil and type(ss.storages) == "table" then storages = ss.storages end
        for _, storage in pairs(storages or {}) do
            -- Gleiche Besitzpruefung wie in readStorages: ohne sie stand bei
            -- Stroh "429.175 L" Kapazitaet, obwohl davon die Staelle des
            -- Nachbarhofs einen grossen Teil stellten.
            local sFarm = storageFarmId(storage)
            if sFarm == nil or sFarm == farmId then
                sammleKapazitaet(storage, kapazitaeten, gesehen)
            end
        end
    end

    -- Ein- und Ausgangslager der eigenen Produktionen: deren Inhalt zaehlt
    -- beim Bestand mit, also gehoert ihr Fassungsvermoegen auch dazu.
    local pcm = g_currentMission ~= nil and g_currentMission.productionChainManager or nil
    if pcm ~= nil and pcm.getProductionPointsForFarmId ~= nil then
        for _, pp in pairs(pcm:getProductionPointsForFarmId(farmId) or {}) do
            if type(pp) == "table" then
                sammleKapazitaet(pp.storage, kapazitaeten, gesehen)
            end
        end
    end
    return kapazitaeten
end

function StorageAnalyzer.getTotals()
    local farmId = StorageAnalyzer.getLocalFarmId()
    local totals = {}

    local ss = g_currentMission and g_currentMission.storageSystem
    if ss ~= nil then
        -- Produktions-Ein/Ausgangslager ausschliessen + jedes Storage-Objekt nur
        -- EINMAL zaehlen (seen), auch wenn es unter farmId und farmId 0 gelistet ist.
        local prodStorages = collectProductionStorages()
        local seen = {}
        readStorages(ss, farmId, totals, prodStorages, seen)
        -- Kein zweiter Durchlauf mit Hof 0 mehr: gezaehlt wird nur, was dem
        -- eigenen Hof gehoert (oder gar keinen Besitzer gemeldet hat).
    else
        print("[FA] Storage: storageSystem nicht verfuegbar")
    end

    readNodeObjects(farmId, totals)
    readBalenLagerPlaceables(farmId, totals)
    readBunkerSilos(farmId, totals)
    readProductionBuffers(farmId, totals)

    -- Trogfutter erst ganz zum Schluss und nur fuer Sorten, die der Hof auch
    -- wirklich lagert (siehe Hinweis bei readHusbandryFood).
    local bekannte = {}
    for key, amount in pairs(totals) do
        if amount > 0 then bekannte[key] = true end
    end
    readHusbandryFood(farmId, totals, bekannte)

    return totals
end
