local helper_name = 'sonorancms_updatehelper'
local update_url = 'https://github.com/Sonoran-Software/sonorancms_core/releases/download/%s/sonorancms_core-%s.zip'
local version_url = 'https://raw.githubusercontent.com/Sonoran-Software/sonorancms_core/master/sonorancms/version.json'
local pendingRestart = false
local helper_signal_key = 'sonorancms_updatehelper_action'

local function normalizeResourcePath(path)
	return (path or ''):gsub('^%.?/?', '')
end

local function readResourceFile(resourceName, filePath)
	return LoadResourceFile(resourceName, normalizeResourcePath(filePath))
end

local function writeResourceFile(resourceName, filePath, contents)
	SaveResourceFile(resourceName, normalizeResourcePath(filePath), contents or '', -1)
end

local function resourceFileExists(resourceName, filePath)
	local contents = readResourceFile(resourceName, filePath)
	return contents ~= nil and contents ~= ''
end

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

exports('unzipCoreCompleted', function(success, error)
	if success then
		if GetNumPlayerIndices() > 0 and not Config.restartWithPlayers then
			pendingRestart = true
			Utilities.Logging.logInfo('Delaying auto-update until server is empty.')
			return
		end
		Utilities.Logging.logWarn(supportHint('WRN-UPD-101') .. ' Auto-restarting...')
		signalUpdateHelper('core')
		Citizen.Wait(5000)
		ExecuteCommand('ensure ' .. helper_name)
	else
		Utilities.Logging.logError(supportHint('ERR-UPD-101') .. ' Failed to download core update. ' .. tostring(json.encode(error)))
	end
end)

local function doUpdate(latest)
	local releaseUrl = (update_url):format(latest, latest)
	PerformHttpRequest(releaseUrl, function(code, data, _)
		if code == 200 then
			local savePath = GetResourcePath(GetCurrentResourceName()) .. '/update.zip'
			writeResourceFile(GetCurrentResourceName(), 'update.zip', data)
			Utilities.Logging.logInfo('Saved file...')
			Utilities.Logging.logInfo('Working our magic, this may take a moment, please be patient...')
			doUnzip(savePath)
		else
			Utilities.Logging.logWarn(supportHint('WRN-UPD-102') .. ' ' .. ('Failed to download from %s: %s %s'):format(releaseUrl, code, data))
		end
	end, 'GET')

end

function FileExists(resourceName, filePath)
	return resourceFileExists(resourceName, filePath)
end

function CopyFile(oldPath, newPath)
	local oldFile = readResourceFile(GetCurrentResourceName(), oldPath)
	if oldFile == nil then
		return false
	end
	writeResourceFile(GetCurrentResourceName(), newPath, oldFile)
	return true
end

RegisterNetEvent(GetCurrentResourceName() .. '::CheckConfig', function()
	exports[GetCurrentResourceName()]:CheckConfigFiles(Config.debug_mode)
	if not FileExists(GetCurrentResourceName(), 'config.lua') then
		CopyFile('config.CHANGEME.lua', 'config.lua')
		writeResourceFile(helper_name, 'config.lock', 'core')
		local configFile = readResourceFile(GetCurrentResourceName(), 'config.lua')
		if configFile ~= nil then
			writeResourceFile(
				GetCurrentResourceName(),
				'config.lua',
				configFile .. '\n\n-- Remove this after configuring\nconfig.auto_config = true'
			)
		end
		ExecuteCommand('ensure ' .. helper_name)
	end
end)

local function RunAutoUpdater()
	local f = readResourceFile(helper_name, 'update.zip')
	if f ~= nil and f ~= '' then
		ExecuteCommand('stop ' .. helper_name)
		writeResourceFile(GetCurrentResourceName(), 'update.zip', '')
		clearUpdateHelperSignal()
	end
	if FileExists(helper_name, 'config.lock') then
		writeResourceFile(helper_name, 'config.lock', '')
	end
	local myVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)

	PerformHttpRequest(version_url, function(code, data, _)
		if code == 200 then
			local remote = json.decode(data)
			if remote == nil then
				Utilities.Logging.logWarn(supportHint('WRN-UPD-103') .. ' ' .. ('Failed to get a valid response for ' .. GetResourceMetadata(GetCurrentResourceName(), 'real_name', 0) .. ' version file. Skipping.'))
				Utilities.Logging.logDebug(('Raw output for %s: %s'):format('version.json', data))
			else
				Config.latestVersion = remote.resource
				local _, _, v1, v2, v3 = string.find(myVersion, '(%d+)%.(%d+)%.(%d+)')
				local _, _, r1, r2, r3 = string.find(remote.resource, '(%d+)%.(%d+)%.(%d+)')
				Utilities.Logging.logDebug(('my: %s remote: %s'):format(myVersion, remote.resource))
				local latestVersion = r3 + (r2 * 100) + (r1 * 1000)
				local localVersion = v3 + (v2 * 100) + (v1 * 1000)

				assert(localVersion ~= nil, 'Failed to parse local version. ' .. tostring(localVersion))
				assert(latestVersion ~= nil, 'Failed to parse remote version. ' .. tostring(latestVersion))

				if latestVersion > localVersion then
					if os.getenv("OS"):match("^Windows") ~= nil then
						-- Running on Windows
						if not Config['allowAutoUpdate'] then
							print('^3|===========================================================================|')
							print('^3|                        ^5SonoranCMS Update Available                        ^3|')
							print('^3|                             ^8Current : ' .. myVersion .. '                               ^3|')
							print('^3|                             ^2Latest  : ' .. remote.resource .. '                               ^3|')
							print('^3| Download at: ^4https://github.com/Sonoran-Software/sonorancms_core          ^3|')
							print('^3|===========================================================================|^7')
							if Config['allowAutoUpdate'] == nil then
								Utilities.Logging.logWarn(supportHint('WRN-UPD-104') .. ' You have not configured the automatic updater. Please set allowAutoUpdate' .. ' in config.lua to allow updates.')
							end
						else
							Utilities.Logging.logInfo('Running auto-update now...')
							doUpdate(remote.resource)
						end
					else
						-- Running on Linux
						print('^3WARNING: Detected Linux Server OS, deferring auto-update until future bugfix update. Server maintainer manual update required...')
						print('^3|===========================================================================|')
						print('^3|                        ^5SonoranCMS Update Available                        ^3|')
						print('^3|                             ^8Current : ' .. myVersion .. '                               ^3|')
						print('^3|                             ^2Latest  : ' .. remote.resource .. '                               ^3|')
						print('^3| Download at: ^4https://github.com/Sonoran-Software/sonorancms_core          ^3|')
						print('^3|===========================================================================|^7')
					end
				end
			end
		end
	end, 'GET')
end

RegisterNetEvent(GetCurrentResourceName() .. '::StartUpdateLoop')
AddEventHandler(GetCurrentResourceName() .. '::StartUpdateLoop', function()
	Citizen.CreateThread(function()
		while true do
			if pendingRestart then
				if GetNumPlayerIndices() > 0 and not Config.restartWithPlayers then
					Utilities.Logging.logWarn(supportHint('WRN-UPD-105') .. ' ' .. 'An update has been applied to ' .. GetResourceMetadata(GetCurrentResourceName(), 'real_name', 0) .. ' but requires a resource restart.'
									                          .. ' Restart delayed until server is empty.')
				else
					Utilities.Logging.logInfo('Server is empty, restarting resources...')
					signalUpdateHelper('core')
					ExecuteCommand('ensure ' .. helper_name)
				end
			else
				RunAutoUpdater()
			end
			Citizen.Wait(60000 * 60)
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
