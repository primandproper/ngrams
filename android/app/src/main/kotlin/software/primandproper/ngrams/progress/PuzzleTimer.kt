package software.primandproper.ngrams.progress

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.updateAndGet
import kotlinx.coroutines.launch
import software.primandproper.ngrams.core.Logger
import software.primandproper.ngrams.core.PlayClock
import software.primandproper.ngrams.core.PlayStretch
import software.primandproper.ngrams.core.PlayTimer
import software.primandproper.ngrams.core.ProgressKey
import java.time.Instant

/**
 * Times one puzzle in play and saves its stretches in [saves], which outlives the screen. Until the
 * puzzle's first entry they stay in memory and are saved with it, so opening a puzzle and leaving
 * never starts it.
 */
class PuzzleTimer(
    private val key: ProgressKey,
    private val store: ProgressStore,
    private val saves: CoroutineScope,
    private val logger: Logger,
) {
    private val _state = MutableStateFlow(PlayTimer())
    val state: StateFlow<PlayTimer> = _state

    /** Picks up the puzzle's saved stretches. Runs before the puzzle is shown, so nothing is timed yet. */
    suspend fun load() {
        _state.value =
            try {
                store.timing(key)?.let { PlayTimer(PlayClock(it.stretches), it.completedAt, it.timed) }
                    ?: PlayTimer()
            } catch (e: Exception) {
                // Without the saved stretches, any time shown would be wrong, so none is.
                logger.error("loading play time", e)
                PlayTimer(timed = false)
            }
    }

    fun resume() = _state.update { it.resume(store.currentInstant()) }

    fun pause() {
        val now = store.currentInstant()
        _state.update { it.pause(now) }
        save(now)
    }

    /** Brings the open stretch up to now, saving it once the checkpoint interval has passed. */
    fun tick() {
        val now = store.currentInstant()
        val timer = _state.updateAndGet { it.tick(now) }
        if (timer.checkpointDue(now)) save(now)
    }

    /**
     * Brings the open stretch up to now for an entry about to be saved, and returns what to save with
     * it and when. An entry that [completes] the puzzle stops its time.
     */
    fun entry(completes: Boolean): Pair<List<PlayStretch>, Instant> {
        val now = store.currentInstant()
        return _state.updateAndGet { it.entry(now, completes) }.clock.stretches to now
    }

    private fun save(now: Instant) {
        val stretches = _state.updateAndGet { it.saved(now) }.clock.stretches
        saves.launch {
            try {
                store.save(stretches, key)
            } catch (e: Exception) {
                logger.error("saving play time", e)
            }
        }
    }
}
