// Package bank builds the puzzle bank the app ships with and writes it as JSON.
package bank

import (
	"bytes"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"io"
	"log/slog"
	"math/rand/v2"
	"time"

	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/lexicon"
	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/tiles"
)

const (
	// Version is the bank format version. Bump it on any change the app can't decode.
	Version = 1

	// KindTiles is the tiles game.
	KindTiles = "tiles"

	dateLayout = time.DateOnly
)

type (
	// Bank is every puzzle the app ships with.
	Bank struct {
		_       struct{} `json:"-"`
		Days    []Day    `json:"days"`
		Seed    uint64   `json:"seed"`
		Version int      `json:"version"`
	}

	// Day is one calendar day's puzzles, in every language, kind, and size.
	Day struct {
		_       struct{} `json:"-"`
		Date    string   `json:"date"`
		Puzzles []Puzzle `json:"puzzles"`
	}

	// Puzzle is one game. Fields past N belong to one kind and are empty for the others.
	Puzzle struct {
		_       struct{} `json:"-"`
		Lang    string   `json:"lang"`
		Kind    string   `json:"kind"`
		Tiles   []string `json:"tiles,omitempty"`
		Targets [][]int  `json:"targets,omitempty"`
		// Blocked holds the folded spellings of offensive words the tiles can build. They
		// score nothing, so they aren't in Words.
		Blocked     []string `json:"blocked,omitempty"`
		Words       []Word   `json:"words,omitempty"`
		N           int      `json:"n"`
		Bonus       int      `json:"bonus,omitempty"`
		TargetScore int      `json:"target_score,omitempty"`
	}

	// Word is a valid word on a tiles board.
	Word struct {
		_ struct{} `json:"-"`
		// Word is the folded spelling, the tiles joined in order.
		Word string `json:"word"`
		// Display is the accented spelling, present only when it differs from Word.
		Display string `json:"display,omitempty"`
		// Tiles index into the puzzle's tiles, the fewest that build the word.
		Tiles  []int `json:"tiles"`
		Points int   `json:"points"`
	}

	// Language is one language's word data.
	Language struct {
		_       struct{} `json:"-"`
		Lexicon *lexicon.Lexicon
		Code    string
	}

	// Size is one tiles board size: N tiles per target and how many targets.
	Size struct {
		_       struct{} `json:"-"`
		N       int
		Targets int
	}

	// BuildConfig is everything that shapes a bank.
	BuildConfig struct {
		_         struct{} `json:"-"`
		Start     time.Time
		Logger    *slog.Logger
		Languages []Language
		Sizes     []Size
		// Search sets every board search's knobs except N and Targets, which come from Sizes.
		Search tiles.SearchConfig
		Days   int
		Seed   uint64
	}
)

// Build generates cfg.Days days of tiles puzzles from cfg.Start, for every language and
// size. No target word repeats within a language. The bank depends only on the config
// and the word data, so the same seed rebuilds the same bank.
func Build(cfg *BuildConfig) (*Bank, error) {
	logger := cfg.Logger
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}

	b := &Bank{Version: Version, Seed: cfg.Seed, Days: make([]Day, cfg.Days)}
	for d := range b.Days {
		b.Days[d].Date = cfg.Start.AddDate(0, 0, d).Format(dateLayout)
	}

	for _, lang := range cfg.Languages {
		started := time.Now()
		rng := rand.New(rand.NewPCG(cfg.Seed, langSeed(lang.Code))) //nolint:gosec // banks must be reproducible from a seed, not secret

		generators := make([]*tiles.Generator, len(cfg.Sizes))
		for i, size := range cfg.Sizes {
			search := cfg.Search
			search.N, search.Targets = size.N, size.Targets
			generators[i] = tiles.NewGenerator(lang.Lexicon, &search)
			logger.Info("indexed targets", "lang", lang.Code, "n", size.N, "pool", generators[i].PoolSize())
		}

		used := map[string]bool{}
		for d := range b.Days {
			day := &b.Days[d]
			for i, size := range cfg.Sizes {
				board, err := generators[i].Best(rng.Uint64(), used)
				if err != nil {
					return nil, fmt.Errorf("%s n=%d on %s: %w", lang.Code, size.N, day.Date, err)
				}
				for _, target := range board.Targets {
					used[target] = true
				}

				day.Puzzles = append(day.Puzzles, tilesPuzzle(lang, size.N, board, rng))
				logger.Debug("built board", "lang", lang.Code, "n", size.N, "date", day.Date,
					"common", board.Common, "obscure", board.Obscure, "blocked", board.Blocked)
				if board.Common < cfg.Search.MinCommon {
					logger.Warn("board below the common-word floor", "lang", lang.Code, "n", size.N,
						"date", day.Date, "common", board.Common)
				}
			}
		}

		logger.Info("built language", "lang", lang.Code, "boards", len(b.Days)*len(cfg.Sizes),
			"took", time.Since(started).Round(time.Millisecond))
	}

	return b, nil
}

func langSeed(code string) uint64 {
	h := fnv.New64a()
	_, _ = h.Write([]byte(code)) // a hash.Hash never returns an error
	return h.Sum64()
}

// tilesPuzzle converts a board, shuffling its tiles so their order gives no target away.
func tilesPuzzle(lang Language, n int, board *tiles.Board, rng *rand.Rand) Puzzle {
	order := rng.Perm(len(board.Tiles))
	position := make([]int, len(order))
	p := Puzzle{
		Lang:        lang.Code,
		Kind:        KindTiles,
		N:           n,
		Tiles:       make([]string, len(order)),
		Bonus:       tiles.AllTargetsBonus,
		TargetScore: tiles.TargetScore(board, n),
	}
	for pos, old := range order {
		p.Tiles[pos] = board.Tiles[old]
		position[old] = pos
	}
	moved := func(old []int) []int {
		out := make([]int, len(old))
		for i, idx := range old {
			out[i] = position[idx]
		}
		return out
	}

	for i := range board.Targets {
		target := make([]int, n)
		for k := range target {
			target[k] = i*n + k
		}
		p.Targets = append(p.Targets, moved(target))
	}

	for i := range board.Found {
		found := &board.Found[i]
		if lang.Lexicon.Blocked(found.Word) {
			p.Blocked = append(p.Blocked, found.Word)
			continue
		}
		w := Word{Word: found.Word, Tiles: moved(found.Tiles), Points: tiles.Points(len(found.Tiles))}
		if shown := lang.Lexicon.Display(found.Word); shown != found.Word {
			w.Display = shown
		}
		p.Words = append(p.Words, w)
	}

	return p
}

// Write encodes b as JSON with one day per block and one word per line, so a regenerated
// bank diffs by eye.
func Write(w io.Writer, b *Bank) error {
	var buf bytes.Buffer
	fmt.Fprintf(&buf, "{\n  \"version\": %d,\n  \"seed\": %d,\n  \"days\": [", b.Version, b.Seed)
	for i := range b.Days {
		day := &b.Days[i]
		if i > 0 {
			buf.WriteString(",")
		}
		date, err := json.Marshal(day.Date)
		if err != nil {
			return fmt.Errorf("encoding date: %w", err)
		}
		fmt.Fprintf(&buf, "\n    {\n      \"date\": %s,\n      \"puzzles\": [", date)
		for j := range day.Puzzles {
			if j > 0 {
				buf.WriteString(",")
			}
			if err = writePuzzle(&buf, &day.Puzzles[j]); err != nil {
				return fmt.Errorf("encoding %s puzzle %d: %w", day.Date, j, err)
			}
		}
		buf.WriteString("\n      ]\n    }")
	}
	buf.WriteString("\n  ]\n}\n")

	if _, err := w.Write(buf.Bytes()); err != nil {
		return fmt.Errorf("writing bank: %w", err)
	}
	return nil
}

func writePuzzle(buf *bytes.Buffer, p *Puzzle) error {
	head := *p
	head.Words = nil
	encoded, err := json.Marshal(&head)
	if err != nil {
		return fmt.Errorf("encoding puzzle: %w", err)
	}

	buf.WriteString("\n        ")
	if len(p.Words) == 0 {
		buf.Write(encoded)
		return nil
	}

	// Reopen the encoded object to append the words, one per line.
	buf.Write(encoded[:len(encoded)-1])
	buf.WriteString(`,"words":[`)
	for i := range p.Words {
		if i > 0 {
			buf.WriteString(",")
		}
		word, wordErr := json.Marshal(&p.Words[i])
		if wordErr != nil {
			return fmt.Errorf("encoding word %q: %w", p.Words[i].Word, wordErr)
		}
		buf.WriteString("\n          ")
		buf.Write(word)
	}
	buf.WriteString("\n        ]}")

	return nil
}
