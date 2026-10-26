package software.primandproper.ngrams.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Backspace
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Shuffle
import androidx.compose.material.icons.filled.SortByAlpha
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.core.FoundWordOrder
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LineStats
import software.primandproper.ngrams.core.PangramGame
import software.primandproper.ngrams.core.PangramSubmission
import software.primandproper.ngrams.core.PangramWord
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.core.SeededGenerator
import software.primandproper.ngrams.core.ShareText
import software.primandproper.ngrams.core.layoutSeed
import software.primandproper.ngrams.core.shuffle
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.hypot
import kotlin.math.sin

sealed interface PangramState {
    data object Loading : PangramState

    data object Failed : PangramState

    data class Playing(
        val game: PangramGame,
        /** Every letter but the center, in the order the wheel shows them. Shuffling changes only this. */
        val outer: List<Char>,
        val feedback: Feedback? = null,
        /** Set by the word that earns the star, so its stats open once. */
        val justFinished: Boolean = false,
    ) : PangramState
}

/** One pangram board in play: the game, the wheel's order, feedback for the last move, and saving each word found. */
class PangramViewModel(
    private val container: AppContainer,
    language: Language,
    n: Int,
    private val day: PuzzleDay,
) : ViewModel() {
    private val key = ProgressKey(language, PuzzleKind.PANGRAM, n, day)
    private val logger =
        container.logger
            .withName("Pangram")
            .withValue("day", day)
            .withValue("n", n)
            .withValue("lang", language.code)
    private val _state = MutableStateFlow<PangramState>(PangramState.Loading)
    val state: StateFlow<PangramState> = _state

    val stats: StateFlow<LineStats?> =
        container.stats(container.today()).map { it[key.line] }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val order: StateFlow<FoundWordOrder> =
        container.settings.settings
            .map { it.pangramFoundOrder }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), FoundWordOrder.ALPHABETICAL)

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        try {
            val puzzle = container.bank().pangramPuzzles(day).first { it.language == key.language && it.n == key.n }
            // The setting applies only until the first word is saved; after that the board keeps
            // the mode it was saved with.
            val hardMode = container.settings.settings.first().hardMode(PuzzleKind.PANGRAM, key.language)
            val (game, feedback) =
                try {
                    val saved = container.progress.find(key)
                    PangramGame(puzzle, saved?.entries.orEmpty(), saved?.hardMode ?: hardMode) to null
                } catch (e: Exception) {
                    logger.error("loading pangram progress", e)
                    PangramGame(puzzle, hardMode = hardMode) to Feedback("Couldn't load saved progress")
                }
            val outer = puzzle.letters.filter { it != puzzle.center }.toMutableList()
            outer.shuffle(SeededGenerator(layoutSeed(key.language, key.kind, key.n, day)))
            _state.value = PangramState.Playing(game, outer, feedback)
        } catch (e: Exception) {
            logger.error("loading the board", e)
            _state.value = PangramState.Failed
        }
    }

    private fun play(move: (PangramState.Playing) -> PangramState.Playing) {
        _state.update { if (it is PangramState.Playing) move(it) else it }
    }

    fun type(letter: Char) = play { it.copy(game = it.game.type(letter)) }

    fun deleteLetter() = play { it.copy(game = it.game.deleteLetter()) }

    fun shuffle() = play { it.copy(outer = it.outer.shuffled()) }

    fun toggleOrder() {
        viewModelScope.launch {
            container.settings.setPangramFoundOrder(
                if (order.value == FoundWordOrder.ALPHABETICAL) FoundWordOrder.RECENT else FoundWordOrder.ALPHABETICAL,
            )
        }
    }

    fun submit() {
        val playing = _state.value as? PangramState.Playing ?: return
        val (game, submission) = playing.game.submit()
        val puzzle = game.puzzle
        val feedback =
            when (submission) {
                is PangramSubmission.Found -> {
                    val word = submission.word
                    when {
                        puzzle.isBonusPangram(word.word) -> Feedback("Bonus pangram! ${word.shown} +${word.points}")
                        word.word in puzzle.pangrams -> Feedback("Pangram! ${word.shown} +${word.points}")
                        else -> Feedback("${word.shown} +${word.points}")
                    }
                }
                is PangramSubmission.AlreadyFound -> Feedback("Already found ${submission.word.shown}")
                PangramSubmission.TooShort -> Feedback("Too short")
                PangramSubmission.MissingCenter -> Feedback("Missing the center letter")
                is PangramSubmission.Blocked -> Feedback("How dare you")
                is PangramSubmission.NotAWord -> Feedback("${submission.text.uppercase()} isn't on the list")
                PangramSubmission.NeedsPangram -> Feedback("Start with a pangram")
                PangramSubmission.Empty -> null
            }
        val justFinished = !playing.game.earnedStar && game.earnedStar
        _state.value = playing.copy(game = game, feedback = feedback ?: playing.feedback, justFinished = justFinished)
        when (submission) {
            is PangramSubmission.Found -> save(submission.word, game)
            is PangramSubmission.Blocked -> logger.debug("spelled a blocked word")
            else -> {}
        }
    }

    private fun save(
        word: PangramWord,
        game: PangramGame,
    ) {
        viewModelScope.launch {
            try {
                container.progress.append(word.word, key, game.hardMode, completes = game.earnedStar)
            } catch (e: Exception) {
                logger.withValue("word", word.word).error("saving a found word", e)
                play { it.copy(feedback = Feedback("Couldn't save that word")) }
            }
        }
    }

    fun feedbackShown(shown: Feedback) = play { if (it.feedback == shown) it.copy(feedback = null) else it }

    fun finishShown() = play { it.copy(justFinished = false) }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PangramScreen(
    container: AppContainer,
    language: Language,
    n: Int,
    day: PuzzleDay,
    onBack: () -> Unit,
) {
    val model: PangramViewModel = viewModel { PangramViewModel(container, language, n, day) }
    val state by model.state.collectAsStateWithLifecycle()
    val stats by model.stats.collectAsStateWithLifecycle()
    val order by model.order.collectAsStateWithLifecycle()
    val playing = state as? PangramState.Playing
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
                title = { Text("${language.flag} ${PuzzleKind.PANGRAM.displayName} · $n") },
                navigationIcon = {
                    IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back") }
                },
                actions = {
                    if (playing != null && playing.game.found.isNotEmpty()) {
                        ShareAction(ShareText.pangram(playing.game, day))
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            FeedbackHost(playing?.feedback, model::feedbackShown)
            when (val current = state) {
                PangramState.Loading -> CircularProgressIndicator()
                PangramState.Failed -> Text("Couldn't load this board.")
                is PangramState.Playing -> Board(current, order, model)
            }
        }
    }

    if (showingStats) {
        LineStatsSheet(PuzzleLine(language, PuzzleKind.PANGRAM, n), stats) { showingStats = false }
    }
}

@Composable
private fun Board(
    playing: PangramState.Playing,
    order: FoundWordOrder,
    model: PangramViewModel,
) {
    val game = playing.game
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        ScoreHeader(
            score = game.score,
            target = game.puzzle.targetScore,
            progress = pangramCount(game),
            earnedStar = game.earnedStar,
            missing = "Find every pangram for the star",
        )
        CurrentWord(game)
        LetterWheel(game.puzzle.center, playing.outer, model::type)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = model::deleteLetter, enabled = game.current.isNotEmpty(), modifier = Modifier.weight(1f)) {
                Icon(Icons.AutoMirrored.Filled.Backspace, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text("Delete")
            }
            FilledTonalIconButton(onClick = model::shuffle) { Icon(Icons.Filled.Shuffle, contentDescription = "Shuffle") }
            Button(onClick = model::submit, enabled = game.current.isNotEmpty(), modifier = Modifier.weight(1f)) { Text("Enter") }
        }
        FoundWords(game, order, model::toggleOrder)
    }
}

/** The common pangrams the star needs, then any bonus ones apart, so a bonus find never looks like it went uncounted. */
private fun pangramCount(game: PangramGame): String {
    val total = game.puzzle.pangrams.size
    val count = if (total == 1) "${game.foundPangrams} of 1 pangram" else "${game.foundPangrams} of $total pangrams"
    return if (game.foundBonusPangrams == 0) count else "$count · ${game.foundBonusPangrams} bonus"
}

@Composable
private fun CurrentWord(game: PangramGame) {
    val primary = MaterialTheme.colorScheme.primary
    Text(
        buildAnnotatedString {
            if (game.current.isEmpty()) append(" ")
            for (letter in game.current) {
                if (letter == game.puzzle.center) {
                    withStyle(SpanStyle(color = primary)) { append(letter.uppercaseChar()) }
                } else {
                    append(letter.uppercaseChar())
                }
            }
        },
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.SemiBold,
        textAlign = TextAlign.Center,
        maxLines = 1,
        modifier = Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = "Current word ${game.current}" },
    )
}

private val centerRadius = 46.dp
private val ringWidth = 90.dp
private val wedgeGap = 6.dp
private val wheelRadius = centerRadius + wedgeGap + ringWidth

/**
 * The center letter in a circle, ringed by a wheel cut into a wedge per other letter, so every
 * board size gets the same shape. A tap anywhere in a wedge types its letter, and each letter is
 * also its own accessibility button.
 */
@Composable
private fun LetterWheel(
    center: Char,
    outer: List<Char>,
    onLetter: (Char) -> Unit,
) {
    val span = 360f / maxOf(outer.size, 1)
    val wedgeColor = MaterialTheme.colorScheme.surfaceContainerHighest
    val centerColor = MaterialTheme.colorScheme.primary

    Box(
        Modifier
            .size(wheelRadius * 2)
            .pointerInput(outer) {
                detectTapGestures { tap ->
                    val c = Offset(size.width / 2f, size.height / 2f)
                    val distance = hypot(tap.x - c.x, tap.y - c.y)
                    when {
                        distance <= centerRadius.toPx() -> onLetter(center)
                        distance <= wheelRadius.toPx() && outer.isNotEmpty() -> {
                            // Degrees clockwise from straight up, where the first wedge is centered.
                            val fromTop = (Math.toDegrees(atan2(tap.y - c.y, tap.x - c.x).toDouble()) + 90 + 360) % 360
                            onLetter(outer[floor((fromTop + span / 2) / span).toInt() % outer.size])
                        }
                    }
                }
            },
    ) {
        Canvas(Modifier.matchParentSize()) {
            val c = Offset(size.width / 2, size.height / 2)
            val inner = (centerRadius + wedgeGap).toPx()
            val outerRadius = wheelRadius.toPx()
            val gap = wedgeGap.toPx()

            fun inset(radius: Float) = Math.toDegrees(asin(gap / 2 / radius).toDouble()).toFloat()
            for (i in outer.indices) {
                val start = -90f + span * i - span / 2
                val path =
                    Path().apply {
                        arcTo(Rect(c, outerRadius), start + inset(outerRadius), span - 2 * inset(outerRadius), forceMoveTo = true)
                        arcTo(Rect(c, inner), start + span - inset(inner), -(span - 2 * inset(inner)), forceMoveTo = false)
                        close()
                    }
                drawPath(path, wedgeColor)
            }
            drawCircle(centerColor, centerRadius.toPx(), c)
        }
        LetterKey(center, Offset.Zero, MaterialTheme.colorScheme.onPrimary, "${center.uppercaseChar()}, center") { onLetter(center) }
        for ((i, letter) in outer.withIndex()) {
            val angle = Math.toRadians((-90.0 + span * i))
            val reach = (wheelRadius - ringWidth / 2).value
            LetterKey(
                letter,
                Offset((reach * cos(angle)).toFloat(), (reach * sin(angle)).toFloat()),
                MaterialTheme.colorScheme.onSurface,
                "${letter.uppercaseChar()}",
            ) { onLetter(letter) }
        }
    }
}

/** A letter drawn at [offset] dp from the wheel's center, labeled for accessibility. */
@Composable
private fun BoxScope.LetterKey(
    letter: Char,
    offset: Offset,
    color: Color,
    label: String,
    onClick: () -> Unit,
) {
    Text(
        "${letter.uppercaseChar()}",
        style = MaterialTheme.typography.headlineMedium,
        fontWeight = FontWeight.Bold,
        color = color,
        modifier =
            Modifier
                .align(Alignment.Center)
                .offset(Dp(offset.x), Dp(offset.y))
                .clearAndSetSemantics {
                    contentDescription = label
                    role = Role.Button
                    onClick {
                        onClick()
                        true
                    }
                },
    )
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FoundWords(
    game: PangramGame,
    order: FoundWordOrder,
    onToggleOrder: () -> Unit,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("${game.found.size} found", style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            IconButton(onClick = onToggleOrder) {
                Icon(
                    if (order == FoundWordOrder.ALPHABETICAL) Icons.Filled.SortByAlpha else Icons.Filled.Schedule,
                    contentDescription = if (order == FoundWordOrder.ALPHABETICAL) "Sorted A to Z" else "Sorted newest first",
                )
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // Common pangrams bold, bonus ones bold and italic.
            for (word in game.found(order)) {
                FoundWord(
                    word.shown,
                    word.points,
                    fontWeight = if (game.puzzle.isPangram(word.word)) FontWeight.Bold else FontWeight.Normal,
                    italic = game.puzzle.isBonusPangram(word.word),
                )
            }
        }
    }
}
