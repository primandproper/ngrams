package main

import (
	"cmp"
	"fmt"
	"io"
	"slices"
	"strings"

	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/bank"
	"github.com/verygoodsoftwarenotvirus/ngrams/generator/internal/lexicon"
)

const (
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

func printBank(w io.Writer, b *bank.Bank, lexicons map[string]*lexicon.Lexicon) error {
	out := &reporter{w: w}
	for d := range b.Days {
		day := &b.Days[d]
		for i := range day.Puzzles {
			p := &day.Puzzles[i]
			switch p.Kind {
			case bank.KindWord:
				out.printf("\n==== %s %s word n=%d: %s\n", day.Date, p.Lang, p.N, cmp.Or(p.Display, p.Answer))
			default:
				printPuzzle(out, day.Date, p, lexicons[p.Lang])
			}
		}
	}
	return out.err
}

func printPuzzle(out *reporter, date string, p *bank.Puzzle, lex *lexicon.Lexicon) {
	var common, obscure int
	byTileCount := map[int][]string{}
	fragmentUse := map[string]int{}
	for i := range p.Words {
		w := &p.Words[i]
		label := cmp.Or(w.Display, w.Word)
		if _, isCommon := lex.Count(w.Word); !isCommon {
			label += "*"
			obscure++
		} else {
			common++
		}
		byTileCount[len(w.Tiles)] = append(byTileCount[len(w.Tiles)], label)
		for _, t := range w.Tiles {
			fragmentUse[p.Tiles[t]]++
		}
	}

	out.printf("\n==== %s %s n=%d: %d words (%d common, %d obscure, %d blocked), target score %d\n",
		date, p.Lang, p.N, len(p.Words), common, obscure, len(p.Blocked), p.TargetScore)

	sorted := slices.Clone(p.Tiles)
	slices.Sort(sorted)
	out.printf("tiles: %s\n", strings.Join(sorted, " "))

	out.println("targets:")
	for _, target := range p.Targets {
		split := make([]string, len(target))
		for i, t := range target {
			split[i] = p.Tiles[t]
		}
		word := strings.Join(split, "")
		out.printf("  %-20s %s\n", lex.Display(word), strings.Join(split, " · "))
	}

	out.println("words (* = obscure):")
	for tileCount := 1; tileCount <= p.N; tileCount++ {
		if words := byTileCount[tileCount]; len(words) > 0 {
			printWrapped(out, fmt.Sprintf("  %d tile: ", tileCount), words)
		}
	}
	if len(p.Blocked) > 0 {
		printWrapped(out, "  blocked: ", p.Blocked)
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
