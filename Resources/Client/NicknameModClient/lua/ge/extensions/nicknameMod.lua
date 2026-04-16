-- NicknameMod | lua/ge/extensions/nicknameMod.lua

local M = {}
local logTag = "nicknameMod"
local function logI(msg) log('I', logTag, msg) end
local function logW(msg) log('W', logTag, msg) end

local nickTable  = {}
local nameTable  = {}
local playersRef = nil

local function getPlayersRef()
    if playersRef then return playersRef end
    local mpvge = rawget(_G, "MPVehicleGE")
    if not mpvge then return nil end
    local fn = mpvge.setPlayerNickPrefix
    if type(fn) ~= "function" then return nil end
    local i = 1
    while i <= 20 do
        local ok, name, val = pcall(debug.getupvalue, fn, i)
        if not ok or name == nil then break end
        if name == "players" and type(val) == "table" then
            playersRef = val; return playersRef
        end
        i = i + 1
    end
    return nil
end

-- Applique les nicks manquants ou réinitialisés
local function applyAll()
    local p = getPlayersRef()
    if not p then return end
    for id, nick in pairs(nickTable) do
        local player = p[id]
        if player and player.name ~= nick then
            player.name = nick
            if player.shortname ~= nil then player.shortname = nick end
            logI(string.format("corrected players[%d].name = '%s'", id, nick))
        end
    end
end

-- ── Réception réseau ──────────────────────────────────────────────────────

local function onNickBulk(jsonData)
    logI("onNickBulk: "..tostring(jsonData))
    local ok, data = pcall(jsonDecode, jsonData)
    if not ok or type(data) ~= "table" then return end
    for idStr, nick in pairs(data) do
        local id = tonumber(idStr)
        if id ~= nil and type(nick) == "string" then
            nickTable[id] = nick
        end
    end
    applyAll()
end

local function onNickSet(jsonData)
    logI("onNickSet: "..tostring(jsonData))
    local ok, data = pcall(jsonDecode, jsonData)
    if not ok or type(data) ~= "table" then return end
    local id, nick, nativeName = tonumber(data.id), data.nick, data.nativeName
    if not id or type(nick) ~= "string" then return end
    nickTable[id] = nick
    if type(nativeName) == "string" and nativeName ~= "" then nameTable[id] = nativeName end
    applyAll()
    local myID = MPConfig and MPConfig.getPlayerServerID and MPConfig.getPlayerServerID() or nil
    if myID and myID == id then ui_message("[NicknameMod] Nickname: "..nick, 5, "info") end
end

local function onNickRemove(jsonData)
    local ok, data = pcall(jsonDecode, jsonData)
    if not ok or type(data) ~= "table" then return end
    local id = tonumber(data.id)
    if not id then return end
    nickTable[id] = nil
    local p = getPlayersRef()
    if p and p[id] then
        local native = nameTable[id] or p[id].name
        p[id].name = native
        if p[id].shortname ~= nil then p[id].shortname = native end
    end
end

local function onNativeNames(jsonData)
    local ok, data = pcall(jsonDecode, jsonData)
    if not ok or type(data) ~= "table" then return end
    for idStr, name in pairs(data) do
        local id = tonumber(idStr)
        if id ~= nil and type(name) == "string" then nameTable[id] = name end
    end
    applyAll()
end

local function sendRequestAll()
    TriggerServerEvent("nickCmd", jsonEncode({cmd = "requestAll"}))
end

-- ── Hooks ─────────────────────────────────────────────────────────────────

function M.onExtensionLoaded()
    logI("=== nicknameMod chargé ===")
    AddEventHandler("nickBulk",    onNickBulk)
    AddEventHandler("nickSet",     onNickSet)
    AddEventHandler("nickRemove",  onNickRemove)
    AddEventHandler("nativeNames", onNativeNames)
end

function M.onClientStartMission()
    playersRef   = nil
    M._initTimer = 3.0
    M._initDone  = false
end

function M.onUpdate(dt)
    -- Demande initiale
    if not M._initDone then
        M._initTimer = (M._initTimer or 3.0) - dt
        if M._initTimer <= 0 then
            M._initDone = true
            sendRequestAll()
        end
    end

    -- Surveillance continue à chaque frame
    -- Coût minimal : une lecture de table + comparaison de string par joueur avec nick
    if next(nickTable) ~= nil then
        applyAll()
    end
end

function M.onClientEndMission()
    nickTable  = {}
    nameTable  = {}
    playersRef = nil
    M._initTimer = nil
    M._initDone  = nil
end

M.getNick   = function(id) return nickTable[id] end
M.getMyNick = function()
    local id = MPConfig and MPConfig.getPlayerServerID and MPConfig.getPlayerServerID() or nil
    return id and nickTable[id] or nil
end

return M
