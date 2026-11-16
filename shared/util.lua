-- Small validation and logging helpers used on both sides.
PSR = PSR or {}

local L = PSR.Limits

function PSR.isInt(v, min, max)
    return type(v) == 'number' and v == math.floor(v) and v >= min and v <= max
end

-- Ids are letters, digits, '-' and '_' only, so they are safe as table keys,
-- in ACE names and in file output.
function PSR.isId(v)
    return type(v) == 'string' and #v >= 1 and #v <= L.idMaxLen
        and v:find('^[%w%-_]+$') ~= nil
end

function PSR.isBase64(v, maxLen)
    return type(v) == 'string' and #v >= 4 and #v <= maxLen and #v % 4 == 0
        and v:find('^[%w%+/]+=?=?$') ~= nil
end

function PSR.isCallsign(v)
    return type(v) == 'string' and #v >= 1 and #v <= L.callsignMaxLen
        and v:find('^[%w%-]+$') ~= nil
end

PSR.debug = false

function PSR.log(level, fmt, ...)
    if level == 'debug' and not PSR.debug then return end
    local ok, msg = pcall(string.format, fmt, ...)
    print(('[psradio] [%s] %s'):format(level, ok and msg or fmt))
end
