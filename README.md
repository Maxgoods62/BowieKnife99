# Bowie Knife99

A Cyberpunk 2077 meme mod inspired by the Forza **"bowie knife99"** legend. While you drive, on a random
timer an ordinary traffic car turns hostile, aggressively rams your vehicle, and then is reliably called
off — and moments later your phone buzzes with a taunt from a contact named **Bowie Knife99**.

## Features

- **Hijacks a real traffic car** (it already has a live AI driver) and sends it after you — no spawning or
  teleporting, so the chase always looks natural.
- **Picks a random nearby car** within a configurable distance and a height window (so a car on a bridge
  overhead or a road below never gets chosen). By default any direction is eligible — oncoming, cross, or
  rear traffic — but a toggle can restrict it to cars *behind* you for a more natural-looking chase.
- **Aggressive ramming** with a close-range lunge, then a forceful, reliable break-off (the attacker flees).
- **Real in-phone SMS**: on a successful hit, the **Bowie Knife99** contact texts you one of **100** rotating
  taunts.
- **Taunt voice line on impact**: when Bowie rams you he yells at you — localized across **10 languages** (English, French, German, Spanish, Italian, Polish, Russian, Chinese,
  Japanese + Korean), with
  English as the fallback for other languages) and **3D-positioned** from the attacker's car. Toggle it under
  **Settings → Audio**.
- **Fully localized text**: the **100 SMS taunts and the entire Mod Settings menu** are translated into the
  same **10 languages** (English, French, German, Spanish, Italian, Polish, Russian, Chinese, Japanese,
  Korean). Text follows your game's **text/subtitle language** — independent of the voice-language audio pick
  above — and falls back to English for any other language.
- **Fully configurable** live via the in-game **Mod Settings** menu — attack chance, check interval, cooldown,
  pursuit timeout, max distance, height limit, attack direction (behind-only or any direction), ram strength,
  debug HUD, and an on/off toggle.

## Requirements

| Dependency | Why |
|---|---|
| [RED4ext](https://www.nexusmods.com/cyberpunk2077/mods/2380) | Base loader for the plugins below |
| [REDscript](https://www.nexusmods.com/cyberpunk2077/mods/1511) | Compiles the mod's gameplay logic (`bowieknife99.reds`) |
| [ArchiveXL](https://www.nexusmods.com/cyberpunk2077/mods/4198) | Loads the phone contact (journal) + taunt text (localization) |
| [Mod Settings](https://www.nexusmods.com/cyberpunk2077/mods/4885) | **Required** — provides the in-game configuration menu |
| [Audioware](https://www.nexusmods.com/cyberpunk2077/mods/12001) | **Required** — plays the ram-impact voice line |
| [Codeware](https://www.nexusmods.com/cyberpunk2077/mods/7780) | **Required** — engine bindings used by Audioware (voice-language lookup) |

## Installation (manual)

Extract the release archive into your Cyberpunk 2077 install folder so the files land here:

```
Cyberpunk 2077/
├── archive/pc/mod/BowieKnife99.archive
├── archive/pc/mod/BowieKnife99.archive.xl
├── r6/scripts/bowieknife99/bowieknife99.reds
└── r6/audioware/BowieKnife99/          (manifest + 10 per-language taunt clips)
```

Launch the game. Open **Settings → Mod Settings → Bowie Knife99** to tune behavior. Drive around and wait —
or crank "Attack chance" up and "Check interval" down to trigger it fast.

## Configuration

All settings live under **Mod Settings → Bowie Knife99**:

- **Enable mod** — master on/off.
- **Show debug HUD** — on-screen lines (ram start, attacker pick counts, SMS status); off for normal play.
- **Behavior →** Attack chance, Check interval (s), Cooldown (checks), Pursuit timeout (s), max attacker
  distance, max height difference, and ram strength.
- **Audio →** **Play taunt sound on ram** — toggle the impact voice line on/off.

## Build from source

The mod is a standard [WolvenKit](https://github.com/WolvenKit/WolvenKit) project.

- `source/archive/mod/bowieknife99/…` — the CR2W journal + onscreens that pack into `BowieKnife99.archive`.
- `source/resources/…` — files installed verbatim to the game root (`r6/scripts/bowieknife99/bowieknife99.reds`,
  `archive/pc/mod/BowieKnife99.archive.xl`, and `r6/audioware/BowieKnife99/` — the Audioware manifest + taunt
  `.wav` clips, picked by voice language in `bowieknife99.reds`).
- `tools/gen_bowie_sms.py` — generates the SMS journal + per-locale localization (the 100 taunts **and** the
  Mod Settings labels, auto-extracted from the `.reds`). Translate by filling `tools/taunts/<locale>.txt` and
  `tools/settings/<locale>.txt` (English-filled templates; blank line = keep English).
- `tools/build_sms.py` — one command: regenerate → compile CR2W → pack `BowieKnife99.archive` → deploy →
  rebuild the release zip. Run it after editing any translation file.
- `tools/extract_vo.py <locale> [vo_name]` — extracts a game VO line in any installed language to
  `r6/audioware/BowieKnife99/<Locale>.wav` (WolvenKit `extract` → vgmstream decode). e.g.
  `python tools/extract_vo.py fr-fr` for the French taunt. New languages also need a `bowieknife99.yml`
  + `RamSoundEvent()` entry (see the script header). **First**: copy `.env.example` → `.env` and set your
  CP2077 / WolvenKit / vgmstream paths (the script reads them from there; `.env` is gitignored).

To rebuild the SMS data from scratch:

1. `python tools/gen_bowie_sms.py` — writes `bowieknife99.journal.json` and `bowieknife99_onscreens.json.json`
   into `source/archive/mod/bowieknife99/…`.
2. In WolvenKit, **Import** (or convert from JSON) those two files to produce the CR2W
   `bowieknife99.journal` / `bowieknife99_onscreens.json` binaries alongside them.
3. **Build/Pack** the project → `packed/archive/pc/mod/BowieKnife99.archive`, then install (the `.reds` and
   `.xl` from `source/resources` install to the game root).

> Note: editing the taunts only touches the localization/journal sources; the gameplay logic
> (`bowieknife99.reds`) is independent.

## Changelog

### 0.1.0
- **New: ram-impact taunt voice line.** Bowie now yells at you on a confirmed hit — localized (English,
  10 languages — English, French, German, Spanish, Italian, Polish, Russian, Chinese, Japanese, Korean,
  English fallback for the rest) and spatialized from the attacker's car. Toggle under **Settings → Audio**.
- **New: localized text.** The 100 SMS taunts **and** the Mod Settings menu are now translated into the same
  10 languages. SMS/menu text follows your game's **text/subtitle language** (the audio follows the separate
  voice language); any other language falls back to English.
- Adds two dependencies for the audio: **Audioware** (plays the clip) and **Codeware** (its engine bindings).

### 0.0.2
- Earlier release: hijack-and-ram behavior, reliable break-off, in-phone SMS taunts, full Mod Settings config.

## Credits

Made by **Maxgoods**. Meme origin: the Forza "bowie knife99" rammer.
Audio playback via **Audioware** + **Codeware**. Ram voice clips are Cyberpunk 2077 game audio
(© CD PROJEKT RED), extracted with [WolvenKit](https://github.com/WolvenKit/WolvenKit) +
[vgmstream](https://github.com/vgmstream/vgmstream).

## License

[MIT](LICENSE).
