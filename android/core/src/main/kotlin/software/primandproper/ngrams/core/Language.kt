package software.primandproper.ngrams.core

/** The languages the bank carries puzzles for, in the order the app lists them. */
enum class Language(
    val code: String,
    val displayName: String,
    /** The country whose word list and usage the language follows. */
    val flag: String,
) {
    EN("en", "English", "🇺🇸"),
    ES("es", "Español", "🇲🇽"),
    ;

    companion object {
        fun fromCode(code: String): Language? = entries.firstOrNull { it.code == code }
    }
}

/** The game kinds, as the bank and saved progress name them. */
enum class PuzzleKind(
    val code: String,
    val displayName: String,
) {
    WORD("word", "Password"),
    TILES("tiles", "Tiles"),
    PANGRAM("pangram", "Pangram"),
    ;

    companion object {
        fun fromCode(code: String): PuzzleKind? = entries.firstOrNull { it.code == code }
    }
}

/** The languages a device is set up for, given its preferred language tags, as a first guess. */
fun suggestedLanguages(preferred: List<String>): Set<Language> {
    val codes = preferred.map { it.substringBefore('-').substringBefore('_').lowercase() }.toSet()
    return Language.entries.filter { it.code in codes }.toSet()
}
