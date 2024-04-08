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
		local jobs = {}
		for _, mapping in ipairs(rankMappings.mappings) do
			for _, r in ipairs(mapping.ranks) do
				if r == rank then
					table.insert(jobs, {
						job = mapping.job,
						rank = mapping.rank
					})
				end
			end
		end
		return jobs -- Return nil if the rank is not found
	end
	RegisterNetEvent('sonoran_jobsync::rankupdate', function(data)
		local ppermissiondata = data.data.ranks
		local identifier = data.data.activeApiIds
		if Config.apiIdType == 'discord' then
			table.insert(identifier, data.data.discordId)
		end
		if data.key == Config.APIKey then
			for _, g in pairs(identifier) do
				if loaded_list[g] ~= nil then
					for k, v in pairs(loaded_list[g]) do
						local has = false
						if ppermissiondata[k] then
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
			if #ppermissiondata > 0 then
				print('1')
				for _, v in pairs(ppermissiondata) do
					if #findJobByRank(v) > 0 then
						print('2')
						for _, b in pairs(identifier) do
							for _, x in pairs(findJobByRank(v)) do
								local playerSource = getPlayerFromID(b)
								if playerSource ~= nil then
									print('Player source: ' .. playerSource)
									if Config.debug_mode then
										infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. playerSource .. ' ' .. x.job .. ' ' .. x.rank)
									end
									print('setjob ' .. playerSource .. ' ' .. x.job .. ' ' .. x.rank)
									ExecuteCommand('setjob ' .. playerSource .. ' ' .. x.job .. ' ' .. x.rank)
									if loaded_list[b] == nil then
										loaded_list[b] = {
											[v] = {
												job = x.job,
												rank = x.rank
											}
										}
									else
										loaded_list[b][v] = {
											job = x.job,
											rank = x.rank
										}
									end
								end
								if Config.offline_cache then
									if cache[b] == nil then
										cache[b] = {
											[v] = {
												apiID = b,
												jobData = x
											}
										}
										SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
									else
										cache[b][v] = {
											identifier = b,
											jobData = x
										}
										SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
									end
								end
							end
						end
					end
				end
			end
		end
	end)
	RegisterNetEvent('SonoranCms:JobSync:PlayerSpawned', function()
		local identifier
		local source = source
		for _, v in pairs(GetPlayerIdentifiers(source)) do
			if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
				identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
			end
		end
		local payload = {}
		payload['id'] = Config.CommID
		payload['key'] = Config.APIKey
		payload['type'] = 'GET_ACCOUNT_RANKS'
		if Config.apiIdType == 'discord' then
			payload['discord'] = identifier
		else
			payload['apiId'] = identifier
		end
		if identifier == nil then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Player ' .. GetPlayerName(source) .. ' was denied access due to not having a ' .. Config.apiIdType .. ' identifier.')
			return
		end
		local reqData = {}
		if Config.apiIdType == 'discord' then
			reqData['discord'] = identifier
		else
			reqData['apiId'] = identifier
		end
		exports['sonorancms']:performApiRequest({
			reqData
		}, 'GET_ACCOUNT_RANKS', function(res)
			if #res > 2 then
				local ppermissiondata = json.decode(res)
				if loaded_list[identifier] ~= nil then
					for k, _ in pairs(loaded_list[identifier]) do
						local has = false
						for _, b in pairs(ppermissiondata) do
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
					if #findJobByRank(v) > 0 then
						for _, x in pairs(findJobByRank(v)) do
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. source .. ' ' .. x.job .. ' ' .. x.rank)
							end
							ExecuteCommand('setjob ' .. source .. ' ' .. x.job .. ' ' .. x.rank)
							if loaded_list[identifier] == nil then
								loaded_list[identifier] = {
									[v] = {
										job = x.job,
										rank = x.rank
									}
								}
							else
								loaded_list[identifier][v] = {
									job = x.job,
									rank = x.rank
								}
							end
							if Config.offline_cache then
								local playerApiID = getPlayerapiID(source)
								if playerApiID ~= nil then
									local foundJobs = findJobByRank(v)
									for _, y in pairs(foundJobs) do
										if cache[identifier] == nil then
											cache[identifier] = {
												[v] = {
													apiID = playerApiID,
													jobData = y
												}
											}
											SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
										else
											cache[identifier][v] = {
												apiID = playerApiID,
												jobData = y
											}
											SaveResourceFile(GetCurrentResourceName(), '/server/modules/jobsync/jobsync_cache.json', json.encode(cache))
										end
									end
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
							local jobs = findJobByRank(v)
							for _, x in pairs(jobs) do
								ExecuteCommand(v)
								if loaded_list[identifier] == nil then
									loaded_list[identifier] = {
										[v] = {
											job = x.job,
											rank = x.rank
										}
									}
								else
									loaded_list[identifier][v] = {
										job = x.job,
										rank = x.rank
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
	RegisterCommand('refreshjob', function(src, _, _)
		local source = src
		local identifier
		for _, v in pairs(GetPlayerIdentifiers(src)) do
			if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
				identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
			end
		end
		local payload = {}
		payload['id'] = Config.CommID
		payload['key'] = Config.APIKey
		payload['type'] = 'GET_ACCOUNT_RANKS'
		if Config.apiIdType == 'discord' then
			payload['discord'] = identifier
		else
			payload['apiId'] = identifier
		end
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
		local reqData = {}
		if Config.apiIdType == 'discord' then
			reqData['discord'] = identifier
		else
			reqData['apiId'] = identifier
		end
		exports['sonorancms']:performApiRequest({
			reqData
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
					if #findJobByRank(v) > 0 then
						for _, x in pairs(findJobByRank(v)) do
							if Config.debug_mode then
								infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. src .. ' ' .. x.job .. ' ' .. x.rank)
							end
							ExecuteCommand('setjob ' .. src .. ' ' .. x.job .. ' ' .. x.rank)
							if loaded_list[identifier] == nil then
								loaded_list[identifier] = {
									[v] = {
										job = x.job,
										rank = x.rank
									}
								}
							else
								loaded_list[identifier][v] = {
									job = x.job,
									rank = x.rank
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
								for _, x in pairs(findJobByRank(v)) do
									if Config.debug_mode then
										infoLog('Push event recieved, executing the following command: ' .. 'setjob ' .. playerSource .. ' ' .. x.job .. ' ' .. x.rank)
									end
									ExecuteCommand('setjob ' .. playerSource .. ' ' .. v.jobData.job .. ' ' .. v.jobData.rank)
									if loaded_list[identifier] == nil then
										loaded_list[identifier] = {
											[v] = {
												job = x.job,
												rank = x.rank
											}
										}
									else
										loaded_list[identifier][v] = {
											job = x.job,
											rank = x.rank
										}
									end
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
