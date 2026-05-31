#!/usr/bin/env python3
r"""Extract a Cyberpunk 2077 spoken VO line to a .wav for the BowieKnife99 Audioware mod.

Run from WSL (it drives the Windows WolvenKit + vgmstream CLIs).

    python tools/extract_vo.py <locale> [vo_name]

    <locale>    in-game voice code: en-us, fr-fr, de-de, it-it, pl-pl, ru-ru, pt-br,
                jp-jp, kr-kr, zh-cn, zh-tw, es-es, es-mx
                (the matching VOICE pack must be installed for that language!)
    [vo_name]   VO file stem incl. hash. Defaults to the ram taunt:
                delamain_angry_sq025_f_18019abc0d62a000

Setup (once): copy `.env.example` (project root) to `.env` and set the paths for your machine.

Writes  source/resources/r6/audioware/BowieKnife99/<Locale>.wav   (e.g. fr-FR.wav)

Pipeline: WolvenKit.CLI `extract` (pulls the .wem) -> vgmstream-cli (.wem -> .wav).
The same VO path/name exists in every language's voice archive, so only <locale> changes.

After extracting a NEW language you still must wire it up once:
  1) add an sfx entry to r6/audioware/BowieKnife99/bowieknife99.yml, e.g.
         bowieknife99_beep_de:
           file: ./de-DE.wav
  2) add a branch in RamSoundEvent() in bowieknife99.reds:
         if Equals(lang, n"de-de") { return n"bowieknife99_beep_de"; }
  3) copy the new .wav into the game's r6/audioware/BowieKnife99/ and rebuild the release zip.
"""
import os, sys, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ENV_PATH = os.path.join(HERE, "..", ".env")

# localization/voice code -> voice-archive segment (lang_<seg>_voice.archive)
ARCHIVE_SEG = {
    "en-us": "en", "fr-fr": "fr", "de-de": "de", "it-it": "it", "pl-pl": "pl",
    "ru-ru": "ru", "pt-br": "pt", "jp-jp": "ja", "kr-kr": "ko",
    "zh-cn": "zh-cn", "zh-tw": "zh-tw", "es-es": "es-es", "es-mx": "es-mx",
    # NB: Japanese/Korean use in-game folder+voice codes jp-jp / kr-kr, but their
    # archives are lang_ja_voice / lang_ko_voice (hence the seg differs from the key).
}
DEFAULT_VO = "delamain_angry_sq025_f_18019abc0d62a000"


def load_env(path):
    """Minimal KEY=VALUE .env reader (no external deps)."""
    cfg = {}
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, _, v = line.partition("=")
                    cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg


def to_wsl(p):
    r"""Windows path -> WSL mount, e.g. D:\Games\X -> /mnt/d/Games/X."""
    p = p.strip()
    if len(p) >= 2 and p[1] == ":":
        return "/mnt/" + p[0].lower() + p[2:].replace("\\", "/")
    return p


def to_win(p):
    r"""WSL mount -> Windows path, e.g. /mnt/c/foo -> C:\foo."""
    if p.startswith("/mnt/") and len(p) > 6:
        return f"{p[5].upper()}:{p[6:].replace('/', chr(92))}"
    return p


def out_name(locale):
    a, _, b = locale.partition("-")
    return f"{a.lower()}-{b.upper()}.wav" if b else f"{a}.wav"


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    env = load_env(ENV_PATH)

    def need(key):
        v = env.get(key)
        if not v:
            print(f"ERROR: '{key}' is not set. Copy `.env.example` to `.env` at the project root and "
                  f"fill in your paths.\n  (.env expected at: {os.path.normpath(ENV_PATH)})")
            sys.exit(1)
        return v

    # .env holds Windows-style paths; we derive WSL mount paths for launching exes / file ops.
    game_win = need("CP2077_DIR")
    wk_cli   = to_wsl(need("WOLVENKIT_CLI"))   # exes are launched via their WSL mount path
    vgm_cli  = to_wsl(need("VGMSTREAM_CLI"))
    tmp_win  = need("VO_TMP")
    game_wsl = to_wsl(game_win)
    tmp_wsl  = to_wsl(tmp_win)
    mod_audio = os.path.join(HERE, "..", "source", "resources", "r6", "audioware", "BowieKnife99")

    locale = sys.argv[1].lower()
    vo = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_VO
    seg = ARCHIVE_SEG.get(locale)
    if not seg:
        print(f"Unknown locale '{locale}'. Known: {', '.join(sorted(ARCHIVE_SEG))}")
        sys.exit(1)

    archive_win = rf"{game_win}\archive\pc\content\lang_{seg}_voice.archive"
    archive_wsl = f"{game_wsl}/archive/pc/content/lang_{seg}_voice.archive"
    if not os.path.isfile(archive_wsl):
        print(f"  ERROR: lang_{seg}_voice.archive not found — the {locale} VOICE pack isn't installed.\n"
              f"  Install it (Steam: game Properties -> Language; GOG: language selector), then retry.")
        sys.exit(2)

    os.makedirs(tmp_wsl, exist_ok=True)
    # Trust only this locale's EXACT extracted path — never a recursive search (that once matched a
    # stale clip from another language). Clear any prior extraction so we can't reuse it.
    wem_wsl = f"{tmp_wsl}/base/localization/{locale}/vo/{vo}.wem"
    if os.path.exists(wem_wsl):
        os.remove(wem_wsl)

    print(f"[1/2] extracting '{vo}' from lang_{seg}_voice.archive ...")
    subprocess.run([wk_cli, "extract", archive_win, "--pattern", f"*{vo}*", "-o", tmp_win], text=True)

    if not os.path.isfile(wem_wsl):
        print(f"  ERROR: '{vo}.wem' not found under {locale}\\vo after extract.\n"
              f"  Check the VO name/hash for this language.")
        sys.exit(2)

    out_wsl = os.path.normpath(os.path.join(mod_audio, out_name(locale)))
    print(f"[2/2] decoding -> {out_wsl}")
    subprocess.run([vgm_cli, "-o", to_win(out_wsl), to_win(wem_wsl)], text=True)

    if os.path.isfile(out_wsl):
        print(f"\nOK: wrote {out_name(locale)} ({os.path.getsize(out_wsl)} bytes).")
        if locale != "en-us":
            print("NOTE: if this is a NEW language, wire it into bowieknife99.yml + RamSoundEvent() "
                  "(see the header of this script).")
    else:
        print("  ERROR: vgmstream did not produce the .wav.")
        sys.exit(3)


if __name__ == "__main__":
    main()
