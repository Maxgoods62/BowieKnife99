#!/usr/bin/env python3
"""Generate BowieKnife SMS journal + onscreens CR2W-JSON sources.
Mirrors the proven adding_my_mod / JRME shapes:
- journal: contacts/bowie/taunts/msg<N>  (realPath used by ChangeEntryState)
- onscreens: secondaryKey == the journal text.value string (proven resolution path)
"""
import json, os, re

# Write the WolvenKit-JSON sources into the project's source/archive tree (this script lives in tools/).
# `convert_from_json` then yields the CR2W binaries (bowieknife99.journal / bowieknife99_onscreens.json)
# alongside, which WolvenKit packs into BowieKnife99.archive.
OUT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "source", "archive"))
JDIR = os.path.join(OUT, "mod", "bowieknife99", "journal")
ODIR = os.path.join(OUT, "mod", "bowieknife99", "onscreens", "en-us")
os.makedirs(JDIR, exist_ok=True)
os.makedirs(ODIR, exist_ok=True)

CONTACT_ID   = "bowie"
CONVO_ID     = "taunts"
CONTACT_NAME_KEY = "bowie_contact_name"
CONTACT_NAME = "Bowie Knife99"
BLANK_KEY = "bowie_blank"   # resolves to "" so the conversation has no valid title (preview = last msg)
AVATAR       = "PhoneAvatars.Avatar_Vik"   # vanilla, known-valid; cosmetic, swappable

TAUNTS = [
    "gg ez",
    "bowie knife99 strikes again",
    "skill issue",
    "you just got bowie'd",
    "should've taken the metro, choom",
    "ramming speed > your driving",
    "that's gonna leave a mark",
    "catch me if you can, V",
    "insurance won't cover this one",
    "another one for the highlight reel",
    "ratio + you fell off",
    "L + ragequit",
    "no respawns out here, choom",
    "0 deaths? not anymore",
    "respawn timer starts now",
    "uninstall, choom",
    "touch grass... or guardrail",
    "K.O. — flawless victory",
    "speedrun any% on your bumper",
    "no scope, all bumper",
    "tell Vik I said hi",
    "this one's on Delamain's tab",
    "NCPD won't even file the report",
    "Trauma Team's en route — they're billing you",
    "eddies can't fix that paint job",
    "your ripperdoc do cars too?",
    "braindance this crash later, it slaps",
    "should've bought the Rayfield",
    "Arasaka builds better bumpers",
    "Night City traffic, am I right",
    "GPS says: pull over",
    "friendly reminder to wear your seatbelt",
    "tip: the brakes are the other pedal",
    "drive safe out there, choom",
    "have you tried not being in my way?",
    "have you considered public transit?",
    "rate your ride 5 stars?",
    "thanks for playing, drive again soon",
    "you dropped this: your bumper",
    "this lane was reserved, sorry",
    "i know where you parked",
    "see you at the next intersection",
    "the road belongs to me now",
    "run. it's funnier when you run",
    "next time i aim for the engine",
    "there is no outrunning bowie knife99",
    "check your mirrors",
    "metal meets metal. you lose",
    "every car is my car",
    "you can't merge away from this",
    "ez clap",
    "down bad, down a bumper",
    "mald harder, choom",
    "get rekt, scrub",
    "1v1 me at the next light",
    "GG no re",
    "outplayed, outdriven",
    "sit down, you're done",
    "hold this L for me",
    "my KDA > your insurance premium",
    "one-tap on your trunk",
    "tutorial island called, you're late",
    "lag? no. me? yes.",
    "Wakako says hi",
    "even Johnny's laughing at this",
    "that's a Misty tarot card right there",
    "Maelstrom drives better than you",
    "should've taken a Delamain cab",
    "your chrome won't save your fender",
    "Watson traffic court is closed, sorry",
    "the Aldecaldos would've dodged that",
    "Kerry wrote a song about your driving",
    "Afterlife's got a drink named after this crash",
    "6th Street says nice parking",
    "even a flathead drives cleaner",
    "just a heads up, your bumper left",
    "reminder: green means go, not stop",
    "here's a tip — yield to me",
    "your warranty just expired",
    "might wanna get that looked at",
    "customer satisfaction: guaranteed",
    "we value your feedback (we don't)",
    "please remain calm and pull over",
    "this has been a friendly demonstration",
    "you've been selected for a free ramming",
    "don't forget to like and subscribe",
    "have a nice day, genuinely",
    "i'm already behind you",
    "don't bother with the rearview",
    "the next one's worse",
    "you felt that one, didn't you",
    "there's no garage deep enough",
    "i drive where you sleep",
    "brake all you want",
    "i've got all night, choom",
    "your engine block is mine",
    "keep driving. i dare you",
    "every red light is mine",
    "i never miss twice",
    "say goodnight to your suspension",
]

def fnv1a64(s):
    # CP2077 LocKey ID = FNV-1a 64-bit of the key string. GetText() (used by the phone's contact-row
    # preview) resolves text via this numeric id (the localizationString's unk1), so unk1 + the
    # onscreens primaryKey must both equal this hash or the preview shows a raw LocKey#<id>.
    h = 0xCBF29CE484222325
    for b in s.encode("utf-8"):
        h = ((h ^ b) * 0x100000001B3) & 0xFFFFFFFFFFFFFFFF
    return str(h)

def header(name):
    return {
        "WolvenKitVersion": "8.18.0",
        "WKitJsonVersion": "0.0.9",
        "GameVersion": 2310,
        "DataType": "CR2W",
        "ArchiveFileName": name,
    }

def tdbid_str(v):
    return {"$type": "TweakDBID", "$storage": "string", "$value": v}

def tdbid_zero():
    return {"$type": "TweakDBID", "$storage": "uint64", "$value": "0"}

# ---- journal ----
hid = [0]
def nh():
    h = str(hid[0]); hid[0] += 1; return h

def msg(mid, key):
    return {
        "HandleId": nh(),
        "Data": {
            "$type": "gameJournalPhoneMessage",
            "attachment": None,
            "delay": 0,
            "id": mid,
            "imageId": tdbid_zero(),
            "isQuestImportant": 0,
            "journalEntryOverrideDataList": [],
            "sender": "NPC",
            "text": {"unk1": fnv1a64(key), "value": key},   # unk1 = LocKey id so GetText() resolves
        },
    }

root_h = nh()      # 0 root folder
prim_h = nh()      # 1 primary folder
contact_h = nh()   # 2 contact
convo_h = nh()     # 3 conversation
messages = [msg(f"msg{i+1}", f"bowie_taunt_{i+1}") for i in range(len(TAUNTS))]

journal = {
    "Header": header("bowieknife99.journal"),
    "Data": {
        "Version": 195,
        "BuildVersion": 0,
        "RootChunk": {
            "$type": "gameJournalResource",
            "cookingPlatform": "PLATFORM_None",
            "entry": {
                "HandleId": root_h,
                "Data": {
                    "$type": "gameJournalRootFolderEntry",
                    "descriptor": {
                        "DepotPath": {"$type": "ResourcePath", "$storage": "uint64", "$value": "0"},
                        "Flags": "Soft",
                    },
                    "entries": [{
                        "HandleId": prim_h,
                        "Data": {
                            "$type": "gameJournalPrimaryFolderEntry",
                            "id": "contacts",
                            "entries": [{
                                "HandleId": contact_h,
                                "Data": {
                                    "$type": "gameJournalContact",
                                    "id": CONTACT_ID,
                                    "avatarID": tdbid_str(AVATAR),
                                    "isCallableDefault": 0,
                                    "name": {"unk1": fnv1a64(CONTACT_NAME_KEY), "value": CONTACT_NAME_KEY},
                                    "type": "Caller",
                                    "useFlatMessageLayout": 1,
                                    "entries": [{
                                        "HandleId": convo_h,
                                        "Data": {
                                            "$type": "gameJournalPhoneConversation",
                                            "id": CONVO_ID,
                                            # Title resolves (via unk1 -> onscreens primaryKey) to an
                                            # EMPTY string, so IsStringValid(GetTitle())==false ->
                                            # hasValidTitle==false -> the contact-row preview falls back
                                            # to the last MESSAGE text. (unk1="0"+value="" instead hashes
                                            # "" to a valid LocKey#... and wrongly shows that as the title.)
                                            "title": {"unk1": fnv1a64(BLANK_KEY), "value": BLANK_KEY},
                                            "entries": messages,
                                        },
                                    }],
                                },
                            }],
                        },
                    }],
                },
            },
        },
    },
}

# ---- onscreens ----
def osentry(key, text):
    return {
        "$type": "localizationPersistenceOnScreenEntry",
        "femaleVariant": text,
        "maleVariant": text,
        "primaryKey": fnv1a64(key),   # numeric LocKey id -> lets GetText()/numeric resolution find it
        "secondaryKey": key,
    }

os_entries = [osentry(CONTACT_NAME_KEY, CONTACT_NAME), osentry(BLANK_KEY, "")]
os_entries += [osentry(f"bowie_taunt_{i+1}", t) for i, t in enumerate(TAUNTS)]

onscreens = {
    "Header": header("bowieknife99_onscreens.json"),
    "Data": {
        "Version": 195,
        "BuildVersion": 0,
        "RootChunk": {
            "$type": "JsonResource",
            "cookingPlatform": "PLATFORM_None",
            "root": {
                "HandleId": "0",
                "Data": {
                    "$type": "localizationPersistenceOnScreenEntries",
                    "entries": os_entries,
                },
            },
        },
    },
}

jpath = os.path.join(JDIR, "bowieknife99.journal.json")
opath = os.path.join(ODIR, "bowieknife99_onscreens.json.json")
with open(jpath, "w", encoding="utf-8") as f:
    json.dump(journal, f, indent=2, ensure_ascii=False)
with open(opath, "w", encoding="utf-8") as f:
    json.dump(onscreens, f, indent=2, ensure_ascii=False)

# ---- keep the gameplay script's MsgCount() in lockstep with len(TAUNTS) ----
# SendBowieSMS() rolls msg1..msgMsgCount(), so this literal MUST equal the number of authored
# messages. Stamping it here makes this generator the single source of truth: editing TAUNTS and
# re-running can never silently desync the script (too-high -> "entry NOT found"; too-low -> dead
# taunts that never fire). Matches `return <N>;` on the MsgCount() line; leaves the comment intact.
REDS = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                     "..", "source", "resources", "r6", "scripts", "bowieknife99", "bowieknife99.reds"))
def stamp_msgcount(path, n):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    new, hits = re.subn(r"(func MsgCount\(\)\s*->\s*Int32\s*\{\s*return\s+)\d+(\s*;)",
                        r"\g<1>%d\g<2>" % n, src)
    if hits != 1:
        raise SystemExit("stamp_msgcount: expected exactly 1 MsgCount() match in %s, found %d" % (path, hits))
    if new != src:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new)
        return True
    return False

changed = stamp_msgcount(REDS, len(TAUNTS))

print("wrote", jpath)
print("wrote", opath)
print("MsgCount() in bowieknife99.reds:", "updated to" if changed else "already", len(TAUNTS))
print("messages:", len(TAUNTS), "realPaths: contacts/%s/%s/msg1..msg%d" % (CONTACT_ID, CONVO_ID, len(TAUNTS)))
