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
) {
    WORD("word"),
    TILES("tiles"),
    PANGRAM("pangram"),
    ;

    /** The game's name in [interfaceLanguage], which share text uses as well as the screens. */
    fun displayName(interfaceLanguage: Language): String =
        when (interfaceLanguage) {
            Language.EN ->
                when (this) {
                    WORD -> "Password"
                    TILES -> "Tiles"
                    PANGRAM -> "Pangram"
                }
            Language.ES ->
                when (this) {
                    WORD -> "Contraseña"
                    TILES -> "Fichas"
                    PANGRAM -> "Pangrama"
                }
        }

    companion object {
        fun fromCode(code: String): PuzzleKind? = entries.firstOrNull { it.code == code }
    }
}

/** The languages a device is set up for, given its preferred language tags, as a first guess. */
fun suggestedLanguages(preferred: List<String>): Set<Language> {
    val codes = preferred.map { it.substringBefore('-').substringBefore('_').lowercase() }.toSet()
    return Language.entries.filter { it.code in codes }.toSet()
}

/** [languages] as comma-separated codes, in [Language] order: how the app stores a set of them. */
fun languageCodes(languages: Set<Language>): String = Language.entries.filter(languages::contains).joinToString(",") { it.code }

/** The languages in comma-separated [codes]. Codes this build doesn't know are dropped. */
fun languagesFrom(codes: String): Set<Language> = codes.split(",").mapNotNull(Language::fromCode).toSet()
