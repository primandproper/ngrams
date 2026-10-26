package software.primandproper.ngrams.core

import java.time.Instant
import java.time.ZoneId

/** One puzzle a player can play every day: a game at one size, in one language. Stats and streaks are kept per line. */
data class PuzzleLine(
    val language: Language,
    val kind: PuzzleKind,
    val n: Int,
)

/** Identifies one puzzle across the bank and saved progress, which share nothing else. */
data class ProgressKey(
    val language: Language,
    val kind: PuzzleKind,
    val n: Int,
    val day: PuzzleDay,
) {
    val line: PuzzleLine get() = PuzzleLine(language, kind, n)
}

/** What a player did on one puzzle, apart from storage so stats are plain values. */
data class PlayRecord(
    val key: ProgressKey,
    val entries: List<String>,
    /** When a word puzzle ended or a board earned its star; for older records, when it was last played. */
    val completedAt: Instant?,
)

/** A line's results across every day up to today. */
data class LineStats(
    val line: PuzzleLine,
    /** Puzzles with at least one guess or word. */
    val played: Int = 0,
    /** What the success rate is out of: word puzzles that are over, won or lost, and boards played. */
    val decided: Int = 0,
    /** Word puzzles solved, or boards that earned their star. */
    val successes: Int = 0,
    /** Successes on their own day, one day after another, through today. An unfinished puzzle today doesn't break the streak until the day is over; a lost one does. */
    val currentStreak: Int = 0,
    val bestStreak: Int = 0,
    /** Word puzzles solved in each number of guesses: the first count is for one guess. */
    val guessCounts: List<Int> = List(WordGame.MAX_GUESSES) { 0 },
) {
    val successRate: Double? get() = if (decided == 0) null else successes.toDouble() / decided
}

object StatsBook {
    private data class Outcome(
        val started: Boolean = false,
        val decided: Boolean = false,
        val succeeded: Boolean = false,
        /** A word puzzle that ran out of guesses. */
        val lost: Boolean = false,
        /** Guesses used, for a solved word puzzle. */
        val guesses: Int? = null,
        val completedAt: Instant? = null,
    )

    /**
     * Every line the bank holds through [today], with what [records] say was played on it. Days
     * after today don't count, and [zone] decides which day a completion fell on.
     */
    fun compute(
        records: List<PlayRecord>,
        bank: PuzzleBank,
        today: PuzzleDay,
        zone: ZoneId = ZoneId.systemDefault(),
    ): Map<PuzzleLine, LineStats> {
        val byKey = records.distinctBy { it.key }.associateBy { it.key }
        val stats = mutableMapOf<PuzzleLine, LineStats>()
        val runs = mutableMapOf<PuzzleLine, Int>()

        for (day in bank.days.filter { it <= today }) {
            val outcomes =
                bank.wordPuzzles(day).map { outcome(it, byKey[ProgressKey(it.language, PuzzleKind.WORD, it.n, day)]) } +
                    bank.tilesPuzzles(day).map { outcome(it, byKey[ProgressKey(it.language, PuzzleKind.TILES, it.n, day)]) } +
                    bank.pangramPuzzles(day).map { outcome(it, byKey[ProgressKey(it.language, PuzzleKind.PANGRAM, it.n, day)]) }
            for ((line, outcome) in outcomes) {
                var lineStats = stats[line] ?: LineStats(line)
                lineStats =
                    lineStats.copy(
                        played = lineStats.played + if (outcome.started) 1 else 0,
                        decided = lineStats.decided + if (outcome.decided) 1 else 0,
                        successes = lineStats.successes + if (outcome.succeeded) 1 else 0,
                        guessCounts =
                            outcome.guesses
                                ?.takeIf { it - 1 in lineStats.guessCounts.indices }
                                ?.let { guesses -> lineStats.guessCounts.mapIndexed { i, c -> if (i == guesses - 1) c + 1 else c } }
                                ?: lineStats.guessCounts,
                    )

                val onTime =
                    outcome.succeeded &&
                        outcome.completedAt?.let { PuzzleDay(it.atZone(zone).toLocalDate()) == day } == true
                if (onTime) {
                    runs[line] = (runs[line] ?: 0) + 1
                } else if (day < today || outcome.lost) {
                    runs[line] = 0
                }
                stats[line] = lineStats.copy(bestStreak = maxOf(lineStats.bestStreak, runs[line] ?: 0))
            }
        }
        return stats.mapValues { (line, lineStats) -> lineStats.copy(currentStreak = runs[line] ?: 0) }
    }

    private fun outcome(
        puzzle: WordPuzzle,
        record: PlayRecord?,
    ): Pair<PuzzleLine, Outcome> {
        val line = PuzzleLine(puzzle.language, PuzzleKind.WORD, puzzle.n)
        record ?: return line to Outcome()
        val game = WordGame(puzzle, record.entries)
        val status = game.status
        return line to
            Outcome(
                started = game.guesses.isNotEmpty(),
                decided = game.isOver,
                succeeded = status is Status.Won,
                lost = status == Status.Lost,
                guesses = (status as? Status.Won)?.guesses,
                completedAt = record.completedAt,
            )
    }

    private fun outcome(
        puzzle: TilesPuzzle,
        record: PlayRecord?,
    ): Pair<PuzzleLine, Outcome> {
        val line = PuzzleLine(puzzle.language, PuzzleKind.TILES, puzzle.n)
        record ?: return line to Outcome()
        val game = TilesGame(puzzle, record.entries)
        val started = game.found.isNotEmpty()
        return line to Outcome(started = started, decided = started, succeeded = game.earnedStar, completedAt = record.completedAt)
    }

    private fun outcome(
        puzzle: PangramPuzzle,
        record: PlayRecord?,
    ): Pair<PuzzleLine, Outcome> {
        val line = PuzzleLine(puzzle.language, PuzzleKind.PANGRAM, puzzle.n)
        record ?: return line to Outcome()
        val game = PangramGame(puzzle, record.entries)
        val started = game.found.isNotEmpty()
        return line to Outcome(started = started, decided = started, succeeded = game.earnedStar, completedAt = record.completedAt)
    }
}
