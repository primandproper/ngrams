package software.primandproper.ngrams.core

import org.junit.jupiter.api.Test
import org.junit.jupiter.api.assertThrows
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PuzzleBankTest {
    private fun bank(json: String) = PuzzleBank.decode(json.byteInputStream())

    @Test
    fun `decodes the shipped bank`() {
        val bank = PuzzleBank.decode(resource("puzzles.json"))

        assertTrue(bank.days.size >= 260)
        for (day in bank.days) {
            val puzzles = bank.wordPuzzles(day)
            assertEquals(
                Language.entries.flatMap { language -> listOf(4, 5, 6).map { language to it } },
                puzzles.map { it.language to it.n },
                "word puzzles on $day",
            )
        }
    }

    @Test
    fun `reads word puzzles and skips the kinds and languages it doesn't know`() {
        val bank =
            bank(
                """
                {"version": 1, "seed": 7, "days": [{"date": "2027-01-01", "puzzles": [
                  {"lang": "es", "kind": "word", "n": 4, "answer": "nino", "display": "niño"},
                  {"lang": "en", "kind": "word", "n": 5, "answer": "llama"},
                  {"lang": "fr", "kind": "word", "n": 5, "answer": "lapin"},
                  {"lang": "en", "kind": "tiles", "n": 3, "tiles": ["ab"], "words": []},
                  {"lang": "en", "kind": "riddle", "n": 3}
                ]}]}
                """,
            )

        val day = PuzzleDay.parse("2027-01-01")!!
        assertEquals(listOf(day), bank.days)
        assertEquals(
            listOf(WordPuzzle(Language.EN, 5, "llama"), WordPuzzle(Language.ES, 4, "nino", "niño")),
            bank.wordPuzzles(day),
        )
        assertEquals("niño", bank.wordPuzzles(day).last().shown)
    }

    @Test
    fun `refuses an unsupported version, a bad date, and a wrong-length answer`() {
        assertThrows<BankException> { bank("""{"version": 2, "seed": 7, "days": []}""") }
        assertThrows<BankException> {
            bank("""{"version": 1, "seed": 7, "days": [{"date": "Jan 1", "puzzles": []}]}""")
        }
        assertThrows<BankException> {
            bank(
                """
                {"version": 1, "seed": 7, "days": [{"date": "2027-01-01", "puzzles": [
                  {"lang": "en", "kind": "word", "n": 4, "answer": "llama"}
                ]}]}
                """,
            )
        }
        assertThrows<BankException> { bank("not json") }
    }
}
