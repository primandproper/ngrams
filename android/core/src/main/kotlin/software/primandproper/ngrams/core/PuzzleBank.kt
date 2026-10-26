package software.primandproper.ngrams.core

import kotlinx.serialization.ExperimentalSerializationApi
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

/**
 * Every puzzle the app ships with, built offline by the generator. The prototype reads only word
 * puzzles; the other kinds decode to nothing for now.
 */
class PuzzleBank(
    private val words: Map<PuzzleDay, List<WordPuzzle>>,
) {
    val days: List<PuzzleDay> = words.keys.sorted()

    /** The day's word puzzles, by language in [Language] order, then shortest first. */
    fun wordPuzzles(day: PuzzleDay): List<WordPuzzle> = words[day].orEmpty().sortedWith(compareBy({ it.language.ordinal }, { it.n }))

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
            for (day in file.days) {
                val date = PuzzleDay.parse(day.date) ?: throw BankException("bank date ${day.date} isn't YYYY-MM-DD")
                words[date] = day.puzzles.mapNotNull { it.wordPuzzle() }
            }
            return PuzzleBank(words)
        }
    }
}

class BankException(
    message: String,
    cause: Throwable? = null,
) : Exception(message, cause)

// Wire format. Unknown keys are skipped rather than built into a tree, so the other kinds' long
// word lists cost a parse but no memory.

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

/** One puzzle of any kind. Kinds and languages this build doesn't know decode to nothing. */
@Serializable
private data class PuzzleFile(
    val kind: String,
    val lang: String,
    val n: Int,
    val answer: String? = null,
    val display: String? = null,
) {
    fun wordPuzzle(): WordPuzzle? {
        if (PuzzleKind.fromCode(kind) != PuzzleKind.WORD) {
            return null
        }
        val language = Language.fromCode(lang) ?: return null
        val answer = answer ?: throw BankException("word puzzle has no answer")
        if (answer.codePointCount(0, answer.length) != n) {
            throw BankException("answer $answer isn't $n letters")
        }
        return WordPuzzle(language, n, answer, display)
    }
}
