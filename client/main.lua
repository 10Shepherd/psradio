--[[
    Client side: key bindings, focus handling, and a relay between the server
    and the NUI page (which owns the display, the microphone and playback).

    The client holds no authority. Every action is a request; the server's
    answer is what gets shown.
]]
local Ev = PSR.Event

local state = {
    nuiCaps = nil,       -- set when the NUI page has loaded
    ready = false,       -- init received from the server
    strings = {},
    access = false,
    power = false,
    channelId = nil,
    visible = false,     -- the radio itself; the settings menu is ox_lib's
    animInfo = nil,      -- what the settings menu may offer for animations
    wantTx = false,      -- key held, or latched on in toggle mode
    pendingSeq = nil,    -- txStart sent, answer not yet received
    txId = nil,          -- granted transmission
    seq = 0,
    keysRegistered = false,
    suggested = false,   -- /radiosetting added to the chat suggestions
    settings = {},       -- the player's own settings, as the server stored them
    overrideOfferedAt = nil,   -- the server said a second press would override
    overrideWindowMs = 3000,
}

local function nui(kind, data)
    data = data or {}
    data.type = kind
    SendNUIMessage(data)
end

local function text(key, param)
    local s = state.strings[key] or key
    if param ~= nil then s = s:gsub('{1}', function() return tostring(param) end) end
    return s
end

-- The animations the settings menu offers one tick box each, in the order the
-- config lists them, with the name to put on the box: the config's own label
-- first, then the locale's name for that id, and the id itself as a last
-- resort, so an animation someone invents is still readable.
local function animInfo(cfg)
    if type(cfg) ~= 'table' then return { enabled = false, styles = {} } end
    local styles = {}
    for _, style in ipairs(type(cfg.styles) == 'table' and cfg.styles or {}) do
        if type(style) == 'table' and type(style.id) == 'string' then
            styles[#styles + 1] = {
                id = style.id,
                label = style.label or state.strings['set_anim_' .. style.id] or style.id,
            }
        end
    end
    return { enabled = cfg.enabled == true, styles = styles }
end

-- The radio models this player's codeplug allows, for the settings menu.
local function models()
    local access = state.access
    return type(access) == 'table' and type(access.codeplug) == 'table'
        and access.codeplug.models or {}
end

local function refreshMenu()
    PSR.SettingsMenu.setData(state.settings, models(), state.animInfo)
end

local function feed(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

-- ---------------------------------------------------------------- visibility
-- look, attack, aim, melee, weapon wheel, pause menu
local BLOCKED_CONTROLS = { 1, 2, 24, 25, 37, 106, 140, 141, 142, 199, 200, 257 }

local function setVisible(visible)
    if state.visible == visible then return end
    state.visible = visible
    SetNuiFocus(visible, visible)
    -- Keep game input so the PTT key binding still fires while the radio is open.
    SetNuiFocusKeepInput(visible)
    nui('visible', { visible = visible })
    if visible then
        CreateThread(function()
            while state.visible do
                for _, control in ipairs(BLOCKED_CONTROLS) do
                    DisableControlAction(0, control, true)
                end
                Wait(0)
            end
        end)
    end
end

local function toggleRadio()
    if not state.ready then return end
    if not state.visible and not state.access then
        feed(text('no_access'))
        return
    end
    setVisible(not state.visible)
end

-- /radiosetting: the settings live in an ox_lib menu, not on the radio.
local function toggleSettings()
    if not state.ready then return end
    if not PSR.SettingsMenu.isOpen() and not state.access then
        feed(text('no_access'))
        return
    end
    refreshMenu()
    if not PSR.SettingsMenu.toggle() then feed(text('no_ox_lib')) end
end

-- ---------------------------------------------------------------- transmit
local function endLocalTx()
    if state.txId then
        nui('txStop')
        state.txId = nil
    end
    PSR.Anim.setTransmitting(false)
end

-- Asks the server for the channel. The override flag is only ever set after
-- the server has offered one, and is good for a single press.
local function requestTx()
    if not state.ready or not state.access then return end
    if not state.power then
        nui('deny', { reason = 'radio_off' })
        state.wantTx = false
        return
    end
    if not state.channelId then
        nui('deny', { reason = 'no_channel' })
        state.wantTx = false
        return
    end
    local override = false
    if state.overrideOfferedAt
        and (GetGameTimer() - state.overrideOfferedAt) <= state.overrideWindowMs then
        override = true
    end
    state.overrideOfferedAt = nil
    state.lastOverride = override
    state.seq = state.seq + 1
    state.pendingSeq = state.seq
    TriggerServerEvent(Ev.svTxStart, state.seq, override)
end

local function releaseTx()
    local hadTx = state.txId ~= nil or state.pendingSeq ~= nil
    state.wantTx = false
    state.pendingSeq = nil
    endLocalTx()
    if hadTx then TriggerServerEvent(Ev.svTxStop) end
end

local function toggleMode()
    return state.settings.pttMode == 'toggle'
end

local function pttDown()
    if toggleMode() then
        -- one press starts, the next one stops
        if state.wantTx then releaseTx() else state.wantTx = true requestTx() end
        return
    end
    if state.wantTx then return end
    state.wantTx = true
    requestTx()
end

local function pttUp()
    if toggleMode() then return end     -- latched: the release means nothing
    if not state.wantTx then return end
    releaseTx()
end

RegisterCommand('+psradio_ptt', pttDown, false)
RegisterCommand('-psradio_ptt', pttUp, false)
RegisterCommand('psradio_toggle', toggleRadio, false)
RegisterCommand('radiosetting', toggleSettings, false)

-- ---------------------------------------------------------------- server -> client
RegisterNetEvent(Ev.clInit)
AddEventHandler(Ev.clInit, function(payload)
    if type(payload) ~= 'table' then return end
    state.strings = type(payload.strings) == 'table' and payload.strings or {}
    state.access = payload.access or false
    state.power = payload.state and payload.state.power == true
    state.channelId = payload.state and payload.state.channelId or nil
    state.pendingSeq, state.txId = nil, nil
    state.wantTx = false
    state.overrideOfferedAt = nil
    state.settings = type(payload.settings) == 'table' and payload.settings or {}
    if type(payload.voice) == 'table' and tonumber(payload.voice.overrideWindowSeconds) then
        state.overrideWindowMs = math.floor(tonumber(payload.voice.overrideWindowSeconds) * 1000)
    end
    PSR.Anim.configure(payload.animations)
    PSR.Anim.setStyle(state.settings.animStyle)
    state.animInfo = animInfo(payload.animations)
    PSR.SettingsMenu.text = text
    PSR.SettingsMenu.onChange = function(partial)
        if state.ready then TriggerServerEvent(Ev.svSettings, partial) end
    end
    refreshMenu()
    state.ready = true

    if not state.keysRegistered and type(payload.keys) == 'table' then
        state.keysRegistered = true
        RegisterKeyMapping('+psradio_ptt', text('key_ptt'), 'keyboard', tostring(payload.keys.ptt or 'B'))
        RegisterKeyMapping('psradio_toggle', text('key_toggle'), 'keyboard', tostring(payload.keys.toggle or 'F6'))
    end
    if not state.suggested then
        state.suggested = true
        TriggerEvent('chat:addSuggestion', '/radiosetting', text('cmd_radiosetting'))
    end

    nui('init', {
        strings = state.strings,
        access = state.access,
        state = payload.state,
        settings = state.settings,
        audio = payload.audio,
        battery = payload.battery,
        voice = payload.voice,
    })
end)

RegisterNetEvent(Ev.clSettings)
AddEventHandler(Ev.clSettings, function(settings)
    if type(settings) ~= 'table' then return end
    state.settings = settings
    PSR.Anim.setStyle(settings.animStyle)
    refreshMenu()
    if not toggleMode() and state.wantTx and state.txId == nil and state.pendingSeq == nil then
        state.wantTx = false
    end
    nui('settings', { settings = settings })
end)

RegisterNetEvent(Ev.clBattery)
AddEventHandler(Ev.clBattery, function(percent, charging)
    if type(percent) ~= 'number' then return end
    nui('battery', { percent = percent, charging = charging == true })
end)

RegisterNetEvent(Ev.clState)
AddEventHandler(Ev.clState, function(s)
    if type(s) ~= 'table' then return end
    state.power = s.power == true
    -- a pending override offer belongs to the channel that made it
    if s.channelId ~= state.channelId then state.overrideOfferedAt = nil end
    state.channelId = s.channelId
    if not state.power or not state.channelId then
        state.pendingSeq = nil
        state.wantTx = false
        endLocalTx()
    end
    nui('state', { state = s })
end)

RegisterNetEvent(Ev.clAccess)
AddEventHandler(Ev.clAccess, function(access)
    state.access = access or false
    nui('access', { access = state.access })
    refreshMenu()
    if not state.access then
        if state.visible then setVisible(false) end
        PSR.SettingsMenu.close()
    end
end)

RegisterNetEvent(Ev.clTxGranted)
AddEventHandler(Ev.clTxGranted, function(clientSeq, txId, params)
    if clientSeq ~= state.pendingSeq or not state.wantTx or type(params) ~= 'table' then
        -- The key was released before the answer arrived: give the channel back.
        if clientSeq == state.seq then TriggerServerEvent(Ev.svTxStop) end
        return
    end
    state.pendingSeq = nil
    state.txId = txId
    PSR.Anim.setTransmitting(true)
    nui('txStart', {
        txId = txId, codec = params.codec, bitrate = params.bitrate,
        framesPerPacket = params.framesPerPacket, maxSeconds = params.maxSeconds,
        override = state.lastOverride == true,
    })
end)

RegisterNetEvent(Ev.clTxDenied)
AddEventHandler(Ev.clTxDenied, function(clientSeq, reason, canOverride)
    if clientSeq ~= state.pendingSeq then return end
    state.pendingSeq = nil
    state.wantTx = false
    if canOverride == true then
        state.overrideOfferedAt = GetGameTimer()
    else
        state.overrideOfferedAt = nil
    end
    nui('deny', { reason = reason, canOverride = canOverride == true })
end)

RegisterNetEvent(Ev.clTxEnded)
AddEventHandler(Ev.clTxEnded, function(txId, reason)
    if txId ~= state.txId then return end
    state.wantTx = false
    endLocalTx()
    nui('deny', { reason = reason })
end)

RegisterNetEvent(Ev.clRxStart)
AddEventHandler(Ev.clRxStart, function(channelId, txId, label, codecId, mode)
    nui('rxStart', { channelId = channelId, txId = txId, label = label, codec = codecId, mode = mode })
end)

RegisterNetEvent(Ev.clRxFrame)
AddEventHandler(Ev.clRxFrame, function(txId, seq, payload)
    nui('rxFrame', { txId = txId, seq = seq, data = payload })
end)

RegisterNetEvent(Ev.clRxStop)
AddEventHandler(Ev.clRxStop, function(channelId, txId, reason)
    nui('rxStop', { channelId = channelId, txId = txId, reason = reason })
end)

RegisterNetEvent(Ev.clNotify)
AddEventHandler(Ev.clNotify, function(key, param)
    if type(key) ~= 'string' then return end
    local message = text(key, param)
    -- Always sent to the page, hidden or not: it owns the tones.
    nui('message', { text = message, key = key })
    feed(message)
end)

-- ---------------------------------------------------------------- NUI -> client
RegisterNUICallback('ready', function(data, cb)
    state.nuiCaps = { opus = type(data) == 'table' and data.opus == true }
    cb({})
end)

RegisterNUICallback('power', function(data, cb)
    if state.ready then TriggerServerEvent(Ev.svPower, data.on == true) end
    cb({})
end)

RegisterNUICallback('select', function(data, cb)
    if state.ready and type(data.channelId) == 'string' then
        TriggerServerEvent(Ev.svSelect, data.channelId)
    end
    cb({})
end)

-- A partial table from the settings dialog. The server validates it and
-- answers with the whole set, so nothing is applied locally first.
RegisterNUICallback('settings', function(data, cb)
    if state.ready and type(data) == 'table' and type(data.settings) == 'table' then
        TriggerServerEvent(Ev.svSettings, data.settings)
    end
    cb({})
end)

RegisterNUICallback('close', function(_, cb)
    setVisible(false)
    cb({})
end)

RegisterNUICallback('pttDown', function(_, cb) pttDown() cb({}) end)
RegisterNUICallback('pttUp', function(_, cb) pttUp() cb({}) end)

-- One encoded voice packet from the page. Dropped unless we hold a grant.
RegisterNUICallback('txFrame', function(data, cb)
    if state.txId and data.txId == state.txId and type(data.data) == 'string' and type(data.seq) == 'number' then
        TriggerServerEvent(Ev.svTxFrame, state.txId, data.seq, data.data)
    end
    cb({})
end)

RegisterNUICallback('micError', function(_, cb)
    if state.txId or state.pendingSeq then
        state.pendingSeq = nil
        state.wantTx = false
        endLocalTx()
        TriggerServerEvent(Ev.svTxStop)
    end
    cb({})
end)

-- ---------------------------------------------------------------- lifecycle
-- Announce ourselves once both the page and the network session are up.
CreateThread(function()
    while not state.nuiCaps or not NetworkIsSessionStarted() do Wait(250) end
    TriggerServerEvent(Ev.svReady, PSR.PROTOCOL_VERSION, state.nuiCaps)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if state.visible then
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
    end
    PSR.SettingsMenu.close()
    PSR.Anim.setTransmitting(false)
end)
