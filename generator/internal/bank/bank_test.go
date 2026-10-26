package bank

import (
	"bytes"
	"encoding/json"
	"math/rand/v2"
	"strings"
	"testing"
	"time"

	"github.com/primandproper/ngrams/generator/internal/lexicon"
	"github.com/primandproper/ngrams/generator/internal/pangram"
	"github.com/primandproper/ngrams/generator/internal/tiles"
	"github.com/primandproper/ngrams/generator/internal/word"

	"github.com/shoenig/test/must"
)

// testLanguage has eight four-letter targets that each split only as two 2-letter tiles,
// plus "ab", a one-tile word, "cdab", which is blocked, and two five-letter targets:
// "zebra" and "cañon", whose display spelling differs.
func testLanguage() Language {
	targets := []string{"abcd", "efgh", "ijkl", "mnop", "qrst", "uvwx", "bdac", "egfh", "cañon", "zebra"}
	display := map[string]string{"ab": "ab", "cdab": "cdab"}
	freq := map[string]int{"ab": 50}
	blocked := map[string]bool{"cdab": true}
	for _, target := range targets {
		display[target] = target
		freq[target] = 100
	}
	display["cañon"] = "cañón"

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
					spelled := joinTiles(p, target)
					must.False(t, seen[spelled], must.Sprintf("%s repeated", spelled))
					seen[spelled] = true
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
		cfg.Days = 4

		_, err := Build(cfg)
		must.ErrorIs(t, err, tiles.ErrNoBoard)
	})
}

func TestBuild_words(T *testing.T) {
	T.Parallel()

	wordConfig := func() *BuildConfig {
		cfg := testBuildConfig()
		cfg.WordSizes = []int{4, 5}
		cfg.WordPool = 10
		return cfg
	}

	T.Run("adds a word puzzle per size after the tiles boards", func(t *testing.T) {
		t.Parallel()

		b, err := Build(wordConfig())
		must.NoError(t, err)

		for _, day := range b.Days {
			must.SliceLen(t, 4, day.Puzzles)
			must.Eq(t, KindWord, day.Puzzles[2].Kind)
			must.Eq(t, 4, day.Puzzles[2].N)
			must.Eq(t, 5, day.Puzzles[3].N)
		}
	})

	T.Run("never repeats an answer and shows accents only when they differ", func(t *testing.T) {
		t.Parallel()

		b, err := Build(wordConfig())
		must.NoError(t, err)

		seen := map[string]bool{}
		for _, day := range b.Days {
			for _, p := range day.Puzzles[2:] {
				must.False(t, seen[p.Answer], must.Sprintf("%s repeated", p.Answer))
				seen[p.Answer] = true
				if p.Answer == "cañon" {
					must.Eq(t, "cañón", p.Display)
				} else {
					must.Eq(t, "", p.Display)
				}
			}
		}
		must.True(t, seen["cañon"])
	})

	T.Run("leaves the tiles boards as they were", func(t *testing.T) {
		t.Parallel()

		withWords, err := Build(wordConfig())
		must.NoError(t, err)
		without, err := Build(testBuildConfig())
		must.NoError(t, err)

		for d := range without.Days {
			must.Eq(t, without.Days[d].Puzzles, withWords.Days[d].Puzzles[:2])
		}
	})

	T.Run("fails once the answer pool runs out", func(t *testing.T) {
		t.Parallel()

		cfg := wordConfig()
		cfg.Days = 3
		cfg.Sizes = nil
		cfg.WordSizes = []int{5}

		_, err := Build(cfg)
		must.ErrorIs(t, err, word.ErrNoAnswer)
	})
}

func TestBuild_pangrams(T *testing.T) {
	T.Parallel()

	// At 4 letters with exactly 2 common words, only efgh (efgh, egfh) and abcd (abcd,
	// bdac, and the blocked cdab) are in range.
	pangramConfig := func() *BuildConfig {
		cfg := testBuildConfig()
		cfg.PangramSizes = []PangramSize{{N: 4, MinCommon: 2, MaxCommon: 2}}
		return cfg
	}

	T.Run("prefers clean boards and never repeats a letter set", func(t *testing.T) {
		t.Parallel()

		b, err := Build(pangramConfig())
		must.NoError(t, err)

		first, second := b.Days[0].Puzzles[2], b.Days[1].Puzzles[2]
		must.Eq(t, KindPangram, first.Kind)
		must.Eq(t, []string{"e", "f", "g", "h"}, first.Letters)
		must.SliceEmpty(t, first.Blocked)
		must.Eq(t, []string{"a", "b", "c", "d"}, second.Letters)
		must.Eq(t, []string{"cdab"}, second.Blocked)
	})

	T.Run("lists every word with its points and the pangrams a star needs", func(t *testing.T) {
		t.Parallel()

		b, err := Build(pangramConfig())
		must.NoError(t, err)

		p := b.Days[0].Puzzles[2]
		must.Eq(t, []string{"efgh", "egfh"}, p.Pangrams)
		must.SliceLen(t, 2, p.Words)
		for _, w := range p.Words {
			must.Eq(t, 1+pangram.PangramBonus, w.Points)
			must.StrContains(t, w.Word, p.Center)
		}
		must.Eq(t, 2*(1+pangram.PangramBonus)*70/100, p.TargetScore)
	})

	T.Run("leaves the tiles boards as they were", func(t *testing.T) {
		t.Parallel()

		withPangrams, err := Build(pangramConfig())
		must.NoError(t, err)
		without, err := Build(testBuildConfig())
		must.NoError(t, err)

		for d := range without.Days {
			must.Eq(t, without.Days[d].Puzzles, withPangrams.Days[d].Puzzles[:2])
		}
	})

	T.Run("fails once the letter sets run out", func(t *testing.T) {
		t.Parallel()

		cfg := pangramConfig()
		cfg.Days = 3
		cfg.Sizes = nil

		_, err := Build(cfg)
		must.ErrorIs(t, err, pangram.ErrNoBoard)
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
