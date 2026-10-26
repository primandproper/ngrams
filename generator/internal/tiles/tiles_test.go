package tiles

import (
	"testing"

	"github.com/primandproper/ngrams/generator/internal/lexicon"

	"github.com/shoenig/test/must"
)

// testLexicon has five four-letter targets that each split only as two 2-letter tiles,
// plus "ab", a one-tile word, and "abgh", which forms a full-length non-target whenever
// abcd and efgh share a board.
func testLexicon() *lexicon.Lexicon {
	words := []string{"abcd", "efgh", "ijkl", "mnop", "qrst", "ab", "abgh"}
	display := map[string]string{}
	freq := map[string]int{}
	for _, word := range words {
		display[word] = word
		freq[word] = 100
	}

	return lexicon.New(display, freq, nil, []string{"abcd", "efgh", "ijkl", "mnop", "qrst"})
}

func testConfig() *SearchConfig {
	return &SearchConfig{N: 2, Targets: 2, MinCommon: 1, MaxCommon: 10, Tries: 8, Steps: 20}
}

func TestTargetsFor(T *testing.T) {
	T.Parallel()

	T.Run("keeps boards near 20 tiles", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, 7, TargetsFor(3))
		must.Eq(t, 5, TargetsFor(4))
		must.Eq(t, 4, TargetsFor(5))
	})
}

func TestTargetScore(T *testing.T) {
	T.Parallel()

	T.Run("reproduces the original's 100 at n=4", func(t *testing.T) {
		t.Parallel()

		b := &Board{Targets: make([]string, 5)}
		must.Eq(t, 100, TargetScore(b, 4))
	})

	T.Run("scales with n", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, 88, TargetScore(&Board{Targets: make([]string, 7)}, 3))
		must.Eq(t, 124, TargetScore(&Board{Targets: make([]string, 4)}, 5))
	})
}

func TestPoints(T *testing.T) {
	T.Parallel()

	T.Run("doubles with each tile", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, []int{1, 2, 4, 8, 16}, []int{Points(1), Points(2), Points(3), Points(4), Points(5)})
	})
}

func TestSegmentations(T *testing.T) {
	T.Parallel()

	T.Run("cuts into every allowed shape", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, [][]string{
			{"st", "aple"},
			{"sta", "ple"},
			{"stap", "le"},
		}, segmentations([]rune("staple"), 2, nil))
	})

	T.Run("skips banned fragments", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, [][]string{{"sta", "ple"}}, segmentations([]rune("staple"), 2, map[string]bool{"st": true, "le": true}))
	})

	T.Run("counts runes, not bytes", func(t *testing.T) {
		t.Parallel()

		must.Eq(t, [][]string{{"ni", "ño"}}, segmentations([]rune("niño"), 2, nil))
	})

	T.Run("finds nothing when the word is too short", func(t *testing.T) {
		t.Parallel()

		must.SliceEmpty(t, segmentations([]rune("cat"), 2, nil))
	})
}

func TestGenerator_evaluate(T *testing.T) {
	T.Parallel()

	T.Run("finds every buildable word", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), testConfig())
		b := g.evaluate(&candidate{words: []string{"abcd", "ijkl"}, splits: []int{0, 0}})

		must.Eq(t, []string{"ab", "cd", "ij", "kl"}, b.Tiles)
		must.Eq(t, []FoundWord{
			{Word: "ab", Tiles: []int{0}},
			{Word: "abcd", Tiles: []int{0, 1}},
			{Word: "ijkl", Tiles: []int{2, 3}},
		}, b.Found)
		must.True(t, b.valid())
		must.Eq(t, 3, b.Common)
	})

	T.Run("flags full-length words that aren't targets", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), testConfig())
		b := g.evaluate(&candidate{words: []string{"abcd", "efgh"}, splits: []int{0, 0}})

		must.Eq(t, []string{"abgh"}, b.Violations)
		must.False(t, b.valid())
	})
}

func TestGenerator_Best(T *testing.T) {
	T.Parallel()

	T.Run("returns a valid board avoiding excluded targets", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), testConfig())
		b, err := g.Best(7, map[string]bool{"ijkl": true})
		must.NoError(t, err)

		must.True(t, b.valid())
		must.SliceLen(t, 2, b.Targets)
		must.SliceNotContains(t, b.Targets, "ijkl")
	})

	T.Run("is deterministic for a seed", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), testConfig())
		first, err := g.Best(7, nil)
		must.NoError(t, err)
		second, err := g.Best(7, nil)
		must.NoError(t, err)

		must.Eq(t, first.Targets, second.Targets)
	})

	T.Run("fails once too few targets are left", func(t *testing.T) {
		t.Parallel()

		g := NewGenerator(testLexicon(), testConfig())
		_, err := g.Best(7, map[string]bool{"abcd": true, "efgh": true, "ijkl": true})
		must.ErrorIs(t, err, ErrNoBoard)
	})
}
