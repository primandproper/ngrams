package software.primandproper.ngrams.core

/** How a board lists the words found on it. */
enum class FoundWordOrder(
    val code: String,
) {
    ALPHABETICAL("alphabetical"),

    /** Newest first. */
    RECENT("recent"),
}

sealed interface PangramSubmission {
    data class Found(
        val word: PangramWord,
    ) : PangramSubmission

    data class AlreadyFound(
        val word: PangramWord,
    ) : PangramSubmission

    data object TooShort : PangramSubmission

    data object MissingCenter : PangramSubmission

    data class Blocked(
        val text: String,
    ) : PangramSubmission

    data class NotAWord(
        val text: String,
    ) : PangramSubmission

    data object NeedsPangram : PangramSubmission

    data object Empty : PangramSubmission
}

/**
 * The rules of one pangram board: the letters typed so far, what's been found, and the score.
 * Immutable; every move returns a new game.
 */
class PangramGame private constructor(
    val puzzle: PangramPuzzle,
    /** Whether the first word found has to be a pangram. */
    val hardMode: Boolean,
    /** Words found so far, oldest first. */
    val found: List<PangramWord>,
    /** Letters typed toward the next word. */
    val current: String,
    /** Hints taken, oldest first, each in the game's own terms. A hint never changes the result. */
    val hints: List<String>,
    /** Whether the player had the puzzle solved for them, which gives up the star. */
    val gaveUp: Boolean,
) {
    data class Submitted(
        val game: PangramGame,
        val submission: PangramSubmission,
    )

    private val words: Map<String, PangramWord> = puzzle.words.distinctBy { it.word }.associateBy { it.word }

    /** Folded spellings of the found words, oldest first, for saving. */
    val foundWords: List<String> get() = found.map { it.word }

    fun found(order: FoundWordOrder): List<PangramWord> =
        when (order) {
            FoundWordOrder.ALPHABETICAL -> found.sortedBy { it.word }
            FoundWordOrder.RECENT -> found.reversed()
        }

    val score: Int get() = found.sumOf { it.points }

    val foundPangrams: Int get() = found.count { it.word in puzzle.pangrams }

    val foundBonusPangrams: Int get() = found.count { puzzle.isBonusPangram(it.word) }

    /** A star takes every common pangram and the target score. */
    val earnedStar: Boolean get() = !gaveUp && foundPangrams == puzzle.pangrams.size && score >= puzzle.targetScore

    /** Whether the board has every common pangram and the target score, star or not. */
    private val reachedStar: Boolean get() = foundPangrams == puzzle.pangrams.size && score >= puzzle.targetScore

    /** The order hints clue words and solving spells them: common pangrams first, then by points, highest first, ties alphabetical. */
    private val helpOrder: List<PangramWord>
        get() =
            puzzle.words.sortedWith(
                compareByDescending<PangramWord> { it.word in puzzle.pangrams }
                    .thenByDescending { it.points }
                    .thenBy { it.word },
            )

    /** The word the next hint clues: the first in help order not found or clued already. Null once there's none left or the board is over. */
    val nextHint: String?
        get() {
            if (earnedStar || gaveUp) {
                return null
            }
            val taken = foundWords.toSet() + hints
            return helpOrder.firstOrNull { it.word !in taken }?.word
        }

    /** The clued words still unfound, oldest clue first. */
    val clues: List<PangramWord>
        get() {
            val found = foundWords.toSet()
            return hints.distinct().filter { it !in found }.mapNotNull { words[it] }
        }

    /** The words solving spells, in help order, until the board has every common pangram and the target score. */
    val solution: List<String>
        get() {
            var board = this
            val spelled = mutableListOf<String>()
            for (word in helpOrder) {
                if (board.reachedStar) {
                    break
                }
                if (word !in board.found) {
                    board = board.copy(found = board.found + word)
                    spelled += word.word
                }
            }
            return spelled
        }

    fun takeHint(hint: String): PangramGame = copy(hints = hints + hint)

    /** Solves the board for the player, finding [words], and gives up its star. */
    fun giveUp(words: List<String>): PangramGame =
        copy(
            found = found + words.distinct().filter { it !in foundWords }.mapNotNull { this.words[it] },
            current = "",
            gaveUp = true,
        )

    fun type(letter: Char): PangramGame = copy(current = current + letter)

    fun deleteLetter(): PangramGame = if (current.isEmpty()) this else copy(current = current.dropLast(1))

    fun clearLetters(): PangramGame = if (current.isEmpty()) this else copy(current = "")

    /** Checks the typed letters as a word and clears them. */
    fun submit(): Submitted {
        val text = current
        if (text.isEmpty()) {
            return Submitted(this, PangramSubmission.Empty)
        }
        val cleared = copy(current = "")
        return when {
            text.length < PangramPuzzle.MIN_LENGTH -> Submitted(cleared, PangramSubmission.TooShort)
            puzzle.center !in text -> Submitted(cleared, PangramSubmission.MissingCenter)
            text in puzzle.blocked -> Submitted(cleared, PangramSubmission.Blocked(text))
            else -> {
                val word = words[text] ?: return Submitted(cleared, PangramSubmission.NotAWord(text))
                when {
                    word in found -> Submitted(cleared, PangramSubmission.AlreadyFound(word))
                    hardMode && found.isEmpty() && !puzzle.isPangram(text) -> Submitted(cleared, PangramSubmission.NeedsPangram)
                    else -> Submitted(cleared.copy(found = found + word), PangramSubmission.Found(word))
                }
            }
        }
    }

    private fun copy(
        found: List<PangramWord> = this.found,
        current: String = this.current,
        hints: List<String> = this.hints,
        gaveUp: Boolean = this.gaveUp,
    ): PangramGame = PangramGame(puzzle, hardMode, found, current, hints, gaveUp)

    companion object {
        /**
         * Starts a board, restoring [foundWords], [hints] and [gaveUp] from saved progress. Saved words the board doesn't
         * have (the bank was rebuilt since) are dropped, as are repeats.
         */
        operator fun invoke(
            puzzle: PangramPuzzle,
            foundWords: List<String> = emptyList(),
            hardMode: Boolean = false,
            hints: List<String> = emptyList(),
            gaveUp: Boolean = false,
        ): PangramGame {
            val byWord = puzzle.words.distinctBy { it.word }.associateBy { it.word }
            return PangramGame(puzzle, hardMode, foundWords.distinct().mapNotNull { byWord[it] }, "", hints, gaveUp)
        }
    }
}
