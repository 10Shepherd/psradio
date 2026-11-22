# psradio — architecture and plan

psradio is an original public-safety radio for FiveM. It was written from a
feature brief; it contains no third-party code, artwork, sounds or branding, and
claims no compatibility with any proprietary radio protocol. Two open-source
resources do work it does not duplicate: ox_lib draws the settings menu, and
scully_emotemenu plays the transmit animations.

This document covers the design that every phase builds on. What is built
today is listed in [STATUS.md](STATUS.md).

## 1. Architecture in one page

```text
 Player's game                                   FiveM server
┌──────────────────────────────────────┐        ┌───────────────────────────────┐
│ NUI page (web/)                      │        │ server/*.lua                  │
│  display, buttons, tones             │        │  registry   config -> tables  │
│  microphone -> codec -> packets ─────┼─┐      │  framework  job lookup        │
│  packets -> codec -> filters -> ears │ │      │  sessions   power / channel   │
└───────────────▲──────────────────────┘ │      │  voice      grant + relay     │
   SendNUIMessage│      │ NUI callbacks   │      │  store      data/state.json   │
┌───────────────┴──────▼───────────────┐ │      └───────────────▲───────────────┘
│ client/main.lua                      │ │  net events          │
│  key bindings, focus, relay only     ├─┴──────────────────────┘
└──────────────────────────────────────┘   psradio:sv:* up, psradio:cl:* down
```

- **Server is the authority.** Power, channel, codeplug and "who is talking"
  live on the server. A client only asks; the display shows the answer.
- **The NUI page owns audio.** It captures the microphone, encodes, decodes and
  plays. The Lua client relays packets and never inspects them.
- **The server never decodes voice.** It checks who sent a packet, that it is
  well-formed and within rate, and forwards it to the channel's members.
- **Proximity voice is untouched.** psradio does not call Mumble or pma-voice
  natives, so either can run alongside it. A player talking on the radio is
  still heard by people standing next to them through proximity voice.

### Data flow: one transmission

1. Player holds PTT. `client/main.lua` sends `sv:txStart(seq)`.
2. Server checks power, channel, codeplug, PTT rate and whether the channel is
   free, then answers `cl:txGranted(seq, txId, params)` or `cl:txDenied(seq, reason)`.
   Listeners get `cl:rxStart`.
3. The page opens the microphone (first use prompts the player), encodes 20 ms
   frames and posts a packet every `framesPerPacket` frames.
4. Client forwards each packet as `sv:txFrame(txId, seq, base64)`.
5. Server validates and sends `cl:rxFrame` to every other powered-on member of
   the channel. Their pages decode and play it through the channel's filter chain.
6. Key released: `sv:txStop`; listeners get `cl:rxStop`. The server also ends a
   transmission on time-out, stall, retune, power-off, access loss or disconnect.

Full message list: [PROTOCOL.md](PROTOCOL.md).

## 2. Directory tree

```text
psradio/
├─ fxmanifest.lua          resource manifest (load order lives here)
├─ config.lua              THE configuration file (server-only)
├─ README.md               install, permissions, controls, exports
├─ shared/
│  ├─ protocol.lua         event names, codec ids, limits
│  └─ util.lua             validators, logger
├─ server/
│  ├─ ratelimit.lua        token bucket
│  ├─ settings.lua         per-player settings: spec, validation, defaults
│  ├─ store.lua            data/state.json, versioning, migrations
│  ├─ registry.lua         config validation -> zones/channels/codeplugs/jobs/models
│  ├─ framework.lua        job adapters (QBX, QBCore, ESX, ND_Core, ox_core)
│  ├─ sessions.lua         per-player session, access resolution, membership
│  ├─ battery.lua          drain / charge model, warnings, flat-battery shutdown
│  ├─ voice.lua            transmit grant, packet relay, time-outs, override
│  └─ main.lua             net events, commands, exports, lifecycle
├─ client/
│  ├─ anim.lua             transmit animation styles via scully_emotemenu (cosmetic, local)
│  ├─ settings_menu.lua    the /radiosetting menu (ox_lib)
│  └─ main.lua             key bindings, NUI focus, server<->NUI relay
├─ web/                    NUI page (plain HTML/CSS/JS, no build step)
│  ├─ index.html
│  ├─ css/
│  │  ├─ radio.css             shared layout and display
│  │  └─ models.css            one block per model skin
│  └─ js/
│     ├─ app.js            display + controls + tx/rx orchestration
│     ├─ ui/
│     │  └─ menu.js            softkey pages and the key stack
│     └─ audio/
│        ├─ codecs.js          codec registry: Opus, ADPCM, packet framing
│        ├─ capture.js         microphone -> 20 ms frames
│        ├─ capture-worklet.js audio-thread framing
│        ├─ playback.js        jitter buffer + tunable receive chain
│        └─ tones.js           synthesised tones
├─ locales/en.json         every player-facing string
├─ data/                   state.json is written here at run time
└─ docs/                   ARCHITECTURE, PROTOCOL, TESTING, STATUS
```

Later phases add files; they do not restructure this tree.

## 3. Feature and dependency matrix

Status words: **Done** = implemented and covered by the maintainer's offline tests; **Planned** =
designed, not written; **Optional** = off by default / needs something extra.
"In-game" verification is tracked separately in STATUS.md.

| Feature                                                                  | Phase | Status                                               | Needs                                                          |
| ------------------------------------------------------------------------ | ----- | ---------------------------------------------------- | -------------------------------------------------------------- |
| Conventional channels, zones                                             | 1     | Done                                                 | —                                                              |
| Codeplugs, job + rank mapping, ACE grants                                | 1     | Done                                                 | A framework for job mapping; ACE works standalone              |
| Own voice transport, PTT, half-duplex, TX time-out                       | 1     | Done                                                 | Player allows NUI microphone access                            |
| Codec abstraction, Opus + ADPCM, per-channel codec                       | 1     | Done                                                 | Opus needs WebCodecs in the game's browser; ADPCM always works |
| Digital / analog receive sound per channel                               | 1     | Done, tunable from `Config.audio` in phase 2         | —                                                              |
| Callsigns, unit ids, persistence, migrations                             | 1     | Done                                                 | Writable `data/` folder                                        |
| One radio model, basic display, tones                                    | 1     | Done                                                 | —                                                              |
| Radio models as skins, softkey menus, per-player settings, full tone set | 2     | Done                                                 | —                                                              |
| Tunable receive chain (band, soft clip, noise floor, squelch tail)       | 2     | Done                                                 | —                                                              |
| Battery: drain, charge, warnings, flat-battery shutdown                  | 2     | Done, on by default                                  | Writable `data/` folder                                        |
| Supervisor transmit override ("bonk override")                           | 2     | Done                                                 | A codeplug with `supervisor = true`                            |
| Transmit animation and radio prop                                        | 2     | Done                                                 | The animation dictionary and prop model exist in the game      |
| Scanning, priorities, nuisance delete, talkback                          | 3     | Planned                                              | —                                                              |
| Trunked talkgroups                                                       | 3     | Planned                                              | —                                                              |
| Persistent patching (conventional only)                                  | 3     | Planned                                              | —                                                              |
| Emergency profiles (alarm / call / silent), man-down                     | 3     | Planned                                              | Auto-transmit stays opt-in per player                          |
| Dispatch web panel, admin panel, live settings                           | 4     | Planned                                              | HTTP handler on the FiveM port; browser mic needs HTTPS        |
| Transmission history / replay                                            | 4     | Planned                                              | Retention + privacy settings; stores encoded audio             |
| Alerts, announcement groups                                              | 4     | Planned                                              | —                                                              |
| Signal towers, bars, degradation                                         | 5     | Planned                                              | OneSync (server-side positions)                                |
| Geo-zone channel switching, GPS blips                                    | 5     | Planned                                              | OneSync                                                        |
| 3D radio audio, earbuds, vehicle radio, speakers                         | 5     | Planned                                              | OneSync; per-listener panning in NUI                           |
| 911 queue with private voice                                             | 6     | Planned, off by default                              | —                                                              |
| Phone / CAD / MDT adapters                                               | 6     | Extension stubs unless a documented API is confirmed | The other resource                                             |
| REST API, Discord OAuth for panels                                       | 6     | Optional                                             | Discord application credentials in convars                     |
| Windows desktop companion                                                | 7     | Optional, feasibility not yet confirmed              | Electron build + code signing                                  |
| Server-to-server federation                                              | 7     | Optional                                             | Authenticated transport; not designed yet                      |

### External dependencies

| Dependency                                                 | Version                       | Required?                                              |
| ---------------------------------------------------------- | ----------------------------- | ------------------------------------------------------ |
| FiveM server artifact with `cerulean` manifest and Lua 5.4 | any current recommended build | Yes                                                    |
| OneSync                                                    | on                            | Recommended now; **required** from phase 5 (positions) |
| ox_lib                                                     | current                       | Yes — the `/radiosetting` menu                         |
| scully_emotemenu                                           | 2.x                           | Yes for animations — it plays them; drop it from `dependencies` to run without any |
| qbx_core / qb-core / es_extended                           | current                       | Optional — job mapping                                 |
| ND_Core 2.x / ox_core                                      | current                       | Optional — adapters are best-effort, see §5            |

No account, licence key, port forward or external service is needed. ox_lib and
scully_emotemenu are ordinary open-source FiveM resources: psradio calls
ox_lib's menu for the settings UI and asks scully_emotemenu to play or cancel
an emote while transmitting, and contains no code from either.

## 4. Voice transport, codecs and licensing

### Transport

Voice travels as ordinary FiveM net events (`sv:txFrame` / `cl:rxFrame`), with
the packet base64-encoded because the NUI ↔ Lua bridge is JSON. This needs no
extra port and no extra process. The costs, stated plainly:

- Net events are **reliable and ordered**. A lost UDP packet delays the ones
  behind it, so a bad connection is heard as a stall followed by a catch-up,
  not as a short dropout. The 120 ms jitter buffer hides small stalls.
- The server sends one event per listener per packet. See TESTING.md →
  Performance for the arithmetic.

If measurements in game show this is not good enough, the upgrade path is a
WebSocket voice server inside the same resource (server-side JavaScript); the
codec, framing and grant logic stay exactly as they are.

### Codecs

All codecs sit behind one interface in `web/js/audio/codecs.js`
(`createEncoder(id, opts, onPacket)` / `createDecoder(id, onAudio)`), fed with
20 ms mono frames at 48 kHz. Each transmission carries its codec id, and each
channel can name its codec in `config.lua`.

| Id  | Codec            | Implementation                                        | Licence position                                                      |
| --- | ---------------- | ----------------------------------------------------- | --------------------------------------------------------------------- |
| 1   | Opus             | The game browser's built-in WebCodecs encoder/decoder | Opus is royalty-free (BSD-style); nothing is redistributed by psradio |
| 2   | IMA ADPCM, 8 kHz | Original JavaScript in this repository                | Long-public algorithm; this implementation is ours                    |

If a client's browser lacks WebCodecs Opus, the server grants that client
ADPCM instead (the client reports its capabilities when it connects).

**Not implemented, and not claimed:**

- **P25 Phase 1 IMBE.** psradio does not encode or decode IMBE frames. No
  implementation is bundled because we have not identified one that is both
  technically vetted and clearly licensed for redistribution inside a game
  resource, and no legal review of the vocoder's patent and licence position has
  been done. "Digital" in psradio means _the channel's receive sound profile_,
  not a P25 air interface.
- **Codec 2.** Technically attractive (700–3200 bit/s, LGPL-2.1), but it needs
  a WebAssembly build of the reference C library. Adding it means: build
  `libcodec2` to WASM, add id 3 to `PSR.Codec`, register an encoder/decoder pair
  in `codecs.js`. Nothing else changes.

### Bitrate and overhead — assumptions

Figures are per talker, per direction. "Payload" is exact arithmetic; "on the
wire" adds an **estimate** for event name, MessagePack framing and
ENet/UDP/IP headers (about 60–90 bytes per event) and has **not** been measured
in game.

|                                      | Opus (16 kbit/s target) | ADPCM                         |
| ------------------------------------ | ----------------------- | ----------------------------- |
| One 20 ms frame                      | ~40 bytes nominal       | 83 bytes (3 header + 80 data) |
| Codec bitrate                        | 16 kbit/s nominal       | 33.2 kbit/s                   |
| Packet (3 frames + 3×2 length bytes) | ~126 bytes              | 255 bytes                     |
| After base64 (×4/3)                  | ~168 characters         | 340 characters                |
| Packets per second                   | 16.7                    | 16.7                          |
| Payload bitrate in events            | ~22 kbit/s              | ~45 kbit/s                    |
| Estimated on the wire                | ~30–35 kbit/s           | ~53–58 kbit/s                 |

Measured once on desktop Chrome with a pure 1 kHz tone: Opus averaged 54 bytes
per frame at the 16 kbit/s setting (232 base64 characters per 3-frame packet).
The built-in encoder treats the bitrate as a target, so speech will vary.
Latency added by batching 3 frames is 60 ms, plus the 120 ms receive buffer.

## 5. Assumptions

Stated so they can be checked rather than discovered:

1. **NUI microphone capture works** in the FiveM client and prompts the player
   once. Other radio resources do this, and it uses the Windows default input
   device. Not yet verified with psradio in game.
2. **WebCodecs Opus exists in the game's browser.** Verified in desktop Chrome
   only. If absent, everything falls back to ADPCM automatically.
3. **`RegisterKeyMapping` may be called after script start** (psradio registers
   keys when the server's init arrives, because key defaults live in the
   server-only config).
4. **About 17 small events per second per talker is acceptable** to the server's
   event handling. Verify under load before a large deployment.
5. **Framework adapters.** qbx_core, qb-core and es_extended follow their
   published server APIs. **ND_Core and ox_core adapters are best-effort**:
   their documented APIs differ between versions and were not run here.
   **nat2k15 has no adapter** — no public API documentation was found; use
   `Config.access.resolve` (see README).
6. The stable player key is the `license` identifier. It is stored in
   `data/state.json` on the server and never sent to any client.

## 6. Threat model

Attacker: a player running a modified client who can send any net event with
any arguments, at any rate, and read everything the server sends them.

| Threat                                           | Defence                                                                                                                        |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------ |
| Spoofing another player                          | The server uses the engine-provided `source`; no event carries a "who am I" field                                              |
| Talking on a channel without permission          | `Voice.start` re-checks codeplug, power and channel membership on every PTT                                                    |
| Injecting audio into someone else's transmission | A packet is accepted only from the source that holds that transmission's server-issued id                                      |
| Replaying or reordering packets                  | Sequence numbers must strictly increase within a transmission and may not jump by more than 64                                 |
| Listening to a channel without permission        | Packets are sent only to sessions the server placed on that channel; the client cannot add itself                              |
| Learning the server's channel plan               | `config.lua` is server-only; a client receives only its own codeplug's channels                                                |
| Flooding (control, PTT, voice)                   | Three token buckets: control messages, PTT presses, voice packets per transmission. Excess is dropped silently                 |
| Oversized or malformed arguments                 | Every argument is type-, range- and length-checked; ids match `[A-Za-z0-9_-]{1,32}`; voice payload must be base64 ≤ 4096 chars |
| Markup / script injection through names          | Callsigns are `[A-Za-z0-9-]{1,12}`; the page writes text with `textContent` only, never `innerHTML`                            |
| Hostile voice payload crashing other clients     | Decoders bounds-check framing and packet sizes and skip anything invalid                                                       |
| Holding a channel forever                        | Transmission time-out and stall detection end it server-side                                                                   |
| Exposing player identity                         | Listeners see a callsign or `Unit <n>`; never a player name, server id or identifier                                           |
| Corrupt or newer state file                      | Corrupt files are backed up and replaced; newer-version files are never overwritten                                            |

Out of scope for phase 1, to be handled when introduced: HTTP/API
authentication and CSRF (phase 4), stored-audio privacy and retention
(phase 4), position spoofing for signal and 3D audio (phase 5), 911 abuse
(phase 6), server-to-server trust (phase 7).

A cheating client can always record what it is legitimately sent, and can
always send its own microphone audio modified. Neither is preventable.

## 7. Phased plan

| Phase                        | Contents                                                                                                                                    | Review point                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- |
| 1 — Foundation               | Config, permissions, codeplugs, conventional channels, voice transport with codec abstraction, PTT, basic radio, persistence, offline tests | Passed in game on 2026-11-17                       |
| **2 — Radio feel (current)** | Radio models as skins, softkey menus, per-player settings in an ox_lib `/radiosetting` menu, full tone set, tunable FX chain, battery, bonk override, animations       | Passed in game on 2026-11-22                       |
| 3 — Channel features         | Scan lists and priorities, nuisance delete, trunked talkgroups, persistent patches, emergency profiles, man-down                            | Behaviour under simultaneous traffic               |
| 4 — Dispatch and admin       | Web panels on the FiveM HTTP port, authentication, live-editable settings, transmission log and replay, alerts, announcement groups         | Security review of the HTTP surface                |
| 5 — World                    | Signal towers and degradation, geo-zones, GPS blips, 3D audio and earbuds, vehicle radio, placeable speakers                                | OneSync behaviour, performance with many listeners |
| 6 — 911 and integrations     | 911 queue and private call voice, phone/CAD/MDT adapters or stubs, REST API, optional Discord OAuth                                         | Abuse limits, integration contracts                |
| 7 — Optional extras          | Desktop companion, federation                                                                                                               | Go / no-go on each after a feasibility spike       |

Each phase is a set of new modules plus small, listed changes to existing
ones, released with its own tests and an updated STATUS.md.
