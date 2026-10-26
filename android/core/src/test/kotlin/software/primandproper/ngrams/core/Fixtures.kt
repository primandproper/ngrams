package software.primandproper.ngrams.core

/** A five-letter word puzzle whose answer has a repeated letter, so marking repeats matters. */
val wordPuzzle = WordPuzzle(Language.EN, 5, "llama")

val wordList =
    GuessList(
        accepted = setOf("llama", "label", "allay", "lolls", "loamy", "cramp", "plaza"),
        blocked = setOf("bitch"),
    )

fun WordGame.typed(text: String): WordGame = text.fold(this) { game, letter -> game.type(letter) }

/** Reads a test resource: testdata/ and data/bank/ are both on the test classpath. */
fun resource(name: String) = requireNotNull(object {}.javaClass.classLoader.getResourceAsStream(name)) { "no test resource $name" }
