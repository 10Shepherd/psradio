--[[
    Transmission control and voice relay.

    The server decides who may talk (one talker per conventional channel),
    issues a transmission id, and forwards opaque voice packets only from the
    granted talker and only to powered-on members of that channel. It never
    decodes audio.
]]
local Voice = { active = {}, bySrc = {}, lastId = 0 }
PSR.Voice = Voice

local Ev, Registry, Sessions, Limits = PSR.Event, PSR.Registry, PSR.Sessions, PSR.Limits

local function newTxId()
    local id
    repeat id = math.random(1, 2147483646) until id ~= Voice.lastId
    Voice.lastId = id
    return id
end

local function eachListener(tx, fn)
    local set = Sessions.members[tx.channelId]
    if not set then return end
    for src in pairs(set) do
        if src ~= tx.src then fn(src) end
    end
end

--[[
    Asks for the channel. Returns true and the transmission, or false, a reason
    and whether the radio should offer an override.

    A busy channel refuses everyone, including a supervisor: the supervisor is
    told they may override, and only a second press inside the override window
    (`override` true) cuts the other unit off. That way nobody takes a channel
    by leaning on the key.
]]
function Voice.start(sess, now, override)
    if not sess.power then return false, 'radio_off' end
    if not sess.channelId or sess.memberOf ~= sess.channelId then return false, 'no_channel' end
    if not Sessions.canTransmit(sess, sess.channelId) then return false, 'tx_denied' end
    if not sess.txStart:take(now) then return false, 'tx_rate' end

    local current = Voice.active[sess.channelId]
    if current then
        if current.src == sess.src then return true, current end
        local mayOverride = Sessions.canOverride(sess)
        local offered = sess.overrideOfferedAt
        -- The offer belongs to the channel that made it. A supervisor refused
        -- on one channel who switches to another inside the window starts over
        -- there, instead of cutting the new channel off with no warning press.
        local inWindow = offered ~= nil
            and sess.overrideOfferedFor == sess.channelId
            and (now - offered) <= Registry.voice.overrideWindowMs
        if not (override == true and mayOverride and inWindow) then
            -- half-duplex: the channel has a talker
            sess.overrideOfferedAt = mayOverride and now or nil
            sess.overrideOfferedFor = mayOverride and sess.channelId or nil
            return false, 'tx_busy', mayOverride
        end
        Voice.stop(current.src, 'overridden')
    end
    sess.overrideOfferedAt = nil
    sess.overrideOfferedFor = nil

    local channel = Registry.channels[sess.channelId]
    local voice = Registry.voice
    local codec = channel.codec
    if codec == 'opus' and not sess.caps.opus then codec = 'adpcm' end

    local packetsPerSecond = 50 / voice.framesPerPacket
    local tx = {
        id = newTxId(),
        src = sess.src,
        channelId = channel.id,
        codecId = PSR.Codec[codec],
        mode = channel.mode,
        startedAt = now,
        lastFrameAt = now,
        lastSeq = -1,
        label = Sessions.label(sess),
        -- 50% headroom over the nominal packet rate, burst of one second
        bucket = PSR.newBucket(packetsPerSecond * 1.5 + 2, packetsPerSecond * 1.5 + 2),
    }
    Voice.active[channel.id] = tx
    Voice.bySrc[sess.src] = tx

    eachListener(tx, function(src)
        TriggerClientEvent(Ev.clRxStart, src, tx.channelId, tx.id, tx.label, tx.codecId, tx.mode)
    end)
    TriggerEvent('psradio:txStarted', sess.src, tx.channelId)
    return true, tx
end

-- Relays one voice packet. Returns false and a reason when it is dropped.
function Voice.frame(sess, txId, seq, payload, now)
    local tx = Voice.bySrc[sess.src]
    if not tx or tx.id ~= txId then return false, 'no_tx' end
    if not PSR.isInt(seq, 0, 2147483646) or seq <= tx.lastSeq or seq > tx.lastSeq + Limits.maxSeqJump then
        return false, 'bad_seq'       -- replayed, reordered or wildly skipped
    end
    if not PSR.isBase64(payload, Limits.maxPayloadChars) then return false, 'bad_payload' end
    if not tx.bucket:take(now) then return false, 'rate' end

    tx.lastSeq = seq
    tx.lastFrameAt = now
    eachListener(tx, function(src)
        TriggerClientEvent(Ev.clRxFrame, src, tx.id, seq, payload)
    end)
    return true
end

-- reason 'released' = the talker let go; anything else is server-forced and
-- is also reported back to the talker.
function Voice.stop(src, reason)
    local tx = Voice.bySrc[src]
    if not tx then return false end
    Voice.bySrc[src] = nil
    if Voice.active[tx.channelId] == tx then Voice.active[tx.channelId] = nil end

    eachListener(tx, function(listener)
        TriggerClientEvent(Ev.clRxStop, listener, tx.channelId, tx.id, reason)
    end)
    if reason ~= 'released' and Sessions.get(src) then
        TriggerClientEvent(Ev.clTxEnded, src, tx.id, reason)
    end
    TriggerEvent('psradio:txEnded', src, tx.channelId, reason)
    return true
end

function Voice.stopAll(reason)
    local list = {}
    for src in pairs(Voice.bySrc) do list[#list + 1] = src end
    for _, src in ipairs(list) do Voice.stop(src, reason) end
end

-- A radio that tunes to a channel mid-transmission needs the stream header.
function Voice.lateJoin(sess)
    local tx = sess.memberOf and Voice.active[sess.memberOf]
    if tx and tx.src ~= sess.src then
        TriggerClientEvent(Ev.clRxStart, sess.src, tx.channelId, tx.id, tx.label, tx.codecId, tx.mode)
    end
end

-- Enforces the transmission time-out and ends stalled transmissions.
function Voice.tick(now)
    local voice = Registry.voice
    local expired
    for src, tx in pairs(Voice.bySrc) do
        local reason
        if now - tx.startedAt >= voice.txTimeoutSeconds * 1000 then
            reason = 'tx_timeout'
        elseif now - tx.lastFrameAt >= voice.txStallSeconds * 1000 then
            reason = 'tx_stalled'
        end
        if reason then
            expired = expired or {}
            expired[#expired + 1] = { src = src, reason = reason }
        end
    end
    for _, e in ipairs(expired or {}) do Voice.stop(e.src, e.reason) end
end
