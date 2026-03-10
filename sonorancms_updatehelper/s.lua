ManagedResources = {'sonorancms'}

CreateThread(function()
	local helperSignalKey = 'sonorancms_updatehelper_action'
	local action = GetConvar(helperSignalKey, '')
    local res = GetCurrentResourceName()
    local runLock = LoadResourceFile(res, 'run.lock')
	local hasRunLock = runLock and (runLock:match('^core') or runLock:match('^plugin'))
	local validAction = (action == 'core' or action == 'plugin')

	-- Check both convar signal and run.lock for compatibility during updater transitions.
    if validAction or hasRunLock then
		local mode = validAction and action or runLock
		SetConvar(helperSignalKey, '')
		os.remove(GetResourcePath(res) .. '/run.lock')
		ExecuteCommand('refresh')
		Wait(1000)
        if mode:match('^core') then
			for _, v in pairs(ManagedResources) do
				if GetResourceState(v) ~= 'started' then
					print(('Not restarting resource %s as it is not started. This may be fine. State: %s'):format(v, GetResourceState(v)))
				else
					ExecuteCommand('restart ' .. v)
					Wait(1000)
				end
			end
        elseif mode:match('^plugin') then
			print('Restarting sonorancms resource for plugin updates...')
			if GetResourceState('sonorancms') ~= 'started' then
				print(('Not restarting resource %s as it is not in the started state to avoid server crashing. State: %s'):format('sonorancms', GetResourceState('sonorancms')))
				print('If you are seeing this message, you have started sonorancms_updatehelper in your configuration which is incorrect. Please do not start sonorancms_updatehelper manually.')
				return
			else
				ExecuteCommand('restart sonorancms')
			end
		end
	else
		os.remove(GetResourcePath(res) .. '/run.lock')
		print('sonorancms_updatehelper is for internal use and should not be started as a resource.')
	end
end)
