// Command tiles-prototype is a throwaway generator for tiles boards. It exists to answer
// whether generated boards are fun in English and Spanish, and which scheme and
// scoring rules make them so. Delete it once the real generator absorbs the answers.
package main

import (
	"cmp"
	"flag"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"slices"
	"strconv"
	"strings"
	"time"
)

const (
	schemeFixed5 = "fixed5"
	schemeNear20 = "near20"

	topFragments = 8
	wrapWidth    = 100
)

// reporter writes the review output and keeps the first write error, so printing code
// doesn't check after every line.
type reporter struct {
	_   struct{} `json:"-"`
	w   io.Writer
	err error
}

func (r *reporter) printf(format string, args ...any) {
	if r.err == nil {
		_, r.err = fmt.Fprintf(r.w, format, args...)
	}
}

func (r *reporter) println(args ...any) {
	if r.err == nil {
		_, r.err = fmt.Fprintln(r.w, args...)
	}
}

func main() {
	out := &reporter{w: os.Stdout}
	err := run(os.Args[1:], out)
	if err == nil && out.err != nil {
		err = fmt.Errorf("writing output: %w", out.err)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "tiles-prototype:", err)
		os.Exit(1)
	}
}

func run(args []string, out *reporter) error {
	fs := flag.NewFlagSet("tiles-prototype", flag.ContinueOnError)
	dataDir := fs.String("data", "../data/raw", "directory holding the downloaded source data")
	blocklistDir := fs.String("blocklists", "../data/blocklists", "directory holding <lang>.txt blocklists")
	langs := fs.String("langs", "en,es", "comma-separated languages")
	ns := fs.String("ns", "3,4,5", "comma-separated tiles-per-word sizes")
	schemes := fs.String("schemes", schemeFixed5+","+schemeNear20, "comma-separated board-size schemes")
	count := fs.Int("count", 3, "boards to print per (lang, n, scheme)")
	tries := fs.Int("tries", 40, "independent hill climbs per (lang, n, scheme)")
	steps := fs.Int("steps", 150, "moves per hill climb")
	minCommon := fs.Int("min-common", 30, "fewest common words a good board has")
	maxCommon := fs.Int("max-common", 80, "most common words a good board has")
	minCount := fs.Int("min-count", 20, "fewest subtitle occurrences for a found word to count as common")
	ban := fs.String("ban", "", "comma-separated fragments never used as tiles")
	seed := fs.Uint64("seed", 0, "random seed; 0 picks one and prints it")
	if err := fs.Parse(args); err != nil {
		return fmt.Errorf("parsing flags: %w", err)
	}

	sizes, err := parseInts(*ns)
	if err != nil {
		return err
	}
	banned := map[string]bool{}
	for _, fragment := range splitList(*ban) {
		banned[fragment] = true
	}
	if *seed == 0 {
		*seed = uint64(time.Now().UnixNano())
	}
	out.printf("seed %d\n", *seed)

	for _, lang := range splitList(*langs) {
		started := time.Now()
		lex, loadErr := loadLexicon(lang, &lexiconConfig{dataDir: *dataDir, blocklistDir: *blocklistDir, minCount: *minCount})
		if loadErr != nil {
			return fmt.Errorf("loading %s: %w", lang, loadErr)
		}
		out.printf("\n######## %s: %d valid words, %d target candidates, loaded in %s\n",
			lang, len(lex.words), len(lex.targets), time.Since(started).Round(time.Millisecond))

		for _, n := range sizes {
			searched := map[int]string{}
			for _, scheme := range splitList(*schemes) {
				targets, schemeErr := targetsFor(scheme, n)
				if schemeErr != nil {
					return schemeErr
				}
				if same, ok := searched[targets]; ok {
					out.printf("\n==== %s n=%d %s: same %d targets as %s, skipped\n", lang, n, scheme, targets, same)
					continue
				}
				searched[targets] = scheme

				cfg := searchConfig{
					banned:    banned,
					n:         n,
					targets:   targets,
					minCommon: *minCommon,
					maxCommon: *maxCommon,
					tries:     *tries,
					steps:     *steps,
				}
				rng := rand.New(rand.NewPCG(*seed, uint64(n))) //nolint:gosec // boards must be reproducible from a seed, not secret
				g := newGenerator(lex, cfg, rng)

				started = time.Now()
				boards := g.search()
				out.printf("\n==== %s n=%d %s: %d targets, %d tiles, pool of %d words, searched in %s\n",
					lang, n, scheme, targets, targets*n, len(g.pool), time.Since(started).Round(time.Millisecond))
				if len(boards) == 0 {
					out.println("no boards: target pool too small")
					continue
				}
				for i, b := range boards[:min(*count, len(boards))] {
					printBoard(out, lex, b, i+1)
				}
			}
		}
	}

	return nil
}

func targetsFor(scheme string, n int) (int, error) {
	switch scheme {
	case schemeFixed5:
		return 5, nil
	case schemeNear20:
		return (20 + n/2) / n, nil
	default:
		return 0, fmt.Errorf("unknown scheme %q", scheme)
	}
}

func printBoard(out *reporter, lex *lexicon, b *board, rank int) {
	out.printf("\n--- board %d: objective %.2f, %d words (%d common, %d obscure, %d blocked), weighted %.1f\n",
		rank, b.objective, len(b.found), b.common, b.obscure, b.blocked, b.weighted)
	if len(b.violations) > 0 || b.duplicates > 0 {
		out.printf("INVALID: %d duplicate tiles, extra full-length words: %s\n",
			b.duplicates, strings.Join(b.violations, " "))
	}

	tiles := slices.Clone(b.tiles)
	slices.Sort(tiles)
	out.printf("tiles: %s\n", strings.Join(tiles, " "))

	out.println("targets:")
	for _, split := range b.targets {
		word := strings.Join(split, "")
		out.printf("  %-20s %s\n", lex.display[word], strings.Join(split, " · "))
	}

	byTileCount := map[int][]string{}
	fragmentUse := map[string]int{}
	for j := range b.found {
		f := &b.found[j]
		label := lex.display[f.word]
		if _, common := lex.freq[f.word]; lex.blocked[f.word] {
			label += "!"
		} else if !common {
			label += "*"
		}
		byTileCount[len(f.tiles)] = append(byTileCount[len(f.tiles)], label)
		for _, i := range f.tiles {
			fragmentUse[b.tiles[i]]++
		}
	}
	out.println("words (* = obscure, ! = blocked):")
	for tileCount := 1; tileCount <= len(b.targets[0]); tileCount++ {
		if words := byTileCount[tileCount]; len(words) > 0 {
			printWrapped(out, fmt.Sprintf("  %d tile: ", tileCount), words)
		}
	}

	fragments := make([]string, 0, len(fragmentUse))
	for fragment := range fragmentUse {
		fragments = append(fragments, fragment)
	}
	slices.SortFunc(fragments, func(x, y string) int {
		return cmp.Or(fragmentUse[y]-fragmentUse[x], strings.Compare(x, y))
	})
	busiest := make([]string, 0, topFragments)
	for _, fragment := range fragments[:min(topFragments, len(fragments))] {
		busiest = append(busiest, fmt.Sprintf("%s(%d)", fragment, fragmentUse[fragment]))
	}
	out.printf("busiest tiles: %s\n", strings.Join(busiest, " "))
}

func printWrapped(out *reporter, lead string, words []string) {
	line := lead
	indent := strings.Repeat(" ", len(lead))
	for _, word := range words {
		if len(line)+len(word) > wrapWidth && line != lead && line != indent {
			out.println(line)
			line = indent
		}
		line += word + " "
	}
	out.println(line)
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
