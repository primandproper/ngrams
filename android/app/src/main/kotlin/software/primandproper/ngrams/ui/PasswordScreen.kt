package software.primandproper.ngrams.ui

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
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.core.GuessList
import software.primandproper.ngrams.core.Hint
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LetterMark
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.Status
import software.primandproper.ngrams.core.Submission
import software.primandproper.ngrams.core.WordGame
import software.primandproper.ngrams.progress.ProgressKey

/** Something to tell the player about their last move. [id] tells two identical messages apart. */
data class Feedback(
    val message: String,
    val id: Long = System.nanoTime(),
)

sealed interface PasswordState {
    data object Loading : PasswordState

    data object Failed : PasswordState

    data class Playing(
        val game: WordGame,
        val feedback: Feedback? = null,
    ) : PasswordState
}

/** One Password puzzle in play: the game, feedback for the last move, and saving each guess. */
class PasswordViewModel(
    private val container: AppContainer,
    private val language: Language,
    private val n: Int,
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

    init {
        viewModelScope.launch { load() }
    }

    private suspend fun load() {
        try {
            val puzzle = container.bank().wordPuzzles(day).first { it.language == language && it.n == n }
            list = container.guessList(language, n)
            _state.value =
                try {
                    val saved = container.progress.find(key)
                    PasswordState.Playing(WordGame(puzzle, saved?.entries.orEmpty(), saved?.hardMode ?: false))
                } catch (e: Exception) {
                    logger.error("loading Password progress", e)
                    PasswordState.Playing(WordGame(puzzle), Feedback("Couldn't load saved progress"))
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
        _state.value = PasswordState.Playing(game, feedback(submission))
        if (submission is Submission.Guessed) {
            viewModelScope.launch {
                try {
                    container.progress.append(submission.guess, key, game.hardMode, completes = game.isOver)
                } catch (e: Exception) {
                    logger.error("saving a guess", e)
                    _state.update {
                        if (it is PasswordState.Playing) it.copy(feedback = Feedback("Couldn't save that guess")) else it
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

    private fun feedback(submission: Submission): Feedback? =
        when (submission) {
            Submission.TooShort -> Feedback("Not enough letters")
            is Submission.Blocked -> Feedback("How dare you")
            is Submission.NotAWord -> Feedback("${submission.guess.uppercase()} isn't on the list")
            is Submission.MissingHint ->
                when (val hint = submission.hint) {
                    is Hint.Position -> Feedback("${ordinal(hint.index + 1)} letter must be ${hint.letter.uppercaseChar()}")
                    is Hint.Letter -> Feedback("Guess must contain ${hint.letter.uppercaseChar()}")
                }
            is Submission.Guessed, Submission.Over -> null
        }
}

/** English ordinals, correct through 20th. */
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
    val snackbars = remember { SnackbarHostState() }

    val feedback = (state as? PasswordState.Playing)?.feedback
    LaunchedEffect(feedback) {
        if (feedback != null) {
            snackbars.currentSnackbarData?.dismiss()
            snackbars.showSnackbar(feedback.message)
            model.feedbackShown(feedback)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("${language.flag} ${PuzzleKind.WORD.displayName} · $n") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
            // Messages show at the top rather than in Scaffold's bottom slot, which would cover the
            // keyboard's Enter and Delete while they're up.
            SnackbarHost(snackbars, Modifier.align(Alignment.TopCenter).zIndex(1f))
            when (val current = state) {
                PasswordState.Loading -> CircularProgressIndicator()
                PasswordState.Failed -> Text("Couldn't load this puzzle.")
                is PasswordState.Playing ->
                    Column(
                        Modifier.fillMaxSize().padding(16.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
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
}

/** The fill behind a marked letter and the ink on it. Absent letters get no fill; they fade instead. */
@Composable
private fun LetterMark.colors(): Pair<Color, Color>? =
    when (this) {
        LetterMark.CORRECT -> MaterialTheme.colorScheme.primary to MaterialTheme.colorScheme.onPrimary
        LetterMark.PRESENT -> MaterialTheme.colorScheme.outline to MaterialTheme.colorScheme.surface
        LetterMark.ABSENT -> null
    }

private val LetterMark.spoken: String
    get() =
        when (this) {
            LetterMark.CORRECT -> "correct"
            LetterMark.PRESENT -> "in the word"
            LetterMark.ABSENT -> "not in the word"
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
            .semantics {
                contentDescription =
                    letter?.let { l -> l.uppercaseChar() + (mark?.let { ", ${it.spoken}" } ?: "") } ?: "empty"
            },
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
                "${WordGame.MAX_GUESSES - game.guesses.size} guesses left",
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        is Status.Won ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = MaterialTheme.colorScheme.tertiary)
                Text(
                    if (status.guesses == 1) "Solved in 1 guess" else "Solved in ${status.guesses} guesses",
                    style = MaterialTheme.typography.titleMedium,
                )
            }
        Status.Lost -> Text("The word was ${game.puzzle.shown.uppercase()}", style = MaterialTheme.typography.titleMedium)
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
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        rows.forEachIndexed { index, row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                if (index == rows.lastIndex) {
                    ActionKey("Enter", "↵", enabled, onEnter)
                }
                for (letter in row) {
                    LetterKey(letter, marks[letter], enabled, Modifier.weight(1f)) { onLetter(letter) }
                }
                if (index == rows.lastIndex) {
                    ActionKey("Delete", "⌫", enabled, onDelete)
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
    Surface(
        onClick = onClick,
        enabled = enabled,
        modifier =
            modifier.height(
                52.dp,
            ).semantics { contentDescription = letter.uppercaseChar() + (mark?.let { ", ${it.spoken}" } ?: "") },
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
