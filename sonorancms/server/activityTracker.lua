AddEventHandler('playerJoining', function()
	local src = source
	local name = GetPlayerName(src)
	TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Player ' .. name .. ' (' .. src .. ') joined the server. Sending activity tracker to SonoranCMS.')
	local identifier
	local source = source
	for _, v in pairs(GetPlayerIdentifiers(source)) do
		if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
			identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
		end
	end
	local reqData = {}
	if Config.apiIdType == 'discord' then
		reqData['discord'] = identifier
	else
		reqData['apiId'] = identifier
	end
	reqData['serverId'] = Config.serverId
	reqData['forceStart'] = true
	exports['sonorancms']:performApiRequest(reqData, 'ACTIVITY_TRACKER_START_STOP', function(data, success)
		if success then
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Activity tracker started for ' .. name .. ' (' .. identifier .. ')')
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Failed to start activity tracker for ' .. name .. ' (' .. identifier .. ') - ' .. data)
		end
	end)
end)

AddEventHandler('playerDropped', function()
	local src = source
	local name = GetPlayerName(src)
	TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Player ' .. name .. ' (' .. src .. ') left the server. Sending activity tracker to SonoranCMS.')
	local identifier
	local source = source
	for _, v in pairs(GetPlayerIdentifiers(source)) do
		if string.sub(v, 1, string.len(Config.apiIdType .. ':')) == Config.apiIdType .. ':' then
			identifier = string.sub(v, string.len(Config.apiIdType .. ':') + 1)
		end
	end
	local reqData = {}
	if Config.apiIdType == 'discord' then
		reqData['discord'] = identifier
	else
		reqData['apiId'] = identifier
	end
	reqData['serverId'] = Config.serverId
	reqData['forceStop'] = true
	exports['sonorancms']:performApiRequest(reqData, 'ACTIVITY_TRACKER_START_STOP', function(data, success)
		if success then
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Activity tracker stopped for ' .. name .. ' (' .. identifier .. ')')
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Failed to stop activity tracker for ' .. name .. ' (' .. identifier .. ') - ' .. json.encode(data))
		end
	end)
end)

AddEventHandler('onResourceStart', function(resourceName)
	if (GetCurrentResourceName() ~= resourceName) then
		return
	end
	TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Resource ' .. resourceName .. ' started. Sending activity tracker to stop all active activities to SonoranCMS.')
	local reqData = {}
	reqData['serverId'] = Config.serverId
	exports['sonorancms']:performApiRequest(reqData, 'ACTIVITY_TRACKER_SERVER_START', function(data, success)
		if success then
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Activity tracker stopped for all active activities - ' .. json.encode(data))
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Failed to stop activity tracker for all active activities - ' .. json.encode(data))
		end
	end)
end)
