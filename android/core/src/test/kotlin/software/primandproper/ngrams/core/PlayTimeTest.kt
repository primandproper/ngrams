package software.primandproper.ngrams.core

import org.junit.jupiter.api.Test
import java.time.Duration
import java.time.Instant
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

private val start = Instant.parse("2027-01-01T12:00:00Z")

private fun at(seconds: Long): Instant = start.plusSeconds(seconds)

class PlayClockTest {
    @Test
    fun `opens a stretch on resume and closes it on pause`() {
        val clock = PlayClock().resume(at(0)).tick(at(10)).pause(at(20)).tick(at(30))

        assertEquals(listOf(PlayStretch(at(0), at(20))), clock.stretches)
        assertFalse(clock.isRunning)
    }

    @Test
    fun `keeps one stretch open when resumed twice`() {
        assertEquals(1, PlayClock().resume(at(0)).resume(at(5)).stretches.size)
    }

    @Test
    fun `adds to the stretches already saved`() {
        val saved = PlayStretch(at(0), at(60))

        val clock = PlayClock(listOf(saved)).resume(at(3600))

        assertEquals(listOf(saved, PlayStretch(at(3600), at(3600))), clock.stretches)
    }
}

class PlayTimerTest {
    @Test
    fun `counts time on screen`() {
        val timer = PlayTimer().resume(at(0)).tick(at(30)).pause(at(30)).resume(at(600)).tick(at(615))

        assertEquals(Duration.ofSeconds(45), timer.elapsed)
    }

    @Test
    fun `stops the time when the puzzle is finished`() {
        val timer = PlayTimer().resume(at(0)).entry(at(20), completes = true).tick(at(120))

        assertEquals(at(20), timer.completedAt)
        assertEquals(Duration.ofSeconds(20), timer.elapsed)
    }

    @Test
    fun `keeps the first completion`() {
        val timer = PlayTimer().resume(at(0)).entry(at(20), completes = true).entry(at(40), completes = true)

        assertEquals(at(20), timer.completedAt)
    }

    @Test
    fun `is due to save once the checkpoint interval passes`() {
        val timer = PlayTimer().resume(at(0))
        assertTrue(timer.checkpointDue(at(0)))

        val saved = timer.saved(at(0))
        assertFalse(saved.checkpointDue(at(29)))
        assertTrue(saved.checkpointDue(at(30)))
    }

    @Test
    fun `shows no time for a puzzle started before timing existed`() {
        assertNull(PlayTimer(timed = false).resume(at(0)).tick(at(30)).elapsed)
    }

    @Test
    fun `formats time the way a clock reads`() {
        assertEquals("0:05", formattedTime(Duration.ofSeconds(5)))
        assertEquals("4:05", formattedTime(Duration.ofSeconds(245)))
        assertEquals("1:02:03", formattedTime(Duration.ofSeconds(3723)))
    }
}
