-- Read-only support snapshot. Never execute config files or invoke their mutating loaders.
local uploadPending = false
local startedAt = os.time()
local configFiles = {
    { path = 'server/modules/clockin/clockin_config.json', fallback = 'server/modules/clockin/clockin_config.dist.json' },
    { path = 'server/modules/whitelist/whitelist_config.json', fallback = 'server/modules/whitelist/whitelist_config.dist.json' },
    { path = 'server/modules/jobsync/jobsync_config.json', fallback = 'server/modules/jobsync/jobsync_config.dist.json' },
    { path = 'server/modules/ace-permissions/ace-permissions_config.json', fallback = 'server/modules/ace-permissions/ace-permissions_config.dist.json' },
}
local dependencies = { 'qb-core', 'qbx_core', 'es_extended', 'ox_lib', 'ox_inventory', 'qb-inventory', 'oxmysql', 'sonorancad' }

local function sensitiveKey(key)
    local field = tostring(key):lower():gsub('[^%w]', '')
    return field:find('apikey', 1, true) or field:find('token', 1, true)
        or field:find('password', 1, true) or field:find('secret', 1, true)
        or field:find('authorization', 1, true) or field:find('webhook', 1, true)
end

local function GetSupportRuntimeInfo()
    return {
        criticalApiError = Config and Config.critError == true,
        apiVersion = Config and Config.apiVersion or nil,
        debugMode = Config and Config.debug_mode == true
    }
end

local function collectSupportLogs()
    local secrets = {}
    local function collectSecrets(value, seen, depth)
        if type(value) ~= 'table' or seen[value] or depth > 32 then return end
        seen[value] = true
        for key, child in pairs(value) do
            if sensitiveKey(key) and type(child) == 'string' and #child >= 4 then
                secrets[#secrets + 1] = child
            elseif type(child) == 'table' then collectSecrets(child, seen, depth + 1) end
        end
    end
    local files = {}
    for _, file in ipairs(configFiles) do
        local ok, raw = pcall(LoadResourceFile, GetCurrentResourceName(), file.path)
        local source = file.path
        local state = 'loaded'
        if ok and raw == nil and file.fallback then
            source = file.fallback
            ok, raw = pcall(LoadResourceFile, GetCurrentResourceName(), source)
            state = 'default_only'
        end
        local item = { path = file.path, source = source, status = state }
        if not ok then item.status = 'read_failed'
        elseif type(raw) ~= 'string' then item.status = 'missing'
        elseif #raw > 100000 then
            item.status = 'omitted_too_large'
            item.originalBytes = #raw
        else
            local decoded, data = pcall(json.decode, raw)
            if decoded and type(data) == 'table' then item.data = data
            else item.status = 'invalid_json' end
            item.originalBytes = #raw
        end
        files[#files + 1] = item
    end
    collectSecrets(Config, {}, 0)
    collectSecrets(files, {}, 0)
    table.sort(secrets, function(a, b) return #a > #b end)
    local function redact(text)
        text = text:gsub('SNRN_PRIV_[%w_-]+', '[REDACTED]'):gsub('SNRN_PUB_[%w_-]+', '[REDACTED]')
        for _, secret in ipairs(secrets) do
            text = text:gsub(secret:gsub('(%W)', '%%%1'), function() return '[REDACTED]' end)
        end
        return text
    end
    local function sanitize(value, seen, depth)
        local kind = type(value)
        if kind == 'string' then return redact(value) end
        if kind == 'nil' or kind == 'boolean' then return value end
        if kind == 'number' then
            if value ~= value or value == math.huge or value == -math.huge then return '<non-finite>' end
            return value
        end
        if kind == 'function' or kind == 'thread' or kind == 'userdata' then return '<' .. kind .. '>' end
        if kind ~= 'table' then return tostring(value) end
        seen, depth = seen or {}, depth or 0
        if seen[value] then return '<recursive-table>' end
        if depth >= 12 then return '<depth-limit>' end
        seen[value] = true
        local result = {}
        for key, child in pairs(value) do
            if type(key) == 'string' or type(key) == 'number' then
                result[key] = sensitiveKey(key) and '[REDACTED]' or sanitize(child, seen, depth + 1)
            end
        end
        seen[value] = nil
        return result
    end
    local function encode(value, limit)
        local text = json.encode(sanitize(value), { indent = true })
        if #text > limit then
            return json.encode({ status = 'omitted_too_large', originalEncodedBytes = #text, limitBytes = limit })
        end
        return text
    end
    local function tail(text, limit)
        if #text <= limit then return text, 0 end
        local start = #text - limit + 1
        -- Avoid cutting through a UTF-8 character.
        while start <= #text and text:byte(start) >= 128 and text:byte(start) < 192 do start = start + 1 end
        return text:sub(start), start - 1
    end

    -- Bound each file independently so one huge configuration cannot hide every
    -- other file (or prevent console/error diagnostics from being uploaded).
    for _, file in ipairs(files) do
        if file.data then
            local encoded = json.encode(sanitize(file.data), { indent = true })
            if #encoded > math.floor(200000 / #configFiles) then
                file.data = nil
                file.status = 'omitted_too_large'
                file.originalEncodedBytes = #encoded
            end
        end
    end

    local configurationFiles = { total = #files, needsAttention = 0, statuses = {} }
    for _, file in ipairs(files) do
        configurationFiles.statuses[file.status] = (configurationFiles.statuses[file.status] or 0) + 1
        if file.status ~= 'loaded' then configurationFiles.needsAttention = configurationFiles.needsAttention + 1 end
    end

    local buffers = type(getSupportErrorBuffer) == 'function' and getSupportErrorBuffer() or {}
    local entries, counts = {}, { errors = 0, warnings = 0 }
    for i, entry in ipairs(buffers) do
        entries[i] = sanitize(entry)
        local level = tostring(entry.level):upper()
        if level == 'ERROR' or level == 'FATAL' then counts.errors = counts.errors + 1
        elseif level == 'WARN' or level == 'WARNING' then counts.warnings = counts.warnings + 1 end
    end
    local encodedErrors = #entries == 0 and '[]' or json.encode(entries)
    while #encodedErrors > 220000 and #entries > 0 do
        table.remove(entries) -- Buffers are newest first: retain the newest complete entries.
        encodedErrors = #entries == 0 and '[]' or json.encode(entries)
    end
    local state = type(GetSupportRuntimeInfo) == 'function' and GetSupportRuntimeInfo() or {}
    local resources = {}
    for _, name in ipairs(dependencies) do
        resources[name] = {
            state = GetResourceState(name),
            version = GetResourceMetadata(name, 'version', 0) or 'unknown'
        }
    end
    local runtime = {
        capturedAt = os.date('!%Y-%m-%dT%H:%M:%SZ'),
        resourceName = GetCurrentResourceName(),
        resourceVersion = GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown',
        fxServerVersion = GetConvar('version', 'unknown'),
        resourceUptimeSeconds = math.max(0, os.time() - startedAt),
        playerCount = #GetPlayers(),
        dependencies = resources,
        configurationFiles = configurationFiles,
        productState = state,
        retainedDiagnostics = {
            errors = counts.errors, warnings = counts.warnings,
            bufferEntries = #buffers, uploadedEntries = #entries, omittedEntries = #buffers - #entries,
            newestAt = buffers[1] and buffers[1].timestamp or nil,
            oldestAt = buffers[#buffers] and buffers[#buffers].timestamp or nil,
            note = 'Counts cover the retained buffer, not all events since startup.'
        }
    }
    local debugBuffer = type(getDebugBuffer) == 'function' and getDebugBuffer() or {}
    local debugMessages = {}
    for i = 1, math.min(50, #debugBuffer) do debugMessages[i] = redact(tostring(debugBuffer[i])) end
    local debugText = table.concat(debugMessages, '\n')
    if #debugText > 40000 then debugText = '[Debug messages omitted: 40000 byte limit]' end
    local console = redact(GetConsoleBuffer() or '')
    local prefix = ([[SonoranCMS Support Output
---------------------------------------
Runtime Snapshot
----------------
%s
---------------------------------------
Configuration Information
---
Core Configuration (effective in-memory values)
%s
Configuration Files (disk snapshot; defaults are labeled)
%s
---------------------------------------
Structured Error Buffer
-----------------------
%s
---------------------------------------
Console Buffer
------
]]):format(encode(runtime, 64000), encode(Config or {}, 64000), encode(files, 220000), encodedErrors)
    local suffix = '\n---------------------------------------\nLast 50 Debug Messages\n----------------------\n' .. debugText
    local clipped, omitted = tail(console, math.max(0, 980000 - #prefix - #suffix - 150))
    local notice = omitted > 0 and ('[Oldest console output omitted: %d bytes; newest output retained]\n'):format(omitted) or ''
    return prefix .. notice .. clipped .. suffix
end

function UploadCmsSupportLogs(ticketId)
    local id = tonumber(ticketId)
    if not id or id < 1 or id > 2147483647 or id % 1 ~= 0 then
        errorLog('SUPPORT_INVALID_ID', 'Use sonorancms support <ticket ID> with the number provided by support.')
        return
    end
    if uploadPending then
        infoLog('A support upload is already in progress. Please wait.')
        return
    end
    local ok, body = pcall(collectSupportLogs)
    if not ok then
        errorLog('SUPPORT_COLLECT_FAILED', 'Unable to collect support diagnostics. Check the resource configuration and restart it.')
        return
    end
    if #body > 1000000 then
        errorLog('SUPPORT_TOO_LARGE', 'Support output exceeds the 1 MB upload limit. Contact support for another way to send the log.')
        return
    end
    uploadPending = true
    infoLog('Please wait, uploading support logs...')
    local finished = false
    local function finish(status, response)
        if finished then return end
        finished = true
        uploadPending = false
        local decodedOk, result = pcall(json.decode, response or '')
        if tonumber(status) == 200 and decodedOk and type(result) == 'table' and result.success == true then
            infoLog('Support logs have been successfully uploaded.')
        else
            errorLog('SUPPORT_UPLOAD_FAILED', ('Support upload failed (HTTP %s). Verify the ticket ID and ask support to enable debug uploads, then retry.'):format(tostring(status)))
        end
    end
    SetTimeout(30000, function() finish('timeout', '') end)
    local requested = pcall(PerformHttpRequest,
        ('https://api.sonoransoftware.com/v2/upload/debug/%d?product=cms'):format(id),
        finish, 'POST', body, { ['Content-Type'] = 'text/plain; charset=utf-8' })
    if not requested then finish('request error', '') end
end
RegisterCommand('sonorancms', function(source, args)
    if source ~= 0 then
        print('This command can only be used from the server console.')
        return
    end
    if args[1] == 'support' then
        UploadCmsSupportLogs(args[2])
    else
        print('Usage: sonorancms support <ticket ID>')
    end
end, true)
