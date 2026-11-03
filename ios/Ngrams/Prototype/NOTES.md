# Prototype: hints, solving, and animation (epic #12)

Throwaway. Lives on `prototype/hints-animations` and never merges. Everything for it is in this
folder or marked `PROTOTYPE` in the game views.

## Questions

1. Does each game's hint feel like the right size of help, and does Solve feel right?
2. Which animations make the games feel better, and which are noise?

## How to try it

- Debug build on the simulator or `make ios_install`. Progress lives in memory in this build, so
  the phone's saved progress is untouched and every launch starts fresh.
- Every game screen has a purple **Prototype** pill (bottom left) with a switch per animation, plus
  slow motion. The lifebuoy in the toolbar has **Hint** and **Solve…**.
- Reduce Motion (iOS Settings, Accessibility, Motion) turns movement into fades.

## What's in it

| Game     | Hint                                                         | Solve                                              |
| -------- | ------------------------------------------------------------ | -------------------------------------------------- |
| Password | Pencils the leftmost unknown letter into its spot, dashed    | Clears the row, types the answer, submits it       |
| Tiles    | Rings the next tile of an unfound target, stopping one short | Builds each unfound target in turn; the board slides |
| Pangram  | A chip with a word's first two letters and length, pangrams first | Spells pangrams, then top scorers, until the star |

Animations: Password flip, shake, and win hop; Tiles lift, springy board, and shake; Pangram
wedge pulse, shake, found-word pop, pangram burst, and ring spin; everywhere, score count-up, star
celebration, and haptics.

## Known gaps (prototype only)

- Solving plays real moves, so a solved Password puzzle counts as a win here. The agreed rule is
  a loss with no star.
- Hint counts aren't in share text yet (agreed: `💡2`).

## Verdict

Played on the phone (2026-11-02). Every hint, Solve, and animation stays except the burst on
finding a pangram. The star celebration's burst is a separate switch and wasn't called out.
