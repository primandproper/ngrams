package software.primandproper.ngrams.core

/**
 * SplitMix64, so a board's first layout comes out the same on every launch, and the same as the
 * iOS app's: this, [nextBelow], and [shuffle] reproduce the Swift standard library's algorithms
 * bit for bit, and testdata/layouts.json holds both apps to it.
 */
class SeededGenerator(
    private var state: ULong,
) {
    /** Seeds from a string with FNV-1a over its UTF-8 bytes, as the iOS app does. */
    constructor(seed: String) : this(fnv1a(seed))

    fun next(): ULong {
        state += 0x9e3779b97f4a7c15uL
        var z = state
        z = (z xor (z shr 30)) * 0xbf58476d1ce4e5b9uL
        z = (z xor (z shr 27)) * 0x94d049bb133111ebuL
        return z xor (z shr 31)
    }

    /**
     * A number below [upperBound], by Swift's `RandomNumberGenerator.next(upperBound:)`: the high
     * half of a full-width multiply, rejecting the few draws that would bias it.
     */
    fun nextBelow(upperBound: ULong): ULong {
        var product = multiplyFull(next(), upperBound)
        if (product.second < upperBound) {
            val threshold = (0uL - upperBound) % upperBound
            while (product.second < threshold) {
                product = multiplyFull(next(), upperBound)
            }
        }
        return product.first
    }

    companion object {
        private fun fnv1a(seed: String): ULong {
            var hash = 0xcbf29ce484222325uL
            for (byte in seed.encodeToByteArray()) {
                hash = (hash xor (byte.toInt() and 0xff).toULong()) * 0x100000001b3uL
            }
            return hash
        }

        /** The 128-bit product of [a] and [b], as (high, low). */
        private fun multiplyFull(
            a: ULong,
            b: ULong,
        ): Pair<ULong, ULong> {
            val mask = 0xffffffffuL
            val aLow = a and mask
            val aHigh = a shr 32
            val bLow = b and mask
            val bHigh = b shr 32
            val lowLow = aLow * bLow
            val highLow = aHigh * bLow
            val lowHigh = aLow * bHigh
            val highHigh = aHigh * bHigh
            val cross = (lowLow shr 32) + (highLow and mask) + lowHigh
            val high = highHigh + (highLow shr 32) + (cross shr 32)
            val low = (cross shl 32) or (lowLow and mask)
            return high to low
        }
    }
}

/** Shuffles in place the way Swift's `shuffle(using:)` does: Fisher-Yates from the front. */
fun <T> MutableList<T>.shuffle(rng: SeededGenerator) {
    var amount = size
    var current = 0
    while (amount > 1) {
        val random = rng.nextBelow(amount.toULong()).toInt()
        amount -= 1
        val other = current + random
        this[current] = this[other].also { this[other] = this[current] }
        current += 1
    }
}

/** The seed a puzzle's first layout comes from, the same string the iOS app uses. */
fun layoutSeed(
    language: Language,
    kind: PuzzleKind,
    n: Int,
    day: PuzzleDay,
): String = "${language.code}-${kind.code}-$n-$day"
