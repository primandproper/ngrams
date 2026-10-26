package software.primandproper.ngrams.progress

import androidx.room.withTransaction
import kotlinx.coroutines.flow.Flow
import software.primandproper.ngrams.core.Logger
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay

/** Reads and writes saved progress. */
class ProgressStore(
    private val database: NgramsDatabase,
    private val logger: Logger,
    private val now: () -> Long = System::currentTimeMillis,
) {
    private val dao = database.progress()

    suspend fun find(key: ProgressKey): PuzzleProgress? = dao.find(key.language.code, key.kind.code, key.n, key.day.toString())

    fun onDay(day: PuzzleDay): Flow<List<PuzzleProgress>> = dao.onDay(day.toString())

    /** Everything saved, for stats and streaks. */
    fun all(): Flow<List<PuzzleProgress>> = dao.all()

    /**
     * Appends one entry. Appending rather than replacing means a failed read can never turn into a
     * write that drops earlier entries. The first entry records [hardMode]; later ones leave it, so
     * a puzzle keeps the mode it started in. The first entry that [completes] the puzzle records when.
     */
    suspend fun append(
        entry: String,
        key: ProgressKey,
        hardMode: Boolean = false,
        completes: Boolean = false,
    ) {
        val now = now()
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
                    ),
                )
            } else {
                dao.update(
                    saved.copy(
                        entries = saved.entries + entry,
                        completedAt = saved.completedAt ?: if (completes) now else null,
                        updatedAt = now,
                    ),
                )
            }
        }
        logger
            .withValue("day", key.day)
            .withValue("n", key.n)
            .debug("saved ${key.kind.code} progress")
    }
}
