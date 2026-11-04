package software.primandproper.ngrams.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class AssistanceTest {
    @Test
    fun `counts a Password puzzle solved for the player as a loss, keeping its guesses`() {
        val game = WordGame(wordPuzzle, listOf("cramp")).type('l').giveUp().type('l')

        assertEquals(Status.Lost, game.status)
        assertEquals(listOf("cramp"), game.guesses)
        assertEquals("", game.current)
    }

    @Test
    fun `leaves a won Password puzzle won`() {
        val won = Status.Won(1)

        assertEquals(won, WordGame(wordPuzzle, listOf(wordPuzzle.answer)).giveUp().status)
        assertEquals(won, WordGame(wordPuzzle, listOf(wordPuzzle.answer), gaveUp = true).status)
    }

    @Test
    fun `takes hints only while a Password puzzle is in play`() {
        val game = WordGame(wordPuzzle, hints = listOf("0")).takeHint("1")
        assertEquals(listOf("0", "1"), game.hints)
        assertEquals(Status.Playing, game.status)

        assertEquals(listOf("0", "1"), game.giveUp().takeHint("2").hints)
    }
}
