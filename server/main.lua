-- Server entry point: start-up, net event handlers, commands, exports.
local Ev = PSR.Event
local Registry, Store, Framework, Sessions, Voice = PSR.Registry, PSR.Store, PSR.Framework, PSR.Sessions, PSR.Voice

local RESOURCE = GetCurrentResourceName()

-- ---------------------------------------------------------------- start-up
PSR.debug = Config.debug == true

for _, w in ipairs(Registry.build(Config)) do PSR.log('warn', 'config: %s', w) end
local storeStatus = Store.load()
Framework.detect(Config.framework)

local function loadLocale(name)
    local raw = LoadResourceFile(RESOURCE, ('locales/%s.json'):format(name))
    if not raw then return nil end
    local ok, tbl = pcall(json.decode, raw)
    return ok and type(tbl) == 'table' and tbl or nil
end

local strings = loadLocale('en') or {}
if Config.locale ~= 'en' and PSR.isId(Config.locale) then
    local chosen = loadLocale(Config.locale)
    if chosen then
        for k, v in pairs(chosen) do if type(v) == 'string' then strings[k] = v end end
    else
        PSR.log('warn', 'locales/%s.json is missing or invalid; using English', Config.locale)
    end
end

PSR.log('info', 'started: %d zones, %d codeplugs, framework=%s%s, state=%s',
    #Registry.zones, #Registry.codeplugOrder, Framework.name,
    Framework.verified and '' or ' (unverified adapter)', storeStatus)

-- ---------------------------------------------------------------- helpers
local function now() return GetGameTimer() end

local function statePayload(sess)
    return {
        power = sess.power,
        channelId = sess.channelId,
        callsign = sess.record.callsign,
        unitId = sess.record.unitId,
    }
end

local function pushState(sess)
    TriggerClientEvent(Ev.clState, sess.src, statePayload(sess))
end

local function notify(src, key, param)
    TriggerClientEvent(Ev.clNotify, src, key, param)
end

-- Session lookup plus the per-player control rate limit.
local function guard(src)
    local sess = Sessions.get(src)
    if not sess or not sess.ready then return nil end
    if not sess.control:take(now()) then
        PSR.log('debug', 'control rate limit hit by %s', tostring(src))
        return nil
    end
    return sess
end

local function onNet(name, handler)
    RegisterNetEvent(name)
    AddEventHandler(name, handler)
end

-- Applies a codeplug change to a live session.
local function applyAccess(sess, codeplugId)
    if sess.codeplugId == codeplugId then return false end
    sess.codeplugId = codeplugId
    if sess.channelId and not Sessions.canTransmit(sess, sess.channelId) then
        Voice.stop(sess.src, 'access')
        sess.channelId = nil
    end
    if not codeplugId then
        Voice.stop(sess.src, 'access')
        sess.power = false
    end
    Sessions.sync(sess)
    TriggerClientEvent(Ev.clAccess, sess.src, Registry.accessView(codeplugId) or false)
    pushState(sess)
    return true
end

-- ---------------------------------------------------------------- net events
onNet(Ev.svReady, function(version, caps)
    local src = source
    if type(src) ~= 'number' or src < 1 then return end
    local sess = Sessions.get(src) or Sessions.create(src)
    if not sess.control:take(now()) then return end
    if version ~= PSR.PROTOCOL_VERSION then
        PSR.log('warn', 'player %d speaks protocol %s, expected %d', src, tostring(version), PSR.PROTOCOL_VERSION)
        return
    end

    -- A (re)connecting client always starts from a clean, powered-off radio.
    Voice.stop(src, 'reset')
    sess.caps = { opus = type(caps) == 'table' and caps.opus == true }
    sess.power = false
    sess.codeplugId = Sessions.resolveCodeplug(src)
    sess.channelId = nil
    local last = sess.record.lastChannel
    if last and Registry.channels[last] and Sessions.canTransmit(sess, last) then
        sess.channelId = last
    end
    Sessions.sync(sess)
    sess.ready = true

    local voice = Registry.voice
    TriggerClientEvent(Ev.clInit, src, {
        protocol = PSR.PROTOCOL_VERSION,
        strings = strings,
        keys = {
            ptt = type(Config.keys) == 'table' and Config.keys.ptt or 'B',
            toggle = type(Config.keys) == 'table' and Config.keys.toggle or 'F6',
        },
        voice = { txTimeoutSeconds = voice.txTimeoutSeconds },
        access = Registry.accessView(sess.codeplugId) or false,
        state = statePayload(sess),
    })
end)

onNet(Ev.svPower, function(on)
    local sess = guard(source)
    if not sess or type(on) ~= 'boolean' then return end
    if on and not sess.codeplugId then
        notify(sess.src, 'no_access')
        return
    end
    if not on then Voice.stop(sess.src, 'power') end
    sess.power = on
    Sessions.sync(sess)
    pushState(sess)
    if on then Voice.lateJoin(sess) end
end)

onNet(Ev.svSelect, function(channelId)
    local sess = guard(source)
    if not sess or not PSR.isId(channelId) then return end
    local cp = Registry.codeplugs[sess.codeplugId]
    if not cp or not Registry.channels[channelId] or not (cp.tx[channelId] or cp.scan[channelId]) then
        notify(sess.src, 'invalid_channel')
        return
    end
    if not cp.tx[channelId] then
        notify(sess.src, 'scan_only')
        return
    end
    if sess.channelId == channelId then return end

    Voice.stop(sess.src, 'retune')
    sess.channelId = channelId
    Sessions.sync(sess)
    if sess.record.lastChannel ~= channelId then
        sess.record.lastChannel = channelId
        Store.touch()
    end
    pushState(sess)
    Voice.lateJoin(sess)
end)

onNet(Ev.svTxStart, function(clientSeq)
    local sess = guard(source)
    if not sess or not PSR.isInt(clientSeq, 0, 2147483646) then return end
    local ok, result = Voice.start(sess, now())
    if not ok then
        TriggerClientEvent(Ev.clTxDenied, sess.src, clientSeq, result)
        return
    end
    local voice = Registry.voice
    TriggerClientEvent(Ev.clTxGranted, sess.src, clientSeq, result.id, {
        codec = result.codecId,
        bitrate = voice.opusBitrate,
        framesPerPacket = voice.framesPerPacket,
        maxSeconds = voice.txTimeoutSeconds,
    })
end)

-- Voice packets have their own limiter (per transmission), not the control one.
onNet(Ev.svTxFrame, function(txId, seq, payload)
    local sess = Sessions.get(source)
    if not sess or not sess.ready then return end
    Voice.frame(sess, txId, seq, payload, now())
end)

onNet(Ev.svTxStop, function()
    local sess = guard(source)
    if sess then Voice.stop(sess.src, 'released') end
end)

-- ---------------------------------------------------------------- lifecycle
AddEventHandler('playerDropped', function()
    local src = source
    Voice.stop(src, 'disconnect')
    Sessions.remove(src)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= RESOURCE then return end
    Voice.stopAll('shutdown')
    Store.save()
end)

CreateThread(function()
    while true do
        Wait(250)
        Voice.tick(now())
    end
end)

CreateThread(function()
    local interval = math.max(1, tonumber(Config.access and Config.access.refreshSeconds) or 5) * 1000
    while true do
        Wait(interval)
        for src, sess in pairs(Sessions.bySrc) do
            if sess.ready then applyAccess(sess, Sessions.resolveCodeplug(src)) end
        end
    end
end)

CreateThread(function()
    local interval = math.max(5, tonumber(Config.persistence and Config.persistence.saveIntervalSeconds) or 15) * 1000
    while true do
        Wait(interval)
        Store.save()
    end
end)

-- ---------------------------------------------------------------- commands
-- /callsign <text> | /callsign clear | /callsign
RegisterCommand('callsign', function(src, args)
    if src == 0 then return end
    local sess = guard(src)
    if not sess then return end
    local value = args[1]
    if value == nil then
        notify(src, sess.record.callsign and 'callsign_current' or 'callsign_none', sess.record.callsign)
    elseif value == 'clear' then
        sess.record.callsign = nil
        Store.touch()
        notify(src, 'callsign_cleared')
        pushState(sess)
    elseif #args == 1 and PSR.isCallsign(value) then
        sess.record.callsign = value
        Store.touch()
        notify(src, 'callsign_set', value)
        pushState(sess)
    else
        notify(src, 'callsign_invalid')
    end
end, false)

-- ---------------------------------------------------------------- exports
-- Documented in README.md -> "Exports and events".
exports('getPlayerChannel', function(src)
    local sess = Sessions.get(tonumber(src))
    return sess and sess.memberOf or nil
end)

exports('getPlayerCodeplug', function(src)
    local sess = Sessions.get(tonumber(src))
    return sess and sess.codeplugId or nil
end)

exports('isTransmitting', function(src)
    return Voice.bySrc[tonumber(src)] ~= nil
end)

-- Re-evaluates one player's codeplug now instead of at the next poll.
exports('refreshAccess', function(src)
    local sess = Sessions.get(tonumber(src))
    if not sess or not sess.ready then return false end
    applyAccess(sess, Sessions.resolveCodeplug(sess.src))
    return true
end)
