-- Wire protocol shared by client and server. See docs/PROTOCOL.md.
PSR = PSR or {}

-- 2: phase 2 added settings, battery, models, audio and transmit override.
PSR.PROTOCOL_VERSION = 2

PSR.Event = {
    -- client -> server (all validated and rate-limited server-side)
    svReady    = 'psradio:sv:ready',     -- (protocolVersion, caps)
    svPower    = 'psradio:sv:power',     -- (on: boolean)
    svSelect   = 'psradio:sv:select',    -- (channelId: string)
    svTxStart  = 'psradio:sv:txStart',   -- (clientSeq: integer, override: boolean)
    svTxFrame  = 'psradio:sv:txFrame',   -- (txId, seq, payloadBase64)
    svTxStop   = 'psradio:sv:txStop',    -- ()
    svSettings = 'psradio:sv:settings',  -- (partial settings table)

    -- server -> client
    clInit      = 'psradio:cl:init',      -- (payload table)
    clState     = 'psradio:cl:state',     -- (state table)
    clAccess    = 'psradio:cl:access',    -- (access view or false)
    clSettings  = 'psradio:cl:settings',  -- (full settings table, after validation)
    clBattery   = 'psradio:cl:battery',   -- (percent, charging: boolean)
    clTxGranted = 'psradio:cl:txGranted', -- (clientSeq, txId, params)
    clTxDenied  = 'psradio:cl:txDenied',  -- (clientSeq, reason, canOverride)
    clTxEnded   = 'psradio:cl:txEnded',   -- (txId, reason) server-forced stop
    clRxStart   = 'psradio:cl:rxStart',   -- (channelId, txId, label, codecId, mode)
    clRxFrame   = 'psradio:cl:rxFrame',   -- (txId, seq, payloadBase64)
    clRxStop    = 'psradio:cl:rxStop',    -- (channelId, txId, reason)
    clNotify    = 'psradio:cl:notify',    -- (localeKey, param)
}

PSR.Codec = { opus = 1, adpcm = 2 }
PSR.CodecName = { [1] = 'opus', [2] = 'adpcm' }

-- The skins the radio page can draw. A model in Config.models must pick one;
-- a model is a look and a softkey count, not different radio behaviour.
PSR.Skins = { handheld = true, mobile = true, console = true }

-- Transmit animations are not listed here: they come from
-- Config.animations.styles, each with an id and an emote command in
-- scully_emotemenu, which is what actually plays them. psradio only says when
-- to start and cancel one. A player's animStyle setting is one of those ids, or
-- 'off'.

PSR.Limits = {
    idMaxLen        = 32,   -- zone / channel / codeplug / model ids
    nameMaxLen      = 16,   -- names shown on the radio display
    callsignMaxLen  = 12,
    maxPayloadChars = 4096, -- one base64 voice packet
    maxSeqJump      = 64,   -- a frame may skip at most this many sequence numbers
    maxSettingsKeys = 16,   -- keys accepted in one sv:settings message
    maxAnimStyles   = 12,   -- animations Config.animations.styles may list
}
