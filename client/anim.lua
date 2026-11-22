--[[
    What other players see while you are on the radio.

    psradio plays nothing itself: scully_emotemenu owns the animations, and this
    file only decides which of its emote commands to start and when to cancel
    it. Each animation in Config.animations.styles names one emote command, and
    the README lists the emote definitions to add to scully_emotemenu's data
    files.

    One animation plays at a time: the one the player ticked in /radiosetting.
    Nothing plays when they ticked none, when animations are off server-side, on
    a blocked vehicle class, or while the ped is in no state to play one.

    This is cosmetic and entirely local. It never blocks a transmission: if
    scully_emotemenu is missing, or an emote command does not exist in it, the
    radio still works and nothing is played.
]]
PSR = PSR or {}
local Anim = {
    cfg = nil,
    byId = {},              -- style id -> the emote commands for it
    style = 'off',          -- the animation the player ticked, or 'off'
    playing = nil,          -- the emote command we started, while it runs
    wanted = false,         -- the key is down
    warned = false,         -- "scully_emotemenu is not running" said once
}
PSR.Anim = Anim

local EMOTES = 'scully_emotemenu'

local function emotesReady()
    return GetResourceState(EMOTES) == 'started'
end

function Anim.configure(cfg)
    Anim.cfg = type(cfg) == 'table' and cfg or nil
    Anim.byId = {}
    for _, style in ipairs(Anim.cfg and Anim.cfg.styles or {}) do
        if type(style) == 'table' and type(style.id) == 'string' then
            Anim.byId[style.id] = style
        end
    end
end

-- Playing an animation on a ped that is dying, ragdolling or swimming either
-- fails or looks broken, so those states are simply skipped.
local function pedUsable(ped)
    return not IsEntityDead(ped)
        and not IsPedRagdoll(ped)
        and not IsPedSwimming(ped)
        and not IsPedCuffed(ped)
end

-- Both hands are busy on a bike or at the controls of an aircraft.
local function vehicleBlocked(ped)
    local cfg = Anim.cfg
    if not cfg then return false end
    local vehicle = GetVehiclePedIsIn(ped, false)
    if vehicle == 0 then return false end
    local class = GetVehicleClass(vehicle)
    for _, blocked in ipairs(cfg.blockedClasses or {}) do
        if blocked == class then return true end
    end
    return false
end

-- The emote command to play right now, or nil for "play nothing".
local function wantedEmote(ped)
    local cfg = Anim.cfg
    if cfg == nil or cfg.enabled ~= true or Anim.style == 'off' then return nil end

    local style = Anim.byId[Anim.style]
    if not style then return nil end

    if IsPedInAnyVehicle(ped, false) then return style.inVehicle or style.emote end
    if IsPlayerFreeAiming(PlayerId()) then return style.aiming or style.emote end
    return style.emote
end

-- scully_emotemenu cancels emotes of its own accord (fatal damage, a door, a
-- collision), so what we started may already be gone.
local function inEmote()
    if not emotesReady() then return false end
    local ok, result = pcall(function() return exports[EMOTES]:isInEmote() end)
    return ok and result == true
end

local function cancel()
    local emote = Anim.playing
    Anim.playing = nil
    -- Only ever cancel the emote we started: the player may have started one
    -- of their own since.
    if not emote or not emotesReady() then return end
    pcall(function() exports[EMOTES]:cancelEmote() end)
end

-- Starts the transmit animation. Safe to call when one is already running.
function Anim.start()
    local ped = PlayerPedId()
    if not pedUsable(ped) or vehicleBlocked(ped) then return end

    local emote = wantedEmote(ped)
    if not emote then return end
    if not emotesReady() then
        if not Anim.warned then
            Anim.warned = true
            print(('[psradio] %s is not running; radio animations are off'):format(EMOTES))
        end
        return
    end
    if emote == Anim.playing then return end

    cancel()
    -- scully_emotemenu refuses an emote in some states of its own (armed,
    -- limited, in a vehicle when its config says so). That is its call to
    -- make: we ask, and carry on either way.
    local ok = pcall(function() exports[EMOTES]:playEmoteByCommand(emote) end)
    Anim.playing = ok and emote or nil
end

function Anim.stop()
    Anim.wanted = false
    cancel()
end

-- The animation the player ticked, independent of the server-wide switch.
-- Ticking another one mid-transmission swaps the animation over rather than
-- waiting for the next press.
function Anim.setStyle(style)
    style = type(style) == 'string' and style or 'off'
    if style == Anim.style then return end
    Anim.style = style
    Anim.refresh()
end

-- Brings what is playing back in line with the setting and the player's state:
-- used after the setting changes, and while transmitting as the player gets in
-- a car or starts aiming.
function Anim.refresh()
    if not Anim.wanted then
        if Anim.playing then cancel() end
        return
    end
    -- Forget an emote scully_emotemenu has already dropped, so it is started
    -- again rather than thought to be running.
    if Anim.playing and not inEmote() then Anim.playing = nil end
    local ped = PlayerPedId()
    local emote = pedUsable(ped) and not vehicleBlocked(ped) and wantedEmote(ped) or nil
    if emote == Anim.playing then return end
    if not emote then
        cancel()
    else
        Anim.start()
    end
end

-- Called by the client script on transmit start / end.
function Anim.setTransmitting(on)
    if on then
        Anim.wanted = true
        Anim.start()
    else
        Anim.stop()
    end
end

-- While transmitting, keep up with the player: a vehicle or a raised weapon can
-- mean a different emote. Only runs during a transmission, and only looks twice
-- a second.
CreateThread(function()
    while true do
        if Anim.wanted then
            Anim.refresh()
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then Anim.stop() end
end)
