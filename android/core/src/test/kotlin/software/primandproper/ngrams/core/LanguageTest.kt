package software.primandproper.ngrams.core

import org.junit.jupiter.api.Test
import kotlin.test.assertEquals

class LanguageTest {
    @Test
    fun `suggests the device's languages the bank carries`() {
        assertEquals(setOf(Language.EN, Language.ES), suggestedLanguages(listOf("es-MX", "en-US", "fr-FR")))
        assertEquals(setOf(Language.ES), suggestedLanguages(listOf("es_419")))
        assertEquals(emptySet(), suggestedLanguages(listOf("de-DE")))
    }
}
