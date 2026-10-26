// Package tiles generates tiles boards: target words of exactly N fragments that
// together use every tile, scored by the words a player can build from them.
package tiles

import (
	"cmp"
	"errors"
	"fmt"
	"math"
	"math/rand/v2"
	"slices"
	"strings"
	"sync"

	"github.com/primandproper/ngrams/generator/internal/lexicon"
)

const (
	minTileRunes = 2
	maxTileRunes = 4

	// boardTiles is the tile count every board aims for, whatever its N.
	boardTiles = 20

	hardPenalty    = 1000.0
	obscurePenalty = 0.01
	// blockedPenalty outweighs any plausible distance from the common-word range, so the
	// search only settles for a blocked found word when it can't climb away from one.
	blockedPenalty = 10.0

	// AllTargetsBonus is added to the score once every target is found.
	AllTargetsBonus = 40
	// extraScore is how far past every target and the bonus the target score sits, which
	// reproduces the original's 100 at N=4.
	extraScore = 20
)

// ErrNoBoard means a search found no board with distinct tiles and no extra
// full-length words.
var ErrNoBoard = errors.New("no valid board")

type (
	// SearchConfig is everything that shapes a board search.
	SearchConfig struct {
		_ struct{} `json:"-"`
		// Banned fragments are never used as tiles.
		Banned map[string]bool
		// N is the number of tiles in every target word.
		N int
		// Targets is how many target words a board hides.
		Targets int
		// MinCommon and MaxCommon bound the common words a good board has.
		MinCommon int
		MaxCommon int
		// Tries is how many independent hill climbs a search runs.
		Tries int
		// Steps is how many moves each climb makes.
		Steps int
	}

	// FoundWord is a valid word on a board, with the fewest tiles that build it.
	FoundWord struct {
		_     struct{} `json:"-"`
		Word  string
		Tiles []int
	}

	// Board is an evaluated set of targets. Tiles hold the targets' fragments in target
	// order, so target i is tiles i*N through i*N+N-1.
	Board struct {
		_          struct{} `json:"-"`
		Targets    []string
		Tiles      []string
		Found      []FoundWord
		Violations []string // full-length words that aren't targets
		Duplicates int      // tiles repeated on the board
		Common     int
		Obscure    int
		Blocked    int
		Weighted   float64 // sum of log10 counts of the common words
		Objective  float64 // lower is better
	}

	// Generator searches for boards of one size in one language.
	Generator struct {
		_      struct{} `json:"-"`
		lex    *lexicon.Lexicon
		splits map[string][][]string
		pool   []string
		cfg    SearchConfig
	}

	// candidate is a board under construction: target words plus which split of each
	// is in use, indexing into the generator's segmentation table.
	candidate struct {
		_      struct{} `json:"-"`
		words  []string
		splits []int
	}
)

// TargetsFor is how many targets a board of n-tile words hides, keeping the tile count
// near 20 at every n.
func TargetsFor(n int) int {
	return (boardTiles + n/2) / n
}

// Points is what a word built from tileCount tiles scores.
func Points(tileCount int) int {
	return 1 << (tileCount - 1)
}

// TargetScore is the score a player aims for on b.
func TargetScore(b *Board, n int) int {
	return len(b.Targets)*Points(n) + AllTargetsBonus + extraScore
}

// NewGenerator indexes every target word in lex that splits cleanly into cfg.N tiles.
func NewGenerator(lex *lexicon.Lexicon, cfg *SearchConfig) *Generator {
	g := &Generator{lex: lex, cfg: *cfg, splits: map[string][][]string{}}

	for _, word := range lex.Targets() {
		if segs := segmentations([]rune(word), cfg.N, cfg.Banned); len(segs) > 0 {
			g.splits[word] = segs
			g.pool = append(g.pool, word)
		}
	}

	return g
}

// PoolSize is how many target words split into N allowed tiles.
func (g *Generator) PoolSize() int {
	return len(g.pool)
}

// segmentations returns every way to cut word into exactly n fragments of allowed
// length that aren't banned.
func segmentations(word []rune, n int, banned map[string]bool) [][]string {
	if n == 0 {
		if len(word) == 0 {
			return [][]string{{}}
		}
		return nil
	}

	var out [][]string
	for size := minTileRunes; size <= maxTileRunes && size <= len(word); size++ {
		head := string(word[:size])
		if banned[head] {
			continue
		}
		for _, rest := range segmentations(word[size:], n-1, banned) {
			out = append(out, append([]string{head}, rest...))
		}
	}
	return out
}

// Best runs the configured hill climbs in parallel and returns the best valid board whose
// targets avoid exclude. Climb i draws from a generator seeded with (seed, i), so the
// result depends only on seed and exclude.
func (g *Generator) Best(seed uint64, exclude map[string]bool) (*Board, error) {
	available := slices.DeleteFunc(slices.Clone(g.pool), func(word string) bool { return exclude[word] })
	// Swapping a target needs at least one available word not already on the board.
	if len(available) <= g.cfg.Targets {
		return nil, fmt.Errorf("%d target words left, need more than %d: %w", len(available), g.cfg.Targets, ErrNoBoard)
	}

	boards := make([]*Board, g.cfg.Tries)
	var wg sync.WaitGroup
	for i := range boards {
		wg.Go(func() {
			rng := rand.New(rand.NewPCG(seed, uint64(i))) //nolint:gosec // boards must be reproducible from a seed, not secret
			boards[i] = g.climb(rng, available)
		})
	}
	wg.Wait()

	var best *Board
	for _, b := range boards {
		if b.valid() && (best == nil || b.Objective < best.Objective) {
			best = b
		}
	}
	if best == nil {
		return nil, fmt.Errorf("after %d tries: %w", g.cfg.Tries, ErrNoBoard)
	}

	return best, nil
}

func (b *Board) valid() bool {
	return len(b.Violations) == 0 && b.Duplicates == 0
}

func (g *Generator) climb(rng *rand.Rand, available []string) *Board {
	current := g.randomCandidate(rng, available)
	best := g.evaluate(current)

	for range g.cfg.Steps {
		next := current.clone()
		i := rng.IntN(len(next.words))
		if rng.IntN(2) == 0 {
			next.splits[i] = rng.IntN(len(g.splits[next.words[i]]))
		} else {
			next.words[i] = unusedWord(rng, available, next.words)
			next.splits[i] = rng.IntN(len(g.splits[next.words[i]]))
		}

		if b := g.evaluate(next); b.Objective <= best.Objective {
			current, best = next, b
		}
	}

	return best
}

func (g *Generator) randomCandidate(rng *rand.Rand, available []string) *candidate {
	c := &candidate{}
	for range g.cfg.Targets {
		word := unusedWord(rng, available, c.words)
		c.words = append(c.words, word)
		c.splits = append(c.splits, rng.IntN(len(g.splits[word])))
	}
	return c
}

// unusedWord picks a random word from available that isn't in used. available must hold
// more words than used.
func unusedWord(rng *rand.Rand, available, used []string) string {
	for {
		if word := available[rng.IntN(len(available))]; !slices.Contains(used, word) {
			return word
		}
	}
}

func (c *candidate) clone() *candidate {
	return &candidate{words: slices.Clone(c.words), splits: slices.Clone(c.splits)}
}

func (g *Generator) evaluate(c *candidate) *Board {
	b := &Board{Targets: slices.Clone(c.words)}
	tileCounts := map[string]int{}
	for i, word := range c.words {
		split := g.splits[word][c.splits[i]]
		b.Tiles = append(b.Tiles, split...)
		for _, tile := range split {
			tileCounts[tile]++
		}
	}
	for _, count := range tileCounts {
		b.Duplicates += count - 1
	}

	fullLength := g.enumerate(b)
	for word := range fullLength {
		if !slices.Contains(c.words, word) {
			b.Violations = append(b.Violations, word)
		}
	}
	slices.Sort(b.Violations)

	for i := range b.Found {
		word := b.Found[i].Word
		if g.lex.Blocked(word) {
			b.Blocked++
			continue
		}
		if count, ok := g.lex.Count(word); ok {
			b.Common++
			b.Weighted += math.Log10(float64(count))
		} else {
			b.Obscure++
		}
	}

	var outOfRange float64
	switch {
	case b.Common < g.cfg.MinCommon:
		outOfRange = float64(g.cfg.MinCommon - b.Common)
	case b.Common > g.cfg.MaxCommon:
		outOfRange = float64(b.Common - g.cfg.MaxCommon)
	}
	b.Objective = hardPenalty*float64(len(b.Violations)+b.Duplicates) +
		outOfRange +
		obscurePenalty*float64(b.Obscure) +
		blockedPenalty*float64(b.Blocked)

	return b
}

// enumerate fills b.Found with every word buildable from 1 to N distinct tiles, and
// returns the set of words buildable from exactly N.
func (g *Generator) enumerate(b *Board) map[string]bool {
	shortest := map[string][]int{}
	fullLength := map[string]bool{}
	used := make([]bool, len(b.Tiles))
	var path []int

	var walk func(prefix string)
	walk = func(prefix string) {
		for i, tile := range b.Tiles {
			if used[i] {
				continue
			}
			s := prefix + tile
			isWord, isPrefix := g.lex.Lookup(s)
			if !isPrefix {
				continue
			}

			used[i] = true
			path = append(path, i)
			if isWord {
				if prev, ok := shortest[s]; !ok || len(path) < len(prev) {
					shortest[s] = slices.Clone(path)
				}
				if len(path) == g.cfg.N {
					fullLength[s] = true
				}
			}
			if len(path) < g.cfg.N {
				walk(s)
			}
			path = path[:len(path)-1]
			used[i] = false
		}
	}
	walk("")

	for word, tiles := range shortest {
		b.Found = append(b.Found, FoundWord{Word: word, Tiles: tiles})
	}
	slices.SortFunc(b.Found, func(x, y FoundWord) int {
		return cmp.Or(len(x.Tiles)-len(y.Tiles), strings.Compare(x.Word, y.Word))
	})

	return fullLength
}
