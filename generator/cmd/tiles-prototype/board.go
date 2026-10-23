package main

import (
	"math"
	"math/rand/v2"
	"slices"
	"strings"
)

const (
	minTileRunes = 2
	maxTileRunes = 4

	hardPenalty    = 1000.0
	obscurePenalty = 0.01
	// blockedPenalty outweighs any plausible distance from the common-word range, so the
	// search only settles for a blocked found word when it can't climb away from one.
	blockedPenalty = 10.0
)

type (
	// searchConfig is everything that shapes one batch of boards.
	searchConfig struct {
		_         struct{} `json:"-"`
		banned    map[string]bool
		n         int
		targets   int
		minCommon int
		maxCommon int
		tries     int
		steps     int
	}

	// candidate is a board under construction: target words plus which split of each
	// is in use, indexing into the generator's segmentation table.
	candidate struct {
		_      struct{} `json:"-"`
		words  []string
		splits []int
	}

	// foundWord is a valid word on a board, with the fewest tiles that build it.
	foundWord struct {
		_     struct{} `json:"-"`
		word  string
		tiles []int
	}

	// board is an evaluated candidate.
	board struct {
		_          struct{} `json:"-"`
		targets    [][]string
		tiles      []string
		found      []foundWord
		violations []string
		duplicates int
		common     int
		obscure    int
		blocked    int
		weighted   float64
		objective  float64
	}

	generator struct {
		_      struct{} `json:"-"`
		lex    *lexicon
		rng    *rand.Rand
		splits map[string][][]string
		pool   []string
		cfg    searchConfig
	}
)

func newGenerator(lex *lexicon, cfg searchConfig, rng *rand.Rand) *generator {
	g := &generator{lex: lex, cfg: cfg, rng: rng, splits: map[string][][]string{}}

	for _, word := range lex.targets {
		if segs := segmentations([]rune(word), cfg.n, cfg.banned); len(segs) > 0 {
			g.splits[word] = segs
			g.pool = append(g.pool, word)
		}
	}

	return g
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

// search runs cfg.tries independent hill climbs and returns the best board from each,
// best first, with repeated target sets dropped.
func (g *generator) search() []*board {
	// Swapping a target needs at least one pool word not already on the board.
	if len(g.pool) <= g.cfg.targets {
		return nil
	}

	var boards []*board
	seen := map[string]bool{}
	for range g.cfg.tries {
		b := g.climb()
		words := b.targetWords()
		slices.Sort(words)
		key := strings.Join(words, ",")
		if seen[key] {
			continue
		}
		seen[key] = true
		boards = append(boards, b)
	}

	slices.SortFunc(boards, func(a, b *board) int {
		switch {
		case a.objective < b.objective:
			return -1
		case a.objective > b.objective:
			return 1
		default:
			return 0
		}
	})

	return boards
}

func (g *generator) climb() *board {
	current := g.randomCandidate()
	best := g.evaluate(current)

	for range g.cfg.steps {
		next := current.clone()
		i := g.rng.IntN(len(next.words))
		if g.rng.IntN(2) == 0 {
			next.splits[i] = g.rng.IntN(len(g.splits[next.words[i]]))
		} else {
			next.words[i] = g.unusedPoolWord(next.words)
			next.splits[i] = g.rng.IntN(len(g.splits[next.words[i]]))
		}

		if b := g.evaluate(next); b.objective <= best.objective {
			current, best = next, b
		}
	}

	return best
}

func (g *generator) randomCandidate() *candidate {
	c := &candidate{}
	for range g.cfg.targets {
		word := g.unusedPoolWord(c.words)
		c.words = append(c.words, word)
		c.splits = append(c.splits, g.rng.IntN(len(g.splits[word])))
	}
	return c
}

func (g *generator) unusedPoolWord(used []string) string {
	for {
		if word := g.pool[g.rng.IntN(len(g.pool))]; !slices.Contains(used, word) {
			return word
		}
	}
}

func (c *candidate) clone() *candidate {
	return &candidate{words: slices.Clone(c.words), splits: slices.Clone(c.splits)}
}

func (g *generator) evaluate(c *candidate) *board {
	b := &board{}
	tileCounts := map[string]int{}
	for i, word := range c.words {
		split := g.splits[word][c.splits[i]]
		b.targets = append(b.targets, split)
		b.tiles = append(b.tiles, split...)
		for _, tile := range split {
			tileCounts[tile]++
		}
	}
	for _, count := range tileCounts {
		b.duplicates += count - 1
	}

	fullLength := g.enumerate(b)
	for word := range fullLength {
		if !slices.Contains(c.words, word) {
			b.violations = append(b.violations, word)
		}
	}
	slices.Sort(b.violations)

	for i := range b.found {
		word := b.found[i].word
		if g.lex.blocked[word] {
			b.blocked++
			continue
		}
		if count, ok := g.lex.freq[word]; ok {
			b.common++
			b.weighted += math.Log10(float64(count))
		} else {
			b.obscure++
		}
	}

	var outOfRange float64
	switch {
	case b.common < g.cfg.minCommon:
		outOfRange = float64(g.cfg.minCommon - b.common)
	case b.common > g.cfg.maxCommon:
		outOfRange = float64(b.common - g.cfg.maxCommon)
	}
	b.objective = hardPenalty*float64(len(b.violations)+b.duplicates) +
		outOfRange +
		obscurePenalty*float64(b.obscure) +
		blockedPenalty*float64(b.blocked)

	return b
}

// enumerate fills b.found with every word buildable from 1 to n distinct tiles, and
// returns the set of words buildable from exactly n.
func (g *generator) enumerate(b *board) map[string]bool {
	shortest := map[string][]int{}
	fullLength := map[string]bool{}
	used := make([]bool, len(b.tiles))
	var path []int

	var walk func(prefix string)
	walk = func(prefix string) {
		for i, tile := range b.tiles {
			if used[i] {
				continue
			}
			s := prefix + tile
			isWord, isPrefix := g.lex.lookup(s)
			if !isPrefix {
				continue
			}

			used[i] = true
			path = append(path, i)
			if isWord {
				if prev, ok := shortest[s]; !ok || len(path) < len(prev) {
					shortest[s] = slices.Clone(path)
				}
				if len(path) == g.cfg.n {
					fullLength[s] = true
				}
			}
			if len(path) < g.cfg.n {
				walk(s)
			}
			path = path[:len(path)-1]
			used[i] = false
		}
	}
	walk("")

	for word, tiles := range shortest {
		b.found = append(b.found, foundWord{word: word, tiles: tiles})
	}
	slices.SortFunc(b.found, func(x, y foundWord) int {
		if len(x.tiles) != len(y.tiles) {
			return len(x.tiles) - len(y.tiles)
		}
		return strings.Compare(x.word, y.word)
	})

	return fullLength
}

func (b *board) targetWords() []string {
	words := make([]string, 0, len(b.targets))
	for _, split := range b.targets {
		words = append(words, strings.Join(split, ""))
	}
	return words
}
