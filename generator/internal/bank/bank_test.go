package bank

import (
	"bytes"
	"encoding/json"
	"math/rand/v2"
	"strings"
	"testing"
	"time"

	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/lexicon"
	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/tiles"

	"github.com/shoenig/test/must"
)

// testLanguage has eight four-letter targets that each split only as two 2-letter tiles,
// plus "ab", a one-tile word, "cañon", whose display spelling differs, and "cdab", which is
// blocked.
func testLanguage() Language {
	targets := []string{"abcd", "efgh", "ijkl", "mnop", "qrst", "uvwx", "bdac", "egfh"}
	display := map[string]string{"ab": "ab", "cañon": "cañón", "cdab": "cdab"}
	freq := map[string]int{"ab": 50}
	blocked := map[string]bool{"cdab": true}
	for _, word := range targets {
		display[word] = word
		freq[word] = 100
	}

	return Language{Code: "en", Lexicon: lexicon.New(display, freq, blocked, targets)}
}

func testBuildConfig() *BuildConfig {
	return &BuildConfig{
		Start:     time.Date(2027, 1, 1, 0, 0, 0, 0, time.UTC),
		Languages: []Language{testLanguage()},
		Sizes:     []Size{{N: 2, Targets: 1}, {N: 2, Targets: 2}},
		Search:    tiles.SearchConfig{MinCommon: 1, MaxCommon: 10, Tries: 4, Steps: 10},
		Days:      2,
		Seed:      7,
	}
}

func testRand() *rand.Rand {
	return rand.New(rand.NewPCG(1, 2))
}

func joinTiles(p *Puzzle, indexes []int) string {
	var b strings.Builder
	for _, i := range indexes {
		b.WriteString(p.Tiles[i])
	}
	return b.String()
}

func TestBuild(T *testing.T) {
	T.Parallel()

	T.Run("builds every day, language, and size", func(t *testing.T) {
		t.Parallel()

		b, err := Build(testBuildConfig())
		must.NoError(t, err)

		must.Eq(t, Version, b.Version)
		must.SliceLen(t, 2, b.Days)
		must.Eq(t, "2027-01-01", b.Days[0].Date)
		must.Eq(t, "2027-01-02", b.Days[1].Date)
		for _, day := range b.Days {
			must.SliceLen(t, 2, day.Puzzles)
		}
	})

	T.Run("never repeats a target within a language", func(t *testing.T) {
		t.Parallel()

		b, err := Build(testBuildConfig())
		must.NoError(t, err)

		seen := map[string]bool{}
		for _, day := range b.Days {
			for i := range day.Puzzles {
				p := &day.Puzzles[i]
				for _, target := range p.Targets {
					word := joinTiles(p, target)
					must.False(t, seen[word], must.Sprintf("%s repeated", word))
					seen[word] = true
				}
			}
		}
		must.MapLen(t, 6, seen)
	})

	T.Run("keeps every word and target spelled by its tiles", func(t *testing.T) {
		t.Parallel()

		b, err := Build(testBuildConfig())
		must.NoError(t, err)

		for _, day := range b.Days {
			for i := range day.Puzzles {
				p := &day.Puzzles[i]
				must.Eq(t, KindTiles, p.Kind)
				must.Eq(t, tiles.AllTargetsBonus, p.Bonus)
				for _, w := range p.Words {
					must.Eq(t, w.Word, joinTiles(p, w.Tiles))
					must.Eq(t, tiles.Points(len(w.Tiles)), w.Points)
				}
			}
		}
	})

	T.Run("is deterministic for a seed", func(t *testing.T) {
		t.Parallel()

		first, err := Build(testBuildConfig())
		must.NoError(t, err)
		second, err := Build(testBuildConfig())
		must.NoError(t, err)

		must.Eq(t, first, second)
	})

	T.Run("fails once the target pool runs out", func(t *testing.T) {
		t.Parallel()

		cfg := testBuildConfig()
		cfg.Days = 3

		_, err := Build(cfg)
		must.ErrorIs(t, err, tiles.ErrNoBoard)
	})
}

func TestTilesPuzzle(T *testing.T) {
	T.Parallel()

	T.Run("shows the accented spelling only when it differs", func(t *testing.T) {
		t.Parallel()

		lang := testLanguage()
		board := &tiles.Board{
			Targets: []string{"abcd"},
			Tiles:   []string{"ab", "cd"},
			Found: []tiles.FoundWord{
				{Word: "ab", Tiles: []int{0}},
				{Word: "abcd", Tiles: []int{0, 1}},
				{Word: "cañon", Tiles: []int{1}},
			},
		}

		p := tilesPuzzle(lang, 2, board, testRand())

		must.Eq(t, "", p.Words[0].Display)
		must.Eq(t, "cañón", p.Words[2].Display)
		must.Eq(t, "abcd", joinTiles(&p, p.Targets[0]))
		must.Eq(t, 2+tiles.AllTargetsBonus+20, p.TargetScore)
	})

	T.Run("moves blocked words out of the scoring list", func(t *testing.T) {
		t.Parallel()

		lang := testLanguage()
		board := &tiles.Board{
			Targets: []string{"abcd"},
			Tiles:   []string{"ab", "cd"},
			Found: []tiles.FoundWord{
				{Word: "abcd", Tiles: []int{0, 1}},
				{Word: "cdab", Tiles: []int{1, 0}},
			},
		}

		p := tilesPuzzle(lang, 2, board, testRand())

		must.Eq(t, []string{"cdab"}, p.Blocked)
		must.SliceLen(t, 1, p.Words)
		must.Eq(t, "abcd", p.Words[0].Word)
	})
}

func TestWrite(T *testing.T) {
	T.Parallel()

	T.Run("round-trips through encoding/json", func(t *testing.T) {
		t.Parallel()

		b, err := Build(testBuildConfig())
		must.NoError(t, err)

		var buf bytes.Buffer
		must.NoError(t, Write(&buf, b))

		var decoded Bank
		must.NoError(t, json.Unmarshal(buf.Bytes(), &decoded))
		must.Eq(t, b, &decoded)
	})

	T.Run("puts each word on its own line", func(t *testing.T) {
		t.Parallel()

		b, err := Build(testBuildConfig())
		must.NoError(t, err)

		var buf bytes.Buffer
		must.NoError(t, Write(&buf, b))

		words := 0
		for _, day := range b.Days {
			for i := range day.Puzzles {
				words += len(day.Puzzles[i].Words)
			}
		}
		must.Eq(t, words, strings.Count(buf.String(), `{"word":`))
		for line := range strings.Lines(buf.String()) {
			must.True(t, strings.Count(line, `{"word":`) <= 1, must.Sprintf("line %q", line))
		}
	})

	T.Run("writes a bank with no words", func(t *testing.T) {
		t.Parallel()

		b := &Bank{Version: Version, Days: []Day{{Date: "2027-01-01", Puzzles: []Puzzle{{Lang: "en", Kind: KindTiles, N: 3}}}}}

		var buf bytes.Buffer
		must.NoError(t, Write(&buf, b))

		var decoded Bank
		must.NoError(t, json.Unmarshal(buf.Bytes(), &decoded))
		must.Eq(t, b, &decoded)
	})
}
