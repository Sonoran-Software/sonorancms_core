local cache = {}
local loaded_list = {}

local function errorLog(message)
    return print(
               '^1[ERROR - Sonoran CMS Ace Perms - ' .. os.date('%c') .. ' ' ..
                   message .. '^0');
end

local function infoLog(message)
    return print('[INFO - Sonoran CMS Ace Perms - ' .. os.date('%c') .. ' ' ..
                     message .. '^0');
end

local function wait(seconds) os.execute('sleep ' .. tonumber(seconds)) end

local function getPlayerFromID(apiId)
    local players = GetPlayers()
    for _, v in ipairs(players) do
        local player = tonumber(v)
        local identifier = nil
        for _, g in pairs(GetPlayerIdentifiers(player)) do
            if string.sub(g, 1, string.len(Config.apiIdType .. ':')) ==
                Config.apiIdType .. ':' then
                identifier = string.sub(g,
                                        string.len(Config.apiIdType .. ':') + 1)
            end
        end
        if identifier == apiId then return player end
    end
end

local function getPlayerapiID(source)
    local identifier = nil
    for _, g in pairs(GetPlayerIdentifiers(source)) do
        if string.sub(g, 1, string.len(Config.apiIdType .. ':')) ==
            Config.apiIdType .. ':' then
            identifier = string.sub(g, string.len(Config.apiIdType .. ':') + 1)
            if identifier ~= nil then return identifier end
        end
    end
end

function initialize()
    cache =
        json.decode(LoadResourceFile(GetCurrentResourceName(), 'cache.json'))
    local rankMappings = json.decode(LoadResourceFile(GetCurrentResourceName(),
                                                      '/server/modules/jobsync/jobsync_config.json'))
    local function findRankByJob(job, grade, duty)
        local ranks = {add = {}, remove = {}}
        for _, mapping in ipairs(rankMappings.mappings) do
            if mapping.job == job and mapping.rank == grade and duty then
                for _, r in ipairs(mapping.ranks) do
                    table.insert(ranks.add, r)
                end
            else
                for _, r in ipairs(mapping.ranks) do
                    table.insert(ranks.remove, r)
                end
            end
        end
        return ranks -- Return nil if the rank is not found
    end
    RegisterNetEvent('SonoranCms:JobSync:PlayerSpawned', function()
        local identifier
        local source = source
        for _, v in pairs(GetPlayerIdentifiers(source)) do
            if string.sub(v, 1, string.len(Config.apiIdType .. ':')) ==
                Config.apiIdType .. ':' then
                identifier = string.sub(v,
                                        string.len(Config.apiIdType .. ':') + 1)
            end
        end
        local QBCore = exports['qb-core']:GetCoreObject()
        local QBChar = QBCore.Functions.GetPlayer(source)
        local job = QBChar.PlayerData.job.name
        local grade = QBChar.PlayerData.job.grade
        local onduty = QBChar.PlayerData.job.onduty or false
        local ranks = findRankByJob(job, grade.level, onduty)
        local payload = {data = {}}
        if Config.apiIdType == 'discord' then
            payload['discord'] = identifier
        else
            payload['apiId'] = identifier
        end
        if identifier == nil then
            TriggerEvent('SonoranCMS::core:writeLog', 'warn',
                         'Unable to set job for ' .. GetPlayerName(source) ..
                             ' due to missing ' .. Config.apiIdType ..
                             ' identifier.')
            return
        end
        if #ranks.add > 0 then payload['add'] = ranks.add end
        if #ranks.remove > 0 then
            payload['remove'] = ranks.remove
        end
        exports['sonorancms']:performApiRequest({payload}, 'SET_ACCOUNT_RANKS',
                                                function(res, success)
            res = json.decode(res)
            if not success then
                TriggerEvent('SonoranCMS::core:writeLog', 'error',
                             'Failed to set job for ' .. GetPlayerName(source) ..
                                 ' (' .. identifier .. ') - ' .. json.encode(res))
            end
        end)
    end)
    RegisterNetEvent('SonoranCms:JobSync:JobUpdate', function()
        local identifier
        local source = source
        for _, v in pairs(GetPlayerIdentifiers(source)) do
            if string.sub(v, 1, string.len(Config.apiIdType .. ':')) ==
                Config.apiIdType .. ':' then
                identifier = string.sub(v,
                                        string.len(Config.apiIdType .. ':') + 1)
            end
        end
        local QBCore = exports['qb-core']:GetCoreObject()
        local QBChar = QBCore.Functions.GetPlayer(source)
        local job = QBChar.PlayerData.job.name
        local grade = QBChar.PlayerData.job.grade
        local onduty = QBChar.PlayerData.job.onduty or false
        local ranks = findRankByJob(job, grade.level, onduty)
        local payload = {data = {}}
        if Config.apiIdType == 'discord' then
            payload['discord'] = identifier
        else
            payload['apiId'] = identifier
        end
        if identifier == nil then
            TriggerEvent('SonoranCMS::core:writeLog', 'warn',
                         'Unable to set job for ' .. GetPlayerName(source) ..
                             ' due to missing ' .. Config.apiIdType ..
                             ' identifier.')
            return
        end
        if #ranks.add > 0 then payload['add'] = ranks.add end
        if #ranks.remove > 0 then
            payload['remove'] = ranks.remove
        end
        exports['sonorancms']:performApiRequest({payload}, 'SET_ACCOUNT_RANKS',
                                                function(res, success)
            res = json.decode(res)
            if not success then
                TriggerEvent('SonoranCMS::core:writeLog', 'error',
                             'Failed to set job for ' .. GetPlayerName(source) ..
                                 ' (' .. identifier .. ') - ' .. json.encode(res))
            end
        end)
    end)
end
local function getRankList()
    local config = LoadResourceFile(GetCurrentResourceName(),
                                    '/server/modules/jobsync/jobsync_config.json')
    if config == nil then
        errorLog('Unable to load jobsync_config.json')
        return {}
    end
    return config
end
exports('getRankListJobSync', getRankList)

local function setRankList(data)
    local rankData = {}
    rankData.mappings = data
    SaveResourceFile(GetCurrentResourceName(),
                     '/server/modules/jobsync/jobsync_config.json',
                     json.encode(rankData))
    Wait(2000)
    initialize();
end
exports('setRankListJobSync', setRankList)
initialize();
