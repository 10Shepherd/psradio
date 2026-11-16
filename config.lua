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
        scan = { 'city-fire', 'county-fire' },
        models = { 'handheld' },
    },
    leo_command = {
        name = 'LE Command', nac = '293', supervisor = true,
        tx   = { 'state-disp', 'state-c2c', 'state-tac', 'state-ops',
                 'city-disp', 'city-c2c', 'city-tac', 'city-fire',
                 'county-disp', 'county-c2c', 'county-tac', 'county-fire' },
        models = { 'handheld' },
    },
    fire = {
        name = 'Fire / EMS', nac = '4F1',
        tx   = { 'state-disp', 'state-ops', 'city-fire', 'county-fire' },
        scan = { 'city-disp', 'county-disp' },
        models = { 'handheld' },
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
