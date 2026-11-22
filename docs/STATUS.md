# Status checklist

Version 0.2.0 — phase 2 of 7. Updated with every phase.

Legend: **Done** (passes the offline suite and the in-game cases) ·
**Experimental** (written, still unproven) · **Optional** · **Not yet**
(planned; phase in brackets).

Phase 1 was tested on a live FiveM server on 2026-11-17: every in-game case in
[TESTING.md](TESTING.md) passed, including microphone capture, radio voice
between two clients, the access rules and persistence.

Phase 2 (this version) was tested on a live FiveM server on 2026-11-22:
every phase 2 in-game case in [TESTING.md](TESTING.md) passed — cases 26-59,
covering the models and the softkey menus, the settings menu and its
persistence, the tone set, the tunable receive chain, the battery, the
supervisor override, every animation case and the upgrade from a phase 1 state
file.

## Done — phase 1, proven in game

- Single server-only configuration file with validation and clear warnings
- Zones and conventional channels; per-channel digital / analog mode and codec
- Codeplugs: transmit channels, scan-only channels (listed, refused for
  selection), allowed models, supervisor flag
- Job → codeplug mapping with optional rank rules; unmapped jobs get no radio
- ACE grant `psradio.codeplug.<id>`; custom resolver hook
- Framework detection: qbx_core, qb-core, es_extended
- Server-authoritative power, channel selection and membership
- Push-to-talk grant / deny, half-duplex (one talker per channel)
- Transmission time-out and stall detection
- Voice packet relay with sender binding, sequence checks and size checks
- Rate limits for control messages, PTT presses and voice packets
- Codec abstraction with Opus and IMA ADPCM; automatic ADPCM fallback
- Microphone capture in the NUI page; Opus through WebCodecs in FiveM's browser
- Callsigns (`/callsign`), stable unit numbers
- File persistence with schema version, migrations, corrupt-file backup
- Clean handling of disconnect, resource stop/restart, access loss
- Locale file for every player-facing string
- Server exports and events for other resources

## Done — phase 2, proven in game

- Radio models as skins: handheld, mobile, console, with 3 or 4 softkeys
- Softkey menu with pages (channel display, radio information)
- Per-player settings in an ox_lib menu, opened with `/radiosetting` rather
  than from the radio, saved against the licence and validated server-side:
  volume, tone volume, effects strength, end beep, transmit animation, PTT
  hold/toggle, model
- Toggle PTT as well as hold
- Full tone set: permit, end, deny, busy "bonk", override, squelch open,
  courtesy beep, power up/down, key, menu, error, battery low, battery flat
- Receive chain tunable from `Config.audio`: pass band, soft-clip drive and
  makeup, noise floor, squelch tail — per mode, scaled by each player's
  `fx` setting
- Battery: drains while on, six times faster while transmitting, charges while
  off, warning chirps at configured levels, switches the radio off when flat and
  refuses to switch on again; saved per player
- `/radiobattery` command and `getBattery` / `setBattery` exports
- Supervisor transmit override: first press is refused with the busy tone and
  an offer, a second press within the window cuts the other unit off, and that
  unit is told why. `Config.voice.allowOverride = false` refuses everyone
- Transmit animations played by scully_emotemenu, one emote at a time. The
  animations are a config list (four ship: shoulder mic, chest mic, earpiece,
  radio in hand) and each one is a tick box in the settings, so a server can
  add or remove its own. Switchable off per player and per server, and nothing
  plays on blocked vehicle classes
- State file schema 2, migrated from schema 1 automatically
- Locale coverage check in the offline suite

## Experimental — written, still unproven

- ND_Core and ox_core job adapters (best-effort, never run against a live install)
- Voice over net events at scale: two clients work, a channel with twenty
  listeners has not been measured
- The animations on custom ped models, and while the player is cuffed. Case 54
  covered driving, sprinting, swimming, fighting and being dead on the default
  peds; no custom ped was tried

## Optional

- OneSync: recommended now, required from phase 5
- `Config.access.standaloneCodeplug`: off (nil) by default
- `Config.battery.enabled`: on by default, one line to switch off

## Not yet

| Feature                                                            | Phase |
| ------------------------------------------------------------------ | ----- |
| Live-editable settings (phase 2 settings need a `restart psradio`) | 4     |
| Scanning, priorities, nuisance delete, scan lists                  | 3     |
| Trunked talkgroups                                                 | 3     |
| Persistent channel patching                                        | 3     |
| Emergency profiles, man-down                                       | 3     |
| Supervisor functions beyond the transmit override                  | 3     |
| Dispatch web panel, admin panel                                    | 4     |
| Transmission history and replay                                    | 4     |
| Alerts, announcement groups                                        | 4     |
| Signal towers, bars, degradation, geo-zones, GPS blips             | 5     |
| 3D audio, earbuds, vehicle radio, placeable speakers               | 5     |
| 911 queue and private call voice                                   | 6     |
| Phone / CAD / MDT integrations (stubs unless an API is confirmed)  | 6     |
| REST API, Discord OAuth                                            | 6     |
| Windows desktop companion (feasibility unconfirmed)                | 7     |
| Federation between servers (not designed)                          | 7     |

## Will not be claimed

- P25 Phase 1 IMBE or any AMBE vocoder — not implemented
- Compatibility with any real or proprietary radio system
- nat2k15 auto-detection — no documented API was found
