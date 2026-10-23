# tiles prototype notes

Throwaway. Delete this directory once the real generator absorbs the answers.

## Questions

1. Are generated `tiles` boards fun, in English and in Spanish?
2. Which board-size scheme: `fixed5` (5 targets, 15/20/25 tiles) or `near20` (7/5/4 targets)?
3. What common-word range makes a good board?
4. Are the `es_MX` `.dic` stems good enough as the Spanish base-form list (design doc open
   question 5)?

Run it with `make tiles-prototype`, narrowing with e.g. `ARGS="-langs es -ns 4 -seed 7"`.

## First-pass observations (Claude, 2026-10-23)

- The heuristic search finds boards with no duplicate tiles and no extra full-length words for
  every (lang, n, scheme), in 0.4 to 4.3 s per batch. Search cost is not a concern.
- Boards settle near the `-min-common` floor (30) because the obscure-word penalty pulls the
  count down once it's in range. The range is a guess until boards get played.
- `es_MX` expands to forms Mexican Spanish doesn't use: vosotros (`dadle`) and voseo (`matate`).
  They're most of the Spanish obscure words. Dropping those affix classes is worth trying.
- `.dic` stems as targets read like base forms on the boards seen so far (`musulmán`,
  `envenenamiento`), including `-mente` adverbs, which the dictionary stores as stems.
- Cutting anywhere produces unpronounceable tiles (`ysan`, `rpri`, `nsp`, `ialm`, `sq`) in both
  languages. Syllable-aligned cuts are the next thing to try if those feel wrong in play.
- Words that fold together display their most common spelling; with no frequency data the first
  expanded form wins, so a few obscure words show without their accent (`ion`).

## Verdict

Pending: play some boards first.
