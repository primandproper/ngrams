package word

import (
	"math/rand/v2"
	"testing"

	"github.com/primandproper/ngrams/generator/internal/lexicon"

	"github.com/shoenig/test/must"
)

// testLexicon has four-letter answers of descending commonness, a five-letter answer, a
// valid word that isn't an answer, and a blocked one.
func testLexicon() *lexicon.Lexicon {
	display := map[string]string{
		"lamp": "lamp", "tree": "tree", "fern": "fern", "piñon": "piñón", "zarf": "zarf", "shit": "shit",
	}
	freq := map[string]int{"lamp": 300, "tree": 200, "fern": 100, "piñon": 50}
	blocked := map[string]bool{"shit": true}
	return lexicon.New(display, freq, blocked, []string{"fern", "lamp", "piñon", "tree"})
}

func TestNewGenerator(T *testing.T) {
	T.Parallel()

	T.Run("pools the most common answers of the length", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), 4, 2)

		must.Eq(t, []string{"lamp", "tree"}, g.pool)
		must.Eq(t, 2, g.PoolSize())
	})

	T.Run("counts letters rather than bytes", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), 5, 10)

		must.Eq(t, []string{"piñon"}, g.pool)
	})
}

func TestGenerator_Pick(T *testing.T) {
	T.Parallel()

	T.Run("picks an unused answer", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), 4, 10)
		rng := rand.New(rand.NewPCG(1, 2))

		for range 20 {
			answer, err := g.Pick(rng, map[string]bool{"lamp": true, "tree": true})
			must.NoError(t, err)
			must.Eq(t, "fern", answer)
		}
	})

	T.Run("fails once the pool runs out", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), 4, 1)

		_, err := g.Pick(rand.New(rand.NewPCG(1, 2)), map[string]bool{"lamp": true})
		must.ErrorIs(t, err, ErrNoAnswer)
	})
}

func TestGuesses(T *testing.T) {
	T.Parallel()

	T.Run("splits every word of the length into accepted and blocked", func(t *testing.T) {
		t.Parallel()

		accepted, blocked := Guesses(testLexicon(), 4)

		must.Eq(t, []string{"fern", "lamp", "tree", "zarf"}, accepted)
		must.Eq(t, []string{"shit"}, blocked)
	})
}
