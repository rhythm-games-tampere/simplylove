# Golf Scoring

An alternate scoring mode for ITGmania: every tap costs **strokes** based on how far off it
was, and a chart has a **par** you're trying to come in under. Lower is better; a perfect
chart is 0.

## Install

Copy these into your theme's `Modules/` directory:

```
Modules/GolfScoring.lua
Modules/Golf/ParBadge.lua
```

That's the whole thing — no other theme files are edited, and nothing else needs configuring.
Restart ITGmania afterwards (modules load once at startup).

Works on Simply Love and its forks. On other themes it still runs, but it can't hide the
theme's own score display during gameplay, so the two will overlap.

## Setting pars

Par isn't something the game knows about, so it lives in a `Golf.ini` at the **root of a pack**.
The presence of that file is the entire opt-in: any pack that ships one is a golf pack, and any
chart it names is a golf hole. Everything else plays exactly as before.

```ini
; /Songs/My Golf Pack/Golf.ini

[Honey]
Par=1.2

[Some Other Song]
Par=2.8

; per-chart override, for a song carrying more than one golf chart
[Honey:Challenge]
Par=1.6
```

Section names are the song's **folder name** — not its display title. So a song whose folder is
`Hyperstrike` but whose title is "Hyperstrike (9 Notes)" uses `[Hyperstrike]`.

The optional `:Difficulty` suffix takes one of `Beginner`, `Easy`, `Medium`, `Hard`,
`Challenge`, `Edit`, and wins over the song-wide entry.

Par is written in the same unit the score is displayed in, and is used exactly as authored --
nothing is scaled. Fractional pars are normal: `Par=5.6` shows as `5.6`.

Edits to a `Golf.ini` are picked up on the next visit to the song wheel — no restart needed.

## What you'll see

- **Song wheel** — a green `PAR n` badge on every chart that has one.
- **Gameplay** — your running stroke total replaces the usual score, with a green `Par` box
  over the difficulty meter, and a per-note readout (`ACE` for a perfect hit, otherwise `+n`).

Charts with no par are untouched: normal score, no par box, nothing hidden.

## Scoring

Every note costs a whole number of **strokes** — the `+n` you see during gameplay. The score is
the running total ÷ 1000. Timing error is taken as a whole number of milliseconds, so every
note landing in the same millisecond costs the same.

| Outcome | Strokes |
|---|---|
| Tap within ±5ms | 0 (an **ACE**) |
| Tap 5–45ms off | rises from +1 to +25, steepening past 23ms |
| Tap 45–103.5ms off | rises from +25 to +65, ever more slowly |
| Tap more than 103.5ms off | 100 |
| Miss | 100 |
| Hit a mine | 100 |
| Dropped or never-held hold/roll | 100 |
| Held hold/roll, avoided mine | 0 |

Hits under 5ms are free, which covers hardware jitter. Past 45ms the cost still climbs, just
ever more slowly — so a very late hit is bad but not ruinous. A miss, a dropped hold or roll,
and a hit mine each cost a flat 100, deliberately worse than the worst possible hit, which
tops out at 65.

Sample costs: **+1** at 5ms, **+3** at 10ms, **+10** at 23ms, **+25** at 45ms, **+38** at 60ms,
**+52** at 80ms, **+65** at 103ms.

Judgment windows are irrelevant — only the raw timing offset matters, so a Fantastic 20ms off
still costs 8 strokes.

Each note is rounded to a whole stroke *as it happens*, and the rounded values are what get
summed — which is what Arrow Cloud's server does too, so the in-game total and the submitted
score agree exactly.

## Notes

- Defines one global, `Golf`, holding the par lookup and formatters. Other code can read
  `Golf.Scores.P1` / `.P2` after a stage for `{ strokes, notes, par }`. `strokes` is the raw
  total (divide by `Golf.RAW_PER_STROKE` for the displayed figure).
- Set `DEBUG = true` at the top of `GolfScoring.lua` to trace what it's doing into the engine
  log, if a pack's pars aren't showing up.
