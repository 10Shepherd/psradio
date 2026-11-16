--[[
    Framework adapters. Each one answers a single question: which job/group
    names and grades does this player hold right now?

    verified = true  : written against the framework's published server API.
    verified = false : best effort — the documented API differs between
                       versions or could not be confirmed. Every call is
                       wrapped in pcall, so a mismatch means "no radio", never
                       a crash. Use Config.access.resolve if yours differs.
]]
local Framework = { name = 'standalone', verified = true }
PSR.Framework = Framework

local function jobEntry(job)
    if type(job) ~= 'table' or type(job.name) ~= 'string' then return {} end
    local grade = job.grade
    if type(grade) == 'table' then grade = grade.level end
    return { { name = job.name, grade = tonumber(grade) or 0 } }
end

local adapters = {
    {
        name = 'qbx_core', resource = 'qbx_core', verified = true,
        groups = function(src)
            local player = exports.qbx_core:GetPlayer(src)
            return jobEntry(player and player.PlayerData and player.PlayerData.job)
        end,
    },
    {
        name = 'qb-core', resource = 'qb-core', verified = true,
        groups = function(src)
            Framework.core = Framework.core or exports['qb-core']:GetCoreObject()
            local player = Framework.core.Functions.GetPlayer(src)
            return jobEntry(player and player.PlayerData and player.PlayerData.job)
        end,
    },
    {
        name = 'es_extended', resource = 'es_extended', verified = true,
        groups = function(src)
            Framework.core = Framework.core or exports['es_extended']:getSharedObject()
            local player = Framework.core.GetPlayerFromId(src)
            return jobEntry(player and player.job)
        end,
    },
    {
        -- ND_Core 2.x: player.job / player.jobInfo.rank, plus player.groups.
        name = 'ND_Core', resource = 'ND_Core', verified = false,
        groups = function(src)
            local player = exports['ND_Core']:getPlayer(src)
            if type(player) ~= 'table' then return {} end
            local out = {}
            if type(player.groups) == 'table' then
                for name, info in pairs(player.groups) do
                    if type(name) == 'string' then
                        out[#out + 1] = { name = name, grade = type(info) == 'table' and tonumber(info.rank) or 0 }
                    end
                end
            end
            if #out == 0 and type(player.job) == 'string' then
                out[1] = { name = player.job, grade = type(player.jobInfo) == 'table' and tonumber(player.jobInfo.rank) or 0 }
            end
            return out
        end,
    },
    {
        -- ox_core: groups are a name -> grade map on the player object.
        name = 'ox_core', resource = 'ox_core', verified = false,
        groups = function(src)
            local groups = exports.ox_core:CallPlayer(src, 'getGroups')
            local out = {}
            if type(groups) == 'table' then
                for name, grade in pairs(groups) do
                    if type(name) == 'string' then
                        out[#out + 1] = { name = name, grade = tonumber(grade) or 0 }
                    end
                end
            end
            return out
        end,
    },
}

function Framework.detect(wanted)
    Framework.name, Framework.verified, Framework.adapter, Framework.core = 'standalone', true, nil, nil
    if wanted == 'standalone' then return Framework.name end
    for _, a in ipairs(adapters) do
        local match = (wanted == nil or wanted == 'auto') and GetResourceState(a.resource) == 'started'
            or wanted == a.name
        if match then
            Framework.name, Framework.verified, Framework.adapter = a.name, a.verified, a
            return Framework.name
        end
    end
    if wanted ~= nil and wanted ~= 'auto' then
        PSR.log('warn', 'Config.framework = "%s" is not a known adapter; running standalone', tostring(wanted))
    end
    return Framework.name
end

-- Array of { name, grade }, sorted by name so the result is deterministic
-- when a player holds several groups.
function Framework.getGroups(src)
    if not Framework.adapter then return {} end
    local ok, groups = pcall(Framework.adapter.groups, src)
    if not ok then
        if not Framework.warned then
            Framework.warned = true
            PSR.log('warn', '%s adapter failed (%s). Players get no job-based radio until this is fixed; see Config.access.resolve.',
                Framework.name, tostring(groups))
        end
        return {}
    end
    table.sort(groups, function(a, b) return a.name < b.name end)
    return groups
end
