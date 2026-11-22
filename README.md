# psradio

![Status: in development](https://img.shields.io/badge/status-in%20development-orange)
![Licence: source-available, no modification](https://img.shields.io/badge/licence-no%20modification-red)

> **In development.** Features are incomplete and anything may change between
> versions. Not recommended for production servers yet.

A standalone public-safety radio for FiveM: zones and channels, codeplugs
mapped to jobs, and its own radio voice that runs next to your proximity voice.

This is **phase 2** of a phased build. It is a working foundation plus the
things that make a radio feel like one, not the full feature list — see
[docs/STATUS.md](docs/STATUS.md) for exactly what is done, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and the plan.

> **Phase 1 was verified in game on 2026-11-17**: cases 1-25 in
> [docs/TESTING.md](docs/TESTING.md) were worked through on a live FiveM server
> with two clients and all passed, so microphone capture, radio voice and the
> access rules do hold up.
>
> **Phase 2 was verified in game on 2026-11-22**: cases 26-59 in
> [docs/TESTING.md](docs/TESTING.md) were worked through on the same footing and
> all passed, so the models and softkey menus, the settings, the tones and the
> receive chain, the battery, the supervisor override, the animations and the
> upgrade from a phase 1 state file all hold up.

## Requirements

- A current FiveM server artifact. OneSync on is recommended (later phases
  require it).
- [**ox_lib**](https://github.com/overextended/ox_lib) — the `/radiosetting`
  menu is an ox_lib menu. Start it before psradio.
- [**scully_emotemenu**](https://github.com/Scullyy/scully_emotemenu) — it
  plays the transmit animations. psradio asks it to start and cancel an emote
  and never plays an animation itself. Drop the `scully_emotemenu` line from
  `dependencies` in `fxmanifest.lua` if you would rather run without
  animations; everything else works without it.
- No account, key, database or extra port.
- Optional: qbx_core, qb-core or es_extended for job-based radios.
- Works alongside pma-voice or Mumble; it does not replace proximity voice.

## Install

1. Copy the `psradio` folder into your server's `resources` directory. Keep the
   folder name `psradio`.
2. Add to `server.cfg`, after your framework and after ox_lib and
   scully_emotemenu:

   ```cfg
   ensure ox_lib
   ensure scully_emotemenu
   ensure psradio
   ```

3. Make sure the server process can write to `psradio/data/`.
4. Give players a radio — either map jobs in `config.lua` (step below) or grant
   a codeplug by ACE:

   ```cfg
   add_ace group.police psradio.codeplug.leo allow
   ```

5. Start the server. The console prints one line such as
   `[psradio] [info] started: 3 zones, 3 codeplugs, framework=qb-core, state=new`,
   plus a warning for anything in the config it had to skip.

## Configure

Everything is in **`config.lua`**. It is loaded on the server only, and every
setting in it takes effect on `restart psradio` (nothing in phase 1 is
live-editable).

The shipped demo has 3 zones, 12 channels, 3 codeplugs and 4 radio models, with
`police` and `sheriff` mapped to the law-enforcement codeplug (grade 4 and up
get the command codeplug, which is the supervisor one) and `ambulance` and
`fire` mapped to Fire/EMS.

| Block | What it sets |
| ----- | ------------ |
| `Config.zones` / `Config.codeplugs` / `Config.jobs` | Who hears what, as in phase 1 |
| `Config.models` | The radios a unit can carry: a name, a skin (`handheld`, `mobile`, `console`) and 3 or 4 softkeys. A codeplug's `models` list decides who may carry which |
| `Config.audio` | How a received transmission sounds: pass band, soft-clip drive, noise floor and squelch tail, per mode. Raise `analog.drive` for a grittier analog channel |
| `Config.battery` | Runtime from full, how much transmitting costs, charge time, warning levels — or `enabled = false` |
| `Config.animations` | The transmit animations players can pick, and the scully_emotemenu emote command each one plays |
| `Config.voice.allowOverride` | Whether a supervisor codeplug may cut into a busy channel |
| `Config.settings` | What a player's own settings start at, until they change them |

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

| ACE                        | Effect                                                     |
| -------------------------- | ---------------------------------------------------------- |
| `psradio.codeplug.<id>`    | Gives the player that codeplug, overriding their job       |
| `command.radiobattery`     | May run `/radiobattery <0-100> [player id]`                 |

A codeplug with `supervisor = true` may cut into a busy channel; see Controls.
The admin panel and its own ACEs arrive in phase 4.

## Controls

| Action                                      | Default                           | Notes                                                            |
| ------------------------------------------- | --------------------------------- | ---------------------------------------------------------------- |
| Show / hide the radio                       | `F6`                              | Rebind in FiveM Settings → Key Bindings                          |
| Push to talk                                | hold `B`                          | Works with the radio hidden. Switchable to a toggle in settings  |
| Power                                       | click the power button            | The radio starts switched off                                    |
| Next zone / previous channel / next channel | the softkeys under the display    | Labels follow the menu page                                      |
| Radio information, and back out of it       | `MENU`, or `Esc`                  | Codeplug, NAC, frequency, model, battery. On a 4-key model `INFO` is the fourth softkey |
| Settings                                    | `/radiosetting`                   | An ox_lib menu, with the radio hidden as well as shown. Arrow keys to move and to change a row, `Esc` to close |
| Volume                                      | `−` / `+` on the radio            | Saved per player, like every setting                             |
| Cut into a busy channel                     | press PTT twice                   | Supervisor codeplugs only, and only within a few seconds         |
| Hide                                        | `Esc` on the channel display, `×` | Hiding does not switch the radio off                             |

Each player's own settings — volume, tone volume, effects strength, end beep,
which transmit animation, PTT hold or toggle, and radio model — live in the
`/radiosetting` menu, not on the radio. They are saved against their licence
and follow them to another machine.

### Transmit animations

The animations live in scully_emotemenu; psradio only says which emote to play
and when to cancel it. The list is yours: every entry in
`Config.animations.styles` becomes **its own tick box** in `/radiosetting`.
Only one animation can play, so ticking one unticks the others, and unticking
the ticked one leaves no animation at all — there is no separate "off" row.

What ships:

| Tick box     | Plays                            | Emote command |
| ------------ | -------------------------------- | ------------- |
| Shoulder mic | a hand to the shoulder mic       | `radio` (`radio2` while aiming or in a vehicle) |
| Chest mic    | a hand to a chest-mounted mic    | `radiochest`  |
| Earpiece     | a hand to an earpiece            | `earpiece`    |
| In hand      | the radio held up, prop and all  | `radiohand`   |

Add, remove or rename entries freely:

```lua
{ id = 'epaulette', label = 'Epaulette mic', emote = 'radioep' },
```

`id` is what is saved for the player, `emote` is the scully_emotemenu command,
`aiming` and `inVehicle` are optional emotes for those two cases, and `label`
is what the tick box says — without one, the locale's `set_anim_<id>` is used,
and failing that the id itself, so only an animation of your own needs a label.
`Config.settings.animStyle` picks which one new players start with, or `'off'`
for none; an id that is not in the list falls back to the first one listed.

Nothing is animated on a motorcycle, bicycle, helicopter or plane
(`Config.animations.blockedClasses`), or while the ped is dead, ragdolling,
swimming or cuffed. `Config.animations.enabled = false` switches animations off
for the whole server, and the tick boxes disappear with it.

#### The emote definitions

The emote commands above have to exist in scully_emotemenu. Add these to its
emote data (`shared/data/emotes/`), or point `Config.animations.styles` at
emotes you already have:

```lua
['radio'] = {
    Label = 'Radio', Command = 'radio',
    Dictionary = 'random@arrests', Animation = 'generic_radio_chatter',
    Options = { Flags = { Loop = true, Move = true } },
},
['radio2'] = {
    Label = 'Radio 2', Command = 'radio2',
    Dictionary = 'random@arrests', Animation = 'radio_chatter',
    Options = { Flags = { Loop = true, Move = true } },
},
['radiochest'] = {
    Label = 'Radio Chest', Command = 'radiochest',
    Dictionary = 'anim@cop_mic_pose_002', Animation = 'chest_mic',
    Options = { Flags = { Loop = true, Move = true } },
},
['earpiece'] = {
    Label = 'Earpiece', Command = 'earpiece',
    Dictionary = 'cellphone@', Animation = 'cellphone_call_listen_base',
    Options = { Flags = { Loop = true, Move = true } },
},
['radiohand'] = {
    Label = 'Radio In Hand', Command = 'radiohand',
    Dictionary = 'cellphone@', Animation = 'cellphone_call_listen_base',
    Options = {
        Flags = { Loop = true, Move = true },
        Props = { { Name = 'prop_cs_hand_radio', Bone = 28422,
                    Placement = { vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 0.0) } } },
    },
},
```

These follow the shape scully_emotemenu's own emotes use, including the prop on
`radiohand`; check its data files for the exact form your version expects. A
style whose emote command does not exist in scully_emotemenu simply plays
nothing.

If you also run pma-voice, switch its own radio animation off so the two do not
fight: `setr voice_enableRadioAnim 0`.

With the battery switched on, the radio drains while it is on, drains faster
while transmitting, charges while it is off, chirps as it passes each warning
level, and switches itself off when it is flat.

`/radiosetting` opens the settings window, and closes it again. It needs a
radio, not an open one.

`/callsign 2L-319` sets your callsign, `/callsign` shows it, `/callsign clear`
removes it. Without one, others see `Unit <number>`.

`/radiobattery <0-100> [player id]` sets a battery level, for admins or for
testing. From the server console the player id is required.

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
exports.psradio:getPlayerModel(source)     -- model id the player is carrying, or nil
exports.psradio:getPlayerSettings(source)  -- a copy of their radio settings, or nil
exports.psradio:isTransmitting(source)     -- boolean
exports.psradio:getBattery(source)         -- 0-100, or nil
exports.psradio:setBattery(source, 100)    -- for a charger or a battery swap
exports.psradio:refreshAccess(source)      -- re-check job / ACE now

AddEventHandler('psradio:txStarted', function(source, channelId) end)
AddEventHandler('psradio:txEnded', function(source, channelId, reason) end)
```

## Data and privacy

`data/state.json` holds, per player licence identifier: a unit number, the
callsign, the last selected channel, the player's own radio settings and their
battery level. No audio is recorded or stored. Other players never receive a
name, server id or identifier from psradio — only the callsign or unit number.

A phase 1 state file is migrated to the new shape the first time this version
starts; the old data is kept and nothing is lost.

## Translating

Copy `locales/en.json` to `locales/<code>.json`, translate the values, and set
`Config.locale = '<code>'`. Missing keys fall back to English.

## AI assistance

Most of the code and documentation in this repository were written with
an AI coding assistant (Claude, by Anthropic), working from the maintainer's
feature brief and direction. Treat it accordingly: the server logic passes the
maintainer's offline test suite and phases 1 and 2 were both proven in a live
game, but review before production use is recommended. Bug reports and
corrections are welcome.

## Licence

psradio is source-available, not open source. You may read it and run it
unmodified on your own server, and edit `config.lua` and the locale files to
set it up. You may not modify the rest, build on it, or redistribute it. The
full terms are in [LICENSE](LICENSE).

## Licences of what is inside

All code, styles and tones here are original to this project. Opus encoding
uses the game browser's built-in encoder; nothing third-party is bundled.
