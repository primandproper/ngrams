package software.primandproper.ngrams

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import software.primandproper.ngrams.core.Language
import software.primandproper.ngrams.core.PuzzleDay
import software.primandproper.ngrams.ui.HomeScreen
import software.primandproper.ngrams.ui.NgramsTheme
import software.primandproper.ngrams.ui.PasswordScreen

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val container = (application as NgramsApplication).container

        setContent {
            NgramsTheme {
                val nav = rememberNavController()
                NavHost(nav, startDestination = "home") {
                    composable("home") {
                        HomeScreen(container) { puzzle, day ->
                            nav.navigate("password/${puzzle.language.code}/${puzzle.n}/$day")
                        }
                    }
                    composable(
                        "password/{language}/{n}/{day}",
                        arguments =
                            listOf(
                                navArgument("language") { type = NavType.StringType },
                                navArgument("n") { type = NavType.IntType },
                                navArgument("day") { type = NavType.StringType },
                            ),
                    ) { entry ->
                        val args = requireNotNull(entry.arguments)
                        val language = Language.fromCode(args.getString("language").orEmpty())
                        val day = PuzzleDay.parse(args.getString("day").orEmpty())
                        if (language == null || day == null) {
                            nav.popBackStack()
                        } else {
                            PasswordScreen(container, language, args.getInt("n"), day, onBack = { nav.popBackStack() })
                        }
                    }
                }
            }
        }
    }
}
