package software.primandproper.ngrams.ui

import android.os.LocaleList
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.ViewList
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomAppBar
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LargeTopAppBar
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import software.primandproper.ngrams.AppContainer
import software.primandproper.ngrams.BuildConfig
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PangramGame
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.core.ShareText
import software.primandproper.ngrams.core.StatsBook
import software.primandproper.ngrams.core.Status
import software.primandproper.ngrams.core.TilesGame
import software.primandproper.ngrams.core.WordGame
import software.primandproper.ngrams.core.name
import software.primandproper.ngrams.core.suggestedLanguages
import software.primandproper.ngrams.settings.HomeGrouping
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset

/** One puzzle on home, in its saved state. */
sealed interface HomeEntry {
    val kind: PuzzleKind
    val language: Language
    val n: Int

    /** A Password puzzle is done once it's over, won or lost; a board once it has its star. */
    val isCompleted: Boolean

    val id: String get() = "${kind.code}-${language.code}-$n"
    val line: PuzzleLine get() = PuzzleLine(language, kind, n)

    data class Word(
        val game: WordGame,
    ) : HomeEntry {
        override val kind = PuzzleKind.WORD
        override val language get() = game.puzzle.language
        override val n get() = game.puzzle.n
        override val isCompleted get() = game.isOver
    }

    data class Tiles(
        val game: TilesGame,
    ) : HomeEntry {
        override val kind = PuzzleKind.TILES
        override val language get() = game.puzzle.language
        override val n get() = game.puzzle.n
        override val isCompleted get() = game.earnedStar
    }

    data class Pangram(
        val game: PangramGame,
    ) : HomeEntry {
        override val kind = PuzzleKind.PANGRAM
        override val language get() = game.puzzle.language
        override val n get() = game.puzzle.n
        override val isCompleted get() = game.earnedStar
    }
}

sealed interface HomeState {
    data object Loading : HomeState

    data object Failed : HomeState

    data class Loaded(
        val today: PuzzleDay,
        val day: PuzzleDay,
        /** The days a player can open: today and every day before it, or every day in debug builds. */
        val days: List<PuzzleDay>,
        val entries: List<HomeEntry>,
        /** Each line's current streak, as of today rather than the day shown. */
        val streaks: Map<PuzzleLine, Int>,
        val grouping: HomeGrouping,
        val shareText: String?,
        /** Set until the player picks languages, with the device's languages as a first guess. */
        val languagePrompt: Set<Language>?,
    ) : HomeState {
        val multilingual: Boolean get() = entries.map { it.language }.toSet().size > 1
    }
}

class HomeViewModel(
    private val container: AppContainer,
) : ViewModel() {
    private val logger = container.logger.withName("Home")
    private val today = MutableStateFlow(container.today())

    /** An earlier day the player went back to, or null for today. */
    private val picked = MutableStateFlow<PuzzleDay?>(null)

    private val bank =
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

    val state: StateFlow<HomeState> =
        combine(bank, container.settings.settings, today, picked, container.progress.all()) { bank, settings, today, picked, saved ->
            bank ?: return@combine HomeState.Failed
            val day = picked ?: today
            val onDay = saved.filter { it.day == day.toString() }.associateBy { Triple(it.language, it.kind, it.n) }

            fun saved(
                kind: PuzzleKind,
                language: Language,
                n: Int,
            ) = onDay[Triple(language.code, kind.code, n)]

            val entries =
                bank.wordPuzzles(day).filter { settings.plays(it.language) }.map {
                    val record = saved(PuzzleKind.WORD, it.language, it.n)
                    HomeEntry.Word(WordGame(it, record?.entries.orEmpty(), record?.hardMode ?: false))
                } +
                    bank.tilesPuzzles(day).filter { settings.plays(it.language) }.map {
                        val record = saved(PuzzleKind.TILES, it.language, it.n)
                        HomeEntry.Tiles(TilesGame(it, record?.entries.orEmpty(), settings.solvedTilesLeave))
                    } +
                    bank.pangramPuzzles(day).filter { settings.plays(it.language) }.map {
                        val record = saved(PuzzleKind.PANGRAM, it.language, it.n)
                        HomeEntry.Pangram(PangramGame(it, record?.entries.orEmpty(), record?.hardMode ?: false))
                    }
            val sorted =
                entries.sortedWith(
                    when (settings.grouping) {
                        HomeGrouping.GAME -> compareBy({ it.kind.ordinal }, { it.language.ordinal }, { it.n })
                        HomeGrouping.N -> compareBy({ it.n }, { it.kind.ordinal }, { it.language.ordinal })
                    },
                )

            HomeState.Loaded(
                today = today,
                day = day,
                days = if (BuildConfig.DEBUG) bank.days else bank.days.filter { it <= today },
                entries = sorted,
                streaks = StatsBook.compute(saved.mapNotNull { it.record }, bank, today).mapValues { it.value.currentStreak },
                grouping = settings.grouping,
                shareText =
                    ShareText.day(
                        entries.filterIsInstance<HomeEntry.Word>().map { it.game },
                        entries.filterIsInstance<HomeEntry.Tiles>().map { it.game },
                        entries.filterIsInstance<HomeEntry.Pangram>().map { it.game },
                        day,
                    ),
                languagePrompt =
                    if (settings.languages.isNullOrEmpty()) {
                        suggestedLanguages(LocaleList.getDefault().toLanguageTags().split(","))
                    } else {
                        null
                    },
            )
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), HomeState.Loading)

    /** Moves to the new day if midnight passed while the app was away. */
    fun refreshDay() {
        today.value = container.today()
    }

    /** Shows [day], keeping today as null so the list follows the date when midnight passes. */
    fun pick(day: PuzzleDay?) {
        picked.value = day?.takeIf { it != today.value }
    }

    fun group(grouping: HomeGrouping) {
        viewModelScope.launch { container.settings.setGrouping(grouping) }
    }

    fun chooseLanguages(languages: Set<Language>) {
        viewModelScope.launch { container.settings.setLanguages(languages) }
    }
}

/** What a row's headline says beyond its section header. */
private data class RowLabeling(
    /** The grouping whose section the row sits in, or null in Completed. */
    val section: HomeGrouping?,
    /** Whether the headline leads with the language's flag: only when more than one language is on, and not under a language's own group. */
    val showsFlag: Boolean,
) {
    fun title(entry: HomeEntry): String {
        val title =
            when (section) {
                HomeGrouping.GAME -> "n=${entry.n}"
                HomeGrouping.N -> entry.kind.displayName
                null -> "${entry.kind.displayName} · n=${entry.n}"
            }
        return if (showsFlag) "${entry.language.flag} $title" else title
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    container: AppContainer,
    onOpen: (HomeEntry, PuzzleDay) -> Unit,
    onStats: () -> Unit,
    onSettings: () -> Unit,
) {
    val model: HomeViewModel = viewModel { HomeViewModel(container) }
    val state by model.state.collectAsStateWithLifecycle()
    LifecycleResumeEffect(Unit) {
        model.refreshDay()
        onPauseOrDispose {}
    }
    val scroll = TopAppBarDefaults.exitUntilCollapsedScrollBehavior()
    val loaded = state as? HomeState.Loaded

    Scaffold(
        modifier = Modifier.nestedScroll(scroll.nestedScrollConnection),
        topBar = {
            LargeTopAppBar(
                title = {
                    Column {
                        Text("n-grams")
                        if (loaded != null) {
                            Text(
                                if (loaded.day == loaded.today) "Today" else loaded.day.name(includingYear = true),
                                style = MaterialTheme.typography.labelLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onStats) { Icon(Icons.Filled.BarChart, contentDescription = "Stats") }
                },
                actions = {
                    if (loaded != null) {
                        GroupingMenu(loaded.grouping, model::group)
                    }
                    IconButton(onClick = onSettings) { Icon(Icons.Filled.Settings, contentDescription = "Settings") }
                    loaded?.shareText?.let { ShareAction(it) }
                },
                scrollBehavior = scroll,
            )
        },
        bottomBar = {
            if (loaded != null) {
                BottomAppBar { DayPicker(loaded, model::pick) }
            }
        },
    ) { padding ->
        when (val current = state) {
            HomeState.Loading ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
            HomeState.Failed ->
                Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) { Text("The puzzles didn't load.") }
            is HomeState.Loaded -> {
                DayList(current, padding) { onOpen(it, current.day) }
                current.languagePrompt?.let { suggested -> LanguagePrompt(suggested, model::chooseLanguages) }
            }
        }
    }
}

@Composable
private fun DayList(
    state: HomeState.Loaded,
    padding: PaddingValues,
    onOpen: (HomeEntry) -> Unit,
) {
    val open = state.entries.filter { !it.isCompleted }
    val completed = state.entries.filter { it.isCompleted }
    val multilingual = state.multilingual

    fun LazyListScope.rows(
        entries: List<HomeEntry>,
        labeling: RowLabeling,
    ) = items(entries, key = { "${labeling.section}-${it.id}" }) { entry ->
        EntryRow(entry, labeling, state.streaks[entry.line] ?: 0, Modifier.clickable { onOpen(entry) })
    }

    LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
        if (state.entries.isEmpty()) {
            item { Text("No puzzles for ${state.day.name(includingYear = true)}.", modifier = Modifier.padding(16.dp)) }
        }
        when (state.grouping) {
            HomeGrouping.GAME ->
                for (kind in PuzzleKind.entries) {
                    val ofKind = open.filter { it.kind == kind }
                    if (ofKind.isEmpty()) continue
                    item(key = "header-${kind.code}") { SectionHeader(kind.displayName) }
                    if (multilingual) {
                        for (language in Language.entries) {
                            val ofLanguage = ofKind.filter { it.language == language }
                            if (ofLanguage.isEmpty()) continue
                            item(key = "header-${kind.code}-${language.code}") { LanguageHeader(language) }
                            rows(ofLanguage, RowLabeling(HomeGrouping.GAME, showsFlag = false))
                        }
                    } else {
                        rows(ofKind, RowLabeling(HomeGrouping.GAME, showsFlag = false))
                    }
                }
            HomeGrouping.N ->
                for (n in open.map { it.n }.distinct().sorted()) {
                    item(key = "header-n-$n") { SectionHeader("n=$n") }
                    rows(open.filter { it.n == n }, RowLabeling(HomeGrouping.N, showsFlag = multilingual))
                }
        }
        if (completed.isNotEmpty()) {
            item(key = "header-completed") { SectionHeader("Completed") }
            rows(completed, RowLabeling(null, showsFlag = multilingual))
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleMedium,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
    )
}

@Composable
private fun LanguageHeader(language: Language) {
    Text(
        "${language.flag} ${language.displayName}",
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 8.dp, bottom = 2.dp),
    )
}

@Composable
private fun EntryRow(
    entry: HomeEntry,
    labeling: RowLabeling,
    streak: Int,
    modifier: Modifier,
) {
    ListItem(
        modifier = modifier,
        headlineContent = { Text(labeling.title(entry)) },
        supportingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    when (entry) {
                        is HomeEntry.Tiles -> "${entry.game.puzzle.targets.size} targets"
                        else -> "${entry.n} letters"
                    },
                )
                StreakBadge(streak)
            }
        },
        trailingContent = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                val star = @Composable { Icon(Icons.Filled.Star, contentDescription = "Star", tint = StarColor) }
                when (entry) {
                    is HomeEntry.Word -> {
                        val game = entry.game
                        when (val status = game.status) {
                            is Status.Won -> {
                                star()
                                Text("${status.guesses}/${WordGame.MAX_GUESSES}")
                            }
                            Status.Lost -> Text("X/${WordGame.MAX_GUESSES}")
                            Status.Playing -> if (game.guesses.isNotEmpty()) Text("${game.guesses.size}/${WordGame.MAX_GUESSES}")
                        }
                    }
                    is HomeEntry.Tiles -> {
                        if (entry.game.earnedStar) star()
                        Text("${entry.game.score} / ${entry.game.puzzle.targetScore}")
                    }
                    is HomeEntry.Pangram -> {
                        if (entry.game.earnedStar) star()
                        Text("${entry.game.score} / ${entry.game.puzzle.targetScore}")
                    }
                }
            }
        },
    )
}

@Composable
private fun GroupingMenu(
    grouping: HomeGrouping,
    onGroup: (HomeGrouping) -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { open = true }) {
            Icon(Icons.AutoMirrored.Filled.ViewList, contentDescription = "Group by")
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            Text(
                "Group by",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
            )
            for (option in HomeGrouping.entries) {
                DropdownMenuItem(
                    text = { Text(option.displayName) },
                    trailingIcon = { if (option == grouping) Icon(Icons.Filled.Check, contentDescription = "Selected") },
                    onClick = {
                        onGroup(option)
                        open = false
                    },
                )
            }
        }
    }
}

/** Steps a day at a time, with the day shown between the arrows opening a calendar. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RowScope.DayPicker(
    state: HomeState.Loaded,
    onPick: (PuzzleDay?) -> Unit,
) {
    val earlier = state.days.lastOrNull { it < state.day }
    val later = state.days.firstOrNull { it > state.day }
    val title = if (state.day == state.today) "Today" else state.day.name(includingYear = state.day.date.year != state.today.date.year)
    var choosing by remember { mutableStateOf(false) }

    IconButton(onClick = { onPick(earlier) }, enabled = earlier != null) {
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, contentDescription = "Earlier")
    }
    Spacer(Modifier.weight(1f))
    TextButton(onClick = { choosing = true }, modifier = Modifier.semantics { contentDescription = "Choose a day, $title" }) {
        Icon(Icons.Filled.CalendarMonth, contentDescription = null)
        Spacer(Modifier.width(6.dp))
        Text(title)
    }
    Spacer(Modifier.weight(1f))
    IconButton(onClick = { onPick(later) }, enabled = later != null) {
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = "Later")
    }

    if (choosing) {
        val playable = remember(state.days) { state.days.map { it.date }.toSet() }
        val picker =
            rememberDatePickerState(
                initialSelectedDateMillis = state.day.date.utcMillis(),
                yearRange = (state.days.first().date.year)..(state.days.last().date.year),
                selectableDates =
                    object : SelectableDates {
                        override fun isSelectableDate(utcTimeMillis: Long) =
                            Instant.ofEpochMilli(utcTimeMillis).atZone(ZoneOffset.UTC).toLocalDate() in playable
                    },
            )
        DatePickerDialog(
            onDismissRequest = { choosing = false },
            confirmButton = {
                TextButton(onClick = {
                    picker.selectedDateMillis?.let {
                        onPick(PuzzleDay(Instant.ofEpochMilli(it).atZone(ZoneOffset.UTC).toLocalDate()))
                    }
                    choosing = false
                }) { Text("Done") }
            },
            dismissButton = {
                TextButton(onClick = {
                    onPick(null)
                    choosing = false
                }, enabled = state.day != state.today) { Text("Today") }
            },
        ) { DatePicker(picker) }
    }
}

private fun LocalDate.utcMillis(): Long = atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()

/** Asked once, before the first puzzle, so nobody is handed puzzles in a language they don't play. */
@Composable
private fun LanguagePrompt(
    suggested: Set<Language>,
    onChoose: (Set<Language>) -> Unit,
) {
    var draft by remember { mutableStateOf(suggested) }
    AlertDialog(
        onDismissRequest = {},
        title = { Text("Languages") },
        text = {
            Column {
                Text("Which languages do you want puzzles in?")
                for (language in Language.entries) {
                    Row(Modifier.padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("${language.flag} ${language.displayName}", modifier = Modifier.weight(1f))
                        Switch(
                            checked = language in draft,
                            onCheckedChange = { on -> draft = if (on) draft + language else draft - language },
                        )
                    }
                }
                HorizontalDivider(Modifier.padding(vertical = 8.dp))
                Text(
                    "You can change this any time in Settings.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = { onChoose(draft) }, enabled = draft.isNotEmpty()) { Text("Continue") }
        },
    )
}
