// Package bank builds the puzzle bank the app ships with and writes it as JSON.
package bank

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"hash/fnv"
	"io"
	"log/slog"
	"math/rand/v2"
	"strings"
	"time"

	"github.com/primandproper/ngrams/generator/internal/lexicon"
	"github.com/primandproper/ngrams/generator/internal/pangram"
	"github.com/primandproper/ngrams/generator/internal/tiles"
	"github.com/primandproper/ngrams/generator/internal/word"
)

const (
	// Version is the bank format version. Bump it on any change the app can't decode.
	Version = 1

	// KindTiles is the tiles game.
	KindTiles = "tiles"
	// KindWord is the word game.
	KindWord = "word"
	// KindPangram is the pangram game.
	KindPangram = "pangram"

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
		_    struct{} `json:"-"`
		Lang string   `json:"lang"`
		Kind string   `json:"kind"`
		// Answer is a word puzzle's folded answer, and Display its accented spelling,
		// present only when it differs.
		Answer  string `json:"answer,omitempty"`
		Display string `json:"display,omitempty"`
		// Letters are a pangram board's letters, sorted, Center among them. Pangrams are
		// the folded spellings of the common pangrams, which a star needs.
		Letters  []string `json:"letters,omitempty"`
		Center   string   `json:"center,omitempty"`
		Pangrams []string `json:"pangrams,omitempty"`
		Tiles    []string `json:"tiles,omitempty"`
		Targets  [][]int  `json:"targets,omitempty"`
		// Blocked holds the folded spellings of offensive words the tiles or letters can
		// build. They score nothing, so they aren't in Words.
		Blocked     []string `json:"blocked,omitempty"`
		Words       []Word   `json:"words,omitempty"`
		N           int      `json:"n"`
		Bonus       int      `json:"bonus,omitempty"`
		TargetScore int      `json:"target_score,omitempty"`
	}

	// Word is a valid word on a tiles or pangram board.
	Word struct {
		_ struct{} `json:"-"`
		// Word is the folded spelling, the tiles joined in order.
		Word string `json:"word"`
		// Display is the accented spelling, present only when it differs from Word.
		Display string `json:"display,omitempty"`
		// Tiles index into a tiles puzzle's tiles, the fewest that build the word.
		Tiles  []int `json:"tiles,omitempty"`
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

	// PangramSize is one pangram board size: N letters, and the range of common words a
	// good board has.
	PangramSize struct {
		_         struct{} `json:"-"`
		N         int
		MinCommon int
		MaxCommon int
	}

	// BuildConfig is everything that shapes a bank.
	BuildConfig struct {
		_      struct{} `json:"-"`
		Start  time.Time
		Logger *slog.Logger
		// Frozen are the first days of an earlier bank, kept as they were because players
		// may already have played them. Only puzzles of the configured languages, kinds, and
		// sizes are kept, and no later puzzle repeats what they used.
		Frozen       []Day
		Languages    []Language
		Sizes        []Size
		WordSizes    []int
		PangramSizes []PangramSize
		Search       tiles.SearchConfig
		WordPool     int
		Days         int
		Seed         uint64
	}
)

// ErrFrozenDays means the frozen days don't fit the bank being built.
var ErrFrozenDays = errors.New("frozen days don't fit the bank")

// Build generates cfg.Days days of puzzles from cfg.Start, for every language, kind, and
// size, after any frozen days. No target or answer repeats within a language. The bank
// depends only on the config and the word data, so the same seed rebuilds the same bank.
// Each kind draws from its own random stream each day, so adding a kind leaves the others'
// puzzles as they were, and freezing days leaves the days after them as they were.
func Build(cfg *BuildConfig) (*Bank, error) {
	logger := cfg.Logger
	if logger == nil {
		logger = slog.New(slog.DiscardHandler)
	}

	if len(cfg.Frozen) > cfg.Days {
		return nil, fmt.Errorf("%w: %d frozen days in a %d-day bank", ErrFrozenDays, len(cfg.Frozen), cfg.Days)
	}
	b := &Bank{Version: Version, Seed: cfg.Seed, Days: make([]Day, cfg.Days)}
	for d := range b.Days {
		b.Days[d].Date = cfg.Start.AddDate(0, 0, d).Format(dateLayout)
		if d < len(cfg.Frozen) && cfg.Frozen[d].Date != b.Days[d].Date {
			return nil, fmt.Errorf("%w: frozen day %d is %s, not %s", ErrFrozenDays, d, cfg.Frozen[d].Date, b.Days[d].Date)
		}
	}

	for _, lang := range cfg.Languages {
		started := time.Now()
		used := keepFrozen(cfg, lang.Code, b)

		generators := make([]*tiles.Generator, len(cfg.Sizes))
		for i, size := range cfg.Sizes {
			search := cfg.Search
			search.N, search.Targets = size.N, size.Targets
			generators[i] = tiles.NewGenerator(lang.Lexicon, &search)
			logger.Info("indexed targets", "lang", lang.Code, "n", size.N, "pool", generators[i].PoolSize())
		}

		for d := len(cfg.Frozen); d < len(b.Days); d++ {
			day := &b.Days[d]
			rng := dayRand(cfg.Seed, lang.Code, day.Date)
			for i, size := range cfg.Sizes {
				board, err := generators[i].Best(rng.Uint64(), used.tiles)
				if err != nil {
					return nil, fmt.Errorf("%s n=%d on %s: %w", lang.Code, size.N, day.Date, err)
				}
				for _, target := range board.Targets {
					used.tiles[target] = true
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

		if err := buildWords(cfg, lang, b, used.words, logger); err != nil {
			return nil, err
		}
		if err := buildPangrams(cfg, lang, b, used.pangrams, logger); err != nil {
			return nil, err
		}

		logger.Info("built language", "lang", lang.Code, "boards", len(b.Days)*len(cfg.Sizes),
			"took", time.Since(started).Round(time.Millisecond))
	}

	return b, nil
}

func buildWords(cfg *BuildConfig, lang Language, b *Bank, used map[string]bool, logger *slog.Logger) error {
	generators := make([]*word.Generator, len(cfg.WordSizes))
	for i, n := range cfg.WordSizes {
		generators[i] = word.NewGenerator(lang.Lexicon, n, cfg.WordPool)
		logger.Info("pooled answers", "lang", lang.Code, "n", n, "pool", generators[i].PoolSize())
	}

	for d := len(cfg.Frozen); d < len(b.Days); d++ {
		day := &b.Days[d]
		rng := dayRand(cfg.Seed, lang.Code+"/"+KindWord, day.Date)
		for i, n := range cfg.WordSizes {
			answer, err := generators[i].Pick(rng, used)
			if err != nil {
				return fmt.Errorf("%s word n=%d on %s: %w", lang.Code, n, day.Date, err)
			}
			used[answer] = true

			p := Puzzle{Lang: lang.Code, Kind: KindWord, N: n, Answer: answer}
			if shown := lang.Lexicon.Display(answer); shown != answer {
				p.Display = shown
			}
			day.Puzzles = append(day.Puzzles, p)
		}
	}

	return nil
}

func buildPangrams(cfg *BuildConfig, lang Language, b *Bank, used map[string]bool, logger *slog.Logger) error {
	generators := make([]*pangram.Generator, len(cfg.PangramSizes))
	for i, size := range cfg.PangramSizes {
		generators[i] = pangram.NewGenerator(lang.Lexicon, size.N, size.MinCommon, size.MaxCommon)
		logger.Info("indexed pangram seeds", "lang", lang.Code, "n", size.N, "pool", generators[i].PoolSize())
	}

	for d := len(cfg.Frozen); d < len(b.Days); d++ {
		day := &b.Days[d]
		rng := dayRand(cfg.Seed, lang.Code+"/"+KindPangram, day.Date)
		for i, size := range cfg.PangramSizes {
			board, err := generators[i].Best(rng, used)
			if err != nil {
				return fmt.Errorf("%s pangram n=%d on %s: %w", lang.Code, size.N, day.Date, err)
			}
			used[pangram.Key(board.Letters)] = true

			day.Puzzles = append(day.Puzzles, pangramPuzzle(lang, size.N, board))
			logger.Debug("built pangram board", "lang", lang.Code, "n", size.N, "date", day.Date,
				"letters", string(board.Letters), "center", string(board.Center), "common", board.Common,
				"words", len(board.Words), "blocked", len(board.Blocked))
		}
	}

	return nil
}

func pangramPuzzle(lang Language, n int, board *pangram.Board) Puzzle {
	p := Puzzle{
		Lang:        lang.Code,
		Kind:        KindPangram,
		N:           n,
		Center:      string(board.Center),
		Blocked:     board.Blocked,
		TargetScore: pangram.TargetScore(board),
	}
	for _, letter := range board.Letters {
		p.Letters = append(p.Letters, string(letter))
	}
	for i := range board.Words {
		found := &board.Words[i]
		if found.Pangram && found.Common {
			p.Pangrams = append(p.Pangrams, found.Word)
		}
		w := Word{Word: found.Word, Points: found.Points}
		if shown := lang.Lexicon.Display(found.Word); shown != found.Word {
			w.Display = shown
		}
		p.Words = append(p.Words, w)
	}
	return p
}

// usedSets are what a language's puzzles have used so far, per kind: tiles targets, word
// answers, and pangram letter sets.
type usedSets struct {
	tiles    map[string]bool
	words    map[string]bool
	pangrams map[string]bool
}

// keepFrozen copies lang's configured puzzles from the frozen days into b and returns
// what they used.
func keepFrozen(cfg *BuildConfig, lang string, b *Bank) usedSets {
	used := usedSets{tiles: map[string]bool{}, words: map[string]bool{}, pangrams: map[string]bool{}}
	configured := map[string]map[int]bool{KindTiles: {}, KindWord: {}, KindPangram: {}}
	for _, size := range cfg.Sizes {
		configured[KindTiles][size.N] = true
	}
	for _, n := range cfg.WordSizes {
		configured[KindWord][n] = true
	}
	for _, size := range cfg.PangramSizes {
		configured[KindPangram][size.N] = true
	}

	for d := range cfg.Frozen {
		for i := range cfg.Frozen[d].Puzzles {
			p := &cfg.Frozen[d].Puzzles[i]
			if p.Lang != lang || !configured[p.Kind][p.N] {
				continue
			}
			b.Days[d].Puzzles = append(b.Days[d].Puzzles, *p)

			switch p.Kind {
			case KindTiles:
				for _, target := range p.Targets {
					var spelled strings.Builder
					for _, tile := range target {
						spelled.WriteString(p.Tiles[tile])
					}
					used.tiles[spelled.String()] = true
				}
			case KindWord:
				used.words[p.Answer] = true
			case KindPangram:
				used.pangrams[pangram.Key([]rune(strings.Join(p.Letters, "")))] = true
			}
		}
	}

	return used
}

// dayRand is one stream's random source for one day, so no day's puzzles depend on how
// much randomness the days before it drew.
func dayRand(seed uint64, stream, date string) *rand.Rand {
	h := fnv.New64a()
	_, _ = h.Write([]byte(stream + "@" + date))   // a hash.Hash never returns an error
	return rand.New(rand.NewPCG(seed, h.Sum64())) //nolint:gosec // banks must be reproducible from a seed, not secret
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
		encodedWord, wordErr := json.Marshal(&p.Words[i])
		if wordErr != nil {
			return fmt.Errorf("encoding word %q: %w", p.Words[i].Word, wordErr)
		}
		buf.WriteString("\n          ")
		buf.Write(encodedWord)
	}
	buf.WriteString("\n        ]}")

	return nil
}
