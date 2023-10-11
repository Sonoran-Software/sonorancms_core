local vehicleGamePool = {}
local tonumber = tonumber
local loggerBuffer = {}
local explosionTypes = {'GRENADE', 'GRENADELAUNCHER', 'STICKYBOMB', 'MOLOTOV', 'ROCKET', 'TANKSHELL', 'HI_OCTANE', 'CAR', 'PLANE', 'PETROL_PUMP', 'BIKE', 'DIR_STEAM', 'DIR_FLAME', 'DIR_WATER_HYDRANT',
	'DIR_GAS_CANISTER', 'BOAT', 'SHIP_DESTROY', 'TRUCK', 'BULLET', 'SMOKEGRENADELAUNCHER', 'SMOKEGRENADE', 'BZGAS', 'FLARE', 'GAS_CANISTER', 'EXTINGUISHER', 'PROGRAMMABLEAR', 'TRAIN', 'BARREL',
	'PROPANE', 'BLIMP', 'DIR_FLAME_EXPLODE', 'TANKER', 'PLANE_ROCKET', 'VEHICLE_BULLET', 'GAS_TANK', 'BIRD_CRAP', 'RAILGUN', 'BLIMP2', 'FIREWORK', 'SNOWBALL', 'PROXMINE', 'VALKYRIE_CANNON',
	'AIR_DEFENCE', 'PIPEBOMB', 'VEHICLEMINE', 'EXPLOSIVEAMMO', 'APCSHELL', 'BOMB_CLUSTER', 'BOMB_GAS', 'BOMB_INCENDIARY', 'BOMB_STANDARD', 'TORPEDO', 'TORPEDO_UNDERWATER', 'BOMBUSHKA_CANNON',
	'BOMB_CLUSTER_SECONDARY', 'HUNTER_BARRAGE', 'HUNTER_CANNON', 'ROGUE_CANNON', 'MINE_UNDERWATER', 'ORBITAL_CANNON', 'BOMB_STANDARD_WIDE', 'EXPLOSIVEAMMO_SHOTGUN', 'OPPRESSOR2_CANNON', 'MORTAR_KINETIC',
	'VEHICLEMINE_KINETIC', 'VEHICLEMINE_EMP', 'VEHICLEMINE_SPIKE', 'VEHICLEMINE_SLICK', 'VEHICLEMINE_TAR', 'SCRIPT_DRONE', 'RAYGUN', 'BURIEDMINE', 'SCRIPT_MISSIL'}

--- logger
--- Sends logs to the logging buffer, then to the SonoranCMS game panel
---@param src number the source of the player who did the action
---@param type string the action type
---@param data table|nil the event data
local function serverLogger(src, type, data)
	loggerBuffer[#loggerBuffer + 1] = {src = src, type = type, data = data or false, ts = os.time()}
	while #loggerBuffer > 1000 do
		table.remove(loggerBuffer, 1)
	end
end

--- Checks is a property is invalid
---@param property any
---@param invalidType any
local function isInvalid(property, invalidType)
	return (property == nil or property == invalidType)
end

--- Removes any quotes to ensure functionality
---@param inputString string
---@return string
local function escapeQuotes(inputString)
	return inputString:gsub('[\'"]', '\\%0')
end

--- Encodes the combinale array for items to be correct
---@param combinableData table
---@return string
local function encodeCombinable(combinableData)
	local acceptArray = {}
	for _, acceptItem in ipairs(combinableData.accept) do
		table.insert(acceptArray, '"' .. acceptItem .. '"')
	end
	local anim = combinableData.anim
	local animString = ''
	if anim then
		animString = string.format(', anim = {text = "%s", dict = "%s", timeOut = %d, lib = "%s"}', anim.text, anim.dict, anim.timeOut, anim.lib)
	end

	local combinableLine = string.format('{accept = {%s}, reward = "%s"%s},', table.concat(acceptArray, ','), combinableData.reward, animString)
	return combinableLine
end

--- Encodes the combinale array for items to be correct
---@param combinableData table
---@return string
local function sortByKey(a, b, key)
	if a and b then
		return a[key] < b[key]
	else
		return nil
	end
end

--- Encodes the combinale array for items to be correct
---@param combinableData table
---@return string
local function sortArrayBy(array, key)
	if array then
		table.sort(array, function(a, b)
			if a and b then
				return sortByKey(a, b, key)
			else
				return nil
			end
		end)
	else
		return nil
	end
end

CreateThread(function()
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_KICK_PLAYER', function(data)
		if data ~= nil then
			local targetPlayer = nil
			for i = 0, GetNumPlayerIndices() - 1 do
				local p = GetPlayerFromIndex(i)
				if tonumber(p) == tonumber(data.data.playerSource) then
					targetPlayer = p
				end
			end
			if targetPlayer ~= nil then
				local reason = 'Kicked By SonoranCMS Management Panel: ' .. data.data.reason
				local targetPlayerName = GetPlayerName(targetPlayer)
				DropPlayer(targetPlayer, reason)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' dropping player ' .. targetPlayerName .. ' for reason: ' .. reason)
				manuallySendPayload()
			else
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but player with source ' .. data.data.playerSource .. ' was not found')
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_SET_PLAYER_MONEY', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `players` WHERE `citizenid` = ? LIMIT 1', {data.data.citizenId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the PlayerData for ' .. data.data.citizenId .. ' was not found')
					return
				end
				local PlayerData = row
				local PlayerDataMoney = json.decode(PlayerData.money)
				local validType = false
				for k, _ in pairs(PlayerDataMoney) do
					if k == data.data.moneyType then
						PlayerDataMoney[k] = data.data.amount
						validType = true
					end
				end
				PlayerDataMoney = json.encode(PlayerDataMoney)
				if validType then
					MySQL.update('UPDATE players SET money = ? WHERE citizenid = ?', {PlayerDataMoney, data.data.citizenId})
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' setting money for ' .. PlayerData.name .. ' to ' .. PlayerDataMoney)
					manuallySendPayload()
				else
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but money type ' .. data.data.moneyType .. ' was not found')
				end
			end)
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_DESPAWN_VEHICLE', function(data)
		if data ~= nil then
			for i = 0, GetNumPlayerIndices() - 1 do
				local p = GetPlayerFromIndex(i)
				if p ~= nil then
					TriggerClientEvent('SonoranCMS::core::DeleteVehicle', p, data.data.vehicleHandle)
				end
			end
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' despawning vehicle with handle ' .. data.data.vehicleHandle)
			manuallySendPayload()
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but vehicle with handle ' .. data.data.vehicleHandle .. ' was not found')
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REPAIR_VEHICLE', function(data)
		if data ~= nil then
			for i = 0, GetNumPlayerIndices() - 1 do
				local p = GetPlayerFromIndex(i)
				if p ~= nil then
					TriggerClientEvent('SonoranCMS::core::RepairVehicle', p, data.data.vehicleHandle)
				end
			end
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' repairing vehicle with handle ' .. data.data.vehicleHandle)
			manuallySendPayload()
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but vehicle with handle ' .. data.data.vehicleHandle .. ' was not found')
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_WARN_PLAYER', function(data)
		if data ~= nil then
			local targetPlayer = nil
			for i = 0, GetNumPlayerIndices() - 1 do
				local p = GetPlayerFromIndex(i)
				if tonumber(p) == tonumber(data.data.playerSource) then
					targetPlayer = p
				end
			end
			if targetPlayer ~= nil then
				local targetPlayerName = GetPlayerName(targetPlayer)
				TriggerClientEvent('SonoranCMS::core::HandleWarnedPlayer', targetPlayer, data.data.message)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' warning player ' .. targetPlayerName .. ' for reason: ' .. data.data.message)
				manuallySendPayload()
			else
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but player with source ' .. data.data.playerSource .. ' was not found')
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'EXECUTE_RESOURCE_COMMAND', function(data)
		if data ~= nil then
			if data.data.resourceName then
				ExecuteCommand(data.data.command .. ' ' .. data.data.resourceName)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' executing command ' .. data.data.command .. ' ' .. data.data.resourceName)
				manuallySendPayload()
			else
				ExecuteCommand(data.data.command)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' executing command ' .. data.data.command)
				manuallySendPayload()
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_SET_CHAR_INFO', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `players` WHERE `citizenid` = ? LIMIT 1', {data.data.citizenId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the PlayerData for ' .. data.data.citizenId .. ' was not found')
					return
				end
				local PlayerData = row
				PlayerData.charinfo = json.decode(PlayerData.charinfo)
				if data.data.charInfo.firstName and data.data.charInfo.firstName ~= '' then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Setting first name to ' .. data.data.charInfo.firstName)
					PlayerData.charinfo.firstname = data.data.charInfo.firstName
				end
				if data.data.charInfo.lastName and data.data.charInfo.lastName ~= '' then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Setting last name to ' .. data.data.charInfo.lastName)
					PlayerData.charinfo.lastname = data.data.charInfo.lastName
				end
				if data.data.charInfo.birthDate and data.data.charInfo.birthDate ~= '' then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Setting birth date to ' .. data.data.charInfo.birthDate)
					PlayerData.charinfo.birthdate = data.data.charInfo.birthDate
				end
				if data.data.charInfo.gender and data.data.charInfo.gender ~= '' then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Setting gender to ' .. data.data.charInfo.gender)
					PlayerData.charinfo.gender = data.data.charInfo.gender
				end
				if data.data.charInfo.nationality and data.data.charInfo.nationality ~= '' then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Setting nationality to ' .. data.data.charInfo.nationality)
					PlayerData.charinfo.nationality = data.data.charInfo.nationality
				end
				if data.data.charInfo.phoneNumber and data.data.charInfo.phoneNumber ~= '' then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Setting phone number to ' .. data.data.charInfo.phoneNumber)
					PlayerData.charinfo.phone = data.data.charInfo.phoneNumber
				end
				local NewCharInfo = json.encode(PlayerData.charinfo)
				MySQL.update('UPDATE players SET charinfo = ? WHERE citizenid = ?', {NewCharInfo, PlayerData.citizenid}, function(affectedRows)
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Updated charinfo for ' .. PlayerData.name .. ' to ' .. NewCharInfo .. ' with ' .. affectedRows .. ' rows affected')
				end)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' saving player ' .. PlayerData.name)
				manuallySendPayload()
			end)
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but character ID ' .. data.data.citizenId .. ' was not found')
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_SET_CHAR_VEHICLE', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `player_vehicles` WHERE `id` = ? LIMIT 1', {data.data.vehicleId}, function(row)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' saving vehicle ' .. data.data.vehicleId)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the vehicle with ID ' .. data.data.vehicleId .. ' was not found')
					return
				else
					local vehData = row
					if data.data.plate and data.data.plate ~= '' then
						vehData.plate = data.data.plate
					end
					if data.data.garage and data.data.garage ~= '' then
						vehData.garage = data.data.garage
					end
					if data.data.fuel and data.data.fuel ~= '' then
						vehData.fuel = data.data.fuel
					end
					if data.data.engine and data.data.engine ~= '' then
						vehData.engine = data.data.engine
					end
					if data.data.body and data.data.body ~= '' then
						vehData.body = data.data.body
					end
					if data.data.state and data.data.state ~= '' then
						vehData.state = data.data.state
					end
					if data.data.mileage and data.data.mileage ~= '' then
						vehData.drivingdistance = data.data.mileage
					end
					if data.data.balance and data.data.balance ~= '' then
						vehData.balance = data.data.balance
					end
					if data.data.paymentAmount and data.data.paymentAmount ~= '' then
						vehData.paymentamount = data.data.paymentAmount
					end
					if data.data.paymentsLeft and data.data.paymentsLeft ~= '' then
						vehData.paymentsleft = data.data.paymentsLeft
					end
					if data.data.financeTime and data.data.financeTime ~= '' then
						vehData.financetime = data.data.financeTime
					end
					MySQL.update(
									'UPDATE player_vehicles SET plate = ?, garage = ?, fuel = ?, engine = ?, body = ?, state = ?, drivingdistance = ?, balance = ?, paymentamount = ?, paymentsleft = ?, financetime = ? WHERE id = ?',
									{vehData.plate, vehData.garage, vehData.fuel, vehData.engine, vehData.body, vehData.state, vehData.drivingdistance, vehData.balance, vehData.paymentamount, vehData.paymentsleft,
										vehData.financetime, data.data.vehicleId}, function(affectedRows)
										TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Updated vehicle metadata for ' .. data.data.vehicleId .. ' to ' .. json.encode(vehData) .. ' with ' .. affectedRows .. ' rows affected')
									end)
					manuallySendPayload()
				end
			end)
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_ADD_CHAR_VEHICLE', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `players` WHERE `citizenid` = ? LIMIT 1', {data.data.citizenId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the PlayerData for ' .. data.data.citizenId .. ' was not found')
					return
				else
					local PlayerData = row
					PlayerData.charinfo = json.decode(PlayerData.charinfo)
					MySQL.insert('INSERT INTO player_vehicles (citizenid, garage, vehicle, plate, state) VALUES (?, ?, ?, ?, ?)',
					             {PlayerData.citizenid, data.data.garage, data.data.model, data.data.plate, data.data.state}, function(affectedRows)
						TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Added vehicle metadata for ' .. PlayerData.name .. ' to ' .. vehData .. ' with ' .. affectedRows .. ' rows affected')
					end)
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' saving player ' .. PlayerData.name)
					manuallySendPayload()
				end
			end)
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but character ID ' .. data.data.citizenId .. ' was not found')
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_TRANSFER_CHAR_VEHICLE', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `player_vehicles` WHERE `id` = ? LIMIT 1', {data.data.vehicleId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the vehicle with ID ' .. data.data.vehicleId .. ' was not found')
					return
				else
					MySQL.update('UPDATE player_vehicles SET citizenid = ? WHERE id = ?', {data.data.newCitizenId, data.data.vehicleId}, function(affectedRows)
						TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Updated vehicle owner for ' .. data.data.vehicleId .. ' to ' .. data.data.newCitizenId .. ' with ' .. affectedRows .. ' rows affected')
					end)
					manuallySendPayload()
				end
			end)
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REPAIR_CHAR_VEHICLE', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `player_vehicles` WHERE `id` = ? LIMIT 1', {data.data.vehicleId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the vehicle with ID ' .. data.data.vehicleId .. ' was not found')
					return
				else
					MySQL.update('UPDATE player_vehicles SET engine = ?, body = ? WHERE id = ?', {1000, 1000, data.data.vehicleId}, function(affectedRows)
						TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Updated vehicle health for ' .. data.data.vehicleId .. ' to 1000 with ' .. affectedRows .. ' rows affected')
					end)
					manuallySendPayload()
				end
			end)
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_DELETE_CHAR_VEHICLE', function(data)
		if data ~= nil then
			MySQL.single('SELECT * FROM `player_vehicles` WHERE `id` = ? LIMIT 1', {data.data.vehicleId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the vehicle with ID ' .. data.data.vehicleId .. ' was not found')
					return
				else
					MySQL.query('DELETE FROM player_vehicles WHERE id = ?', {data.data.vehicleId}, function(affectedRows)
						TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Deleted vehicle with ID ' .. data.data.vehicleId .. ' with ' .. affectedRows .. ' rows affected')
					end)
					manuallySendPayload()
				end
			end)
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REMOVE_GANG_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/gangs.lua')
			local validGangs = {}
			local function filterGangs(gangs)
				local validGangs = {}
				for gangName, gangData in pairs(gangs) do
					validGangs[gangName] = gangData
				end
				return validGangs
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'gangData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedGangs = tempEnv.QBShared and tempEnv.QBShared.Gangs
			if not loadedGangs or next(loadedGangs) == nil then
				print('Error: QBShared.Gangs table is missing or empty.')
				return
			end
			validGangs = filterGangs(loadedGangs)
			if not validGangs[data.data.gangId] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Gang ' .. data.data.gangId .. ' does not exist.')
				return
			else
				validGangs[data.data.gangId] = nil
				local function convertToPlainText(gangsTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.Gangs = {')
					for gangName, gangData in pairs(gangsTable) do
						local gangLine = '\t[\'' .. gangName .. '\'] = {'
						table.insert(lines, gangLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', gangData.label)
						table.insert(lines, labelLine)
						table.insert(lines, '\t\tgrades = {')
						for gradeIndex, gradeData in pairs(gangData.grades) do
							if gradeData.isboss then
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', isboss = %s },', gradeIndex, gradeData.name, gradeData.isboss)
								table.insert(lines, gradeLine)
							else
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\' },', gradeIndex, gradeData.name)
								table.insert(lines, gradeLine)
							end
						end
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validGangs)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' removing gang ' .. data.data.gangId)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving gangs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/gangs.lua', modifiedData, -1)
				manuallySendPayload()
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_EDIT_GANG_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/gangs.lua')
			local validGangs = {}
			local function filterGangs(gangs)
				local validGangs = {}
				for gangName, gangData in pairs(gangs) do
					validGangs[gangName] = gangData
				end
				return validGangs
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'gangData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedGangs = tempEnv.QBShared and tempEnv.QBShared.Gangs
			if not loadedGangs or next(loadedGangs) == nil then
				print('Error: QBShared.Gangs table is missing or empty.')
				return
			end
			validGangs = filterGangs(loadedGangs)
			if not validGangs[data.data.id] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Gang ' .. data.data.id .. ' does not exist.')
				return
			else
				local gradesTable = {}
				for gradeIndex, gradeData in pairs(data.data.grades) do
					if gradeData.isBoss then
						gradesTable[gradeIndex - 1] = {name = gradeData.name, isboss = gradeData.isBoss}
					else
						gradesTable[gradeIndex - 1] = {name = gradeData.name}
					end
				end
				validGangs[data.data.id] = {label = data.data.label, grades = gradesTable}
				local function convertToPlainText(gangsTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.Gangs = {')
					for gangName, gangData in pairs(gangsTable) do
						local gangLine = '\t[\'' .. gangName .. '\'] = {'
						table.insert(lines, gangLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', gangData.label)
						table.insert(lines, labelLine)
						table.insert(lines, '\t\tgrades = {')
						for gradeIndex, gradeData in pairs(gangData.grades) do
							if gradeData.isboss then
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', isboss = %s },', gradeIndex, gradeData.name, gradeData.isboss)
								table.insert(lines, gradeLine)
							else
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\' },', gradeIndex, gradeData.name)
								table.insert(lines, gradeLine)
							end
						end
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validGangs)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' editing gang ' .. data.data.id)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving gangs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/gangs.lua', modifiedData, -1)
				manuallySendPayload()
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_ADD_GANG_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/gangs.lua')
			local validGangs = {}
			local function filterGangs(gangs)
				local validGangs = {}
				for gangName, gangData in pairs(gangs) do
					validGangs[gangName] = gangData
				end
				return validGangs
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'gangData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedGangs = tempEnv.QBShared and tempEnv.QBShared.Gangs
			if not loadedGangs or next(loadedGangs) == nil then
				print('Error: QBShared.Gangs table is missing or empty.')
				return
			end
			validGangs = filterGangs(loadedGangs)
			if validGangs[data.data.id] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Gang ' .. data.data.id .. ' already exists.')
				return
			else
				local gradesTable = {}
				for gradeIndex, gradeData in pairs(data.data.grades) do
					if gradeData.isBoss then
						gradesTable[gradeIndex - 1] = {name = gradeData.name, isboss = gradeData.isBoss}
					else
						gradesTable[gradeIndex - 1] = {name = gradeData.name}
					end
				end
				validGangs[data.data.id] = {label = data.data.label, grades = gradesTable}
				exports['qb-core']:AddGang(data.data.id, {label = data.data.label, grades = gradesTable})
				local function convertToPlainText(gangsTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.Gangs = {')
					for gangName, gangData in pairs(gangsTable) do
						local gangLine = '\t[\'' .. gangName .. '\'] = {'
						table.insert(lines, gangLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', gangData.label)
						table.insert(lines, labelLine)
						table.insert(lines, '\t\tgrades = {')
						for gradeIndex, gradeData in pairs(gangData.grades) do
							if gradeData.isboss then
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', isboss = %s },', gradeIndex, gradeData.name, gradeData.isboss)
								table.insert(lines, gradeLine)
							else
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\' },', gradeIndex, gradeData.name)
								table.insert(lines, gradeLine)
							end
						end
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validGangs)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' adding gang ' .. data.data.id)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving gangs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/gangs.lua', modifiedData, -1)
				manuallySendPayload()
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REMOVE_JOB_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/jobs.lua')
			local validJobs = {}
			local function filterJobs(jobs)
				local validJobs = {}
				for jobName, jobData in pairs(jobs) do
					validJobs[jobName] = jobData
				end
				return validJobs
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'jobData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedJobs = tempEnv.QBShared and tempEnv.QBShared.Jobs
			if not loadedJobs or next(loadedJobs) == nil then
				print('Error: QBShared.Jobs table is missing or empty.')
				return
			end
			validJobs = filterJobs(loadedJobs)
			if not validJobs[data.data.jobId] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Job ' .. data.data.jobId .. ' does not exist.')
				return
			else
				validJobs[data.data.jobId] = nil
				local function convertToPlainText(jobTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.ForceJobDefaultDutyAtLogin = true -- true: Force duty state to jobdefaultDuty | false: set duty state from database last saved')
					table.insert(lines, 'QBShared.Jobs = {')
					for jobName, jobData in pairs(jobTable) do
						local gangLine = '\t[\'' .. jobName .. '\'] = {'
						table.insert(lines, gangLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', jobData.label)
						table.insert(lines, labelLine)
						if jobData.type then
							local typeLine = '\t\ttype = \'' .. jobData.type .. '\','
							table.insert(lines, typeLine)
						end
						if jobData.defaultDuty ~= nil then
							local defaultDutyLine = '\t\tdefaultDuty = ' .. tostring(jobData.defaultDuty) .. ','
							table.insert(lines, defaultDutyLine)
						end
						if jobData.offDutyPay ~= nil then
							local offDutyPayLine = '\t\toffDutyPay = ' .. tostring(jobData.offDutyPay) .. ','
							table.insert(lines, offDutyPayLine)
						end
						table.insert(lines, '\t\tgrades = {')
						for gradeIndex, gradeData in pairs(jobData.grades) do
							if gradeData.isboss then
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', payment = %s, isboss = %s },', gradeIndex, gradeData.name, gradeData.payment, gradeData.isboss)
								table.insert(lines, gradeLine)
							else
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', payment = %s },', gradeIndex, gradeData.name, gradeData.payment)
								table.insert(lines, gradeLine)
							end
						end
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validJobs)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' removing job ' .. data.data.jobId)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving jobs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/jobs.lua', modifiedData, -1)
				manuallySendPayload()
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_EDIT_JOB_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/jobs.lua')
			local validJobs = {}
			local function filterJobs(jobs)
				local validJobs = {}
				for jobName, jobData in pairs(jobs) do
					validJobs[jobName] = jobData
				end
				return validJobs
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'jobData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedJobs = tempEnv.QBShared and tempEnv.QBShared.Jobs
			if not loadedJobs or next(loadedJobs) == nil then
				print('Error: QBShared.Jobs table is missing or empty.')
				return
			end
			validJobs = filterJobs(loadedJobs)
			if not validJobs[data.data.id] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Job ' .. data.data.id .. ' does not exist.')
				return
			else
				local gradesTable = {}
				for gradeIndex, gradeData in pairs(data.data.grades) do
					if gradeData.isBoss then
						gradesTable[gradeIndex - 1] = {name = gradeData.name, payment = gradeData.payment, isboss = gradeData.isBoss}
					else
						gradesTable[gradeIndex - 1] = {name = gradeData.name, payment = gradeData.payment}
					end
				end
				validJobs[data.data.id] = {type = data.data.type, label = data.data.label, grades = gradesTable, defaultDuty = data.data.defaultDuty, offDutyPay = data.data.offDutyPay}
				local function convertToPlainText(jobTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.ForceJobDefaultDutyAtLogin = true -- true: Force duty state to jobdefaultDuty | false: set duty state from database last saved')
					table.insert(lines, 'QBShared.Jobs = {')
					for jobName, jobData in pairs(jobTable) do
						local gangLine = '\t[\'' .. jobName .. '\'] = {'
						table.insert(lines, gangLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', jobData.label)
						table.insert(lines, labelLine)
						if jobData.type and jobData.type ~= nil then
							local typeLine = '\t\ttype = \'' .. jobData.type .. '\','
							table.insert(lines, typeLine)
						end
						if jobData.defaultDuty ~= nil then
							local defaultDutyLine = '\t\tdefaultDuty = ' .. tostring(jobData.defaultDuty) .. ','
							table.insert(lines, defaultDutyLine)
						end
						if jobData.offDutyPay ~= nil then
							local offDutyPayLine = '\t\toffDutyPay = ' .. tostring(jobData.offDutyPay) .. ','
							table.insert(lines, offDutyPayLine)
						end
						table.insert(lines, '\t\tgrades = {')
						for gradeIndex, gradeData in pairs(jobData.grades) do
							if gradeData.isboss then
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', payment = %s, isboss = %s },', gradeIndex, gradeData.name, gradeData.payment, gradeData.isboss)
								table.insert(lines, gradeLine)
							else
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', payment = %s },', gradeIndex, gradeData.name, gradeData.payment)
								table.insert(lines, gradeLine)
							end
						end
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validJobs)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' editing job ' .. data.data.id)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving jobs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/jobs.lua', modifiedData, -1)
				manuallySendPayload()
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_ADD_JOB_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/jobs.lua')
			local validJobs = {}
			local function filterJobs(jobs)
				local validJobs = {}
				for jobName, jobData in pairs(jobs) do
					validJobs[jobName] = jobData
				end
				return validJobs
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'jobData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedJobs = tempEnv.QBShared and tempEnv.QBShared.Jobs
			if not loadedJobs or next(loadedJobs) == nil then
				print('Error: QBShared.Jobs table is missing or empty.')
				return
			end
			validJobs = filterJobs(loadedJobs)
			if validJobs[data.data.id] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Job ' .. data.data.id .. ' already exist.')
				return
			else
				local gradesTable = {}
				for gradeIndex, gradeData in pairs(data.data.grades) do
					if gradeData.isBoss then
						gradesTable[gradeIndex - 1] = {name = gradeData.name, payment = gradeData.payment, isboss = gradeData.isBoss}
					else
						gradesTable[gradeIndex - 1] = {name = gradeData.name, payment = gradeData.payment}
					end
				end
				validJobs[data.data.id] = {type = data.data.type, label = data.data.label, grades = gradesTable, defaultDuty = data.data.defaultDuty, offDutyPay = data.data.offDutyPay}
				exports['qb-core']:AddJob(data.data.id, {label = data.data.label, grades = gradesTable, defaultDuty = data.data.defaultDuty, offDutyPay = data.data.offDutyPay})
				local function convertToPlainText(jobTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.ForceJobDefaultDutyAtLogin = true -- true: Force duty state to jobdefaultDuty | false: set duty state from database last saved')
					table.insert(lines, 'QBShared.Jobs = {')
					for jobName, jobData in pairs(jobTable) do
						local gangLine = '\t[\'' .. jobName .. '\'] = {'
						table.insert(lines, gangLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', jobData.label)
						table.insert(lines, labelLine)
						if jobData.type and jobData.type ~= nil then
							local typeLine = '\t\ttype = \'' .. jobData.type .. '\','
							table.insert(lines, typeLine)
						end
						if jobData.defaultDuty ~= nil then
							local defaultDutyLine = '\t\tdefaultDuty = ' .. tostring(jobData.defaultDuty) .. ','
							table.insert(lines, defaultDutyLine)
						end
						if jobData.offDutyPay ~= nil then
							local offDutyPayLine = '\t\toffDutyPay = ' .. tostring(jobData.offDutyPay) .. ','
							table.insert(lines, offDutyPayLine)
						end
						table.insert(lines, '\t\tgrades = {')
						for gradeIndex, gradeData in pairs(jobData.grades) do
							if gradeData.isboss then
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', payment = %s, isboss = %s },', gradeIndex, gradeData.name, gradeData.payment, gradeData.isboss)
								table.insert(lines, gradeLine)
							else
								local gradeLine = string.format('\t\t\t[\'%s\'] = { name = \'%s\', payment = %s },', gradeIndex, gradeData.name, gradeData.payment)
								table.insert(lines, gradeLine)
							end
						end
						table.insert(lines, '\t\t},')
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validJobs)
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' adding job ' .. data.data.id)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving jobs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/jobs.lua', modifiedData, -1)
				manuallySendPayload()
			end
		end
	end)
	-- Adding Items to QBCore
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_ADD_ITEM_CONFIG', function(data)
		if data ~= nil then
			QBCore = exports['qb-core']:GetCoreObject()
			local item = {name = data.data.name, label = data.data.label, weight = data.data.weight or 0, type = data.data.type, image = data.data.image or '', description = data.data.description or '',
				unique = data.data.unique or false, useable = data.data.useable or false, ammoType = data.data.ammoType or nil, shouldClose = data.data.shouldClose or false,
				combinable = data.data.combinable or nil}
			QBCore.Functions.AddItem(item.name, item)
			local originalData = LoadResourceFile('qb-core', './shared/items.lua')
			local validItems = {}
			local function filterJobs(items)
				local validItems = {}
				for itemName, itemData in pairs(items) do
					validItems[itemName] = itemData
				end
				return validItems
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'itemData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedItems = tempEnv.QBShared and tempEnv.QBShared.Items
			if not loadedItems or next(loadedItems) == nil then
				print('Error: QBShared.Items table is missing or empty.')
				return
			end
			validItems = filterJobs(loadedItems)
			if validItems[data.data.name] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Item ' .. data.data.name .. ' already exist.')
				return
			else
				validItems[data.data.name] = {name = data.data.name, label = data.data.label, weight = data.data.weight or 0, type = data.data.type, image = data.data.image or '',
					description = data.data.description or '', unique = data.data.unique or false, useable = data.data.useable or false, ammoType = data.data.ammoType or nil,
					shouldClose = data.data.shouldClose or false, combinable = data.data.combinable or nil}
				local function convertToPlainText(itemTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.Items = {')
					for itemName, itemData in pairs(itemTable) do
						local itemLine = '\t[\'' .. itemName .. '\'] = {'
						table.insert(lines, itemLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', itemData.label)
						table.insert(lines, labelLine)
						if itemData.type and itemData.type ~= nil then
							local typeLine = '\t\ttype = \'' .. itemData.type .. '\','
							table.insert(lines, typeLine)
						end
						if itemData.weight ~= nil then
							local weightLine = '\t\tweight = ' .. tostring(itemData.weight) .. ','
							table.insert(lines, weightLine)
						end
						if itemData.image and itemData.image ~= '' then
							local imageLine = '\t\timage = \'' .. itemData.image .. '\','
							table.insert(lines, imageLine)
						end
						if itemData.description and itemData.description ~= '' then
							local descLine = '\t\tdescription = \'' .. escapeQuotes(itemData.description) .. '\','
							table.insert(lines, descLine)
						end
						if itemData.unique ~= nil then
							local uniqueLine = '\t\tunique = ' .. tostring(itemData.unique) .. ','
							table.insert(lines, uniqueLine)
						end
						if itemData.useable ~= nil then
							local useableLine = '\t\tuseable = ' .. tostring(itemData.useable) .. ','
							table.insert(lines, useableLine)
						end
						if itemData.ammoType ~= nil then
							local ammoTypeLine = '\t\tammoType = \'' .. itemData.ammoType .. '\','
							table.insert(lines, ammoTypeLine)
						end
						if itemData.shouldClose ~= nil then
							local shouldCloseLine = '\t\tshouldClose = ' .. tostring(itemData.shouldClose) .. ','
							table.insert(lines, shouldCloseLine)
						end
						if itemData.combinable ~= nil then
							local combinableLine = '\t\tcombinable = ' .. encodeCombinable(itemData.combinable) .. ''
							table.insert(lines, combinableLine)
						end
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validItems)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving jobs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/items.lua', modifiedData, -1)
				manuallySendPayload()
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' adding item ' .. data.data.name)
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_EDIT_ITEM_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/items.lua')
			local validItems = {}
			local function filterJobs(items)
				local validItems = {}
				for itemName, itemData in pairs(items) do
					validItems[itemName] = itemData
				end
				return validItems
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'itemData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedItems = tempEnv.QBShared and tempEnv.QBShared.Items
			if not loadedItems or next(loadedItems) == nil then
				print('Error: QBShared.Items table is missing or empty.')
				return
			end
			validItems = filterJobs(loadedItems)
			if not validItems[data.data.name] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Item ' .. data.data.name .. ' does not exist.')
				return
			else
				validItems[data.data.name] = {name = data.data.name, label = data.data.label, weight = data.data.weight or 0, type = data.data.type, image = data.data.image or '',
					description = data.data.description or '', unique = data.data.unique or false, useable = data.data.useable or false, ammoType = data.data.ammoType or nil,
					shouldClose = data.data.shouldClose or false, combinable = data.data.combinable or nil}
				local function convertToPlainText(itemTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.Items = {')
					for itemName, itemData in pairs(itemTable) do
						local itemLine = '\t[\'' .. itemName .. '\'] = {'
						table.insert(lines, itemLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', itemData.label)
						table.insert(lines, labelLine)
						if itemData.type and itemData.type ~= nil then
							local typeLine = '\t\ttype = \'' .. itemData.type .. '\','
							table.insert(lines, typeLine)
						end
						if itemData.weight ~= nil then
							local weightLine = '\t\tweight = ' .. tostring(itemData.weight) .. ','
							table.insert(lines, weightLine)
						end
						if itemData.image and itemData.image ~= '' then
							local imageLine = '\t\timage = \'' .. itemData.image .. '\','
							table.insert(lines, imageLine)
						end
						if itemData.description and itemData.description ~= '' then
							local descLine = '\t\tdescription = \'' .. escapeQuotes(itemData.description) .. '\','
							table.insert(lines, descLine)
						end
						if itemData.unique ~= nil then
							local uniqueLine = '\t\tunique = ' .. tostring(itemData.unique) .. ','
							table.insert(lines, uniqueLine)
						end
						if itemData.useable ~= nil then
							local useableLine = '\t\tuseable = ' .. tostring(itemData.useable) .. ','
							table.insert(lines, useableLine)
						end
						if itemData.ammoType ~= nil then
							local ammoTypeLine = '\t\tammoType = \'' .. itemData.ammoType .. '\','
							table.insert(lines, ammoTypeLine)
						end
						if itemData.shouldClose ~= nil then
							local shouldCloseLine = '\t\tshouldClose = ' .. tostring(itemData.shouldClose) .. ','
							table.insert(lines, shouldCloseLine)
						end
						if itemData.combinable ~= nil then
							local combinableLine = '\t\tcombinable = ' .. encodeCombinable(itemData.combinable) .. ''
							table.insert(lines, combinableLine)
						end
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validItems)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving jobs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/items.lua', modifiedData, -1)
				manuallySendPayload()
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' editing item ' .. data.data.name)
			end
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REMOVE_ITEM_CONFIG', function(data)
		if data ~= nil then
			local originalData = LoadResourceFile('qb-core', './shared/items.lua')
			local validItems = {}
			local function filterJobs(items)
				local validItems = {}
				for itemName, itemData in pairs(items) do
					validItems[itemName] = itemData
				end
				return validItems
			end
			local tempEnv = {}
			setmetatable(tempEnv, {__index = _G})
			local func, err = load(originalData, 'itemData', 't', tempEnv)
			if not func then
				print('Error loading data: ' .. err)
				return
			end
			func()
			local loadedItems = tempEnv.QBShared and tempEnv.QBShared.Items
			if not loadedItems or next(loadedItems) == nil then
				print('Error: QBShared.Items table is missing or empty.')
				return
			end
			validItems = filterJobs(loadedItems)
			if not validItems[data.data.itemName] then
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: Item ' .. data.data.itemName .. ' does not exist.')
				return
			else
				validItems[data.data.itemName] = nil
				local function convertToPlainText(itemTable)
					local lines = {'QBShared = QBShared or {}'}
					table.insert(lines, 'QBShared.Items = {')
					for itemName, itemData in pairs(itemTable) do
						local itemLine = '\t[\'' .. itemName .. '\'] = {'
						table.insert(lines, itemLine)
						local labelLine = '\t\tlabel = ' .. string.format('\'%s\',', itemData.label)
						table.insert(lines, labelLine)
						if itemData.type and itemData.type ~= nil then
							local typeLine = '\t\ttype = \'' .. itemData.type .. '\','
							table.insert(lines, typeLine)
						end
						if itemData.weight ~= nil then
							local weightLine = '\t\tweight = ' .. tostring(itemData.weight) .. ','
							table.insert(lines, weightLine)
						end
						if itemData.image and itemData.image ~= '' then
							local imageLine = '\t\timage = \'' .. itemData.image .. '\','
							table.insert(lines, imageLine)
						end
						if itemData.description and itemData.description ~= '' then
							local descLine = '\t\tdescription = \'' .. escapeQuotes(itemData.description) .. '\','
							table.insert(lines, descLine)
						end
						if itemData.unique ~= nil then
							local uniqueLine = '\t\tunique = ' .. tostring(itemData.unique) .. ','
							table.insert(lines, uniqueLine)
						end
						if itemData.useable ~= nil then
							local useableLine = '\t\tuseable = ' .. tostring(itemData.useable) .. ','
							table.insert(lines, useableLine)
						end
						if itemData.ammoType ~= nil then
							local ammoTypeLine = '\t\tammoType = \'' .. itemData.ammoType .. '\','
							table.insert(lines, ammoTypeLine)
						end
						if itemData.shouldClose ~= nil then
							local shouldCloseLine = '\t\tshouldClose = ' .. tostring(itemData.shouldClose) .. ','
							table.insert(lines, shouldCloseLine)
						end
						if itemData.combinable ~= nil then
							local combinableLine = '\t\tcombinable = ' .. encodeCombinable(itemData.combinable) .. ''
							table.insert(lines, combinableLine)
						end
						table.insert(lines, '\t},')
					end
					table.insert(lines, '}')
					return table.concat(lines, '\n')
				end
				local modifiedData = convertToPlainText(validItems)
				-- Too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Saving jobs.lua with new data: ' .. modifiedData)
				SaveResourceFile('qb-core', './shared/items.lua', modifiedData, -1)
				manuallySendPayload()
				TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' removed item ' .. data.data.itemName)
			end
		end
	end)
	-- Editng a characters inventory
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_SET_CHAR_INVENTORY', function(data)
		if data ~= nil then
			local QBCore = exports['qb-core']:GetCoreObject()
			MySQL.query('SELECT * FROM `players` WHERE `citizenid` = ? LIMIT 1', {data.data.citizenId}, function(row)
				if not row then
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' editing inventory for ' .. data.data.citizenId .. ' but no player found.')
				else
					local player = QBCore.Functions.GetPlayerByCitizenId(data.data.citizenId)
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Attempting to find character with citizenId: ' .. data.data.citizenId .. ' to edit inventory.')
					if player then
						player.Functions.ClearInventory();
						for _, item in pairs(data.data.slots) do
							if item.name then
								player.Functions.AddItem(item.name, item.amount, item.slot, item.info or {})
							end
						end
						-- exports['qb-inventory']:SetInventory(player.PlayerData.source, data.data.slots)
					else
						MySQL.query('UPDATE `players` SET inventory = ? WHERE citizenid = ?', {json.encode(data.data.slots), data.data.citizenId})
					end
					manuallySendPayload()
					TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' editing inventory for ' .. data.data.citizenId)
				end
			end)
		end
	end)
	-- Editng a characters job and grade
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_SET_CHAR_JOB', function(data)
		if data ~= nil then
			local QBCore = exports['qb-core']:GetCoreObject()
			local QBPlayer = QBCore.Functions.GetPlayerByCitizenId(data.data.citizenId)
			if QBPlayer then
				QBPlayer.Functions.SetJob(data.data.job, data.data.grade)
			else
				MySQL.single('SELECT * FROM `players` WHERE `citizenid` = ? LIMIT 1', {data.data.citizenId}, function(row)
					if not row then
						TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' but the PlayerData for ' .. data.data.citizenId .. ' was not found')
						return
					else
						local PlayerData = row
						PlayerData.job = json.decode(PlayerData.job)
						PlayerData.job.name = data.data.job
						PlayerData.job.grade = data.data.grade
						PlayerData.job.onduty = data.data.onDuty
						PlayerData.job.isboss = data.data.isBoss or false
						PlayerData.job.label = data.data.label
						MySQL.update('UPDATE players SET job = ? WHERE citizenid = ?', {PlayerData.job, data.data.citizenId})
					end
				end)
			end
		end
	end)
	-- Adding an ace perm to a user
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_ADD_ACE', function(data)
		if data ~= nil then
			ExecuteCommand(('add_ace %s %s %s'):format(data.principal, data.ace, data.allow and 'allow' or 'deny'))
		end
	end)
	-- Removing an ace perm from a user
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REMOVE_ACE', function(data)
		if data ~= nil then
			ExecuteCommand(('remove_ace %s %s %s'):format(data.principal, data.ace, data.allow and 'allow' or 'deny'))
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_ADD_PRINCIPAL', function(data)
		if data ~= nil then
			ExecuteCommand(('add_principal %s %s %s'):format(data.principal, data.ace, data.allow and 'allow' or 'deny'))
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_REMOVE_PRINCIPAL', function(data)
		if data ~= nil then
			ExecuteCommand(('remove_principal %s %s %s'):format(data.principal, data.ace, data.allow and 'allow' or 'deny'))
		end
	end)
	TriggerEvent('sonorancms::RegisterPushEvent', 'CMD_SET_ACE_MAPPING', function(data)
		print('Received push event: ' .. data.type .. ' setting ace mapping')
		if data ~= nil then
			exports['sonorancms']:setRankList(data.data.mappings)
			TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Received push event: ' .. data.type .. ' setting ace mapping')
			manuallySendPayload()
		end
	end)
end)

CreateThread(function()
	local first = true
	while true do
		while first do
			Wait(5000)
			first = false
		end
		if not Config.critErrorGamestate then
			manuallySendPayload()
		else
			TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Skipping SonoranCMS Game Panel payload send due to critical error. If you do not use the SonoranCMS Game Panel you can ignore this.')
		end
		Wait(60000)
	end
end)

--- Manually send the GAMESTATE payload
function manuallySendPayload()
	local errors = {}
	if GetCurrentResourceName() ~= 'sonorancms' then
		TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'The current resource name is ' .. GetCurrentResourceName() .. ' however it should be named sonorancms. Please rename this resource to sonorancms')
		table.insert(errors, {code = 'ERR_RESOURCE_NAME',
			message = 'The current resource name is ' .. GetCurrentResourceName() .. ' however it should be named sonorancms. Please rename this resource to sonorancms'})
	end
	if GetResourceState('sonorancms_ace_perms') == 'started' then
		TriggerEvent('SonoranCMS::core:writeLog', 'warn',
		             'sonorancms_ace_perms was started, however it is now bundled with the SonoranCMS Core, please stop the sonorancms_ace_perms resource before continuing.')
		table.insert(errors, {code = 'ERR_ACE_PERMS_STARTED',
			message = 'sonorancms_ace_perms was started, however it is now bundled with the SonoranCMS Core, please stop the sonorancms_ace_perms resource before continuing.'})
	end
	if GetResourceState('sonorancms_clockin') == 'started' then
		TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'sonorancms_clockin was started, however it is now bundled with the SonoranCMS Core, please stop the sonorancms_clockin resource before continuing.')
		table.insert(errors, {code = 'ERR_CLOCKIN_STARTED',
			message = 'sonorancms_clockin was started, however it is now bundled with the SonoranCMS Core, please stop the sonorancms_clockin resource before continuing.'})
	end
	if GetResourceState('qb-core') == 'started' then
		if GetResourceState('qb-inventory') ~= 'started' and GetResourceState('ox_inventory') ~= 'started' and GetResourceState('qs-inventory') ~= 'started' and GetResourceState('ps-inventory') ~= 'started' then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn',
			             'Skipping payload send due to qb-inventory, qs-inventory, ps-inventory and ox_inventory not being started. If you do not use the SonoranCMS Game Panel you can ignore this.')
			Config.critErrorGamestate = true
			return
		end
		if GetResourceState('qb-garages') ~= 'started' and GetResourceState('cd_garage') ~= 'started' and GetResourceState('qs-advancedgarages') ~= 'started' and GetResourceState('jg-advancedgarages')
						~= 'started' then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn',
			             'qb-garages, qs-advancedgarages, jg-advancedgarages and cd_garage are not started. The garage data will be sent as empty currently. If you do not use the SonoranCMS Game Panel you can ignore this.')
			table.insert(errors,
			             {code = 'ERR_GARAGE_NOT_STARTED', message = 'qb-garages, qs-advancedgarages, jg-advancedgarages and cd_garage are not started. The garage data will be sent as empty currently.'})
		end
		if GetResourceState('oxmysql') ~= 'started' and GetResourceState('mysql-async') ~= 'started' and GetResourceState('ghmattimysql') ~= 'started' then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn',
			             'Skipping payload send due to oxmysql, mysql-async, and ghmattimysql not being started. If you do not use the SonoranCMS Game Panel you can ignore this.')
			Config.critErrorGamestate = true
			return
		end
		if Config.critErrorGamestate then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Skipping SonoranCMS Game Panel payload send due to critical error. If you do not use the SonoranCMS Game Panel you can ignore this.')
			return
		else
			-- Getting System Info
			local systemInfo = exports['sonorancms']:getSystemInfo()
			-- Getting all active players on the server
			local activePlayers = {}
			for i = 0, GetNumPlayerIndices() - 1 do
				local player = GetPlayerFromIndex(i)
				local playerInfo = {name = GetPlayerName(player), ping = GetPlayerPing(player), source = player, identifiers = GetPlayerIdentifiers(player)}
				table.insert(activePlayers, playerInfo)
			end
			if Config.framework == 'qb-core' then
				-- Getting QBCore object
				local QBCore = exports['qb-core']:GetCoreObject()
				-- Query the DB for QB Players rather than using the function because the function only returns active ones
				local qbCharacters = {}
				MySQL.query('SELECT * FROM `players`', function(row)
					for _, v in ipairs(row) do
						local qbCharInfo = QBCore.Functions.GetPlayerByCitizenId(v.citizenid)
						local playerInventory = {}
						v.charinfo = json.decode(v.charinfo)
						v.job = json.decode(v.job)
						v.money = json.decode(v.money)
						v.inventory = json.decode(v.inventory)
						if v.inventory == nil then
							v.inventory = {}
						end
						sortArrayBy(v.inventory, 'slot')
						for _, item in pairs(v.inventory) do
							local QBItems = QBCore.Shared.Items
							local QBItem = {}
							if item.name then
								QBItem = QBItems[item.name:lower()]
							end
							if item and QBItem and next(QBItem) ~= nil then
								table.insert(playerInventory,
								             {slot = item.slot, name = item.name, amount = item.amount, label = item.label or QBItem.label or 'Unknown', description = item.description or '', weight = item.weight or 0,
									type = item.type, unique = item.unique or false, image = item.image or QBItem.image or '', info = item.info or {}, shouldClose = item.shouldClose or false, combinable = v.combinable or nil})
							else
								TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Error: An item does not exist in qb-core. Item data: ' .. json.encode(item))
							end
						end
						local charInfo = {firstname = v.charinfo.firstname, lastname = v.charinfo.lastname, dob = v.charinfo.birthdate, offline = true, name = v.charinfo.firstname .. ' ' .. v.charinfo.lastname,
							id = v.charinfo.id, citizenid = v.citizenid, license = v.license, jobInfo = {name = v.job.name, grade = v.job.grade.name, label = v.job.label, onDuty = v.job.onduty, type = v.job.type},
							money = {bank = v.money.bank, cash = v.money.cash, crypto = v.money.crypto}, gender = v.charinfo.gender, nationality = v.charinfo.nationality, phoneNumber = v.charinfo.phone,
							inventory = playerInventory}
						if qbCharInfo then
							charInfo.offline = false
							charInfo.source = qbCharInfo.PlayerData.source
						end
						table.insert(qbCharacters, charInfo)
					end
				end)
				-- Request the game pool of vheicles to send all active vehicles in game
				for i = 0, GetNumPlayerIndices() - 1 do
					local p = GetPlayerFromIndex(i)
					if p ~= nil then
						TriggerClientEvent('SonoranCMS::core::RequestGamePool', p)
					end
				end
				-- Request all the resources and their valid paths relative to the resources folder
				local resourceList = {}
				for i = 0, GetNumResources(), 1 do
					local resource_name = GetResourceByFindIndex(i)
					if resource_name then
						local path = GetResourcePath(resource_name):match('.*/resources/(.*)')
						table.insert(resourceList, {name = resource_name, state = GetResourceState(resource_name), path = path, version = GetResourceMetadata(resource_name, 'version', 0),
							description = GetResourceMetadata(resource_name, 'description', 0)})
					end
				end
				-- Request all the saved player vehicles from the database
				local characterVehicles = {}
				MySQL.query('SELECT * FROM player_vehicles', function(row)
					for _, v in ipairs(row) do
						local vehicle = {}
						vehicle.id = v.id
						vehicle.citizenId = v.citizenid
						vehicle.garage = v.garage
						vehicle.model = v.vehicle
						vehicle.plate = v.plate
						vehicle.state = v.state
						vehicle.fuel = v.fuel
						vehicle.engine = v.engine
						vehicle.body = v.body
						vehicle.mileage = v.drivingdistance
						vehicle.balance = v.balance
						vehicle.paymentAmount = v.paymentamount
						vehicle.paymentsLeft = v.paymentsleft
						vehicle.financeTime = v.financetime
						vehicle.depotPrice = v.depotprice
						vehicle.displayName = v.vehicle
						table.insert(characterVehicles, vehicle)
					end
				end)
				-- Request the active runtime jobs and their grades
				local jobTable = {}
				for i, v in pairs(QBCore.Shared.Jobs) do
					local gradesTable = {}
					for _, g in pairs(v.grades) do
						table.insert(gradesTable, {name = g.name, payment = g.payment, isBoss = g.isboss})
					end
					table.insert(jobTable, {id = i, label = v.label, defaultDuty = v.defaultDuty, offDutyPay = v.offDutyPay, grades = gradesTable})
				end
				-- Request the active runtime gangs and their grades
				local gangTable = {}
				for i, v in pairs(QBCore.Shared.Gangs) do
					local gradesTable = {}
					for _, g in pairs(v.grades) do
						table.insert(gradesTable, {name = g.name, payment = g.payment, isBoss = g.isboss})
					end
					table.insert(gangTable, {id = i, label = v.label, grades = gradesTable})
				end
				-- Request the hardcoded jobs from the qb-core shared file (shared/jobs.lua)
				local originalData = LoadResourceFile('qb-core', './shared/jobs.lua')
				local validJobs = {}
				local function filterJobs(jobs)
					local validJobs = {}
					for jobName, jobData in pairs(jobs) do
						local gradesTable = {}
						for _, g in pairs(jobData.grades) do
							table.insert(gradesTable, {name = g.name, payment = g.payment, isBoss = g.isboss})
						end
						table.insert(validJobs, {id = jobName, label = jobData.label, defaultDuty = jobData.defaultDuty, offDutyPay = jobData.offDutyPay, grades = gradesTable})
					end
					return validJobs
				end
				local tempEnv = {}
				setmetatable(tempEnv, {__index = _G})
				local func, err = load(originalData, 'jobData', 't', tempEnv)
				if not func then
					print('Error loading data: ' .. err)
					return
				end
				func()
				local loadedJobs = tempEnv.QBShared and tempEnv.QBShared.Jobs
				if not loadedJobs or next(loadedJobs) == nil then
					print('Error: QBShared.Jobs table is missing or empty.')
					table.insert(errors, {code = 'ERR_JOBS_NOT_LOADED', message = 'QBShared.Jobs table is missing or empty.'})
					return
				end
				validJobs = filterJobs(loadedJobs)
				-- Request the hardcoded gangs from the qb-core shared file (shared/gangs.lua)
				local originalData = LoadResourceFile('qb-core', './shared/gangs.lua')
				local validGangs = {}
				local function filterGangs(gangs)
					local validGangs = {}
					for gangName, gangData in pairs(gangs) do
						local gradesTable = {}
						for _, g in pairs(gangData.grades) do
							table.insert(gradesTable, {name = g.name, payment = g.payment, isBoss = g.isboss})
						end
						table.insert(validGangs, {id = gangName, label = gangData.label, grades = gradesTable})
					end
					return validGangs
				end
				local tempEnv = {}
				setmetatable(tempEnv, {__index = _G})
				local func, err = load(originalData, 'gangData', 't', tempEnv)
				if not func then
					print('Error loading data: ' .. err)
					return
				end
				func()
				local loadedGangs = tempEnv.QBShared and tempEnv.QBShared.Gangs
				if not loadedGangs or next(loadedGangs) == nil then
					print('Error: QBShared.Gangs table is missing or empty.')
					table.insert(errors, {code = 'ERR_GANGS_NOT_LOADED', message = 'QBShared.Gangs table is missing or empty.'})
					return
				end
				validGangs = filterGangs(loadedGangs)
				-- Request the garage data from qb-garages
				local QBGarages = {}
				if GetResourceState('qb-garages') == 'started' then
					-- Safely check if the export exists
					local success, garageData = pcall(function()
						local garages = {}
						if GetResourceState('qb-garages') == 'started' then
							return exports['qb-garages']:getAllGarages()
						end
						return garages
					end)
					if success then
						QBGarages = garageData
					else
						TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Error getting garage data from qb-garages, the export getAllGarages() is not available. Please update your qb-garages resource.')
						table.insert(errors, {code = 'ERR_GARAGE_EXPORT_NOT_FOUND', message = 'qb-garages export getAllGarages() is not available.'})
					end
				elseif GetResourceState('cd_garage') == 'started' then
					local CDConfig = exports['cd_garage']:GetConfig()
					for _, v in pairs(CDConfig.Locations) do
						table.insert(QBGarages,
						             {name = v.Garage_ID, label = v.Garage_ID, takeVehicle = {v.x_1, v.y_1, v.z_1}, spawnPoint = {v.x_2, v.y_2, v.z_2, v.h_2}, putVehicle = {v.x_1, v.y_1, v.z_1},
							showBlip = v.EnableBlip, blipName = v.Garage_ID, blipNumber = 357, blipColor = 3, type = 'public', vehicle = v.Type})
					end
				elseif GetResourceState('qs-advancedgarages') == 'started' then
					local originalData = LoadResourceFile('qs-advancedgarages', './config/config.lua')
					local function filterGarages(garages)
						for k, v in pairs(garages) do
							table.insert(QBGarages,
							             {name = v.Garage_ID, label = k, takeVehicle = v.coords.menuCoords, spawnPoint = v.coords.spawnCoords, putVehicle = v.coords.menuCoords, showBlip = v.available, blipName = k,
								blipNumber = 357, blipColor = 3, type = 'public', vehicle = v.type})
						end
					end
					local tempEnv = {}
					setmetatable(tempEnv, {__index = _G})
					local func, err = load(originalData, 'garageData', 't', tempEnv)
					if not func then
						print('Error loading data: ' .. err)
						return
					end
					func()
					local loadedGarages = tempEnv.Config.Garages
					if not loadedGarages or next(loadedGarages) == nil then
						print('Error: Config.Garages table is missing or empty in qs-advancedgarages Config.')
						table.insert(errors, {code = 'ERR_GARAGE_EXPORT_NOT_FOUND', message = 'qs-advancedgarages Config.Garages table is missing or empty.'})
						return
					end
					filterGarages(loadedGarages)
				elseif GetResourceState('jg-advancedgarages') == 'started' then
					-- Safely check if the export exists
					local success, garageData = pcall(function()
						local garages = {}
						if GetResourceState('jg-advancedgarages') == 'started' then
							return exports['jg-advancedgarages']:getAllGarages()
						end
						return garages
					end)
					if success then
						QBGarages = garageData
					else
						TriggerEvent('SonoranCMS::core:writeLog', 'error',
						             'Error getting garage data from jg-advancedgarages, the export getAllGarages() is not available. Please update your jg-advancedgarages resource.')
					end
				end
				-- Request all items from QBShared
				local QBItems = QBCore.Shared.Items
				local formattedQBItems = {}
				for _, v in pairs(QBItems) do
					local item = {name = v.name, label = v.label or 'Unknown', weight = v.weight or 0, type = v.type, image = v.image or '', description = v.description or '', unique = v.unique or false,
						useable = v.useable or false, ammoType = v.ammoType or nil, shouldClose = v.shouldClose or false, combinable = v.combinable or nil}
					table.insert(formattedQBItems, item)
				end
				-- Request the hardcoded items from the qb-core shared file (shared/items.lua)
				local originalData = LoadResourceFile('qb-core', './shared/items.lua')
				local validItems = {}
				local function filterItems(items)
					local validItems = {}
					for itemName, itemData in pairs(items) do
						table.insert(validItems, {name = itemName, label = itemData.label, weight = itemData.weight or 0, type = itemData.type, image = itemData.image or '', description = itemData.description or '',
							unique = itemData.unique or false, useable = itemData.useable or false, ammoType = itemData.ammoType or nil, shouldClose = itemData.shouldClose or false, combinable = itemData.combinable or nil})
					end
					return validItems
				end
				local tempEnv = {}
				setmetatable(tempEnv, {__index = _G})
				local func, err = load(originalData, 'itemData', 't', tempEnv)
				if not func then
					print('Error loading data: ' .. err)
					return
				end
				func()
				local loadedItems = tempEnv.QBShared and tempEnv.QBShared.Items
				if not loadedItems or next(loadedItems) == nil then
					print('Error: QBShared.Items table is missing or empty.')
					table.insert(errors, {code = 'ERR_ITEMS_NOT_LOADED', message = 'QBShared.Items table is missing or empty.'})
					return
				end
				validItems = filterItems(loadedItems)
				-- Compile a list of aces and principals
				-- ExecuteCommand('list_aces')
				-- local aceOutput = GetConsoleBuffer()
				-- local aceList = {}
				-- for line in aceOutput:gmatch('[^\r\n]+') do
				-- 	local ace, obj, allow = line:match('(.-)%s--> (.-)%s-=%s-(%S+)')
				-- 	if ace and obj and allow then
				-- 		table.insert(aceList, {ace = ace, obj = obj, allow = (allow == 'ALLOW')})
				-- 	end
				-- end
				-- Wait(5000)
				-- ExecuteCommand('list_principals')
				-- local principalOutput = GetConsoleBuffer()
				-- local principalList = {}
				-- for line in principalOutput:gmatch('[^\r\n]+') do
				-- 	local parent, principal = line:match('(.-)%s-<- (.-)%s')
				-- 	if principal and parent then
				-- 		table.insert(principalList, {principal = principal, parent = parent})
				-- 	end
				-- end
				local acePermList = exports['sonorancms']:getRankList()
				acePermList = json.decode(acePermList)
				Wait(5000)
				apiResponse = {uptime = GetGameTimer(), system = {cpuRaw = systemInfo.cpuRaw, cpuUsage = systemInfo.cpuUsage, memoryRaw = systemInfo.ramRaw, memoryUsage = systemInfo.ramUsage},
					players = activePlayers, characters = qbCharacters, gameVehicles = vehicleGamePool, logs = loggerBuffer, resources = resourceList, characterVehicles = characterVehicles, jobs = jobTable,
					gangs = gangTable, fileJobs = validJobs, fileGangs = validGangs, items = formattedQBItems, fileItems = validItems, garages = QBGarages,
					config = {slotCount = Config.MaxInventorySlots, version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)}, errors = errors, aceMappings = acePermList.mappings}
				-- Disabled for time being, too spammy
				-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Sending API update for GAMESTATE, payload: ' .. json.encode(apiResponse))
				-- SaveResourceFile(GetCurrentResourceName(), './apiPayload.json', json.encode(apiResponse), -1)
				performApiRequest(apiResponse, 'GAMESTATE', function(result, ok)
					Utilities.Logging.logDebug('API Response: ' .. result .. ' ' .. tostring(ok))
					if not ok then
						logError('API_ERROR')
						Config.critErrorGamestate = true
						return
					end
				end)
			end
		end
	else
		-- Handle a standalone gamestate
		if Config.critErrorGamestate then
			TriggerEvent('SonoranCMS::core:writeLog', 'warn', 'Skipping SonoranCMS Game Panel payload send due to critical error. If you do not use the SonoranCMS Game Panel you can ignore this.')
			return
		else
			-- Getting System Info
			local systemInfo = exports['sonorancms']:getSystemInfo()
			-- Getting all active players on the server
			local activePlayers = {}
			for i = 0, GetNumPlayerIndices() - 1 do
				local player = GetPlayerFromIndex(i)
				local playerInfo = {name = GetPlayerName(player), ping = GetPlayerPing(player), source = player, identifiers = GetPlayerIdentifiers(player)}
				table.insert(activePlayers, playerInfo)
			end
			-- Request the game pool of vheicles to send all active vehicles in game
			for i = 0, GetNumPlayerIndices() - 1 do
				local p = GetPlayerFromIndex(i)
				if p ~= nil then
					TriggerClientEvent('SonoranCMS::core::RequestGamePool', p)
				end
			end
			-- Request all the resources and their valid paths relative to the resources folder
			local resourceList = {}
			for i = 0, GetNumResources(), 1 do
				local resource_name = GetResourceByFindIndex(i)
				if resource_name then
					local path = GetResourcePath(resource_name):match('.*/resources/(.*)')
					table.insert(resourceList, {name = resource_name, state = GetResourceState(resource_name), path = path, version = GetResourceMetadata(resource_name, 'version', 0),
						description = GetResourceMetadata(resource_name, 'description', 0)})
				end
			end
			-- Compile a list of aces and principals
			-- ExecuteCommand('list_aces')
			-- local aceOutput = GetConsoleBuffer()
			-- local aceList = {}
			-- for line in aceOutput:gmatch('[^\r\n]+') do
			-- 	local ace, obj, allow = line:match('(.-)%s--> (.-)%s-=%s-(%S+)')
			-- 	if ace and obj and allow then
			-- 		table.insert(aceList, {ace = ace, obj = obj, allow = (allow == 'ALLOW')})
			-- 	end
			-- end
			-- Wait(5000)
			-- ExecuteCommand('list_principals')
			-- local principalOutput = GetConsoleBuffer()
			-- local principalList = {}
			-- for line in principalOutput:gmatch('[^\r\n]+') do
			-- 	local parent, principal = line:match('(.-)%s-<- (.-)%s')
			-- 	if principal and parent then
			-- 		table.insert(principalList, {principal = principal, parent = parent})
			-- 	end
			-- end
			local acePermList = exports['sonorancms']:getRankList()
			acePermList = json.decode(acePermList)
			Wait(5000)
			apiResponse = {uptime = GetGameTimer(), system = {cpuRaw = systemInfo.cpuRaw, cpuUsage = systemInfo.cpuUsage, memoryRaw = systemInfo.ramRaw, memoryUsage = systemInfo.ramUsage},
				players = activePlayers, gameVehicles = vehicleGamePool, logs = loggerBuffer, resources = resourceList, config = {version = GetResourceMetadata(GetCurrentResourceName(), 'version', 0)},
				errors = errors, aceMappings = acePermList.mappings}
			-- Disabled for time being, too spammy
			-- TriggerEvent('SonoranCMS::core:writeLog', 'debug', 'Sending API update for GAMESTATE, payload: ' .. json.encode(apiResponse))
			-- SaveResourceFile(GetCurrentResourceName(), './apiPayload.json', json.encode(apiResponse), -1)
			performApiRequest(apiResponse, 'GAMESTATE', function(result, ok)
				Utilities.Logging.logDebug('API Response: ' .. result .. ' ' .. tostring(ok))
				if not ok then
					logError('API_ERROR')
					Config.critErrorGamestate = true
					return
				end
			end)
		end
	end
end

RegisterConsoleListener(function(channel, message)
	serverLogger(0, 'CONSOLE_LOG', {channel = channel, message = message})
end)

RegisterNetEvent('SonoranCMS::core::ReturnGamePool', function(gamePool)
	vehicleGamePool = gamePool
end)

RegisterNetEvent('SonoranCMS::core::DeleteVehicleCB', function(vehDriver, passengers)
	TriggerClientEvent('chat:addMessage', vehDriver, {color = {255, 0, 0}, multiline = true,
		args = {'[SonoranCMS Management Panel] ', 'Your vehicle has been despawned! Please contact a staff member if you believe this is an error.'}})
	for _, v in ipairs(passengers) do
		TriggerClientEvent('chat:addMessage', v, {color = {255, 0, 0}, multiline = true,
			args = {'[SonoranCMS Management Panel] ', 'Your vehicle has been despawned! Please contact a staff member if you believe this is an error.'}})
	end
end)

RegisterNetEvent('SonoranCMS::core::RepairVehicleCB', function(vehDriver, passengers)
	TriggerClientEvent('chat:addMessage', vehDriver, {color = {255, 0, 0}, multiline = true, args = {'[SonoranCMS Management Panel] ', 'Your vehicle has been repaired!'}})
	for _, v in ipairs(passengers) do
		TriggerClientEvent('chat:addMessage', v, {color = {255, 0, 0}, multiline = true, args = {'[SonoranCMS Management Panel] ', 'Your vehicle has been repaired!'}})
	end
end)

RegisterNetEvent('SonoranCMS::ServerLogger::DeathEvent', function(killer, cause)
	serverLogger(source, 'deathEvent', {killer = killer, cause = cause})
end)

RegisterNetEvent('SonoranCMS::ServerLogger::PlayerShot', function(weapon)
	serverLogger(source, 'playerShot', {weapon = weapon})
end)

AddEventHandler('explosionEvent', function(source, ev)
	if (isInvalid(ev.damageScale, 0) or isInvalid(ev.cameraShake, 0) or isInvalid(ev.isInvisible, true) or isInvalid(ev.isAudible, false)) then
		return
	end
	if ev.explosionType < -1 or ev.explosionType > 77 then
		ev.explosionType = 'UNKNOWN'
	else
		ev.explosionType = explosionTypes[ev.explosionType + 1]
	end
	serverLogger(tonumber(source), 'explosionEvent', ev)
end)

RegisterNetEvent('chatMessage', function(src, author, text)
	serverLogger(src, 'ChatMessage', {author = author, text = text})
end)

AddEventHandler('onResourceStarting', function(resource)
	serverLogger(0, 'onResourceStarting', resource)
end)

AddEventHandler('onResourceStart', function(resource)
	serverLogger(0, 'onResourceStart', resource)
end)

Citizen.CreateThread(function()
	local first = true
	while true do
		while first do
			Wait(15000)
			first = false
		end
		local resources = {'sonorancms_whitelist', 'sonorancms_clockin', 'sonorancms_ace_perms'}
		for i = 1, #resources do
			local resource = resources[i]
			-- Safely try to stop the old Sonoran CMS plugin resources
			pcall(function()
				if GetResourceState(resource) == 'started' then
					ExecuteCommand('stop ' .. resource .. '')
					Wait(1000)
					if GetResourceState(resource) == 'started' then
						TriggerEvent('SonoranCMS::core:writeLog', 'error', 'Failed to stop the old SonoranCMS ' .. resource .. ' resource. Please remove this addon as it is now bundled with SonoranCMS.')
					else
						TriggerEvent('SonoranCMS::core:writeLog', 'info', 'Successfully stopped the old SonoranCMS ' .. resource .. ' resource. Please remove this addon as it is now bundled with SonoranCMS.')
					end
				end
			end)
		end
		Wait(3600 * 1000)
	end
end)

AddEventHandler('onServerResourceStart', function(resource)
	serverLogger(0, 'onServerResourceStart', resource)
end)

AddEventHandler('onResourceListRefresh', function(resource)
	serverLogger(0, 'onResourceListRefresh', resource)
end)

AddEventHandler('onResourceStop', function(resource)
	serverLogger(0, 'onResourceStop', resource)
end)

AddEventHandler('onServerResourceStop', function(resource)
	serverLogger(0, 'onServerResourceStop', resource)
end)

AddEventHandler('playerConnecting', function(name, _, _)
	serverLogger(0, 'playerConnecting', name)
end)

AddEventHandler('playerDropped', function(name, _, _)
	serverLogger('playerDropped', name)
end)

AddEventHandler('QBCore:CallCommand', function(command, args)
	serverLogger(source, 'QBCore::CallCommand', {command = command, args = args})
end)

-- Disabled for time being, not safe for net in certain cases
-- AddEventHandler('QBCore:ToggleDuty', function()
-- 	local Player = QBCore.Functions.GetPlayer(source)
-- 	if Player.PlayerData.job.onduty then
-- 		serverLogger(source, 'QBCore::ToggleDuty', {job = Player.PlayerData.job.name, duty = false})
-- 	else
-- 		serverLogger(source, 'QBCore::ToggleDuty', {job = Player.PlayerData.job.name, duty = true})
-- 	end
-- end)

-- Disabled for time being, too spammy
-- AddEventHandler('QBCore:Server:SetMetaData', function(meta, data)
-- 	serverLogger(source, 'QBCore:Server:SetMetaData', {meta = meta, data = data})
-- end)

RegisterNetEvent('SonoranCMS::ServerLogger::QBSpawnVehicle', function(veh)
	serverLogger(source, 'QBCore:Command:SpawnVehicle', veh)
end)

RegisterNetEvent('SonoranCMS::ServerLogger::QBDeleteVehicle', function()
	serverLogger(source, 'QBCore:Command:DeleteVehicle', nil)
end)

RegisterNetEvent('SonoranCMS::ServerLogger::QBClientUsedItem', function(item)
	serverLogger(source, 'QBCore:Command:ClientUsedItem', item)
end)

