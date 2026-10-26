package software.primandproper.ngrams.core

/** Logging severity. */
enum class Level { DEBUG, INFO, WARN, ERROR }

/**
 * Structured logger. A stand-in shaped like primandproper/primitives-kt's observability `Logger`,
 * method for method, so that package can replace it once ngrams can depend on it. Every `with*`
 * returns a new logger carrying the added context.
 */
interface Logger {
    fun debug(msg: String)

    fun info(msg: String)

    fun warn(msg: String)

    /** [whatWasHappening] says what the code was doing when [err] happened. */
    fun error(
        whatWasHappening: String,
        err: Throwable?,
    )

    fun withName(name: String): Logger

    fun withValue(
        key: String,
        value: Any?,
    ): Logger
}

/** A logger that discards everything, for tests that don't assert on logs. */
object NoopLogger : Logger {
    override fun debug(msg: String) {}

    override fun info(msg: String) {}

    override fun warn(msg: String) {}

    override fun error(
        whatWasHappening: String,
        err: Throwable?,
    ) {}

    override fun withName(name: String): Logger = this

    override fun withValue(
        key: String,
        value: Any?,
    ): Logger = this
}
