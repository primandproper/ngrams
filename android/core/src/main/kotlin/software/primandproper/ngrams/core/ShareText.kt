package software.primandproper.ngrams.core

/**
 * Spoiler-free results to paste anywhere: one puzzle's, or every puzzle started on a day. A `*`
 * marks a result played in hard mode, and a ⭐ one that earned its star. Written in the sharer's
 * interface language, and matches the iOS app's text exactly; testdata/share.json holds both apps
 * to it.
 */
object ShareText {
    /** Appended to every share: one page for both stores, so a share works whoever receives it. */
    const val LINK = "https://primandproper.software/ngrams/"

    /** The headline and the guess grid. */
    fun word(
        game: WordGame,
        day: PuzzleDay,
        interfaceLanguage: Language,
    ): String {
        val puzzle = game.puzzle
        val grid = game.marks.map { marks -> marks.joinToString("") { it.square } }
        return finished(listOf(headline(PuzzleKind.WORD, puzzle.language, puzzle.n, day, interfaceLanguage) + " · " + result(game)) + grid)
    }

    /** The headline, then progress toward the target and the targets found. */
    fun tiles(
        game: TilesGame,
        day: PuzzleDay,
        interfaceLanguage: Language,
    ): String {
        val puzzle = game.puzzle
        val targets =
            when (interfaceLanguage) {
                Language.EN -> "targets"
                Language.ES -> "objetivos"
            }
        return finished(
            listOf(
                headline(PuzzleKind.TILES, puzzle.language, puzzle.n, day, interfaceLanguage) + " · " + result(game),
                bar(game.score, puzzle.targetScore) + " ${game.solvedTargets.size}/${puzzle.targets.size} $targets",
            ),
        )
    }

    /** The headline, then progress toward the target and the common pangrams found. */
    fun pangram(
        game: PangramGame,
        day: PuzzleDay,
        interfaceLanguage: Language,
    ): String {
        val puzzle = game.puzzle
        val pangrams = puzzle.pangrams.size
        val noun = PuzzleKind.PANGRAM.displayName(interfaceLanguage).lowercase() + if (pangrams == 1) "" else "s"
        return finished(
            listOf(
                headline(PuzzleKind.PANGRAM, puzzle.language, puzzle.n, day, interfaceLanguage) + " · " + result(game),
                bar(game.score, puzzle.targetScore) + " ${game.foundPangrams}/$pangrams $noun",
            ),
        )
    }

    /** A line per language and game with the result of each puzzle started, or null if none was. */
    fun day(
        words: List<WordGame>,
        tiles: List<TilesGame>,
        pangrams: List<PangramGame>,
        day: PuzzleDay,
        interfaceLanguage: Language,
    ): String? {
        val lines = mutableListOf<String>()
        for (language in Language.entries) {
            val results =
                listOf(
                    PuzzleKind.WORD to
                        words
                            .filter { it.puzzle.language == language && it.guesses.isNotEmpty() }
                            .sortedBy { it.puzzle.n }
                            .map { "n=${it.puzzle.n} ${result(it)}" },
                    PuzzleKind.TILES to
                        tiles
                            .filter { it.puzzle.language == language && it.found.isNotEmpty() }
                            .sortedBy { it.puzzle.n }
                            .map { "n=${it.puzzle.n} ${result(it)}" },
                    PuzzleKind.PANGRAM to
                        pangrams
                            .filter { it.puzzle.language == language && it.found.isNotEmpty() }
                            .sortedBy { it.puzzle.n }
                            .map { "n=${it.puzzle.n} ${result(it)}" },
                )
            for ((kind, kindResults) in results) {
                if (kindResults.isNotEmpty()) {
                    lines += "${language.flag} ${kind.displayName(interfaceLanguage)} · " + kindResults.joinToString(" · ")
                }
            }
        }
        if (lines.isEmpty()) {
            return null
        }
        return finished(listOf("n-grams · ${day.name(includingYear = false, interfaceLanguage)}") + lines)
    }

    private fun headline(
        kind: PuzzleKind,
        language: Language,
        n: Int,
        day: PuzzleDay,
        interfaceLanguage: Language,
    ): String =
        "n-grams · ${kind.displayName(interfaceLanguage)} ${language.flag} n=$n · ${day.name(includingYear = false, interfaceLanguage)}"

    private fun result(game: WordGame): String {
        val guesses =
            when (val status = game.status) {
                is Status.Won -> "${status.guesses}"
                Status.Lost -> "X"
                Status.Playing -> "${game.guesses.size}"
            }
        return "$guesses/${WordGame.MAX_GUESSES}" + marks(game.hardMode, game.status is Status.Won)
    }

    private fun result(game: TilesGame): String = "${game.score}/${game.puzzle.targetScore}" + marks(game.solvedTilesLeave, game.earnedStar)

    private fun result(game: PangramGame): String = "${game.score}/${game.puzzle.targetScore}" + marks(game.hardMode, game.earnedStar)

    private fun marks(
        hard: Boolean,
        star: Boolean,
    ): String = (if (hard) "*" else "") + (if (star) " ⭐" else "")

    /** Ten segments, full once [score] reaches [target]. */
    private fun bar(
        score: Int,
        target: Int,
    ): String {
        val filled = minOf(10, score * 10 / maxOf(target, 1))
        return "▰".repeat(filled) + "▱".repeat(10 - filled)
    }

    private fun finished(lines: List<String>): String = (lines + LINK).joinToString("\n")
}

/** How a share shows the mark, matching the board: filled in place, light in the word, and dark for absent. */
val LetterMark.square: String
    get() =
        when (this) {
            LetterMark.CORRECT -> "🟦"
            LetterMark.PRESENT -> "⬜"
            LetterMark.ABSENT -> "⬛"
        }
