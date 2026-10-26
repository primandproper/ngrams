package software.primandproper.ngrams.core

import org.junit.jupiter.api.Test
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertNull

class PuzzleDayTest {
    @Test
    fun `parses YYYY-MM-DD and nothing else`() {
        assertEquals("2026-10-26", PuzzleDay.parse("2026-10-26").toString())
        assertNull(PuzzleDay.parse("2026-1-26"))
        assertNull(PuzzleDay.parse("2026-02-30"))
        assertNull(PuzzleDay.parse("Oct 26"))
    }

    @Test
    fun `rolls over at local midnight`() {
        // 2026-10-27 at 02:00 UTC is still the 26th in Chicago.
        val instant = Instant.parse("2026-10-27T02:00:00Z")

        assertEquals("2026-10-27", PuzzleDay.today(Clock.fixed(instant, ZoneId.of("UTC"))).toString())
        assertEquals("2026-10-26", PuzzleDay.today(Clock.fixed(instant, ZoneId.of("America/Chicago"))).toString())
    }
}
