package software.primandproper.ngrams.core

import java.time.Clock
import java.time.LocalDate
import java.time.format.DateTimeParseException

/**
 * A calendar day, as the bank and saved progress key it: `YYYY-MM-DD` in the device's time zone,
 * so the day rolls over at local midnight.
 */
data class PuzzleDay(
    val date: LocalDate,
) : Comparable<PuzzleDay> {
    override fun compareTo(other: PuzzleDay): Int = date.compareTo(other.date)

    /** `YYYY-MM-DD`, the form the bank and saved progress use. */
    override fun toString(): String = date.toString()

    companion object {
        private val pattern = Regex("""\d{4}-\d{2}-\d{2}""")

        /** Parses `YYYY-MM-DD`, or returns null for anything else. */
        fun parse(text: String): PuzzleDay? {
            if (!pattern.matches(text)) {
                return null
            }
            return try {
                PuzzleDay(LocalDate.parse(text))
            } catch (e: DateTimeParseException) {
                null
            }
        }

        /** The day it is on [clock], whose zone decides when midnight falls. */
        fun today(clock: Clock = Clock.systemDefaultZone()): PuzzleDay = PuzzleDay(LocalDate.now(clock))
    }
}

private val englishMonths = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
private val spanishMonths = listOf("ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic")

/**
 * The day in [interfaceLanguage]: "Oct 25" or "Oct 25, 2026" in English, "25 oct" or "25 oct 2026"
 * in Spanish. Spelled out here rather than left to the platform's formatter, so share text matches
 * the iOS app's exactly.
 */
fun PuzzleDay.name(
    includingYear: Boolean,
    interfaceLanguage: Language,
): String {
    val month = date.monthValue - 1
    return when (interfaceLanguage) {
        Language.EN -> "${englishMonths[month]} ${date.dayOfMonth}" + if (includingYear) ", ${date.year}" else ""
        Language.ES -> "${date.dayOfMonth} ${spanishMonths[month]}" + if (includingYear) " ${date.year}" else ""
    }
}
