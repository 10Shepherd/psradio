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
    visible = false,
    pttHeld = false,
    pendingSeq = nil,    -- txStart sent, answer not yet received
    txId = nil,          -- granted transmission
    seq = 0,
    keysRegistered = false,
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

local function feed(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(message)
    EndTextCommandThefeedPostTicker(false, true)
end

-- ---------------------------------------------------------------- visibility
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
                -- look, attack, aim, melee, weapon wheel, pause menu
                for _, control in ipairs({ 1, 2, 24, 25, 37, 106, 140, 141, 142, 199, 200, 257 }) do
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

-- ---------------------------------------------------------------- transmit
local function endLocalTx()
    if state.txId then
        nui('txStop')
        state.txId = nil
    end
end

local function pttDown()
    if state.pttHeld then return end
    state.pttHeld = true
    if not state.ready or not state.access then return end
    if not state.power then
        nui('deny', { reason = 'radio_off' })
        return
    end
    if not state.channelId then
        nui('deny', { reason = 'no_channel' })
        return
    end
    state.seq = state.seq + 1
    state.pendingSeq = state.seq
    TriggerServerEvent(Ev.svTxStart, state.seq)
end

local function pttUp()
    if not state.pttHeld then return end
    state.pttHeld = false
    local hadTx = state.txId ~= nil or state.pendingSeq ~= nil
    state.pendingSeq = nil
    endLocalTx()
    if hadTx then TriggerServerEvent(Ev.svTxStop) end
end

RegisterCommand('+psradio_ptt', pttDown, false)
RegisterCommand('-psradio_ptt', pttUp, false)
RegisterCommand('psradio_toggle', toggleRadio, false)

-- ---------------------------------------------------------------- server -> client
RegisterNetEvent(Ev.clInit)
AddEventHandler(Ev.clInit, function(payload)
    if type(payload) ~= 'table' then return end
    state.strings = type(payload.strings) == 'table' and payload.strings or {}
    state.access = payload.access or false
    state.power = payload.state and payload.state.power == true
    state.channelId = payload.state and payload.state.channelId or nil
    state.pendingSeq, state.txId = nil, nil
    state.ready = true

    if not state.keysRegistered and type(payload.keys) == 'table' then
        state.keysRegistered = true
        RegisterKeyMapping('+psradio_ptt', text('key_ptt'), 'keyboard', tostring(payload.keys.ptt or 'B'))
        RegisterKeyMapping('psradio_toggle', text('key_toggle'), 'keyboard', tostring(payload.keys.toggle or 'F6'))
    end

    nui('init', { strings = state.strings, access = state.access, state = payload.state })
end)

RegisterNetEvent(Ev.clState)
AddEventHandler(Ev.clState, function(s)
    if type(s) ~= 'table' then return end
    state.power = s.power == true
    state.channelId = s.channelId
    if not state.power or not state.channelId then
        state.pendingSeq = nil
        endLocalTx()
    end
    nui('state', { state = s })
end)

RegisterNetEvent(Ev.clAccess)
AddEventHandler(Ev.clAccess, function(access)
    state.access = access or false
    nui('access', { access = state.access })
    if not state.access and state.visible then setVisible(false) end
end)

RegisterNetEvent(Ev.clTxGranted)
AddEventHandler(Ev.clTxGranted, function(clientSeq, txId, params)
    if clientSeq ~= state.pendingSeq or not state.pttHeld or type(params) ~= 'table' then
        -- The key was released before the answer arrived: give the channel back.
        if clientSeq == state.seq then TriggerServerEvent(Ev.svTxStop) end
        return
    end
    state.pendingSeq = nil
    state.txId = txId
    nui('txStart', {
        txId = txId, codec = params.codec, bitrate = params.bitrate,
        framesPerPacket = params.framesPerPacket, maxSeconds = params.maxSeconds,
    })
end)

RegisterNetEvent(Ev.clTxDenied)
AddEventHandler(Ev.clTxDenied, function(clientSeq, reason)
    if clientSeq ~= state.pendingSeq then return end
    state.pendingSeq = nil
    nui('deny', { reason = reason })
end)

RegisterNetEvent(Ev.clTxEnded)
AddEventHandler(Ev.clTxEnded, function(txId, reason)
    if txId ~= state.txId then return end
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
    if state.visible then nui('message', { text = message }) end
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
end)
