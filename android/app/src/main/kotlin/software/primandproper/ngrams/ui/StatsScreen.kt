package software.primandproper.ngrams.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.R
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LineStats
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine

/** Every line's stats in the player's languages, or null while they load. */
class StatsViewModel(
    container: AppContainer,
) : ViewModel() {
    val lines: StateFlow<List<LineStats>?> =
        combine(container.stats(container.today()), container.settings.settings) { stats, settings ->
            stats.values.filter { settings.plays(it.line.language) }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
}

/** Every line's stats in the player's languages, grouped by game like home, each opening its full stats. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StatsScreen(
    container: AppContainer,
    onLine: (PuzzleLine) -> Unit,
    onBack: () -> Unit,
) {
    val model: StatsViewModel = viewModel { StatsViewModel(container) }
    val lines by model.lines.collectAsStateWithLifecycle()
    val interfaceLanguage = interfaceLanguage()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.stats)) },
                navigationIcon = {
                    BackButton(onBack)
                },
            )
        },
    ) { padding ->
        val current = lines
        if (current == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            return@Scaffold
        }
        val multilingual = current.map { it.line.language }.toSet().size > 1
        LazyColumn(Modifier.fillMaxSize().testTag("stats-list"), contentPadding = padding) {
            for (kind in PuzzleKind.entries) {
                val ofKind = current.filter { it.line.kind == kind }
                if (ofKind.isEmpty()) continue
                item(key = kind.code) {
                    Text(
                        kind.displayName(interfaceLanguage),
                        style = MaterialTheme.typography.titleMedium,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
                    )
                }
                for (language in Language.entries) {
                    val ofLanguage = ofKind.filter { it.line.language == language }.sortedBy { it.line.n }
                    if (ofLanguage.isEmpty()) continue
                    if (multilingual) {
                        item(key = "${kind.code}-${language.code}") {
                            Text(
                                "${language.flag} ${language.displayName}",
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 2.dp),
                            )
                        }
                    }
                    items(ofLanguage, key = { it.line.toString() }) { stats ->
                        ListItem(
                            modifier = Modifier.clickable { onLine(stats.line) },
                            headlineContent = { Text("n=${stats.line.n}") },
                            supportingContent = {
                                Text(statsSummary(stats))
                            },
                            trailingContent = { StreakBadge(stats.currentStreak) },
                        )
                    }
                }
            }
        }
    }
}

/** One line's full stats. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LineStatsScreen(
    container: AppContainer,
    line: PuzzleLine,
    onBack: () -> Unit,
) {
    val model: StatsViewModel = viewModel { StatsViewModel(container) }
    val lines by model.lines.collectAsStateWithLifecycle()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(line.title(interfaceLanguage())) },
                navigationIcon = {
                    BackButton(onBack)
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding)) {
            when (val stats = lines?.firstOrNull { it.line == line }) {
                null -> Text(stringResource(R.string.no_stats), modifier = Modifier.padding(16.dp))
                else -> LineStatsView(stats)
            }
        }
    }
}
