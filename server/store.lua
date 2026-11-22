--[[
    File-based persistence: data/state.json inside the resource folder.

    Schema (version 2):
      { version = 2,
        nextUnitId = <int>,
        players = { [identifier] = {
            unitId = <int>, callsign = <string?>, lastChannel = <string?>,
            settings = { <per-player settings, see server/settings.lua> },
            battery = <number 0..100> } },
        patches = {} }            -- reserved for the patching phase

    Versioning: `version` is bumped whenever the shape changes, and a function
    in `migrations[n]` upgrades a version-n table to n+1. A file written by a
    NEWER psradio is never overwritten: the store goes read-only for the session.
]]
local Store = { state = nil, dirty = false, readOnly = false }
PSR.Store = Store

local CURRENT_VERSION = 2
local FILE = 'data/state.json'

-- migrations[n](state) -> state at version n+1
Store.migrations = {}

-- 1 -> 2: phase 2 gave every player settings and a battery. Existing players
-- keep their unit id, callsign and last channel, start on the configured
-- defaults and get a full battery.
Store.migrations[1] = function(state)
    if type(state.players) == 'table' then
        for _, rec in pairs(state.players) do
            if type(rec) == 'table' then
                if type(rec.settings) ~= 'table' then rec.settings = {} end
                rec.battery = 100
            end
        end
    end
    return state
end
Store.currentVersion = CURRENT_VERSION

local function fresh()
    return { version = CURRENT_VERSION, nextUnitId = 1, players = {}, patches = {} }
end

local function sanitizeRecord(rec)
    if rec.callsign ~= nil and not PSR.isCallsign(rec.callsign) then rec.callsign = nil end
    if rec.lastChannel ~= nil and not PSR.isId(rec.lastChannel) then rec.lastChannel = nil end
    if type(rec.settings) ~= 'table' then rec.settings = {} end
    -- The settings themselves are checked per player on join, against the
    -- current config, so a setting that was dropped from config.lua disappears
    -- on its own instead of being rejected here.
    if type(rec.battery) ~= 'number' or rec.battery ~= rec.battery then
        rec.battery = 100
    else
        rec.battery = math.max(0, math.min(100, rec.battery))
    end
end

local function sanitize(state)
    if type(state.players) ~= 'table' then state.players = {} end
    if type(state.patches) ~= 'table' then state.patches = {} end
    if not PSR.isInt(state.nextUnitId, 1, 2 ^ 31) then state.nextUnitId = 1 end
    for id, rec in pairs(state.players) do
        if type(id) ~= 'string' or type(rec) ~= 'table' or not PSR.isInt(rec.unitId, 1, 2 ^ 31) then
            state.players[id] = nil
        else
            sanitizeRecord(rec)
            if rec.unitId >= state.nextUnitId then state.nextUnitId = rec.unitId + 1 end
        end
    end
    return state
end

function Store.load()
    local res = GetCurrentResourceName()
    Store.readOnly, Store.dirty = false, false

    local raw = LoadResourceFile(res, FILE)
    if not raw or raw == '' then
        Store.state = fresh()
        return 'new'
    end

    local ok, decoded = pcall(json.decode, raw)
    if not ok or type(decoded) ~= 'table' or not PSR.isInt(decoded.version, 0, 100000) then
        SaveResourceFile(res, 'data/state.corrupt.json', raw, -1)
        PSR.log('error', '%s could not be read; it was copied to data/state.corrupt.json and a new file started', FILE)
        Store.state = fresh()
        Store.dirty = true
        return 'corrupt'
    end

    if decoded.version > CURRENT_VERSION then
        PSR.log('error', '%s is version %d but this psradio understands up to %d. Nothing will be saved this session.',
            FILE, decoded.version, CURRENT_VERSION)
        Store.state = fresh()
        Store.readOnly = true
        return 'newer'
    end

    local migrated = false
    while decoded.version < CURRENT_VERSION do
        local step = Store.migrations[decoded.version]
        if not step then
            PSR.log('error', 'no migration from state version %d; starting a new file', decoded.version)
            SaveResourceFile(res, 'data/state.corrupt.json', raw, -1)
            Store.state = fresh()
            Store.dirty = true
            return 'corrupt'
        end
        local from = decoded.version
        decoded = step(decoded)
        decoded.version = from + 1
        migrated = true
    end

    Store.state = sanitize(decoded)
    if migrated then Store.dirty = true end
    return migrated and 'migrated' or 'loaded'
end

-- Writes only when something changed (or when forced).
function Store.save(force)
    if Store.readOnly or not Store.state then return false end
    if not Store.dirty and not force then return false end
    local ok = SaveResourceFile(GetCurrentResourceName(), FILE, json.encode(Store.state), -1)
    if ok then
        Store.dirty = false
    else
        PSR.log('error', 'could not write %s — does the data folder exist and is it writable?', FILE)
    end
    return ok and true or false
end

function Store.touch() Store.dirty = true end

-- Returns the saved record for a player, creating it (with a new unit id) on
-- first sight. Players without a stable identifier get a throwaway record.
function Store.player(identifier)
    local state = Store.state
    local rec = identifier and state.players[identifier]
    if rec then return rec end
    rec = { unitId = state.nextUnitId, settings = {}, battery = 100 }
    state.nextUnitId = state.nextUnitId + 1
    if identifier then state.players[identifier] = rec end
    Store.dirty = true
    return rec
end
