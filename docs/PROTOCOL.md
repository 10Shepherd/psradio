# psradio wire protocol — version 1

Event names and limits are defined once, in `shared/protocol.lua`. All events
are FiveM net events. A client that reports a different protocol version in
`sv:ready` is not initialised.

## Client → server

Every handler takes the sender from the engine (`source`), validates each
argument, and silently drops anything invalid or over the rate limit.

| Event | Arguments | Notes |
|---|---|---|
| `psradio:sv:ready` | `version: int`, `caps: { opus: bool }` | Sent once the page has loaded. Resets the radio to "off". Answer: `cl:init` |
| `psradio:sv:power` | `on: bool` | Refused with `no_access` when the player has no codeplug |
| `psradio:sv:select` | `channelId: string` | Must be a transmit channel of the player's codeplug |
| `psradio:sv:txStart` | `clientSeq: int ≥ 0` | Answer: `cl:txGranted` or `cl:txDenied` with the same `clientSeq` |
| `psradio:sv:txFrame` | `txId: int`, `seq: int ≥ 0`, `payload: base64` | Only from the holder of `txId`; `seq` strictly increasing, jump ≤ 64; payload ≤ 4096 chars |
| `psradio:sv:txStop` | — | Releases the channel |

Rate limits (defaults, `Config.security`): control messages 10/s with a burst
of 30; PTT presses 2/s with a burst of 4; voice packets 1.5 × the nominal
packet rate + 2 per second, per transmission.

## Server → client

| Event | Arguments |
|---|---|
| `psradio:cl:init` | `{ protocol, strings, keys, voice, access, state }` |
| `psradio:cl:state` | `{ power, channelId, callsign, unitId }` — authoritative radio state |
| `psradio:cl:access` | access view, or `false` when the player has no codeplug |
| `psradio:cl:txGranted` | `clientSeq`, `txId`, `{ codec, bitrate, framesPerPacket, maxSeconds }` |
| `psradio:cl:txDenied` | `clientSeq`, `reason` |
| `psradio:cl:txEnded` | `txId`, `reason` — the server ended the talker's transmission |
| `psradio:cl:rxStart` | `channelId`, `txId`, `label`, `codecId`, `mode` |
| `psradio:cl:rxFrame` | `txId`, `seq`, `payload` |
| `psradio:cl:rxStop` | `channelId`, `txId`, `reason` |
| `psradio:cl:notify` | `localeKey`, `param` |

Access view: `{ codeplug = { id, name, nac, supervisor, models }, zones = { { id, name, channels = { { id, name, frequency, mode, tx } } } } }`.
It contains only channels the codeplug may transmit on (`tx = true`) or scan.

Reasons are locale keys: `radio_off`, `no_channel`, `tx_denied`, `tx_busy`,
`tx_rate`, `tx_timeout`, `tx_stalled`; and for `rxStop` also `released`,
`retune`, `power`, `access`, `disconnect`, `reset`, `shutdown`.

## Voice payload

`payload` is base64 of one or more records:

```
[length: uint16 big-endian][codec packet: length bytes] ...
```

Each codec packet is one 20 ms frame and is decodable on its own.

| Codec id | Packet |
|---|---|
| 1 Opus | One Opus packet as produced by WebCodecs, ≤ 1275 bytes |
| 2 ADPCM | 83 bytes: predictor (int16 big-endian), step index (0–88), 80 bytes of 4-bit codes, low nibble first; 160 samples at 8 kHz |

Receivers accept at most 8 records per payload and ignore a malformed tail.

## Server-side events for other resources

| Event | Arguments |
|---|---|
| `psradio:txStarted` | `source`, `channelId` |
| `psradio:txEnded` | `source`, `channelId`, `reason` |

These are local server events (not net events); clients cannot trigger them
on the server unless another resource registers them as net events.
