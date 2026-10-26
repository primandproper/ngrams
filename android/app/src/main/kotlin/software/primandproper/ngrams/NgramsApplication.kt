package software.primandproper.ngrams

import android.app.Application
import android.content.Context
import androidx.room.Room
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import software.primandproper.ngrams.core.GuessList
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.Level
import software.primandproper.ngrams.core.LineStats
import software.primandproper.ngrams.core.Logger
import software.primandproper.ngrams.core.PuzzleBank
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.core.StatsBook
import software.primandproper.ngrams.progress.NgramsDatabase
import software.primandproper.ngrams.progress.ProgressStore
import software.primandproper.ngrams.settings.SettingsStore
import kotlin.time.measureTimedValue

class NgramsApplication : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}

/** What the screens share: the bank, the guess lists, saved progress, settings, and the logger. */
class AppContainer(
    context: Context,
) {
    val logger: Logger = LogcatLogger("ngrams", if (BuildConfig.DEBUG) Level.DEBUG else Level.INFO)

    private val assets = context.assets
    private val database =
        Room.databaseBuilder(context, NgramsDatabase::class.java, "ngrams.db").build()

    val progress = ProgressStore(database, logger.withName("ProgressStore"))
    val settings = SettingsStore(context, logger.withName("Settings"))

    /** A day debug builds can pin as today, so screenshots don't depend on when they're taken. */
    var pinnedToday: PuzzleDay? = null

    fun today(): PuzzleDay = pinnedToday ?: PuzzleDay.today()

    /** Every line's stats as of [today], from everything saved, updating as progress is saved. */
    fun stats(today: PuzzleDay): Flow<Map<PuzzleLine, LineStats>> =
        combine(flow { emit(bank()) }, progress.all()) { bank, saved ->
            StatsBook.compute(saved.mapNotNull { it.record }, bank, today)
        }

    private val bankLock = Mutex()
    private var bank: PuzzleBank? = null

    /** The bundled bank, decoded once off the main thread. */
    suspend fun bank(): PuzzleBank =
        bankLock.withLock {
            bank ?: withContext(Dispatchers.IO) {
                val (decoded, took) = measureTimedValue { assets.open("puzzles.json").use(PuzzleBank::decode) }
                logger
                    .withName("Bank")
                    .withValue("days", decoded.days.size)
                    .withValue("took", took)
                    .info("loaded puzzle bank")
                decoded
            }.also { bank = it }
        }

    /** The bundled guess list for [language] and [n]. */
    suspend fun guessList(
        language: Language,
        n: Int,
    ): GuessList =
        withContext(Dispatchers.IO) {
            val name = GuessList.name(language, n)

            fun read(file: String) = assets.open("guesses/$file.txt").bufferedReader().use { it.readText() }
            GuessList.parse(read(name), read("$name-blocked"))
        }
}
