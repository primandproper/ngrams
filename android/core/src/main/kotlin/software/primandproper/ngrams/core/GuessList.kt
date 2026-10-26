package software.primandproper.ngrams.core

/**
 * The words a word puzzle of one language and length accepts as guesses, built offline by the
 * generator alongside the bank.
 */
class GuessList(
    val accepted: Set<String>,
    /** Valid but offensive words, answered apart from words the list doesn't know. */
    val blocked: Set<String> = emptySet(),
) {
    companion object {
        /** Parses the generator's one-word-per-line files. */
        fun parse(
            accepted: String,
            blocked: String,
        ): GuessList = GuessList(words(accepted), words(blocked))

        /** The bundled file name for [language] and [n], without the `.txt`. */
        fun name(
            language: Language,
            n: Int,
        ): String = "${language.code}-$n"

        private fun words(text: String): Set<String> = text.lineSequence().filter { it.isNotEmpty() }.toSet()
    }
}
