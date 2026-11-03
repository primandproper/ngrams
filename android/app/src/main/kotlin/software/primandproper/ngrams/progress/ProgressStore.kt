package software.primandproper.ngrams.progress

import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import software.primandproper.ngrams.core.Assistance
import software.primandproper.ngrams.core.Logger
import software.primandproper.ngrams.core.PlayStretch
import software.primandproper.ngrams.core.PlayTime
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleTiming
import java.time.Instant

/** Reads and writes saved progress. */
class ProgressStore(
    private val database: NgramsDatabase,
    private val logger: Logger,
    private val now: () -> Long = System::currentTimeMillis,
) {
    /** The store's clock, to the millisecond it saves times at. */
    fun currentInstant(): Instant = Instant.ofEpochMilli(now())

    private val dao = database.progress()

    suspend fun find(key: ProgressKey): PuzzleProgress? = dao.find(key.language.code, key.kind.code, key.n, key.day.toString())

    fun onDay(day: PuzzleDay): Flow<List<PuzzleProgress>> = dao.onDay(day.toString())

    /** What a puzzle's time is worked out from, or null if nothing's been saved for it yet. */
    suspend fun timing(key: ProgressKey): PuzzleTiming? =
        find(key)?.let { PuzzleTiming(it.stretches, it.completedAt?.let(Instant::ofEpochMilli), it.timed) }

    /** The hints a puzzle has taken and whether it was solved for the player, or null if nothing's been saved for it yet. */
    suspend fun assistance(key: ProgressKey): Assistance? = find(key)?.let { Assistance(it.hints, it.gaveUp) }

    /** Everything saved, for stats and streaks. */
    fun all(): Flow<List<PuzzleProgress>> = dao.all()

    /** Replaces everything saved with [rows]. Only the debug build's screenshot seed calls it. */
    suspend fun replaceAll(rows: List<PuzzleProgress>) {
        database.withTransaction {
            dao.deleteAll()
            rows.forEach { dao.insert(it) }
        }
    }

    /**
     * Appends one entry, folding in [stretches]. Appending rather than replacing means a failed read
     * can never turn into a write that drops earlier entries. The first entry records [hardMode] and
     * starts the puzzle timed; later ones leave both, so a puzzle keeps the mode it started in. The
     * first entry that [completes] the puzzle records when.
     */
    suspend fun append(
        entry: String,
        key: ProgressKey,
        hardMode: Boolean = false,
        completes: Boolean = false,
        stretches: List<PlayStretch> = emptyList(),
        at: Instant = currentInstant(),
    ) {
        val now = at.toEpochMilli()
        database.withTransaction {
            val saved = find(key)
            if (saved == null) {
                dao.insert(
                    PuzzleProgress(
                        language = key.language.code,
                        kind = key.kind.code,
                        n = key.n,
                        day = key.day.toString(),
                        entries = listOf(entry),
                        hardMode = hardMode,
                        completedAt = if (completes) now else null,
                        updatedAt = now,
                        stretches = PlayTime.merged(emptyList(), stretches),
                        timed = true,
                    ),
                )
            } else {
                dao.update(
                    saved.copy(
                        entries = saved.entries + entry,
                        completedAt = saved.completedAt ?: if (completes) now else null,
                        updatedAt = now,
                        stretches = PlayTime.merged(saved.stretches, stretches),
                    ),
                )
            }
        }
        logger
            .withValue("day", key.day)
            .withValue("n", key.n)
            .debug("saved ${key.kind.code} progress")
    }

    /**
     * Folds [stretches] into a started puzzle's. A puzzle with nothing saved yet keeps its stretches
     * in memory until its first entry, so opening a puzzle never starts it.
     */
    suspend fun save(
        stretches: List<PlayStretch>,
        key: ProgressKey,
    ) {
        database.withTransaction {
            val saved = find(key) ?: return@withTransaction
            dao.update(saved.copy(stretches = PlayTime.merged(saved.stretches, stretches)))
        }
    }

    /**
     * Saves a hint, folding in [stretches]. A hint starts the puzzle the way a first entry does: with
     * nothing saved yet, it records [hardMode] and starts the puzzle timed.
     */
    suspend fun takeHint(
        hint: String,
        key: ProgressKey,
        hardMode: Boolean = false,
        stretches: List<PlayStretch> = emptyList(),
        at: Instant = currentInstant(),
    ) {
        database.withTransaction {
            val saved = findOrStart(key, hardMode, at)
            dao.update(
                saved.copy(
                    hints = saved.hints + hint,
                    stretches = PlayTime.merged(saved.stretches, stretches),
                    updatedAt = at.toEpochMilli(),
                ),
            )
        }
        logger
            .withValue("day", key.day)
            .withValue("n", key.n)
            .debug("saved a ${key.kind.code} hint")
    }

    /**
     * Saves that the player had the puzzle solved for them, appending the [entries] that finish it (a
     * board's remaining words; none for Password) and recording when, as a finishing entry would.
     */
    suspend fun giveUp(
        key: ProgressKey,
        entries: List<String> = emptyList(),
        hardMode: Boolean = false,
        stretches: List<PlayStretch> = emptyList(),
        at: Instant = currentInstant(),
    ) {
        val now = at.toEpochMilli()
        database.withTransaction {
            val saved = findOrStart(key, hardMode, at)
            dao.update(
                saved.copy(
                    entries = saved.entries + entries,
                    gaveUp = true,
                    stretches = PlayTime.merged(saved.stretches, stretches),
                    completedAt = saved.completedAt ?: now,
                    updatedAt = now,
                ),
            )
        }
        logger
            .withValue("day", key.day)
            .withValue("n", key.n)
            .info("solved ${key.kind.code} for the player")
    }

    /** The puzzle's saved progress, or new progress inserted for it, started the way a first entry starts it. Call inside a transaction. */
    private suspend fun findOrStart(
        key: ProgressKey,
        hardMode: Boolean,
        at: Instant,
    ): PuzzleProgress =
        find(key) ?: PuzzleProgress(
            language = key.language.code,
            kind = key.kind.code,
            n = key.n,
            day = key.day.toString(),
            entries = emptyList(),
            hardMode = hardMode,
            updatedAt = at.toEpochMilli(),
            timed = true,
        ).let { it.copy(id = dao.insert(it)) }
}
