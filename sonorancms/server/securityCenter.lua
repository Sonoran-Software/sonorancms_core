AddEventHandler('playerConnecting', function()
	local identifier = exports['sonorancms']:getAppropriateIdentifier(source, Config.apiIdType);
	local reqData = {}
	if Config.apiIdType == 'discord' then
		reqData['discord'] = identifier
	else
		reqData['apiId'] = identifier
	end
	local playerIds = {};
	for k = 0, GetNumPlayerTokens(source) - 1 do
		local id = GetPlayerToken(source, k)
		local cleanId = string.gsub(id, '^%d+:', '')
		table.insert(playerIds, {
			type = 'hwid',
			value = cleanId
		})
	end
	local idTypes = {
		'ip',
		'license',
		'steam',
		'xbl',
		'live',
		'discord',
		'fivem',
		'license2'
	}
	for _, v in pairs(idTypes) do
		local id = GetPlayerIdentifierByType(source, v)
		if id then
			local cleanId = string.gsub(id, '^[^:]+:', '')
			if cleanId then
				table.insert(playerIds, {
					type = v,
					value = cleanId
				});
			end
		end
	end
	reqData['identifiers'] = playerIds;
	exports['sonorancms']:performApiRequest(reqData, 'IDENTIFIERS', function(res)
		res = json.decode(res)
		if res.success then
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Security Center posted for ' .. identifier)
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Failed to post to Security Center for ' .. identifier .. ' - ' .. res.message)
		end
	end)
end)
