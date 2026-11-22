--[[
    Per-player settings: what each player changed in the radio's own menu.

    Settings live on the server and are saved against the player's licence, so
    they follow the player to another machine. The client never decides a
    setting: it asks, the server validates and answers with the whole set.

    Adding a setting means one entry in SPEC and nothing else here.
]]
local Settings = {}
PSR.Settings = Settings

local function intSetting(min, max)
    return function(value)
        if type(value) ~= 'number' or value ~= value then return nil end
        return math.floor(math.max(min, math.min(max, value)))
    end
end

local function boolSetting()
    return function(value)
        if type(value) ~= 'boolean' then return nil end
        return value
    end
end

-- 'off', or the id of an animation Config.animations.styles defines. The list
-- is config, not protocol, so it is read from the registry as it is validated.
local function animStyleSetting()
    return function(value)
        if value == 'off' then return 'off' end
        if not PSR.isId(value) then return nil end
        local animations = PSR.Registry and PSR.Registry.animations
        if animations and not animations.byId[value] then return nil end
        return value
    end
end

local function enumSetting(allowed)
    return function(value)
        if type(value) ~= 'string' or not allowed[value] then return nil end
        return value
    end
end

-- Each validator returns the value to store, or nil to reject it outright.
Settings.SPEC = {
    volume     = intSetting(0, 100),
    toneVolume = intSetting(0, 100),
    fx         = enumSetting({ full = true, light = true, off = true }),
    rogerBeep  = boolSetting(),
    -- Which transmit animation plays: a style id, or 'off' for none.
    animStyle  = animStyleSetting(),
    pttMode    = enumSetting({ hold = true, toggle = true }),
    -- A model id. It must exist and the player's codeplug must allow it, which
    -- depends on the player, so that check happens in Settings.apply.
    model      = function(value)
        if value == nil then return nil end
        if not PSR.isId(value) then return nil end
        return value
    end,
}

-- Hard fallbacks, used when Config.settings says nothing usable.
Settings.FALLBACK = {
    volume = 80, toneVolume = 25, fx = 'full',
    rogerBeep = true, animStyle = 'shoulder', pttMode = 'hold',
}

-- Validates Config.settings into the defaults every player starts from.
-- Returns the defaults and a list of warnings.
function Settings.buildDefaults(cfg)
    local warnings = {}
    local defaults = {}
    for key, fallback in pairs(Settings.FALLBACK) do defaults[key] = fallback end

    -- The animations are config, not a fixed list, so the default animation has
    -- to be one of them: the first one listed, or 'off' when there are none.
    -- Config.settings.animStyle is read over the top of this below.
    local animations = PSR.Registry and PSR.Registry.animations
    if animations then
        local first = animations.styles[1]
        defaults.animStyle = first and first.id or 'off'
    end

    for key, value in pairs(type(cfg) == 'table' and cfg or {}) do
        local check = Settings.SPEC[key]
        if not check then
            warnings[#warnings + 1] = ('settings: unknown setting "%s" ignored'):format(tostring(key))
        else
            local clean = check(value)
            if clean == nil then
                warnings[#warnings + 1] = ('settings: %s = %s is not a valid value; using %s')
                    :format(key, tostring(value), tostring(defaults[key]))
            else
                defaults[key] = clean
            end
        end
    end
    -- A default model is only a hint; whether a player may carry it is checked
    -- per player, because it depends on their codeplug.
    if type(cfg) == 'table' and cfg.model ~= nil and defaults.model == nil then
        warnings[#warnings + 1] = 'settings: model must be a model id or nil'
    end
    return defaults, warnings
end

-- The model a player actually gets: their choice if their codeplug allows it,
-- otherwise the one they already had, otherwise the codeplug's first model.
-- Asking for something they may not carry is a no-op, not a reset.
function Settings.resolveModel(chosen, codeplugId, current)
    local Registry = PSR.Registry
    local cp = Registry.codeplugs[codeplugId]
    if not cp then return nil end
    local allowed = {}
    for _, id in ipairs(cp.models) do
        if Registry.models[id] then allowed[#allowed + 1] = id end
    end
    for _, id in ipairs(allowed) do
        if id == chosen then return id end
    end
    for _, id in ipairs(allowed) do
        if id == current then return id end
    end
    return allowed[1]
end

-- Merges a partial, untrusted table over a player's saved settings. Unknown
-- keys and bad values are dropped silently; the caller sends the result back so
-- the radio always shows what the server stored. Returns the full set and
-- whether anything changed.
function Settings.apply(saved, partial)
    local changed = false
    local out = {}
    for key, value in pairs(saved) do out[key] = value end

    if type(partial) == 'table' then
        local seen = 0
        for key, value in pairs(partial) do
            seen = seen + 1
            if seen > PSR.Limits.maxSettingsKeys then break end
            local check = Settings.SPEC[key]
            if check then
                local clean = check(value)
                if clean ~= nil and out[key] ~= clean then
                    out[key] = clean
                    changed = true
                end
            end
        end
    end
    return out, changed
end

-- Fills in anything missing or no longer valid in a loaded record.
function Settings.normalize(saved, defaults)
    local out = {}
    for key, value in pairs(defaults) do out[key] = value end
    if type(saved) == 'table' then
        for key, value in pairs(saved) do
            local check = Settings.SPEC[key]
            if check then
                local clean = check(value)
                if clean ~= nil then out[key] = clean end
            end
        end
        -- Records written before animations became a choice carry the old
        -- on/off boolean. Someone who switched them off keeps them off; anyone
        -- else gets the configured default animation.
        if saved.animStyle == nil and saved.animations == false then
            out.animStyle = 'off'
        end
    end
    return out
end
