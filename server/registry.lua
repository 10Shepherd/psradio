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

    -- voice settings, clamped to safe ranges
    local v = type(cfg.voice) == 'table' and cfg.voice or {}
    local defaultCodec = PSR.Codec[v.defaultCodec] and v.defaultCodec or 'opus'
    Registry.voice = {
        defaultCodec     = defaultCodec,
        opusBitrate      = math.floor(clampNumber(v.opusBitrate, 6000, 64000, 16000)),
        framesPerPacket  = math.floor(clampNumber(v.framesPerPacket, 1, 6, 3)),
        txTimeoutSeconds = clampNumber(v.txTimeoutSeconds, 5, 600, 60),
        txStallSeconds   = clampNumber(v.txStallSeconds, 1, 30, 3),
    }

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
                if PSR.isId(m) then models[#models + 1] = m end
            end
            if #models == 0 then models[1] = 'handheld' end
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
    return {
        codeplug = { id = cp.id, name = cp.name, nac = cp.nac, supervisor = cp.supervisor, models = cp.models },
        zones = zones,
    }
end
