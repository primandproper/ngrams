package software.primandproper.ngrams

import android.util.Log
import software.primandproper.ngrams.core.Level
import software.primandproper.ngrams.core.Logger

/**
 * A [Logger] that writes to Logcat, rendering accumulated values as a trailing `{k=v, ...}` block.
 * Immutable: every `with*` returns a new logger.
 */
class LogcatLogger private constructor(
    private val tag: String,
    private val minLevel: Level,
    private val values: Map<String, Any?>,
) : Logger {
    constructor(tag: String, minLevel: Level = Level.DEBUG) : this(tag, minLevel, emptyMap())

    private fun enabled(level: Level) = level >= minLevel

    private fun render(msg: String): String =
        if (values.isEmpty()) {
            msg
        } else {
            values.entries.joinToString(", ", prefix = "$msg {", postfix = "}") { (k, v) -> "$k=$v" }
        }

    override fun debug(msg: String) {
        if (enabled(Level.DEBUG)) Log.d(tag, render(msg))
    }

    override fun info(msg: String) {
        if (enabled(Level.INFO)) Log.i(tag, render(msg))
    }

    override fun warn(msg: String) {
        if (enabled(Level.WARN)) Log.w(tag, render(msg))
    }

    override fun error(
        whatWasHappening: String,
        err: Throwable?,
    ) {
        if (enabled(Level.ERROR)) Log.e(tag, render(whatWasHappening), err)
    }

    override fun withName(name: String): Logger = LogcatLogger(name, minLevel, values)

    override fun withValue(
        key: String,
        value: Any?,
    ): Logger = LogcatLogger(tag, minLevel, values + (key to value))
}
