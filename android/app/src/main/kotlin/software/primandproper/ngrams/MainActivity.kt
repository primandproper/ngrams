package software.primandproper.ngrams

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavGraphBuilder
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.core.PuzzleKind
import software.primandproper.ngrams.core.PuzzleLine
import software.primandproper.ngrams.ui.AcknowledgementsScreen
import software.primandproper.ngrams.ui.HomeScreen
import software.primandproper.ngrams.ui.LineStatsScreen
import software.primandproper.ngrams.ui.NgramsTheme
import software.primandproper.ngrams.ui.PangramScreen
import software.primandproper.ngrams.ui.PasswordScreen
import software.primandproper.ngrams.ui.SettingsScreen
import software.primandproper.ngrams.ui.StatsScreen
import software.primandproper.ngrams.ui.TilesScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as NgramsApplication).container
        ScreenshotSetup.apply(container, intent)

        setContent {
            NgramsTheme {
                val nav = rememberNavController()
                val back: () -> Unit = { nav.popBackStack() }
                NavHost(nav, startDestination = "home") {
                    composable("home") {
                        HomeScreen(
                            container,
                            onOpen = { entry, day -> nav.navigate("${entry.kind.code}/${entry.language.code}/${entry.n}/$day") },
                            onStats = { nav.navigate("stats") },
                            onSettings = { nav.navigate("settings") },
                        )
                    }
                    puzzle(PuzzleKind.WORD, back) { language, n, day -> PasswordScreen(container, language, n, day, back) }
                    puzzle(PuzzleKind.TILES, back) { language, n, day -> TilesScreen(container, language, n, day, back) }
                    puzzle(PuzzleKind.PANGRAM, back) { language, n, day -> PangramScreen(container, language, n, day, back) }
                    composable("stats") {
                        StatsScreen(
                            container,
                            onLine = { nav.navigate("stats/${it.kind.code}/${it.language.code}/${it.n}") },
                            onBack = back,
                        )
                    }
                    composable("stats/{kind}/{language}/{n}", arguments = lineArguments) { entry ->
                        val line = entry.line()
                        if (line == null) back() else LineStatsScreen(container, line, back)
                    }
                    composable("settings") {
                        SettingsScreen(container, onAcknowledgements = { nav.navigate("acknowledgements") }, onBack = back)
                    }
                    composable("acknowledgements") { AcknowledgementsScreen(back) }
                }
            }
        }
    }
}

private val lineArguments =
    listOf(
        navArgument("kind") { type = NavType.StringType },
        navArgument("language") { type = NavType.StringType },
        navArgument("n") { type = NavType.IntType },
    )

private fun NavBackStackEntry.line(): PuzzleLine? {
    val args = arguments ?: return null
    val kind = PuzzleKind.fromCode(args.getString("kind").orEmpty()) ?: return null
    val language = Language.fromCode(args.getString("language").orEmpty()) ?: return null
    return PuzzleLine(language, kind, args.getInt("n"))
}

/** A puzzle's screen at `kind/language/n/day`, leaving it if the route doesn't parse. */
private fun NavGraphBuilder.puzzle(
    kind: PuzzleKind,
    back: () -> Unit,
    screen: @Composable (Language, Int, PuzzleDay) -> Unit,
) {
    composable(
        "${kind.code}/{language}/{n}/{day}",
        arguments =
            listOf(
                navArgument("language") { type = NavType.StringType },
                navArgument("n") { type = NavType.IntType },
                navArgument("day") { type = NavType.StringType },
            ),
    ) { entry ->
        val args = entry.arguments
        val language = Language.fromCode(args?.getString("language").orEmpty())
        val day = PuzzleDay.parse(args?.getString("day").orEmpty())
        if (args == null || language == null || day == null) back() else screen(language, args.getInt("n"), day)
    }
}
