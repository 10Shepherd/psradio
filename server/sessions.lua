-- One session per connected player that has loaded the radio. The server's
-- copy of power / channel / codeplug is the only one that counts.
local Sessions = { bySrc = {}, members = {} }
PSR.Sessions = Sessions

local Registry, Store, Framework = PSR.Registry, PSR.Store, PSR.Framework

local function identifierOf(src)
    local id = GetPlayerIdentifierByType(tostring(src), 'license')
    if type(id) == 'string' and id ~= '' then return id end
    return nil
end

function Sessions.get(src) return Sessions.bySrc[src] end

function Sessions.create(src)
    local sec = Config.security or {}
    local identifier = identifierOf(src)
    local sess = {
        src = src,
        identifier = identifier,
        record = Store.player(identifier),
        ready = false,
        power = false,
        channelId = nil,
        memberOf = nil,
        codeplugId = nil,
        caps = { opus = false },
        control = PSR.newBucket(tonumber(sec.controlRate) or 10, tonumber(sec.controlBurst) or 30),
        txStart = PSR.newBucket(tonumber(sec.txStartRate) or 2, tonumber(sec.txStartBurst) or 4),
    }
    Sessions.bySrc[src] = sess
    return sess
end

-- Name other radios see. Never the player name or a game identifier.
function Sessions.label(sess)
    return sess.record.callsign or ('Unit ' .. sess.record.unitId)
end

-- Keeps channel membership in step with power + selected channel.
function Sessions.sync(sess)
    local want = (sess.power and sess.channelId) or nil
    if sess.memberOf == want then return end
    if sess.memberOf then
        local set = Sessions.members[sess.memberOf]
        if set then
            set[sess.src] = nil
            if next(set) == nil then Sessions.members[sess.memberOf] = nil end
        end
    end
    sess.memberOf = want
    if want then
        Sessions.members[want] = Sessions.members[want] or {}
        Sessions.members[want][sess.src] = true
    end
end

function Sessions.remove(src)
    local sess = Sessions.bySrc[src]
    if not sess then return end
    sess.power = false
    Sessions.sync(sess)
    Sessions.bySrc[src] = nil
end

-- Order: custom hook, ACE grant, framework job, standalone default.
function Sessions.resolveCodeplug(src)
    local access = Config.access or {}

    if type(access.resolve) == 'function' then
        local ok, id = pcall(access.resolve, src)
        if ok and id == false then return nil end
        if ok and id ~= nil and Registry.codeplugs[id] then return id end
    end

    for _, id in ipairs(Registry.codeplugOrder) do
        if IsPlayerAceAllowed(tostring(src), 'psradio.codeplug.' .. id) then return id end
    end

    for _, group in ipairs(Framework.getGroups(src)) do
        local id = Registry.codeplugForJob(group.name, group.grade)
        if id then return id end
    end

    if Framework.name == 'standalone' and access.standaloneCodeplug
        and Registry.codeplugs[access.standaloneCodeplug] then
        return access.standaloneCodeplug
    end
    return nil
end

function Sessions.canTransmit(sess, channelId)
    local cp = Registry.codeplugs[sess.codeplugId]
    return cp ~= nil and cp.tx[channelId] == true
end
