#!/usr/bin/env python3
r"""One-command rebuild of BowieKnife99's localized SMS archive + release zip.

    python tools/build_sms.py

Run this after editing the translations in tools/taunts/<locale>.txt. Pipeline:
  1. gen_bowie_sms.py        -> journal + per-locale onscreens CR2W-JSON sources
  2. WolvenKit convert       -> CR2W (.json) for the journal + every onscreens locale
  3. WolvenKit pack          -> BowieKnife99.archive (clean staging; CR2W only)
  4. deploy                  -> copy archive + .archive.xl into the game
  5. zip + verify            -> rebuild BowieKnife99-<version>.zip, byte-check vs the live install

Paths come from .env (same file as extract_vo.py): CP2077_DIR, WOLVENKIT_CLI.
Locales are auto-discovered from source/archive/.../onscreens/<locale>/. Adding a BRAND-NEW language
also needs its LOCALES entry in gen_bowie_sms.py and a line in BowieKnife99.archive.xl (one-time).
"""
import os, re, sys, shutil, zipfile, hashlib, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
PROJ = os.path.normpath(os.path.join(HERE, ".."))
ENV_PATH = os.path.join(PROJ, ".env")
ARCH_SRC = os.path.join(PROJ, "source", "archive", "mod", "bowieknife99")
ONSCREENS_SRC = os.path.join(ARCH_SRC, "onscreens")
RES = os.path.join(PROJ, "source", "resources")
XL_REL = os.path.join("archive", "pc", "mod", "BowieKnife99.archive.xl")
ARCHIVE_REL = os.path.join("archive", "pc", "mod", "BowieKnife99.archive")


def load_env(path):
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
    p = p.strip()
    if len(p) >= 2 and p[1] == ":":
        return "/mnt/" + p[0].lower() + p[2:].replace("\\", "/")
    return p


def to_win(p):
    if p.startswith("/mnt/") and len(p) > 6:
        return f"{p[5].upper()}:{p[6:].replace('/', chr(92))}"
    return p


def project_version():
    with open(os.path.join(PROJ, "BowieKnife99.cpmodproj"), encoding="utf-8") as f:
        m = re.search(r"<Version>([^<]+)</Version>", f.read())
    return m.group(1) if m else "0.0.0"


def main():
    env = load_env(ENV_PATH)
    if not env.get("CP2077_DIR") or not env.get("WOLVENKIT_CLI"):
        print("ERROR: CP2077_DIR / WOLVENKIT_CLI missing. Copy .env.example -> .env and fill them in.")
        sys.exit(1)
    game_wsl = to_wsl(env["CP2077_DIR"])
    wk = to_wsl(env["WOLVENKIT_CLI"])     # launch the Windows exe via its WSL mount path

    # 1) regenerate journal + per-locale onscreens sources
    print("[1/5] generating sources ...")
    subprocess.run([sys.executable, os.path.join(HERE, "gen_bowie_sms.py")], check=True)

    locales = sorted(d for d in os.listdir(ONSCREENS_SRC)
                     if os.path.isdir(os.path.join(ONSCREENS_SRC, d)))
    print("      locales:", ", ".join(locales))

    # 2) convert journal + each locale onscreens JSON -> CR2W (.json.json -> .json)
    print("[2/5] converting to CR2W ...")
    sources = [os.path.join(ARCH_SRC, "journal", "bowieknife99.journal.json")]
    sources += [os.path.join(ONSCREENS_SRC, loc, "bowieknife99_onscreens.json.json") for loc in locales]
    for src in sources:
        subprocess.run([wk, "convert", "deserialize", to_win(src)], check=True)

    # 3) pack a CLEAN staging tree (CR2W only) named BowieKnife99 -> BowieKnife99.archive
    print("[3/5] packing archive ...")
    build = os.path.join(PROJ, ".build")
    if os.path.isdir(build):
        shutil.rmtree(build)
    stage = os.path.join(build, "BowieKnife99")
    jdst = os.path.join(stage, "mod", "bowieknife99", "journal")
    os.makedirs(jdst)
    shutil.copy(os.path.join(ARCH_SRC, "journal", "bowieknife99.journal"), jdst)
    for loc in locales:
        odst = os.path.join(stage, "mod", "bowieknife99", "onscreens", loc)
        os.makedirs(odst)
        shutil.copy(os.path.join(ONSCREENS_SRC, loc, "bowieknife99_onscreens.json"), odst)
    subprocess.run([wk, "pack", to_win(stage), "-o", to_win(build)], check=True)
    archive = os.path.join(build, "BowieKnife99.archive")
    if not os.path.isfile(archive):
        print("ERROR: pack did not produce BowieKnife99.archive"); sys.exit(2)

    # 4) rebuild the release zip (source/resources + the freshly packed archive) — always
    print("[4/5] building release zip ...")
    ver = project_version()
    zip_path = os.path.join(PROJ, f"BowieKnife99-{ver}.zip")
    zstage = os.path.join(build, "zip")
    shutil.copytree(RES, zstage)
    os.makedirs(os.path.join(zstage, os.path.dirname(ARCHIVE_REL)), exist_ok=True)
    shutil.copy(archive, os.path.join(zstage, ARCHIVE_REL))
    entries = []
    for root, _, names in os.walk(zstage):
        for n in names:
            full = os.path.join(root, n)
            entries.append((full, os.path.relpath(full, zstage).replace(os.sep, "/")))
    entries.sort(key=lambda x: x[1])
    if os.path.isfile(zip_path):
        os.remove(zip_path)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for full, arc in entries:
            z.write(full, arc)
    print(f"      wrote {os.path.basename(zip_path)} ({len(entries)} files)")

    # 5) deploy into the game (BEST-EFFORT: the archive is locked while the game is running),
    #    then byte-verify the zip against the live install if the deploy went through.
    print("[5/5] deploying to game ...")
    gmod = os.path.join(game_wsl, "archive", "pc", "mod")
    try:
        shutil.copy(archive, os.path.join(gmod, "BowieKnife99.archive"))
        shutil.copy(os.path.join(RES, XL_REL), os.path.join(gmod, "BowieKnife99.archive.xl"))
        deployed = True
    except (PermissionError, OSError) as e:
        deployed = False
        print(f"      WARN: could not write the game's archive ({e.__class__.__name__}). Cyberpunk 2077 is "
              f"likely RUNNING (it locks installed archives). The zip is built either way — close the game "
              f"and re-run to deploy, or just reinstall the zip.")

    if deployed:
        ok = True
        with zipfile.ZipFile(zip_path) as z:
            for arc in z.namelist():
                gp = os.path.join(game_wsl, arc)
                same = os.path.isfile(gp) and (hashlib.sha256(z.read(arc)).digest()
                                               == hashlib.sha256(open(gp, "rb").read()).digest())
                if not same:
                    ok = False
                    print("  MISMATCH/missing vs live:", arc)
        print("      deployed +", "verified byte-identical to live install ✓" if ok else "DIFFERS vs live — review above")

    shutil.rmtree(build, ignore_errors=True)
    print("done.")


if __name__ == "__main__":
    main()
