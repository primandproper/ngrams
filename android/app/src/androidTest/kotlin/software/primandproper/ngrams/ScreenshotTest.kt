package software.primandproper.ngrams

import android.content.Intent
import android.graphics.Bitmap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.isRoot
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.printToLog
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Walks the app through its Play Store screenshots on a seeded, pinned day, saving each to the
 * app's external files. make screenshots runs this on an emulator and pulls them off; make test
 * leaves it out. It finds everything by test tag, so it runs in whatever language the app is set to.
 */
@RunWith(AndroidJUnit4::class)
class ScreenshotTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    @Test
    fun screenshots() {
        val intent =
            Intent(instrumentation.targetContext, MainActivity::class.java)
                // Three weeks into the bank, so the seeded history has room for streaks, and the
                // same day the iOS screenshots use.
                .putExtra(ScreenshotSetup.PINNED_TODAY, "2026-11-12")
                .putExtra(ScreenshotSetup.SEED, true)

        ActivityScenario.launch<MainActivity>(intent).use {
            waitFor(hasTestTag("word-en-5"))
            snap("01-home")

            open("word-es-5")
            waitFor(hasTestTag("keyboard"))
            snap("02-password")
            back()

            open("tiles-en-4")
            waitFor(hasTestTag("board"))
            snap("03-tiles")
            back()

            open("pangram-en-7")
            waitFor(hasTestTag("wheel"))
            snap("04-pangram")
            back()

            compose.onNodeWithTag("stats").performClick()
            waitFor(hasTestTag("stats-list"))
            snap("05-stats")
            back()

            compose.onNodeWithTag("settings-button").performClick()
            waitFor(hasTestTag("settings"))
            snap("06-settings")
        }
    }

    /**
     * Opens a home row by its puzzle's tag, scrolling the list to it first. The click goes through
     * the row's semantics action rather than a tap, since a row scrolled into view can still sit
     * under the bottom bar, which would take the tap.
     */
    private fun open(tag: String) {
        compose.onNodeWithTag("home").performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
    }

    /** Goes back to home and waits out the transition, while which home is in the tree twice. */
    private fun back() {
        compose.onNodeWithTag("back").performClick()
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodes(hasTestTag("back")).fetchSemanticsNodes().isEmpty() &&
                compose.onAllNodes(hasTestTag("home")).fetchSemanticsNodes().size == 1
        }
        compose.waitForIdle()
    }

    /** Waits for a node, logging what's on screen if it never shows, so a failed run says why. */
    private fun waitFor(matcher: SemanticsMatcher) {
        try {
            compose.waitUntil(timeoutMillis = 15_000) { compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty() }
        } catch (e: ComposeTimeoutException) {
            compose.onAllNodes(isRoot()).printToLog("ScreenshotTest", maxDepth = Int.MAX_VALUE)
            throw AssertionError("never saw ${matcher.description}", e)
        }
        compose.waitForIdle()
    }

    /** The whole screen, status bar included, as an opaque PNG: Play refuses screenshots with alpha. */
    private fun snap(name: String) {
        // The tree can be ready a frame before the screen shows it, and the screenshot reads the
        // screen.
        Thread.sleep(750)
        val bitmap = checkNotNull(instrumentation.uiAutomation.takeScreenshot()) { "no screenshot for $name" }
        bitmap.setHasAlpha(false)
        val dir = File(instrumentation.targetContext.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
        File(dir, "$name.png").outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) { "couldn't write $name" } }
    }
}
