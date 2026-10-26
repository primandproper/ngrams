package software.primandproper.ngrams.progress

import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.RoomDatabase
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import androidx.room.Update
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PlayRecord
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import java.time.Instant

/**
 * What a player has done on one puzzle, the same record the iOS app keeps. Entries are
 * kind-specific and only ever appended: guesses for Password.
 */
@Entity(
    tableName = "puzzle_progress",
    indices = [Index(value = ["language", "kind", "n", "day"], unique = true)],
)
data class PuzzleProgress(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val language: String,
    val kind: String,
    val n: Int,
    val day: String,
    val entries: List<String>,
    /** The mode the puzzle was started in, fixed by its first entry. */
    val hardMode: Boolean = false,
    /** Epoch milliseconds when a Password puzzle ended, which decides streaks. */
    val completedAt: Long? = null,
    val updatedAt: Long,
) {
    /**
     * The plain values stats read, or null if a field doesn't parse (saved by a build that knew a
     * language or game this one doesn't). Records finished before completedAt was saved count their
     * last play instead.
     */
    val record: PlayRecord?
        get() {
            val language = Language.fromCode(language) ?: return null
            val kind = PuzzleKind.fromCode(kind) ?: return null
            val day = PuzzleDay.parse(day) ?: return null
            return PlayRecord(ProgressKey(language, kind, n, day), entries, Instant.ofEpochMilli(completedAt ?: updatedAt))
        }
}

@Dao
interface ProgressDao {
    @Query("SELECT * FROM puzzle_progress WHERE language = :language AND kind = :kind AND n = :n AND day = :day LIMIT 1")
    suspend fun find(
        language: String,
        kind: String,
        n: Int,
        day: String,
    ): PuzzleProgress?

    /** Every kind, language, and size on one day, updating as progress is saved. */
    @Query("SELECT * FROM puzzle_progress WHERE day = :day")
    fun onDay(day: String): Flow<List<PuzzleProgress>>

    /** Everything saved, for stats and streaks, updating as progress is saved. */
    @Query("SELECT * FROM puzzle_progress")
    fun all(): Flow<List<PuzzleProgress>>

    @Insert
    suspend fun insert(progress: PuzzleProgress): Long

    @Update
    suspend fun update(progress: PuzzleProgress)
}

class Converters {
    private val strings = ListSerializer(String.serializer())

    @TypeConverter
    fun fromEntries(entries: List<String>): String = Json.encodeToString(strings, entries)

    @TypeConverter
    fun toEntries(json: String): List<String> = Json.decodeFromString(strings, json)
}

@Database(entities = [PuzzleProgress::class], version = 1)
@TypeConverters(Converters::class)
abstract class NgramsDatabase : RoomDatabase() {
    abstract fun progress(): ProgressDao
}
