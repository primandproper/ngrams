package software.primandproper.ngrams

import android.content.Intent
import kotlinx.coroutines.runBlocking
import software.primandproper.ngrams.core.FoundWordOrder
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LetterMark
import software.primandproper.ngrams.core.PangramGame
import software.primandproper.ngrams.core.PangramPuzzle
import software.primandproper.ngrams.core.PangramWord
import software.primandproper.ngrams.core.PuzzleBank
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.core.TilesGame
import software.primandproper.ngrams.core.TilesPuzzle
import software.primandproper.ngrams.core.TilesWord
import software.primandproper.ngrams.core.WordGame
import software.primandproper.ngrams.core.WordPuzzle
import software.primandproper.ngrams.progress.PuzzleProgress
import software.primandproper.ngrams.settings.HomeGrouping
import java.time.ZoneId
import kotlin.math.abs

/**
 * Debug builds launched with screenshot extras pin today and plant three weeks of made-up play,
 * the same history the iOS screenshot seed plants, so the Play screenshots don't depend on when
 * they're taken. Every entry is picked from the bank at launch, so the seed survives a rebuild.
 */
object ScreenshotSetup {
    const val PINNED_TODAY = "pinnedToday"
    const val SEED = "screenshotSeed"

    fun apply(
        container: AppContainer,
        intent: Intent,
    ) {
        intent.getStringExtra(PINNED_TODAY)?.let(PuzzleDay::parse)?.let { container.pinnedToday = it }
        if (intent.getBooleanExtra(SEED, false)) {
            // Before the first frame, so home never shows the language prompt or an empty board.
            runBlocking { ScreenshotSeed(container).plant() }
        }
    }
}

private class ScreenshotSeed(
    private val container: AppContainer,
) {
    private enum class Play { FINISHED, PARTWAY, FELL_SHORT }

    private val historyDays = 21
    private val spanishDays = 7

    /** Today's puzzles worth showing: one of each game finished, one of each partway (the ones the screenshot test opens), the rest untouched. */
    private val finishedToday =
        setOf(
            PuzzleLine(Language.EN, PuzzleKind.WORD, 4),
            PuzzleLine(Language.EN, PuzzleKind.TILES, 3),
            PuzzleLine(Language.EN, PuzzleKind.PANGRAM, 6),
        )
    private val partwayToday =
        setOf(
            PuzzleLine(Language.ES, PuzzleKind.WORD, 5),
            PuzzleLine(Language.EN, PuzzleKind.TILES, 4),
            PuzzleLine(Language.EN, PuzzleKind.PANGRAM, 7),
        )

    private val rows = mutableListOf<PuzzleProgress>()

    suspend fun plant() {
        val settings = container.settings
        settings.setLanguages(Language.entries.toSet())
        settings.setGrouping(HomeGrouping.GAME)
        settings.setWordHardMode(true)
        settings.setSolvedTilesLeave(false)
        settings.setPangramHardMode(false)
        settings.setPangramFoundOrder(FoundWordOrder.ALPHABETICAL)

        val bank = container.bank()
        val today = container.today()
        // Every word puzzle's answer comes from the most common words of its length, so they're
        // the words a player would plausibly guess or find.
        val common = bank.days.flatMap(bank::wordPuzzles).groupBy({ it.language }, { it.answer }).mapValues { it.value.toSet() }

        val history = bank.days.filter { it < today }.takeLast(historyDays)
        for ((index, day) in history.withIndex()) {
            val spanish = history.size - index <= spanishDays
            plant(bank, day, index, common) { line ->
                if (line.language == Language.ES && !spanish) {
                    null
                } else if (index == (line.n * 3 + line.kind.ordinal * 7) % 12) {
                    // One off day per line, early and in a different place on each, so streaks
                    // differ and nothing wins every time.
                    Play.FELL_SHORT
                } else {
                    Play.FINISHED
                }
            }
        }
        plant(bank, today, history.size, common) { line ->
            when (line) {
                in finishedToday -> Play.FINISHED
                in partwayToday -> Play.PARTWAY
                else -> null
            }
        }
        container.progress.replaceAll(rows)
    }

    private fun plant(
        bank: PuzzleBank,
        day: PuzzleDay,
        index: Int,
        common: Map<Language, Set<String>>,
        plays: (PuzzleLine) -> Play?,
    ) {
        fun insert(
            line: PuzzleLine,
            entries: List<String>,
            play: Play,
        ) {
            // Finished mid-morning on its own day, so it counts toward the streak.
            val finishedAt =
                if (play == Play.PARTWAY) {
                    null
                } else {
                    day.date
                        .atStartOfDay(ZoneId.systemDefault())
                        .plusHours(9)
                        .toInstant()
                        .toEpochMilli()
                }
            rows +=
                PuzzleProgress(
                    language = line.language.code,
                    kind = line.kind.code,
                    n = line.n,
                    day = day.toString(),
                    entries = entries,
                    completedAt = finishedAt,
                    updatedAt = finishedAt ?: System.currentTimeMillis(),
                )
        }

        for (puzzle in bank.wordPuzzles(day)) {
            val line = PuzzleLine(puzzle.language, PuzzleKind.WORD, puzzle.n)
            val play = plays(line) ?: continue
            val candidates = common[puzzle.language].orEmpty().filter { it.length == puzzle.n }.sorted()
            when (play) {
                Play.PARTWAY -> insert(line, closingIn(puzzle, 3, candidates, index), play)
                Play.FELL_SHORT -> insert(line, closingIn(puzzle, WordGame.MAX_GUESSES, candidates, index), play)
                Play.FINISHED -> {
                    // Solved in two to five guesses, so the guess distribution has some shape.
                    val misses = listOf(1, 2, 3, 2, 1, 4, 2)[(index + puzzle.n) % 7]
                    insert(line, closingIn(puzzle, misses, candidates, index) + puzzle.answer, play)
                }
            }
        }
        for (puzzle in bank.tilesPuzzles(day)) {
            val line = PuzzleLine(puzzle.language, PuzzleKind.TILES, puzzle.n)
            plays(line)?.let { insert(line, foundWords(puzzle, it, common[puzzle.language].orEmpty()), it) }
        }
        for (puzzle in bank.pangramPuzzles(day)) {
            val line = PuzzleLine(puzzle.language, PuzzleKind.PANGRAM, puzzle.n)
            plays(line)?.let { insert(line, foundWords(puzzle, it, common[puzzle.language].orEmpty()), it) }
        }
    }

    /**
     * Wrong guesses that close in on the answer as a player would: each finds one more letter than
     * the last, and from the second on, one more in its spot. Where no word fits exactly, the
     * nearest does. [offset] starts each puzzle's search somewhere different.
     */
    private fun closingIn(
        puzzle: WordPuzzle,
        misses: Int,
        candidates: List<String>,
        offset: Int,
    ): List<String> {
        val guesses = mutableListOf<String>()
        for (miss in 1..misses) {
            val found = minOf(miss, puzzle.n - 1)
            val placed = minOf(miss - 1, puzzle.n - 2)
            val unused = candidates.filter { it != puzzle.answer && it !in guesses }
            if (unused.isEmpty()) break
            val start = (offset * 7919 + miss * 104_729) % unused.size
            val rotated = unused.drop(start) + unused.take(start)
            rotated.minByOrNull { distance(it, puzzle, found, placed) }?.let(guesses::add)
        }
        return guesses
    }

    private fun distance(
        guess: String,
        puzzle: WordPuzzle,
        found: Int,
        placed: Int,
    ): Int {
        val marks = WordGame.marks(guess, puzzle.answer)
        return abs(marks.count { it != LetterMark.ABSENT } - found) + abs(marks.count { it == LetterMark.CORRECT } - placed)
    }

    /** Up to [count] words a player would find first: common ones, shortest first. Obscure words only pad a board with fewer than four common ones. */
    private fun likely(
        spelled: List<String>,
        common: Set<String>,
        count: Int,
    ): List<String> {
        val preferred = spelled.filter { it in common }.sortedWith(compareBy({ it.length }, { it }))
        val padding = spelled.filter { it !in common }.take(maxOf(0, 4 - preferred.size))
        return (preferred + padding).take(count)
    }

    /** A finished board has every target, then its best words until the star. One partway, or short of its star, has a handful of words and one target. */
    private fun foundWords(
        puzzle: TilesPuzzle,
        play: Play,
        common: Set<String>,
    ): List<String> {
        val targets = puzzle.targets.map { target -> target.joinToString("") { puzzle.tiles[it] } }
        val others = puzzle.words.filter { it.word !in targets }
        if (play != Play.FINISHED) {
            return likely(others.map(TilesWord::word), common, 6) + targets.take(1)
        }
        val found = targets.toMutableList()
        for (word in others.sortedByDescending { it.points }) {
            if (TilesGame(puzzle, found).earnedStar) break
            found += word.word
        }
        return found
    }

    /** A finished board has every common pangram, then its best words until the star. One partway, or short of its star, has a pangram and a handful of other words. */
    private fun foundWords(
        puzzle: PangramPuzzle,
        play: Play,
        common: Set<String>,
    ): List<String> {
        val pangrams = puzzle.words.map(PangramWord::word).filter { it in puzzle.pangrams }
        val others = puzzle.words.filter { it.word !in puzzle.pangrams }
        if (play != Play.FINISHED) {
            return likely(others.map(PangramWord::word), common, 9) + pangrams.take(1)
        }
        val found = pangrams.toMutableList()
        for (word in others.sortedByDescending { it.points }) {
            if (PangramGame(puzzle, found).earnedStar) break
            found += word.word
        }
        return found
    }
}
