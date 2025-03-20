local helper_name = 'sonorancms_updatehelper'
local update_url = 'https://github.com/Sonoran-Software/sonorancms_core/releases/download/%s/sonorancms_core-%s.zip'
local version_url = 'https://raw.githubusercontent.com/Sonoran-Software/sonorancms_core/master/sonorancms/version.json'
local pendingRestart = false

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
		Utilities.Logging.logWarn('Auto-restarting...')
		local f = assert(io.open(GetResourcePath(helper_name) .. '/run.lock', 'w+'))
		f:write('core')
		f:close()
		Citizen.Wait(5000)
		ExecuteCommand('ensure ' .. helper_name)
	else
		Utilities.Logging.logError('Failed to download core update. ' .. tostring(json.encode(error)))
	end
end)

local function doUpdate(latest)
	local releaseUrl = (update_url):format(latest, latest)
	PerformHttpRequest(releaseUrl, function(code, data, _)
		if code == 200 then
			local savePath = GetResourcePath(GetCurrentResourceName()) .. '/update.zip'
			local f = assert(io.open(savePath, 'wb'))
			f:write(data)
			f:close()
			Utilities.Logging.logInfo('Saved file...')
			Utilities.Logging.logInfo('Working our magic, this may take a moment, please be patient...')
			doUnzip(savePath)
		else
			Utilities.Logging.logWarn(('Failed to download from %s: %s %s'):format(releaseUrl, code, data))
		end
	end, 'GET')

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

local function RunAutoUpdater()
	local f = LoadResourceFile(GetResourcePath(helper_name), '/update.zip')
	if f ~= nil then
		ExecuteCommand('stop ' .. helper_name)
		os.remove(GetResourcePath(GetCurrentResourceName()) .. '/update.zip')
		os.remove(GetResourcePath(helper_name) .. '/run.lock')
	end
	if FileExists(GetResourcePath(helper_name) .. '/config.lock') then
		os.remove(GetResourcePath(helper_name) .. '/config.lock')
	end
	local myVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)

	PerformHttpRequest(version_url, function(code, data, _)
		if code == 200 then
			local remote = json.decode(data)
			if remote == nil then
				Utilities.Logging.logWarn(('Failed to get a valid response for ' .. GetResourceMetadata(GetCurrentResourceName(), 'real_name', 0) .. ' version file. Skipping.'))
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
								Utilities.Logging.logWarn('You have not configured the automatic updater. Please set allowAutoUpdate' .. ' in config.lua to allow updates.')
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
					Utilities.Logging.logWarn('An update has been applied to ' .. GetResourceMetadata(GetCurrentResourceName(), 'real_name', 0) .. ' but requires a resource restart.'
									                          .. ' Restart delayed until server is empty.')
				else
					Utilities.Logging.logInfo('Server is empty, restarting resources...')
					local f = assert(io.open(GetResourcePath(helper_name) .. '/run.lock', 'w+'))
					f:write('core')
					f:close()
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
