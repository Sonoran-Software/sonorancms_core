local plugin_handlers = {}
local MessageBuffer = {}
local DebugBuffer = {}
local ErrorBuffer = {}

SetHttpHandler(function(req, res)
	local path = req.path
	local method = req.method
	if method == 'POST' and path == '/panel/data' then
		req.setDataHandler(function(data)
			local body = json.decode(data)
			if body.key and body.key:upper() == Config.APIKey:upper() then
				local resData = handleDataRequest(body)
				res.send(json.encode(resData))
				return
			else
				res.send('Bad API Key')
				return
			end
		end)
	end
	if method == 'POST' and path == '/events' then
		req.setDataHandler(function(data)
			if not data then
				res.send(json.encode({
					['error'] = 'bad request'
				}))
				return
			end
			local body = json.decode(data)
			if not body then
				res.send(json.encode({
					['error'] = 'bad request'
				}))
				return
			end
			if body.key and body.key:upper() == Config.APIKey:upper() then
				if plugin_handlers[body.type] ~= nil then
					plugin_handlers[body.type](body)
					res.send('ok')
					return
				else
					res.send('Event not registered')
				end
			else
				res.send('Bad API Key')
				return
			end
		end)
	else
		path = req.path:gsub('/proxy.*', '')
		method = req.method
		if method == 'GET' then
			local imagePath = nil
			if GetResourceState('qb-inventory') == 'started' then
				imagePath = GetResourcePath('qb-inventory') .. '/html/' .. path .. '.png'
			elseif GetResourceState('ps-inventory') == 'started' then
				imagePath = GetResourcePath('ps-inventory') .. '/html/' .. path .. '.png'
			elseif GetResourceState('ox_inventory') == 'started' then
				imagePath = GetResourcePath('ox_inventory') .. '/web/' .. path .. '.png'
			elseif GetResourceState('qs-inventory') == 'started' then
				imagePath = GetResourcePath('qs-inventory') .. '/html/' .. path .. '.png'
			elseif GetResourceState('origen_inventory') == 'started' then
				imagePath = GetResourcePath('origen_inventory') .. '/html/' .. path .. '.png'
			elseif GetResourceState('core_inventory') == 'started' then
				imagePath = GetResourcePath('core_inventory') .. '/html/' .. path .. '.png'
			end
			if not path or not imagePath then
				res.send(json.encode({
					error = 'Invalid path'
				}))
				return
			end
			local file = io.open(imagePath, 'rb')
			if not file then
				res.send(json.encode({
					error = 'Image not found'
				}))
				return
			else
				local content = file:read('*all')
				file:close()
				res.send(content)
			end
		end
		if method == 'POST' then
			local data = req.body
			req.setDataHandler(function(body)
				data = body
				local decoded = json.decode(data)
				if tostring(decoded.key) ~= tostring(Config.APIKey) then
					res.send(json.encode({
						error = 'Invalid API key'
					}))
					return
				end
				if decoded.type ~= 'UPLOAD_ITEM_IMAGE' then
					res.send(json.encode({
						error = 'Invalid request type'
					}))
					return
				end
				if not path or path ~= '/upload' then
					res.send(json.encode({
						error = 'Invalid path'
					}))
					return
				end
				if not decoded or not decoded.data.raw then
					res.send(json.encode({
						error = 'Invalid data'
					}))
					return
				end
				local imageCb = nil
				if GetResourceState('qb-inventory') == 'started' then
					imageCb = exports['sonorancms']:SaveBase64ToFile(decoded.data.raw, GetResourcePath('qb-inventory') .. '/html/images/' .. decoded.data.name, decoded.data.name)
				elseif GetResourceState('ps-inventory') == 'started' then
					imageCb = exports['sonorancms']:SaveBase64ToFile(decoded.data.raw, GetResourcePath('ps-inventory') .. '/html/images/' .. decoded.data.name, decoded.data.name)
				elseif GetResourceState('ox_inventory') == 'started' then
					imageCb = exports['sonorancms']:SaveBase64ToFile(decoded.data.raw, GetResourcePath('ox_inventory') .. '/web/images/' .. decoded.data.name, decoded.data.name)
				elseif GetResourceName('qs-inventory') == 'started' then
					imageCb = exports['sonorancms']:SaveBase64ToFile(decoded.data.raw, GetResourcePath('qs-inventory') .. '/html/images/' .. decoded.data.name, decoded.data.name)
				elseif GetResourceState('origen_inventory') == 'started' then
					imageCb = exports['sonorancms']:SaveBase64ToFile(decoded.data.raw, GetResourcePath('origen_inventory') .. '/html/images/' .. decoded.data.name, decoded.data.name)
				end
				if imageCb then
					res.send(json.encode({
						success = true,
						file = imageCb.error
					}))
				else
					res.send(json.encode({
						success = false,
						error = 'Failed to save image. Error: ' .. imageCb.error
					}))
				end
			end)
		end
	end
end)

RegisterNetEvent('sonorancms::RegisterPushEvent', function(type, event)
	plugin_handlers[type] = event
end)

AddEventHandler('onResourceStart', function(resource)
	if resource == GetCurrentResourceName() then
		Citizen.Wait(100)
		SetConvar('SONORAN_CMS_API_KEY', Config.APIKey)
		SetConvar('SONORAN_CMS_COMMUNITY_ID', Config.CommID)

		if GetResourceState('qb-core') == 'started' then
			if GetResourceState('qb-inventory') ~= 'started' and GetResourceState('ox_inventory') ~= 'started' and GetResourceState('qs-inventory') ~= 'started' and GetResourceState('ps-inventory') ~= 'started'
							and GetResourceState('origen_inventory') ~= 'started' and GetResourceState('core_inventory') ~= 'started' and GetResourceState('tgiann-inventory') ~= 'started' then
				TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Unable to send game panel data due to qb-inventory, qs-inventory, ps-inventory, ox_inventory, origen_inventory, core_inventory and tgiann_inventory not being started. If you do not use the SonoranCMS Game Panel you can ignore this.')
				return
			end
			if GetResourceState('qb-garages') ~= 'started' and GetResourceState('cd_garage') ~= 'started' and GetResourceState('qs-advancedgarages') ~= 'started' and GetResourceState('jg-advancedgarages')
							~= 'started' and GetResourceState('ak47_qb_garage') ~= 'started' then
				TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'qb-garages, qs-advancedgarages, jg-advancedgarages, ak47_qb_garage and cd_garage are not started. The garage data will be sent as empty. If you do not use the SonoranCMS Game Panel you can ignore this.')
			end
			if GetResourceState('oxmysql') ~= 'started' and GetResourceState('mysql-async') ~= 'started' and GetResourceState('ghmattimysql') ~= 'started' then
				TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Unable to send game panel data due to oxmysql, mysql-async, and ghmattimysql not being started. If you do not use the SonoranCMS Game Panel you can ignore this.')
				return
			end
		end
	end
end)

function getServerVersion()
    local s = GetConvar('version', '')
    local v = s:find('v1.0.0.')
    local e = string.gsub(s:sub(v),'v1.0.0.','')
    local i = e:sub(1, string.len(e) - e:find(''))
    return i
end

local function extractPort(endpoint)
	if type(endpoint) ~= 'string' then
		return nil
	end
	local cleaned = endpoint:gsub('"', '')
	local port = cleaned:match(':(%d+)%s*$')
	if port then
		return tonumber(port)
	end
	return nil
end

local function getServerPort()
	local port = extractPort(GetConvar('endpoint_add_tcp', ''))
	if not port then
		port = extractPort(GetConvar('endpoint_add_udp', ''))
	end
	if not port then
		local convarPort = GetConvar('sv_port', '')
		if convarPort ~= '' then
			port = tonumber(convarPort)
		end
	end
	if not port and GetConvarInt then
		local intPort = GetConvarInt('sv_port', 0)
		if intPort and intPort > 0 then
			port = intPort
		end
	end
	if not port then
		local lastCheck = GetConvar('netPort', '')
			if lastCheck ~= '' then
				port = tonumber(lastCheck)
			end
	end
	return port
end

local function getServerName()
	local name = GetConvar('sv_projectName', '')
	if name == '' then
		name = GetConvar('sv_hostname', '')
	end
	if name == '' then
		name = ('Server %s'):format(tostring(Config.serverId))
	end
	return name
end

local function getServerDescription()
	local desc = GetConvar('sv_projectDesc', '')
	if desc == '' then
		desc = 'Auto-created by SonoranCMS'
	end
	return desc
end

local function ensureCmsServerRegistered()
	performApiRequest({}, 'GET_GAME_SERVERS', function(result, ok)
		if not ok then
			warnLog(('Failed to fetch CMS servers: %s'):format(tostring(result)))
			return
		end
		local decoded = result
		if type(result) == 'string' then
			local okDecode, decodedRes = pcall(json.decode, result)
			if not okDecode then
				warnLog(('Failed to parse GET_GAME_SERVERS response: %s'):format(tostring(result)))
				return
			end
			decoded = decodedRes
		end
		if type(decoded) ~= 'table' or type(decoded.servers) ~= 'table' then
			warnLog(('Unexpected GET_GAME_SERVERS response: %s'):format(tostring(result)))
			return
		end
		local targetId = tostring(Config.serverId)
		for _, server in ipairs(decoded.servers) do
			if tostring(server.id) == targetId then
				debugLog(('CMS server id %s already registered.'):format(targetId))
				return
			end
		end
		local port = getServerPort()
		if not port then
			warnLog('Unable to detect server port. Defaulting to 30120 for CMS registration.')
			port = 30120
		end
		local addPayload = {
			{
				id = tonumber(Config.serverId) or Config.serverId,
				name = getServerName(),
				description = getServerDescription(),
				ip = json.null,
				port = port,
				type = Config.framework or json.null
			}
		}
		performApiRequest(addPayload, 'ADD_GAME_SERVERS', function(addResult, addOk)
			if not addOk then
				warnLog(('Failed to add CMS server %s: %s'):format(targetId, tostring(addResult)))
				return
			end
			infoLog(('Added CMS server %s (%s).'):format(targetId, addPayload[1].name))
		end)
	end)
end

CreateThread(function()
	print('Starting SonoranCMS from ' .. GetResourcePath('sonorancms'))
	exports['sonorancms']:initializeCMS(Config.CommID, Config.APIKey, Config.serverId, Config.apiUrl, Config.debug_mode)
	local serverType = Config.framework
	if serverType == 'none' then serverType = nil end
	local setTypeData = { serverId = Config.serverId, type = serverType }
	performApiRequest(setTypeData, 'SET_SERVER_TYPE', function(result, ok)
		if not ok then
			infoLog(('Failed to set server type to %s: %s'):format(serverType, result))
			return
		end
		infoLog(('Set server type to %s'):format(serverType))
	end)
	performApiRequest({}, 'GET_SUB_VERSION', function(result, ok)
		if not ok then
			logError('API_ERROR')
			Config.critError = true
			return
		end
		local subVersionData = json.decode(result)
		if type(subVersionData) == 'table' and subVersionData.subVersion then
			Config.apiVersion = tonumber(subVersionData.subVersion)
		else
			Config.apiVersion = tonumber(string.sub(tostring(result), 1, 1))
		end
		-- if Config.apiVersion < 2 then
		-- 	logError('API_PAID_ONLY')
		-- 	Config.critError = true
		-- end
		debugLog(('Set version %s from response %s'):format(Config.apiVersion, result))
		infoLog(('Loaded community ID %s with API URL: %s'):format(Config.CommID, Config.apiUrl))
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'ACCOUNT_UPDATED', function(data)
		TriggerEvent('sonoran_permissions::rankupdate', data)
		TriggerEvent('sonoran_jobsync::rankupdate', data)
	end)
	-- Returns: "found", "permission", or "missing"
	function exists(path)
		if type(path) ~= "string" then
			return "missing"
		end

		local f = io.open(path, "r")
		if f then
			f:close()
			return "found"
		else
			-- If io.open fails, check rename() just in case it's permissions
			local ok, _, code = os.rename(path, path)
			if code == 13 then
				return "permission"
			else
				return "missing"
			end
		end
	end

	-- Check addonupdates folder
	local addonStatus = exists(GetResourcePath('sonorancms') .. '/addonupdates')
	if addonStatus == "found" then
		infoLog('addonupdates folder was found! This folder is no longer used and can be deleted...')
	elseif addonStatus == "permission" then
		warnLog('addonupdates folder exists but permission was denied when checking. Please verify permissions.')
	end

	-- Check config.NEW.lua
	local configStatus = exists(GetResourcePath('sonorancms') .. '/config.NEW.lua')
	if configStatus == "found" then
		errorLog('config.NEW.lua was found! Please copy over the new config and then delete this file! See https://sonoran.link/cmsconfig for more information.')
		return
	elseif configStatus == "permission" then
		warnLog('config.NEW.lua exists but permission was denied when checking. Please verify permissions. See https://sonoran.link/cmsconfig for more information.')
	end
	Wait(5000)
	local versionfile = json.decode(LoadResourceFile(GetCurrentResourceName(), '/version.json'))
	local fxversion = versionfile.testedFxServerVersion
	local currentFxVersion = getServerVersion()
	if tonumber(currentFxVersion) ~= nil and tonumber(fxversion) ~= nil then
		if tonumber(currentFxVersion) < tonumber(fxversion) then
			warnLog(('SonoranCMS has been tested with FXServer version %s, but you\'re running %s. Please update ASAP.'):format(fxversion, currentFxVersion))
		end
	end
	if GetResourceState('sonorancms_updatehelper') == 'started' then
		ExecuteCommand('stop sonorancms_updatehelper')
		TriggerEvent('SonoranCMS::core:writeLog', 'info', 'Stopping update helper... Please do not manually start this resource.')
	end
	TriggerEvent(GetCurrentResourceName() .. '::CheckConfig')
	ensureCmsServerRegistered()
	TriggerEvent(GetCurrentResourceName() .. '::StartUpdateLoop')
end)

--[[
	Sonoran CMS Core Logging Functions
]]

local function sendConsole(level, color, message)
	local debugging = true
	if Config ~= nil then
		debugging = (Config.debug_mode == true and Config.debug_mode ~= 'false')
	end
	local time = os and os.date('%X') or LocalTime()
	local info = debug.getinfo(3, 'S')
	local source = '.'
	if info.source:find('@@sonorancms') then
		source = info.source:gsub('@@sonorancms/', '') .. ':' .. info.linedefined
	end
	local msg = ('[%s][%s:%s%s^7]%s %s^0'):format(time, debugging and source or 'SonoranCMS', color, level, color, message)
	if (debugging and level == 'DEBUG') or (not debugging and level ~= 'DEBUG') or level == 'ERROR' or level == 'WARNING' or level == 'INFO' then
		print(msg)
	end
	if (level == 'ERROR' or level == 'WARNING') and IsDuplicityVersion() then
		table.insert(ErrorBuffer, 1, msg)
	end
	if level == 'DEBUG' and IsDuplicityVersion() then
		if #DebugBuffer > 50 then
			table.remove(DebugBuffer)
		end
		table.insert(DebugBuffer, 1, msg)
	else
		if not IsDuplicityVersion() then
			if #MessageBuffer > 10 then
				table.remove(MessageBuffer)
			end
			table.insert(MessageBuffer, 1, msg)
		end
	end
end

AddEventHandler('SonoranCMS::core:writeLog', function(level, message)
	if level == 'debug' then
		debugLog(message)
	elseif level == 'info' then
		infoLog(message)
	elseif level == 'error' then
		errorLog(message)
	elseif level == 'warn' then
		warnLog(message)
	else
		debugLog(message)
	end
end)

function getDebugBuffer()
	return DebugBuffer
end

function getErrorBuffer()
	return ErrorBuffer
end

function debugLog(message)
	sendConsole('DEBUG', '^7', message)
end

local ErrorCodes = {
	['INVALID_COMMUNITY_ID'] = 'You have set an invalid community ID, please check your Config and SonoranCMS integration'
}

function logError(err, msg)
	local o = ''
	if msg == nil then
		o = ('ERR %s: %s - See https://sonoran.software/errorcodes for more information.'):format(err, ErrorCodes[err])
	else
		o = ('ERR %s: %s - See https://sonoran.software/errorcodes for more information.'):format(err, msg)
	end
	sendConsole('ERROR', '^1', o)
end

function errorLog(message)
	sendConsole('ERROR', '^1', message)
end

function warnLog(message)
	sendConsole('WARNING', '^3', message)
end

function infoLog(message)
	sendConsole('INFO', '^5', message)
end

function PerformHttpRequestS(url, cb, method, data, headers)
	if not data then
		data = ''
	end
	if not headers then
		headers = {
			['X-User-Agent'] = 'SonoranCAD'
		}
	end
	exports['sonorancms']:HandleHttpRequest(url, cb, method, data, headers)
end

exports('getCmsVersion', function()
	return Config.apiVersion
end)

--[[
	Sonoran CMS API Wrapper
]]

local LegacyApiEndpoints = {
	['GET_SUB_VERSION'] = 'general',
	['CHECK_COM_APIID'] = 'general',
	['GET_COM_ACCOUNT'] = 'general',
	['GET_DEPARTMENTS'] = 'general',
	['GET_PROFILE_FIELDS'] = 'general',
	['GET_ACCOUNT_RANKS'] = 'general',
	['SET_ACCOUNT_RANKS'] = 'general',
	['CLOCK_IN_OUT'] = 'general',
	['KICK_ACCOUNT'] = 'general',
	['BAN_ACCOUNT'] = 'general',
	['EDIT_ACC_PROFLIE_FIELDS'] = 'general',
	['GET_GAME_SERVERS'] = 'servers',
	['SET_GAME_SERVERS'] = 'servers',
	['ADD_GAME_SERVERS'] = 'servers',
	['VERIFY_WHITELIST'] = 'servers',
	['FULL_WHITELIST'] = 'servers',
	['RSVP'] = 'events',
	['GAMESTATE'] = 'servers',
	['ACTIVITY_TRACKER_START_STOP'] = 'servers',
	['ACTIVITY_TRACKER_SERVER_START'] = 'servers',
	['IDENTIFIERS'] = 'game',
	['GET_ACE_CONFIG'] = 'servers',
	['SET_SERVER_TYPE'] = 'servers'
}

function registerApiType(requestType, endpoint)
	LegacyApiEndpoints[requestType] = endpoint
end
exports('registerApiType', registerApiType)

local rateLimitedEndpoints = {}

local function trimTrailingSlash(value)
	return (tostring(value or ''):gsub('/+$', ''))
end

local function urlEncode(value)
	return tostring(value):gsub('\n', '\r\n'):gsub("([^%w%-_%.~])", function(char)
		return string.format('%%%02X', string.byte(char))
	end)
end

local function buildQueryString(params)
	if _G.type(params) ~= 'table' then
		return ''
	end
	local query = {}
	for key, value in pairs(params) do
		if value ~= nil then
			table.insert(query, string.format('%s=%s', urlEncode(key), urlEncode(value)))
		end
	end
	table.sort(query)
	return table.concat(query, '&')
end

local function buildCmsV2Url(path, query)
	local base = trimTrailingSlash(Config.apiUrl)
	local url = base .. '/v2/' .. tostring(path or ''):gsub('^/+', '')
	local queryString = buildQueryString(query)
	if queryString ~= '' then
		url = url .. '?' .. queryString
	end
	return url
end

local function firstArrayValue(value)
	if _G.type(value) ~= 'table' then
		return value
	end
	if value[1] ~= nil and next(value, 1) == nil then
		return value[1]
	end
	return value
end

local function normalizeRequestData(postData)
	local data = firstArrayValue(postData)
	if _G.type(data) ~= 'table' then
		return {}
	end
	return data
end

local function decodeJsonBody(body)
	if _G.type(body) ~= 'string' or body == '' then
		return nil
	end
	local ok, decoded = pcall(json.decode, body)
	if ok then
		return decoded
	end
	return nil
end

local function normalizeResponseValue(value)
	if value == nil then
		return ''
	end
	if _G.type(value) == 'table' then
		return json.encode(value)
	end
	return tostring(value)
end

local function unwrapV2ResponseBody(res)
	local decoded = decodeJsonBody(res)
	if decoded == nil then
		return res
	end
	if _G.type(decoded) == 'table' and decoded.success == true and decoded.data ~= nil then
		return decoded.data
	end
	return decoded
end

local function extractV2ErrorMessage(res)
	local decoded = decodeJsonBody(res)
	if _G.type(decoded) == 'table' then
		return decoded.detail or decoded.message or decoded.error or decoded.reason or res
	end
	return res
end

local function requestCmsV2(requestMethod, path, body, query, requestType, cb)
	local url = buildCmsV2Url(path, query)
	local headers = {
		['Accept'] = 'application/json',
		['Authorization'] = 'Bearer ' .. tostring(Config.APIKey),
		['X-User-Agent'] = 'SonoranCAD'
	}
	local requestBody = ''
	if body ~= nil then
		requestBody = json.encode(body)
	end
	PerformHttpRequestS(url, function(statusCode, res, responseHeaders)
		if Config.debug_mode and requestType ~= 'GAMESTATE' then
			debugLog('API Result:', tostring(res))
		end
		if requestType ~= 'GAMESTATE' then
			debugLog(('type %s called with v2 body %s to url %s'):format(requestType, requestBody ~= '' and requestBody or '{}', url))
		end
		if statusCode == 200 or statusCode == 201 or statusCode == 204 then
			cb(normalizeResponseValue(unwrapV2ResponseBody(res)), true)
			return
		end
		if statusCode == 429 then
			if rateLimitedEndpoints[requestType] then
				debugLog(('Endpoint %s ratelimited. Dropping request.'):format(requestType))
				return
			end
			rateLimitedEndpoints[requestType] = true
			warnLog(
				('WARN_RATELIMIT: You are being ratelimited (last request made to %s) - Ignoring all API requests to this endpoint for 60 seconds. If this is happening frequently, please review your configuration to ensure you\'re not sending data too quickly.'):format(
					requestType))
			SetTimeout(60000, function()
				rateLimitedEndpoints[requestType] = nil
				infoLog(('Endpoint %s no longer ignored.'):format(requestType))
			end)
			cb(extractV2ErrorMessage(res), false)
			return
		end
		if statusCode == 400 or statusCode == 401 or statusCode == 403 or statusCode == 404 or statusCode == 422 then
			local errorMessage = extractV2ErrorMessage(res)
			warnLog(('Bad request was sent to the V2 API. Response: %s'):format(tostring(errorMessage)))
			if statusCode == 400 and (tostring(errorMessage) == 'INVALID COMMUNITY ID' or tostring(errorMessage) == 'API IS NOT ENABLED FOR THIS COMMUNITY' or string.find(tostring(errorMessage), 'IS NOT ENABLED FOR THIS COMMUNITY') or tostring(errorMessage) == 'INVALID API KEY') then
				errorLog('Fatal: Disabling API - an error was encountered that must be resolved. Please restart the resource after resolving: ' .. tostring(errorMessage))
				Config.critError = true
			end
			cb(errorMessage, false)
			return
		end
		if string.match(tostring(statusCode), '50') then
			local errorMessage = extractV2ErrorMessage(res)
			errorLog(('API error returned (%s). Check status.sonoransoftware.com or our Discord to see if there\'s an outage.'):format(statusCode))
			debugLog(('API_ERROR Error returned: %s %s'):format(statusCode, tostring(errorMessage)))
			cb(errorMessage, false)
			return
		end
		errorLog(('CMS API ERROR (from %s): %s %s'):format(url, statusCode, tostring(res)))
		cb(res, false)
	end, requestMethod, requestBody, headers)
end

local function resolveAccountSearchQuery(postData)
	local data = normalizeRequestData(postData)
	return {
		accountId = data.accountId,
		apiId = data.apiId,
		username = data.username,
		accId = data.accId,
		discord = data.discordId or data.discord,
		uniqueId = data.uniqueId
	}
end

local function parseAccountsFromResponse(result)
	local decoded = decodeJsonBody(result)
	if _G.type(decoded) ~= 'table' then
		return {}
	end
	if _G.type(decoded.items) == 'table' then
		return decoded.items
	end
	if decoded[1] ~= nil then
		return decoded
	end
	return {}
end

local function requestAccountSearch(postData, requestType, cb)
	requestCmsV2('GET', 'community/accounts/search', nil, resolveAccountSearchQuery(postData), requestType, cb)
end

local function resolveAccountId(postData, requestType, cb)
	local data = normalizeRequestData(postData)
	if data.accId or data.accountId then
		cb(data.accId or data.accountId, data, true)
		return
	end
	requestAccountSearch(data, requestType, function(result, ok)
		if not ok then
			cb(nil, data, false, result)
			return
		end
		local accounts = parseAccountsFromResponse(result)
		if #accounts == 0 then
			cb(nil, data, false, 'ACCOUNT_NOT_FOUND')
			return
		end
		if #accounts > 1 then
			cb(nil, data, false, 'TOO_MANY_ACCOUNTS')
			return
		end
		cb(accounts[1].accId, data, true)
	end)
end

function performApiRequest(postData, requestType, cb)
	local payload = {
		id = Config.CommID,
		key = Config.APIKey,
		serverId = Config.serverId,
		data = postData,
		type = requestType
	}
	assert(requestType ~= nil, 'No type specified, invalid request.')
	if Config.critError then
		errorLog('API request failed: critical error encountered, API version too low, aborting request.')
		return
	end

	if rateLimitedEndpoints[requestType] ~= nil then
		debugLog(('Endpoint %s is ratelimited. Dropped request: %s'):format(requestType, json.encode(payload)))
		return
	end

	if requestType == 'GET_SUB_VERSION' then
		requestCmsV2('GET', 'community/sub-version', nil, nil, requestType, cb)
		return
	end

	if requestType == 'GET_GAME_SERVERS' then
		requestCmsV2('GET', 'community/servers', nil, nil, requestType, cb)
		return
	end

	if requestType == 'ADD_GAME_SERVERS' then
		local data = normalizeRequestData(postData)
		local servers = data.servers or postData
		requestCmsV2('POST', 'community/servers', { servers = servers }, nil, requestType, cb)
		return
	end

	if requestType == 'SET_GAME_SERVERS' then
		local data = normalizeRequestData(postData)
		local servers = data.servers or postData
		requestCmsV2('PUT', 'community/servers', { servers = servers }, nil, requestType, cb)
		return
	end

	if requestType == 'SET_SERVER_TYPE' then
		local data = normalizeRequestData(postData)
		requestCmsV2('PATCH', ('community/servers/%s/type'):format(tostring(data.serverId or Config.serverId)), { type = data.type }, nil, requestType, cb)
		return
	end

	if requestType == 'GET_ACE_CONFIG' then
		local data = normalizeRequestData(postData)
		requestCmsV2('GET', ('community/servers/%s/ace-config'):format(tostring(data.serverId or Config.serverId)), nil, nil, requestType, cb)
		return
	end

	if requestType == 'VERIFY_WHITELIST' then
		local data = normalizeRequestData(postData)
		requestCmsV2(
			'POST',
			('community/servers/%s/whitelist/check'):format(tostring(data.serverId or Config.serverId)),
			{
				apiId = data.apiId,
				accId = data.accId,
				username = data.username,
				discord = data.discord or data.discordId,
				uniqueId = data.uniqueId
			},
			nil,
			requestType,
			cb
		)
		return
	end

	if requestType == 'FULL_WHITELIST' then
		local data = normalizeRequestData(postData)
		requestCmsV2('GET', ('community/servers/%s/whitelist'):format(tostring(data.serverId or Config.serverId)), nil, nil, requestType, cb)
		return
	end

	if requestType == 'ACTIVITY_TRACKER_START_STOP' then
		local data = normalizeRequestData(postData)
		requestCmsV2(
			'POST',
			('community/servers/%s/activity'):format(tostring(data.serverId or Config.serverId)),
			{
				apiId = data.apiId,
				accId = data.accId,
				username = data.username,
				discord = data.discord or data.discordId,
				uniqueId = data.uniqueId,
				forceClear = data.forceClear,
				forceStart = data.forceStart,
				forceStop = data.forceStop
			},
			nil,
			requestType,
			cb
		)
		return
	end

	if requestType == 'ACTIVITY_TRACKER_SERVER_START' then
		local data = normalizeRequestData(postData)
		requestCmsV2('POST', ('community/servers/%s/activity/start'):format(tostring(data.serverId or Config.serverId)), nil, nil, requestType, cb)
		return
	end

	if requestType == 'GET_COM_ACCOUNT' then
		requestAccountSearch(postData, requestType, function(result, ok)
			if not ok then
				cb(result, false)
				return
			end
			cb(normalizeResponseValue(parseAccountsFromResponse(result)), true)
		end)
		return
	end

	if requestType == 'GET_ACCOUNT_RANKS' then
		requestAccountSearch(postData, requestType, function(result, ok)
			if not ok then
				cb(result, false)
				return
			end
			local accounts = parseAccountsFromResponse(result)
			local ranks = {}
			if #accounts > 0 and _G.type(accounts[1].ranks) == 'table' then
				ranks = accounts[1].ranks
			end
			cb(normalizeResponseValue(ranks), true)
		end)
		return
	end

	if requestType == 'CLOCK_IN_OUT' then
		resolveAccountId(postData, requestType, function(accountId, data, ok, errorMessage)
			if not ok then
				cb(errorMessage, false)
				return
			end
			requestCmsV2(
				'POST',
				('community/accounts/%s/clock'):format(tostring(accountId)),
				{
					accountId = accountId,
					accId = data.accId,
					apiId = data.apiId,
					username = data.username,
					discord = data.discord or data.discordId,
					uniqueId = data.uniqueId,
					forceClockIn = data.forceClockIn,
					forceClockOut = data.forceClockOut,
					intention = data.intention,
					type = data.type
				},
				nil,
				requestType,
				cb
			)
		end)
		return
	end

	if requestType == 'SET_ACCOUNT_RANKS' then
		resolveAccountId(postData, requestType, function(accountId, data, ok, errorMessage)
			if not ok then
				cb(errorMessage, false)
				return
			end
			requestCmsV2(
				'PATCH',
				('community/accounts/%s/ranks'):format(tostring(accountId)),
				{
					accountId = accountId,
					accId = data.accId,
					apiId = data.apiId,
					username = data.username,
					discord = data.discord or data.discordId,
					uniqueId = data.uniqueId,
					add = data.add,
					remove = data.remove,
					set = data.set,
					active = data.active
				},
				nil,
				requestType,
				cb
			)
		end)
		return
	end

	if requestType == 'IDENTIFIERS' then
		resolveAccountId(postData, requestType, function(accountId, data, ok, errorMessage)
			if not ok then
				cb(errorMessage, false)
				return
			end
			requestCmsV2(
				'POST',
				('community/accounts/%s/identifiers'):format(tostring(accountId)),
				{
					identifiers = data.identifiers or {}
				},
				nil,
				requestType,
				cb
			)
		end)
		return
	end

	if requestType == 'GET_DEPARTMENTS' then
		requestCmsV2('GET', 'community/departments', nil, nil, requestType, cb)
		return
	end

	if requestType == 'GET_PROFILE_FIELDS' then
		requestCmsV2('GET', 'community/profile-fields', nil, nil, requestType, cb)
		return
	end

	if requestType == 'RSVP' then
		local data = normalizeRequestData(postData)
		requestCmsV2('POST', ('community/events/%s/rsvps'):format(tostring(data.eventId or '')), data, nil, requestType, cb)
		return
	end

	local endpoint = LegacyApiEndpoints[requestType]
	if endpoint ~= nil then
		local url = Config.apiUrl .. tostring(endpoint) .. '/' .. tostring(requestType:lower())
		local payload = {}
		payload['id'] = Config.CommID
		payload['key'] = Config.APIKey
		payload['serverId'] = Config.serverId
		payload['data'] = postData
		payload['type'] = requestType
		PerformHttpRequestS(url, function(statusCode, res, headers)
			if Config.debug_mode and requestType ~= 'GAMESTATE' then
				debugLog('API Result:', tostring(res))
			end
			if requestType ~= 'GAMESTATE' then
				debugLog(('type %s called with post data %s to url %s'):format(requestType, json.encode(payload), url))
			end
			if statusCode == 200 or statusCode == 201 and res ~= nil then
				debugLog('result: ' .. tostring(res))
				if res == 'Sonoran CMS: Backend Service Reached' or res == 'Backend Service Reached' then
					errorLog(('API ERROR: Invalid endpoint (URL: %s). Ensure you\'re using a valid endpoint.'):format(url))
				else
					if res == nil then
						res = {}
						debugLog('Warning: Response had no result, setting to empty table.')
					end
					cb(res, true)
				end
			elseif statusCode == 400 then
				warnLog('Bad request was sent to the API. Enable debug mode and retry your request. Response: ' .. tostring(res))
				if res == 'INVALID COMMUNITY ID' or res == 'API IS NOT ENABLED FOR THIS COMMUNITY' or string.find(res, 'IS NOT ENABLED FOR THIS COMMUNITY') or res == 'INVALID API KEY' then
					errorLog('Fatal: Disabling API - an error was encountered that must be resolved. Please restart the resource after resolving: ' .. tostring(res))
					Config.critError = true
				end
				cb(res, false)
			elseif statusCode == 404 then
				debugLog('404 response found')
				cb(res, false)
			elseif statusCode == 429 then
				if rateLimitedEndpoints[requestType] then
					debugLog(('Endpoint %s ratelimited. Dropping request.'):format(requestType))
					return
				end
				rateLimitedEndpoints[requestType] = true
				warnLog(
					('WARN_RATELIMIT: You are being ratelimited (last request made to %s) - Ignoring all API requests to this endpoint for 60 seconds. If this is happening frequently, please review your configuration to ensure you\'re not sending data too quickly.'):format(
						requestType))
				SetTimeout(60000, function()
					rateLimitedEndpoints[requestType] = nil
					infoLog(('Endpoint %s no longer ignored.'):format(requestType))
				end)
			elseif string.match(tostring(statusCode), '50') then
				errorLog(('API error returned (%s). Check status.sonoransoftware.com or our Discord to see if there\'s an outage.'):format(statusCode))
				debugLog(('API_ERROR Error returned: %s %s'):format(statusCode, res))
				if requestType == 'GET_ACCOUNT_RANKS' or requestType == 'FULL_WHITELIST' then
					cb({}, false)
				end
			else
				errorLog(('CMS API ERROR (from %s): %s %s'):format(url, statusCode, res))
			end
		end, 'POST', json.encode(payload), {
			['Content-Type'] = 'application/json'
		})
		return
	end

	warnLog(('API request failed: endpoint %s is not registered. Use the registerApiType function to register this endpoint with the appropriate type.'):format(requestType))
end
exports('performApiRequest', performApiRequest)

RegisterNetEvent('SonoranCMS::core::RequestEnvironment', function()
	TriggerClientEvent('SonoranCMS::core::ReceiveEnvironment', source, {
		EnableWeatherSync = Config.EnableWeatherSync
	})
end)


exports('jsGetPlayers', function()
	local players = GetPlayers()
	return players
end)
