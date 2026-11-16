# Status checklist

Version 0.1.0 — phase 1 of 7. Updated with every phase.

Legend: **Done** (written, offline-tested) · **Experimental** (written, needs
in-game proof) · **Optional** · **Not yet** (planned; phase in brackets).

No item on this page has been verified in a running FiveM server yet. "Done"
means the logic passes the maintainer's offline test suite, which is not
published in this repository.

## Done

- Single server-only configuration file with validation and clear warnings
- Zones and conventional channels; per-channel digital / analog mode and codec
- Codeplugs: transmit channels, scan-only channels (listed, refused for
  selection), allowed models (stored), supervisor flag (stored)
- Job → codeplug mapping with optional rank rules; unmapped jobs get no radio
- ACE grant `psradio.codeplug.<id>`; custom resolver hook
- Framework detection: qbx_core, qb-core, es_extended
- Server-authoritative power, channel selection and membership
- Push-to-talk grant / deny, half-duplex (one talker per channel)
- Transmission time-out and stall detection
- Voice packet relay with sender binding, sequence checks and size checks
- Rate limits for control messages, PTT presses and voice packets
- Codec abstraction with Opus and IMA ADPCM; automatic ADPCM fallback
- Callsigns (`/callsign`), stable unit numbers
- File persistence with schema version, migrations, corrupt-file backup
- Clean handling of disconnect, resource stop/restart, access loss
- Locale file for every player-facing string
- Server exports and events for other resources
- Offline test suite (kept by the maintainer, not published)

## Experimental — written, must be proven in game

- Microphone capture in the NUI page
- Opus through WebCodecs inside FiveM's browser (works in desktop Chrome)
- Receive filter chains for digital and analog (basic; tuning comes in phase 2)
- Radio page: one handheld model, power, zone / channel keys, volume, on-screen PTT
- Key bindings registered after the server's init
- ND_Core and ox_core job adapters (best-effort, never run against a live install)
- Voice over net events at scale

## Optional

- OneSync: recommended now, required from phase 5
- `Config.access.standaloneCodeplug`: off (nil) by default

## Not yet

| Feature | Phase |
|---|---|
| Multiple radio models, softkey menus, settings dialog, full tones, FX tuning | 2 |
| Battery, bonk override, radio animations, live-editable settings | 2 |
| Scanning, priorities, nuisance delete, scan lists | 3 |
| Trunked talkgroups | 3 |
| Persistent channel patching | 3 |
| Emergency profiles, man-down | 3 |
| Supervisor functions (the flag exists, nothing uses it) | 3 |
| Dispatch web panel, admin panel | 4 |
| Transmission history and replay | 4 |
| Alerts, announcement groups | 4 |
| Signal towers, bars, degradation, geo-zones, GPS blips | 5 |
| 3D audio, earbuds, vehicle radio, placeable speakers | 5 |
| 911 queue and private call voice | 6 |
| Phone / CAD / MDT integrations (stubs unless an API is confirmed) | 6 |
| REST API, Discord OAuth | 6 |
| Windows desktop companion (feasibility unconfirmed) | 7 |
| Federation between servers (not designed) | 7 |

## Will not be claimed

- P25 Phase 1 IMBE or any AMBE vocoder — not implemented
- Compatibility with any real or proprietary radio system
- nat2k15 auto-detection — no documented API was found
