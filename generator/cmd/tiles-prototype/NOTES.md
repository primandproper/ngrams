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
- `es_MX` carries a few forms Mexican Spanish doesn't use: three voseo imperative rules
  (`matate`, `tené`, `vení`) and 23 vosotros forms stored as bare stems (`dadle`, `estéis`).
  The prototype drops them, which removes 96 of 496k forms. They were not a meaningful share of
  the obscure words; those are rare but standard forms the 50k subtitle list misses (`untó`,
  `transpón`, `vencía`). A bigger frequency list is the lever there, not the dictionary.
- Spanish now reads the full subtitle list (1.2M lines) instead of the top 50k, which covers
  148k dictionary forms at count ≥ 3 versus 36k before. The tail is junk (`lowlands`,
  `thatis`), but the dictionary filters it out. Even at count 2 what survives is real, rare
  inflection (`elogiándolo`, `desinfectaste`). Targets still come from the top 50k ranks, so
  the target pool is unchanged. At the default `-min-count 5`, obscure words per board fall
  from 6 to 11 to 0 or 1. The catch is that "common" now admits words most players won't
  find (`helo`, `inri`, `vilo`), so raise `-min-count` if boards feel padded.
  Dropping them still matters for targets: `dadles` is a stem and common in Spain-dubbed
  subtitles, so it could have been a target.
- `.dic` stems as targets read like base forms on the boards seen so far (`musulmán`,
  `envenenamiento`), including `-mente` adverbs, which the dictionary stores as stems.
- Cutting anywhere produces unpronounceable tiles (`ysan`, `rpri`, `nsp`, `ialm`, `sq`) in both
  languages. Syllable-aligned cuts are the next thing to try if those feel wrong in play.
- Words that fold together display their most common spelling; with no frequency data the first
  expanded form wins, so a few obscure words show without their accent (`ion`).

## Verdict

- Unpronounceable tiles are fine (Jeffrey, 2026-10-23). No syllable-aligned cuts.
- The rest is pending: play some boards first.
