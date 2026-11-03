package software.primandproper.ngrams.core

import java.time.Duration
import java.time.Instant
import java.util.Locale

/** One stretch of time a puzzle spent on screen with the app in front. */
data class PlayStretch(
    val start: Instant,
    val end: Instant,
)

/** What a puzzle's time is worked out from. Only the stretches are saved; the time itself never is. */
object PlayTime {
    /**
     * [saved] with [stretches] folded in. A stretch starting when a saved one does keeps the later of
     * the two ends, so saving an open stretch again only ever extends it; any other is added.
     */
    fun merged(
        saved: List<PlayStretch>,
        stretches: List<PlayStretch>,
    ): List<PlayStretch> {
        val byStart = saved.distinctBy { it.start }.associateBy { it.start }.toMutableMap()
        for (stretch in stretches) {
            val existing = byStart[stretch.start]
            byStart[stretch.start] = if (existing == null) stretch else existing.copy(end = maxOf(existing.end, stretch.end))
        }
        return byStart.values.sortedBy { it.start }
    }

    /**
     * Time on screen up to [completedAt], or all of it for an unfinished puzzle. Play after a puzzle
     * is finished is kept but doesn't count toward its time.
     */
    fun active(
        stretches: List<PlayStretch>,
        completedAt: Instant?,
    ): Duration =
        stretches.fold(Duration.ZERO) { total, stretch ->
            val end = completedAt?.let { minOf(stretch.end, it) } ?: stretch.end
            val length = Duration.between(stretch.start, end)
            if (length.isNegative) total else total + length
        }
}

/**
 * Times one puzzle's play as stretches: one opens when the puzzle comes on screen and closes when it
 * leaves or the app goes to the background.
 */
data class PlayClock(
    val stretches: List<PlayStretch> = emptyList(),
    val isRunning: Boolean = false,
) {
    fun resume(now: Instant): PlayClock = if (isRunning) this else PlayClock(stretches + PlayStretch(now, now), isRunning = true)

    /** Moves the open stretch's end up to [now]. */
    fun tick(now: Instant): PlayClock {
        val last = stretches.lastOrNull()
        if (!isRunning || last == null) return this
        return copy(stretches = stretches.dropLast(1) + last.copy(end = maxOf(last.end, now)))
    }

    fun pause(now: Instant): PlayClock = tick(now).copy(isRunning = false)
}

/**
 * One puzzle's timing in play, as plain values the app saves from: the clock, when the puzzle was
 * finished, and when its stretches were last saved.
 */
data class PlayTimer(
    val clock: PlayClock = PlayClock(),
    /** When the puzzle was finished, which stops its time. */
    val completedAt: Instant? = null,
    /** Whether the puzzle has a time to show: false for one started before timing existed. */
    val timed: Boolean = true,
    val lastSaved: Instant? = null,
) {
    /** The puzzle's time as of the last tick, or null if it has none to show. */
    val elapsed: Duration? get() = if (timed) PlayTime.active(clock.stretches, completedAt) else null

    fun resume(now: Instant): PlayTimer = copy(clock = clock.resume(now))

    fun pause(now: Instant): PlayTimer = copy(clock = clock.pause(now))

    fun tick(now: Instant): PlayTimer = copy(clock = clock.tick(now))

    /** Whether the open stretch is due to be saved, once [CHECKPOINT_INTERVAL] has passed. */
    fun checkpointDue(now: Instant): Boolean = lastSaved?.let { Duration.between(it, now) >= CHECKPOINT_INTERVAL } ?: true

    fun saved(now: Instant): PlayTimer = copy(lastSaved = now)

    /** Brings the open stretch up to [now] for an entry saved with it. An entry that [completes] the puzzle stops its time. */
    fun entry(
        now: Instant,
        completes: Boolean,
    ): PlayTimer = copy(clock = clock.tick(now), completedAt = completedAt ?: now.takeIf { completes }, lastSaved = now)

    companion object {
        /** How often an open stretch is saved, which is the most a crash can lose. */
        val CHECKPOINT_INTERVAL: Duration = Duration.ofSeconds(30)
    }
}

/** A puzzle's time as a clock reads: 4:05, or 1:02:03 past an hour. */
fun formattedTime(time: Duration): String {
    val seconds = time.seconds
    val (hours, minutes, rest) = Triple(seconds / 3600, seconds % 3600 / 60, seconds % 60)
    return if (hours > 0) {
        String.format(Locale.ROOT, "%d:%02d:%02d", hours, minutes, rest)
    } else {
        String.format(Locale.ROOT, "%d:%02d", minutes, rest)
    }
}
