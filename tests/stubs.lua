-- Minimal stand-ins for the FiveM server runtime so the server scripts can run
-- under plain Lua (fengari) in tests/run.js. Test-only; never loaded in game.

T = {
    clock = 1000,          -- GetGameTimer() in ms
    outbox = {},           -- every TriggerClientEvent call
    emitted = {},          -- every local TriggerEvent call
    files = {},            -- in-memory resource files
    aces = {},             -- aces[src][ace] = true
    identifiers = {},      -- identifiers[src] = 'license:...'
    resources = {},        -- resources[name] = 'started'
    exportsOf = {},        -- fake exports of other resources
    ownExports = {},       -- exports registered by psradio
    handlers = {},
    commands = {},
    threads = {},
}

-- ------------------------------------------------------------------ json
do
    local function encode(v, out)
        local tv = type(v)
        if v == nil then out[#out + 1] = 'null'
        elseif tv == 'boolean' then out[#out + 1] = tostring(v)
        elseif tv == 'number' then
            out[#out + 1] = (v == math.floor(v)) and string.format('%d', v) or tostring(v)
        elseif tv == 'string' then
            out[#out + 1] = '"' .. v:gsub('[%c"\\]', function(c)
                return string.format('\\u%04x', c:byte())
            end) .. '"'
        elseif tv == 'table' then
            if #v > 0 then
                out[#out + 1] = '['
                for i = 1, #v do
                    if i > 1 then out[#out + 1] = ',' end
                    encode(v[i], out)
                end
                out[#out + 1] = ']'
            else
                out[#out + 1] = '{'
                local first = true
                for k, val in pairs(v) do
                    if not first then out[#out + 1] = ',' end
                    first = false
                    encode(tostring(k), out)
                    out[#out + 1] = ':'
                    encode(val, out)
                end
                out[#out + 1] = '}'
            end
        else
            error('cannot encode ' .. tv)
        end
    end

    local function decode(s)
        local pos = 1
        local function ws() pos = s:find('%S', pos) or #s + 1 end
        local value
        local function str()
            local out = {}
            pos = pos + 1
            while true do
                local c = s:sub(pos, pos)
                if c == '' then error('unterminated string') end
                if c == '"' then pos = pos + 1 break end
                if c == '\\' then
                    local n = s:sub(pos + 1, pos + 1)
                    if n == 'u' then
                        out[#out + 1] = string.char(tonumber(s:sub(pos + 2, pos + 5), 16) % 256)
                        pos = pos + 6
                    else
                        local map = { n = '\n', t = '\t', r = '\r', b = '\b', f = '\f' }
                        out[#out + 1] = map[n] or n
                        pos = pos + 2
                    end
                else
                    out[#out + 1] = c
                    pos = pos + 1
                end
            end
            return table.concat(out)
        end
        function value()
            ws()
            local c = s:sub(pos, pos)
            if c == '{' then
                local t = {}
                pos = pos + 1
                ws()
                if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
                while true do
                    ws()
                    if s:sub(pos, pos) ~= '"' then error('expected key at ' .. pos) end
                    local k = str()
                    ws()
                    if s:sub(pos, pos) ~= ':' then error('expected : at ' .. pos) end
                    pos = pos + 1
                    t[k] = value()
                    ws()
                    local d = s:sub(pos, pos)
                    pos = pos + 1
                    if d == '}' then return t end
                    if d ~= ',' then error('expected , at ' .. pos) end
                end
            elseif c == '[' then
                local t = {}
                pos = pos + 1
                ws()
                if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
                while true do
                    t[#t + 1] = value()
                    ws()
                    local d = s:sub(pos, pos)
                    pos = pos + 1
                    if d == ']' then return t end
                    if d ~= ',' then error('expected , at ' .. pos) end
                end
            elseif c == '"' then
                return str()
            elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
            elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
            elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
            else
                local num = s:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
                if not num or num == '' then error('unexpected character at ' .. pos) end
                pos = pos + #num
                return tonumber(num)
            end
        end
        local result = value()
        ws()
        if pos <= #s then error('trailing data') end
        return result
    end

    json = {
        encode = function(v) local out = {} encode(v, out) return table.concat(out) end,
        decode = decode,
    }
end

-- ------------------------------------------------------------------ natives
function GetCurrentResourceName() return 'psradio' end
function GetGameTimer() return T.clock end
function GetResourceState(name) return T.resources[name] or 'missing' end
function LoadResourceFile(_, path) return T.files[path] end
function SaveResourceFile(_, path, data) T.files[path] = data return true end
function GetPlayerIdentifierByType(src, kind)
    if kind ~= 'license' then return nil end
    return T.identifiers[tonumber(src)]
end
function IsPlayerAceAllowed(src, ace)
    local set = T.aces[tonumber(src)]
    return set ~= nil and set[ace] == true
end

function RegisterNetEvent() end
function AddEventHandler(name, fn)
    T.handlers[name] = T.handlers[name] or {}
    table.insert(T.handlers[name], fn)
end
function TriggerClientEvent(name, target, ...)
    T.outbox[#T.outbox + 1] = { name = name, target = target, args = { ... } }
end
function TriggerEvent(name, ...)
    T.emitted[#T.emitted + 1] = { name = name, args = { ... } }
end
function RegisterCommand(name, fn) T.commands[name] = fn end

function CreateThread(fn)
    local co = coroutine.create(fn)
    local ok, wait = coroutine.resume(co)
    if not ok then error(wait) end
    if coroutine.status(co) ~= 'dead' then
        T.threads[#T.threads + 1] = { co = co, wake = T.clock + (wait or 0) }
    end
end
function Wait(ms) coroutine.yield(ms) end

exports = setmetatable({}, {
    __call = function(_, name, fn) T.ownExports[name] = fn end,
    __index = function(_, resource) return T.exportsOf[resource] end,
})

-- ------------------------------------------------------------------ test helpers
-- Delivers a net event as if player `src` sent it.
function T.fire(name, src, ...)
    source = src
    for _, fn in ipairs(T.handlers[name] or {}) do fn(...) end
    source = nil
end

-- Removes and returns the argument lists of matching outgoing events.
function T.take(name, target)
    local found, rest = {}, {}
    for _, m in ipairs(T.outbox) do
        if m.name == name and (target == nil or m.target == target) then
            found[#found + 1] = m.args
        else
            rest[#rest + 1] = m
        end
    end
    T.outbox = rest
    return found
end

function T.clear() T.outbox = {} T.emitted = {} end

-- Advances the clock in 50 ms steps, resuming threads whose Wait has elapsed.
function T.advance(ms)
    local target = T.clock + ms
    while T.clock < target do
        T.clock = math.min(target, T.clock + 50)
        for _, th in ipairs(T.threads) do
            if th.wake <= T.clock and coroutine.status(th.co) ~= 'dead' then
                local ok, wait = coroutine.resume(th.co)
                if not ok then error(wait) end
                th.wake = T.clock + (wait or 0)
            end
        end
    end
end
