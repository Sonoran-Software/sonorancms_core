local cache = {}
local loaded_list = {}

local function errorLog(message)
	return print('^1[ERROR - Sonoran CMS Ace Perms - ' .. os.date('%c') .. ' ' .. message .. '^0');
end

local function infoLog(message)
	return print('[INFO - Sonoran CMS Ace Perms - ' .. os.date('%c') .. ' ' .. message .. '^0');
end

local function wait(seconds)
	os.execute('sleep ' .. tonumber(seconds))
end

local function getPlayerFromID(apiId)
	local players = GetPlayers()
	for _, v in ipairs(players) do
		local player = tonumber(v)
		local identifier = nil
		for _, g in pairs(GetPlayerIdentifiers(player)) do
			if string.sub(g, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
				identifier = string.sub(g, string.len(Config.apiIdType .. ':') + 1)
			end
		end
		if identifier == apiId then
			return player
		end
	end
end

local function getPlayerapiID(source)
	local identifier = nil
	for _, g in pairs(GetPlayerIdentifiers(source)) do
		if string.sub(g, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
			identifier = string.sub(g, string.len(Config.apiIdType .. ':') + 1)
			if identifier ~= nil then
				return identifier
			end
		end
	end
end

function initialize()
	cache = json.decode(LoadResourceFile(GetCurrentResourceName(), 'cache.json'))
	local rankMappings = json.decode(LoadResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_config.json'))
	local function findJobByRank(rank)
		for _, mapping in ipairs(rankMappings.mappings) do
			for _, r in ipairs(mapping.ranks) do
				if r == rank then
					return {
						job = mapping.job,
						rank = mapping.rank
					}
				end
			end
		end
		return nil -- Return nil if the rank is not found
	end
	TriggerEvent('sonorancms::RegisterPushEvent', 'ACCOUNT_UPDATED', function()
		TriggerEvent('sonoran_permissions::rankupdate')
	end)
	RegisterNetEvent('sonoran_jobsync::rankupdate', function(data)
		local ppermissiondata = data.data.primaryRank
		local ppermissiondatas = data.data.secondaryRanks
		local identifier = data.data.activeApiIds
		if data.key == Config.apiKey then
			for _, g in pairs(identifier) do
				if loaded_list[g] ~= nil then
					for k, v in pairs(loaded_list[g]) do
						local has = false
						for _, b in pairs(ppermissiondatas) do
							if b == k then
								has = true
							end
						end
						if ppermissiondata == v then
							has = true
						end
						if not has then
							loaded_list[g][k] = nil
							local playerSource = getPlayerFromID(g)
							if playerSource ~= nil then
								if Config.debug_mode then
									infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. playerSource .. ' unemployed 0')
								end
								ExecuteCommand('setjob ' .. playerSource .. ' unemployed 0')
							end
							if Config.offline_cache then
								cache[g][k] = nil
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
							end
						end
					end
				end
			end
			if ppermissiondata ~= '' or ppermissiondata ~= nil then
				if findJobByRank(ppermissiondata) ~= nil then
					for _, b in pairs(identifier) do
						local playerSource = getPlayerFromID(b)
						if playerSource ~= nil then
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. playerSource .. ' ' .. findJobByRank(ppermissiondata).job .. ' ' .. findJobByRank(ppermissiondata).rank)
							end
							ExecuteCommand('setjob ' .. playerSource .. ' ' .. findJobByRank(ppermissiondata).job .. ' ' .. findJobByRank(ppermissiondata).rank)
							if loaded_list[b] == nil then
								loaded_list[b] = {
									[ppermissiondata] = {
										job = findJobByRank(ppermissiondata).job,
										rank = findJobByRank(ppermissiondata).rank
									}
								}
							else
								loaded_list[b][ppermissiondata] = {
									job = findJobByRank(ppermissiondata).job,
									rank = findJobByRank(ppermissiondata).rank
								}
							end
						end
						if Config.offline_cache then
							if cache[b] == nil then
								cache[b] = {
									[ppermissiondata] = {
										apiID = b,
										jobData = findJobByRank(ppermissiondata)
									}
								}
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
							else
								cache[b][ppermissiondata] = {
									identifier = b,
									jobData = findJobByRank(ppermissiondata)
								}
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
							end
						end
					end
				end
			end
			if ppermissiondatas ~= nil then
				for _, v in pairs(ppermissiondatas) do
					if findJobByRank(v) ~= nil then
						for _, b in pairs(identifier) do
							local playerSource = getPlayerFromID(b)
							if playerSource ~= nil then
								if Config.debug_mode then
									infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. playerSource .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
								end
								ExecuteCommand('setjob ' .. playerSource .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
								if loaded_list[b] == nil then
									loaded_list[b] = {
										[v] = {
											job = findJobByRank(v).job,
											rank = findJobByRank(v).rank
										}
									}
								else
									loaded_list[b][v] = findJobByRank(v)
								end
							end
							if Config.offline_cache then
								if cache[b] == nil then
									cache[b] = {
										[v] = {
											apiID = b,
											jobData = findJobByRank(v)
										}
									}
									SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
								else
									cache[b][v] = {
										apiID = b,
										jobData = findJobByRank(v)
									}
									SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
								end
							end
						end
					end
				end
			end
		end
	end)

	AddEventHandler('playerConnecting', function(name, setKickReason, deferrals)
		local source = source
		deferrals.defer();
		Wait(0)
		deferrals.update('Grabbing API ID and getting your permissions...')
		local identifier
		for _, v in pairs(GetPlayerIdentifiers(source)) do
			if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
				identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
			end
		end
		if identifier == nil then
			deferrals.done('You must have a ' .. Config.apiIdType .. ' identifier to join this server.')
			TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Player ' .. GetPlayerName(source) .. ' was denied access due to not having a ' .. Config.apiIdType .. ' identifier.')
			return
		end
		exports['sonorancms']:performApiRequest({
			{
				['apiId'] = identifier
			}
		}, 'GET_ACCOUNT_RANKS', function(res)
			if #res > 2 then
				local ppermissiondata = json.decode(res)
				if loaded_list[identifier] ~= nil then
					for k, v in pairs(loaded_list[identifier]) do
						local has = false
						for l, b in pairs(ppermissiondata) do
							if b == k then
								has = true
							end
						end
						if not has then
							loaded_list[identifier][k] = nil
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. source .. ' unemployed 0')
							end
							ExecuteCommand('setjob ' .. source .. ' unemployed 0')
							if Config.offline_cache then
								cache[identifier][k] = nil
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
							end
						end
					end
				end
				for _, v in pairs(ppermissiondata) do
					if findJobByRank(v) ~= nil then
						if Config.debug_mode then
							infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. source .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
						end
						ExecuteCommand('setjob ' .. source .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
						if loaded_list[identifier] == nil then
							loaded_list[identifier] = {
								[v] = {
									job = findJobByRank(v).job,
									rank = findJobByRank(v).rank
								}
							}
						else
							loaded_list[identifier][v] = {
								job = findJobByRank(v).job,
								rank = findJobByRank(v).rank
							}
						end
						if Config.offline_cache then
							local playerApiID = getPlayerapiID(source)
							if playerApiID ~= nil then
								if cache[identifier] == nil then
									cache[identifier] = {
										[v] = {
											apiID = playerApiID,
											jobData = findJobByRank(v)
										}
									}
									SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
								else
									cache[identifier][v] = {
										apiID = playerApiID,
										jobData = findJobByRank(v)
									}
									SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
								end
							end
						end
					end
				end
				deferrals.done()
			elseif Config.offline_cache then
				if cache[identifier] ~= nil then
					for _, v in pairs(cache[identifier]) do
						if string.sub(v, 1, string.len('')) == 'setjob' then
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. v)
							end
							ExecuteCommand(v)
							if loaded_list[identifier] == nil then
								loaded_list[identifier] = {
									[v] = {
										job = findJobByRank(v).job,
										rank = findJobByRank(v).rank
									}
								}
							else
								loaded_list[identifier][v] = {
									job = findJobByRank(v).job,
									rank = findJobByRank(v).rank
								}
							end
						end
					end
				end
				deferrals.done()
			end
		end, 'POST', json.encode({
			id = communityId,
			key = Config.apiKey,
			type = 'GET_ACCOUNT_RANKS',
			data = {
				{
					apiId = identifier
				}
			}
		}), {
			['Content-Type'] = 'application/json'
		})
	end)

	RegisterCommand('refreshjob', function(src, _, _)
		local identifier
		for _, v in pairs(GetPlayerIdentifiers(src)) do
			if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
				identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
			end
		end
		local payload = {}
		payload['id'] = communityId
		payload['key'] = Config.apiKey
		payload['type'] = 'GET_ACCOUNT_RANKS'
		payload['data'] = {
			{
				['apiId'] = identifier
			}
		}
		if identifier == nil then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Player ' .. GetPlayerName(src) .. ' was denied access due to not having a ' .. Config.apiIdType .. ' identifier.')
			TriggerClientEvent('chat:addMessage', src, {
				color = {
					255,
					0,
					0
				},
				multiline = true,
				args = {
					'SonoranCMS',
					'You must have a ' .. Config.apiIdType .. ' identifier to use this command.'
				}
			})
			return
		end
		exports['sonorancms']:performApiRequest({
			{
				['apiId'] = identifier
			}
		}, 'GET_ACCOUNT_RANKS', function(res)
			if #res > 2 then
				local ppermissiondata = json.decode(res)
				if loaded_list[identifier] ~= nil then
					for k, v in pairs(loaded_list[identifier]) do
						local has = false
						for l, b in pairs(ppermissiondata) do
							if b == k then
								has = true
							end
						end
						if not has then
							loaded_list[identifier][k] = nil
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. source .. ' unemployed 0')
							end
							ExecuteCommand('setjob ' .. source .. ' unemployed 0')
							if Config.offline_cache then
								cache[identifier][k] = nil
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
							end
						end
					end
				end
				for _, v in pairs(ppermissiondata) do
					if findJobByRank(v) ~= nil then
						if Config.debug_mode then
							infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. src .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
						end
						ExecuteCommand('setjob ' .. src .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
						if loaded_list[identifier] == nil then
							loaded_list[identifier] = {
								[v] = {
									job = findJobByRank(v).job,
									rank = findJobByRank(v).rank
								}
							}
						else
							loaded_list[identifier][v] = {
								job = findJobByRank(v).job,
								rank = findJobByRank(v).rank
							}
						end
						if Config.offline_cache then
							local playerApiID = getPlayerapiID(source)
							if playerApiID ~= nil then
								if cache[identifier] == nil then
									cache[identifier] = {
										[v] = {
											apiID = playerApiID,
											jobData = findJobByRank(v)
										}
									}
									SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
								else
									cache[identifier][v] = {
										apiID = playerApiID,
										jobData = findJobByRank(v)
									}
									SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
								end
							end
						end
					end
				end
			elseif Config.offline_cache then
				if cache[identifier] ~= nil then
					for _, v in pairs(cache[identifier]) do
						if string.sub(v, 1, string.len('')) == 'setjob' then
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. v)
							end
							local playerSource = getPlayerFromID(v.apiId)
							if playerSource ~= nil then
								if Config.debug_mode then
									infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. playerSource .. ' ' .. findJobByRank(v).job .. ' ' .. findJobByRank(v).rank)
								end
								ExecuteCommand('setjob ' .. playerSource .. ' ' .. v.jobData.job .. ' ' .. v.jobData.rank)
								if loaded_list[identifier] == nil then
									loaded_list[identifier] = {
										[v] = {
											job = findJobByRank(v).job,
											rank = findJobByRank(v).rank
										}
									}
								else
									loaded_list[identifier][v] = {
										job = findJobByRank(v).job,
										rank = findJobByRank(v).rank
									}
								end
							end
						end
					end
				end
			end
		end, 'POST', json.encode(payload), {
			['Content-Type'] = 'application/json'
		})
	end)
end
local function getRankList()
	local config = LoadResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_config.json')
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
	SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_config.json', json.encode(rankData))
	Wait(2000)
	initialize();
end
exports('setRankListJobSync', setRankList)
initialize();
