# Squizzcap - Death Recap

A death recap for World of Warcraft Retail, built for patch 12.1.

The moment you die, Squizzcap tells you what killed you, how hard it hit and
how fast you went down - then lets you dig into every hit, and look back over
every death from a whole key or raid night.

**[Download on CurseForge](https://www.curseforge.com/projects/1713974)** ·
[Changelog](CHANGELOG.txt)

---

## Features

**At a glance**
- A compact summary pops up when you die: the killing blow, its damage and
  how fast you went from healthy to dead. It stays through release,
  resurrection and loading screens until you close it
- Click **Details** for the full recap, or set the full window to open
  straight away

**The full recap**
- **Killed By** - the spell, who cast it, the damage and overkill, and
  Blizzard's own *Avoidable* and *Deadly* markers
- **How fast** you went down (burst or worn down), total damage taken, and
  how much was absorbed, resisted or blocked
- **Your health** as a graph over the last 5 seconds, one dot per hit sized
  by damage, rising in green exactly when each heal landed. Hover a dot for
  the spell's tooltip, click it to jump to that hit
- **Healing received** beside damage taken, and what landed between each pair
  of hits
- **What hit you** - the damage split by spell in its school colour

**Digging in**
- **Hits** - every hit, newest first; click one for health before and after,
  absorbed, resisted, blocked and overkill
- **Sources** - each enemy and the spells they hit you with
- **This fight** - everything that hit you over the whole pull, not just the
  last few seconds: each spell, who cast it, how much it did and its share,
  with Blizzard's Avoidable and Deadly markers and how much of the fight's
  damage was avoidable
- **All deaths** - every death saved for your character, grouped by dungeon
  or raid visit (Mythic+ runs show their key level). Each run is summed up:
  deaths from an avoidable killing blow, avoidable hits taken, and anything
  that killed you more than once
- Keep the last 5, 10, 20 or 50 runs, delete a run or clear everything, or
  start fresh with each Mythic+ key

**Sharing**
- Link Blizzard's death recap into chat, or post a one-line summary to your
  group

## How the numbers work

Everything comes from Blizzard's own death recap (`C_DeathRecap`), so the
numbers are the game's, not reconstructed from the combat log (which addons
can no longer read). That recap holds the **last 10 hits** before a death.

The health graph is exact at every hit - the game records your health as each
one lands. Healing you received comes from the game's own heal feed and is
placed exactly when each heal landed (overhealing included, and the figure
says so).

In a burst, 10 hits can be well under a second, so Squizzcap reaches back 5
seconds with the older hits from the game's hit feed. The game names no spell
or source for those and can miss or add one in a burst, so they are marked
with ~ as approximate. The recap's own 10 hits, killing blow included, are
never changed.

**This fight** is read from Blizzard's damage meter the moment you die. If the
game is still hiding it then, Squizzcap tries again over the next few seconds;
`/squizzcap fight` tells you why a death has no This fight tab.

If the game ever hides a recap's numbers from addons, Squizzcap still shows
the killing blow and every hit, and switches off the parts that need
calculating rather than guessing.

## Installing

Install from [CurseForge](https://www.curseforge.com/projects/1713974), or
manually: download this repository and drop the `Squizzcap` folder into

```
World of Warcraft\_retail_\Interface\AddOns\
```

Requires WoW Retail 12.1 (interface 120100). No libraries or other addons
needed.

## Commands

| Command | What it does |
|---------|--------------|
| `/squizzcap` or `/scr` | Open the options |
| `/squizzcap show` | Open your last death (the All deaths tab has the rest) |
| `/squizzcap toast` | Show your last death as the compact summary |
| `/squizzcap fight` | Why your last death has (or lacks) a This fight tab |
| `/squizzcap notes` | What's new in this version |

## Bugs and requests

Please open an [issue](../../issues). A copy of the error text (BugSack or
similar) and where you died - open world, dungeon, Mythic+ or raid - helps a
lot.

## Credits

Uses Blizzard's death recap data and art (the tombstone, Avoidable and Deadly
icons). Headings and numbers are set in **Barlow** by the Barlow Project
Authors, bundled under the SIL Open Font License
([Media/Fonts/OFL.txt](Media/Fonts/OFL.txt)).

## Support

If you enjoy using Squizzcap, consider supporting development on
[Ko-fi](https://ko-fi.com/squizz) ❤️

## More addons by Squizz

- **[SquizzFrames](https://www.curseforge.com/projects/1649203)** — party, raid, pet and unit frames with a full indicator system, click-casting and a tank tracker
- **[Squizzumables](https://www.curseforge.com/projects/1483099)** — one-click reminders for food, flasks, oils and class buffs, plus raid tools and a restyled Cooldown Manager
- **[SquizzTalents](https://www.curseforge.com/projects/1705647)** — all your talent builds in one list, with a reminder when your build doesn't match the content
- **[DPS Report](https://www.curseforge.com/projects/1504877)** — a lightweight damage meter with spell breakdowns and an end-of-key MVP summary
- **[Avatar Continued](https://www.curseforge.com/projects/1533608)** — your character model on screen as part of your UI
- **[KSLBestDungeon](https://www.curseforge.com/projects/1599575)** — ranks Mythic+ dungeons by how many of your KeystoneLoot favorites drop there

## License

[MIT](LICENSE). The bundled fonts remain under the
[SIL Open Font License](Media/Fonts/OFL.txt).
