// Package word picks the answers for word puzzles and lists the guesses each length
// accepts.
package word

import (
	"cmp"
	"errors"
	"math/rand/v2"
	"slices"
	"unicode/utf8"

	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/lexicon"
)

// ErrNoAnswer means every answer in the pool has been used.
var ErrNoAnswer = errors.New("no unused answer")

// Generator picks answers of one length in one language.
type Generator struct {
	_    struct{} `json:"-"`
	pool []string
}

// NewGenerator pools the poolSize most common answers of n letters in lex.
func NewGenerator(lex *lexicon.Lexicon, n, poolSize int) *Generator {
	var pool []string
	for _, answer := range lex.Answers() {
		if utf8.RuneCountInString(answer) == n {
			pool = append(pool, answer)
		}
	}

	count := func(word string) int {
		c, _ := lex.Count(word)
		return c
	}
	slices.SortStableFunc(pool, func(a, b string) int {
		return cmp.Compare(count(b), count(a))
	})

	return &Generator{pool: pool[:min(poolSize, len(pool))]}
}

// PoolSize is how many answers the generator picks from.
func (g *Generator) PoolSize() int {
	return len(g.pool)
}

// Pick returns a random answer not in used.
func (g *Generator) Pick(rng *rand.Rand, used map[string]bool) (string, error) {
	var unused []string
	for _, answer := range g.pool {
		if !used[answer] {
			unused = append(unused, answer)
		}
	}
	if len(unused) == 0 {
		return "", ErrNoAnswer
	}
	return unused[rng.IntN(len(unused))], nil
}

// Guesses returns every valid word of n letters, sorted, split into the ones a guess may
// be and the blocked ones, which the app answers apart from words it doesn't know.
func Guesses(lex *lexicon.Lexicon, n int) (accepted, blocked []string) {
	for _, word := range lex.Words() {
		if utf8.RuneCountInString(word) != n {
			continue
		}
		if lex.Blocked(word) {
			blocked = append(blocked, word)
		} else {
			accepted = append(accepted, word)
		}
	}
	return accepted, blocked
}
