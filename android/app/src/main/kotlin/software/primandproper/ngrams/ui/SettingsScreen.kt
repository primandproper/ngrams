package software.primandproper.ngrams.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.R
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.settings.Settings

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    container: AppContainer,
    onAcknowledgements: () -> Unit,
    onBack: () -> Unit,
) {
    val settings by container.settings.settings.collectAsStateWithLifecycle(Settings())
    val scope = rememberCoroutineScope()
    val store = container.settings
    val languages = settings.languages ?: Language.entries.toSet()
    val played = Language.entries.filter { it in languages }
    val interfaceLanguage = interfaceLanguage()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.settings)) },
                navigationIcon = {
                    BackButton(onBack)
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).testTag("settings")) {
            Header(stringResource(R.string.languages))
            for (language in Language.entries) {
                val on = language in languages
                SwitchRow(
                    title = "${language.flag} ${language.displayName}",
                    checked = on,
                    // The last language left on can't be switched off.
                    enabled = !(on && languages.size == 1),
                ) { checked -> scope.launch { store.setLanguages(if (checked) languages + language else languages - language) } }
            }
            HorizontalDivider()
            // One language keeps a section per game; more get a section per language, so each can
            // be harder or easier than the others.
            val only = played.singleOrNull()
            if (only != null) {
                for (kind in PuzzleKind.entries) {
                    Header(kind.displayName(interfaceLanguage))
                    SwitchRow(stringResource(R.string.hard_mode), settings.hardMode(kind, only)) {
                        scope.launch { store.setHardMode(kind, only, it) }
                    }
                    Footer(stringResource(hardModeRules.getValue(kind)))
                }
            } else {
                for (language in played) {
                    Header("${language.flag} ${language.displayName}")
                    for (kind in PuzzleKind.entries) {
                        SwitchRow(
                            stringResource(R.string.game_hard_mode, kind.displayName(interfaceLanguage)),
                            settings.hardMode(kind, language),
                            supporting = stringResource(hardModeRules.getValue(kind)),
                        ) { scope.launch { store.setHardMode(kind, language, it) } }
                    }
                }
            }
            HorizontalDivider()
            ListItem(
                modifier = Modifier.clickable(onClick = onAcknowledgements),
                headlineContent = { Text(stringResource(R.string.acknowledgements)) },
                trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null) },
            )
        }
    }
}

/** What each game's hard mode changes. */
private val hardModeRules =
    mapOf(
        PuzzleKind.WORD to R.string.word_hard_mode_rule,
        PuzzleKind.TILES to R.string.tiles_hard_mode_rule,
        PuzzleKind.PANGRAM to R.string.pangram_hard_mode_rule,
    )

@Composable
private fun Header(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
    )
}

@Composable
private fun Footer(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
}

@Composable
private fun SwitchRow(
    title: String,
    checked: Boolean,
    enabled: Boolean = true,
    supporting: String? = null,
    onChange: (Boolean) -> Unit,
) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = supporting?.let { { Text(it) } },
        trailingContent = { Switch(checked = checked, onCheckedChange = onChange, enabled = enabled) },
    )
}

/** A credit: what it's for and its license are resources, the rest is the same in every language. */
private data class Credit(
    val name: String,
    @StringRes val use: Int,
    val license: License,
    val url: String,
)

/** A license by its own name, or one that reads differently per language. */
private sealed interface License {
    data class Named(
        val name: String,
    ) : License

    data class Described(
        @StringRes val description: Int,
    ) : License
}

private val wordLists =
    listOf(
        Credit(
            "ENABLE",
            R.string.credit_enable,
            License.Described(R.string.license_public_domain),
            "https://github.com/dolph/dictionary",
        ),
        Credit("RLA-ES", R.string.credit_rla_es, License.Named("MPL 1.1"), "https://github.com/sbosio/rla-es"),
        Credit(
            "FrequencyWords",
            R.string.credit_frequency_words,
            License.Named("CC BY-SA 4.0"),
            "https://github.com/hermitdave/FrequencyWords",
        ),
    )

private val source =
    Credit("n-grams", R.string.credit_source, License.Described(R.string.license_source), "https://github.com/primandproper/ngrams")

/** Credits for the word lists every puzzle is built from, as their licenses ask, and for the app's own source. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AcknowledgementsScreen(onBack: () -> Unit) {
    val uris = LocalUriHandler.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.acknowledgements)) },
                navigationIcon = {
                    BackButton(onBack)
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            Header(stringResource(R.string.word_lists))
            for (credit in wordLists) {
                CreditRow(credit) { uris.openUri(credit.url) }
            }
            Header(stringResource(R.string.source))
            CreditRow(source) { uris.openUri(source.url) }
        }
    }
}

@Composable
private fun CreditRow(
    credit: Credit,
    onOpen: () -> Unit,
) {
    ListItem(
        modifier = Modifier.clickable(onClick = onOpen),
        headlineContent = { Text(credit.name) },
        supportingContent = {
            val license =
                when (val license = credit.license) {
                    is License.Named -> license.name
                    is License.Described -> stringResource(license.description)
                }
            Text("${stringResource(credit.use)} $license.")
        },
    )
}
