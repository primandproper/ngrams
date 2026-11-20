package software.primandproper.ngrams.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
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
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
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
import software.primandproper.ngrams.R
import software.primandproper.ngrams.core.FoundWordOrder
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PangramGame
import software.primandproper.ngrams.core.PangramSubmission
import software.primandproper.ngrams.core.PangramWord
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.SeededGenerator
import software.primandproper.ngrams.core.ShareText
import software.primandproper.ngrams.core.layoutSeed
import software.primandproper.ngrams.core.shuffle
import software.primandproper.ngrams.progress.PuzzleTimer
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
        /** Whether the board is being solved for the player, a word at a time. */
        val solving: Boolean = false,
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
    val timer = PuzzleTimer(key, container.progress, container.saves, logger)
    private val _state = MutableStateFlow<PangramState>(PangramState.Loading)
    val state: StateFlow<PangramState> = _state

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
            timer.load()
            // The setting applies only until the first word is saved; after that the board keeps
            // the mode it was saved with.
            val hardMode = container.settings.settings.first().hardMode(PuzzleKind.PANGRAM, key.language)
            val (game, feedback) =
                try {
                    val saved = container.progress.find(key)
                    PangramGame(
                        puzzle,
                        saved?.entries.orEmpty(),
                        saved?.hardMode ?: hardMode,
                        saved?.hints.orEmpty(),
                        saved?.gaveUp ?: false,
                    ) to null
                } catch (e: Exception) {
                    logger.error("loading pangram progress", e)
                    PangramGame(puzzle, hardMode = hardMode) to Feedback(R.string.couldnt_load_progress)
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

    /** A move the player makes, which waits out solving. */
    private fun move(move: (PangramState.Playing) -> PangramState.Playing) = play { if (it.solving) it else move(it) }

    fun type(letter: Char) = move { it.copy(game = it.game.type(letter)) }

    fun deleteLetter() = move { it.copy(game = it.game.deleteLetter()) }

    fun shuffle() = move { it.copy(outer = it.outer.shuffled()) }

    /** Clues the next unfound word, if there is one. */
    fun takeHint() {
        val playing = _state.value as? PangramState.Playing ?: return
        val word = playing.game.nextHint
        if (playing.solving || word == null) {
            return
        }
        val game = playing.game.takeHint(word)
        _state.value = playing.copy(game = game)
        val (stretches, at) = timer.entry(completes = false)
        viewModelScope.launch {
            try {
                container.progress.takeHint(word, key, game.hardMode, stretches, at)
            } catch (e: Exception) {
                logger.withValue("word", word).error("saving a hint", e)
                play { it.copy(feedback = Feedback(R.string.couldnt_save_progress)) }
            }
        }
    }

    /** Solves the board for the player, giving up its star: spells each word of the solution a letter at a time. */
    fun solve() {
        val playing = _state.value as? PangramState.Playing ?: return
        if (playing.solving || playing.game.earnedStar || playing.game.gaveUp) {
            return
        }
        val words = playing.game.solution
        _state.value = playing.copy(game = playing.game.clearLetters(), solving = true)
        viewModelScope.launch {
            for (word in words) {
                for (letter in word) {
                    play { it.copy(game = it.game.type(letter)) }
                    delay(SOLVE_PACE_MS)
                }
                play { it.copy(game = it.game.giveUp(listOf(word))) }
                delay(SOLVE_PACE_MS * 6)
            }
            play { it.copy(solving = false) }
            val (stretches, at) = timer.entry(completes = true)
            try {
                container.progress.giveUp(key, words, playing.game.hardMode, stretches, at)
            } catch (e: Exception) {
                logger.error("saving a solve", e)
                play { it.copy(feedback = Feedback(R.string.couldnt_save_progress)) }
            }
        }
    }

    fun toggleOrder() {
        viewModelScope.launch {
            container.settings.setPangramFoundOrder(
                if (order.value == FoundWordOrder.ALPHABETICAL) FoundWordOrder.RECENT else FoundWordOrder.ALPHABETICAL,
            )
        }
    }

    fun submit() {
        val playing = _state.value as? PangramState.Playing ?: return
        if (playing.solving) {
            return
        }
        val (game, submission) = playing.game.submit()
        val puzzle = game.puzzle
        val feedback =
            when (submission) {
                is PangramSubmission.Found -> {
                    val word = submission.word
                    when {
                        puzzle.isBonusPangram(word.word) -> Feedback(R.string.bonus_pangram_found, listOf(word.shown, word.points))
                        word.word in puzzle.pangrams -> Feedback(R.string.pangram_found, listOf(word.shown, word.points))
                        else -> Feedback(R.string.word_points, listOf(word.shown, word.points))
                    }
                }
                is PangramSubmission.AlreadyFound -> Feedback(R.string.already_found, listOf(submission.word.shown), rejected = true)
                PangramSubmission.TooShort -> Feedback(R.string.too_short, rejected = true)
                PangramSubmission.MissingCenter -> Feedback(R.string.missing_center, rejected = true)
                is PangramSubmission.Blocked -> Feedback(R.string.how_dare_you, rejected = true)
                is PangramSubmission.NotAWord -> Feedback(R.string.not_on_list, listOf(submission.text.uppercase()), rejected = true)
                PangramSubmission.NeedsPangram -> Feedback(R.string.needs_pangram, rejected = true)
                PangramSubmission.Empty -> null
            }
        _state.value = playing.copy(game = game, feedback = feedback ?: playing.feedback)
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
        val (stretches, at) = timer.entry(completes = game.earnedStar)
        viewModelScope.launch {
            try {
                container.progress.append(word.word, key, game.hardMode, completes = game.earnedStar, stretches = stretches, at = at)
            } catch (e: Exception) {
                logger.withValue("word", word.word).error("saving a found word", e)
                play { it.copy(feedback = Feedback(R.string.couldnt_save_word)) }
            }
        }
    }

    fun feedbackShown(shown: Feedback) = play { if (it.feedback == shown) it.copy(feedback = null) else it }
}

/** The wait between letters as a board is solved for the player. */
private const val SOLVE_PACE_MS = 80L

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
    val showTimer = showsTimer(container)
    val timing by model.timer.state.collectAsStateWithLifecycle()
    val state by model.state.collectAsStateWithLifecycle()
    val order by model.order.collectAsStateWithLifecycle()
    val playing = state as? PangramState.Playing
    val interfaceLanguage = interfaceLanguage()

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    TimedTitle(
                        "${language.flag} ${PuzzleKind.PANGRAM.displayName(interfaceLanguage)} · $n",
                        model.timer,
                        showTimer,
                    )
                },
                navigationIcon = {
                    BackButton(onBack)
                },
                actions = {
                    if (playing != null && playing.game.found.isNotEmpty()) {
                        ShareAction(ShareText.pangram(playing.game, day, interfaceLanguage))
                    }
                    if (playing != null && (!(playing.game.earnedStar || playing.game.gaveUp) || playing.solving)) {
                        HelpAction(
                            used = playing.game.hints.size,
                            canHint = playing.game.nextHint != null,
                            enabled = !playing.solving,
                            solveWarning = stringResource(R.string.solve_board_warning),
                            onHint = model::takeHint,
                            onSolve = model::solve,
                        )
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            FeedbackHost(playing?.feedback, model::feedbackShown)
            when (val current = state) {
                PangramState.Loading -> CircularProgressIndicator()
                PangramState.Failed -> Text(stringResource(R.string.couldnt_load_board))
                is PangramState.Playing -> {
                    RunTimer(model.timer)
                    Board(current, order, model)
                }
            }
        }
    }
}

@Composable
private fun Board(
    playing: PangramState.Playing,
    order: FoundWordOrder,
    model: PangramViewModel,
) {
    val game = playing.game
    val haptics = rememberHaptics()
    // Words rejected since the board opened, each of which shakes the current word.
    var rejections by remember { mutableIntStateOf(0) }
    // Full turns the ring has spun through, one per shuffle.
    var spins by remember { mutableIntStateOf(0) }
    OnChange(playing.feedback) { _, feedback ->
        if (feedback?.rejected == true) {
            rejections++
            haptics(Haptic.ERROR)
        }
    }
    OnChange(game.found.size) { old, new -> if (new > old && !playing.solving) haptics(Haptic.SUCCESS) }
    OnChange(game.current) { old, new -> if (new.length > old.length && !playing.solving) haptics(Haptic.PICK) }
    OnChange(game.hints.size) { old, new -> if (new > old) haptics(Haptic.HINT) }
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
            missing = stringResource(R.string.pangram_star_missing).takeIf { game.score >= game.puzzle.targetScore },
        )
        CurrentWord(game, Modifier.shake(rejections))
        Clues(game.clues)
        LetterWheel(game.puzzle.center, playing.outer, spins, model::type)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = model::deleteLetter, enabled = game.current.isNotEmpty(), modifier = Modifier.weight(1f)) {
                Icon(Icons.AutoMirrored.Filled.Backspace, contentDescription = null)
                Spacer(Modifier.width(6.dp))
                Text(stringResource(R.string.delete))
            }
            FilledTonalIconButton(onClick = {
                if (!playing.solving) {
                    spins++
                    model.shuffle()
                }
            }) {
                Icon(Icons.Filled.Shuffle, contentDescription = stringResource(R.string.shuffle))
            }
            Button(onClick = model::submit, enabled = game.current.isNotEmpty(), modifier = Modifier.weight(1f)) {
                Text(stringResource(R.string.enter))
            }
        }
        FoundWords(game, order, model::toggleOrder)
    }
}

/** The common pangrams the star needs, then any bonus ones apart, so a bonus find never looks like it went uncounted. */
@Composable
private fun pangramCount(game: PangramGame): String {
    val total = game.puzzle.pangrams.size
    val count = pluralStringResource(R.plurals.pangrams_progress, total, game.foundPangrams, total)
    return if (game.foundBonusPangrams == 0) count else stringResource(R.string.pangram_bonus_count, count, game.foundBonusPangrams)
}

/** A chip per clued word still unfound: its first two letters and its length. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Clues(words: List<PangramWord>) {
    if (words.isEmpty()) return
    FlowRow(
        horizontalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterHorizontally),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        for (word in words) {
            Text(
                stringResource(R.string.clue, word.shown.take(2).uppercase(), word.shown.length),
                style = MaterialTheme.typography.labelMedium,
                fontWeight = FontWeight.SemiBold,
                modifier =
                    Modifier
                        .background(StarColor.copy(alpha = 0.2f), RoundedCornerShape(50))
                        .padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
    }
}

@Composable
private fun CurrentWord(
    game: PangramGame,
    modifier: Modifier,
) {
    val currentWord = stringResource(R.string.current_word, game.current)
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
        modifier = modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = currentWord },
    )
}

private val centerRadius = 46.dp
private val ringWidth = 90.dp
private val wedgeGap = 6.dp
private val wheelRadius = centerRadius + wedgeGap + ringWidth

/** A spring that settles in about seven tenths of a second with a little overshoot, for the ring's spin. */
private val ringSpring = spring<Float>(dampingRatio = 0.8f, stiffness = 80f)

/**
 * The center letter in a circle, ringed by a wheel cut into a wedge per other letter, so every
 * board size gets the same shape. A tap anywhere in a wedge types its letter, and each letter is
 * also its own accessibility button. A pressed wedge dips toward the center and darkens, and
 * shuffling spins the ring [spins] full turns while the letters swing to their new places.
 */
@Composable
private fun LetterWheel(
    center: Char,
    outer: List<Char>,
    spins: Int,
    onLetter: (Char) -> Unit,
) {
    val span = 360f / maxOf(outer.size, 1)
    val wedgeColor = MaterialTheme.colorScheme.surfaceContainerHighest
    val centerColor = MaterialTheme.colorScheme.primary
    val centerLabel = stringResource(R.string.center_letter, center.uppercaseChar().toString())
    val still = reduceMotion()
    var pressed by remember { mutableStateOf<Char?>(null) }
    val spin by animateFloatAsState(spins * 360f, ringSpring, label = "spin")
    // How far each letter's wedge is pressed in, from 0 to 1.
    val press =
        (outer + center).associateWith { letter ->
            key(letter) {
                animateFloatAsState(
                    if (pressed == letter) 1f else 0f,
                    spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMedium),
                    label = "press",
                ).value
            }
        }
    // Each letter's place on the ring, in degrees clockwise from the top, which swings when the letters swap.
    val angles =
        outer.withIndex().associate { (i, letter) ->
            letter to key(letter) { animateFloatAsState(span * i, ringSpring, label = "letter").value }
        }

    fun dip(letter: Char) = if (still) 1f else 1f - 0.1f * press.getValue(letter)

    fun shade(
        color: Color,
        letter: Char,
    ) = lerp(color, Color.Black, 0.08f * press.getValue(letter))

    // The screenshot test waits for the wheel by this tag, whatever the language.
    Box(
        Modifier
            .size(wheelRadius * 2)
            .testTag("wheel")
            .pointerInput(outer) {
                fun letterAt(tap: Offset): Char? {
                    val c = Offset(size.width / 2f, size.height / 2f)
                    val distance = hypot(tap.x - c.x, tap.y - c.y)
                    return when {
                        distance <= centerRadius.toPx() -> center
                        distance <= wheelRadius.toPx() && outer.isNotEmpty() -> {
                            // Degrees clockwise from straight up, where the first wedge is centered.
                            val fromTop = (Math.toDegrees(atan2(tap.y - c.y, tap.x - c.x).toDouble()) + 90 + 360) % 360
                            outer[floor((fromTop + span / 2) / span).toInt() % outer.size]
                        }
                        else -> null
                    }
                }
                detectTapGestures(
                    onPress = { tap ->
                        pressed = letterAt(tap)
                        tryAwaitRelease()
                        pressed = null
                    },
                    onTap = { tap -> letterAt(tap)?.let(onLetter) },
                )
            },
    ) {
        Canvas(Modifier.matchParentSize()) {
            val c = Offset(size.width / 2, size.height / 2)
            val inner = (centerRadius + wedgeGap).toPx()
            val outerRadius = wheelRadius.toPx()
            val gap = wedgeGap.toPx()

            fun inset(radius: Float) = Math.toDegrees(asin(gap / 2 / radius).toDouble()).toFloat()
            for ((i, letter) in outer.withIndex()) {
                val start = -90f + span * i - span / 2 + spin
                val path =
                    Path().apply {
                        arcTo(Rect(c, outerRadius), start + inset(outerRadius), span - 2 * inset(outerRadius), forceMoveTo = true)
                        arcTo(Rect(c, inner), start + span - inset(inner), -(span - 2 * inset(inner)), forceMoveTo = false)
                        close()
                    }
                scale(dip(letter), pivot = c) { drawPath(path, shade(wedgeColor, letter)) }
            }
            drawCircle(shade(centerColor, center), centerRadius.toPx() * dip(center), c)
        }
        LetterKey(center, Offset.Zero, dip(center), MaterialTheme.colorScheme.onPrimary, centerLabel) { onLetter(center) }
        for (letter in outer) {
            val angle = Math.toRadians(-90.0 + angles.getValue(letter) + spin)
            val reach = (wheelRadius - ringWidth / 2).value * dip(letter)
            LetterKey(
                letter,
                Offset((reach * cos(angle)).toFloat(), (reach * sin(angle)).toFloat()),
                dip(letter),
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
    scale: Float,
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
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }.clearAndSetSemantics {
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
            Text(
                pluralStringResource(R.plurals.found_count, game.found.size, game.found.size),
                style = MaterialTheme.typography.titleMedium,
                modifier = Modifier.weight(1f),
            )
            IconButton(onClick = onToggleOrder) {
                Icon(
                    if (order == FoundWordOrder.ALPHABETICAL) Icons.Filled.SortByAlpha else Icons.Filled.Schedule,
                    contentDescription =
                        stringResource(if (order == FoundWordOrder.ALPHABETICAL) R.string.sorted_alphabetical else R.string.sorted_newest),
                )
            }
        }
        // Words found once the board is open pop in with a small bounce; the ones it opened with are just there.
        val opened = remember { game.found.map { it.word }.toSet() }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // Common pangrams bold, bonus ones bold and italic.
            for (word in game.found(order)) {
                key(word.word) {
                    val pop = remember { Animatable(if (word.word in opened) 1f else 0.2f) }
                    LaunchedEffect(Unit) { pop.animateTo(1f, spring(dampingRatio = 0.5f, stiffness = Spring.StiffnessMediumLow)) }
                    FoundWord(
                        word.shown,
                        word.points,
                        fontWeight = if (game.puzzle.isPangram(word.word)) FontWeight.Bold else FontWeight.Normal,
                        italic = game.puzzle.isBonusPangram(word.word),
                        modifier =
                            Modifier.graphicsLayer {
                                scaleX = pop.value
                                scaleY = pop.value
                                alpha = ((pop.value - 0.2f) / 0.8f).coerceIn(0f, 1f)
                            },
                    )
                }
            }
        }
    }
}
