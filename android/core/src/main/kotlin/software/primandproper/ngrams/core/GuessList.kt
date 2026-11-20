package software.primandproper.ngrams.core

/**
 * The words a word puzzle of one language and length accepts as guesses, built offline by the
 * generator alongside the bank.
 */
class GuessList(
    val accepted: Set<String>,
    /** Valid but offensive words, answered apart from words the list doesn't know. */
    val blocked: Set<String> = emptySet(),
    /** The blocked words a player can turn on: swearing, not slurs. */
    val profane: Set<String> = emptySet(),
) {
    /** The list with curse words on: its profane words are guesses like any other. */
    val withCurseWords: GuessList get() = GuessList(accepted + profane, blocked - profane)

    companion object {
        /** Parses the generator's one-word-per-line files. */
        fun parse(
            accepted: String,
            blocked: String,
            profane: String = "",
        ): GuessList = GuessList(words(accepted), words(blocked), words(profane))

        /** The bundled file name for [language] and [n], without the `.txt`. */
        fun name(
            language: Language,
            n: Int,
        ): String = "${language.code}-$n"

        private fun words(text: String): Set<String> = text.lineSequence().filter { it.isNotEmpty() }.toSet()
    }
}
