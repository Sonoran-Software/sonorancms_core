local warningstring = false
local scaleform = nil
local warningMessage = nil
local secondsCount = 10
local breakOff = false
local notReset = true
local CurrentWeather = 'EXTRASUNNY'
local lastWeather = CurrentWeather
local baseTime = 8
local timeOffset = 0
local timer = 0
local freezeTime = false
local blackout = false
local blackoutVehicle = false

RegisterNetEvent('SonoranCMS::core::RequestGamePool', function()
	local returnVehicleData = {}
	for _, v in pairs(GetGamePool('CVehicle')) do
		local ped = GetPedInVehicleSeat(v, -1)
		if (DoesEntityExist(ped)) and (IsPedAPlayer(ped)) then
			local vehicleData = {}
			vehicleData.vehicleHandle = v
			vehicleData.model = GetEntityModel(v)
			vehicleData.plate = GetVehicleNumberPlateText(v)
			vehicleData.health = GetVehicleEngineHealth(v)
			vehicleData.fuel = GetVehicleFuelLevel(v)
			vehicleData.bodyHealth = GetVehicleBodyHealth(v)
			vehicleData.displayName = GetDisplayNameFromVehicleModel(GetEntityModel(v))
			vehicleData.driver = GetPlayerServerId(NetworkGetPlayerIndexFromPed(ped))
			vehicleData.passengers = {}
			for i = -1, GetVehicleMaxNumberOfPassengers(GetVehiclePedIsIn(ped)) + 1, 1 do
				local pedPass = GetPedInVehicleSeat(GetVehiclePedIsIn(ped), i)
				if (DoesEntityExist(pedPass)) then
					if (IsPedAPlayer(pedPass) and ped ~= pedPass) then
						local pedServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(pedPass))
						table.insert(vehicleData.passengers, {seat = i, passengerId = pedServerId})
					end
				end
			end
			table.insert(returnVehicleData, vehicleData)
		end
	end
	TriggerServerEvent('SonoranCMS::core::ReturnGamePool', returnVehicleData)
end)

RegisterNetEvent('SonoranCMS::core::DeleteVehicle', function(vehHandle)
	if DoesEntityExist(vehHandle) then
		local vehDriver = GetPedInVehicleSeat(vehHandle, -1)
		if (DoesEntityExist(vehDriver)) and (IsPedAPlayer(vehDriver)) then
			local passengers = {}
			for i = -1, GetVehicleMaxNumberOfPassengers(GetVehiclePedIsIn(ped)) + 1, 1 do
				local pedPass = GetPedInVehicleSeat(GetVehiclePedIsIn(ped), i)
				if (DoesEntityExist(pedPass)) then
					if (IsPedAPlayer(pedPass) and ped ~= pedPass) then
						local pedServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(pedPass))
						table.insert(passengers, pedServerId)
					end
				end
			end
			if not NetworkHasControlOfEntity(vehHandle) then
				if NetworkRequestControlOfEntity(vehHandle) then
					vehDriver = GetPlayerServerId(NetworkGetPlayerIndexFromPed(vehDriver))
					TriggerServerEvent('SonoranCMS::core::DeleteVehicleCB', vehDriver, passengers)
					SetEntityAsMissionEntity(vehHandle, true, true)
					DeleteEntity(vehHandle)
				else
					print('Failed to request control of entity ' .. vehHandle)
				end
			else
				vehDriver = GetPlayerServerId(NetworkGetPlayerIndexFromPed(vehDriver))
				TriggerServerEvent('SonoranCMS::core::DeleteVehicleCB', vehDriver, passengers)
				SetEntityAsMissionEntity(vehHandle, true, true)
				DeleteEntity(vehHandle)
			end
		end
	end
end)

RegisterNetEvent('SonoranCMS::core::RepairVehicle', function(vehHandle)
	if DoesEntityExist(vehHandle) then
		local vehDriver = GetPedInVehicleSeat(vehHandle, -1)
		if (DoesEntityExist(vehDriver)) and (IsPedAPlayer(vehDriver)) then
			local passengers = {}
			for i = -1, GetVehicleMaxNumberOfPassengers(GetVehiclePedIsIn(ped)) + 1, 1 do
				local pedPass = GetPedInVehicleSeat(GetVehiclePedIsIn(ped), i)
				if (DoesEntityExist(pedPass)) then
					if (IsPedAPlayer(pedPass) and ped ~= pedPass) then
						local pedServerId = GetPlayerServerId(NetworkGetPlayerIndexFromPed(pedPass))
						table.insert(passengers, pedServerId)
					end
				end
			end
			if not NetworkHasControlOfEntity(vehHandle) then
				if NetworkRequestControlOfEntity(vehHandle) then
					vehDriver = GetPlayerServerId(NetworkGetPlayerIndexFromPed(vehDriver))
					TriggerServerEvent('SonoranCMS::core::RepairVehicleCB', vehDriver, passengers)
					SetVehicleFixed(vehHandle)
					SetVehicleDeformationFixed(vehHandle)
				else
					print('Failed to request control of entity ' .. vehHandle)
				end
			else
				vehDriver = GetPlayerServerId(NetworkGetPlayerIndexFromPed(vehDriver))
				TriggerServerEvent('SonoranCMS::core::RepairVehicleCB', vehDriver, passengers)
				SetVehicleFixed(vehHandle)
				SetVehicleDeformationFixed(vehHandle)
			end
		end
	end
end)

RegisterNetEvent('SonoranCMS::core::HandleWarnedPlayer', function(message)
	warningMessage = message
	local sendMessage = message .. '\n\n\n~y~To close this message, hold [space] for ' .. secondsCount .. ' seconds'
	scaleform = Initialize('mp_big_message_freemode', sendMessage)
	Wait(500)
	warnPlayer(message)
end)

function warnPlayer(msg)
	warningstring = true
	PlaySoundFrontend(-1, 'DELETE', 'HUD_DEATHMATCH_SOUNDSET', 1)
end

function Initialize(scaleform, message)
	local scaleform = RequestScaleformMovie(scaleform)
	while not HasScaleformMovieLoaded(scaleform) do
		Citizen.Wait(0)
	end
	PushScaleformMovieFunction(scaleform, 'SHOW_SHARD_WASTED_MP_MESSAGE')
	PushScaleformMovieFunctionParameterString('~r~SonoranCMS Management Panel:')
	PushScaleformMovieFunctionParameterString(message)
	PopScaleformMovieFunctionVoid()
	return scaleform
end

Citizen.CreateThread(function()
	while true do
		Citizen.Wait(0)
		if warningstring and not breakOff then
			DrawScaleformMovieFullscreen(scaleform, 255, 255, 255, 255, 0)
		else
			breakOff = false
		end
	end
end)

Citizen.CreateThread(function()
	while true do
		Wait(1)
		if warningstring then
			local countLimit = 100 -- 10 seconds
			local count = 0
			while true do
				Wait(100)
				if IsControlPressed(0, 22) then
					if (count % 10) == 0 then
						secondsCount = secondsCount - 1
						Initialize('mp_big_message_freemode', warningMessage .. '\n\n\n~y~To close this message, hold [space] for ' .. secondsCount .. ' seconds')
						breakOff = true
						notReset = true
					end
					count = count + 1
					if count >= countLimit then
						warningstring = false
						secondsCount = 10
						notReset = true
						return
					end
				else
					secondsCount = 10
					count = 0
					if notReset then
						Wait(100)
						Initialize('mp_big_message_freemode', warningMessage .. '\n\n\n~y~To close this message, hold [space] for ' .. secondsCount .. ' seconds')
						breakOff = true
						notReset = false
					end
				end
			end
		end
	end
end)

-- Death reasons
local fivemfivemDeathHashTable = {[(GetHashKey('WEAPON_UNARMED'))] = 'Unarmed', [(GetHashKey('GADGET_PARACHUTE'))] = 'Parachute', [(GetHashKey('WEAPON_KNIFE'))] = 'Knife',
	[(GetHashKey('WEAPON_NIGHTSTICK'))] = 'Nightstick', [(GetHashKey('WEAPON_HAMMER'))] = 'Hammer', [(GetHashKey('WEAPON_BAT'))] = 'Baseball Bat', [(GetHashKey('WEAPON_CROWBAR'))] = 'Crowbar',
	[(GetHashKey('WEAPON_GOLFCLUB'))] = 'Golf Club', [(GetHashKey('WEAPON_BOTTLE'))] = 'Bottle', [(GetHashKey('WEAPON_DAGGER'))] = 'Antique Cavalry Dagger', [(GetHashKey('WEAPON_HATCHET'))] = 'Hatchet',
	[(GetHashKey('WEAPON_KNUCKLE'))] = 'Knuckle Duster', [(GetHashKey('WEAPON_MACHETE'))] = 'Machete', [(GetHashKey('WEAPON_FLASHLIGHT'))] = 'Flashlight',
	[(GetHashKey('WEAPON_SWITCHBLADE'))] = 'Switchblade', [(GetHashKey('WEAPON_BATTLEAXE'))] = 'Battleaxe', [(GetHashKey('WEAPON_POOLCUE'))] = 'Poolcue', [(GetHashKey('WEAPON_PIPEWRENCH'))] = 'Wrench',
	[(GetHashKey('WEAPON_STONE_HATCHET'))] = 'Stone Hatchet', [(GetHashKey('WEAPON_PISTOL'))] = 'Pistol', [(GetHashKey('WEAPON_PISTOL_MK2'))] = 'Pistol Mk2',
	[(GetHashKey('WEAPON_COMBATPISTOL'))] = 'Combat Pistol', [(GetHashKey('WEAPON_PISTOL50'))] = 'Pistol .50	', [(GetHashKey('WEAPON_SNSPISTOL'))] = 'SNS Pistol',
	[(GetHashKey('WEAPON_SNSPISTOL_MK2'))] = 'SNS Pistol Mk2', [(GetHashKey('WEAPON_HEAVYPISTOL'))] = 'Heavy Pistol', [(GetHashKey('WEAPON_VINTAGEPISTOL'))] = 'Vintage Pistol',
	[(GetHashKey('WEAPON_MARKSMANPISTOL'))] = 'Marksman Pistol', [(GetHashKey('WEAPON_REVOLVER'))] = 'Heavy Revolver', [(GetHashKey('WEAPON_REVOLVER_MK2'))] = 'Heavy Revolver Mk2',
	[(GetHashKey('WEAPON_DOUBLEACTION'))] = 'Double-Action Revolver', [(GetHashKey('WEAPON_APPISTOL'))] = 'AP Pistol', [(GetHashKey('WEAPON_STUNGUN'))] = 'Stun Gun',
	[(GetHashKey('WEAPON_FLAREGUN'))] = 'Flare Gun', [(GetHashKey('WEAPON_RAYPISTOL'))] = 'Up-n-Atomizer', [(GetHashKey('WEAPON_MICROSMG'))] = 'Micro SMG',
	[(GetHashKey('WEAPON_MACHINEPISTOL'))] = 'Machine Pistol', [(GetHashKey('WEAPON_MINISMG'))] = 'Mini SMG', [(GetHashKey('WEAPON_SMG'))] = 'SMG', [(GetHashKey('WEAPON_SMG_MK2'))] = 'SMG Mk2	',
	[(GetHashKey('WEAPON_ASSAULTSMG'))] = 'Assault SMG', [(GetHashKey('WEAPON_COMBATPDW'))] = 'Combat PDW', [(GetHashKey('WEAPON_MG'))] = 'MG', [(GetHashKey('WEAPON_COMBATMG'))] = 'Combat MG	',
	[(GetHashKey('WEAPON_COMBATMG_MK2'))] = 'Combat MG Mk2', [(GetHashKey('WEAPON_GUSENBERG'))] = 'Gusenberg Sweeper', [(GetHashKey('WEAPON_RAYCARBINE'))] = 'Unholy Deathbringer',
	[(GetHashKey('WEAPON_ASSAULTRIFLE'))] = 'Assault Rifle', [(GetHashKey('WEAPON_ASSAULTRIFLE_MK2'))] = 'Assault Rifle Mk2', [(GetHashKey('WEAPON_CARBINERIFLE'))] = 'Carbine Rifle',
	[(GetHashKey('WEAPON_CARBINERIFLE_MK2'))] = 'Carbine Rifle Mk2', [(GetHashKey('WEAPON_ADVANCEDRIFLE'))] = 'Advanced Rifle', [(GetHashKey('WEAPON_SPECIALCARBINE'))] = 'Special Carbine',
	[(GetHashKey('WEAPON_SPECIALCARBINE_MK2'))] = 'Special Carbine Mk2', [(GetHashKey('WEAPON_BULLPUPRIFLE'))] = 'Bullpup Rifle', [(GetHashKey('WEAPON_BULLPUPRIFLE_MK2'))] = 'Bullpup Rifle Mk2',
	[(GetHashKey('WEAPON_COMPACTRIFLE'))] = 'Compact Rifle', [(GetHashKey('WEAPON_SNIPERRIFLE'))] = 'Sniper Rifle', [(GetHashKey('WEAPON_HEAVYSNIPER'))] = 'Heavy Sniper',
	[(GetHashKey('WEAPON_HEAVYSNIPER_MK2'))] = 'Heavy Sniper Mk2', [(GetHashKey('WEAPON_MARKSMANRIFLE'))] = 'Marksman Rifle', [(GetHashKey('WEAPON_MARKSMANRIFLE_MK2'))] = 'Marksman Rifle Mk2',
	[(GetHashKey('WEAPON_GRENADE'))] = 'Grenade', [(GetHashKey('WEAPON_STICKYBOMB'))] = 'Sticky Bomb', [(GetHashKey('WEAPON_PROXMINE'))] = 'Proximity Mine',
	[(GetHashKey('WAPAON_PIPEBOMB'))] = 'Pipe Bomb', [(GetHashKey('WEAPON_SMOKEGRENADE'))] = 'Tear Gas', [(GetHashKey('WEAPON_BZGAS'))] = 'BZ Gas', [(GetHashKey('WEAPON_MOLOTOV'))] = 'Molotov',
	[(GetHashKey('WEAPON_FIREEXTINGUISHER'))] = 'Fire Extinguisher', [(GetHashKey('WEAPON_PETROLCAN'))] = 'Jerry Can', [(GetHashKey('WEAPON_BALL'))] = 'Ball',
	[(GetHashKey('WEAPON_SNOWBALL'))] = 'Snowball', [(GetHashKey('WEAPON_FLARE'))] = 'Flare', [(GetHashKey('WEAPON_GRENADELAUNCHER'))] = 'Grenade Launcher', [(GetHashKey('WEAPON_RPG'))] = 'RPG',
	[(GetHashKey('WEAPON_MINIGUN'))] = 'Minigun', [(GetHashKey('WEAPON_FIREWORK'))] = 'Firework Launcher', [(GetHashKey('WEAPON_RAILGUN'))] = 'Railgun',
	[(GetHashKey('WEAPON_HOMINGLAUNCHER'))] = 'Homing Launcher', [(GetHashKey('WEAPON_COMPACTLAUNCHER'))] = 'Compact Grenade Launcher', [(GetHashKey('WEAPON_RAYMINIGUN'))] = 'Widowmaker',
	[(GetHashKey('WEAPON_PUMPSHOTGUN'))] = 'Pump Shotgun', [(GetHashKey('WEAPON_PUMPSHOTGUN_MK2'))] = 'Pump Shotgun Mk2', [(GetHashKey('WEAPON_SAWNOFFSHOTGUN'))] = 'Sawed-off Shotgun',
	[(GetHashKey('WEAPON_BULLPUPSHOTGUN'))] = 'Bullpup Shotgun', [(GetHashKey('WEAPON_ASSAULTSHOTGUN'))] = 'Assault Shotgun', [(GetHashKey('WEAPON_MUSKET'))] = 'Musket',
	[(GetHashKey('WEAPON_HEAVYSHOTGUN'))] = 'Heavy Shotgun', [(GetHashKey('WEAPON_DBSHOTGUN'))] = 'Double Barrel Shotgun', [(GetHashKey('WEAPON_SWEEPERSHOTGUN'))] = 'Sweeper Shotgun',
	[(GetHashKey('WEAPON_REMOTESNIPER'))] = 'Remote Sniper', [(GetHashKey('WEAPON_GRENADELAUNCHER_SMOKE'))] = 'Smoke Grenade Launcher', [(GetHashKey('WEAPON_PASSENGER_ROCKET'))] = 'Passenger Rocket',
	[(GetHashKey('WEAPON_AIRSTRIKE_ROCKET'))] = 'Airstrike Rocket', [(GetHashKey('WEAPON_STINGER'))] = 'Stinger [Vehicle]', [(GetHashKey('OBJECT'))] = 'Object',
	[(GetHashKey('VEHICLE_WEAPON_TANK'))] = 'Tank Cannon', [(GetHashKey('VEHICLE_WEAPON_SPACE_ROCKET'))] = 'Rockets', [(GetHashKey('VEHICLE_WEAPON_PLAYER_LASER'))] = 'Laser',
	[(GetHashKey('AMMO_RPG'))] = 'Rocket', [(GetHashKey('AMMO_TANK'))] = 'Tank', [(GetHashKey('AMMO_SPACE_ROCKET'))] = 'Rocket', [(GetHashKey('AMMO_PLAYER_LASER'))] = 'Laser',
	[(GetHashKey('AMMO_ENEMY_LASER'))] = 'Laser', [(GetHashKey('WEAPON_RAMMED_BY_CAR'))] = 'Rammed by Car', [(GetHashKey('WEAPON_FIRE'))] = 'Fire', [(GetHashKey('WEAPON_HELI_CRASH'))] = 'Heli Crash',
	[(GetHashKey('WEAPON_RUN_OVER_BY_CAR'))] = 'Run over by Car', [(GetHashKey('WEAPON_HIT_BY_WATER_CANNON'))] = 'Hit by Water Cannon', [(GetHashKey('WEAPON_EXHAUSTION'))] = 'Exhaustion',
	[(GetHashKey('WEAPON_EXPLOSION'))] = 'Explosion', [(GetHashKey('WEAPON_ELECTRIC_FENCE'))] = 'Electric Fence', [(GetHashKey('WEAPON_BLEEDING'))] = 'Bleeding',
	[(GetHashKey('WEAPON_DROWNING_IN_VEHICLE'))] = 'Drowning in Vehicle', [(GetHashKey('WEAPON_DROWNING'))] = 'Drowning', [(GetHashKey('WEAPON_BARBED_WIRE'))] = 'Barbed Wire',
	[(GetHashKey('WEAPON_VEHICLE_ROCKET'))] = 'Vehicle Rocket', [(GetHashKey('VEHICLE_WEAPON_ROTORS'))] = 'Rotors', [(GetHashKey('WEAPON_AIR_DEFENCE_GUN'))] = 'Air Defence Gun',
	[(GetHashKey('WEAPON_ANIMAL'))] = 'Animal', [(GetHashKey('WEAPON_COUGAR'))] = 'Cougar'}

--- Handles player death
---@param ped PlayerPed
local function handleDeath(ped)
	local killerPed = GetPedSourceOfDeath(ped)
	local causeHash = GetPedCauseOfDeath(ped)
	local killer = false
	if killerPed == ped then
		killer = false
	else
		if IsEntityAPed(killerPed) and IsPedAPlayer(killerPed) then
			killer = NetworkGetPlayerIndexFromPed(killerPed)
		elseif IsEntityAVehicle(killerPed) then
			local drivingPed = GetPedInVehicleSeat(killerPed, -1)
			if IsEntityAPed(drivingPed) == 1 and IsPedAPlayer(drivingPed) then
				killer = NetworkGetPlayerIndexFromPed(drivingPed)
			end
		end
	end
	local deathReason = fivemfivemDeathHashTable[causeHash] or 'unknown'
	if not killer then
		if deathReason ~= 'unknown' then
			deathReason = 'suicide (' .. deathReason .. ')'
		else
			deathReason = 'suicide'
		end
	else
		killer = GetPlayerServerId(killer)
	end
	TriggerServerEvent('SonoranCMS::ServerLogger::DeathEvent', killer, deathReason)
end

local deathFlag = false
local IsEntityDead = IsEntityDead
CreateThread(function()
	local hour
	local minute = 0
	local second = 0
	while true do
		Wait(100)
		local ped = PlayerPedId()
		local playerped = GetPlayerPed(-1)
		local isDead = IsEntityDead(ped)
		if isDead and not deathFlag then
			deathFlag = true
			handleDeath(ped)
		elseif not isDead then
			deathFlag = false
		end
		if IsPedShooting(playerped) then
			TriggerServerEvent('SonoranCMS::ServerLogger::PlayerShot', fivemfivemDeathHashTable[GetSelectedPedWeapon(playerped)])
		end
		if GetResourceState('qb-weathersync') ~= 'started' then
			if lastWeather ~= CurrentWeather then
				lastWeather = CurrentWeather
				SetWeatherTypeOverTime(CurrentWeather, 15.0)
				Wait(15000)
			end
			Wait(100)
			SetArtificialLightsState(blackout)
			SetArtificialLightsStateAffectsVehicles(blackoutVehicle)
			ClearOverrideWeather()
			ClearWeatherTypePersist()
			SetWeatherTypePersist(lastWeather)
			SetWeatherTypeNow(lastWeather)
			SetWeatherTypeNowPersist(lastWeather)
			if lastWeather == 'XMAS' then
				SetForceVehicleTrails(true)
				SetForcePedFootstepsTracks(true)
			else
				SetForceVehicleTrails(false)
				SetForcePedFootstepsTracks(false)
			end
			if lastWeather == 'RAIN' then
				SetRainLevel(0.3)
			elseif lastWeather == 'THUNDER' then
				SetRainLevel(0.5)
			else
				SetRainLevel(0.0)
			end
			local newBaseTime = baseTime
			if GetGameTimer() - 22 > timer then
				second = second + 1
				timer = GetGameTimer()
			end
			if freezeTime then
				timeOffset = timeOffset + baseTime - newBaseTime
				second = 0
			end
			baseTime = newBaseTime
			hour = math.floor(((baseTime + timeOffset) / 60) % 24)
			if minute ~= math.floor((baseTime + timeOffset) % 60) then
				minute = math.floor((baseTime + timeOffset) % 60)
				second = 0
			end
			NetworkOverrideClockTime(hour, minute, second)
		end
	end
end)

AddEventHandler('QBCore:Command:SpawnVehicle', function(vehicle)
	TriggerServerEvent('SonoranCMS::ServerLogger::QBSpawnVehicle', vehicle)
end)

AddEventHandler('QBCore:Command:DeleteVehicle', function()
	TriggerServerEvent('SonoranCMS::ServerLogger::QBDeleteVehicle')
end)

AddEventHandler('QBCore:Client:UseItem', function(item)
	TriggerServerEvent('SonoranCMS::ServerLogger::QBClientUsedItem', item)
end)

RegisterNetEvent('SonoranCMS::core::SetEnvironment', function(data)
	CurrentWeather = data.currentWeather
	blackout = data.blackout
	freezeTime = data.freezeTime
	timeOffset = data.timeOffset
	baseTime = data.baseTime
end)
