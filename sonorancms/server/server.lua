local plugin_handlers = {}
local MessageBuffer = {}
local DebugBuffer = {}
local ErrorBuffer = {}
local ERROR_DOC_BASE_URL = 'https://sonorancms.com/error/'

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
				TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'GAME_PANEL_INVENTORY_DEPENDENCY_MISSING', 'Unable to send game panel data due to qb-inventory, qs-inventory, ps-inventory, ox_inventory, origen_inventory, core_inventory and tgiann_inventory not being started. If you do not use the SonoranCMS Game Panel you can ignore this.')
				return
			end
			if GetResourceState('qb-garages') ~= 'started' and GetResourceState('cd_garage') ~= 'started' and GetResourceState('qs-advancedgarages') ~= 'started' and GetResourceState('jg-advancedgarages')
							~= 'started' and GetResourceState('ak47_qb_garage') ~= 'started' then
				TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'GAME_PANEL_GARAGE_DEPENDENCY_MISSING', 'qb-garages, qs-advancedgarages, jg-advancedgarages, ak47_qb_garage and cd_garage are not started. The garage data will be sent as empty. If you do not use the SonoranCMS Game Panel you can ignore this.')
			end
			if GetResourceState('oxmysql') ~= 'started' and GetResourceState('mysql-async') ~= 'started' and GetResourceState('ghmattimysql') ~= 'started' then
				TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'GAME_PANEL_DATABASE_DEPENDENCY_MISSING', 'Unable to send game panel data due to oxmysql, mysql-async, and ghmattimysql not being started. If you do not use the SonoranCMS Game Panel you can ignore this.')
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
			warnLog('CMS_SERVERS_FETCH_FAILED', ('Failed to fetch CMS servers: %s'):format(tostring(result)))
			return
		end
		local decoded = result
		if type(result) == 'string' then
			local okDecode, decodedRes = pcall(json.decode, result)
			if not okDecode then
				warnLog('CMS_SERVERS_PARSE_FAILED', ('Failed to parse GET_GAME_SERVERS response: %s'):format(tostring(result)))
				return
			end
			decoded = decodedRes
		end
		if type(decoded) ~= 'table' or type(decoded.servers) ~= 'table' then
			warnLog('CMS_SERVERS_RESPONSE_INVALID', ('Unexpected GET_GAME_SERVERS response: %s'):format(tostring(result)))
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
			warnLog('CMS_SERVER_PORT_DEFAULTED', 'Unable to detect server port. Defaulting to 30120 for CMS registration.')
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
				warnLog('CMS_SERVER_REGISTER_FAILED', ('Failed to add CMS server %s: %s'):format(targetId, tostring(addResult)))
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
		Config.apiVersion = tonumber(string.sub(result, 1, 1))
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
		warnLog('LEGACY_ADDONUPDATES_PERMISSION', 'addonupdates folder exists but permission was denied when checking. Please verify permissions.')
	end

	-- Check config.NEW.lua
	local configStatus = exists(GetResourcePath('sonorancms') .. '/config.NEW.lua')
	if configStatus == "found" then
		errorLog('CONFIG_NEW_FOUND', 'config.NEW.lua was found! Please copy over the new config and then delete this file! See https://sonoran.link/cmsconfig for more information.')
		return
	elseif configStatus == "permission" then
		warnLog('CONFIG_NEW_PERMISSION', 'config.NEW.lua exists but permission was denied when checking. Please verify permissions. See https://sonoran.link/cmsconfig for more information.')
	end
	Wait(5000)
	local versionfile = json.decode(LoadResourceFile(GetCurrentResourceName(), '/version.json'))
	local fxversion = versionfile.testedFxServerVersion
	local currentFxVersion = getServerVersion()
	if tonumber(currentFxVersion) ~= nil and tonumber(fxversion) ~= nil then
		if tonumber(currentFxVersion) < tonumber(fxversion) then
			warnLog('FXSERVER_OUTDATED', ('SonoranCMS has been tested with FXServer version %s, but you\'re running %s. Please update ASAP.'):format(fxversion, currentFxVersion))
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

AddEventHandler('SonoranCMS::core:writeLog', function(level, codeOrMessage, message)
	if level == 'debug' then
		debugLog(codeOrMessage)
	elseif level == 'info' then
		infoLog(codeOrMessage)
	elseif level == 'error' then
		errorLog(codeOrMessage, message)
	elseif level == 'warn' then
		warnLog(codeOrMessage, message)
	else
		debugLog(codeOrMessage)
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

local WarningCodes = {
	['CMS_SERVERS_FETCH_FAILED'] = { code = 'WRN-CORE-101', message = 'Fetching the CMS server list failed.' },
	['CMS_SERVERS_PARSE_FAILED'] = { code = 'WRN-CORE-102', message = 'The CMS server list response could not be parsed.' },
	['CMS_SERVERS_RESPONSE_INVALID'] = { code = 'WRN-CORE-103', message = 'The CMS server list response was missing required data.' },
	['CMS_SERVER_PORT_DEFAULTED'] = { code = 'WRN-CORE-104', message = 'The CMS server port could not be detected automatically and the default port was used.' },
	['CMS_SERVER_REGISTER_FAILED'] = { code = 'WRN-CORE-105', message = 'Registering the CMS server entry failed.' },
	['LEGACY_ADDONUPDATES_PERMISSION'] = { code = 'WRN-CORE-106', message = 'The legacy addonupdates folder could not be inspected because of a permission issue.' },
	['CONFIG_NEW_PERMISSION'] = { code = 'WRN-CORE-107', message = 'config.NEW.lua may exist, but a permission error prevented verification.' },
	['FXSERVER_OUTDATED'] = { code = 'WRN-CORE-108', message = 'The running FXServer build is older than the version SonoranCMS was tested against.' },
	['API_ENDPOINT_UNREGISTERED'] = { code = 'WRN-CORE-109', message = 'An API request was attempted for an unregistered endpoint type.' },
	['API_BAD_REQUEST'] = { code = 'WRN-CORE-110', message = 'The CMS API rejected a request as malformed or invalid.' },
	['API_RATELIMITED'] = { code = 'WRN-CORE-111', message = 'The CMS API temporarily rate-limited this endpoint.' },
	['GAME_PANEL_INVENTORY_DEPENDENCY_MISSING'] = { code = 'WRN-GP-101', message = 'Game Panel inventory data could not be sent because no supported inventory resource is started.' },
	['GAME_PANEL_GARAGE_DEPENDENCY_MISSING'] = { code = 'WRN-GP-102', message = 'Game Panel garage data will be empty because no supported garage resource is started.' },
	['GAME_PANEL_DATABASE_DEPENDENCY_MISSING'] = { code = 'WRN-GP-103', message = 'Game Panel data could not be sent because no supported database resource is started.' },
	['GAME_PANEL_PAYLOAD_BLOCKED'] = { code = 'WRN-GP-104', message = 'Game Panel payload delivery was skipped because the resource is in a critical error state.' },
	['GAME_PANEL_PAYLOAD_BLOCKED_DETAILS'] = { code = 'WRN-GP-105', message = 'Game Panel payload delivery was skipped and additional error details were logged.' },
	['RESOURCE_NAME_INVALID'] = { code = 'WRN-GP-106', message = 'The SonoranCMS resource is not using the required resource name.' },
	['LEGACY_RESOURCE_RUNNING'] = { code = 'WRN-GP-107', message = 'A legacy standalone SonoranCMS addon is still running alongside the bundled core module.' },
	['ACE_IDENTIFIER_MISSING'] = { code = 'WRN-ACE-101', message = 'A player was denied ACE mapping because the configured identifier was missing.' },
	['JOBSYNC_IDENTIFIER_MISSING'] = { code = 'WRN-JS-101', message = 'JobSync could not update CMS ranks because the configured identifier was missing.' },
}

local ErrorCodes = {
	['API_ERROR'] = { code = 'ERR-CORE-101', message = 'The CMS API version request failed during startup.' },
	['CONFIG_NEW_FOUND'] = { code = 'ERR-CORE-102', message = 'config.NEW.lua was detected and the running configuration is out of date.' },
	['API_ENDPOINT_INVALID'] = { code = 'ERR-CORE-103', message = 'The configured CMS API endpoint is invalid.' },
	['API_DISABLED_FATAL'] = { code = 'ERR-CORE-104', message = 'The CMS API was disabled after a fatal configuration or authentication error.' },
	['API_SERVER_ERROR'] = { code = 'ERR-CORE-105', message = 'The CMS API returned a server-side error.' },
	['API_REQUEST_UNEXPECTED'] = { code = 'ERR-CORE-106', message = 'The CMS API returned an unexpected response.' },
	['API_REQUEST_BLOCKED'] = { code = 'ERR-CORE-107', message = 'An API request was blocked because the resource is in a critical error state.' },
	['SECURITY_CENTER_POST_FAILED'] = { code = 'ERR-SEC-101', message = 'Posting a Security Center event to SonoranCMS failed.' },
	['ACTIVITY_TRACKER_START_FAILED'] = { code = 'ERR-AT-101', message = 'Starting a player activity tracker entry failed.' },
	['ACTIVITY_TRACKER_STOP_FAILED'] = { code = 'ERR-AT-102', message = 'Stopping a player activity tracker entry failed.' },
	['ACTIVITY_TRACKER_RESET_FAILED'] = { code = 'ERR-AT-103', message = 'Resetting active activity tracker entries failed.' },
	['ACE_PERMISSIONS_FETCH_FAILED'] = { code = 'ERR-ACE-102', message = 'Fetching ACE permissions from SonoranCMS failed.' },
	['JOBSYNC_SET_RANKS_FAILED'] = { code = 'ERR-JS-101', message = 'JobSync could not update account ranks in SonoranCMS.' },
	['GAME_PANEL_GARAGE_EXPORT_MISSING'] = { code = 'ERR-GP-201', message = 'A garage resource is missing the export SonoranCMS expects.' },
	['LEGACY_RESOURCE_STOP_FAILED'] = { code = 'ERR-PLUG-101', message = 'A legacy standalone SonoranCMS addon could not be stopped automatically.' },
}

local function buildErrorDocUrl(code)
	return ERROR_DOC_BASE_URL .. tostring(code)
end

local function getLogMeta(level, key)
	local codeTable = level == 'WARNING' and WarningCodes or ErrorCodes
	return codeTable[key] or ErrorCodes[key]
end

local function formatStructuredLog(level, key, message)
	local meta = type(key) == 'string' and getLogMeta(level, key) or nil
	if meta == nil then
		return message or key
	end
	local resolvedMessage = message or meta.message or key
	return ('%s %s More: %s'):format(meta.code, resolvedMessage, buildErrorDocUrl(meta.code))
end

function RegisterErrorCode(key, code, message)
	ErrorCodes[key] = { code = code, message = message }
end

function RegisterWarningCode(key, code, message)
	WarningCodes[key] = { code = code, message = message }
end

function logError(err, msg)
	sendConsole('ERROR', '^1', formatStructuredLog('ERROR', err, msg))
end

function errorLog(err, msg)
	sendConsole('ERROR', '^1', formatStructuredLog('ERROR', err, msg))
end

function warnLog(err, msg)
	sendConsole('WARNING', '^3', formatStructuredLog('WARNING', err, msg))
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

ApiEndpoints = {
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

function registerApiType(type, endpoint)
	ApiEndpoints[type] = endpoint
end
exports('registerApiType', registerApiType)

local rateLimitedEndpoints = {}

function performApiRequest(postData, type, cb)
	-- apply required headers
	local payload = {}
	payload['id'] = Config.CommID
	payload['key'] = Config.APIKey
	payload['serverId'] = Config.serverId
	payload['data'] = postData
	payload['type'] = type
	local endpoint = nil
	if ApiEndpoints[type] ~= nil then
		endpoint = ApiEndpoints[type]
	else
		return warnLog('API_ENDPOINT_UNREGISTERED', ('API request failed: endpoint %s is not registered. Use the registerApiType function to register this endpoint with the appropriate type.'):format(type))
	end
	local url = Config.apiUrl .. tostring(endpoint) .. '/' .. tostring(type:lower())
	assert(type ~= nil, 'No type specified, invalid request.')
	if Config.critError then
		errorLog('API_REQUEST_BLOCKED', 'API request failed: critical error encountered, API version too low, aborting request.')
		return
	end
	if rateLimitedEndpoints[type] == nil then
		PerformHttpRequestS(url, function(statusCode, res, headers)
			if Config.debug_mode and type ~= 'GAMESTATE' then
				debugLog('API Result:', tostring(res))
			end
			if type ~= 'GAMESTATE' then
				debugLog(('type %s called with post data %s to url %s'):format(type, json.encode(payload), url))
			end
			if statusCode == 200 or statusCode == 201 and res ~= nil then
				debugLog('result: ' .. tostring(res))
				if res == 'Sonoran CMS: Backend Service Reached' or res == 'Backend Service Reached' then
					errorLog('API_ENDPOINT_INVALID', ('API ERROR: Invalid endpoint (URL: %s). Ensure you\'re using a valid endpoint.'):format(url))
				else
					if res == nil then
						res = {}
						debugLog('Warning: Response had no result, setting to empty table.')
					end
					cb(res, true)
				end
			elseif statusCode == 400 then
				warnLog('API_BAD_REQUEST', 'Bad request was sent to the API. Enable debug mode and retry your request. Response: ' .. tostring(res))
				-- additional safeguards
				if res == 'INVALID COMMUNITY ID' or res == 'API IS NOT ENABLED FOR THIS COMMUNITY' or string.find(res, 'IS NOT ENABLED FOR THIS COMMUNITY') or res == 'INVALID API KEY' then
					errorLog('API_DISABLED_FATAL', 'Fatal: Disabling API - an error was encountered that must be resolved. Please restart the resource after resolving: ' .. tostring(res))
					Config.critError = true
				end
				cb(res, false)
			elseif statusCode == 404 then -- handle 404 requests, like from CHECK_APIID
				debugLog('404 response found')
				cb(res, false)
			elseif statusCode == 429 then -- rate limited :(
				if rateLimitedEndpoints[type] then
					-- don't warn again, it's spammy. Instead, just print a debug
					debugLog(('Endpoint %s ratelimited. Dropping request.'))
					return
				end
				rateLimitedEndpoints[type] = true
				warnLog('API_RATELIMITED',
								('You are being ratelimited (last request made to %s) - Ignoring all API requests to this endpoint for 60 seconds. If this is happening frequently, please review your configuration to ensure you\'re not sending data too quickly.'):format(
												type))
				SetTimeout(60000, function()
					rateLimitedEndpoints[type] = nil
					infoLog(('Endpoint %s no longer ignored.'):format(type))
				end)
			elseif string.match(tostring(statusCode), '50') then
				errorLog('API_SERVER_ERROR', ('API error returned (%s). Check status.sonoransoftware.com or our Discord to see if there\'s an outage.'):format(statusCode))
				debugLog(('API_ERROR Error returned: %s %s'):format(statusCode, res))
				if type == 'GET_ACCOUNT_RANKS' or type == 'FULL_WHITELIST' then
					cb({}, false)
				end
			else
				errorLog('API_REQUEST_UNEXPECTED', ('CMS API ERROR (from %s): %s %s'):format(url, statusCode, res))
			end
		end, 'POST', json.encode(payload), {
			['Content-Type'] = 'application/json'
		})
	else
		debugLog(('Endpoint %s is ratelimited. Dropped request: %s'):format(type, json.encode(payload)))
	end

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
