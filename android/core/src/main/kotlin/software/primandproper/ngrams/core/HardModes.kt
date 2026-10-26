package software.primandproper.ngrams.core

/** Where each game's hard mode is stored, as the languages it's on for, and the move to that. */
object HardModes {
    /** The languages [kind]'s hard mode is on for, as [languageCodes]. */
    fun key(kind: PuzzleKind): String = "${legacyKey(kind)}Languages"

    /** The single switch [kind]'s hard mode was before it went per language. */
    fun legacyKey(kind: PuzzleKind): String =
        when (kind) {
            PuzzleKind.WORD -> "wordHardMode"
            PuzzleKind.TILES -> "solvedTilesLeave"
            PuzzleKind.PANGRAM -> "pangramHardMode"
        }

    /**
     * Each game's languages after moving the old switches over. A game with only its old switch
     * gets every language if the switch was on and none if it was off; a game already stored per
     * language keeps that.
     */
    fun migrated(
        legacy: Map<PuzzleKind, Boolean>,
        current: Map<PuzzleKind, Set<Language>>,
    ): Map<PuzzleKind, Set<Language>> =
        current + legacy.filterKeys { it !in current }.mapValues { (_, on) -> if (on) Language.entries.toSet() else emptySet() }
}
