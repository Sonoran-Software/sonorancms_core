"""Run the real Lua API adapter with mocked FiveM natives: python tests/whitelist_api.py."""
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime, lua_type

lua = LuaRuntime(unpack_returned_tuples=True)


def unpack(value):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys) + 1)):
        return [unpack(value[i]) for i in range(1, len(keys) + 1)]
    return {str(key): unpack(value[key]) for key in keys}


lua.globals().json = lua.table_from({
    'encode': lambda value: json.dumps(unpack(value)),
    'decode': lambda value: lua.table_from(json.loads(value), recursive=True),
})
lua.execute('''
    Config = { CommID = 'community', APIKey = 'test-key', serverId = 17,
        apiIdType = 'discord', apiUrl = 'https://cms.invalid/', debug_mode = false }
    events = {}; threads = {}; registered = {}; requests = {}; timers = {}; triggered = {}
    function print() end
    function SetHttpHandler(callback) httpHandler = callback end
    function RegisterNetEvent(name, callback) events[name] = callback end
    function AddEventHandler(name, callback) events[name] = callback end
    function CreateThread(callback) table.insert(threads, callback) end
    function GetCurrentResourceName() return 'sonorancms' end
    function GetResourcePath() return '/resources/sonorancms' end
    function LoadResourceFile(_, file) return file == 'config.NEW.lua' and 'test stop after API setup' or nil end
    function GetGameTimer() return 0 end
    function GetInvokingResource() return nil end
    function GetPlayers() return {} end
    function TriggerEvent(name, ...)
        table.insert(triggered, name)
        if events[name] then events[name](...) end
    end
    function SetTimeout(delay, callback) table.insert(timers, callback) end
    exports = setmetatable({ sonorancms = {
        HandleHttpRequest = function(_, url, callback, method, data, headers)
            table.insert(requests, {url=url, callback=callback, method=method, data=data})
        end,
        initializeCMS = function() end,
    }}, { __call = function(_, name, callback) registered[name] = callback end })
''')
source = Path(__file__).resolve().parents[1] / 'sonorancms/server/server.lua'
lua.execute(source.read_text(encoding='utf-8'))
# Logging has no bearing on response handling and normally calls additional natives.
lua.execute('debugLog=function() end; infoLog=function() end; warnLog=function() end; errorLog=function() end; logError=function() end')

assert unpack(lua.globals().registered.getWhitelistContext()) == {
    'communityId': 'community', 'serverId': '17',
    'apiIdType': 'discord', 'apiUrl': 'https://cms.invalid/',
}
lua.globals().Config.apiIdType = 'Discord'
assert lua.globals().registered.getWhitelistContext().apiIdType == 'discord'


def request(kind, data):
    replies = []
    lua.globals().registered.performApiRequest(
        lua.table_from(data), kind,
        lambda result, ok: replies.append((result, ok)),
    )
    return lua.globals().requests[len(lua.globals().requests)], replies


for flag in (None, False, True):
    data = {'serverId': 17}
    if flag is not None:
        data['snapshot'] = flag
    sent, replies = request('FULL_WHITELIST', data)
    assert sent.url == 'https://cms.invalid/v2/community/servers/17/whitelist' + ('?snapshot=true' if flag else '')
    payload = {'enabled': True, 'players': [{'name': 'Player', 'apiIds': ['123']}]} if flag else [{'name': 'Player', 'apiIds': ['123']}]
    sent.callback(200, json.dumps({'success': True, 'data': payload}), lua.table())
    assert len(replies) == 1 and replies[0][1] is True
    assert json.loads(replies[0][0]) == payload

for malformed in ('<html>Proxy unavailable</html>', 'Player', '{bad json}',
                  '{"success":false,"error":"offline"}', '{"success":true}',
                  '{"success":true,"data":false}', '{"success":true,"data":123}',
                  '{"success":true,"data":{}}'):
    sent, replies = request('VERIFY_WHITELIST', {'apiId': '123', 'serverId': 17})
    sent.callback(200, malformed, lua.table())
    assert replies == [('Invalid whitelist API response', False)]

sent, replies = request('VERIFY_WHITELIST', {'apiId': '123'})
sent.callback(200, json.dumps({'success': True, 'data': 'Player'}), lua.table())
assert replies == [('Player', True)]
sent, replies = request('VERIFY_WHITELIST', {'apiId': '123'})
sent.callback(400, json.dumps({'detail': 'NOT ALLOWED ON WHITELIST'}), lua.table())
assert replies == [('NOT ALLOWED ON WHITELIST', False)]

# A startup outage must not permanently disable later snapshot/verification requests.
lua.globals().threads[1]()
sub_version = lua.globals().requests[len(lua.globals().requests)]
assert sub_version.url.endswith('/community/sub-version')
sub_version.callback(503, '{"detail":"offline"}', lua.table())
assert lua.globals().Config.critError is not True
sent, replies = request('FULL_WHITELIST', {'snapshot': True})
sent.callback(200, json.dumps({'success': True, 'data': {
    'enabled': False, 'players': [{'name': 'unused', 'apiIds': ['123']}],
}}), lua.table())
assert replies[0][1] is True

# The authenticated account update dispatcher forwards to a local whitelist event.
lua.execute('TriggerEvent("sonorancms::RegisterPushEvent", "TEST", function() end)')
lua.globals().httpHandler(lua.table_from({
    'path': '/events', 'method': 'POST',
    'setDataHandler': lambda callback: callback(json.dumps({'key': 'test-key', 'type': 'ACCOUNT_UPDATED', 'data': {'accId': 'member'}})),
}), lua.table_from({'send': lambda value: None}))
assert 'sonoran_whitelist::rankupdate' in list(lua.globals().triggered.values())

print('whitelist Lua API: snapshot query, envelope validation, denial, startup recovery, and local push routing passed')
