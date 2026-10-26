package pangram

import (
	"math/rand/v2"
	"testing"

	"github.com/primandproper/ngrams/generator/internal/lexicon"

	"github.com/shoenig/test/must"
)

// testLexicon's only seed is "plaice", whose letters build "plaice", "place", and "pail"
// (common), "pace" and "lace" (obscure), and "pals", which its s rules out. Centers p, a,
// and l each keep all three common words.
func testLexicon(blocked ...string) *lexicon.Lexicon {
	display := map[string]string{}
	for _, word := range []string{"plaice", "place", "pace", "lace", "pail", "pals", "ice"} {
		display[word] = word
	}
	freq := map[string]int{"plaice": 100, "place": 500, "pail": 50, "pals": 90}
	isBlocked := map[string]bool{}
	for _, word := range blocked {
		isBlocked[word] = true
	}
	return lexicon.New(display, freq, isBlocked, []string{"plaice", "place", "pals"})
}

func testRand() *rand.Rand {
	return rand.New(rand.NewPCG(1, 2))
}

func TestGenerator_Best(T *testing.T) {
	T.Parallel()

	T.Run("finds a board in range with every word using the center", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), 6, 3, 3)
		must.Eq(t, 1, g.PoolSize())

		b, err := g.Best(testRand(), map[string]bool{})
		must.NoError(t, err)

		must.Eq(t, []rune("aceilp"), b.Letters)
		must.Eq(t, 3, b.Common)
		must.SliceContains(t, []rune("pal"), b.Center)
		for _, w := range b.Words {
			must.StrContains(t, w.Word, string(b.Center))
		}
		must.SliceContainsSubset(t, words(b), []string{"pail", "place", "plaice"})
		must.SliceNotContains(t, words(b), "pals")
	})

	T.Run("scores words and marks pangrams", func(t *testing.T) {
		t.Parallel()

		b, err := NewGenerator(testLexicon(), 6, 3, 3).Best(testRand(), map[string]bool{})
		must.NoError(t, err)

		byWord := map[string]Word{}
		for _, w := range b.Words {
			byWord[w.Word] = w
		}
		must.True(t, byWord["plaice"].Pangram)
		must.Eq(t, 6+PangramBonus, byWord["plaice"].Points)
		must.False(t, byWord["place"].Pangram)
		must.Eq(t, 1, byWord["pail"].Points)
		must.False(t, byWord["pace"].Common)
		must.Eq(t, (13+5+1)*70/100, TargetScore(b))
	})

	T.Run("prefers a board without blocked words", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon("lace"), 6, 2, 4)
		for seed := range uint64(20) {
			b, err := g.Best(rand.New(rand.NewPCG(seed, 2)), map[string]bool{})
			must.NoError(t, err)
			must.SliceEmpty(t, b.Blocked, must.Sprintf("center %c", b.Center))
		}
	})

	T.Run("settles for blocked words when nothing else is in range", func(t *testing.T) {
		t.Parallel()

		b, err := NewGenerator(testLexicon("plaice"), 6, 2, 2).Best(testRand(), map[string]bool{})
		must.NoError(t, err)

		must.Eq(t, []string{"plaice"}, b.Blocked)
		must.SliceNotContains(t, words(b), "plaice")
	})

	T.Run("skips used letter sets", func(t *testing.T) {
		t.Parallel()

		_, err := NewGenerator(testLexicon(), 6, 3, 3).Best(testRand(), map[string]bool{Key([]rune("aceilp")): true})
		must.ErrorIs(t, err, ErrNoBoard)
	})

	T.Run("fails when no center lands in range", func(t *testing.T) {
		t.Parallel()

		_, err := NewGenerator(testLexicon(), 6, 10, 20).Best(testRand(), map[string]bool{})
		must.ErrorIs(t, err, ErrNoBoard)
	})
}

func TestPoints(T *testing.T) {
	T.Parallel()

	T.Run("scores a point a letter past the minimum", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, 1, Points("pace", false))
		must.Eq(t, 5, Points("place", false))
		must.Eq(t, 5+PangramBonus, Points("cañon", true))
	})
}

func words(b *Board) []string {
	out := make([]string, len(b.Words))
	for i := range b.Words {
		out[i] = b.Words[i].Word
	}
	return out
}
