package software.primandproper.ngrams.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
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
import software.primandproper.ngrams.core.GuessList
import software.primandproper.ngrams.core.Hint
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LetterMark
import software.primandproper.ngrams.core.LineStats
import software.primandproper.ngrams.core.ProgressKey
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.core.ShareText
import software.primandproper.ngrams.core.Status
import software.primandproper.ngrams.core.Submission
import software.primandproper.ngrams.core.WordGame

sealed interface PasswordState {
    data object Loading : PasswordState

    data object Failed : PasswordState

    data class Playing(
        val game: WordGame,
        val feedback: Feedback? = null,
        /** Set by the guess that ends the puzzle, so its stats open once. */
        val justFinished: Boolean = false,
    ) : PasswordState
}

/** One Password puzzle in play: the game, feedback for the last move, and saving each guess. */
class PasswordViewModel(
    private val container: AppContainer,
    language: Language,
    n: Int,
    private val day: PuzzleDay,
) : ViewModel() {
    private val key = ProgressKey(language, PuzzleKind.WORD, n, day)
    private val logger =
        container.logger
            .withName("Password")
            .withValue("day", day)
            .withValue("n", n)
            .withValue("lang", language.code)
    private val _state = MutableStateFlow<PasswordState>(PasswordState.Loading)
    val state: StateFlow<PasswordState> = _state
    private var list: GuessList? = null

    val stats: StateFlow<LineStats?> =
        container.stats(container.today()).map { it[key.line] }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        try {
            val puzzle = container.bank().wordPuzzles(day).first { it.language == key.language && it.n == key.n }
            list = container.guessList(key.language, key.n)
            // The setting applies only until the first guess is saved; after that the puzzle keeps
            // the mode it was saved with.
            val hardMode = container.settings.settings.first().hardMode(PuzzleKind.WORD, key.language)
            _state.value =
                try {
                    val saved = container.progress.find(key)
                    PasswordState.Playing(WordGame(puzzle, saved?.entries.orEmpty(), saved?.hardMode ?: hardMode))
                } catch (e: Exception) {
                    logger.error("loading Password progress", e)
                    PasswordState.Playing(WordGame(puzzle, hardMode = hardMode), Feedback(R.string.couldnt_load_progress))
                }
        } catch (e: Exception) {
            logger.error("loading the puzzle", e)
            _state.value = PasswordState.Failed
        }
    }

    private fun play(move: (WordGame) -> WordGame) {
        _state.update { if (it is PasswordState.Playing) it.copy(game = move(it.game)) else it }
    }

    fun type(letter: Char) = play { it.type(letter) }

    fun deleteLetter() = play { it.deleteLetter() }

    fun submit() {
        val playing = _state.value as? PasswordState.Playing ?: return
        val list = list ?: return
        val (game, submission) = playing.game.submit(list)
        _state.value = PasswordState.Playing(game, feedback(submission), justFinished = !playing.game.isOver && game.isOver)
        if (submission is Submission.Guessed) {
            viewModelScope.launch {
                try {
                    container.progress.append(submission.guess, key, game.hardMode, completes = game.isOver)
                } catch (e: Exception) {
                    logger.error("saving a guess", e)
                    _state.update {
                        if (it is PasswordState.Playing) it.copy(feedback = Feedback(R.string.couldnt_save_guess)) else it
                    }
                }
            }
        } else if (submission is Submission.Blocked) {
            logger.debug("guessed a blocked word")
        }
    }

    fun feedbackShown(shown: Feedback) {
        _state.update { if (it is PasswordState.Playing && it.feedback == shown) it.copy(feedback = null) else it }
    }

    fun finishShown() {
        _state.update { if (it is PasswordState.Playing) it.copy(justFinished = false) else it }
    }

    private fun feedback(submission: Submission): Feedback? =
        when (submission) {
            Submission.TooShort -> Feedback(R.string.not_enough_letters)
            is Submission.Blocked -> Feedback(R.string.how_dare_you)
            is Submission.NotAWord -> Feedback(R.string.not_on_list, listOf(submission.guess.uppercase()))
            is Submission.MissingHint ->
                when (val hint = submission.hint) {
                    // English spells the position as an ordinal and Spanish as a number, so both go along.
                    is Hint.Position ->
                        Feedback(
                            R.string.hint_position,
                            listOf(ordinal(hint.index + 1), hint.index + 1, hint.letter.uppercaseChar().toString()),
                        )
                    is Hint.Letter -> Feedback(R.string.hint_letter, listOf(hint.letter.uppercaseChar().toString()))
                }
            is Submission.Guessed, Submission.Over -> null
        }
}

/** English ordinals, correct through 20th, for the English hint; Spanish uses the number. */
private fun ordinal(n: Int): String =
    when (n) {
        1 -> "1st"
        2 -> "2nd"
        3 -> "3rd"
        else -> "${n}th"
    }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PasswordScreen(
    container: AppContainer,
    language: Language,
    n: Int,
    day: PuzzleDay,
    onBack: () -> Unit,
) {
    val model: PasswordViewModel = viewModel { PasswordViewModel(container, language, n, day) }
    val state by model.state.collectAsStateWithLifecycle()
    val stats by model.stats.collectAsStateWithLifecycle()
    val playing = state as? PasswordState.Playing
    var showingStats by rememberSaveable { mutableStateOf(false) }
    val interfaceLanguage = interfaceLanguage()

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
                title = { Text("${language.flag} ${PuzzleKind.WORD.displayName(interfaceLanguage)} · $n") },
                navigationIcon = {
                    BackButton(onBack)
                },
                actions = {
                    if (playing != null && playing.game.isOver) {
                        ShareAction(ShareText.word(playing.game, day, interfaceLanguage))
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            FeedbackHost(playing?.feedback, model::feedbackShown)
            when (val current = state) {
                PasswordState.Loading -> CircularProgressIndicator()
                PasswordState.Failed -> Text(stringResource(R.string.couldnt_load_puzzle))
                is PasswordState.Playing ->
                    Column(Modifier.fillMaxSize().padding(16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        GuessGrid(current.game)
                        Spacer(Modifier.weight(1f))
                        ResultLine(current.game)
                        Spacer(Modifier.height(16.dp))
                        Keyboard(
                            language = language,
                            marks = current.game.letterMarks,
                            enabled = !current.game.isOver,
                            onLetter = model::type,
                            onDelete = model::deleteLetter,
                            onEnter = model::submit,
                        )
                    }
            }
        }
    }

    if (showingStats && playing != null) {
        LineStatsSheet(
            line = PuzzleLine(language, PuzzleKind.WORD, n),
            stats = stats,
            highlight = (playing.game.status as? Status.Won)?.guesses,
            onDismiss = { showingStats = false },
        )
    }
}

/** The fill behind a marked letter and the ink on it. Absent letters get no fill; they fade instead. */
@Composable
private fun LetterMark.colors(): Pair<Color, Color>? =
    when (this) {
        LetterMark.CORRECT -> MaterialTheme.colorScheme.primary to MaterialTheme.colorScheme.onPrimary
        LetterMark.PRESENT -> MaterialTheme.colorScheme.outline to MaterialTheme.colorScheme.surface
        LetterMark.ABSENT -> null
    }

private val LetterMark.spoken: Int
    @StringRes get() =
        when (this) {
            LetterMark.CORRECT -> R.string.mark_correct
            LetterMark.PRESENT -> R.string.mark_present
            LetterMark.ABSENT -> R.string.mark_absent
        }

/** A letter and how it's marked, for a screen reader, or [empty] without a letter. */
@Composable
private fun spokenLetter(
    letter: Char?,
    mark: LetterMark?,
): String {
    val markText = mark?.let { ", " + stringResource(it.spoken) }.orEmpty()
    return letter?.let { it.uppercaseChar() + markText } ?: stringResource(R.string.empty_cell)
}

@Composable
private fun GuessGrid(game: WordGame) {
    val marks = game.marks
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (row in 0 until WordGame.MAX_GUESSES) {
            val text =
                when {
                    row < game.guesses.size -> game.guesses[row]
                    row == game.guesses.size -> game.current
                    else -> ""
                }
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                for (column in 0 until game.puzzle.n) {
                    LetterCell(text.getOrNull(column), marks.getOrNull(row)?.getOrNull(column))
                }
            }
        }
    }
}

@Composable
private fun LetterCell(
    letter: Char?,
    mark: LetterMark?,
) {
    val colors = mark?.colors()
    val description = spokenLetter(letter, mark)
    val shape = RoundedCornerShape(8.dp)
    val border =
        when {
            colors != null -> Color.Transparent
            mark == LetterMark.ABSENT || letter == null -> MaterialTheme.colorScheme.outlineVariant
            else -> MaterialTheme.colorScheme.outline
        }
    Box(
        Modifier
            .size(52.dp)
            .background(colors?.first ?: Color.Transparent, shape)
            .border(2.dp, border, shape)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            letter?.uppercaseChar()?.toString().orEmpty(),
            style = MaterialTheme.typography.headlineSmall,
            fontWeight = FontWeight.Bold,
            color =
                colors?.second
                    ?: if (mark == LetterMark.ABSENT) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
        )
    }
}

@Composable
private fun ResultLine(game: WordGame) {
    when (val status = game.status) {
        Status.Playing ->
            Text(
                (WordGame.MAX_GUESSES - game.guesses.size).let { pluralStringResource(R.plurals.guesses_left, it, it) },
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        is Status.Won ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = StarColor)
                Text(
                    pluralStringResource(R.plurals.solved_in, status.guesses, status.guesses),
                    style = MaterialTheme.typography.titleMedium,
                )
            }
        Status.Lost -> Text(stringResource(R.string.word_was, game.puzzle.shown.uppercase()), style = MaterialTheme.typography.titleMedium)
    }
}

@Composable
private fun Keyboard(
    language: Language,
    marks: Map<Char, LetterMark>,
    enabled: Boolean,
    onLetter: (Char) -> Unit,
    onDelete: () -> Unit,
    onEnter: () -> Unit,
) {
    val rows = listOf("qwertyuiop", if (language == Language.ES) "asdfghjklñ" else "asdfghjkl", "zxcvbnm")
    // The screenshot test waits for the keyboard by this tag, whatever the language.
    Column(Modifier.fillMaxWidth().testTag("keyboard"), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEachIndexed { index, row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (index == rows.lastIndex) {
                    ActionKey(stringResource(R.string.enter), "↵", enabled, onEnter)
                }
                for (letter in row) {
                    LetterKey(letter, marks[letter], enabled, Modifier.weight(1f)) { onLetter(letter) }
                }
                if (index == rows.lastIndex) {
                    ActionKey(stringResource(R.string.delete), "⌫", enabled, onDelete)
                }
            }
        }
    }
}

@Composable
private fun LetterKey(
    letter: Char,
    mark: LetterMark?,
    enabled: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val colors = mark?.colors()
    val description = spokenLetter(letter, mark)
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.height(52.dp).semantics { contentDescription = description },
        shape = RoundedCornerShape(6.dp),
        color = colors?.first ?: MaterialTheme.colorScheme.surfaceContainerHighest,
        contentColor =
            colors?.second
                ?: if (mark == LetterMark.ABSENT) MaterialTheme.colorScheme.outlineVariant else MaterialTheme.colorScheme.onSurface,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Text(letter.uppercaseChar().toString(), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun ActionKey(
    label: String,
    symbol: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    FilledTonalButton(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(6.dp),
        contentPadding = PaddingValues(horizontal = 12.dp),
        modifier = Modifier.height(52.dp).widthIn(min = 48.dp).semantics { contentDescription = label },
    ) {
        Text(symbol, style = MaterialTheme.typography.titleMedium)
    }
}
