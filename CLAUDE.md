# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

**Squizzcap** is a World of Warcraft (Retail 12.1) death recap addon: the moment you die it shows what
killed you (a compact toast by default, or the full window), and every death is saved per character,
grouped into runs, for looking back over a key or a raid night. No libraries.

- **Interface**: `120100, 120105`. **CurseForge**: project `1713974`. **GitHub**: SquizzCheeze/Squizzcap.
- **SavedVariables**: `SquizzcapDB` (per character: settings AND saved runs) and `SquizzcapAccountDB`
  (account-wide: only the welcome window's `lastSeenVersion`).
- **Slash**: `/squizzcap` or `/scr`.
- Latest release: **V1.2.0 (2026-09-29)**.

## Files (load order from the TOC)

| File | Purpose |
|------|---------|
| `Data.lua` | Reads `C_DeathRecap` into a plain model (`Data.Read`), extends it with the hit/heal log, and reads the damage meter's This fight (`Data.ReadFight`). Header comment documents Blizzard's recap field meanings -- read it first |
| `Window.lua` | The toast and the full window: title, card, stats, health graph strip, tabs (`TABS`: Hits, Sources, This fight, All deaths), share buttons. `Window.HistoryChanged()` redraws an open window |
| `Squizzcap.lua` | Settings (`defaults`, `Backfill`), options panel, runs, the death event, slash commands |
| `Welcome.lua` | First-run greeting + per-version notes. `RELEASE_NOTES` keyed by the TOC Version, THREE-part (`"1.2.0"`) -- adding an entry is a release step. Ported from SquizzTalents |

## Development

- `/reload` picks up every change, TOC included. Never tell the user to restart or relog.
- Static check: the `wowlua_ls` CLI (see SquizzFrames' CLAUDE.md, "Static checks") and Squizzumables'
  `.claude/check-*.pl` / `check-balance.awk` scripts (one file per awk run, quote every path).
- Never write code containing a backslash, `%` or `$` through sed/perl; use the Edit/Write tools.

## Rules this addon lives by

- **Secrets.** Nothing compares, measures or does arithmetic on a value that might be secret; each is
  probed first (`Data.IsSecret`). A recap with any secret field is flagged `model.secret`: the window
  hands the raw values to widget setters and switches every calculated section off.
- **SavedVariables must never receive a secret**, so a hidden recap is saved as a **stub** (`when`,
  `zone`, nothing else) and the live model kept in a weak table for this session
  (`Saveable` / `addon.LiveModel(stub)`). Anything walking saved deaths must handle `m.stub`.
- **The recap's own 10 hits are exact and never altered** (killing blow included). Recap events come back
  NEWEST FIRST; `currentHP` is health when the hit landed (before it).
- **`UNIT_COMBAT` heals are exact, hits are not.** Heals (overheal included) are placed between recap
  hits for the graph and the Healing Received figure. Logged HITS miss the killing blow, drop hits in
  bursts, include phantom hits and arrive up to 1.4s late, so the hits added before the recap's oldest
  (`ExtendHits`, back to 5s, aligned by `AlignLog` / `PairRecap`) are ALWAYS marked `~` approximate.
- **Tried and rejected, don't re-add**: "a heal at full health is overheal, stay at 100%" (drew the
  user at full while they were at ~10%), and forward-from-the-pull health reconstruction (14-24% off in
  real fights, because it rests on the hit log).

## Deaths and runs (`Squizzcap.lua`)

- **A run** = one visit to one instance at one difficulty (`RunIdentity`); a new one starts on walking in
  from outside or on `CHALLENGE_MODE_START`, never on a corpse run or a /reload. Open-world deaths group
  by zone and day. Created lazily on the first death. `keepRuns` (default 20) trims the oldest;
  `freshEachKey` clears all runs when a key starts.
- **`PLAYER_DEAD` can fire TWICE for one death** (arena skirmish, 2026-09-29: two identical entries).
  `SameDeath` matches readable recaps on the killing blow's timestamp + amount, hidden ones on being
  within 3s. A duplicate is dropped, but may fill in This fight that the first read lacked.
- **This fight** (`Data.ReadFight`, `C_DamageMeter` damage taken for the current session) can be hidden
  at the moment of death (you can still be flagged in combat). `RetryFight` retries at 1/3/6s and adds
  the tab to the saved death; the failure reason is stored in `model.fightWhy` and printed by
  `/squizzcap fight`. Seen working in an arena before the retry; the retry itself is UNTESTED in game.

## Slash commands

| Command | Action |
|---------|--------|
| `/squizzcap` | Options |
| `/squizzcap show` | Open the last saved death |
| `/squizzcap toast` | Show the last death as the compact summary |
| `/squizzcap fight` | Why the last death has (or lacks) a This fight tab |
| `/squizzcap notes` | Re-open the release notes |
| `/squizzcap probe` | **TEMPORARY** (shipped in V1.2.0): lists the damage meter's Deaths entries and tries `C_DeathRecap` on each `deathRecapID`, to learn whether OTHER group members' recaps are readable. The answer gates a "group deaths" feature here and "open this death in Squizzcap" in DPSReport. Remove once the user has run it in a group |

## Releasing

Same pipeline as SquizzFrames: pushing an annotated `v*` tag runs `.github/workflows/release.yml`
(BigWigsMods/packager) to CurseForge and a GitHub release; pushes to `main` publish nothing.
**Ask before tagging, every time.**

1. The top `CHANGELOG.txt` section stays OPEN (undated) while work lands. `.pkgmeta` sends the WHOLE
   file as release notes (SquizzFrames' convention, not the archive one).
2. Add `RELEASE_NOTES["<version>"]` in `Welcome.lua`.
3. When the user says ship: date the heading, bump `## Version:` in the TOC (three-part), commit, then
   `git tag -a vX.Y.Z -m "VX.Y.Z"` and `git push origin vX.Y.Z`.

`.pkgmeta` excludes `CLAUDE.md`, `README.md`, `.claude`, `.github` and the git files from the zip.
