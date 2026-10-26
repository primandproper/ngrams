package software.primandproper.ngrams.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class WordGameTest {
    @Serializable
    private data class MarksFixture(
        val cases: List<Case>,
    ) {
        @Serializable
        data class Case(
            val answer: String,
            val guess: String,
            val marks: List<String>,
        )
    }

    @Test
    fun `marks every shared case the way the iOS app does`() {
        val fixture =
            Json { ignoreUnknownKeys = true }.decodeFromString<MarksFixture>(
                resource("word_marks.json").bufferedReader().readText(),
            )

        assertTrue(fixture.cases.isNotEmpty())
        for (case in fixture.cases) {
            val marks = WordGame.marks(case.guess, case.answer).map { it.name.lowercase() }
            assertEquals(case.marks, marks, "${case.guess} against ${case.answer}")
        }
    }

    @Test
    fun `solves with the answer`() {
        var game = WordGame(wordPuzzle).typed("cramp")
        var submitted = game.submit(wordList)
        assertEquals(Submission.Guessed("cramp"), submitted.submission)

        game = submitted.game.typed("llama")
        submitted = game.submit(wordList)

        assertEquals(Submission.Guessed("llama"), submitted.submission)
        assertEquals(Status.Won(2), submitted.game.status)
        assertEquals("", submitted.game.current)
    }

    @Test
    fun `loses after the last guess`() {
        val game = WordGame(wordPuzzle, List(5) { "cramp" }).typed("plaza")
        val lost = game.submit(wordList).game

        assertEquals(Status.Lost, lost.status)
        assertEquals("", lost.typed("llama").current)
        assertEquals(Submission.Over, lost.submit(wordList).submission)
    }

    @Test
    fun `keeps the best mark per letter for the keyboard`() {
        val game = WordGame(wordPuzzle, listOf("plaza", "label"))

        assertEquals(LetterMark.CORRECT, game.letterMarks['l'])
        assertEquals(LetterMark.CORRECT, game.letterMarks['a'])
        assertEquals(LetterMark.ABSENT, game.letterMarks['p'])
    }

    @Test
    fun `refuses short, unknown, and blocked guesses and keeps them typed`() {
        var game = WordGame(wordPuzzle).typed("lla")
        assertEquals(Submission.TooShort, game.submit(wordList).submission)

        game = game.typed("mz")
        val unknown = game.submit(wordList)
        assertEquals(Submission.NotAWord("llamz"), unknown.submission)
        assertEquals("llamz", unknown.game.current)

        repeat(5) { game = game.deleteLetter() }
        game = game.typed("bitch")
        val blocked = game.submit(wordList)
        assertEquals(Submission.Blocked("bitch"), blocked.submission)
        assertTrue(blocked.game.guesses.isEmpty())
    }

    @Test
    fun `makes hard mode guesses keep correct letters in place`() {
        // PLAZA finds L, A, and A in place against LLAMA.
        val game = WordGame(wordPuzzle, listOf("plaza"), hardMode = true).typed("label")
        val refused = game.submit(wordList)

        assertEquals(Submission.MissingHint(Hint.Position('l', 1)), refused.submission)
        assertEquals("label", refused.game.current)
        assertEquals(listOf("plaza"), refused.game.guesses)

        val easy = WordGame(wordPuzzle, listOf("plaza")).typed("label")
        assertEquals(Submission.Guessed("label"), easy.submit(wordList).submission)
    }

    @Test
    fun `makes hard mode guesses use every found letter, counting copies`() {
        // LABEL finds an L in place, another L, and an A.
        var game = WordGame(wordPuzzle, listOf("label"), hardMode = true).typed("lolls")
        assertEquals(Submission.MissingHint(Hint.Letter('a')), game.submit(wordList).submission)

        // LOLLS finds an L in place and a second L that LOAMY leaves out.
        game = WordGame(wordPuzzle, listOf("lolls"), hardMode = true).typed("loamy")
        assertEquals(Submission.MissingHint(Hint.Letter('l')), game.submit(wordList).submission)

        game = WordGame(wordPuzzle, listOf("label"), hardMode = true).typed("llama")
        assertEquals(Submission.Guessed("llama"), game.submit(wordList).submission)
    }

    @Test
    fun `types at most n letters`() {
        assertEquals("llama", WordGame(wordPuzzle).typed("llamas").current)
    }

    @Test
    fun `drops saved guesses it can't hold`() {
        val game = WordGame(wordPuzzle, listOf("cramp", "lla", "llama", "plaza"))

        assertEquals(listOf("cramp", "llama"), game.guesses)
        assertEquals(Status.Won(2), game.status)
    }
}
