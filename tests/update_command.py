"""Exercise the console updater against mocked FiveM natives (requires lupa).

Run with ``py tests/update_command.py``. The real Lua files are loaded so these
checks cover the command dispatcher as well as the updater state transitions.
"""

import json
from pathlib import Path

from lupa.lua54 import LuaError, LuaRuntime, lua_type


ROOT = Path(__file__).resolve().parents[1]
UPDATE = ROOT / 'sonorancms/server/update.lua'
SUPPORT = ROOT / 'sonorancms/server/support.lua'


def scenario(*, auto_update=False, restart_with_players=False, os_name='Windows_NT'):
    lua = LuaRuntime(unpack_returned_tuples=True)

    def unpack(value):
        if lua_type(value) != 'table':
            return value
        keys = list(value.keys())
        if keys and set(keys) == set(range(1, len(keys) + 1)):
            return [unpack(value[i]) for i in range(1, len(keys) + 1)]
        return {str(key): unpack(value[key]) for key in keys}

    lua.globals().json = lua.table_from({
        'decode': lambda value: lua.table_from(json.loads(value), recursive=True),
        'encode': lambda value, *args: json.dumps(unpack(value)),
    })
    lua.execute('''
        requests = {}; messages = {}; commands = {}; events = {}; convars = {}; waits = {}
        savedFiles = {}; unzipCalls = {}; registeredExports = {}; threads = {}
        Config = { debug_mode = false, script_version = '1.6.36' }
        function print(message) table.insert(messages, tostring(message)) end
        function infoLog(message) print(message) end
        function errorLog(code, message) print(code .. ': ' .. message) end
        function GetCurrentResourceName() return 'sonorancms' end
        function GetResourcePath(name) return 'C:/fake/' .. name end
        function GetResourceMetadata(_, key) return key == 'version' and '1.6.36' or 'Sonoran CMS' end
        function GetNumPlayerIndices() return playerCount or 0 end
        function LoadResourceFile() return nil end
        function SaveResourceFile(resource, path, contents, length)
            assert(length == -1, 'Resource writes must preserve the complete ZIP/config')
            savedFiles['C:/fake/' .. resource .. '/' .. path] = contents
            return true
        end
        function GetConvar(_, fallback) return fallback end
        function SetConvar(key, value) convars[key] = value end
        function RegisterNetEvent() end
        function AddEventHandler(name, callback) events[name] = callback end
        function RegisterCommand(name, callback, restricted)
            assert(restricted, 'The update command must be restricted')
            assert(commands[name] == nil, 'Do not register sonorancms twice')
            commands[name] = callback
        end
        function PerformHttpRequest(url, callback, method, body, headers)
            table.insert(requests, {url = url, callback = callback, method = method, body = body, headers = headers})
        end
        function ExecuteCommand(command) table.insert(executedCommands, command) end
        executedCommands = {}
        function SetTimeout(ms, callback) table.insert(timers, {ms = ms, callback = callback}) end
        timers = {}
        Citizen = {
            Wait = function(ms) table.insert(waits, ms) end,
            CreateThread = function(callback) table.insert(threads, callback) end,
        }
        exports = setmetatable({}, {
            __call = function(_, name, callback) registeredExports[name] = callback end,
            __index = function(_, resource)
                return { UnzipFile = function(_, path, destination, debug)
                    table.insert(unzipCalls, {path = path, destination = destination, debug = debug})
                end }
            end,
        })
        io.open = function() error('Updater files must use FiveM resource IO') end
        os.remove = function(path) return true end
    ''')
    lua.globals().Config.allowAutoUpdate = auto_update
    lua.globals().Config.restartWithPlayers = restart_with_players
    lua.globals().os.getenv = lambda _: os_name
    lua.execute(UPDATE.read_text())
    lua.execute(SUPPORT.read_text())
    return lua


def issue(lua, source=0):
    lua.globals().commands.sonorancms(source, lua.table_from(['update']), '')


def requests(lua):
    return lua.globals().requests


def messages(lua):
    return '\n'.join(str(value) for value in lua.globals().messages.values())


def check_console_only():
    lua = scenario()
    issue(lua, source=42)
    assert len(requests(lua)) == 0, 'A player must not trigger an update'
    assert 'console' in messages(lua).lower()


def check_same_version_and_config_override():
    for remote in ('1.6.36', '1.6.35'):
        lua = scenario(auto_update=False)
        issue(lua)
        assert len(requests(lua)) == 1, 'Manual update must check for a release even when auto updates are disabled'
        version = requests(lua)[1]
        assert version.method == 'GET' and 'version.json' in version.url
        version.callback(200, '{"resource":"' + remote + '"}', lua.table())
        assert len(requests(lua)) == 1, 'An installed or older release must not be downloaded'
        assert len(lua.globals().unzipCalls) == 0
        if remote == '1.6.36':
            assert 'up to date' in messages(lua).lower() or 'latest' in messages(lua).lower()


def check_newer_release_and_duplicate_requests():
    lua = scenario(auto_update=False)
    issue(lua)
    issue(lua)
    assert len(requests(lua)) == 1, 'Only one update check may be in flight'
    requests(lua)[1].callback(200, '{"resource":"1.6.37"}', lua.table())
    assert len(requests(lua)) == 2
    release = requests(lua)[2]
    assert release.method == 'GET'
    assert release.url == 'https://github.com/Sonoran-Software/sonorancms_core/releases/download/1.6.37/sonorancms_core-1.6.37.zip'
    issue(lua)
    assert len(requests(lua)) == 2, 'Do not start another download while this one is pending'
    release.callback(200, 'PK-test-zip', lua.table())
    assert lua.globals().savedFiles['C:/fake/sonorancms/update.zip'] == 'PK-test-zip'
    assert len(lua.globals().unzipCalls) == 1
    assert lua.globals().unzipCalls[1].path == 'C:/fake/sonorancms/update.zip'
    issue(lua)
    assert len(requests(lua)) == 2, 'Do not start another check while extraction is pending'


def check_linux_manual_update():
    lua = scenario(os_name='Linux')
    issue(lua)
    assert len(requests(lua)) == 1, 'The manual command should work on Linux'
    requests(lua)[1].callback(200, '{"resource":"1.6.37"}', lua.table())
    assert len(requests(lua)) == 2
    requests(lua)[2].callback(200, 'PK-test-zip', lua.table())
    assert len(lua.globals().unzipCalls) == 1


def check_errors_release_lock():
    for code, body in [
        (500, 'unavailable'),
        (200, 'invalid json'),
        (200, '{"resource":"broken"}'),
        (200, '{"resource":"1.6.37/../../evil"}'),
    ]:
        lua = scenario()
        issue(lua)
        requests(lua)[1].callback(code, body, lua.table())
        assert len(lua.globals().unzipCalls) == 0
        issue(lua)
        assert len(requests(lua)) == 2, 'A failed version check must permit retry'
    lua = scenario()
    issue(lua)
    requests(lua)[1].callback(200, '{"resource":"1.6.37"}', lua.table())
    requests(lua)[2].callback(503, 'release unavailable', lua.table())
    assert len(lua.globals().unzipCalls) == 0
    issue(lua)
    assert len(requests(lua)) == 3, 'A failed download must permit retry'

    lua = scenario()
    issue(lua)
    requests(lua)[1].callback(200, '{"resource":"1.6.37"}', lua.table())
    requests(lua)[2].callback(200, 'not a zip', lua.table())
    assert len(lua.globals().unzipCalls) == 0
    issue(lua)
    assert len(requests(lua)) == 3, 'An invalid ZIP must permit retry'

    lua = scenario()
    issue(lua)
    requests(lua)[1].callback(200, '{"resource":"1.6.37"}', lua.table())
    requests(lua)[2].callback(200, 'PK-test-zip', lua.table())
    lua.globals().registeredExports.unzipCoreCompleted(False, 'bad archive')
    issue(lua)
    assert len(requests(lua)) == 3, 'Extraction failure must permit retry'

    lua = scenario()
    original_request = lua.globals().PerformHttpRequest
    lua.execute("PerformHttpRequest = function() error('network unavailable') end")
    issue(lua)
    lua.globals().PerformHttpRequest = original_request
    issue(lua)
    assert len(requests(lua)) == 1, 'A request native error must permit retry'

    lua = scenario()
    issue(lua)
    requests(lua)[1].callback(200, '{"resource":"1.6.37"}', lua.table())
    lua.execute('SaveResourceFile = function() return false end')
    requests(lua)[2].callback(200, 'PK-test-zip', lua.table())
    assert len(lua.globals().unzipCalls) == 0
    issue(lua)
    assert len(requests(lua)) == 3, 'A ZIP write failure must permit retry'


def check_restart_policy():
    delayed = scenario(restart_with_players=False)
    delayed.globals().playerCount = 1
    issue(delayed)
    requests(delayed)[1].callback(200, '{"resource":"1.6.37"}', delayed.table())
    requests(delayed)[2].callback(200, 'PK-test-zip', delayed.table())
    delayed.globals().registeredExports.unzipCoreCompleted(True, None)
    assert 'ensure sonorancms_updatehelper' not in list(delayed.globals().executedCommands.values())
    assert delayed.globals().convars['sonorancms_updatehelper_action'] is None
    issue(delayed)
    assert len(requests(delayed)) == 2, 'A waiting restart must not download the release again'
    delayed.globals().playerCount = 0
    delayed.globals().events['sonorancms::StartUpdateLoop']()
    delayed.globals().events['sonorancms::StartUpdateLoop']()
    assert len(delayed.globals().threads) == 2, 'The update loop must not be started twice'
    delayed.execute('''
        Citizen.Wait = function(ms)
            table.insert(waits, ms)
            error('stop-after-first-update-loop-iteration')
        end
    ''')
    try:
        delayed.globals().threads[2]()
    except LuaError as error:
        assert 'stop-after-first-update-loop-iteration' in str(error)
    assert len(delayed.globals().timers) == 1 and delayed.globals().timers[1].ms == 5000
    assert delayed.globals().convars['sonorancms_updatehelper_action'] is None
    assert 'ensure sonorancms_updatehelper' not in list(delayed.globals().executedCommands.values())
    delayed.globals().timers[1].callback()
    assert delayed.globals().convars['sonorancms_updatehelper_action'] == 'core'
    assert 'ensure sonorancms_updatehelper' in list(delayed.globals().executedCommands.values())
    assert any(0 < value <= 60000 for value in delayed.globals().waits.values()), 'Player deferral should be checked within a minute'

    joining = scenario(restart_with_players=False)
    joining.globals().playerCount = 0
    issue(joining)
    requests(joining)[1].callback(200, '{"resource":"1.6.37"}', joining.table())
    requests(joining)[2].callback(200, 'PK-test-zip', joining.table())
    joining.globals().registeredExports.unzipCoreCompleted(True, None)
    assert len(joining.globals().timers) == 1 and joining.globals().timers[1].ms == 5000
    joining.globals().playerCount = 1
    joining.globals().timers[1].callback()
    assert joining.globals().convars['sonorancms_updatehelper_action'] is None
    assert 'ensure sonorancms_updatehelper' not in list(joining.globals().executedCommands.values())
    issue(joining)
    assert len(requests(joining)) == 2, 'A player joining during the delay must leave the update pending'

    immediate = scenario(restart_with_players=True)
    immediate.globals().playerCount = 1
    issue(immediate)
    requests(immediate)[1].callback(200, '{"resource":"1.6.37"}', immediate.table())
    requests(immediate)[2].callback(200, 'PK-test-zip', immediate.table())
    immediate.globals().registeredExports.unzipCoreCompleted(True, None)
    assert len(immediate.globals().timers) == 1 and immediate.globals().timers[1].ms == 5000
    assert immediate.globals().convars['sonorancms_updatehelper_action'] is None
    assert 'ensure sonorancms_updatehelper' not in list(immediate.globals().executedCommands.values())
    immediate.globals().timers[1].callback()
    assert immediate.globals().convars['sonorancms_updatehelper_action'] == 'core'
    assert 'ensure sonorancms_updatehelper' in list(immediate.globals().executedCommands.values())


def run():
    check_console_only()
    check_same_version_and_config_override()
    check_newer_release_and_duplicate_requests()
    check_linux_manual_update()
    check_errors_release_lock()
    check_restart_policy()
    print('sonorancms update: console, version, override, duplicate, error, and restart checks passed')


if __name__ == '__main__':
    run()
