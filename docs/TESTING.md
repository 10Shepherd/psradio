# Testing psradio

## Offline checks

The maintainer keeps an offline test suite that is **not published in this
repository**, so you cannot run it from a clone. It checks:

1. **Lua syntax** for every `.lua` file.
2. **JavaScript syntax** for every NUI script.
3. **Manifest check** — every file named in `fxmanifest.lua` exists.
4. **Server behaviour** — the real server scripts, loaded in manifest order
   into a Lua VM with stand-ins for the FiveM natives. It covers config
   validation, access by ACE and by job and rank, channel selection, transmit
   grant and denial, packet relay, spoofing / replay / malformed input, all
   three rate limits, time-out and stall, disconnect, access loss
   mid-transmission, shutdown, callsigns, and the state file (corrupt, newer
   version, migration).
5. **Codecs** — packet framing, hostile input, and an ADPCM encode/decode round trip.

What these do **not** cover: `client/main.lua` (syntax only), the page's
microphone path, and anything that depends on the real FiveM runtime. The Lua
VM is 5.3 while FiveM runs 5.4; the scripts avoid 5.4-only syntax.

The in-game cases below need nothing but the published resource.

## In-game test cases

Use two game clients (A and B) with different licences. Tick each off; the
first three decide whether the voice design holds at all.

### Must pass first

| # | Steps | Expected |
|---|---|---|
| 1 | A: `F6`, power on, hold `B` for the first time | FiveM asks to allow the microphone. After allowing: three beeps, red light, `TX` |
| 2 | A and B on the same channel; A talks | B hears A through the radio, sees `RX: Unit n` and an amber light. A does not hear themselves |
| 3 | Server console at start | `started: 3 zones, 3 codeplugs, framework=<yours>`; no config warnings |

If case 1 never prompts or always shows `Mic unavailable`, stop and see
Troubleshooting — the remaining audio cases cannot pass.

### Access

| # | Steps | Expected |
|---|---|---|
| 4 | Player with an unmapped job presses `F6` | Notification `No radio assigned`; nothing opens |
| 5 | Change that player's job to `police` | Within about 5 s `F6` opens the radio |
| 6 | Police grade 4 or higher | `FIREGRND` channels become selectable (command codeplug) |
| 7 | Remove the job while the radio is on | Radio closes within about 5 s; a transmission in progress ends |
| 8 | `add_ace identifier.license:<id> psradio.codeplug.fire allow`, then rejoin | Fire/EMS channels only, regardless of job |

### Channels and transmit

| # | Steps | Expected |
|---|---|---|
| 9 | Zone key, channel keys | Display follows; wraps at the ends; only your codeplug's transmit channels appear |
| 10 | A and B on different channels; A talks | B hears nothing |
| 11 | A talks; B presses `B` | B gets a low tone and `Channel busy` |
| 12 | A holds `B` for 60 s | A gets `Time out`, the channel frees, B can talk |
| 13 | A talks; B tunes to A's channel mid-sentence | B starts hearing A |
| 14 | A talks and switches channel / powers off / disconnects | B's `RX` clears each time |
| 15 | Radio off, press `B` | Low tone, `Radio is off` (visible if the radio is open) |
| 16 | Hide the radio with `Esc`, then talk and listen | Still works while hidden |
| 17 | `TAC 1` (analog, ADPCM) versus `DISPATCH` (digital, Opus) | Audible difference; `A` / `D` in the display corner |

### Persistence and lifecycle

| # | Steps | Expected |
|---|---|---|
| 18 | `/callsign 2L-319`; B listens to A | B sees `RX: 2L-319` |
| 19 | Rejoin | Callsign and last channel are back; the radio is off |
| 20 | `restart psradio` while A is talking | No errors; radios reload switched off; `data/state.json` exists |
| 21 | `/callsign <b>x` and a 13-character callsign | Both refused |
| 22 | With pma-voice running, stand next to each other | Proximity voice still works; radio adds to it |

### Abuse (needs a client-side Lua executor on a private test server)

| # | Steps | Expected |
|---|---|---|
| 23 | Fire `psradio:sv:select` with a channel outside your codeplug | Refused; `getPlayerChannel` unchanged |
| 24 | Fire `psradio:sv:txFrame` without a grant, or with a made-up id | Nobody hears anything |
| 25 | Loop `psradio:sv:power` thousands of times | Server stays responsive; most are dropped |

## Troubleshooting

| Symptom | Likely cause and fix |
|---|---|
| `Mic unavailable` | The player refused the microphone prompt, or Windows has no default input device. Set the microphone as the Windows default and restart FiveM; press `F8` and look for a `[psradio] microphone` line naming the error |
| No prompt and no audio at all | This FiveM build may block NUI microphone capture. Report the `F8` error; the transport would need the planned WebSocket/other route |
| Everyone sounds narrowband on digital channels | The game browser has no WebCodecs Opus, so the server fell back to ADPCM. Expected on old builds; nothing to fix |
| `F6` / `B` do nothing | Another resource owns the key. Rebind under FiveM Settings → Key Bindings → look for "Radio:" entries. Defaults in `config.lua` only apply the first time a player sees a binding |
| Radio opens but no channels | The codeplug's `tx` list is empty or names channels that do not exist — check the console warnings at start |
| `No radio assigned` for a mapped job | Job name in `Config.jobs` does not match the framework's job name exactly, or the adapter failed (console prints one warning). `Config.debug = true` for more |
| `could not write data/state.json` | The `data` folder is missing or read-only |
| Audio stalls then speeds through | Packet loss on a reliable channel (see ARCHITECTURE §4). Check the players' connection first |
| Tones or voice silent until the player clicks the radio | Browser audio starts on the first click; powering the radio on is that click |

## Performance notes

- **Idle cost** is three server timers (250 ms, 5 s, 15 s) and no client
  per-frame work unless the radio is open (then one loop disabling a dozen
  controls).
- **Per transmission:** 16.7 events per second from the talker, and the same
  number to each listener. Twenty listeners on one channel is about 330 small
  server→client events per second for that channel.
- **Access polling** calls the framework once per connected radio every 5 s.
  Raise `Config.access.refreshSeconds` on very large servers and call
  `refreshAccess` from your job-change code instead.
- **State file** is written at most every 15 s and only when something changed.
  It grows by one small record per distinct player and is never pruned in
  phase 1.
- Lower `Config.voice.framesPerPacket` for less delay and more events; raise it
  (up to 6 = 120 ms) for fewer events and more delay.

None of these figures has been measured on a live server yet.
