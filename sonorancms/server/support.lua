-- Support diagnostics use the same upload permission and text format as SonoranCAD.
local uploadPending = false

local function sanitize(value, seen)
    local kind = type(value)
    if kind ~= 'table' then
        if kind == 'function' or kind == 'thread' or kind == 'userdata' then return '<' .. kind .. '>' end
        return value
    end
    seen = seen or {}
    if seen[value] then return '<recursive-table>' end
    seen[value] = true
    local result = {}
    for key, child in pairs(value) do
        if type(key) == 'string' or type(key) == 'number' then
            local field = tostring(key):lower():gsub('[^%w]', '')
            if field:find('apikey', 1, true) or field:find('token', 1, true)
                or field:find('password', 1, true) or field:find('secret', 1, true) then
                result[key] = '[REDACTED]'
            else
                result[key] = sanitize(child, seen)
            end
        end
    end
    seen[value] = nil
    return result
end

local function redact(text)
    text = text:gsub('SNRN_PRIV_[%w_-]+', '[REDACTED]'):gsub('SNRN_PUB_[%w_-]+', '[REDACTED]')
    local function visit(value, seen)
        if type(value) ~= 'table' or seen[value] then return end
        seen[value] = true
        for key, child in pairs(value) do
            local field = tostring(key):lower():gsub('[^%w]', '')
            if type(child) == 'string' and #child >= 4 and
                (field:find('apikey', 1, true) or field:find('token', 1, true)
                or field:find('password', 1, true) or field:find('secret', 1, true)) then
                text = text:gsub(child:gsub('(%W)', '%%%1'), function() return '[REDACTED]' end)
            elseif type(child) == 'table' then visit(child, seen) end
        end
    end
    visit(Config, {})
    return text
end

local function collectSupportLogs()
    local console = GetConsoleBuffer() or ''
    local errors = type(getSupportErrorBuffer) == 'function' and getSupportErrorBuffer() or {}
    local debugMessages = type(getDebugBuffer) == 'function' and getDebugBuffer() or {}
    local output = ([[
SonoranCMS Support Output
---------------------------------------
Configuration Information
---
Version: %s
FXS Version: %s
Core Configuration
%s
---------------------------------------
Structured Error Buffer
-----------------------
%s
---------------------------------------
Console Buffer
------
%s
---------------------------------------
Last 50 Debug Messages
----------------------
%s
]]):format(GetResourceMetadata(GetCurrentResourceName(), 'version', 0) or 'unknown',
        GetConvar('version', 'unknown'), json.encode(sanitize(Config or {})),
        #errors == 0 and '[]' or json.encode(sanitize(errors)), console, table.concat(debugMessages, '\n'))
    return redact(output)
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
