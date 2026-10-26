package software.primandproper.ngrams

import android.content.Intent

/** Release builds ignore screenshot launches; the debug source set has the real one. */
object ScreenshotSetup {
    @Suppress("UNUSED_PARAMETER")
    fun apply(
        container: AppContainer,
        intent: Intent,
    ) {}
}
