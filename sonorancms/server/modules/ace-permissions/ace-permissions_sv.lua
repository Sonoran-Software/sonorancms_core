local cache = {}
local rankMappings = {  -- Default empty mappings
    mappings = {}
}
local loaded_list = {}

local function setAcePermissionsCache()
	cache = json.decode(LoadResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json'))
	rankMappings = json.decode(LoadResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_config.json'))
end
local function findPrincipalByRank(rank)
	local principals = {}
	for _, mapping in ipairs(rankMappings.mappings) do
		for _, r in ipairs(mapping.ranks) do
			if r == rank then
				table.insert(principals, mapping.principal)
			end
		end
	end
	return principals -- Return nil if the rank is not found
end
RegisterNetEvent('sonoran_permissions::rankupdate', function(data)
	local ppermissiondata = data.data.ranks
	local identifier = data.data.activeApiIds
	if Config.apiIdType == 'discord' then
		table.insert(identifier, data.data.discordId)
	end
	if data.key == Config.APIKey then
		for _, g in pairs(identifier) do
			if loaded_list[g] ~= nil then
				for p, v in pairs(loaded_list[g]) do
					local has = false
					if ppermissiondata[p] then
						has = true
					end
					if not has then
						local toRemove = {}
						for i, x in pairs(v) do
							table.insert(toRemove, i)
							ExecuteCommand('remove_principal identifier.' .. Config.apiIdType .. ':' .. g .. ' ' .. x)
						end
						table.sort(toRemove, function(a, b)
							return a > b
						end)
						for _, i in ipairs(toRemove) do
							table.remove(v, i)
						end
						loaded_list[g][p] = nil
						if Config.offline_cache then
							cache[g][p] = nil
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						end
					end
				end
			end
		end
		if #ppermissiondata > 0 then
			for _, v in pairs(ppermissiondata) do
				if #findPrincipalByRank(v) > 0 then
					for _, b in pairs(identifier) do
						for _, x in pairs(findPrincipalByRank(v)) do
							ExecuteCommand('add_principal identifier.' .. Config.apiIdType .. ':' .. b .. ' ' .. x)
							if loaded_list[b] == nil then
								loaded_list[b] = {
									[v] = {}
								}
								table.insert(loaded_list[b][v], x)
							else
								if loaded_list[b][v] == nil then
									loaded_list[b][v] = {}
								end
								table.insert(loaded_list[b][v], x)
							end
							if cache[b] == nil then
								cache[b] = {
									[v] = 'add_principal identifier.' .. Config.apiIdType .. ':' .. b .. ' ' .. x
								}
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
							else
								cache[b][v] = 'add_principal identifier.' .. Config.apiIdType .. ':' .. b .. ' ' .. x
								SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
							end
						end
					end
				end
			end
		end
	end
end)

AddEventHandler('playerConnecting', function(_, _, deferrals)
	deferrals.defer();
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
						ExecuteCommand('remove_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. v)
						if Config.offline_cache then
							cache[identifier][k] = nil
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						end
					end
				end
			end
			for _, v in pairs(ppermissiondata) do
				if #findPrincipalByRank(v) > 0 then
					for _, b in pairs(findPrincipalByRank(v)) do
						ExecuteCommand('add_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. b)
						if loaded_list[identifier] == nil then
							loaded_list[identifier] = {
								[v] = findPrincipalByRank(v)
							}
						else
							loaded_list[identifier][v] = findPrincipalByRank(v)
						end
						if cache[identifier] == nil then
							cache[identifier] = {
								[v] = 'add_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. b
							}
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						else
							cache[identifier][v] = 'add_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. b
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						end
					end
				end
			end
			deferrals.done()
		else
			if cache[identifier] ~= nil then
				for _, v in pairs(cache[identifier]) do
					local principals = findPrincipalByRank(v)
					if string.sub(v, 1, string.len('')) == 'add_principal' then
						ExecuteCommand(v)
						if loaded_list[identifier] == nil then
							loaded_list[identifier] = {
								[v] = findPrincipalByRank(v)
							}
						else
							loaded_list[identifier][v] = findPrincipalByRank(v)
						end
					end
				end
			end
			deferrals.done()
		end
	end)
end)

RegisterCommand('refreshpermissions', function(src, _, _)
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
				for p, v in pairs(loaded_list[identifier]) do
					local has = false
					if ppermissiondata[p] then
						has = true
					end
					if not has then
						local toRemove = {}
						for i, x in pairs(v) do
							table.insert(toRemove, i)
							ExecuteCommand('remove_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. x)
						end
						table.sort(toRemove, function(a, b)
							return a > b
						end)
						for _, i in ipairs(toRemove) do
							table.remove(v, i)
						end
						loaded_list[identifier][p] = nil
						if Config.offline_cache then
							cache[identifier][p] = nil
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						end
					end
				end
			end
			for _, v in pairs(ppermissiondata) do
				if #findPrincipalByRank(v) > 0 then
					for _, b in pairs(findPrincipalByRank(v)) do
						ExecuteCommand('add_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. b)
						if loaded_list[identifier] == nil then
							loaded_list[identifier] = {
								[v] = findPrincipalByRank(v)
							}
						else
							loaded_list[identifier][v] = findPrincipalByRank(v)
						end
						if cache[identifier] == nil then
							cache[identifier] = {
								[v] = 'add_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. b
							}
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						else
							cache[identifier][v] = 'add_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. b
							SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_cache.json', json.encode(cache))
						end
					end
				end
			end
		else
			if cache[identifier] ~= nil then
				for _, v in pairs(cache[identifier]) do
					local principals = findPrincipalByRank(v)
					if string.sub(v, 1, string.len('')) == 'add_principal' then
						ExecuteCommand(v)
						if loaded_list[identifier] == nil then
							loaded_list[identifier] = {
								[v] = findPrincipalByRank(v)
							}
						else
							loaded_list[identifier][v] = findPrincipalByRank(v)
						end
					end
				end
			end
		end
	end, 'POST', json.encode(payload), {
		['Content-Type'] = 'application/json'
	})
end)

RegisterCommand('permissiontest', function(src, args, _)
	if args[1] == nil then
		TriggerClientEvent('chat:addMessage', src, {
			color = {
				255,
				0,
				0
			},
			multiline = true,
			args = {
				'SonoranCMS',
				'Usage: /permissiontest [permission]'
			}
		})
		return
	end
	if IsPlayerAceAllowed(src, args[1]) then
		TriggerClientEvent('chat:addMessage', src, {
			color = {
				0,
				255,
				0
			},
			multiline = true,
			args = {
				'SonoranCMS',
				'true'
			}
		})
	else
		TriggerClientEvent('chat:addMessage', src, {
			color = {
				255,
				0,
				0
			},
			multiline = true,
			args = {
				'SonoranCMS',
				'false'
			}
		})
	end
end, false)

AddEventHandler('playerDropped', function()
	local src = source
	local identifier
	for _, v in pairs(GetPlayerIdentifiers(src)) do
		if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
			identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
		end
	end
	if loaded_list[identifier] ~= nil then
		for _, v in pairs(loaded_list[identifier]) do
			local toRemove = {}
			for i, x in pairs(v) do
				table.insert(toRemove, i)
				ExecuteCommand('remove_principal identifier.' .. Config.apiIdType .. ':' .. identifier .. ' ' .. x)
			end
			table.sort(toRemove, function(a, b)
				return a > b
			end)
			for _, i in ipairs(toRemove) do
				table.remove(v, i)
			end
		end
	end
end)
local function getRankList()
	local config = LoadResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_config.json')
	if config == nil then
		config = {}
	else
		config = config
	end
	return config
end
exports('getRankList', getRankList)

local function setRankList(data)
	local rankData = {}
	rankData.mappings = data
	SaveResourceFile(GetCurrentResourceName(), '/server/modules/ace-permissions/ace-permissions_config.json', json.encode(rankData))
	Wait(2000)
	setAcePermissionsCache();
end
exports('setRankList', setRankList)
setAcePermissionsCache();

AddEventHandler('onResourceStart', function(resource)
	if resource == GetCurrentResourceName() then
		TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Resource ' .. resource .. ' started. Requesting ace permissions from CMS.')
		performApiRequest({serverId = Config.serverId}, 'GET_ACE_CONFIG', function(result, ok)
			if ok then
				local resultDecoded = json.decode(result)
				if resultDecoded.success and resultDecoded.data and resultDecoded.data.mappings then
					setRankList(resultDecoded.data.mappings)
				end
			else
				TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Failed to get ACE permissions from CMS. Please check your API key and connection.')
			end
		end)
	end
end)