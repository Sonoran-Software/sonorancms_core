"""Exercise real Lua support commands with mocked FiveM/HTTP natives (requires lupa)."""
import json
from pathlib import Path
from lupa.lua54 import LuaRuntime, lua_type

ROOT = Path(__file__).resolve().parents[1]
PRODUCT = 'cms'
SCRIPT = ROOT / 'sonorancms/server/support.lua'


def scenario():
    lua = LuaRuntime(unpack_returned_tuples=True)
    def unpack(value):
        if lua_type(value) != 'table':
            return value
        keys = list(value.keys())
        if keys and set(keys) == set(range(1, len(keys) + 1)):
            return [unpack(value[i]) for i in range(1, len(keys) + 1)]
        return {str(k): unpack(v) for k, v in value.items()}
    def decode(value):
        return lua.table_from(json.loads(value), recursive=True)
    lua.globals().json = lua.table_from({'encode': lambda v, *args: json.dumps(unpack(v), indent=2 if args else None), 'decode': decode})
    lua.execute('''
        requests = {}; messages = {}; commands = {}; timers = {}; fileReads = {}
        function GetGameTimer() return 42000 end
        function GetPlayers() return {'1', '2', '3'} end
        function GetResourceState(name) return name == 'qb-core' and 'started' or 'missing' end
        function LoadResourceFile(resource, path)
            fileReads[#fileReads + 1] = path
            if path:find('jammers.json', 1, true) or path:find('jobsync_config.json', 1, true) then return '{broken' end
            if path:find('speakers.json', 1, true) or path:find('whitelist_config.json', 1, true) then return nil end
            return '{"enabled":true,"password":"module-secret-value","setting":"visible setting"}'
        end
        function SaveResourceFile() error('Diagnostics must never write configs') end
        Config = {debug = true, debug_mode = true, APIKey = 'fake-secret-key', nested = {token = 'fake-token-value'}}
        Config.self = Config
        Config.callback = function() end
        function GetCurrentResourceName() return 'test-resource' end
        function GetResourceMetadata() return 'test-version' end
        function GetConvar() return 'test-fxserver' end
        function GetConsoleBuffer() return '[ERROR] ERR-127: Upload failed\\nSNRN_PRIV_fake-token fake-secret-key fake-token-value' end
        function getSupportErrorBuffer() return {{level = 'ERROR', code = 'ERR-127', message = 'Upload failed'}} end
        function getDebugBuffer() return {'debug message'} end
        function infoLog(message) table.insert(messages, message) end
        function errorLog(code, message) table.insert(messages, code .. ': ' .. message) end
        function print(message) table.insert(messages, message) end
        function RegisterCommand(name, callback, restricted) commands[name] = callback; assert(restricted) end
        function SetTimeout(ms, callback) assert(ms == 30000); table.insert(timers, callback) end
        function PerformHttpRequest(url, callback, method, body, headers)
            table.insert(requests, {url=url, callback=callback, method=method, body=body, headers=headers})
        end
    ''')
    lua.execute(SCRIPT.read_text())
    return lua, lua.globals().UploadCmsSupportLogs


def run():
    lua, upload = scenario()
    g = lua.globals()
    for invalid in [None, '', 'abc', 0, -1, 1.5, 2147483648, float('inf')]:
        upload(invalid)
    assert len(g.requests) == 0
    g.commands.sonorancms(42, lua.table_from(['support', '123']))
    assert len(g.requests) == 0, 'Player must not upload the server console'
    upload('123')
    assert len(g.requests) == 1
    request = g.requests[1]
    assert request.url == f'https://api.sonoransoftware.com/v2/upload/debug/123?product={PRODUCT}'
    assert request.method == 'POST'
    assert request.headers['Content-Type'].startswith('text/plain')
    for section in ['Configuration Information', 'Structured Error Buffer', 'Console Buffer', 'Last 50 Debug Messages']:
        assert section in request.body
    assert 'ERR-127' in request.body and 'debug message' in request.body
    for secret in ['fake-secret-key', 'fake-token-value', 'SNRN_PRIV_fake-token', 'module-secret-value']:
        assert secret not in request.body
    assert '[REDACTED]' in request.body and '<recursive-table>' in request.body
    assert 'Configuration Files' in request.body and 'visible setting' in request.body
    assert 'invalid_json' in request.body and 'default_only' in request.body
    assert '"playerCount": 3' in request.body and 'resourceUptimeSeconds' in request.body
    assert len(g.fileReads) >= 4
    config_secret = 'secret-with-"quotes"-and-back\\slash'
    g.Config.APIKey = config_secret
    g.Config.copyOfCredential = config_secret
    assert g.Config.debug and g.Config.debug_mode, 'Support must not change product behavior'
    upload(123)
    assert len(g.requests) == 1, 'Concurrent uploads should be suppressed'
    request.callback(200, '{"success":true}')
    assert 'successfully uploaded' in g.messages[len(g.messages)]
    count = len(g.messages)
    g.timers[1]()
    assert len(g.messages) == count, 'Completed request must not time out later'
    for status, body in [(403, '{"success":false}'), (200, 'bad JSON'), (200, '{"success":false}'), (500, '')]:
        upload(123)
        g.requests[len(g.requests)].callback(status, body)
        assert 'UPLOAD_FAILED' in g.messages[len(g.messages)]
    upload(123)
    g.timers[len(g.timers)]()
    assert 'timeout' in g.messages[len(g.messages)]
    count = len(g.messages)
    g.requests[len(g.requests)].callback(200, '{"success":true}')
    assert len(g.messages) == count, 'Ignore late responses'
    upload(123)
    g.requests[len(g.requests)].callback(200, '{"success":true}')
    lua.execute("function GetConsoleBuffer() return string.rep('x', 1100000) .. ' NEWEST LOG' end")
    count = len(g.requests)
    upload(123)
    assert len(g.requests) == count + 1
    clipped = g.requests[len(g.requests)]
    assert len(clipped.body.encode()) <= 1000000
    assert 'Oldest console output omitted' in clipped.body and 'NEWEST LOG' in clipped.body
    assert config_secret not in clipped.body
    core_section = clipped.body.split('Core Configuration (effective in-memory values)\n')[1].split('Configuration Files')[0]
    assert json.loads(core_section)['copyOfCredential'] == '[REDACTED]'
    clipped.callback(200, '{"success":true}')
    count = len(g.requests)
    lua.execute("function LoadResourceFile(resource, path) if path:find('jammers') or path:find('jobsync') then return string.rep('x', 110000) end return '{\"setting\":\"other files still visible\"}' end")
    lua.execute("function getSupportErrorBuffer() return {{level='ERROR', message=string.rep('x', 300000)}} end")
    upload(123)
    oversized = g.requests[len(g.requests)]
    assert 'other files still visible' in oversized.body and 'omitted_too_large' in oversized.body
    assert '"omittedEntries": 1' in oversized.body and '"uploadedEntries": 0' in oversized.body
    assert len(oversized.body.encode()) <= 1000000
    oversized.callback(200, '{"success":true}')
    count = len(g.requests)
    lua.execute("function GetConsoleBuffer() error('native unavailable') end")
    upload(123)
    assert len(g.requests) == count and 'COLLECT_FAILED' in g.messages[len(g.messages)]
    verify_cms_logger()
    print(f'{PRODUCT}: upload, permissions, payload, redaction, duplicate, size, failure, and timeout checks passed')



def verify_cms_logger():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("Config = {debug_mode = false}; function IsDuplicityVersion() return true end; function print() end; function AddEventHandler() end; function GetCurrentResourceName() return 'sonorancms' end")
    source = (ROOT / 'sonorancms/server/server.lua').read_text()
    block = source[source.index('local function sendConsole'):source.index('function PerformHttpRequestS')]
    lua.execute("local MessageBuffer, DebugBuffer, ErrorBuffer, SupportErrorBuffer = {}, {}, {}, {}; local ERROR_DOC_BASE_URL = 'https://sonorancms.com/error/'; local SupportRefCounter = 0; " + block)
    for offset, key in enumerate(['SUPPORT_INVALID_ID', 'SUPPORT_COLLECT_FAILED', 'SUPPORT_TOO_LARGE', 'SUPPORT_UPLOAD_FAILED']):
        expected = f'ERR-SUP-{101 + offset}'
        assert lua.globals().getErrorMeta(key).code == expected
        lua.execute(f"errorLog('{key}')")
        entry = lua.globals().getSupportErrorBuffer()[1]
        assert entry.level == 'ERROR' and entry.code == expected


if __name__ == '__main__':
    run()
