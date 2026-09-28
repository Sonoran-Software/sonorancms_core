local helper_name = 'sonorancms_updatehelper'
local update_url = 'https://github.com/Sonoran-Software/sonorancms_core/releases/download/%s/sonorancms_core-%s.zip'
local version_url = 'https://raw.githubusercontent.com/Sonoran-Software/sonorancms_core/master/sonorancms/version.json'
local pendingRestart = false
local updateState = 'idle'
local updateLoopStarted = false
local helper_signal_key = 'sonorancms_updatehelper_action'
local function supportHint(code)
	return code .. ' More: https://sonorancms.com/error/' .. code
end

local function signalUpdateHelper(action)
	SetConvar(helper_signal_key, action or 'core')
end

local function clearUpdateHelperSignal()
	SetConvar(helper_signal_key, '')
end

function doUnzip(path)
	local unzipPath = GetResourcePath(GetCurrentResourceName()) .. '/../../'
	exports[GetCurrentResourceName()]:UnzipFile(path, unzipPath, Config.debug_mode)
end

local function restartUpdatedResource()
	pendingRestart = false
	updateState = 'restarting'
	SetTimeout(5000, function()
		if GetNumPlayerIndices() > 0 and not Config.restartWithPlayers then
			pendingRestart = true
			updateState = 'pending_restart'
			Utilities.Logging.logInfo('Update installed. Waiting until the server is empty to restart sonorancms.')
			return
		end
		Utilities.Logging.logWarn(supportHint('WRN-UPD-101') .. ' Restarting the updated resource...')
		signalUpdateHelper('core')
		ExecuteCommand('ensure ' .. helper_name)
	end)
end

exports('unzipCoreCompleted', function(success, error)
	if updateState ~= 'extracting' then return end
	if success then
		if GetNumPlayerIndices() > 0 and not Config.restartWithPlayers then
			pendingRestart = true
			updateState = 'pending_restart'
			Utilities.Logging.logInfo('Update installed. Waiting until the server is empty to restart sonorancms.')
			return
		end
		restartUpdatedResource()
	else
		updateState = 'idle'
		Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' Failed to extract core update. ' .. tostring(error))
	end
end)

local function doUpdate(latest)
	local releaseUrl = (update_url):format(latest, latest)
	updateState = 'downloading'
	local requested, requestError = pcall(PerformHttpRequest, releaseUrl, function(code, data, _)
		if tonumber(code) ~= 200 or type(data) ~= 'string' or data:sub(1, 2) ~= 'PK' then
			updateState = 'idle'
			Utilities.Logging.logWarn(supportHint('WRN-UPD-102') .. ' Failed to download a valid core update ZIP (HTTP ' .. tostring(code) .. ').')
			return
		end
		local savePath = GetResourcePath(GetCurrentResourceName()) .. '/update.zip'
		local saved, saveError = pcall(function()
			local file = assert(io.open(savePath, 'wb'))
			local wrote, writeError = file:write(data)
			file:close()
			assert(wrote, writeError)
		end)
		if not saved then
			updateState = 'idle'
			Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' Could not save core update: ' .. tostring(saveError))
			return
		end
		Utilities.Logging.logInfo('Core update downloaded. Extracting release...')
		updateState = 'extracting'
		local unzipStarted, unzipError = pcall(doUnzip, savePath)
		if not unzipStarted then
			updateState = 'idle'
			Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' Could not extract core update: ' .. tostring(unzipError))
		end
	end, 'GET')
	if not requested then
		updateState = 'idle'
		Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' Could not request core update: ' .. tostring(requestError))
	end

end

function FileExists(name)
	local f = io.open(name, 'r')
	return f ~= nil and io.close(f)
end

function CopyFile(old_path, new_path)
	local old_file = io.open(old_path, 'rb')
	local new_file = io.open(new_path, 'wb')
	local old_file_sz, new_file_sz
	if not old_file or not new_file then
		return false
	end
	while true do
		local block = old_file:read(2 ^ 13)
		if not block then
			old_file_sz = old_file:seek('end')
			break
		end
		new_file:write(block)
	end
	old_file:close()
	new_file_sz = new_file:seek('end')
	new_file:close()
	return new_file_sz == old_file_sz
end

RegisterNetEvent(GetCurrentResourceName() .. '::CheckConfig', function()
	exports[GetCurrentResourceName()]:CheckConfigFiles(Config.debug_mode)
	if not FileExists(GetResourcePath(GetCurrentResourceName()) .. '/config.lua') then
		CopyFile(GetResourcePath(GetCurrentResourceName()) .. '/config.CHANGEME.lua', GetResourcePath(GetCurrentResourceName()) .. '/config.lua')
		local c = assert(io.open(GetResourcePath(helper_name) .. '/config.lock', 'w+'))
		c:write('core')
		c:close()
		local cc = assert(io.open(GetResourcePath(GetCurrentResourceName()) .. '/config.lua', 'a'))
		cc:write('\n\n-- Remove this after configuring\nconfig.auto_config = true')
		cc:close()
		ExecuteCommand('ensure ' .. helper_name)
	end
end)

local function parseVersion(version)
	if type(version) ~= 'string' then return nil end
	local major, minor, patch = version:match('^(%d+)%.(%d+)%.(%d+)$')
	if not major then return nil end
	return { tonumber(major), tonumber(minor), tonumber(patch) }
end

local function versionIsNewer(latest, current)
	for index = 1, 3 do
		if latest[index] > current[index] then return true end
		if latest[index] < current[index] then return false end
	end
	return false
end

local function showAvailableUpdate(current, latest)
	Utilities.Logging.logInfo(('SonoranCMS update available: %s -> %s. Run sonorancms update in the server console.'):format(current, latest))
end

function RequestCmsUpdate(manual)
	manual = manual == true
	if updateState ~= 'idle' then
		Utilities.Logging.logInfo('An update is already ' .. updateState:gsub('_', ' ') .. '.')
		return false
	end
	local helperPath = GetResourcePath(helper_name)
	if not helperPath then
		Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' The sonorancms_updatehelper resource is missing.')
		return false
	end
	local resourcePath = GetResourcePath(GetCurrentResourceName())
	if FileExists(resourcePath .. '/update.zip') then
		os.remove(resourcePath .. '/update.zip')
		clearUpdateHelperSignal()
	end
	if FileExists(helperPath .. '/config.lock') then
		os.remove(helperPath .. '/config.lock')
	end
	local currentVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)
	updateState = 'checking'
	if manual then Utilities.Logging.logInfo('Checking for SonoranCMS updates...') end
	local requested, requestError = pcall(PerformHttpRequest, version_url, function(code, data, _)
		if tonumber(code) ~= 200 then
			updateState = 'idle'
			Utilities.Logging.logWarn(supportHint('WRN-UPD-103') .. ' Could not check for updates (HTTP ' .. tostring(code) .. ').')
			return
		end
		local decoded, remote = pcall(json.decode, data or '')
		local latest = decoded and type(remote) == 'table' and remote.resource or nil
		local parsedLatest = parseVersion(latest)
		local parsedCurrent = parseVersion(currentVersion)
		if not parsedLatest or not parsedCurrent then
			updateState = 'idle'
			Utilities.Logging.logWarn(supportHint('WRN-UPD-103') .. ' Invalid SonoranCMS version information; update skipped.')
			return
		end
		Config.latestVersion = latest
		if not versionIsNewer(parsedLatest, parsedCurrent) then
			updateState = 'idle'
			if manual then Utilities.Logging.logInfo('SonoranCMS is up to date (' .. currentVersion .. ').') end
			return
		end
		if not manual then
			local isWindows = (os.getenv('OS') or ''):match('^Windows') ~= nil
			if not isWindows or not Config.allowAutoUpdate then
				updateState = 'idle'
				showAvailableUpdate(currentVersion, latest)
				if not isWindows then
					Utilities.Logging.logWarn('Linux automatic updates remain disabled. Run sonorancms update in the server console to install explicitly.')
				elseif Config.allowAutoUpdate == nil then
					Utilities.Logging.logWarn(supportHint('WRN-UPD-104') .. ' Set allowAutoUpdate in config.lua to enable automatic updates.')
				end
				return
			end
		end
		Utilities.Logging.logInfo(('Installing SonoranCMS %s (current %s)...'):format(latest, currentVersion))
		doUpdate(latest)
	end, 'GET')
	if not requested then
		updateState = 'idle'
		Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' Could not check for updates: ' .. tostring(requestError))
	end
	return requested
end

AddEventHandler(GetCurrentResourceName() .. '::StartUpdateLoop', function()
	if updateLoopStarted then return end
	updateLoopStarted = true
	Citizen.CreateThread(function()
		while true do
			RequestCmsUpdate(false)
			Citizen.Wait(60000 * 60)
		end
	end)
	Citizen.CreateThread(function()
		while true do
			if pendingRestart and (GetNumPlayerIndices() == 0 or Config.restartWithPlayers) then
				restartUpdatedResource()
			end
			Citizen.Wait(15000)
		end
	end)
end)

lastLogs = {}
Utilities = {Logging = {logDebug = function(message)
	if Config['debug_mode'] then
		print('^4Debug: ' .. message .. '^0')
	end
	if #lastLogs > 50 then
		table.remove(lastLogs, 1)
		lastLogs[#lastLogs] = message
	else
		lastLogs[#lastLogs] = message
	end
end, logWarn = function(message)
	print('^3Warning: ' .. message .. '^0')
	if #lastLogs > 50 then
		table.remove(lastLogs, 1)
		lastLogs[#lastLogs] = message
	else
		lastLogs[#lastLogs] = message
	end
end, logError = function(message)
	print('^1Error: ' .. message .. '^0')
	if #lastLogs > 50 then
		table.remove(lastLogs, 1)
		lastLogs[#lastLogs] = message
	else
		lastLogs[#lastLogs] = message
	end
end, logInfo = function(message)
	print('^2Info: ' .. message .. '^0')
	if #lastLogs > 50 then
		table.remove(lastLogs, 1)
		lastLogs[#lastLogs] = message
	else
		lastLogs[#lastLogs] = message
	end
end, sendLogs = function(key, name)
	if IsDuplicityVersion() then
		local payload = {}

		payload['type'] = 'UPLOAD_LOGS'

		local postData = {{['key'] = key, ['logs'] = table.concat(lastLogs, '\n'), ['plugins'] = {{['name'] = name, ['version'] = Config['script_version'], ['config'] = Config}}}}

		payload['data'] = postData

		PerformHttpRequest('https://api.sonoransoftware.com/support', function(_, _, _)

		end, 'POST', json.encode(payload), {['Content-Type'] = 'application/json'})
	else
		TriggerServerEvent('SonoranScripts::Logging::Event', GetCurrentResourceName(), lastLogs, key, name)
	end
end}}
