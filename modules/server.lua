local Debug = Config.Debug
local MaxPlayers = GetConvarInt('sv_maxclients')
local HostName = GetConvar("sv_hostname") ~= "default FXServer" and GetConvar("sv_hostname") or false
local jsonCard = json.decode(LoadResourceFile(GetCurrentResourceName(), 'presentCard.json'))[1]
local date = os.date("%a %b %d, %H:%M")
local arrivalTime = os.date("%a %b %d, %H:%M", os.time() + (5 * 60))

local prioritydata = {}
local queuelist = {}
local queuepositions = {}
local connectinglist = {}
local reconnectlist = {}
local playercount = 0

local function updateCard(data, src)
    local pCard = jsonCard
    if not pCard or not pCard.body then
        DebugPrint("^1[ERROR] jsonCard is nil or has no body in updateCard!^7")
        return {}
    end

    local playerName = src and GetPlayerName(src) or "Unknown Passenger"
    local flightNumber = "OW" .. tostring(math.random(1000, 9999))
    local date = os.date("%a %b %d, %H:%M")
    local arrivalTime = os.date("%a %b %d, %H:%M", os.time() + ((data.pos > 1) and (5 * 60) or (1 * 60)))

         if pCard.body[2] and pCard.body[2]["columns"] and pCard.body[2]["columns"][2] and pCard.body[2]["columns"][2]["items"] then
            pCard.body[2]["columns"][2]["items"][2].text = (data.pos > 1) and "DELAYED" or "ON TIME"
            pCard.body[2]["columns"][2]["items"][2]["color"] = (data.pos > 1) and "Warning" or "Good"
        else
        DebugPrint("^1[ERROR] Flight Status section missing in JSON Card^7")
        end
        
        local playerCountText = string.format("%d/%d", playercount, MaxPlayers)
        local playerCountColor = (playercount >= MaxPlayers) and "Attention" or "Default"
   
         if pCard.body[3] and pCard.body[3]["columns"] then
         if pCard.body[3]["columns"][1] and pCard.body[3]["columns"][1]["items"] then
            pCard.body[3]["columns"][1]["items"][1].text = "Passenger"
            pCard.body[3]["columns"][1]["items"][2].text = playerName
        end

         if pCard.body[3]["columns"][2] and pCard.body[3]["columns"][2]["items"] then
            pCard.body[3]["columns"][2]["items"][1].text = "Aircraft Capacity"
            pCard.body[3]["columns"][2]["items"][2].text = playerCountText
            pCard.body[3]["columns"][2]["items"][2]["color"] = playerCountColor
        end
         if pCard.body[3]["columns"][3] and pCard.body[3]["columns"][3]["items"] then
            pCard.body[3]["columns"][3]["items"][1].text = "Seat"
            pCard.body[3]["columns"][3]["items"][2].text = string.format("%d/%d", data.pos, data.maxpos)
        end
    else
        DebugPrint("^1[ERROR] Passenger Name, Aircraft Capacity & Seat section missing in JSON Card^7")
    end
         if pCard.body[4] and pCard.body[4]["columns"] then
         if pCard.body[4]["columns"][1] and pCard.body[4]["columns"][1]["items"] then
            pCard.body[4]["columns"][1]["items"][2].text = flightNumber
        end
         if pCard.body[4]["columns"][2] and pCard.body[4]["columns"][2]["items"] then
            pCard.body[4]["columns"][2]["items"][2].text = date
        end
         if pCard.body[4]["columns"][3] and pCard.body[4]["columns"][3]["items"] then
            pCard.body[4]["columns"][3]["items"][2].text = arrivalTime
            pCard.body[4]["columns"][3]["items"][2]["color"] = (data.pos > 1) and "Warning" or "Good"
        end
    else
        DebugPrint("^1[ERROR] Flight Info section missing in JSON Card^7")
    end
         if pCard.body[6] and pCard.body[6]["columns"] and pCard.body[6]["columns"][2] and pCard.body[6]["columns"][2]["items"] then
        local points = data.points or 0
            pCard.body[6]["columns"][2]["items"][1].text = "Airline Miles: " .. tostring(points)
        DebugPrint("^3[DEBUG] Airline Miles updated: " .. tostring(points))
    else
        DebugPrint("^1[ERROR] Airline Miles section missing in JSON Card^7")
    end
    return pCard
end

local function getPrioData(identifier)
    return prioritydata[identifier]
end exports('getPrioData', getPrioData)

local function isInQueue(ids)
    local identifier = ids[Config.Identifier]
    local qpos, qdata = nil, nil
    for pos, data in ipairs(queuelist) do
        if data.id == identifier then
            qpos, qdata = pos, data
            break
        end
    end
    return qpos, qdata
end exports('isInQueue', isInQueue)

local function setQueuePos(identifier, newPos)
    if newPos <= 0 or newPos > #queuelist then return false end
    if not queuepositions[identifier] then return false end
    local currentPos = queuepositions[identifier]
    local data = queuelist[currentPos]
    if not data then return false end
    table.remove(queuelist, currentPos)
    table.insert(queuelist, newPos, data)
    queuepositions[identifier] = newPos

    return true
end exports('setQueuePos', setQueuePos)

local function getQueuePos(identifier)
    return queuepositions[identifier]
end exports('getQueuePos', getQueuePos)

local function updateQueuePositions()
    for k, v in ipairs(queuelist) do
        if k ~= queuepositions[v.id] then
            queuepositions[v.id] = k
        end
    end
    return true
end

local function addToQueue(ids, points)
    local index = #queuelist + 1
    local currentTime = os.time()
    local data = { id = ids[Config.Identifier], ids = ids, points = points, qTime = function() return (os.time()-currentTime) end }
    local newPos = index
    for pos, data in ipairs(queuelist) do
        if data.points >= points then
            newPos = pos + 1
        else
            newPos = pos
            break
        end
    end
    table.insert(queuelist, newPos, data)
    updateQueuePositions()

    return data
end

local function removeFromQueue(ids)
    local identifier = ids[Config.Identifier]
    for pos, data in ipairs(queuelist) do
        if identifier == data.id then
            queuepositions[identifier] = nil
            table.remove(queuelist, pos)
            updateQueuePositions()
            return true
        end
    end

    return false
end

local function isInConnecting(identifier)
    for pos, data in ipairs(connectinglist) do
        if identifier == data.id then
            return true, pos
        end
    end
    return false, false
end

local function addToConnecting(source, identifiers)
    if not source or not identifiers then return end
    local currentTime = os.time()
    local identifier = identifiers[Config.Identifier]
    local isConnecting, position = isInConnecting(identifier)
    if isConnecting then
        connectinglist[position] = {
            source = source,
            id = identifier,
            timeout = 0,
            cTime = function() return (os.time()-currentTime) end
        }
    else
        local index = #connectinglist + 1
        local cData = {
            source = source,
            id = identifier,
            timeout = 0,
            cTime = function() return (os.time()-currentTime) end
        }
        table.insert(connectinglist, index, cData)
    end
    removeFromQueue(identifiers)
end

local function removeFromConnecting(identifier)
    for pos, data in ipairs(connectinglist) do
        if identifier == data.id then
            table.remove(connectinglist, pos)
            break
        end
    end
end

local function canJoin()
    return ((#connectinglist + playercount) < MaxPlayers)
end exports('canJoin', canJoin)

local function getIdentifiers(src)
    if not src then return nil end
    local identifiers = {}
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        local index = tostring(id:match("(%w+):"))
        identifiers[index] = id
    end
    return identifiers
end

AddEventHandler("playerConnecting", function(playerName, setKickReason, deferrals)
    deferrals.defer()
    local source = source
    local identifiers = getIdentifiers(source)

    if isInConnecting(identifiers[Config.Identifier]) then
        removeFromConnecting(identifiers[Config.Identifier])
        Wait(500)
    end

    if Config.AntiSpam.enabled then
        deferrals.update(Lang.please_wait)
        Wait(math.random(Config.AntiSpam.time, Config.AntiSpam.time + 5000))
    end

    deferrals.update(Lang.checking_identifiers)
    if not identifiers then
        deferrals.done(Lang.ids_doesnt_exist)
        CancelEvent()
        return
    end

    for _, id in ipairs(Config.RequiredIdentifiers) do
        if not identifiers[id] then
            deferrals.done(string.format(Lang.id_doesnt_exist, id))
            CancelEvent()
            return
        end
    end

    deferrals.update(Lang.checking_roles)

    if Config.Discord.enabled then
        DebugPrint("^3[DEBUG] Fetching Discord roles for: " .. (identifiers['discord'] or "No Discord ID"))
    
        local playerroles = GetUserRoles(identifiers['discord'])
    
        if not playerroles or type(playerroles) ~= "table" then
            DebugPrint("^1[ERROR] No Discord roles found or invalid format for: " .. (identifiers['discord'] or "No Discord ID"))
            deferrals.done(Lang.join_discord)
            CancelEvent()
            return
        end
    
        DebugPrint("^3[DEBUG] Discord roles received: " .. json.encode(playerroles))
    
        local cIdentifier = identifiers[Config.Identifier]
        
        if not prioritydata[cIdentifier] then 
            prioritydata[cIdentifier] = { points = 0, name = "No Role" }
        end
    
        local whitelisted = false
        local totalPoints = 0

        for _, role in pairs(playerroles) do
            if Config.Discord.roles[role] then
                local rolePoints = Config.Discord.roles[role].points or 0
                totalPoints = totalPoints + rolePoints
                prioritydata[cIdentifier].name = Config.Discord.roles[role].name
                whitelisted = true
            end
        end

        prioritydata[cIdentifier].points = totalPoints

        DebugPrint("^3[DEBUG] Total priority points assigned: " .. prioritydata[cIdentifier].points)
    
        if not whitelisted then
            DebugPrint("^1[ERROR] Player not whitelisted due to missing roles: " .. playerName)
            deferrals.done(Lang.not_whitelisted)
            CancelEvent()
            return
        end

        if Config.ReconnectPrio.enabled and reconnectlist[cIdentifier] then
            prioritydata[cIdentifier].points = prioritydata[cIdentifier].points + Config.ReconnectPrio.points
            DebugPrint("^3[DEBUG] Reconnect priority added: " .. Config.ReconnectPrio.points)
        end
    end

    if canJoin() then
        addToConnecting(source, identifiers)

        local displayCard = updateCard({pos=1, maxpos=1, points=prioritydata[identifiers[Config.Identifier]].points}, source)
        deferrals.presentCard(displayCard, function(data, rawdata) end)
        Wait(10000) ---< ADJUST TO KEEP CARD VISIBLE LONGER(MILLISECONDS) >---
        deferrals.done()
        CancelEvent()
        return
    end

    if isInQueue(identifiers) then
        deferrals.done(Lang.already_in_queue)
        CancelEvent()
        return
    end

    local data = addToQueue(identifiers, prioritydata[identifiers[Config.Identifier]].points)
    if not data then
        deferrals.done(Lang.could_not_connect)
        CancelEvent()
        return
    end

    while data and queuepositions[data.id] do
        Wait(3000)

        if queuepositions[data.id] <= 1 and canJoin() then
            addToConnecting(source, data.ids)
            deferrals.update(Lang.joining_now)
            Wait(1000)
            deferrals.done()
            CancelEvent()
            return
        end

        local endpoint = GetPlayerEndpoint(source)
        if not endpoint then
            removeFromQueue(data.ids)
            deferrals.done(Lang.timed_out)
            CancelEvent()
            return
        end

        local displayCard = updateCard({pos=queuepositions[data.id], maxpos=#queuelist, qTime = data.qTime, points = prioritydata[data.id].points}, source)
        deferrals.presentCard(displayCard, function(data, rawdata) end)
    end

    deferrals.done()
end)

CreateThread(function()
    while true do
        Wait(5000)
        if #connectinglist < 1 then goto skipLoop end
        for pos, data in ipairs(connectinglist) do
            local endpoint = GetPlayerEndpoint(data.source)
            if not endpoint or data.cTime() >= Config.Timeout then
                removeFromConnecting(data.id)
                DebugPrint(string.format('%s has been timed out while connecting to server', data.id))
            end
        end
        ::skipLoop::
        local currentTime = os.time()
        for identifier, expire in pairs(reconnectlist) do
            if expire < currentTime then
                reconnectlist[identifier] = nil
            end
        end
    end
end)

AddEventHandler("playerJoining", function(source, oldid)
    local identifiers = getIdentifiers(source)

    playercount = playercount + 1
    removeFromConnecting(identifiers[Config.Identifier])
end)

AddEventHandler("playerDropped", function()
    local source = source
    local identifiers = getIdentifiers(source)
    playercount = playercount - 1

    if Config.ReconnectPrio.enabled then
        reconnectlist[identifiers[Config.Identifier]] = os.time() + (Config.ReconnectPrio.time * 60)
    end
end)

AddEventHandler('onResourceStart', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    local playerPool = GetPlayers()
    playercount = #playerPool
    DebugPrint('Players: '..playercount)
end)

local function getQueueCount()
    return queuelist
end exports('getQueueCount', getQueueCount)
