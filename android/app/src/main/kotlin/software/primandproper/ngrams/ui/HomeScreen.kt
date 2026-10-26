package software.primandproper.ngrams.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.Status
import software.primandproper.ngrams.core.WordGame
import software.primandproper.ngrams.core.WordPuzzle

sealed interface HomeState {
    data object Loading : HomeState

    data class Loaded(
        val day: PuzzleDay,
        val games: List<WordGame>,
    ) : HomeState

    data class Failed(
        val message: String,
    ) : HomeState
}

@OptIn(ExperimentalCoroutinesApi::class)
class HomeViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val logger = container.logger.withName("Home")
    private val today = MutableStateFlow(PuzzleDay.today())

    val state: StateFlow<HomeState> =
        today
            .flatMapLatest { day ->
                val bank =
                    flow {
                        emit(
                            try {
                                container.bank()
                            } catch (e: Exception) {
                                logger.error("loading the puzzle bank", e)
                                null
                            },
                        )
                    }
                combine(bank, container.progress.onDay(day)) { bank, saved ->
                    if (bank == null) {
                        HomeState.Failed("The puzzles didn't load.")
                    } else {
                        val byKey = saved.associateBy { Triple(it.language, it.kind, it.n) }
                        HomeState.Loaded(
                            day,
                            bank.wordPuzzles(day).map { puzzle ->
                                val record = byKey[Triple(puzzle.language.code, PuzzleKind.WORD.code, puzzle.n)]
                                WordGame(puzzle, record?.entries.orEmpty(), record?.hardMode ?: false)
                            },
                        )
                    }
                }
            }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeState.Loading)

    /** Moves to the new day if midnight passed while the app was away. */
    fun refreshDay() {
        today.value = PuzzleDay.today()
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    container: AppContainer,
    onOpen: (WordPuzzle, PuzzleDay) -> Unit,
) {
    val model: HomeViewModel = viewModel { HomeViewModel(container) }
    val state by model.state.collectAsStateWithLifecycle()
    LifecycleResumeEffect(Unit) {
        model.refreshDay()
        onPauseOrDispose {}
    }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(title = { Text("n-grams") }, scrollBehavior = scroll)
        },
    ) { padding ->
        when (val current = state) {
            HomeState.Loading ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator()
                }
            is HomeState.Failed ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                    Text(current.message)
                }
            is HomeState.Loaded ->
                LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                    item { SectionHeader(PuzzleKind.WORD.displayName) }
                    for (language in Language.entries) {
                        val games = current.games.filter { it.puzzle.language == language }
                        if (games.isNotEmpty()) {
                            item { LanguageHeader(language) }
                            items(games, key = { "${it.puzzle.language.code}-${it.puzzle.n}" }) { game ->
                                PasswordRow(game, Modifier.clickable { onOpen(game.puzzle, current.day) })
                            }
                        }
                    }
                }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}

@Composable
private fun LanguageHeader(language: Language) {
    Text(
        "${language.flag} ${language.displayName}",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp),
    )
}

@Composable
private fun PasswordRow(
    game: WordGame,
    modifier: Modifier = Modifier,
) {
    ListItem(
        modifier = modifier,
        headlineContent = { Text("n=${game.puzzle.n}") },
        supportingContent = { Text("${game.puzzle.n} letters") },
        trailingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                when (val status = game.status) {
                    is Status.Won -> {
                        Icon(Icons.Filled.Star, contentDescription = "Solved", tint = MaterialTheme.colorScheme.tertiary)
                        Text("${status.guesses}/${WordGame.MAX_GUESSES}")
                    }
                    Status.Lost -> Text("X/${WordGame.MAX_GUESSES}")
                    Status.Playing ->
                        if (game.guesses.isNotEmpty()) {
                            Text("${game.guesses.size}/${WordGame.MAX_GUESSES}")
                        }
                }
            }
        },
    )
}
