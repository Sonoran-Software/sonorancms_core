-- Run from the repository root with Lua 5.3+ (or npx --package=fengari-node-cli fengari).
-- Exercise the real request handler with a bounded database adapter and FiveM stubs.
local function equal(actual, expected, message)
	assert(actual == expected, (message or 'unexpected value') .. ': expected ' .. tostring(expected) .. ', got ' .. tostring(actual))
end

local function copy(value)
	if type(value) ~= 'table' then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

Config = { framework = 'qb-core' }
CreateThread = function() end
Citizen = { CreateThread = CreateThread }
RegisterConsoleListener = function() end
RegisterNetEvent = function() end
AddEventHandler = function() end
TriggerEvent = function() end
Wait = function() error('Database requests must await results, not use fixed delays') end
GetCurrentResourceName = function() return 'sonorancms' end
local started = { ['qb-core'] = true, ['oxmysql'] = true, ['qb-inventory'] = true, ['qb-garages'] = true }
GetResourceState = function(name) return started[name] and 'started' or 'missing' end
json = { decode = function(value) return value end }

local rows, vehicles, garageRows = {}, {}, {}
for index = 1, 253 do
	local citizenid = ('C%04d'):format(index)
	rows[index] = {
		citizenid = citizenid, license = 'license:' .. citizenid,
		charinfo = { firstname = 'First', lastname = citizenid },
		job = { name = 'police', label = 'Police', grade = { name = 'Officer' } },
		money = { bank = index, cash = 0 }, inventory = {}, metadata = {}
	}
	vehicles[index] = { id = index, citizenid = index <= 130 and 'OWNER' or citizenid, vehicle = 'adder', plate = citizenid, garage = 'central', state = 1 }
	garageRows[index] = { gid = citizenid, name = 'Garage ' .. citizenid, spawns = { { x = 1, y = 2, z = 3 } } }
end
local online = { [42] = { PlayerData = { citizenid = 'C0200', source = 42, items = {}, job = { name = 'police', grade = { name = 'Officer' } } } } }
local qb = { Shared = { Items = {} }, Functions = {
	GetPlayer = function(source) return online[source] end,
	GetQBPlayers = function() return online end,
	GetPlayerByCitizenId = function(citizenid)
		for _, player in pairs(online) do if player.PlayerData.citizenid == citizenid then return player end end
	end
} }
local exportedGarages = { bravo = { label = 'Bravo' }, alpha = { label = 'Alpha' }, charlie = { label = 'Charlie' } }
exports = { ['qb-core'] = { GetCoreObject = function() return qb end }, ['qb-garages'] = { getAllGarages = function() return exportedGarages end } }

local queries = {}
local function filtered(sql, parameters)
	local source = sql:find('`player_vehicles`', 1, true) and vehicles or sql:find('`ak47_qb_garage`', 1, true) and garageRows or rows
	local result = {}
	for _, row in ipairs(source) do
		local matches = true
		if sql:find('`citizenid` = ?', 1, true) then matches = row.citizenid == parameters[1] end
		if sql:find('`id` = ?', 1, true) then matches = row.id == parameters[1] end
		if sql:find('1 = 0', 1, true) then matches = false end
		if sql:find('`citizenid` IN (', 1, true) then matches = row.citizenid == parameters[1] end
		if matches then table.insert(result, copy(row)) end
	end
	return result
end
MySQL = {
	scalar = { await = function(sql, parameters)
		table.insert(queries, { sql = sql, parameters = copy(parameters) })
		assert(sql:find('LIMIT 1', 1, true), 'Count result must also be explicitly bounded')
		return #filtered(sql, parameters)
	end },
	query = { await = function(sql, parameters)
		table.insert(queries, { sql = sql, parameters = copy(parameters) })
		assert(sql:find('LIMIT ? OFFSET ?', 1, true), 'Collection query is unbounded')
		assert(sql:find('ORDER BY', 1, true), 'Collection query is unstable')
		local pageSize, offset = parameters[#parameters - 1], parameters[#parameters]
		assert(pageSize >= 1 and pageSize <= 100, 'Collection query exceeded row cap')
		local all, page = filtered(sql, parameters), {}
		for index = offset + 1, math.min(offset + pageSize, #all) do table.insert(page, all[index]) end
		return page
	end }
}

assert(loadfile('sonorancms/server/pushEvents.lua'))()
local function request(key, options)
	queries = {}
	return handleDataRequest({ dataKeys = { key }, pagination = options and { [key] = options } or nil })
end

local first = request('characters')
equal(#first.data.characters, 25)
equal(first.pagination.characters.total, 253)
equal(first.pagination.characters.hasMore, true)
equal(#queries, 2, 'Default request must not walk the full table')
local second = request('characters', { page = 2, pageSize = 100 })
equal(#second.data.characters, 100)
equal(second.data.characters[1].citizenid, 'C0101')
local last = request('characters', { page = 3, pageSize = 100 })
equal(#last.data.characters, 53)
equal(last.pagination.characters.hasMore, false)
local beyond = request('characters', { page = 4, pageSize = 100 })
equal(#beyond.data.characters, 0)
equal(beyond.pagination.characters.total, 253)
local capped = request('characters', { page = -9, pageSize = 1000000, sortBy = 'citizenid; DROP TABLE players' })
equal(#capped.data.characters, 100)
equal(capped.pagination.characters.page, 1)
assert(queries[2].sql:find('ORDER BY `citizenid` ASC LIMIT', 1, true))
assert(not queries[2].sql:find('DROP', 1, true))
request('characters', { search = "O'Brien%_!", sortBy = 'name', descending = true })
equal(queries[2].parameters[1], "%O'Brien!%!_!!%")
assert(not queries[2].sql:find("O'Brien", 1, true), 'Search must remain a bound value')
assert(queries[2].sql:find(' DESC, `citizenid` ASC LIMIT', 1, true), 'Names need a unique tie-breaker')
local _, nameExtractions = queries[2].sql:gsub('JSON_EXTRACT', '')
local _, guardedNameExtractions = queries[2].sql:gsub('JSON_EXTRACT%(CASE WHEN JSON_VALID%(`charinfo`%) THEN `charinfo` ELSE', '')
equal(guardedNameExtractions, nameExtractions, 'Search and sorting must not abort on malformed character JSON')
request('characters', { sortBy = 'job' })
assert(queries[2].sql:find("JSON_EXTRACT(CASE WHEN JSON_VALID(`job`) THEN `job` ELSE '{}' END", 1, true), 'Job sorting must guard malformed JSON')
local chinese = ('界'):rep(34)
request('characters', { search = chinese, citizenId = chinese })
equal(queries[2].parameters[1], chinese, 'Citizen IDs must not be truncated by UTF-8 byte count')
equal(queries[2].parameters[2], '%' .. chinese .. '%', 'Chinese search must remain valid and complete')
local accented = ('é'):rep(100)
request('characters', { search = accented, citizenId = accented })
equal(queries[2].parameters[1], accented, '100 accented characters must be retained')
equal(queries[2].parameters[2], '%' .. accented .. '%')
request('characters', { search = ('界'):rep(101), citizenId = ('é'):rep(101) })
equal(queries[2].parameters[1], accented, 'Oversized citizen IDs must truncate at a character boundary')
equal(queries[2].parameters[2], '%' .. ('界'):rep(100) .. '%')
local invalidText = request('characters', { citizenId = string.char(0xE7, 0x95) })
equal(invalidText.data.characters, nil, 'Invalid UTF-8 must reject the query instead of dropping an exact filter')
equal(invalidText.errors[1].code, 'characters')
equal(#queries, 0)

local selected = request('characters', { citizenId = 'C0200' })
equal(#selected.data.characters, 1)
equal(selected.data.characters[1].citizenid, 'C0200')
equal(selected.data.characters[1].offline, false)
equal(selected.pagination.characters.pageSize, 25)
equal(selected.pagination.characters.page, 1)
equal(queries[2].parameters[#queries[2].parameters - 1], 1, 'Exact lookup must request at most one SQL row')
local selectedBeyond = request('characters', { citizenId = 'C0200', page = 2 })
equal(#selectedBeyond.data.characters, 0)
equal(selectedBeyond.pagination.characters.page, 2)
equal(selectedBeyond.pagination.characters.total, 1)
local bySource = request('characters', { source = 42 })
equal(bySource.data.characters[1].citizenid, 'C0200')
equal(bySource.pagination.characters.pageSize, 25)
equal(#request('characters', { source = 42, page = 2 }).data.characters, 0)
equal(#request('characters', { source = 404 }).data.characters, 0)
local active = request('characters', { onlineOnly = true })
equal(#active.data.characters, 1)
equal(active.pagination.characters.total, 1)
online = {}
equal(#request('characters', { onlineOnly = true }).data.characters, 0)

local owner = request('characterVehicles', { citizenId = 'OWNER', page = 2, pageSize = 100 })
equal(#owner.data.characterVehicles, 30)
equal(owner.pagination.characterVehicles.total, 130)
equal(owner.data.characterVehicles[1].id, 101)
equal(#queries, 2, 'Owner vehicle request must fetch only its requested page')
local vehicle = request('characterVehicles', { vehicleId = 200 })
equal(vehicle.data.characterVehicles[1].id, 200)
equal(vehicle.pagination.characterVehicles.pageSize, 25)
equal(#request('characterVehicles', { vehicleId = 200, page = 2 }).data.characterVehicles, 0)

local garagePage = request('garages', { page = 2, pageSize = 1 })
equal(garagePage.data.garages[1].name, 'bravo')
equal(garagePage.pagination.garages.total, 3)
equal(exportedGarages.bravo.name, nil, 'Export-owned data must not be mutated')
equal(request('garages', { search = 'Charlie' }).pagination.garages.total, 1)
started['qb-garages'], started['ak47_qb_garage'] = nil, true
local sqlGarages = request('garages', { page = 3, pageSize = 100 })
equal(#sqlGarages.data.garages, 53)
equal(sqlGarages.data.garages[1].name, 'C0201')
equal(sqlGarages.pagination.garages.total, 253)
equal(#queries, 2)

started['qb-core'], started['qbx_core'] = nil, true
Config.framework = 'qbox'
equal(#request('characters', { pageSize = 1 }).data.characters, 1, 'Qbox bridge must support paged data')
started['ak47_qb_garage'], started['qbx_garages'] = nil, true
exports['qbx_garages'] = { GetGarages = function()
	return { central = { label = 'Central', accessPoints = { { coords = { x = 1, y = 2, z = 3 } } } } }
end }
local qboxGarages = request('garages')
equal(qboxGarages.data.garages[1].name, 'central')
equal(qboxGarages.pagination.garages.total, 1)
equal(#queries, 0, 'Qbox garages must preserve the upstream export path')
local charinfo = rows[1].charinfo
rows[1].charinfo = false
local partial = request('characters')
equal(#partial.data.characters, 24, 'A malformed character must not discard other records on its page')
equal(partial.pagination.characters.total, 253)
equal(partial.errors[1].code, 'characters')
local brokenDetail = request('characters', { citizenId = 'C0001' })
equal(#brokenDetail.data.characters, 0, 'Decode failures must retain successful query pagination')
equal(brokenDetail.pagination.characters.total, 1)
equal(brokenDetail.errors[1].code, 'characters')
rows[1].charinfo = charinfo
equal(#request('characters').errors, 0, 'Request errors must not persist into the next request')
local firstPageCharacterInfo = {}
for index = 1, 25 do
	firstPageCharacterInfo[index] = rows[index].charinfo
	rows[index].charinfo = false
end
local malformedPage = request('characters')
equal(#malformedPage.data.characters, 0)
equal(malformedPage.pagination.characters.total, 253, 'An all-malformed page must retain navigation to later records')
equal(malformedPage.pagination.characters.hasMore, true)
equal(malformedPage.errors[1].code, 'characters')
local goodNextPage = request('characters', { page = 2 })
equal(#goodNextPage.data.characters, 25)
equal(goodNextPage.data.characters[1].citizenid, 'C0026')
equal(#goodNextPage.errors, 0)
for index = 1, 25 do rows[index].charinfo = firstPageCharacterInfo[index] end
local queryAwait = MySQL.query.await
MySQL.query.await = function() return nil end
local failedDatabase = request('characters')
equal(failedDatabase.data.characters, nil, 'Failed database results must not look like empty pages')
equal(failedDatabase.errors[1].code, 'characters')
MySQL.query.await = queryAwait
started['qbx_core'] = nil
equal(request('characters').data.characters, nil)
equal(#queries, 0, 'Unavailable framework must not query the database')

print('Game panel pagination tests passed')
