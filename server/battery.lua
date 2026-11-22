--[[
    Battery: one number per player, counted down by the server.

    It drains while the radio is on, faster while transmitting, and charges
    back while the radio is off, so switching off is how a player looks after
    it. The level is saved against the licence, so reconnecting is not a refill.
    A flat battery switches the radio off and refuses to switch it back on.

    Everything here is a no-op when Config.battery.enabled is false.
]]
local Battery = {}
PSR.Battery = Battery

local Ev = PSR.Event

-- Percent per millisecond, worked out once from the configured minutes.
local function rates()
    local cfg = PSR.Registry.battery
    return 100 / (cfg.capacityMinutes * 60000), 100 / (cfg.chargeMinutes * 60000), cfg
end

function Battery.enabled()
    return PSR.Registry.battery.enabled == true
end

function Battery.get(sess)
    if not Battery.enabled() then return 100 end
    local value = sess.record.battery
    if type(value) ~= 'number' then return 100 end
    return value
end

local function push(sess, charging)
    local shown = math.floor(Battery.get(sess) + 0.5)
    if sess.batteryShown == shown and sess.batteryCharging == charging then return end
    sess.batteryShown = shown
    sess.batteryCharging = charging
    PSR.Store.touch()
    TriggerClientEvent(Ev.clBattery, sess.src, shown, charging)
end

-- Called when a session starts so the radio shows the saved level immediately.
function Battery.prime(sess, now)
    sess.batteryAt = now
    sess.batteryShown = nil
    sess.batteryCharging = nil
    -- Re-arm the warnings that are already below the current level.
    sess.batteryWarned = nil
    for _, level in ipairs(PSR.Registry.battery.warnAtPercent) do
        if Battery.get(sess) > level then break end
        sess.batteryWarned = level
    end
end

-- True when the radio may be switched on.
function Battery.canPowerOn(sess)
    if not Battery.enabled() then return true end
    return Battery.get(sess) > 0
end

function Battery.set(sess, percent)
    if type(percent) ~= 'number' or percent ~= percent then return false end
    sess.record.battery = math.max(0, math.min(100, percent))
    sess.batteryWarned = nil
    PSR.Store.touch()
    push(sess, not sess.power)
    return true
end

-- One step of the drain / charge model for one session.
local function step(sess, now, transmitting)
    local drainPerMs, chargePerMs, cfg = rates()
    local elapsed = now - (sess.batteryAt or now)
    sess.batteryAt = now
    if elapsed <= 0 or elapsed > 60000 then return end   -- clock jump: skip this step

    local before = Battery.get(sess)
    local after = before
    if sess.power then
        local multiplier = transmitting and cfg.txMultiplier or 1
        after = before - elapsed * drainPerMs * multiplier
    elseif before < 100 then
        after = before + elapsed * chargePerMs
    end
    after = math.max(0, math.min(100, after))
    if after == before then
        push(sess, not sess.power and before < 100)
        return
    end
    sess.record.battery = after

    -- warnings, highest level first, each one only once per discharge
    if sess.power and after < before then
        for _, level in ipairs(cfg.warnAtPercent) do
            if after <= level and (sess.batteryWarned == nil or sess.batteryWarned > level) then
                sess.batteryWarned = level
                TriggerClientEvent(Ev.clNotify, sess.src, 'batt_low', level)
                break
            end
        end
    elseif after > before and sess.batteryWarned and after > sess.batteryWarned then
        sess.batteryWarned = nil    -- charged back past the level: warn again next time
    end

    push(sess, not sess.power and after < 100)

    if after <= 0 and sess.power then
        PSR.Voice.stop(sess.src, 'batt_dead')
        sess.power = false
        PSR.Sessions.sync(sess)
        TriggerClientEvent(Ev.clNotify, sess.src, 'batt_dead')
        return true    -- the caller pushes the new radio state
    end
    return false
end

-- Runs over every ready session. `onPowerOff` is called for a session whose
-- battery just went flat, so main.lua can send the state change.
function Battery.tick(now, onPowerOff)
    if not Battery.enabled() then return end
    for src, sess in pairs(PSR.Sessions.bySrc) do
        if sess.ready then
            local transmitting = PSR.Voice.bySrc[src] ~= nil
            if step(sess, now, transmitting) and onPowerOff then onPowerOff(sess) end
        end
    end
end

-- What the client needs to draw the indicator.
function Battery.initPayload(sess)
    local cfg = PSR.Registry.battery
    return {
        enabled = cfg.enabled == true,
        percent = math.floor(Battery.get(sess) + 0.5),
        warnAt = cfg.warnAtPercent[1] or 0,
    }
end
