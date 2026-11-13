package software.primandproper.ngrams.core

/** How a guessed letter compares with the answer. Declared worst to best, so `maxOf` picks the best. */
enum class LetterMark { ABSENT, PRESENT, CORRECT }

/** A revealed hint that hard mode makes every later guess use. */
sealed interface Hint {
    /** A correct letter has to stay in its spot, counted from zero. */
    data class Position(
        val letter: Char,
        val index: Int,
    ) : Hint

    /** A found letter has to appear at least as often as an earlier guess showed it. */
    data class Letter(
        val letter: Char,
    ) : Hint
}

sealed interface Submission {
    data class Guessed(
        val guess: String,
    ) : Submission

    data object TooShort : Submission

    data class Blocked(
        val guess: String,
    ) : Submission

    data class NotAWord(
        val guess: String,
    ) : Submission

    data class MissingHint(
        val hint: Hint,
    ) : Submission

    data object Over : Submission
}

sealed interface Status {
    data object Playing : Status

    data class Won(
        val guesses: Int,
    ) : Status

    data object Lost : Status
}

/**
 * The rules of one word puzzle: the letters typed so far, the guesses made, and whether the puzzle
 * is over. Immutable, so a screen can hold it as state; every move returns a new game.
 */
class WordGame private constructor(
    val puzzle: WordPuzzle,
    /** Whether each guess has to use every hint revealed so far. */
    val hardMode: Boolean,
    /** Submitted guesses, oldest first. */
    val guesses: List<String>,
    /** Letters typed toward the next guess. */
    val current: String,
    /** Hints taken, oldest first, each in the game's own terms. A hint never changes the result. */
    val hints: List<String>,
    /** Whether the player had the puzzle solved for them, which gives up the win. */
    val gaveUp: Boolean,
) {
    /** The result of submitting: the game after it, and what happened. */
    data class Submitted(
        val game: WordGame,
        val submission: Submission,
    )

    val status: Status
        get() =
            when {
                guesses.lastOrNull() == puzzle.answer -> Status.Won(guesses.size)
                // A puzzle solved for the player is lost, whatever guesses were left.
                gaveUp -> Status.Lost
                guesses.size >= MAX_GUESSES -> Status.Lost
                else -> Status.Playing
            }

    val isOver: Boolean get() = status != Status.Playing

    /** Each guess's marks, in the order guessed. */
    val marks: List<List<LetterMark>> get() = guesses.map { marks(it, puzzle.answer) }

    /** The best mark each guessed letter has earned, for the keyboard. */
    val letterMarks: Map<Char, LetterMark>
        get() {
            val best = mutableMapOf<Char, LetterMark>()
            for ((guess, marks) in guesses.zip(marks)) {
                for ((letter, mark) in guess.toList().zip(marks)) {
                    best[letter] = maxOf(best[letter] ?: LetterMark.ABSENT, mark)
                }
            }
            return best
        }

    fun takeHint(hint: String): WordGame = if (isOver) this else copy(hints = hints + hint)

    /** Solves the puzzle for the player, as a loss. A puzzle that's over stays as it was. */
    fun giveUp(): WordGame = if (isOver) this else copy(current = "", gaveUp = true)

    /** Whether hard mode keeps [letter] from being typed: an earlier guess showed it isn't in the answer anywhere. */
    fun isRuledOut(letter: Char): Boolean = hardMode && letterMarks[letter] == LetterMark.ABSENT

    fun type(letter: Char): WordGame =
        if (!isOver && current.length < puzzle.n && !isRuledOut(letter)) copy(current = current + letter) else this

    fun deleteLetter(): WordGame = if (current.isEmpty()) this else copy(current = current.dropLast(1))

    /** Checks the typed letters against [list]. A guess the list rejects stays typed, so it can be corrected. */
    fun submit(list: GuessList): Submitted {
        if (isOver) {
            return Submitted(this, Submission.Over)
        }
        if (current.length != puzzle.n) {
            return Submitted(this, Submission.TooShort)
        }
        val guess = current
        if (guess in list.blocked) {
            return Submitted(this, Submission.Blocked(guess))
        }
        if (guess != puzzle.answer && guess !in list.accepted) {
            return Submitted(this, Submission.NotAWord(guess))
        }
        if (hardMode) {
            missingHint(guess)?.let { return Submitted(this, Submission.MissingHint(it)) }
        }
        return Submitted(copy(guesses = guesses + guess, current = ""), Submission.Guessed(guess))
    }

    /**
     * The first hint [guess] leaves out: correct letters out of their spot first, then found
     * letters it has too few copies of, both in the order they were revealed.
     */
    fun missingHint(guess: String): Hint? {
        val marks = marks
        for ((previous, previousMarks) in guesses.zip(marks)) {
            for ((i, mark) in previousMarks.withIndex()) {
                if (mark == LetterMark.CORRECT && guess[i] != previous[i]) {
                    return Hint.Position(previous[i], i)
                }
            }
        }

        val required = mutableMapOf<Char, Int>()
        for ((previous, previousMarks) in guesses.zip(marks)) {
            val found = mutableMapOf<Char, Int>()
            for ((letter, mark) in previous.toList().zip(previousMarks)) {
                if (mark != LetterMark.ABSENT) {
                    found[letter] = (found[letter] ?: 0) + 1
                }
            }
            for ((letter, count) in found) {
                required[letter] = maxOf(required[letter] ?: 0, count)
            }
        }
        for (letter in guesses.joinToString("")) {
            if (guess.count { it == letter } < (required[letter] ?: 0)) {
                return Hint.Letter(letter)
            }
        }
        return null
    }

    private fun copy(
        guesses: List<String> = this.guesses,
        current: String = this.current,
        hints: List<String> = this.hints,
        gaveUp: Boolean = this.gaveUp,
    ): WordGame = WordGame(puzzle, hardMode, guesses, current, hints, gaveUp)

    companion object {
        const val MAX_GUESSES = 6

        /**
         * Starts a puzzle, restoring [guesses], [hints] and [gaveUp] from saved progress. Saved
         * guesses the puzzle can't hold (the wrong length, or past the end) are dropped.
         */
        operator fun invoke(
            puzzle: WordPuzzle,
            guesses: List<String> = emptyList(),
            hardMode: Boolean = false,
            hints: List<String> = emptyList(),
            gaveUp: Boolean = false,
        ): WordGame {
            var game = WordGame(puzzle, hardMode, emptyList(), "", hints, gaveUp = false)
            for (guess in guesses) {
                if (game.status == Status.Playing && guess.length == puzzle.n) {
                    game = game.copy(guesses = game.guesses + guess)
                }
            }
            return if (gaveUp && game.status == Status.Playing) game.copy(gaveUp = true) else game
        }

        /**
         * Marks [guess] against [answer]. Correct letters are marked first, then a misplaced letter
         * is present only while the answer has copies of it left over, so guessing a letter twice
         * doesn't mark it twice against an answer that has it once.
         */
        fun marks(
            guess: String,
            answer: String,
        ): List<LetterMark> {
            val marks = MutableList(guess.length) { LetterMark.ABSENT }
            val leftover = mutableMapOf<Char, Int>()
            for ((i, letter) in answer.withIndex()) {
                if (i < guess.length && guess[i] != letter) {
                    leftover[letter] = (leftover[letter] ?: 0) + 1
                }
            }
            for ((i, letter) in guess.withIndex()) {
                val count = leftover[letter] ?: 0
                if (i < answer.length && answer[i] == letter) {
                    marks[i] = LetterMark.CORRECT
                } else if (count > 0) {
                    marks[i] = LetterMark.PRESENT
                    leftover[letter] = count - 1
                }
            }
            return marks
        }
    }
}
