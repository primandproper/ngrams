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

private val monthNames = listOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

/** "Oct 25", or "Oct 25, 2026" with the year. Always English, like the rest of the app's text. */
fun PuzzleDay.name(includingYear: Boolean): String {
    val name = "${monthNames[date.monthValue - 1]} ${date.dayOfMonth}"
    return if (includingYear) "$name, ${date.year}" else name
}
