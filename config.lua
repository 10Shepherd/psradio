--[[
    psradio configuration — the one file you edit.

    This file is loaded on the SERVER only. Players are sent just the zones and
    channels their codeplug allows, so the full layout is never downloaded by
    clients. Secrets (added by later phases) go in server.cfg convars, not here.

    Every setting in this file is read at resource start: after editing, run
    `restart psradio`. Live-editable settings arrive with the admin panel phase.
]]

Config = {}

Config.locale = 'en'        -- file name in locales/, falls back to en for missing keys
Config.debug  = false       -- verbose server console output

-- 'auto' detects qbx_core, qb-core, es_extended, ND_Core, ox_core (in that order).
-- Set a name to force one, or 'standalone' to use ACE permissions only.
Config.framework = 'auto'

-- Default keys. Players rebind them in FiveM Settings -> Key Bindings.
-- A default only applies the first time a player sees the binding.
Config.keys = {
    ptt    = 'B',   -- hold to transmit
    toggle = 'F6',  -- show / hide the radio
}

Config.voice = {
    defaultCodec     = 'opus',  -- 'opus' or 'adpcm'; a channel may override it
    opusBitrate      = 16000,   -- bits per second, 6000..64000
    framesPerPacket  = 3,       -- 20 ms frames per network packet (1..6); 3 = 60 ms
    txTimeoutSeconds = 60,      -- longest single transmission
    txStallSeconds   = 3,       -- a transmission with no audio for this long is ended

    -- "Bonk" override. A unit whose codeplug has supervisor = true may cut into
    -- a busy channel, but never by accident: the first press is refused with the
    -- busy tone and the display offers the override, and only a second press
    -- within overrideWindowSeconds takes the channel. The unit being cut off
    -- hears why. Set allowOverride = false to refuse supervisors as well.
    allowOverride        = true,
    overrideWindowSeconds = 3,
}

Config.access = {
    refreshSeconds = 5,         -- how often job / ACE changes are picked up

    -- Codeplug given to everybody when no framework is running and no ACE
    -- matches. nil = unmapped players get no radio (recommended).
    standaloneCodeplug = nil,

    -- Optional hook for frameworks psradio does not know (for example nat2k15):
    -- return a codeplug id, false for "no radio", or nil to fall through to the
    -- built-in rules.
    --   resolve = function(source) return 'leo' end,
    resolve = nil,
}

Config.persistence = {
    saveIntervalSeconds = 15,   -- data/state.json is written at most this often
}

-- ---------------------------------------------------------------------------
-- Receive audio chain. These are the numbers the radio page builds its filters
-- from, so they change how a transmission SOUNDS, not what is sent. Players
-- scale them for themselves with the `fx` setting (full / light / off).
-- Frequencies are hertz; levels are 0..1 unless noted.
-- ---------------------------------------------------------------------------
Config.audio = {
    digital = {
        high = 250, low = 3400,  -- pass band
        noise = 0.0,             -- digital channels are clean by design
    },
    analog = {
        high = 380, low = 2400,  -- narrower band than digital
        drive = 1.6,             -- how hard the soft clipper is pushed; 1 = almost clean,
                                 -- 2.5 is heavy, past that speech starts to flat-top
        makeup = 0.8,            -- level correction after the clipper
        noise = 0.06,            -- hiss mixed under an open carrier
        tailMs = 110,            -- squelch tail: noise burst when the carrier drops
    },
    rogerBeep = true,            -- courtesy beep to listeners at the end of a transmission
    toneVolume = 0.25,           -- default tone level (players can change it)
}

-- ---------------------------------------------------------------------------
-- Radio models. `skin` is one of 'handheld', 'mobile' or 'console' and decides
-- how the page draws the radio; `softkeys` is how many menu keys it has (3 or
-- 4). A codeplug's `models` list says which of these a unit may carry, and the
-- first entry in that list is what a player gets until they pick another in the
-- radio's settings. Phase 2 models differ in looks and softkey count; they do
-- not yet differ in features.
-- ---------------------------------------------------------------------------
Config.models = {
    handheld = { name = 'Portable', skin = 'handheld', softkeys = 3 },
    duty     = { name = 'Duty Belt', skin = 'handheld', softkeys = 4 },
    mobile   = { name = 'Mobile', skin = 'mobile', softkeys = 4 },
    console  = { name = 'Console', skin = 'console', softkeys = 4 },
}

-- ---------------------------------------------------------------------------
-- Battery. The server counts it down while the radio is on, faster while
-- transmitting, and charges it back while the radio is off. It is saved per
-- player, so switching the radio off is how you look after it.
--   capacityMinutes   minutes of runtime from full, radio on and idle
--   txMultiplier      how much faster it drains while transmitting
--   chargeMinutes     minutes to go from empty to full with the radio off
--   warnAtPercent     levels that chirp a warning as they are crossed
-- enabled = false switches the whole feature off and keeps every radio at 100%.
-- ---------------------------------------------------------------------------
Config.battery = {
    enabled         = true,
    capacityMinutes = 480,      -- 8 hours idle
    txMultiplier    = 6,        -- transmitting costs 6x idle
    chargeMinutes   = 90,
    warnAtPercent   = { 25, 10, 5 },
}

-- ---------------------------------------------------------------------------
-- Animations played on the player's own character while transmitting, so other
-- players can see who is on the radio.
--
-- psradio does not play animations itself: scully_emotemenu does, and the emote
-- names below are its emote commands (what you would type after a / in its
-- menu). README lists the emote definitions to add to its data files.
--
-- Every entry here becomes its own tick box in /radiosetting. Ticking one
-- unticks the others, because only one animation can play; unticking it means
-- no animation at all. The order here is the order they are listed.
--   id         unique, letters/digits/-/_ only; what is saved for the player
--   emote      the emote command that plays while transmitting
--   aiming     used instead while the player is aiming a weapon (optional)
--   inVehicle  used instead while the player is in a vehicle (optional)
--   label      what the tick box says (optional). Without one, the locale's
--              "set_anim_<id>" is used, and failing that the id itself, so an
--              animation of your own only needs a label here.
-- `enabled = false` switches animations off for the whole server.
-- ---------------------------------------------------------------------------
Config.animations = {
    enabled = true,

    styles = {
        { id = 'shoulder', emote = 'radio',      aiming = 'radio2', inVehicle = 'radio2' },
        { id = 'chest',    emote = 'radiochest', inVehicle = 'wt2' },
        { id = 'earpiece', emote = 'earpiece',   inVehicle = 'wt2' },
        { id = 'handheld', emote = 'wt2',        inVehicle = 'wt2' },
    },

    -- Vehicle classes with no animation at all: both hands are busy.
    -- 8 motorcycle, 13 bicycle, 15 helicopter, 16 plane.
    blockedClasses = { 8, 13, 15, 16 },
}

-- ---------------------------------------------------------------------------
-- Starting point for a player's own settings. Each player changes these with
-- /radiosetting and they are saved against their licence; these values only
-- apply until they do. `model` nil = the first model their codeplug allows.
-- ---------------------------------------------------------------------------
Config.settings = {
    volume     = 80,        -- 0..100
    toneVolume = 25,        -- 0..100
    fx         = 'full',    -- 'full' | 'light' | 'off' — strength of the receive effects
    rogerBeep  = true,      -- hear the courtesy beep at the end of a transmission
    -- which transmit animation plays: an id from Config.animations.styles, or
    -- 'off' for none
    animStyle  = 'handheld',
    pttMode    = 'hold',    -- 'hold' | 'toggle'
    model      = nil,
}

Config.security = {
    controlRate  = 10, controlBurst = 30,  -- control messages per second, per player
    txStartRate  = 2,  txStartBurst = 4,   -- PTT presses per second, per player
}

-- ---------------------------------------------------------------------------
-- Zones and channels (demo set: 3 zones, 12 channels)
--   id        unique, letters/digits/-/_ only
--   name      up to 16 characters, shown on the radio
--   frequency display only, MHz
--   type      'conventional' (trunked arrives in a later phase)
--   mode      'digital' or 'analog' — selects the receive sound
--   codec     'opus' or 'adpcm' (optional, defaults to voice.defaultCodec)
-- ---------------------------------------------------------------------------
Config.zones = {
    {
        id = 'state', name = 'STATEWIDE',
        channels = {
            { id = 'state-disp', name = 'DISPATCH', frequency = 151.130, mode = 'digital' },
            { id = 'state-c2c',  name = 'CAR-CAR',  frequency = 151.205, mode = 'digital' },
            { id = 'state-tac',  name = 'TAC 1',    frequency = 151.310, mode = 'analog', codec = 'adpcm' },
            { id = 'state-ops',  name = 'OPS 1',    frequency = 151.475, mode = 'digital' },
            { id = 'state-fire', name = 'FIREGRND', frequency = 151.530, mode = 'analog', codec = 'adpcm' },
        },
    },
    {
        id = 'city', name = 'CITY',
        channels = {
            { id = 'city-disp', name = 'DISPATCH', frequency = 453.150, mode = 'digital' },
            { id = 'city-c2c',  name = 'CAR-CAR',  frequency = 453.275, mode = 'digital' },
            { id = 'city-tac',  name = 'TAC 1',    frequency = 453.400, mode = 'analog', codec = 'adpcm' },
            { id = 'city-fire', name = 'FIREGRND', frequency = 453.850, mode = 'analog', codec = 'adpcm' },
        },
    },
    {
        id = 'county', name = 'COUNTY',
        channels = {
            { id = 'county-disp', name = 'DISPATCH', frequency = 155.415, mode = 'digital' },
            { id = 'county-c2c',  name = 'CAR-CAR',  frequency = 155.520, mode = 'digital' },
            { id = 'county-tac',  name = 'TAC 1',    frequency = 155.640, mode = 'analog', codec = 'adpcm' },
            { id = 'county-fire', name = 'FIREGRND', frequency = 155.805, mode = 'analog', codec = 'adpcm' },
        },
    },
}

-- ---------------------------------------------------------------------------
-- Codeplugs: one radio personality per department.
--   tx         channels the unit may select and transmit on
--   scan       extra receive-only channels (used by the scanning phase)
--   models     radio models the unit may carry (one model ships in this phase)
--   supervisor reserved for supervisor-only functions in later phases
-- A player can also be granted a codeplug directly with the ACE
-- psradio.codeplug.<id>, which wins over the job mapping below.
-- ---------------------------------------------------------------------------
Config.codeplugs = {
    leo = {
        name = 'Law Enforcement', nac = '293',
        tx   = { 'state-disp', 'state-c2c', 'state-tac', 'state-ops',
                 'city-disp', 'city-c2c', 'city-tac',
                 'county-disp', 'county-c2c', 'county-tac' },
        scan = { 'state-fire', 'city-fire', 'county-fire' },
        models = { 'handheld', 'mobile' },
    },
    leo_command = {
        name = 'LE Command', nac = '293', supervisor = true,
        tx   = { 'state-disp', 'state-c2c', 'state-tac', 'state-ops', 'state-fire',
                 'city-disp', 'city-c2c', 'city-tac', 'city-fire',
                 'county-disp', 'county-c2c', 'county-tac', 'county-fire' },
        scan = { 'state-disp', 'state-c2c', 'state-tac', 'state-ops', 'state-fire',
                 'city-disp', 'city-c2c', 'city-tac', 'city-fire',
                 'county-disp', 'county-c2c', 'county-tac', 'county-fire'},
        models = { 'handheld', 'mobile', 'console' },
    },
    fire = {
        name = 'Fire / EMS', nac = '4F1',
        tx   = { 'state-disp', 'state-ops', 'state-fire', 'city-fire', 'city-disp', 
                 'county-disp', 'county-fire' },
        scan = { 'state-disp', 'city-disp', 'county-disp',
                 'state-ops', 'state-fire', 'city-fire', 'county-fire' },
        models = { 'handheld', 'duty' },
    },
}

-- ---------------------------------------------------------------------------
-- Job -> codeplug. Jobs that are not listed get no radio.
-- Short form:  police = 'leo'
-- With ranks:  the highest listed rank that is <= the player's grade wins.
-- ---------------------------------------------------------------------------
Config.jobs = {
    police    = { default = 'leo', ranks = { [4] = 'leo_command' } },
    sheriff   = { default = 'leo', ranks = { [4] = 'leo_command' } },
    ambulance = 'fire',
    fire      = 'fire',
}
