package software.primandproper.ngrams.ui

import android.content.Context
import android.content.Intent
import androidx.annotation.StringRes
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import kotlinx.coroutines.withTimeoutOrNull
import software.primandproper.ngrams.R
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.LineStats
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import kotlin.math.roundToInt

/**
 * Something to tell the player about their last move: a string resource and its format arguments,
 * resolved when it's shown so ViewModels stay free of Context. [id] tells two identical messages
 * apart.
 */
data class Feedback(
    @StringRes val message: Int,
    val args: List<Any> = emptyList(),
    val id: Long = System.nanoTime(),
)

/** The language the interface is showing: the one its string resources are in. */
fun Context.interfaceLanguage(): Language = Language.fromCode(getString(R.string.interface_language)) ?: Language.EN

/** The language the interface is showing, for game names, dates and share text. */
@Composable
fun interfaceLanguage(): Language = Language.fromCode(stringResource(R.string.interface_language)) ?: Language.EN

/** A top bar's way back, tagged so tests find it whatever the language. */
@Composable
fun BackButton(onBack: () -> Unit) {
    IconButton(onClick = onBack, modifier = Modifier.testTag("back")) {
        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
    }
}

/** The orange the iOS app uses for stars and streaks. */
val StarColor = Color(0xFFFF9500)

/**
 * Shows [feedback] at the top of the screen for a moment, then calls [onShown]. At the top rather
 * than in Scaffold's bottom slot, where it would cover the keyboard and controls.
 */
@Composable
fun BoxScope.FeedbackHost(
    feedback: Feedback?,
    onShown: (Feedback) -> Unit,
) {
    val host = remember { SnackbarHostState() }
    val context = LocalContext.current
    LaunchedEffect(feedback) {
        if (feedback != null) {
            host.currentSnackbarData?.dismiss()
            val message = context.getString(feedback.message, *feedback.args.toTypedArray())
            withTimeoutOrNull(1_500) { host.showSnackbar(message) }
            onShown(feedback)
        }
    }
    SnackbarHost(host, Modifier.align(Alignment.TopCenter).zIndex(1f))
}

/** A flame and the current streak, or nothing without one. */
@Composable
fun StreakBadge(streak: Int) {
    if (streak > 0) {
        val description = pluralStringResource(R.plurals.streak_description, streak, streak)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.clearAndSetSemantics { contentDescription = description },
        ) {
            Icon(Icons.Filled.LocalFireDepartment, contentDescription = null, tint = StarColor, modifier = Modifier.padding(end = 2.dp))
            Text("$streak", color = StarColor, fontWeight = FontWeight.SemiBold, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** Opens the system share sheet with [text]. */
fun share(
    context: Context,
    text: String,
) {
    val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
    context.startActivity(Intent.createChooser(send, null))
}

/** A top bar action that shares [text]. */
@Composable
fun ShareAction(text: String) {
    val context = LocalContext.current
    IconButton(onClick = { share(context, text) }) {
        Icon(Icons.Filled.Share, contentDescription = stringResource(R.string.share))
    }
}

/** A board's score against its target, its progress toward the star's other half, and the star. */
@Composable
fun ScoreHeader(
    score: Int,
    target: Int,
    progress: String,
    earnedStar: Boolean,
    missing: String,
) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text("$score", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
            Text(" / $target", color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
            Spacer(Modifier.weight(1f))
            Text(progress, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(bottom = 6.dp))
        }
        LinearProgressIndicator(progress = { (score.toFloat() / maxOf(target, 1)).coerceAtMost(1f) }, modifier = Modifier.fillMaxWidth())
        if (earnedStar) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Star, contentDescription = null, tint = StarColor)
                Text(
                    stringResource(R.string.star_earned),
                    color = StarColor,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.padding(start = 4.dp),
                )
            }
        } else if (score >= target) {
            Text(missing, color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

/** The line's flag, game and size, with the game named in [interfaceLanguage]. */
fun PuzzleLine.title(interfaceLanguage: Language): String = "${language.flag} ${kind.displayName(interfaceLanguage)} · n=$n"

/** What counts as success on a line: winning a Password puzzle, starring a board. */
@StringRes
fun successLabel(kind: PuzzleKind): Int = if (kind == PuzzleKind.WORD) R.string.won else R.string.starred

/** "12 played · 50% won", or starred for a board. */
@Composable
fun statsSummary(stats: LineStats): String =
    pluralStringResource(
        if (stats.line.kind == PuzzleKind.WORD) R.plurals.stats_won_summary else R.plurals.stats_starred_summary,
        stats.played,
        stats.played,
        percent(stats.successRate),
    )

fun percent(rate: Double?): String = rate?.let { "${(it * 100).roundToInt()}%" } ?: "–"

/** One line's numbers, and for Password how many guesses each solve took. */
@Composable
fun LineStatsView(
    stats: LineStats,
    highlight: Int? = null,
) {
    Column(
        Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Row(Modifier.fillMaxWidth()) {
            Figure("${stats.played}", stringResource(R.string.played))
            Figure(percent(stats.successRate), stringResource(successLabel(stats.line.kind)))
            Figure("${stats.currentStreak}", stringResource(R.string.streak))
            Figure("${stats.bestStreak}", stringResource(R.string.best_streak))
        }
        if (stats.line.kind == PuzzleKind.WORD) {
            GuessDistribution(stats.guessCounts, highlight)
        }
        Text(
            stringResource(if (stats.line.kind == PuzzleKind.WORD) R.string.streaks_count_solves else R.string.streaks_count_stars),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun RowScope.Figure(
    value: String,
    label: String,
) {
    Column(
        Modifier.weight(1f).clearAndSetSemantics { contentDescription = "$label: $value" },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(value, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun GuessDistribution(
    counts: List<Int>,
    highlight: Int?,
) {
    val most = maxOf(counts.maxOrNull() ?: 0, 1)
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(stringResource(R.string.guesses), style = MaterialTheme.typography.titleMedium)
        counts.forEachIndexed { index, count ->
            val description = pluralStringResource(R.plurals.guess_distribution_row, index + 1, index + 1, count)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.clearAndSetSemantics { contentDescription = description },
            ) {
                Text("${index + 1}", modifier = Modifier.width(16.dp))
                BoxWithConstraints(Modifier.weight(1f)) {
                    // Every bar is at least wide enough for its count, as on iOS.
                    Box(
                        Modifier
                            .width(maxOf(30.dp, maxWidth * (count.toFloat() / most)))
                            .height(22.dp)
                            .background(
                                if (index + 1 == highlight) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.outline,
                                RoundedCornerShape(4.dp),
                            ),
                        contentAlignment = Alignment.CenterEnd,
                    ) {
                        Text(
                            "$count",
                            color = MaterialTheme.colorScheme.surface,
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            modifier = Modifier.padding(horizontal = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

/** One line's stats in a sheet, shown when a puzzle is finished. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LineStatsSheet(
    line: PuzzleLine,
    stats: LineStats?,
    highlight: Int? = null,
    onDismiss: () -> Unit,
) {
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Text(line.title(interfaceLanguage()), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(horizontal = 16.dp))
        if (stats == null) {
            Text(stringResource(R.string.no_stats), modifier = Modifier.padding(16.dp))
        } else {
            LineStatsView(stats, highlight)
        }
    }
}
