// Command generate builds the puzzle bank the app ships with.
package main

import (
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/bank"
	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/lexicon"
	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/tiles"
)

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "generate:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	fs := flag.NewFlagSet("generate", flag.ContinueOnError)
	dataDir := fs.String("data", "../data/raw", "directory holding the downloaded source data")
	blocklistDir := fs.String("blocklists", "../data/blocklists", "directory holding <lang>.txt blocklists")
	out := fs.String("out", "../data/bank/puzzles.json", "where to write the bank")
	langs := fs.String("langs", "en,es", "comma-separated languages")
	ns := fs.String("ns", "3,4,5", "comma-separated tiles-per-word sizes")
	start := fs.String("start", "", "first day of the bank, YYYY-MM-DD")
	days := fs.Int("days", 90, "days of puzzles to build")
	seed := fs.Uint64("seed", 1, "random seed; the same seed and data rebuild the same bank")
	tries := fs.Int("tries", 40, "independent hill climbs per board")
	steps := fs.Int("steps", 150, "moves per hill climb")
	minCommon := fs.Int("min-common", 40, "fewest common words a good board has")
	maxCommon := fs.Int("max-common", 80, "most common words a good board has")
	minCount := fs.Int("min-count", 20, "fewest subtitle occurrences for a found word to count as common")
	ban := fs.String("ban", "", "comma-separated fragments never used as tiles")
	review := fs.Bool("print", false, "print every board for review")
	verbose := fs.Bool("v", false, "log every board as it's built")
	if err := fs.Parse(args); err != nil {
		return fmt.Errorf("parsing flags: %w", err)
	}

	level := slog.LevelInfo
	if *verbose {
		level = slog.LevelDebug
	}
	logger := slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: level}))

	startDate, err := time.Parse(time.DateOnly, *start)
	if err != nil {
		return fmt.Errorf("parsing -start %q: %w", *start, err)
	}
	sizes, err := parseInts(*ns)
	if err != nil {
		return err
	}
	banned := map[string]bool{}
	for _, fragment := range splitList(*ban) {
		banned[fragment] = true
	}

	cfg := &bank.BuildConfig{
		Start:  startDate,
		Logger: logger,
		Search: tiles.SearchConfig{
			Banned:    banned,
			MinCommon: *minCommon,
			MaxCommon: *maxCommon,
			Tries:     *tries,
			Steps:     *steps,
		},
		Days: *days,
		Seed: *seed,
	}
	for _, n := range sizes {
		cfg.Sizes = append(cfg.Sizes, bank.Size{N: n, Targets: tiles.TargetsFor(n)})
	}

	lexicons := map[string]*lexicon.Lexicon{}
	for _, lang := range splitList(*langs) {
		loadStarted := time.Now()
		lex, loadErr := lexicon.Load(lang, &lexicon.Config{DataDir: *dataDir, BlocklistDir: *blocklistDir, MinCount: *minCount})
		if loadErr != nil {
			return fmt.Errorf("loading %s: %w", lang, loadErr)
		}
		logger.Info("loaded lexicon", "lang", lang, "words", lex.Size(), "targets", len(lex.Targets()),
			"took", time.Since(loadStarted).Round(time.Millisecond))
		lexicons[lang] = lex
		cfg.Languages = append(cfg.Languages, bank.Language{Code: lang, Lexicon: lex})
	}

	b, err := bank.Build(cfg)
	if err != nil {
		return fmt.Errorf("building bank: %w", err)
	}

	if err = writeBank(*out, b); err != nil {
		return err
	}
	logger.Info("wrote bank", "path", *out, "days", len(b.Days))

	if *review {
		if err = printBank(os.Stdout, b, lexicons); err != nil {
			return fmt.Errorf("printing boards: %w", err)
		}
	}

	return nil
}

// writeBank writes through a temporary file and renames it into place, so a failed run
// never leaves a truncated bank behind.
func writeBank(path string, b *bank.Bank) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o750); err != nil {
		return fmt.Errorf("creating bank directory: %w", err)
	}

	partial := path + ".partial"
	f, err := os.Create(partial)
	if err != nil {
		return fmt.Errorf("creating %s: %w", partial, err)
	}
	if err = bank.Write(f, b); err != nil {
		return errors.Join(err, f.Close(), os.Remove(partial))
	}
	if err = f.Close(); err != nil {
		return fmt.Errorf("closing %s: %w", partial, err)
	}
	if err = os.Rename(partial, path); err != nil {
		return fmt.Errorf("moving bank into place: %w", err)
	}

	return nil
}

func splitList(s string) []string {
	var out []string
	for item := range strings.SplitSeq(s, ",") {
		if item = strings.TrimSpace(item); item != "" {
			out = append(out, item)
		}
	}
	return out
}

func parseInts(s string) ([]int, error) {
	var out []int
	for _, item := range splitList(s) {
		n, err := strconv.Atoi(item)
		if err != nil {
			return nil, fmt.Errorf("parsing size %q: %w", item, err)
		}
		out = append(out, n)
	}
	return out, nil
}
