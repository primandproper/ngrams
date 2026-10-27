package software.primandproper.ngrams.settings

import android.content.Context
import androidx.annotation.StringRes
import androidx.datastore.core.DataMigration
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import software.primandproper.ngrams.R
import software.primandproper.ngrams.core.FoundWordOrder
import software.primandproper.ngrams.core.HardModes
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.Logger
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.languageCodes
import software.primandproper.ngrams.core.languagesFrom
import java.io.IOException

/** How home sections the day's open puzzles. By N puts every game's puzzles of one size together. */
enum class HomeGrouping(
    val code: String,
    @StringRes val label: Int,
) {
    GAME("game", R.string.grouping_game),
    N("n", R.string.grouping_n),
}

/** App-wide settings. */
data class Settings(
    /** The languages the player wants puzzles in, or null until they first choose. */
    val languages: Set<Language>? = null,
    val grouping: HomeGrouping = HomeGrouping.GAME,
    /** The languages each game's hard mode is on for. */
    val hardModes: Map<PuzzleKind, Set<Language>> = emptyMap(),
    val pangramFoundOrder: FoundWordOrder = FoundWordOrder.ALPHABETICAL,
) {
    /** Whether puzzles in [language] are shown: every language until the player chooses. */
    fun plays(language: Language): Boolean = languages?.contains(language) ?: true

    fun hardMode(
        kind: PuzzleKind,
        language: Language,
    ): Boolean = language in hardModes[kind].orEmpty()
}

private fun hardModeKey(kind: PuzzleKind) = stringPreferencesKey(HardModes.key(kind))

private fun legacyHardModeKey(kind: PuzzleKind) = booleanPreferencesKey(HardModes.legacyKey(kind))

/** Moves each game's hard mode from the single switch it used to be to the languages it's on for. */
private object HardModeMigration : DataMigration<Preferences> {
    override suspend fun shouldMigrate(currentData: Preferences): Boolean = PuzzleKind.entries.any { legacyHardModeKey(it) in currentData }

    override suspend fun migrate(currentData: Preferences): Preferences {
        val legacy = PuzzleKind.entries.mapNotNull { kind -> currentData[legacyHardModeKey(kind)]?.let { kind to it } }.toMap()
        val current = PuzzleKind.entries.mapNotNull { kind -> currentData[hardModeKey(kind)]?.let { kind to languagesFrom(it) } }.toMap()
        return currentData
            .toMutablePreferences()
            .apply {
                for ((kind, languages) in HardModes.migrated(legacy, current)) {
                    this[hardModeKey(kind)] = languageCodes(languages)
                }
                for (kind in legacy.keys) {
                    remove(legacyHardModeKey(kind))
                }
            }.toPreferences()
    }

    override suspend fun cleanUp() = Unit
}

private val Context.dataStore by preferencesDataStore("settings", produceMigrations = { listOf(HardModeMigration) })

/** Reads and writes [Settings], under the same key names the iOS app uses. */
class SettingsStore(
    context: Context,
    private val logger: Logger,
) {
    private val store = context.dataStore

    private object Keys {
        val languages = stringPreferencesKey("languages")
        val grouping = stringPreferencesKey("homeGrouping")
        val pangramFoundOrder = stringPreferencesKey("pangramFoundOrder")
    }

    val settings: Flow<Settings> =
        store.data
            .catch { e ->
                // A settings file that can't be read falls back to defaults rather than crashing.
                if (e is IOException) {
                    logger.error("reading settings", e)
                    emit(emptyPreferences())
                } else {
                    throw e
                }
            }.map { it.settings() }

    private fun Preferences.settings() =
        Settings(
            languages =
                this[Keys.languages]?.let(::languagesFrom),
            grouping = HomeGrouping.entries.firstOrNull { it.code == this[Keys.grouping] } ?: HomeGrouping.GAME,
            hardModes = PuzzleKind.entries.associateWith { kind -> this[hardModeKey(kind)]?.let(::languagesFrom).orEmpty() },
            pangramFoundOrder =
                FoundWordOrder.entries.firstOrNull { it.code == this[Keys.pangramFoundOrder] } ?: FoundWordOrder.ALPHABETICAL,
        )

    suspend fun setLanguages(languages: Set<Language>) = edit { it[Keys.languages] = languageCodes(languages) }

    suspend fun setGrouping(grouping: HomeGrouping) = edit { it[Keys.grouping] = grouping.code }

    /** Turns [kind]'s hard mode on or off for [language], leaving the other languages as they are. */
    suspend fun setHardMode(
        kind: PuzzleKind,
        language: Language,
        on: Boolean,
    ) = edit {
        val languages = it[hardModeKey(kind)]?.let(::languagesFrom).orEmpty()
        it[hardModeKey(kind)] = languageCodes(if (on) languages + language else languages - language)
    }

    suspend fun setPangramFoundOrder(order: FoundWordOrder) = edit { it[Keys.pangramFoundOrder] = order.code }

    private suspend fun edit(change: (MutablePreferences) -> Unit) {
        try {
            store.edit(change)
        } catch (e: IOException) {
            logger.error("saving settings", e)
        }
    }
}
