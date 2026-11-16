# psradio

![Status: in development](https://img.shields.io/badge/status-in%20development-orange)
![Licence: source-available, no modification](https://img.shields.io/badge/licence-no%20modification-red)

> **In development.** Features are incomplete and anything may change between
> versions. Not recommended for production servers yet.

A standalone public-safety radio for FiveM: zones and channels, codeplugs
mapped to jobs, and its own radio voice that runs next to your proximity voice.

This is **phase 1** of a phased build. It is a working foundation, not the full
feature list — see [docs/STATUS.md](docs/STATUS.md) for exactly what is done,
and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and the plan.

> **Not yet run in a live game.** The server logic is covered by an offline test
> suite and the radio page was exercised in desktop Chrome, but nobody has
> loaded this resource in FiveM yet. Work through
> [docs/TESTING.md](docs/TESTING.md) before putting it on a public server.

## Requirements

- A current FiveM server artifact. OneSync on is recommended (later phases
  require it).
- Nothing else. No account, key, database or extra port.
- Optional: qbx_core, qb-core or es_extended for job-based radios.
- Works alongside pma-voice or Mumble; it does not replace proximity voice.

## Install

1. Copy the `psradio` folder into your server's `resources` directory. Keep the
   folder name `psradio`.
2. You may delete `psradio/tests` on a production server; the game never loads it.
3. Add to `server.cfg`, after your framework:

   ```cfg
   ensure psradio
   ```

4. Make sure the server process can write to `psradio/data/`.
5. Give players a radio — either map jobs in `config.lua` (step below) or grant
   a codeplug by ACE:

   ```cfg
   add_ace group.police psradio.codeplug.leo allow
   ```

6. Start the server. The console prints one line such as
   `[psradio] [info] started: 3 zones, 3 codeplugs, framework=qb-core, state=new`,
   plus a warning for anything in the config it had to skip.

## Configure

Everything is in **`config.lua`**. It is loaded on the server only, and every
setting in it takes effect on `restart psradio` (nothing in phase 1 is
live-editable).

The shipped demo has 3 zones, 12 channels and 3 codeplugs, with `police` and
`sheriff` mapped to the law-enforcement codeplug (grade 4 and up get the
command codeplug) and `ambulance` and `fire` mapped to Fire/EMS.

### Who gets a radio

Checked in this order; the first match wins:

1. `Config.access.resolve(source)` — your own function, if you set one.
2. An ACE `psradio.codeplug.<id>` (if a player holds several, the
   alphabetically first codeplug id wins).
3. The player's job, through `Config.jobs`.
4. `Config.access.standaloneCodeplug`, only when no framework is running.

A player who matches nothing has no radio. Changes to a player's job or ACEs
are picked up within `Config.access.refreshSeconds` (5 s by default), or
immediately if another resource calls `exports.psradio:refreshAccess(source)`.

### Frameworks

| Framework                      | Status                                                                                                    |
| ------------------------------ | --------------------------------------------------------------------------------------------------------- |
| qbx_core, qb-core, es_extended | Supported through their published server APIs                                                             |
| ND_Core, ox_core               | Best-effort adapters, not run against a live install. If a job is not recognised the console says so once |
| nat2k15                        | No adapter — no public API documentation was found. Use the hook below                                    |
| none                           | Standalone: ACE grants only                                                                               |

Hook for anything else:

```lua
Config.access.resolve = function(source)
    -- return a codeplug id, false for "no radio", or nil to use the normal rules
    if exports.myframework:getDepartment(source) == 'SAHP' then return 'leo' end
end
```

## Permissions

| ACE                     | Effect                                               |
| ----------------------- | ---------------------------------------------------- |
| `psradio.codeplug.<id>` | Gives the player that codeplug, overriding their job |

There are no admin ACEs in phase 1 because there is no admin surface yet.

## Controls

| Action                                      | Default                          | Notes                                   |
| ------------------------------------------- | -------------------------------- | --------------------------------------- |
| Show / hide the radio                       | `F6`                             | Rebind in FiveM Settings → Key Bindings |
| Push to talk                                | hold `B`                         | Works with the radio hidden             |
| Power                                       | click the power button           | The radio starts switched off           |
| Next zone / previous channel / next channel | the three keys under the display |                                         |
| Volume                                      | `−` / `+` on the radio           | Saved per player                        |
| Hide                                        | `Esc` or `×`                     | Hiding does not switch the radio off    |

`/callsign 2L-319` sets your callsign, `/callsign` shows it, `/callsign clear`
removes it. Without one, others see `Unit <number>`.

The first time a player transmits, FiveM asks them to allow microphone access
for the resource. The microphone used is the Windows default input device.

## Quick start (two players)

1. Both players need a radio (job or ACE).
2. Each presses `F6`, clicks the power button, and uses the keys under the
   display to reach the same zone and channel.
3. One holds `B`: three short beeps mean go ahead. The other sees
   `RX: Unit 1` and hears them. A low tone means the transmission was refused,
   and the display says why.

## Exports and events (server-side)

```lua
exports.psradio:getPlayerChannel(source)   -- channel id the radio is on, or nil
exports.psradio:getPlayerCodeplug(source)  -- codeplug id, or nil
exports.psradio:isTransmitting(source)     -- boolean
exports.psradio:refreshAccess(source)      -- re-check job / ACE now

AddEventHandler('psradio:txStarted', function(source, channelId) end)
AddEventHandler('psradio:txEnded', function(source, channelId, reason) end)
```

## Data and privacy

`data/state.json` holds, per player licence identifier: a unit number, the
callsign, and the last selected channel. No audio is recorded or stored. Other
players never receive a name, server id or identifier from psradio — only the
callsign or unit number.

## Translating

Copy `locales/en.json` to `locales/<code>.json`, translate the values, and set
`Config.locale = '<code>'`. Missing keys fall back to English.

## AI assistance

Most of the code, tests and documentation in this repository were written with
an AI coding assistant (Claude, by Anthropic), working from the maintainer's
feature brief and direction. Treat it accordingly: the server logic passes the
offline test suite, but nothing has been proven in a live game yet, and review
before production use is recommended. Bug reports and corrections are welcome.

## Licence

psradio is source-available, not open source. You may read it and run it
unmodified on your own server, and edit `config.lua` and the locale files to
set it up. You may not modify the rest, build on it, or redistribute it. The
full terms are in [LICENSE](LICENSE).

## Licences of what is inside

All code, styles and tones here are original to this project. Opus encoding
uses the game browser's built-in encoder; nothing third-party is bundled. The
`tests/` folder downloads two MIT-licensed developer tools (`fengari`,
`luaparse`) when you run `npm install` there.
