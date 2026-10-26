package software.primandproper.ngrams.settings

import android.content.Context
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.map
import software.primandproper.ngrams.core.FoundWordOrder
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.Logger
import java.io.IOException

/** How home sections the day's open puzzles. By N puts every game's puzzles of one size together. */
enum class HomeGrouping(
    val code: String,
    val displayName: String,
) {
    GAME("game", "Game"),
    N("n", "n"),
}

/** App-wide settings. */
data class Settings(
    /** The languages the player wants puzzles in, or null until they first choose. */
    val languages: Set<Language>? = null,
    val grouping: HomeGrouping = HomeGrouping.GAME,
    val wordHardMode: Boolean = false,
    val solvedTilesLeave: Boolean = false,
    val pangramHardMode: Boolean = false,
    val pangramFoundOrder: FoundWordOrder = FoundWordOrder.ALPHABETICAL,
) {
    /** Whether puzzles in [language] are shown: every language until the player chooses. */
    fun plays(language: Language): Boolean = languages?.contains(language) ?: true
}

private val Context.dataStore by preferencesDataStore("settings")

/** Reads and writes [Settings], under the same key names the iOS app uses. */
class SettingsStore(
    context: Context,
    private val logger: Logger,
) {
    private val store = context.dataStore

    private object Keys {
        val languages = stringPreferencesKey("languages")
        val grouping = stringPreferencesKey("homeGrouping")
        val wordHardMode = booleanPreferencesKey("wordHardMode")
        val solvedTilesLeave = booleanPreferencesKey("solvedTilesLeave")
        val pangramHardMode = booleanPreferencesKey("pangramHardMode")
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
                this[Keys.languages]?.let { codes ->
                    codes.split(",").mapNotNull(Language::fromCode).toSet()
                },
            grouping = HomeGrouping.entries.firstOrNull { it.code == this[Keys.grouping] } ?: HomeGrouping.GAME,
            wordHardMode = this[Keys.wordHardMode] ?: false,
            solvedTilesLeave = this[Keys.solvedTilesLeave] ?: false,
            pangramHardMode = this[Keys.pangramHardMode] ?: false,
            pangramFoundOrder =
                FoundWordOrder.entries.firstOrNull { it.code == this[Keys.pangramFoundOrder] } ?: FoundWordOrder.ALPHABETICAL,
        )

    suspend fun setLanguages(languages: Set<Language>) =
        edit { it[Keys.languages] = Language.entries.filter(languages::contains).joinToString(",") { language -> language.code } }

    suspend fun setGrouping(grouping: HomeGrouping) = edit { it[Keys.grouping] = grouping.code }

    suspend fun setWordHardMode(on: Boolean) = edit { it[Keys.wordHardMode] = on }

    suspend fun setSolvedTilesLeave(on: Boolean) = edit { it[Keys.solvedTilesLeave] = on }

    suspend fun setPangramHardMode(on: Boolean) = edit { it[Keys.pangramHardMode] = on }

    suspend fun setPangramFoundOrder(order: FoundWordOrder) = edit { it[Keys.pangramFoundOrder] = order.code }

    private suspend fun edit(change: (androidx.datastore.preferences.core.MutablePreferences) -> Unit) {
        try {
            store.edit(change)
        } catch (e: IOException) {
            logger.error("saving settings", e)
        }
    }
}
