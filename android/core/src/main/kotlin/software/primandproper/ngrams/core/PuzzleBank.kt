package software.primandproper.ngrams.core

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.decodeFromStream
import java.io.InputStream

/** A word puzzle: guess the `n`-letter answer. */
data class WordPuzzle(
    val language: Language,
    val n: Int,
    /** Accent-folded, so it compares against guesses letter for letter. */
    val answer: String,
    /** Accented spelling, present only when it differs from [answer]. */
    val display: String? = null,
) {
    val shown: String get() = display ?: answer
}

/** A tiles board: build words from 1 to `n` tiles, and find the targets that use every tile. */
data class TilesPuzzle(
    val language: Language,
    val n: Int,
    /** Fragments, accent-folded, in the order the board first shows them. */
    val tiles: List<String>,
    /** Each target's tile indices, in reading order. */
    val targets: List<List<Int>>,
    val bonus: Int,
    val targetScore: Int,
    val words: List<TilesWord>,
    /** Folded spellings of offensive words the tiles can build. They score nothing. */
    val blocked: Set<String> = emptySet(),
)

/** A valid word on a tiles board. */
data class TilesWord(
    /** Folded spelling: the tiles joined in order. */
    val word: String,
    /** Accented spelling, present only when it differs from [word]. */
    val display: String?,
    val tiles: List<Int>,
    val points: Int,
) {
    val shown: String get() = display ?: word
}

/** A pangram board: spell words of at least four letters from `n` letters, always using the center. */
data class PangramPuzzle(
    val language: Language,
    val n: Int,
    /** Accent-folded and sorted, the center among them. */
    val letters: List<Char>,
    val center: Char,
    val targetScore: Int,
    val words: List<PangramWord>,
    /** Folded spellings of the common pangrams, every one of which the star needs. */
    val pangrams: Set<String>,
    /** Folded spellings of offensive words the letters can build. They score nothing. */
    val blocked: Set<String> = emptySet(),
) {
    /** Whether [word] uses every letter. */
    fun isPangram(word: String): Boolean = word.toSet() == letters.toSet()

    /** Whether [word] uses every letter but isn't one of the common pangrams the star needs. It scores like any pangram. */
    fun isBonusPangram(word: String): Boolean = isPangram(word) && word !in pangrams

    companion object {
        const val MIN_LENGTH = 4
    }
}

/** A valid word on a pangram board. */
data class PangramWord(
    val word: String,
    /** Accented spelling, present only when it differs from [word]. */
    val display: String?,
    val points: Int,
) {
    val shown: String get() = display ?: word
}

/** Every puzzle the app ships with, built offline by the generator. See docs/design.md. */
class PuzzleBank(
    private val words: Map<PuzzleDay, List<WordPuzzle>> = emptyMap(),
    private val tiles: Map<PuzzleDay, List<TilesPuzzle>> = emptyMap(),
    private val pangrams: Map<PuzzleDay, List<PangramPuzzle>> = emptyMap(),
) {
    val days: List<PuzzleDay> = (words.keys + tiles.keys + pangrams.keys).sorted()

    /** The day's word puzzles, by language in [Language] order, then shortest first. */
    fun wordPuzzles(day: PuzzleDay): List<WordPuzzle> = sorted(words[day]) { it.language to it.n }

    /** The day's tiles boards, by language in [Language] order, then smallest first. */
    fun tilesPuzzles(day: PuzzleDay): List<TilesPuzzle> = sorted(tiles[day]) { it.language to it.n }

    /** The day's pangram boards, by language in [Language] order, then fewest letters first. */
    fun pangramPuzzles(day: PuzzleDay): List<PangramPuzzle> = sorted(pangrams[day]) { it.language to it.n }

    private fun <P> sorted(
        puzzles: List<P>?,
        key: (P) -> Pair<Language, Int>,
    ): List<P> = puzzles.orEmpty().sortedWith(compareBy({ key(it).first.ordinal }, { key(it).second }))

    companion object {
        const val SUPPORTED_VERSION = 1

        private val json = Json { ignoreUnknownKeys = true }

        /** Decodes a bank from the generator's JSON. */
        @OptIn(ExperimentalSerializationApi::class)
        fun decode(input: InputStream): PuzzleBank {
            val file =
                try {
                    json.decodeFromStream<BankFile>(input)
                } catch (e: SerializationException) {
                    throw BankException("bank JSON doesn't decode", e)
                } catch (e: IllegalArgumentException) {
                    throw BankException("bank JSON doesn't decode", e)
                }
            if (file.version != SUPPORTED_VERSION) {
                throw BankException("bank version ${file.version} isn't supported")
            }

            val words = mutableMapOf<PuzzleDay, List<WordPuzzle>>()
            val tiles = mutableMapOf<PuzzleDay, List<TilesPuzzle>>()
            val pangrams = mutableMapOf<PuzzleDay, List<PangramPuzzle>>()
            for (day in file.days) {
                val date = PuzzleDay.parse(day.date) ?: throw BankException("bank date ${day.date} isn't YYYY-MM-DD")
                words[date] = day.puzzles.mapNotNull { it.wordPuzzle() }
                tiles[date] = day.puzzles.mapNotNull { it.tilesPuzzle() }
                pangrams[date] = day.puzzles.mapNotNull { it.pangramPuzzle() }
            }
            return PuzzleBank(words, tiles, pangrams)
        }
    }
}

class BankException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

// Wire format, as the generator writes it.

@Serializable
private data class BankFile(
    val version: Int,
    val days: List<DayFile>,
)

@Serializable
private data class DayFile(
    val date: String,
    val puzzles: List<PuzzleFile>,
)

@Serializable
private data class WordFile(
    val word: String,
    val display: String? = null,
    val tiles: List<Int> = emptyList(),
    val points: Int,
)

/** One puzzle of any kind. Kinds and languages this build doesn't know decode to nothing. */
@Serializable
private data class PuzzleFile(
    val kind: String,
    val lang: String,
    val n: Int,
    val answer: String? = null,
    val display: String? = null,
    val tiles: List<String> = emptyList(),
    val targets: List<List<Int>> = emptyList(),
    val bonus: Int = 0,
    @SerialName("target_score") val targetScore: Int = 0,
    val words: List<WordFile> = emptyList(),
    val blocked: List<String> = emptyList(),
    val letters: List<String> = emptyList(),
    val center: String? = null,
    val pangrams: List<String> = emptyList(),
) {
    private fun language(expected: PuzzleKind): Language? = if (PuzzleKind.fromCode(kind) == expected) Language.fromCode(lang) else null

    fun wordPuzzle(): WordPuzzle? {
        val language = language(PuzzleKind.WORD) ?: return null
        val answer = answer ?: throw BankException("word puzzle has no answer")
        if (answer.codePointCount(0, answer.length) != n) {
            throw BankException("answer $answer isn't $n letters")
        }
        return WordPuzzle(language, n, answer, display)
    }

    fun tilesPuzzle(): TilesPuzzle? {
        val language = language(PuzzleKind.TILES) ?: return null
        for (index in targets.flatten() + words.flatMap { it.tiles }) {
            if (index !in tiles.indices) {
                throw BankException("tile index $index is outside a ${tiles.size}-tile board")
            }
        }
        return TilesPuzzle(
            language = language,
            n = n,
            tiles = tiles,
            targets = targets,
            bonus = bonus,
            targetScore = targetScore,
            words = words.map { TilesWord(it.word, it.display, it.tiles, it.points) },
            blocked = blocked.toSet(),
        )
    }

    fun pangramPuzzle(): PangramPuzzle? {
        val language = language(PuzzleKind.PANGRAM) ?: return null
        val letters = letters.mapNotNull { it.firstOrNull() }
        val center = center?.firstOrNull()?.takeIf { it in letters } ?: throw BankException("pangram center $center isn't a letter")
        for (word in words) {
            if (center !in word.word || !letters.containsAll(word.word.toList())) {
                throw BankException("${word.word} doesn't fit its pangram board")
            }
        }
        return PangramPuzzle(
            language = language,
            n = n,
            letters = letters,
            center = center,
            targetScore = targetScore,
            words = words.map { PangramWord(it.word, it.display, it.points) },
            pangrams = pangrams.toSet(),
            blocked = blocked.toSet(),
        )
    }
}
