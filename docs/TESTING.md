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

Use two game clients (A and B) with different licences.

Cases 1-25 are the phase 1 set; they all passed on 2026-11-17. Cases 26-59
are the phase 2 set; they all passed on 2026-11-22. Re-run cases 1-3 after
upgrading to be sure nothing basic broke, then the phase 2 cases if you have
changed anything they cover.

### Must pass first

| #   | Steps                                          | Expected                                                                                      |
| --- | ---------------------------------------------- | --------------------------------------------------------------------------------------------- |
| 1   | A: `F6`, power on, hold `B` for the first time | FiveM asks to allow the microphone. After allowing: three beeps, red light, `TX`              |
| 2   | A and B on the same channel; A talks           | B hears A through the radio, sees `RX: Unit n` and an amber light. A does not hear themselves |
| 3   | Server console at start                        | `started: 3 zones, 3 codeplugs, framework=<yours>`; no config warnings                        |

If case 1 never prompts or always shows `Mic unavailable`, stop and see
Troubleshooting — the remaining audio cases cannot pass.

### Access

| #   | Steps                                                                      | Expected                                                       |
| --- | -------------------------------------------------------------------------- | -------------------------------------------------------------- |
| 4   | Player with an unmapped job presses `F6`                                   | Notification `No radio assigned`; nothing opens                |
| 5   | Change that player's job to `police`                                       | Within about 5 s `F6` opens the radio                          |
| 6   | Police grade 4 or higher                                                   | `FIREGRND` channels become selectable (command codeplug)       |
| 7   | Remove the job while the radio is on                                       | Radio closes within about 5 s; a transmission in progress ends |
| 8   | `add_ace identifier.license:<id> psradio.codeplug.fire allow`, then rejoin | Fire/EMS channels only, regardless of job                      |

### Channels and transmit

| #   | Steps                                                     | Expected                                                                          |
| --- | --------------------------------------------------------- | --------------------------------------------------------------------------------- |
| 9   | Zone key, channel keys                                    | Display follows; wraps at the ends; only your codeplug's transmit channels appear |
| 10  | A and B on different channels; A talks                    | B hears nothing                                                                   |
| 11  | A talks; B presses `B`                                    | B gets a low tone and `Channel busy`                                              |
| 12  | A holds `B` for 60 s                                      | A gets `Time out`, the channel frees, B can talk                                  |
| 13  | A talks; B tunes to A's channel mid-sentence              | B starts hearing A                                                                |
| 14  | A talks and switches channel / powers off / disconnects   | B's `RX` clears each time                                                         |
| 15  | Radio off, press `B`                                      | Low tone, `Radio is off` (visible if the radio is open)                           |
| 16  | Hide the radio with `Esc`, then talk and listen           | Still works while hidden                                                          |
| 17  | `TAC 1` (analog, ADPCM) versus `DISPATCH` (digital, Opus) | Audible difference; `A` / `D` in the display corner                               |

### Persistence and lifecycle

| #   | Steps                                            | Expected                                                        |
| --- | ------------------------------------------------ | --------------------------------------------------------------- |
| 18  | `/callsign 2L-319`; B listens to A               | B sees `RX: 2L-319`                                             |
| 19  | Rejoin                                           | Callsign and last channel are back; the radio is off            |
| 20  | `restart psradio` while A is talking             | No errors; radios reload switched off; `data/state.json` exists |
| 21  | `/callsign <b>x` and a 13-character callsign     | Both refused                                                    |
| 22  | With pma-voice running, stand next to each other | Proximity voice still works; radio adds to it                   |

### Abuse (needs a client-side Lua executor on a private test server)

| #   | Steps                                                           | Expected                                  |
| --- | --------------------------------------------------------------- | ----------------------------------------- |
| 23  | Fire `psradio:sv:select` with a channel outside your codeplug   | Refused; `getPlayerChannel` unchanged     |
| 24  | Fire `psradio:sv:txFrame` without a grant, or with a made-up id | Nobody hears anything                     |
| 25  | Loop `psradio:sv:power` thousands of times                      | Server stays responsive; most are dropped |

## Phase 2 test cases

Everything below passed in a game on 2026-11-22. A and B are two clients as
before; A is on a supervisor codeplug (police grade 4 and up, or
`add_ace ... psradio.codeplug.leo_command allow`) for the override cases.

### The radio itself

| #   | Steps                                                        | Expected                                                                                                                      |
| --- | ------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| 26  | `/radiosetting`                                              | An ox_lib menu opens, with the radio hidden as well as shown, listing Volume, Tones, Effects, End beep, one Animation tick box per animation in the config, PTT and Model |
| 27  | Arrow keys: down to Volume, then left / right to 50%         | The value changes as you scroll and the volume follows at once, with no delay                                                 |
| 28  | `Esc` to close, `/radiosetting` again, then rejoin the server | The menu closes; every setting you changed is still set                                                                      |
| 28a | Stop ox_lib, then `/radiosetting`                            | A notice says the settings need ox_lib. The radio itself still works                                                          |
| 29  | Settings → Model                                             | The radio redraws as another model. A 4-key model shows `INFO` on its fourth softkey and the key under the display disappears |
| 30  | A player whose codeplug lists one model opens the settings   | No Model row at all                                                                                                           |
| 31  | Settings → PTT → Toggle, then tap `B` once, speak, tap again | One tap starts the transmission and the next ends it; the transmit key is outlined while it is latched                        |
| 31a | `MENU` (the key under the display)                           | The radio information page, with `/radiosetting` listed as the last row; settings are no longer on the radio itself           |
| 32  | With PTT on Toggle, tap `B` and walk away from the keyboard  | The transmission still ends itself after 60 s (`tx_timeout`)                                                                  |

### Sound

| #   | Steps                                                              | Expected                                                                                                                                                                                         |
| --- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 33  | Listen through one full exchange                                   | Three chirps on permit, a beep at the end of your own transmission, a short courtesy beep when the other unit releases, a crackle as each transmission opens and a short noise tail as it closes |
| 34  | Press `B` on a busy channel                                        | Two low "bonk" notes, not the plain deny buzz                                                                                                                                                    |
| 35  | Settings → Effects → Light, then Off; listen to `TAC 1` both ways  | Light halves the grit, the noise floor and the squelch tail; Off leaves clean band-limited speech. Digital channels barely change                                                                |
| 36  | Settings → End beep → Off                                          | No courtesy beep when the other unit releases; everything else is unchanged                                                                                                                      |
| 37  | Settings → Tones → 0%                                              | Every radio tone is silent; voice is not                                                                                                                                                         |
| 38  | Edit `Config.audio.analog.drive` to 2.5, `restart psradio`, rejoin | `TAC 1` is clearly grittier than before                                                                                                                                                          |

### Battery

Set `Config.battery.capacityMinutes = 3` and `chargeMinutes = 2` first, or
these take hours. Put them back afterwards.

| #   | Steps                                                               | Expected                                                                                     |
| --- | ------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| 39  | Power on and wait                                                   | The bar in the top corner empties; it turns amber at 25%                                     |
| 40  | Keep waiting past 25%, 10% and 5%                                   | One chirp and one message as each level is crossed, never twice for the same level           |
| 41  | Hold `B` for 30 s and watch the bar                                 | It drops about six times faster than idle                                                    |
| 42  | Let it reach 0                                                      | The radio switches itself off, says `Battery flat`, and `F6` + power refuses to switch it on |
| 43  | Leave the radio off for a minute, then power on                     | It charged while it was off and switches on again                                            |
| 44  | Rejoin the server                                                   | The level is where you left it — reconnecting is not a refill                                |
| 45  | `/radiobattery 100 <player id>` from the server console or an admin | That player's radio is full again                                                            |
| 46  | `Config.battery.enabled = false`, `restart psradio`                 | No battery indicator at all and nothing ever drains                                          |

### Supervisor override

| #   | Steps                                                   | Expected                                                                                           |
| --- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 47  | B transmits; A (supervisor) presses `B` once            | A gets the bonk and `Busy - press again to cut in`. B is not interrupted                           |
| 48  | A presses `B` again within 3 s                          | A takes the channel; B's transmission ends and B is told `Cut off by supervisor`; listeners hear A |
| 49  | Repeat 47, wait 5 s, then press again                   | Refused again — the offer expires                                                                  |
| 50  | A unit without the supervisor flag does 47              | Plain `Channel busy`, no offer, and a second press changes nothing                                 |
| 51  | `Config.voice.allowOverride = false`, `restart psradio` | Even the supervisor only ever gets `Channel busy`                                                  |

### Animations, and the phase review point

| #   | Steps                                                           | Expected                                                                               |
| --- | --------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| 52  | Add the README's emote definitions to scully_emotemenu, then type its own command (`/radio`) | The emote plays. If it does not, psradio cannot play it either — fix this first |
| 53  | Tick Animation: Shoulder mic, transmit on foot; B watches from third person | A reaches for the shoulder mic, and the emote ends when A releases. Every other animation box is unticked |
| 54  | A transmits while driving, then while sprinting, swimming, in a fight, or dead | Either the emote plays or nothing happens — the transmission always works regardless |
| 55  | Untick the animation that is ticked, then transmit               | No box is ticked and nothing plays; B sees nothing                                     |
| 55a | Tick Animation: In hand, then transmit                          | The `radiohand` emote plays, prop and all — one emote, never two animations at once    |
| 55b | Tick Animation: Shoulder mic while In hand is ticked             | Shoulder mic ticks and In hand unticks on its own; only one box is ever ticked          |
| 55c | Tick another animation while holding the PTT                    | The emote swaps over mid-transmission; the audio is not interrupted                     |
| 55d | Add `{ id = 'epaulette', label = 'Epaulette mic', emote = 'radioep' }` to `Config.animations.styles`, `restart psradio` | A fifth tick box appears, labelled Epaulette mic, and ticking it plays that emote |
| 55e | Remove the animation a player had ticked, `restart psradio`     | That player falls back to the first animation in the list; the console says so once     |
| 55f | Transmit on a motorcycle or a bicycle                           | No animation at all (`blockedClasses`); the transmission still works                   |
| 55g | Start an emote of your own in scully_emotemenu, then transmit and release | psradio's emote replaces it while transmitting; releasing cancels only what psradio started |
| 55h | Stop scully_emotemenu, then transmit                            | The radio works, nothing is animated, and `F8` says scully_emotemenu is not running once |
| 55i | `Config.animations.enabled = false`, `restart psradio`          | No Animation tick boxes in `/radiosetting` at all, and nothing plays for anyone         |
| 56  | Open the radio while driving, change zone and channel, transmit | Usable with one hand on the keys; no steering or camera input is stolen                |
| 57  | `restart psradio` while transmitting                            | The emote is cancelled with the resource: no animation and no prop left running        |

### Upgrading from phase 1

| #   | Steps                                                                  | Expected                                                                                                                                     |
| --- | ---------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| 58  | Keep an existing `data/state.json` from phase 1, start the new version | Console says `state=migrated`; callsigns, unit ids and last channels are intact, everyone starts on the default settings with a full battery |
| 59  | Start with no state file                                               | `state=new`, and the console line now ends with `battery=on, 480 min`                                                                        |

## Troubleshooting

| Symptom                                                 | Likely cause and fix                                                                                                                                                                                                  |
| ------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `Mic unavailable`                                       | The player refused the microphone prompt, or Windows has no default input device. Set the microphone as the Windows default and restart FiveM; press `F8` and look for a `[psradio] microphone` line naming the error |
| No prompt and no audio at all                           | This FiveM build may block NUI microphone capture. Report the `F8` error; the transport would need the planned WebSocket/other route                                                                                  |
| Everyone sounds narrowband on digital channels          | The game browser has no WebCodecs Opus, so the server fell back to ADPCM. Expected on old builds; nothing to fix                                                                                                      |
| `F6` / `B` do nothing                                   | Another resource owns the key. Rebind under FiveM Settings → Key Bindings → look for "Radio:" entries. Defaults in `config.lua` only apply the first time a player sees a binding                                     |
| Radio opens but no channels                             | The codeplug's `tx` list is empty or names channels that do not exist — check the console warnings at start                                                                                                           |
| `No radio assigned` for a mapped job                    | Job name in `Config.jobs` does not match the framework's job name exactly, or the adapter failed (console prints one warning). `Config.debug = true` for more                                                         |
| `could not write data/state.json`                       | The `data` folder is missing or read-only                                                                                                                                                                             |
| Audio stalls then speeds through                        | Packet loss on a reliable channel (see ARCHITECTURE §4). Check the players' connection first                                                                                                                          |
| Tones or voice silent until the player clicks the radio | Browser audio starts on the first click; powering the radio on is that click                                                                                                                                          |
| Battery drains far too fast or slow                     | `Config.battery.capacityMinutes` is minutes of runtime from full, and `txMultiplier` is how much transmitting costs. Only connected players drain or charge                                                           |
| Battery is back to full after a reconnect               | The `data/` folder is not writable, so nothing was saved — see the `could not write` row above                                                                                                                        |
| No animation at all                                     | scully_emotemenu is not running, the emote command in `Config.animations.styles` does not exist in it, `Config.animations.enabled = false`, or the player has no animation ticked. Type the emote's own command to tell which. A transmission is never blocked by an animation that will not play |
| A tick box is missing from the settings                 | That animation was skipped: the console says why (no `id`, a duplicate id, a missing `emote`, or more than `Limits.maxAnimStyles` of them)                                                                            |
| The prop floats or clips through the hand               | The prop belongs to the emote: fix it in scully_emotemenu's emote definition (`Bone`, `Placement`)                                                                                                                    |
| Two radio animations fight each other                   | pma-voice is playing its own as well: `setr voice_enableRadioAnim 0`                                                                                                                                                  |
| The radio is drawn too wide for the screen              | A `mobile` or `console` model on a small display. Under 900 px wide they stack into one column; a player can switch back to a handheld in the settings                                                                |
| A setting will not change                               | The server refused it: either the value is invalid or, for a model, the codeplug does not allow it. The radio always shows what the server stored                                                                     |
| Settings changed in `config.lua` do nothing             | `Config.settings` is only the starting point for players who have never changed that setting. Phase 4 adds live editing                                                                                               |

## Performance notes

- **Idle cost** is four server timers (250 ms for transmissions, 5 s for access,
  5 s for batteries, 15 s for saving) and no client per-frame work unless the
  radio is open (then one loop disabling a dozen controls). The battery timer
  does arithmetic per connected radio and nothing else; it is skipped entirely
  when the battery is switched off.
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
