package software.primandproper.ngrams.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LineStats
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.core.SeededGenerator
import software.primandproper.ngrams.core.ShareText
import software.primandproper.ngrams.core.TilesGame
import software.primandproper.ngrams.core.TilesLayout
import software.primandproper.ngrams.core.TilesSubmission
import software.primandproper.ngrams.core.TilesWord
import software.primandproper.ngrams.core.layoutSeed
import kotlin.random.Random

sealed interface TilesState {
    data object Loading : TilesState

    data object Failed : TilesState

    data class Playing(
        val game: TilesGame,
        /** The order the board shows tiles in, unsolved tiles first. Shuffling changes only this. */
        val order: List<Int>,
        val feedback: Feedback? = null,
        /** Set by the word that earns the star, so its stats open once. */
        val justFinished: Boolean = false,
    ) : TilesState {
        /** Tiles on the board, `n` to a row: solved targets first in the order they were found, unless solved tiles leave the board, then the rest in board order. */
        val boardTiles: List<Int>
            get() {
                val solved = game.solvedTiles
                val solvedRows = if (game.solvedTilesLeave) emptyList() else game.solvedTargets.flatMap { game.puzzle.targets[it] }
                return solvedRows + order.filter { it !in solved }
            }
    }
}

/** One tiles board in play: the game, the board's tile order, feedback for the last move, and saving each word found. */
class TilesViewModel(
    private val container: AppContainer,
    language: Language,
    n: Int,
    private val day: PuzzleDay,
) : ViewModel() {
    private val key = ProgressKey(language, PuzzleKind.TILES, n, day)
    private val logger =
        container.logger
            .withName("Tiles")
            .withValue("day", day)
            .withValue("n", n)
            .withValue("lang", language.code)
    private val _state = MutableStateFlow<TilesState>(TilesState.Loading)
    val state: StateFlow<TilesState> = _state

    val stats: StateFlow<LineStats?> =
        container.stats(container.today()).map { it[key.line] }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        try {
            val puzzle = container.bank().tilesPuzzles(day).first { it.language == key.language && it.n == key.n }
            // Tiles reads its hard mode live, like the iOS app, rather than fixing it per board.
            val solvedTilesLeave = container.settings.settings.first().solvedTilesLeave
            val (game, feedback) =
                try {
                    TilesGame(puzzle, container.progress.find(key)?.entries.orEmpty(), solvedTilesLeave) to null
                } catch (e: Exception) {
                    logger.error("loading tiles progress", e)
                    TilesGame(puzzle, solvedTilesLeave = solvedTilesLeave) to Feedback("Couldn't load saved progress")
                }
            val first = withContext(Dispatchers.Default) { arranged(game, SeededGenerator(layoutSeed(key.language, key.kind, key.n, day))) }
            _state.value = TilesState.Playing(game, first, feedback)
        } catch (e: Exception) {
            logger.error("loading the board", e)
            _state.value = TilesState.Failed
        }
    }

    /**
     * Spreads the unsolved tiles, then appends the solved ones, which [TilesState.Playing.boardTiles]
     * places itself. Can take thousands of shuffles, so it runs off the main thread.
     */
    private fun arranged(
        game: TilesGame,
        rng: SeededGenerator,
    ): List<Int> {
        val solved = game.solvedTiles
        val unsolved = game.puzzle.tiles.indices.filter { it !in solved }
        return TilesLayout.spread(unsolved, game.puzzle, rng) + solved.sorted()
    }

    private fun play(move: (TilesState.Playing) -> TilesState.Playing) {
        _state.update { if (it is TilesState.Playing) move(it) else it }
    }

    fun tap(tile: Int) = play { it.copy(game = it.game.toggle(tile)) }

    fun clear() = play { it.copy(game = it.game.clearSelection()) }

    fun shuffle() {
        val playing = _state.value as? TilesState.Playing ?: return
        viewModelScope.launch {
            val order = withContext(Dispatchers.Default) { arranged(playing.game, SeededGenerator(Random.nextLong().toULong())) }
            play { it.copy(order = order) }
        }
    }

    fun submit() {
        val playing = _state.value as? TilesState.Playing ?: return
        val (game, submission) = playing.game.submit()
        val feedback =
            when (submission) {
                is TilesSubmission.Found -> Feedback("${submission.word.shown} +${submission.word.points}")
                is TilesSubmission.AlreadyFound -> Feedback("Already found ${submission.word.shown}")
                is TilesSubmission.Blocked -> Feedback("How dare you")
                is TilesSubmission.NotAWord -> Feedback("${submission.text} isn't on the list")
                TilesSubmission.Empty -> null
            }
        val justFinished = !playing.game.earnedStar && game.earnedStar
        _state.value = playing.copy(game = game, feedback = feedback ?: playing.feedback, justFinished = justFinished)
        when (submission) {
            is TilesSubmission.Found -> save(submission.word, game)
            is TilesSubmission.Blocked -> logger.debug("spelled a blocked word")
            else -> {}
        }
    }

    private fun save(
        word: TilesWord,
        game: TilesGame,
    ) {
        viewModelScope.launch {
            try {
                container.progress.append(word.word, key, completes = game.earnedStar)
            } catch (e: Exception) {
                logger.withValue("word", word.word).error("saving a found word", e)
                play { it.copy(feedback = Feedback("Couldn't save that word")) }
            }
        }
    }

    fun feedbackShown(shown: Feedback) = play { if (it.feedback == shown) it.copy(feedback = null) else it }

    fun finishShown() = play { it.copy(justFinished = false) }
}

/** The fill behind a solved target's tiles, the green the iOS app uses. */
private val SolvedColor = Color(0x3334C759)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TilesScreen(
    container: AppContainer,
    language: Language,
    n: Int,
    day: PuzzleDay,
    onBack: () -> Unit,
) {
    val model: TilesViewModel = viewModel { TilesViewModel(container, language, n, day) }
    val state by model.state.collectAsStateWithLifecycle()
    val stats by model.stats.collectAsStateWithLifecycle()
    val playing = state as? TilesState.Playing
    var showingStats by rememberSaveable { mutableStateOf(false) }

    LaunchedEffect(playing?.justFinished) {
        if (playing?.justFinished == true) {
            // Cleared only after the sheet opens: clearing it changes this effect's key, which
            // would cancel the wait.
            delay(1_000)
            showingStats = true
            model.finishShown()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${language.flag} ${PuzzleKind.TILES.displayName} · $n") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    if (playing != null && playing.game.found.isNotEmpty()) {
                        ShareAction(ShareText.tiles(playing.game, day))
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            FeedbackHost(playing?.feedback, model::feedbackShown)
            when (val current = state) {
                TilesState.Loading -> CircularProgressIndicator()
                TilesState.Failed -> Text("Couldn't load this board.")
                is TilesState.Playing -> Board(current, model)
            }
        }
    }

    if (showingStats && playing != null) {
        LineStatsSheet(PuzzleLine(language, PuzzleKind.TILES, n), stats) {
            showingStats = false
        }
    }
}

@Composable
private fun Board(
    playing: TilesState.Playing,
    model: TilesViewModel,
) {
    val game = playing.game
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ScoreHeader(
            score = game.score,
            target = game.puzzle.targetScore,
            progress = "${game.solvedTargets.size} of ${game.puzzle.targets.size} targets",
            earnedStar = game.earnedStar,
            missing = "Find every target for the star",
        )
        if (game.solvedTilesLeave) {
            SolvedTargets(game)
        }
        Text(
            game.selectedText.ifEmpty { " " },
            style = MaterialTheme.typography.headlineSmall,
            fontFamily = FontFamily.Monospace,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Current word ${game.selectedText}" },
            textAlign = TextAlign.Center,
        )
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            for (row in playing.boardTiles.chunked(game.puzzle.n)) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (tile in row) {
                        TileButton(
                            text = game.puzzle.tiles[tile],
                            position = game.selection.indexOf(tile).takeIf { it >= 0 },
                            solved = tile in game.solvedTiles,
                            modifier = Modifier.weight(1f),
                        ) { model.tap(tile) }
                    }
                    repeat(game.puzzle.n - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = model::shuffle) {
                Icon(Icons.Filled.Shuffle, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Shuffle")
            }
            Spacer(Modifier.weight(1f))
            OutlinedButton(onClick = model::clear, enabled = game.selection.isNotEmpty()) { Text("Clear") }
            Button(onClick = model::submit, enabled = game.selection.isNotEmpty()) { Text("Submit") }
        }
        FoundWords(game.found)
    }
}

@Composable
private fun TileButton(
    text: String,
    /** Where this tile sits in the current word, if it's selected. */
    position: Int?,
    solved: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    Surface(
        onClick = onClick,
        modifier = modifier.heightIn(min = 56.dp).semantics { selected = position != null },
        shape = RoundedCornerShape(10.dp),
        color =
            when {
                position != null -> MaterialTheme.colorScheme.primary
                solved -> SolvedColor
                else -> MaterialTheme.colorScheme.surfaceContainerHighest
            },
        contentColor = if (position != null) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurface,
    ) {
        Box(Modifier.heightIn(min = 56.dp), contentAlignment = Alignment.Center) {
            Text(
                text,
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
                maxLines = 1,
                overflow = TextOverflow.Clip,
            )
            if (position != null) {
                Text(
                    "${position + 1}",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.align(Alignment.TopEnd).padding(4.dp),
                )
            }
        }
    }
}

/** In hard mode, found targets leave the board and line up here, each with the word it spells. */
@Composable
private fun SolvedTargets(game: TilesGame) {
    if (game.solvedTargets.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (target in game.solvedTargets) {
            val folded = game.puzzle.targets[target].joinToString("") { game.puzzle.tiles[it] }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                for (tile in game.puzzle.targets[target]) {
                    Surface(color = SolvedColor, shape = RoundedCornerShape(6.dp)) {
                        Text(
                            game.puzzle.tiles[tile],
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.padding(horizontal = 8.dp, vertical = 4.dp),
                        )
                    }
                }
                Spacer(Modifier.weight(1f))
                Text(game.found.firstOrNull { it.word == folded }?.shown ?: folded, fontWeight = FontWeight.SemiBold)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FoundWords(words: List<TilesWord>) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("${words.size} found", style = MaterialTheme.typography.titleMedium)
        FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            for (word in words.reversed()) {
                FoundWord(word.shown, word.points)
            }
        }
    }
}

/** A found word and its points, the points small and faint. */
@Composable
fun FoundWord(
    shown: String,
    points: Int,
    fontWeight: FontWeight = FontWeight.Normal,
    italic: Boolean = false,
) {
    Row(verticalAlignment = Alignment.Top) {
        Text(
            shown,
            fontWeight = fontWeight,
            fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal,
        )
        Text(
            "$points",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = 3.dp),
        )
    }
}
