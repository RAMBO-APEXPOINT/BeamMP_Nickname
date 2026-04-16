-- NicknameMod | Server/NicknameMod/main.lua

local nickDB = {}   -- { ["0"] = "nick" }  clés STRING
local nameDB = {}   -- { ["0"] = "guest..." }

local MIN_LEN, MAX_LEN = 2, 20

local function idKey(playerID) return tostring(playerID) end

local function isValidNick(nick)
    if type(nick) ~= "string" then return false, "Invalid value." end
    nick = nick:match("^%s*(.-)%s*$")
    if #nick < MIN_LEN then return false, "Nickname too short (min "..MIN_LEN.." chars)." end
    if #nick > MAX_LEN then return false, "Nickname too long (max "..MAX_LEN.." chars)." end
    if not nick:match("^[%w%-_%.]+$") then return false, "Invalid characters. Use letters, digits, - _ ." end
    return true, nick
end

local function notify(playerID, msg) MP.SendChatMessage(playerID, msg) end

local function sendBulkTo(playerID)
    local nickJson = Util.JsonEncode(nickDB)
    local nameJson = Util.JsonEncode(nameDB)
    print("[NicknameMod] sendBulkTo player "..playerID.." | nickDB="..nickJson)
    MP.TriggerClientEvent(playerID, "nickBulk",    nickJson)
    MP.TriggerClientEvent(playerID, "nativeNames", nameJson)
end

local function broadcastBulk()
    -- Envoyer nickBulk+nativeNames à TOUS les joueurs connectés
    local allPlayers = MP.GetPlayers()
    for pid, _ in pairs(allPlayers) do
        sendBulkTo(pid)
    end
end

local function broadcastNick(playerID, nick)
    local payload = Util.JsonEncode({
        id = playerID, nick = nick, nativeName = nameDB[idKey(playerID)] or ""
    })
    print("[NicknameMod] broadcastNick -> all | "..payload)
    MP.TriggerClientEvent(-1, "nickSet", payload)
end

local function broadcastRemove(playerID)
    MP.TriggerClientEvent(-1, "nickRemove", Util.JsonEncode({id = playerID}))
end

local function setNick(playerID, rawNick)
    local ok, result = isValidNick(rawNick)
    if not ok then notify(playerID, "[Nickname] "..result); return end
    local nick = result
    for id, existing in pairs(nickDB) do
        if id ~= idKey(playerID) and existing:lower() == nick:lower() then
            notify(playerID, "[Nickname] This nickname is already in use."); return
        end
    end
    nickDB[idKey(playerID)] = nick
    broadcastNick(playerID, nick)
    notify(playerID, "[Nickname] Nickname set: "..nick)
    print("[NicknameMod] nickDB now: "..Util.JsonEncode(nickDB))
end

local function resetNick(playerID)
    if nickDB[idKey(playerID)] then
        nickDB[idKey(playerID)] = nil
        broadcastRemove(playerID)
        notify(playerID, "[Nickname] Nickname removed.")
    else
        notify(playerID, "[Nickname] You don't have a nickname.")
    end
end

function onPlayerJoining(playerID)
    local nativeName = MP.GetPlayerName(playerID) or ("player"..playerID)
    nameDB[idKey(playerID)] = nativeName
    nickDB[idKey(playerID)] = nil
    print("[NicknameMod] onPlayerJoining: player "..playerID.." ("..nativeName..") | nickDB="..Util.JsonEncode(nickDB))
    MP.TriggerClientEvent(-1, "nativeNames", Util.JsonEncode({[idKey(playerID)] = nativeName}))
    sendBulkTo(playerID)
    notify(playerID, "[Nickname] Welcome! Set your nickname with: !setname YourName")
    notify(playerID, "[Nickname] Other commands: !resetname | !myname | !nickhelp")
end

function onVehicleSpawn(playerID, vehicleID, vehicleData)
    -- Quand un véhicule spawne, BeamMP recrée players[ownerID] avec
    -- le nom natif sur TOUS les clients connectés.
    -- → envoyer nickBulk à TOUS pour qu'ils ré-appliquent leurs nicks.
    print("[NicknameMod] onVehicleSpawn: player "..playerID.." veh="..tostring(vehicleID).." -> broadcastBulk")
    broadcastBulk()
end

function onPlayerDisconnect(playerID, name, reason)
    if nickDB[idKey(playerID)] then nickDB[idKey(playerID)] = nil; broadcastRemove(playerID) end
    nameDB[idKey(playerID)] = nil
    print("[NicknameMod] onPlayerDisconnect: player "..playerID)
end

function onChatMessage(playerID, playerName, message)
    if not message then return end
    local cmd, args = message:match("^(!%S+)%s*(.*)")
    if cmd then
        cmd = cmd:lower()
        if cmd == "!setname" or cmd == "!name" then
            if args == "" then notify(playerID, "[Nickname] Usage: !setname YourNickname")
            else setNick(playerID, args) end; return 1
        elseif cmd == "!resetname" then resetNick(playerID); return 1
        elseif cmd == "!myname" then
            local n = nickDB[idKey(playerID)]
            if n then notify(playerID, "[Nickname] Your nickname: "..n)
            else notify(playerID, "[Nickname] No nickname. Use !setname YourNickname") end; return 1
        elseif cmd == "!nickhelp" then
            notify(playerID, "[Nickname] Commands: !setname <n>  |  !resetname  |  !myname"); return 1
        end
    end
    local nick = nickDB[idKey(playerID)]
    if nick then MP.SendChatMessage(-1, "["..nick.."] : "..message); return 1 end
end

function onNickCmd(playerID, jsonData)
    if not jsonData then return end
    local ok, data = pcall(Util.JsonDecode, jsonData)
    if not ok or type(data) ~= "table" then return end
    print("[NicknameMod] onNickCmd player "..playerID.." cmd="..tostring(data.cmd))
    if data.cmd == "set" then setNick(playerID, data.nick or "")
    elseif data.cmd == "reset" then resetNick(playerID)
    elseif data.cmd == "requestAll" then sendBulkTo(playerID)
    end
end

MP.RegisterEvent("onPlayerJoining",    "onPlayerJoining")
MP.RegisterEvent("onVehicleSpawn",     "onVehicleSpawn")
MP.RegisterEvent("onPlayerDisconnect", "onPlayerDisconnect")
MP.RegisterEvent("onChatMessage",      "onChatMessage")
MP.RegisterEvent("nickCmd",            "onNickCmd")

print("[NicknameMod] Loaded.")