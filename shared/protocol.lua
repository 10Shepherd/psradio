-- Wire protocol shared by client and server. See docs/PROTOCOL.md.
PSR = PSR or {}

PSR.PROTOCOL_VERSION = 1

PSR.Event = {
    -- client -> server (all validated and rate-limited server-side)
    svReady   = 'psradio:sv:ready',    -- (protocolVersion, caps)
    svPower   = 'psradio:sv:power',    -- (on: boolean)
    svSelect  = 'psradio:sv:select',   -- (channelId: string)
    svTxStart = 'psradio:sv:txStart',  -- (clientSeq: integer)
    svTxFrame = 'psradio:sv:txFrame',  -- (txId, seq, payloadBase64)
    svTxStop  = 'psradio:sv:txStop',   -- ()

    -- server -> client
    clInit      = 'psradio:cl:init',      -- (payload table)
    clState     = 'psradio:cl:state',     -- (state table)
    clAccess    = 'psradio:cl:access',    -- (access view or false)
    clTxGranted = 'psradio:cl:txGranted', -- (clientSeq, txId, params)
    clTxDenied  = 'psradio:cl:txDenied',  -- (clientSeq, reason)
    clTxEnded   = 'psradio:cl:txEnded',   -- (txId, reason) server-forced stop
    clRxStart   = 'psradio:cl:rxStart',   -- (channelId, txId, label, codecId, mode)
    clRxFrame   = 'psradio:cl:rxFrame',   -- (txId, seq, payloadBase64)
    clRxStop    = 'psradio:cl:rxStop',    -- (channelId, txId, reason)
    clNotify    = 'psradio:cl:notify',    -- (localeKey, param)
}

PSR.Codec = { opus = 1, adpcm = 2 }
PSR.CodecName = { [1] = 'opus', [2] = 'adpcm' }

PSR.Limits = {
    idMaxLen        = 32,   -- zone / channel / codeplug ids
    nameMaxLen      = 16,   -- names shown on the radio display
    callsignMaxLen  = 12,
    maxPayloadChars = 4096, -- one base64 voice packet
    maxSeqJump      = 64,   -- a frame may skip at most this many sequence numbers
}
