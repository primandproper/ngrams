package software.primandproper.ngrams.core

sealed interface TilesSubmission {
    data class Found(
        val word: TilesWord,
    ) : TilesSubmission

    data class AlreadyFound(
        val word: TilesWord,
    ) : TilesSubmission

    data class Blocked(
        val text: String,
    ) : TilesSubmission

    data class NotAWord(
        val text: String,
    ) : TilesSubmission

    data object Empty : TilesSubmission
}

/**
 * The rules of one tiles board: which tiles are selected, what's been found, and the score.
 * Immutable; every move returns a new game.
 */
class TilesGame private constructor(
    val puzzle: TilesPuzzle,
    /** Whether a found target's tiles leave the board, so no other word can use them. */
    val solvedTilesLeave: Boolean,
    /** Words found so far, oldest first. */
    val found: List<TilesWord>,
    /** Selected tile indices, in the order they were tapped. */
    val selection: List<Int>,
    /** Hints taken, oldest first, each in the game's own terms. A hint never changes the result. */
    val hints: List<String>,
    /** Whether the player had the puzzle solved for them, which gives up the star. */
    val gaveUp: Boolean,
) {
    data class Submitted(
        val game: TilesGame,
        val submission: TilesSubmission,
    )

    /** The board's words by spelling, the first of any repeat winning, as on iOS. */
    private val words: Map<String, TilesWord> = puzzle.words.distinctBy { it.word }.associateBy { it.word }
    private val targetIndex: Map<String, Int> =
        puzzle.targets.withIndex().associate { (i, target) -> target.joinToString("") { puzzle.tiles[it] } to i }

    val selectedText: String get() = selection.joinToString("") { puzzle.tiles[it] }

    /** Folded spellings of the found words, oldest first, for saving. */
    val foundWords: List<String> get() = found.map { it.word }

    /** Indices into the puzzle's targets of the targets found, oldest first. */
    val solvedTargets: List<Int> get() = found.mapNotNull { targetIndex[it.word] }

    /** Tiles belonging to a found target. */
    val solvedTiles: Set<Int> get() = solvedTargets.flatMap { puzzle.targets[it] }.toSet()

    val allTargetsFound: Boolean get() = solvedTargets.size == puzzle.targets.size

    val score: Int get() = found.sumOf { it.points } + if (allTargetsFound) puzzle.bonus else 0

    /** A star takes every target and the target score. */
    val earnedStar: Boolean get() = !gaveUp && allTargetsFound && score >= puzzle.targetScore

    /**
     * Whether an unfound word can still be spelled from the tiles left on the board. Once solved tiles leave, finding
     * every target leaves none.
     */
    val hasWordsLeft: Boolean
        get() {
            val found = foundWords.toSet()
            val gone = if (solvedTilesLeave) solvedTiles else emptySet()
            return puzzle.words.any { it.word !in found && it.tiles.none { tile -> tile in gone } }
        }

    /** A board is over once it has its star, was solved for the player, or has no words left. */
    val isOver: Boolean get() = earnedStar || gaveUp || !hasWordsLeft

    fun takeHint(hint: String): TilesGame = copy(hints = hints + hint)

    /** Solves the board for the player, finding [words], and gives up its star. */
    fun giveUp(words: List<String>): TilesGame =
        copy(found = found + words.distinct().filter { it !in foundWords }.mapNotNull { this.words[it] }, gaveUp = true)

    /**
     * Selects a tile, or deselects it if it's already selected. A word holds at most `n` tiles,
     * and solved tiles can't be selected once they've left the board.
     */
    fun toggle(tile: Int): TilesGame =
        when {
            tile in selection -> copy(selection = selection - tile)
            selection.size < puzzle.n && tile in puzzle.tiles.indices && !(solvedTilesLeave && tile in solvedTiles) ->
                copy(selection = selection + tile)
            else -> this
        }

    fun clearSelection(): TilesGame = copy(selection = emptyList())

    /** Checks the selected tiles as a word and clears the selection. */
    fun submit(): Submitted {
        val text = selectedText
        if (text.isEmpty()) {
            return Submitted(this, TilesSubmission.Empty)
        }
        val cleared = copy(selection = emptyList())
        if (text in puzzle.blocked) {
            return Submitted(cleared, TilesSubmission.Blocked(text))
        }
        val word = words[text] ?: return Submitted(cleared, TilesSubmission.NotAWord(text))
        if (word in found) {
            return Submitted(cleared, TilesSubmission.AlreadyFound(word))
        }
        return Submitted(cleared.copy(found = found + word), TilesSubmission.Found(word))
    }

    private fun copy(
        found: List<TilesWord> = this.found,
        selection: List<Int> = this.selection,
        hints: List<String> = this.hints,
        gaveUp: Boolean = this.gaveUp,
    ): TilesGame = TilesGame(puzzle, solvedTilesLeave, found, selection, hints, gaveUp)

    companion object {
        /**
         * Starts a board, restoring [foundWords], [hints] and [gaveUp] from saved progress. Saved words the board doesn't
         * have (the bank was rebuilt since) are dropped, as are repeats.
         */
        operator fun invoke(
            puzzle: TilesPuzzle,
            foundWords: List<String> = emptyList(),
            solvedTilesLeave: Boolean = false,
            hints: List<String> = emptyList(),
            gaveUp: Boolean = false,
        ): TilesGame {
            val byWord = puzzle.words.distinctBy { it.word }.associateBy { it.word }
            val found = foundWords.distinct().mapNotNull { byWord[it] }
            return TilesGame(puzzle, solvedTilesLeave, found, emptyList(), hints, gaveUp)
        }
    }
}
