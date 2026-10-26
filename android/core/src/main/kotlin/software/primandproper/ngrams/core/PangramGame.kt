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
    val earnedStar: Boolean get() = foundPangrams == puzzle.pangrams.size && score >= puzzle.targetScore

    fun type(letter: Char): PangramGame = copy(current = current + letter)

    fun deleteLetter(): PangramGame = if (current.isEmpty()) this else copy(current = current.dropLast(1))

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
    ): PangramGame = PangramGame(puzzle, hardMode, found, current)

    companion object {
        /**
         * Starts a board, restoring [foundWords] from saved progress. Saved words the board doesn't
         * have (the bank was rebuilt since) are dropped, as are repeats.
         */
        operator fun invoke(
            puzzle: PangramPuzzle,
            foundWords: List<String> = emptyList(),
            hardMode: Boolean = false,
        ): PangramGame {
            val byWord = puzzle.words.distinctBy { it.word }.associateBy { it.word }
            return PangramGame(puzzle, hardMode, foundWords.distinct().mapNotNull { byWord[it] }, "")
        }
    }
}
