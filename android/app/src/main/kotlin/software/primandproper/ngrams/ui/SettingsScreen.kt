package software.primandproper.ngrams.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch
import software.primandproper.ngrams.AppContainer
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

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                    ) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            Header("Languages")
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
                    Header(kind.displayName)
                    SwitchRow("Hard mode", settings.hardMode(kind, only)) { scope.launch { store.setHardMode(kind, only, it) } }
                    Footer(hardModeRules.getValue(kind))
                }
            } else {
                for (language in played) {
                    Header("${language.flag} ${language.displayName}")
                    for (kind in PuzzleKind.entries) {
                        SwitchRow(
                            "${kind.displayName} hard mode",
                            settings.hardMode(kind, language),
                            supporting = hardModeRules.getValue(kind),
                        ) { scope.launch { store.setHardMode(kind, language, it) } }
                    }
                }
            }
            HorizontalDivider()
            ListItem(
                modifier = Modifier.clickable(onClick = onAcknowledgements),
                headlineContent = { Text("Acknowledgements") },
                trailingContent = { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null) },
            )
        }
    }
}

/** What each game's hard mode changes. */
private val hardModeRules =
    mapOf(
        PuzzleKind.WORD to
            "Every guess uses the hints so far: green letters stay put and yellow letters appear somewhere. " +
            "A puzzle keeps the mode it had at its first guess.",
        PuzzleKind.TILES to
            "Found targets leave the board, so their tiles can't spell other words. Finding the last target ends the board.",
        PuzzleKind.PANGRAM to "The first word on a board has to be a pangram. A board keeps the mode it had at its first word.",
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

private data class Credit(
    val name: String,
    val use: String,
    val license: String,
    val url: String,
)

private val wordLists =
    listOf(
        Credit("ENABLE", "The English dictionary.", "Public domain", "https://github.com/dolph/dictionary"),
        Credit(
            "RLA-ES",
            "The Mexican Spanish dictionary, from Recursos Lingüísticos Abiertos del Español.",
            "MPL 1.1",
            "https://github.com/sbosio/rla-es",
        ),
        Credit(
            "FrequencyWords",
            "Word frequencies from OpenSubtitles 2018, by Hermit Dave, which decide the common words.",
            "CC BY-SA 4.0",
            "https://github.com/hermitdave/FrequencyWords",
        ),
    )

private val source =
    Credit("n-grams", "This app's source and puzzle bank.", "MIT, puzzles CC BY-SA 4.0", "https://github.com/primandproper/ngrams")

/** Credits for the word lists every puzzle is built from, as their licenses ask, and for the app's own source. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AcknowledgementsScreen(onBack: () -> Unit) {
    val uris = LocalUriHandler.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Acknowledgements") },
                navigationIcon = {
                    IconButton(
                        onClick = onBack,
                    ) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            Header("Word lists")
            for (credit in wordLists) {
                CreditRow(credit) { uris.openUri(credit.url) }
            }
            Header("Source")
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
        supportingContent = { Text("${credit.use} ${credit.license}.") },
    )
}
