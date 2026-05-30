# Bowie Knife99

A Cyberpunk 2077 meme mod inspired by the Forza **"bowie knife99"** legend. While you drive, on a random
timer an ordinary traffic car turns hostile, aggressively rams your vehicle, and then is reliably called
off — and moments later your phone buzzes with a taunt from a contact named **Bowie Knife99**.

## Features

- **Hijacks a real traffic car** (it already has a live AI driver) and sends it after you — no spawning or
  teleporting, so the chase always looks natural.
- **Picks an attacker from *behind* you**, within a configurable distance and a height window (so a car on a
  bridge overhead or a road below never gets chosen).
- **Aggressive ramming** with a close-range lunge, then a forceful, reliable break-off (the attacker flees).
- **Real in-phone SMS**: on a successful hit, the **Bowie Knife99** contact texts you one of **100** rotating
  taunts.
- **Fully configurable** live via the in-game **Mod Settings** menu — attack chance, check interval, cooldown,
  pursuit timeout, max distance, height limit, ram strength, debug HUD, and an on/off toggle.

## Requirements

| Dependency | Why |
|---|---|
| [RED4ext](https://www.nexusmods.com/cyberpunk2077/mods/2380) | Base loader for the plugins below |
| [REDscript](https://www.nexusmods.com/cyberpunk2077/mods/1511) | Compiles the mod's gameplay logic (`bowieknife99.reds`) |
| [ArchiveXL](https://www.nexusmods.com/cyberpunk2077/mods/4198) | Loads the phone contact (journal) + taunt text (localization) |
| [Mod Settings](https://www.nexusmods.com/cyberpunk2077/mods/4885) | **Required** — provides the in-game configuration menu |

## Installation (manual)

Extract the release archive into your Cyberpunk 2077 install folder so the files land here:

```
Cyberpunk 2077/
├── archive/pc/mod/BowieKnife99.archive
├── archive/pc/mod/BowieKnife99.archive.xl
└── r6/scripts/bowieknife99/bowieknife99.reds
```

Launch the game. Open **Settings → Mod Settings → Bowie Knife99** to tune behavior. Drive around and wait —
or crank "Attack chance" up and "Check interval" down to trigger it fast.

## Configuration

All settings live under **Mod Settings → Bowie Knife99**:

- **Enable mod** — master on/off.
- **Show debug HUD** — on-screen lines (ram start, attacker pick counts, SMS status); off for normal play.
- **Behavior →** Attack chance, Check interval (s), Cooldown (checks), Pursuit timeout (s), max attacker
  distance, max height difference, and ram strength.

## Build from source

The mod is a standard [WolvenKit](https://github.com/WolvenKit/WolvenKit) project.

- `source/archive/mod/bowieknife99/…` — the CR2W journal + onscreens that pack into `BowieKnife99.archive`.
- `source/resources/…` — files installed verbatim to the game root (`r6/scripts/bowieknife99/bowieknife99.reds`,
  `archive/pc/mod/BowieKnife99.archive.xl`).
- `tools/gen_bowie_sms.py` — generates the SMS journal + localization sources (the 100 taunts).

To rebuild the SMS data from scratch:

1. `python tools/gen_bowie_sms.py` — writes `bowieknife99.journal.json` and `bowieknife99_onscreens.json.json`
   into `source/archive/mod/bowieknife99/…`.
2. In WolvenKit, **Import** (or convert from JSON) those two files to produce the CR2W
   `bowieknife99.journal` / `bowieknife99_onscreens.json` binaries alongside them.
3. **Build/Pack** the project → `packed/archive/pc/mod/BowieKnife99.archive`, then install (the `.reds` and
   `.xl` from `source/resources` install to the game root).

> Note: editing the taunts only touches the localization/journal sources; the gameplay logic
> (`bowieknife99.reds`) is independent.

## Credits

Made by **Maxgoods**. Meme origin: the Forza "bowie knife99" rammer.

## License

[MIT](LICENSE).
