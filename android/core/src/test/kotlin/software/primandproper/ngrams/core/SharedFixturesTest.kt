package software.primandproper.ngrams.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Test
import java.time.Instant
import java.time.ZoneId
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Runs testdata/, the cases the iOS tests run too, so the two apps play the same game. */
class SharedFixturesTest {
    private fun fixture(name: String): JsonObject = Json.parseToJsonElement(resource(name).bufferedReader().readText()).jsonObject

    private fun bank(fixture: JsonObject): PuzzleBank = PuzzleBank.decode(fixture.getValue("bank").toString().byteInputStream())

    private val JsonElement.string get() = jsonPrimitive.content
    private val JsonElement.strings get() = jsonArray.map { it.string }
    private val JsonElement.ints get() = jsonArray.map { it.jsonPrimitive.int }

    private operator fun JsonElement.get(key: String): JsonElement = jsonObject.getValue(key)

    private val day = PuzzleDay.parse("2027-01-01")!!

    @Test
    fun `lays boards out the way the iOS app does`() {
        val fixture = fixture("layouts.json")

        for (case in fixture.getValue("generator").jsonArray) {
            val rng = SeededGenerator(case["seed"].string)
            assertEquals(case["outputs"].strings, case["outputs"].jsonArray.map { rng.next().toString() }, "seed '${case["seed"].string}'")
        }
        for (case in fixture.getValue("shuffles").jsonArray) {
            val order = MutableList(case["count"].jsonPrimitive.int) { it }
            order.shuffle(SeededGenerator(case["seed"].string))
            assertEquals(case["order"].ints, order, "seed '${case["seed"].string}'")
        }
        for (case in fixture.getValue("tiles").jsonArray) {
            val n = case["n"].jsonPrimitive.int
            val targets = case["targets"].jsonPrimitive.int
            val puzzle =
                TilesPuzzle(
                    Language.EN,
                    n,
                    List(n * targets) { "t$it" },
                    List(targets) { t -> List(n) { t * n + it } },
                    40,
                    100,
                    emptyList(),
                )
            val order = TilesLayout.spread(List(n * targets) { it }, puzzle, SeededGenerator(case["seed"].string))
            assertEquals(case["order"].ints, order, "seed '${case["seed"].string}'")
            assertTrue(TilesLayout.isSpread(order, puzzle))
        }
        for (case in fixture.getValue("wheels").jsonArray) {
            val center = case["center"].string.single()
            val outer = case["letters"].string.filter { it != center }.toMutableList()
            outer.shuffle(SeededGenerator(case["seed"].string))
            assertEquals(case["outer"].string, outer.joinToString(""), "seed '${case["seed"].string}'")
        }
    }

    @Test
    fun `plays tiles the way the iOS app does`() {
        val fixture = fixture("tiles.json")
        val bank = bank(fixture)

        fun puzzle(case: JsonElement) = bank.tilesPuzzles(day).single { it.language.code == case["lang"].string }

        for (case in fixture.getValue("states").jsonArray) {
            val game = TilesGame(puzzle(case), case["found"].strings)
            val label = "${case["lang"].string} ${case["found"].strings}"
            assertEquals(case["foundWords"].strings, game.foundWords, label)
            assertEquals(case["score"].jsonPrimitive.int, game.score, label)
            assertEquals(case["solvedTargets"].ints, game.solvedTargets, label)
            assertEquals(case["allTargetsFound"].jsonPrimitive.boolean, game.allTargetsFound, label)
            assertEquals(case["earnedStar"].jsonPrimitive.boolean, game.earnedStar, label)
        }
        for (case in fixture.getValue("submissions").jsonArray) {
            var game = TilesGame(puzzle(case), case["found"].strings, case["solvedTilesLeave"].jsonPrimitive.boolean)
            for (tile in case["taps"].ints) {
                game = game.toggle(tile)
            }
            val label = "taps ${case["taps"].ints} after ${case["found"].strings}"
            assertEquals(case["selection"].ints, game.selection, label)

            val (after, submission) = game.submit()
            val (result, text) =
                when (submission) {
                    is TilesSubmission.Found -> "found" to submission.word.word
                    is TilesSubmission.AlreadyFound -> "alreadyFound" to submission.word.word
                    is TilesSubmission.Blocked -> "blocked" to submission.text
                    is TilesSubmission.NotAWord -> "notAWord" to submission.text
                    TilesSubmission.Empty -> "empty" to ""
                }
            assertEquals(case["result"].string to case["text"].string, result to text, label)
            assertEquals(case["foundAfter"].strings, after.foundWords, label)
            assertTrue(after.selection.isEmpty(), label)
        }
    }

    @Test
    fun `plays pangrams the way the iOS app does`() {
        val fixture = fixture("pangram.json")
        val puzzle = bank(fixture).pangramPuzzles(day).single()

        for (case in fixture.getValue("states").jsonArray) {
            val game = PangramGame(puzzle, case["found"].strings)
            val label = "${case["found"].strings}"
            assertEquals(case["foundWords"].strings, game.foundWords, label)
            assertEquals(case["score"].jsonPrimitive.int, game.score, label)
            assertEquals(case["foundPangrams"].jsonPrimitive.int, game.foundPangrams, label)
            assertEquals(case["foundBonusPangrams"].jsonPrimitive.int, game.foundBonusPangrams, label)
            assertEquals(case["earnedStar"].jsonPrimitive.boolean, game.earnedStar, label)
            assertEquals(case["alphabetical"].strings, game.found(FoundWordOrder.ALPHABETICAL).map { it.word }, label)
            assertEquals(case["recent"].strings, game.found(FoundWordOrder.RECENT).map { it.word }, label)
        }
        for (case in fixture.getValue("submissions").jsonArray) {
            val game =
                case["typed"].string.fold(
                    PangramGame(puzzle, case["found"].strings, case["hardMode"].jsonPrimitive.boolean),
                ) { g, letter -> g.type(letter) }
            val (after, submission) = game.submit()
            val (result, text) =
                when (submission) {
                    is PangramSubmission.Found -> "found" to submission.word.word
                    is PangramSubmission.AlreadyFound -> "alreadyFound" to submission.word.word
                    is PangramSubmission.Blocked -> "blocked" to submission.text
                    is PangramSubmission.NotAWord -> "notAWord" to submission.text
                    PangramSubmission.TooShort -> "tooShort" to ""
                    PangramSubmission.MissingCenter -> "missingCenter" to ""
                    PangramSubmission.NeedsPangram -> "needsPangram" to ""
                    PangramSubmission.Empty -> "empty" to ""
                }
            assertEquals(
                case["result"].string to case["text"].string,
                result to text,
                "'${case["typed"].string}' after ${case["found"].strings}",
            )
            assertEquals("", after.current)
        }
    }

    @Test
    fun `hints hard mode guesses the way the iOS app does`() {
        val fixture = fixture("word_hints.json")
        val answer = fixture.getValue("answer").string
        val puzzle = WordPuzzle(Language.EN, answer.length, answer)

        for (case in fixture.getValue("cases").jsonArray) {
            val hint = WordGame(puzzle, case["guesses"].strings, hardMode = true).missingHint(case["guess"].string)
            val expected =
                case["hint"].takeIf { it != JsonNull }?.let {
                    when (it["kind"].string) {
                        "position" -> Hint.Position(it["letter"].string.single(), it["index"].jsonPrimitive.int)
                        else -> Hint.Letter(it["letter"].string.single())
                    }
                }
            assertEquals(expected, hint, "${case["guess"].string} after ${case["guesses"].strings}")
        }
    }

    @Test
    fun `keeps stats and streaks the way the iOS app does`() {
        val fixture = fixture("stats.json")
        val bank = bank(fixture)
        val zone = ZoneId.of(fixture.getValue("timeZone").string)

        for (scenario in fixture.getValue("scenarios").jsonArray) {
            val records =
                scenario["records"].jsonArray.map {
                    PlayRecord(
                        ProgressKey(
                            Language.fromCode(it["lang"].string)!!,
                            PuzzleKind.fromCode(it["kind"].string)!!,
                            it["n"].jsonPrimitive.int,
                            PuzzleDay.parse(it["day"].string)!!,
                        ),
                        it["entries"].strings,
                        it["completedAt"].takeIf { at -> at != JsonNull }?.let { at -> Instant.parse(at.string) },
                    )
                }
            val stats = StatsBook.compute(records, bank, PuzzleDay.parse(scenario["today"].string)!!, zone)

            for (expected in scenario["lines"].jsonArray) {
                val line =
                    PuzzleLine(
                        Language.fromCode(expected["lang"].string)!!,
                        PuzzleKind.fromCode(expected["kind"].string)!!,
                        expected["n"].jsonPrimitive.int,
                    )
                val actual = assertNotNull(stats[line], scenario["name"].string)
                assertEquals(
                    listOf("played", "decided", "successes", "currentStreak", "bestStreak").map {
                        expected[it].jsonPrimitive.int
                    } + expected["guessCounts"].ints,
                    listOf(actual.played, actual.decided, actual.successes, actual.currentStreak, actual.bestStreak) + actual.guessCounts,
                    scenario["name"].string,
                )
            }
        }
    }

    @Test
    fun `shares the way the iOS app does`() {
        val fixture = fixture("share.json")
        val bank = bank(fixture)
        val day = PuzzleDay.parse(fixture.getValue("day").string)!!

        fun matches(
            game: JsonElement,
            language: Language,
            n: Int,
        ) = game["lang"].string == language.code && game["n"].jsonPrimitive.int == n

        fun word(game: JsonElement) =
            WordGame(
                bank.wordPuzzles(day).single { matches(game, it.language, it.n) },
                game["entries"].strings,
                game["hardMode"].jsonPrimitive.boolean,
            )

        fun tiles(game: JsonElement) =
            TilesGame(
                bank.tilesPuzzles(day).single {
                    matches(game, it.language, it.n)
                },
                game["entries"].strings,
                game["hardMode"].jsonPrimitive.boolean,
            )

        fun pangram(game: JsonElement) =
            PangramGame(
                bank.pangramPuzzles(day).single {
                    matches(game, it.language, it.n)
                },
                game["entries"].strings,
                game["hardMode"].jsonPrimitive.boolean,
            )

        for (case in fixture.getValue("puzzles").jsonArray) {
            val text =
                when (case["kind"].string) {
                    "word" -> ShareText.word(word(case), day)
                    "tiles" -> ShareText.tiles(tiles(case), day)
                    else -> ShareText.pangram(pangram(case), day)
                }
            assertEquals(case["text"].string, text)
        }
        for (case in fixture.getValue("days").jsonArray) {
            val games = case["games"].jsonArray
            val text =
                ShareText.day(
                    games.filter { it["kind"].string == "word" }.map(::word),
                    games.filter { it["kind"].string == "tiles" }.map(::tiles),
                    games.filter { it["kind"].string == "pangram" }.map(::pangram),
                    day,
                )
            assertEquals(case["text"].takeIf { it != JsonNull }?.string, text)
        }
    }

    @Test
    fun `stores and moves hard modes the way the iOS app does`() {
        val fixture = fixture("settings.json")

        fun <V> JsonElement.byKind(value: (JsonElement) -> V): Map<PuzzleKind, V> =
            jsonObject.entries.associate { (code, raw) -> requireNotNull(PuzzleKind.fromCode(code)) to value(raw) }

        val keys = fixture.getValue("keys").byKind { it.string }
        val legacyKeys = fixture.getValue("legacyKeys").byKind { it.string }
        for (kind in PuzzleKind.entries) {
            assertEquals(keys[kind], HardModes.key(kind))
            assertEquals(legacyKeys[kind], HardModes.legacyKey(kind))
        }

        for (case in fixture.getValue("migrations").jsonArray) {
            val after =
                HardModes.migrated(
                    legacy = case["legacy"].byKind { it.jsonPrimitive.boolean },
                    current = case["current"].byKind { languagesFrom(it.string) },
                )
            assertEquals(case["after"].byKind { it.string }, after.mapValues { languageCodes(it.value) }, case["name"].string)
        }
    }
}
