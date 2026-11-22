-- Validates Config and builds the lookup tables the rest of the server uses.
-- Invalid entries are dropped with a warning instead of stopping the resource.
local Registry = {}
PSR.Registry = Registry

local L = PSR.Limits

local function isName(v)
    return type(v) == 'string' and #v >= 1 and #v <= L.nameMaxLen
end

local function clampNumber(v, min, max, default)
    if type(v) ~= 'number' or v ~= v then return default end
    return math.max(min, math.min(max, v))
end

function Registry.build(cfg)
    local warnings = {}
    local function warn(fmt, ...) warnings[#warnings + 1] = fmt:format(...) end

    Registry.zones, Registry.channels = {}, {}
    Registry.codeplugs, Registry.codeplugOrder = {}, {}
    Registry.jobs = {}
    Registry.models, Registry.modelOrder = {}, {}

    -- voice settings, clamped to safe ranges
    local v = type(cfg.voice) == 'table' and cfg.voice or {}
    local defaultCodec = PSR.Codec[v.defaultCodec] and v.defaultCodec or 'opus'
    Registry.voice = {
        defaultCodec     = defaultCodec,
        opusBitrate      = math.floor(clampNumber(v.opusBitrate, 6000, 64000, 16000)),
        framesPerPacket  = math.floor(clampNumber(v.framesPerPacket, 1, 6, 3)),
        txTimeoutSeconds = clampNumber(v.txTimeoutSeconds, 5, 600, 60),
        txStallSeconds   = clampNumber(v.txStallSeconds, 1, 30, 3),
        allowOverride    = v.allowOverride ~= false,
        overrideWindowMs = math.floor(clampNumber(v.overrideWindowSeconds, 1, 30, 3) * 1000),
    }

    -- receive audio chain (the page builds its filters from these)
    local a = type(cfg.audio) == 'table' and cfg.audio or {}
    local function band(src, defHigh, defLow)
        src = type(src) == 'table' and src or {}
        local high = clampNumber(src.high, 50, 2000, defHigh)
        local low = clampNumber(src.low, 1000, 8000, defLow)
        if low <= high then
            warn('audio: low must be above high; using %d-%d Hz', defHigh, defLow)
            high, low = defHigh, defLow
        end
        return high, low, src
    end
    local dHigh, dLow, dSrc = band(a.digital, 250, 3400)
    local aHigh, aLow, aSrc = band(a.analog, 380, 2400)
    Registry.audio = {
        digital = {
            high = dHigh, low = dLow,
            drive = 1, makeup = 1,
            noise = clampNumber(dSrc.noise, 0, 0.5, 0),
            tailMs = 0,
        },
        analog = {
            high = aHigh, low = aLow,
            drive = clampNumber(aSrc.drive, 1, 4, 1.6),
            makeup = clampNumber(aSrc.makeup, 0.2, 1, 0.8),
            noise = clampNumber(aSrc.noise, 0, 0.5, 0.06),
            tailMs = math.floor(clampNumber(aSrc.tailMs, 0, 500, 110)),
        },
        rogerBeep = a.rogerBeep ~= false,
        toneVolume = clampNumber(a.toneVolume, 0, 1, 0.25),
    }

    -- battery
    local b = type(cfg.battery) == 'table' and cfg.battery or {}
    local warnLevels = {}
    for _, level in ipairs(type(b.warnAtPercent) == 'table' and b.warnAtPercent or { 25, 10, 5 }) do
        if PSR.isInt(level, 1, 99) then warnLevels[#warnLevels + 1] = level end
    end
    table.sort(warnLevels, function(x, y) return x > y end)   -- highest first
    Registry.battery = {
        enabled         = b.enabled == true,
        capacityMinutes = clampNumber(b.capacityMinutes, 1, 10080, 480),
        txMultiplier    = clampNumber(b.txMultiplier, 1, 50, 6),
        chargeMinutes   = clampNumber(b.chargeMinutes, 1, 10080, 90),
        warnAtPercent   = warnLevels,
    }

    -- animations
    -- The animations themselves live in scully_emotemenu; what is validated
    -- here is the list of styles and the emote command each one plays. Order is
    -- kept, because it is the order the tick boxes appear in.
    local an = type(cfg.animations) == 'table' and cfg.animations or {}
    local function emoteName(value)
        if type(value) ~= 'string' then return nil end
        local clean = value:gsub('^%s+', ''):gsub('%s+$', '')
        if clean == '' or #clean > 64 then return nil end
        return clean
    end

    local styles, byId = {}, {}
    for index, src in ipairs(type(an.styles) == 'table' and an.styles or {}) do
        local id = type(src) == 'table' and src.id or nil
        if type(src) ~= 'table' or not PSR.isId(id) then
            warn('animations: style #%d skipped: needs an id of letters, digits, - or _', index)
        elseif byId[id] then
            warn('animations: style %s skipped: duplicate id', id)
        elseif #styles >= L.maxAnimStyles then
            warn('animations: style %s skipped: no more than %d animations', id, L.maxAnimStyles)
        elseif not emoteName(src.emote) then
            warn('animations: style %s skipped: emote must be an emote command of 1-64 characters', id)
        else
            local style = {
                id        = id,
                emote     = emoteName(src.emote),
                aiming    = emoteName(src.aiming),
                inVehicle = emoteName(src.inVehicle),
                label     = type(src.label) == 'string' and src.label ~= ''
                    and src.label:sub(1, L.nameMaxLen) or nil,
            }
            styles[#styles + 1] = style
            byId[id] = style
        end
    end
    if an.styles ~= nil and type(an.styles) ~= 'table' then
        warn('animations: styles must be a list of animations')
    end

    -- Vehicle classes that get no animation at all.
    local blockedClasses = {}
    for _, class in ipairs(type(an.blockedClasses) == 'table' and an.blockedClasses or {}) do
        if PSR.isInt(class, 0, 22) then
            blockedClasses[#blockedClasses + 1] = class
        else
            warn('animations: blockedClasses entry "%s" is not a vehicle class 0-22', tostring(class))
        end
    end

    Registry.animations = {
        enabled        = an.enabled ~= false,
        styles         = styles,
        byId           = byId,
        blockedClasses = blockedClasses,
    }

    -- radio models (built before codeplugs, which name them)
    for id, m in pairs(type(cfg.models) == 'table' and cfg.models or {}) do
        if not PSR.isId(id) or type(m) ~= 'table' then
            warn('model "%s" skipped: invalid id or definition', tostring(id))
        elseif m.skin ~= nil and not PSR.Skins[m.skin] then
            warn('model %s skipped: skin "%s" is not one of handheld, mobile, console',
                id, tostring(m.skin))
        else
            Registry.models[id] = {
                id = id,
                name = isName(m.name) and m.name or id:sub(1, L.nameMaxLen),
                skin = m.skin or 'handheld',
                softkeys = PSR.isInt(m.softkeys, 3, 4) and m.softkeys or 3,
            }
            Registry.modelOrder[#Registry.modelOrder + 1] = id
        end
    end
    table.sort(Registry.modelOrder)
    if #Registry.modelOrder == 0 then
        warn('no usable models configured; falling back to one built-in handheld')
        Registry.models.handheld = { id = 'handheld', name = 'Portable', skin = 'handheld', softkeys = 3 }
        Registry.modelOrder[1] = 'handheld'
    end

    -- per-player setting defaults
    local defaults, settingWarnings = PSR.Settings.buildDefaults(cfg.settings)
    for _, w in ipairs(settingWarnings) do warnings[#warnings + 1] = w end
    Registry.defaultSettings = defaults

    -- zones and channels
    local zoneIds = {}
    for zi, z in ipairs(type(cfg.zones) == 'table' and cfg.zones or {}) do
        if type(z) ~= 'table' or not PSR.isId(z.id) or not isName(z.name) or zoneIds[z.id] then
            warn('zone #%d skipped: needs a unique id and a name of 1-%d characters', zi, L.nameMaxLen)
        else
            zoneIds[z.id] = true
            local zone = { id = z.id, name = z.name, channels = {} }
            for ci, c in ipairs(type(z.channels) == 'table' and z.channels or {}) do
                local ctype = type(c) == 'table' and (c.type or 'conventional')
                if type(c) ~= 'table' or not PSR.isId(c.id) or not isName(c.name) then
                    warn('zone %s channel #%d skipped: needs an id and a name of 1-%d characters', z.id, ci, L.nameMaxLen)
                elseif Registry.channels[c.id] then
                    warn('channel %s skipped: duplicate id', c.id)
                elseif ctype ~= 'conventional' then
                    warn('channel %s skipped: type "%s" is not implemented yet', c.id, tostring(ctype))
                elseif c.mode ~= nil and c.mode ~= 'digital' and c.mode ~= 'analog' then
                    warn('channel %s skipped: mode must be "digital" or "analog"', c.id)
                elseif c.codec ~= nil and not PSR.Codec[c.codec] then
                    warn('channel %s skipped: unknown codec "%s"', c.id, tostring(c.codec))
                else
                    local channel = {
                        id = c.id, name = c.name, zoneId = z.id, type = 'conventional',
                        frequency = type(c.frequency) == 'number' and c.frequency or 0,
                        mode = c.mode or 'digital',
                        codec = c.codec or defaultCodec,
                    }
                    Registry.channels[c.id] = channel
                    zone.channels[#zone.channels + 1] = channel
                end
            end
            Registry.zones[#Registry.zones + 1] = zone
        end
    end

    -- codeplugs
    local function channelSet(list, cpId, field)
        local set = {}
        for _, id in ipairs(type(list) == 'table' and list or {}) do
            if Registry.channels[id] then
                set[id] = true
            else
                warn('codeplug %s: %s channel "%s" does not exist', cpId, field, tostring(id))
            end
        end
        return set
    end

    for id, cp in pairs(type(cfg.codeplugs) == 'table' and cfg.codeplugs or {}) do
        if not PSR.isId(id) or type(cp) ~= 'table' then
            warn('codeplug "%s" skipped: invalid id or definition', tostring(id))
        else
            local models = {}
            for _, m in ipairs(type(cp.models) == 'table' and cp.models or {}) do
                if Registry.models[m] then
                    models[#models + 1] = m
                else
                    warn('codeplug %s: model "%s" is not in Config.models', id, tostring(m))
                end
            end
            if #models == 0 then models[1] = Registry.modelOrder[1] end
            Registry.codeplugs[id] = {
                id = id,
                name = type(cp.name) == 'string' and cp.name:sub(1, 32) or id,
                nac = type(cp.nac) == 'string' and cp.nac:sub(1, 8) or '',
                supervisor = cp.supervisor == true,
                tx = channelSet(cp.tx, id, 'tx'),
                scan = channelSet(cp.scan, id, 'scan'),
                models = models,
            }
            Registry.codeplugOrder[#Registry.codeplugOrder + 1] = id
        end
    end
    table.sort(Registry.codeplugOrder)

    -- job map
    for job, rule in pairs(type(cfg.jobs) == 'table' and cfg.jobs or {}) do
        local entry
        if type(rule) == 'string' then
            entry = { default = rule, ranks = {} }
        elseif type(rule) == 'table' then
            entry = { default = rule.default, ranks = {} }
            for rank, cpId in pairs(type(rule.ranks) == 'table' and rule.ranks or {}) do
                if type(rank) == 'number' and Registry.codeplugs[cpId] then
                    entry.ranks[#entry.ranks + 1] = { rank = rank, codeplug = cpId }
                else
                    warn('job %s: rank rule %s -> %s ignored', tostring(job), tostring(rank), tostring(cpId))
                end
            end
            table.sort(entry.ranks, function(a, b) return a.rank > b.rank end)
        end
        if type(job) ~= 'string' or not entry
            or (entry.default ~= nil and not Registry.codeplugs[entry.default])
            or (entry.default == nil and #entry.ranks == 0) then
            warn('job "%s" skipped: it does not point at an existing codeplug', tostring(job))
        else
            Registry.jobs[job] = entry
        end
    end

    return warnings
end

-- Codeplug id for a job name and grade, or nil when the job is unmapped.
function Registry.codeplugForJob(job, grade)
    local entry = Registry.jobs[job]
    if not entry then return nil end
    grade = tonumber(grade) or 0
    for _, r in ipairs(entry.ranks) do     -- sorted highest rank first
        if grade >= r.rank then return r.codeplug end
    end
    return entry.default
end

-- What a client is allowed to know: only its own codeplug's channels.
function Registry.accessView(codeplugId)
    local cp = Registry.codeplugs[codeplugId]
    if not cp then return nil end
    local zones = {}
    for _, zone in ipairs(Registry.zones) do
        local channels = {}
        for _, ch in ipairs(zone.channels) do
            if cp.tx[ch.id] or cp.scan[ch.id] then
                channels[#channels + 1] = {
                    id = ch.id, name = ch.name, frequency = ch.frequency,
                    mode = ch.mode, tx = cp.tx[ch.id] == true,
                }
            end
        end
        if #channels > 0 then
            zones[#zones + 1] = { id = zone.id, name = zone.name, channels = channels }
        end
    end
    local models = {}
    for _, id in ipairs(cp.models) do
        local m = Registry.models[id]
        if m then
            models[#models + 1] = { id = m.id, name = m.name, skin = m.skin, softkeys = m.softkeys }
        end
    end
    return {
        codeplug = { id = cp.id, name = cp.name, nac = cp.nac, supervisor = cp.supervisor, models = models },
        zones = zones,
    }
end
