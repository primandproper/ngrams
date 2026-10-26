package software.primandproper.ngrams.core

/**
 * Arranges a board's tiles so no target reads off it at a glance. A uniform shuffle leaves two of
 * a target's tiles side by side, in order, on about half of all boards.
 */
object TilesLayout {
    /** Enough draws that a board which can be spread effectively always is: the strictest board (N=4) passes about 1 draw in 300. */
    const val MAX_DRAWS = 10_000

    /** Orders [tiles] into rows of `puzzle.n` that pass [isSpread], falling back to the last draw if none does. */
    fun spread(
        tiles: List<Int>,
        puzzle: TilesPuzzle,
        rng: SeededGenerator,
    ): List<Int> {
        val owners = owners(puzzle)
        val order = tiles.toMutableList()
        repeat(MAX_DRAWS) {
            order.shuffle(rng)
            if (isSpread(order, puzzle.n, owners)) {
                return order
            }
        }
        return order
    }

    /** Whether no row holds more of one target's tiles than it must, and no two of a target's tiles sit side by side in reading order. */
    fun isSpread(
        order: List<Int>,
        puzzle: TilesPuzzle,
    ): Boolean = isSpread(order, puzzle.n, owners(puzzle))

    private data class Owner(
        val target: Int,
        val position: Int,
    )

    private fun owners(puzzle: TilesPuzzle): Map<Int, Owner> =
        buildMap {
            for ((target, tiles) in puzzle.targets.withIndex()) {
                for ((position, tile) in tiles.withIndex()) {
                    put(tile, Owner(target, position))
                }
            }
        }

    private fun isSpread(
        order: List<Int>,
        n: Int,
        owners: Map<Int, Owner>,
    ): Boolean {
        val targets = order.mapNotNull { owners[it]?.target }.toSet().size
        if (targets == 0) {
            return true
        }
        // A row of n tiles from fewer than n targets has to repeat one.
        val perRow = (n + targets - 1) / targets

        for (row in order.chunked(n)) {
            val rowOwners = row.mapNotNull { owners[it] }
            val counts = mutableMapOf<Int, Int>()
            for (owner in rowOwners) {
                val count = (counts[owner.target] ?: 0) + 1
                if (count > perRow) {
                    return false
                }
                counts[owner.target] = count
            }
            for ((left, right) in rowOwners.zipWithNext()) {
                if (left.target == right.target && right.position == left.position + 1) {
                    return false
                }
            }
        }
        return true
    }
}
