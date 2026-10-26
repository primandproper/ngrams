# n-grams design

Status: draft. The generator and the app cover all three games (2026-10-24)

## Goal

Daily word puzzles on iPhone without ads, accounts, energy meters, or upsells. Three game types
modeled on games I already like (NYT Wordle, Apple News Quartiles, and NYT Spelling Bee), each
offered at three sizes, so N varies, in English and Spanish. Nine puzzles a day per language,
every day.

Built to launch publicly on the App Store.

## Non-goals (for now)

- Accounts, sync, leaderboards, notifications.
- A "play unlimited" mode.
- Live puzzle generation on the device.
- Monetization of any kind.
- Translating the app's own text. Puzzles are bilingual; the app around them stays English.

## Games

The originals' names are trademarks (WORDLE and SPELLING BEE are NYT's, Quartiles is Apple's)
and must not appear in the app. The in-app names are "Password", "Tiles", and "Pangram", under
the app name "n-grams". The app's name and the n in its own text ("n=4") are always lowercase.
Internally the kinds are `word`, `tiles`, and `pangram`.

| Kind      | Modeled on   | Sizes (N)          | Daily puzzles |
| --------- | ------------ | ------------------ | ------------- |
| `word`    | Wordle       | 4, 5, 6 letters    | 3             |
| `tiles`   | Quartiles    | 3, 4, 5 tiles/word | 3             |
| `pangram` | Spelling Bee | 6, 7, 8 letters    | 3             |

"Spellbound" was considered for `pangram` and rejected: Spellbound: A Game of Letters, the same
game under that name, is already on the App Store (checked 2026-10-24). "Password" for `word`
collides with Fremantle's TV word game of that name, and "Magic Word" with several App Store word
games; the risk was accepted for an in-app label, since only the app's name is searchable
(2026-10-25).

### `word`

- Guess an N-letter word; each guess marks letters as correct, present, or absent. A
  misplaced letter is marked present only as many times as the answer has it left over after
  its correct letters, as in the original.
- 6 guesses at every N to start. Shorter words are the trap-prone ones (BATE/DATE/FATE/GATE),
  so scaling guesses as N+1 would make the hardest variant harder. Tune by playing.
- Guesses must come from the accepted-guess list for that length: every dictionary form,
  plurals and conjugations included. A blocked word gets "How dare you", as in `tiles`.
- The app has its own keyboard; the Spanish one adds Ñ. A lost puzzle shows the answer with
  its accents.
- Solving earns the star. A puzzle is completed once it's over, won or lost, and its row
  shows the guesses used ("4/6", "X/6").
- A "hard mode" setting makes every guess use the hints so far, by the original's rule: a
  correct letter stays in its spot, and a found letter appears at least as many times as any
  earlier guess showed it. Absent letters stay allowed. A refused guess says which hint it
  left out ("2nd letter must be R", "Guess must contain E").

### `tiles`

- A board of word fragments ("tiles"). Build words from 1 to N tiles, each tile used at most
  once per word, in order.
- Each board hides target words of exactly N tiles that together use every tile: 7, 5, and 4
  targets at N=3, 4, 5, so every board has about 20 tiles (21, 20, 20).
- Holding the tile count near 20 beat 5 targets at every N (15/20/25 tiles) in the prototype.
  At N=3, 15 tiles can't produce 40 common words in either language; 21 can. At N=5, 20 tiles
  reach the same word counts as 25, so the extra tiles are clutter. A constant tile count also
  means one board layout on the phone instead of three.
- The board has N columns, so 21 or 20 tiles always fill a rectangle (7×3, 5×4, 4×5) and a
  solved target fills exactly one row.
- The app lays tiles out, not the bank: a uniform shuffle left two of a target's tiles side by
  side, in order, on about half of all boards. A row holds at most one tile of any target at
  N=3 and 4 (two at N=5, where five tiles from four targets must repeat one), and no target's
  tiles sit side by side in reading order. The app redraws random layouts until one passes
  (about 1 in 300 at N=4, so microseconds), seeding the first by board so it's stable across
  launches. Shuffle redraws the unsolved tiles; solving a target leaves the rest to slide up
  as in the original.
- A board's star takes every target and the target score.
- As in the original, a found target's tiles lock into a row at the top of the board and stay
  usable in other words. A global "hard mode" setting takes them off the board instead. Since
  every tile belongs to a target, finishing the last target empties the board, so in hard mode
  the 20 points beyond the targets and bonus have to come before the last target.
- Scoring borrows the original's curve. Quartiles (per Apple's help page, checked 2026-10-23)
  scores 1, 2, 4, and 8 points for words of 1 to 4 tiles, adds 40 for finding all five
  Quartiles, and calls 100 points "Expert". Here a word of k tiles scores 2^(k-1) at every N,
  finding every target adds 40, and the target score is every target plus the bonus plus 20:
  88, 100, and 124 at N=3, 4, 5, which reproduces the original at N=4. The generator writes
  each word's points, the bonus, and the target score into the bank, so retuning is a bank
  rebuild rather than an app release.

### `pangram`

- N letters, one of them the center. Spell words of at least 4 letters from them, always using
  the center; letters repeat freely. A pangram uses every letter.
- Scoring follows the original: a 4-letter word scores 1, a longer word a point a letter, and a
  pangram 7 more.
- Every dictionary word counts, Spanish verb forms included. The target score is 70% of the
  points in the common words alone, so obscure words help but are never needed.
- A board's star takes every common pangram and the target score, as a `tiles` star takes
  every target. Obscure pangrams score but aren't required.
- A "hard mode" setting makes the first word found a pangram, any pangram, obscure ones
  included.
- No S on any board in either language: plurals would double every board, and in Spanish S
  also ends most second-person and plural verb forms.
- Sizes are N=6, 7, and 8 letters. A 5-letter hive was measured at a median of 10 common words
  in English, too thin to be a puzzle. Each size has its own range of common words, centered
  near what a typical board reaches: 20 to 45, 30 to 70, and 50 to 110. Tune by playing.
- The letters sit on a wheel: the center in a circle, the rest in a ring cut into one wedge
  each. The original's hexagons only close up with exactly six around the center; a wheel
  closes at any size, keeps one shape across sizes, and its wedges make bigger tap targets than
  circles on a ring would. Shuffle moves only the outer letters, and the first order is seeded
  by board, as in `tiles`.

### Shared

- The day rolls over at local midnight on the device.
- Every earlier day the bank holds stays playable: arrows at the bottom of home step a day at a
  time, and the day between them opens a calendar. Days ahead stay hidden so nothing is spoiled,
  except in debug builds, which open the whole bank for playtesting.
- Home lists every puzzle for the day on one screen, grouped by game ("Tiles") or by N ("n=4")
  from a toolbar menu, and remembers the choice. By game, each language gets its own group in
  the section, its puzzles running by N; by N, rows run by game, then language. Languages are
  marked by flag (🇺🇸, 🇲🇽 for the American and Mexican word lists), and only when more than
  one is on.
  Grouping by N mixes games whose N means different things (tiles per word, letters per answer,
  letters per board); that's accepted, since it's the player's choice. Completed puzzles move
  to a "Completed" section at the bottom: a `tiles` or `pangram` board once it has its star, a
  `word` puzzle once it's over.
- Players choose which languages they want puzzles in, once on first launch (pre-checked from
  the device's preferred languages) and any time after in Settings. Home shows only those, so
  nobody is handed puzzles in a language they don't play. At least one stays on.
- `word` and `pangram` hard modes lock per puzzle: the setting applies until a puzzle's first
  guess or word is saved, and the puzzle keeps that mode after, saved with its progress. `tiles`
  hard mode predates this and still reads the setting whenever a board opens.
- Results share as spoiler-free text: each puzzle from its own screen, and every puzzle started
  on a day from home, a line per language and game. Shares carry the date ("Oct 25") rather
  than a puzzle number, a flag even when only one language is on (the reader may play
  another), `*` for hard mode, and ⭐ for a star. `word` shares its grid; `tiles` and `pangram`
  a ten-segment bar toward the target. The grid avoids the original's colors: blue in place,
  grey in the word, dark for absent (🟦⬜⬛), matching the board, where absent letters fade
  rather than fill.
- Stats and streaks are per `(lang, kind, n)`: played, the share won (`word`) or starred
  (boards), current and best streak, and for `word` how many guesses each solve took. They
  show on a stats screen from home, after finishing a puzzle, and as a flame on each home row.
- A streak counts a `word` solve or a board's star, on the puzzle's own day. Playing earlier
  days from the calendar counts toward the totals but not the streak, as in the original's
  archive. An unfinished puzzle today leaves the streak alone until midnight; a lost one ends
  it.
- Stats are worked out from saved progress each time, never stored, so they can't drift from
  what was played. Progress keeps when each puzzle was completed for the on-day rule.

## Languages

English and Spanish (`en`, `es`). Each language gets its own full daily set, so 18 puzzles a
day.

- **Region.** Spanish means `es_MX`: dictionary, commonness judgments, and blocklist.
- **Accents fold.** For matching and scoring, á/é/í/ó/ú/ü count as their plain vowels in both
  games. `tiles` forces this: CANCIÓN and CANCIONES would otherwise need different tiles for
  the same fragment. Whole words (the revealed `word` answer, the `tiles` found-words list)
  display with their accents.
- **Ñ is its own letter.** N and Ñ score separately. The Spanish keyboard has an Ñ key and no
  accent keys.
- **Digraphs are two letters.** CH, LL, and RR count as two letters each, per current RAE
  spelling.
- **Base forms as answers.** `word` answers and `tiles` targets are infinitives, singular nouns,
  and masculine singular adjectives. Every inflected form is still a valid guess or found word.
  A Spanish verb has around 50 forms, so without this rule a large share of answers would be
  conjugations.
- Sizes and guess counts match English to start. Tune by playing.

The generator does the folding, so the app only compares plain strings: tiles and accepted
guesses ship folded, and each word carries its accented spelling for display.

## Architecture

The app plays puzzles; it never makes them. All generation and curation happens offline in a
Go tool, and the app ships with a pre-built puzzle bank.

```mermaid
flowchart LR
  subgraph Offline["generator (Go, run locally)"]
    W[Word lists + frequency data + blocklist] --> G[Generators + quality scoring]
    G --> R[Manual review pass]
    R --> B[puzzles.json]
  end
  B -->|bundled resource| A
  subgraph A["iOS app (SwiftUI)"]
    D[Today's date + selected language] --> P[Look up today's puzzles]
    P --> WG[word: N=4,5,6]
    P --> TG[tiles: N=3,4,5]
    WG & TG --> S[(SwiftData: progress)]
  end
```

### Repo layout

```text
generator/   Go module: word list processing, puzzle generation, bank output
ios/         Xcode project
data/        per-language source word lists and blocklists, generated bank
docs/        this file
```

`make format lint test` covers every part of the repo. `make bank` rebuilds the bank.

## Generator

The generator takes a list of languages and runs the same pipeline once per language. What
differs between them (word sources, folding, banned fragments, the base-form rule) lives in
per-language config.

### Word lists

- English dictionary: ENABLE (public domain). SCOWL (permissive) if ENABLE proves too sparse or
  too obscure. NYT's own lists are not usable.
- Spanish dictionary: the RLA-ES `es_MX` Hunspell dictionary, licensed GPLv3+, LGPLv3+, or
  MPL 1.1+ at our choice, and actively maintained. Hunspell stores stems plus affix rules, so
  the generator expands them into full forms (`unmunch`, or a small Go affix expander). The
  `.dic` stems are close to lemmas and may seed the base-form answer list; irregular verbs
  probably break that, unverified.
- Mexican Spanish uses neither voseo nor vosotros, but a few of `es_MX`'s affix rules and
  stems produce them (`tené`, `adquiríais`, `dadle`). The generator drops those rules and stems
  by name, and fails if a dictionary update removes one, so a renamed rule can't sneak back.
- Commonness: subtitle word counts from hermitdave/FrequencyWords (OpenSubtitles 2018), not
  Google Books Ngram. English reads the top 50k list. Spanish reads the full list (1.2M lines),
  since the 50k list misses rare but standard inflections (`untó`, `vencía`); the dictionary
  filters out the junk in its tail. In both languages targets come only from the top 50k
  ranks, and a found word counts as common at 20 or more occurrences.
- Blocklist: one per language, in `data/blocklists/`. Offensive words are excluded from
  answers and targets, and the board search penalizes boards that can spell them. A board
  that still can lists them apart from its scoring words, and spelling one gets "How dare you"
  instead of points: a plain rejection of a real word would read as a bug. The bar is slurs,
  sexual or anatomical vulgarity, and sexual-violence terms; words whose innocent sense
  dominates stay (sexual, suck, butt, Spanish pedo), and mild profanity (damn, hell, crap)
  stays except "ass". Spanish entries are stems, so blocking one blocks every form it
  expands to; English entries are exact forms, so compounds need their own entries. Stems
  also mean a Spanish word can only be blocked with its whole family: mamar takes mamá with
  it and violar takes viola, so their vulgar forms (mame, violen) stay unblocked until the
  list supports exact forms.

### `word` puzzles

Pick one answer per length per day at random from the 1,500 most common answers of that
length, without repeats within a language. Each kind draws from its own random stream, so
adding word puzzles left every `tiles` board as it was. Accepted guesses per length come
from the full dictionary.

Answers are base forms, which neither dictionary marks directly:

- English drops a target that is another word plus "s", "ed", or "d" (CATS, BAKED, FREED),
  except words ending in "ss". ENABLE has no lemmas, so this guesses, and it also drops some
  base forms (NEED, from NEE). Gerunds (TIRING, ASKING) stay.
- Spanish takes the `.dic` stems that carry affix flags. The flagless ones are mostly
  irregular conjugations and abbreviations (seré, podrán, dpto). A stem displays as the
  dictionary spells it rather than as its most common homograph (vera, not verá), which also
  changed a few `tiles` words' display spellings.
- At 4 letters Spanish has only about 720 answers, under 2 years of puzzles.

### `tiles` puzzles

1. Pick the target words (7, 5, or 4) that split cleanly into N fragments.
2. Choose a segmentation for each.
3. Enumerate every valid word buildable from 1 to N tiles, using a trie to prune.
4. Score the board and keep the good ones for review.

Enumeration cost is not a concern at these sizes: 20 tiles with 5-tile words is small once
a trie prunes dead prefixes.

What makes a board good is the real question, and it is not "most words":

- **Fragment shape.** Short fragments ("in", "er") combine with everything and produce
  hundreds of junk words. Fragments are at least 2 letters (the original rarely if ever uses
  1-letter tiles), at most 4 to start, and never on a banned-fragment list. These are filters on
  the candidate segmentations, applied before any search, and they matter more than the search
  strategy itself. Banned-fragment lists are per language, and Spanish's will be longer:
  inflectional suffixes (`ar`, `os`, `as`, `mos`, `ron`) attach to nearly every stem. Cuts
  land anywhere, so some tiles are unpronounceable (`ysan`, `rpri`, `nsp`); that's fine, so
  there is no syllable alignment.
- **Frequency-weighted word count.** Count found words weighted by how common they are, inside
  a target range rather than maximized. The range starts at 40 to 80 common words at every N.
  40 is the highest floor N=3 comes close to reliably: in the 90-day bank, 47 of 180 N=3
  boards (30 English, 17 Spanish) land at 35 to 39, which the generator logs as a warning.
  Whether N=4 and N=5 want a higher floor of their own is for playtesting to decide. Boards
  settle near the floor, because the penalty for obscure words pulls the count down once it's
  in range.
- **Target uniqueness.** The targets should be the only N-tile words on the board, or "find
  all the full-length words" becomes ambiguous.
- **Not trivially guessable.** Fragments should be ambiguous enough that targets aren't
  obvious at a glance.

### `pangram` puzzles

A board is seeded by a target word with exactly N distinct letters and no S. Every center
among its letters is tried, and the first board whose common words land in range is kept,
preferring one that can't spell a blocked word; one that can lists them apart from its
scoring words, as in `tiles`. No letter set repeats within a language. Indexing every word by
its letter set (a bitmask) means checking a board is one lookup per subset of its letters, at
most 256.

### Search strategy: heuristic first, solver if needed

Choosing segmentations to optimize the board can be stated as weighted MaxSAT or an integer
program: one boolean per candidate segmentation, exactly one per target, a derived word "exists"
only if all its tiles are chosen, uniqueness as a hard constraint, the frequency-weighted score
as the objective. A solver (OR-Tools CP-SAT is the mainstream choice) would return provably
optimal boards.

Starting with generate-and-test instead:

- n is small. About 1,100 boards a year, generated offline, with no time limit worth caring
  about. Random sampling plus local search over segmentations, scored and ranked, is likely
  good enough.
- Optimality only helps once the objective is right, and the objective is the part we don't
  know yet. Playing heuristic boards is how we find it.
- CP-SAT does have a Go API in the OR-Tools repo (`ortools/sat/go/cpmodel`, actively maintained),
  but it is a cgo wrapper over the C API that OR-Tools builds with Bazel, and the README doesn't
  document it. Using it from a plain `go build` means getting the native library and headers
  installed and linked first; that setup cost is unmeasured.

Reach for a solver if heuristic boards come out consistently mediocre and the scoring rules can
be stated precisely. Segmentation with targets already fixed is the part it suits best.

## Puzzle bank

Plain JSON at `data/bank/puzzles.json`, committed, bundled in the app as a resource, and
decoded with `Codable` at launch. 90 days in both languages is about 4.8 MB (1.5 MB before
`pangram`), so a year is roughly 10 MB per language, almost all of it the precomputed
valid-word lists for `tiles` and `pangram` boards. The generator computes those lists so the app never has to work them out, and so the
review pass covers exactly what the app will accept.

`make bank` rebuilds it from a fixed start date, length, and seed set in the Makefile; the same
seed and source data rebuild the same bank. No target repeats within a language. Tiles are
shuffled, though the app lays them out itself. Each day sits in its own block with one word
per line, so a rebuilt bank diffs by eye; `make bank ARGS=-print` prints every board for review.

A rebuild never changes a day a player may have reached: saved progress is keyed by date, so a changed
board would sit under someone's old guesses. Every day through today in the earliest time zone
(UTC+14) is frozen, copied as it was from the committed bank, and the days after it repeat
nothing the frozen days used. Each kind draws from its own random stream per day, so freezing
leaves the later days as a full rebuild would make them, and a rebuild with nothing changed
diffs clean.

Accepted `word` guesses ship as one newline-separated text file per `(lang, n)` in
`data/bank/guesses/` (`en-5.txt`), with that length's blocked words beside it
(`en-5-blocked.txt`), loaded into a `Set<String>` when a puzzle opens.

The format (puzzles are a list per day, so adding a language, kind, or size is additive).
`display` appears only when the accented spelling differs from the folded one. `blocked` lists
the folded spellings of offensive words the tiles can build, and appears only when there are
any.

```json
{
  "version": 1,
  "seed": 1,
  "days": [
    {
      "date": "2027-01-01",
      "puzzles": [
        { "lang": "en", "kind": "word", "n": 4, "answer": "lamp" },
        { "lang": "es", "kind": "word", "n": 5, "answer": "arbol", "display": "árbol" },
        {
          "lang": "en",
          "kind": "tiles",
          "n": 3,
          "tiles": ["sta", "ple", "ham", "..."],
          "targets": [[0, 4, 9], "..."],
          "bonus": 40,
          "target_score": 88,
          "blocked": ["..."],
          "words": [{ "word": "staple", "tiles": [0, 1], "points": 2 }, "..."]
        },
        {
          "lang": "en",
          "kind": "pangram",
          "n": 7,
          "letters": ["a", "f", "g", "i", "n", "r", "t"],
          "center": "r",
          "pangrams": ["..."],
          "target_score": 249,
          "words": [{ "word": "grant", "points": 5 }, "..."]
        }
      ]
    }
  ]
}
```

### Why not SQLite

- The bank is small, read-only, and only ever looked up by date.
- Apple's frameworks only open SQLite files in Core Data's own internal layout, which a Go tool
  can't easily produce, so a Go-built database means the C API or a dependency (GRDB). That buys
  nothing at this size.
- JSON can be reviewed and diffed by eye during curation.

Revisit if the bank grows to tens of MB (a many-year archive); split per year or move to SQLite then.

### Two stores, kept apart

| Store         | Contents                       | Written by        | Lives in      |
| ------------- | ------------------------------ | ----------------- | ------------- |
| Puzzle bank   | Puzzles, accepted words        | Generator (build) | App bundle    |
| User progress | Guesses, words, completion     | App (runtime)     | SwiftData     |

The only link is the key `(lang, kind, n, date)`. Shipping a new bank never touches user data, and
moving the bank from "bundled" to "fetched from a static URL behind Caddy, cached on device,
bundled copy as fallback" changes nothing about the format.

## Distribution and legal

- `make ios_install` puts a Debug build on my phone, signed with my paid developer team, so it
  keeps launching for the year its provisioning profile lasts. TestFlight builds expire after
  90 days.
- `make release` uploads a Release build to App Store Connect with the API key from 1Password,
  numbered by commit count, and tags the commit `v<version>+<build>`. It refuses a dirty tree,
  anything but `origin/main`, and a bank with under 60 days left. Submitting for review and
  releasing stay manual in App Store Connect, with "manually release this version" chosen.
- The word lists keep their own licenses (`NOTICE`); the app credits them under Settings,
  Acknowledgements.
- Going public means no use of any original's name, and a visual design that is
  clearly its own. App Review guideline 4.1 (copycats) can reject apps that look too much like
  an existing game, and NYT pursued Wordle clones in 2022.
- "n-grams" is not taken on the US App Store (checked 2026-10-19), but App Store search for
  "n-grams" returns kitchen scales, so the name helps nobody find it.

## Open questions

1. Whether the `tiles` scoring curve and target scores above play well; tune by playing.
2. Whether the `es_MX` `.dic` stems are good enough as the Spanish base-form list, or a real
   lemma source is needed. On the boards seen so far, stems as targets read like base forms
   (`musulmán`, `envenenamiento`), including `-mente` adverbs, which the dictionary stores as
   stems.

## Milestones

Whether boards are fun gets judged by playing them in the app, installed on my phone, not by
reading printed output. So the order is:

1. `tiles` playable on my phone with real generated boards, in both languages. Debug builds' day
   picker reaches the whole bank, so a playtest isn't limited to one day's boards.
2. `word`.
3. `pangram`.
4. The app icon: three tiles reading N, GR, AMS, drawn by `make icon` (`ios/Tools/AppIcon.swift`)
   in light, dark, and tinted variants, so it's reproducible and diffs as code. Icon
   Composer's layered `.icon` format, which adds Liquid Glass, is left for a real design pass.
5. Sharing results as text.
6. Stats and streaks.
