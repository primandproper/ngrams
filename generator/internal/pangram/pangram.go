// Package pangram generates pangram boards: n letters, one of them the center, where every
// word of at least four letters uses the center and only board letters, and a pangram uses
// them all.
package pangram

import (
	"errors"
	"math/bits"
	"math/rand/v2"
	"slices"
	"strings"
	"unicode/utf8"

	"github.com/primandproper/ngrams/generator/internal/lexicon"
)

const (
	// MinLength is the shortest word a board accepts.
	MinLength = 4
	// PangramBonus is added to a pangram's points.
	PangramBonus = 7
	// targetPercent is how much of the common words' points the target score asks for.
	targetPercent = 70
	// banned never appears on a board: it would double every board with plurals.
	banned = 's'
)

// ErrNoBoard means no unused letter set yields a board in the common-word range.
var ErrNoBoard = errors.New("no valid board")

type (
	// Word is a valid word on a board.
	Word struct {
		_       struct{} `json:"-"`
		Word    string
		Points  int
		Pangram bool
		Common  bool
	}

	// Board is a letter set and center with every word it accepts.
	Board struct {
		_       struct{} `json:"-"`
		Letters []rune
		Words   []Word
		Blocked []string
		Common  int
		Center  rune
	}

	// Generator searches for boards of one size in one language.
	Generator struct {
		_   struct{} `json:"-"`
		lex *lexicon.Lexicon
		// byMask groups every word a board could accept by the letters it uses.
		byMask    map[uint32][]string
		seeds     []string
		minCommon int
		maxCommon int
	}
)

// CommonRange bounds the common words a good board of n letters has, centered near what a
// typical board of that size reaches.
func CommonRange(n int) (minCommon, maxCommon int) {
	switch n {
	case 6:
		return 20, 45
	case 7:
		return 30, 70
	default:
		return 50, 110
	}
}

// Points is what a word scores: 1 at the minimum length, a point a letter beyond it, and
// the bonus for a pangram.
func Points(word string, pangram bool) int {
	points := utf8.RuneCountInString(word)
	if points == MinLength {
		points = 1
	}
	if pangram {
		points += PangramBonus
	}
	return points
}

// TargetScore is the score a player aims for on b: most of the common words' points, so
// obscure words help but are never needed.
func TargetScore(b *Board) int {
	total := 0
	for i := range b.Words {
		if b.Words[i].Common {
			total += b.Words[i].Points
		}
	}
	return total * targetPercent / 100
}

// NewGenerator indexes every word in lex a board could accept, and the targets with exactly
// n distinct letters that can seed a board.
func NewGenerator(lex *lexicon.Lexicon, n, minCommon, maxCommon int) *Generator {
	g := &Generator{lex: lex, byMask: map[uint32][]string{}, minCommon: minCommon, maxCommon: maxCommon}

	for _, word := range lex.Words() {
		if mask, ok := letterMask(word); ok && utf8.RuneCountInString(word) >= MinLength {
			g.byMask[mask] = append(g.byMask[mask], word)
		}
	}
	for _, word := range lex.Targets() {
		if mask, ok := letterMask(word); ok && bits.OnesCount32(mask) == n {
			g.seeds = append(g.seeds, word)
		}
	}

	return g
}

// PoolSize is how many targets can seed a board.
func (g *Generator) PoolSize() int {
	return len(g.seeds)
}

// Best returns a board whose common words land in range, seeded by a random target whose
// letter set's Key isn't in used. It prefers a board with no blocked words, and settles for
// one with them only when no other board is in range.
func (g *Generator) Best(rng *rand.Rand, used map[string]bool) (*Board, error) {
	var fallback *Board
	tried := map[uint32]bool{}
	for _, i := range rng.Perm(len(g.seeds)) {
		mask, _ := letterMask(g.seeds[i])
		if tried[mask] {
			continue
		}
		tried[mask] = true

		letters := lettersOf(mask)
		if used[Key(letters)] {
			continue
		}
		for _, c := range rng.Perm(len(letters)) {
			b := g.evaluate(mask, letters, letters[c])
			if b.Common < g.minCommon || b.Common > g.maxCommon {
				continue
			}
			if len(b.Blocked) == 0 {
				return b, nil
			}
			if fallback == nil {
				fallback = b
			}
		}
	}
	if fallback == nil {
		return nil, ErrNoBoard
	}
	return fallback, nil
}

// Key identifies a letter set regardless of its center, so no set repeats within a
// language.
func Key(letters []rune) string {
	return string(letters)
}

func (g *Generator) evaluate(mask uint32, letters []rune, center rune) *Board {
	b := &Board{Letters: letters, Center: center}
	centerBit, _ := letterBit(center)
	for sub := mask; sub != 0; sub = (sub - 1) & mask {
		if sub&centerBit == 0 {
			continue
		}
		for _, word := range g.byMask[sub] {
			if g.lex.Blocked(word) {
				b.Blocked = append(b.Blocked, word)
				continue
			}
			_, common := g.lex.Count(word)
			pangram := sub == mask
			b.Words = append(b.Words, Word{Word: word, Points: Points(word, pangram), Pangram: pangram, Common: common})
			if common {
				b.Common++
			}
		}
	}
	slices.SortFunc(b.Words, func(x, y Word) int { return strings.Compare(x.Word, y.Word) })
	slices.Sort(b.Blocked)
	return b
}

// alphabet is every letter a folded word can hold, ñ last.
const alphabet = "abcdefghijklmnopqrstuvwxyzñ"

func letterBit(r rune) (uint32, bool) {
	if r == banned {
		return 0, false
	}
	i := strings.IndexRune(alphabet, r)
	if i < 0 {
		return 0, false
	}
	return 1 << utf8.RuneCountInString(alphabet[:i]), true
}

// letterMask is the set of letters in word, and false if it holds a letter no board uses.
func letterMask(word string) (uint32, bool) {
	var mask uint32
	for _, r := range word {
		bit, ok := letterBit(r)
		if !ok {
			return 0, false
		}
		mask |= bit
	}
	return mask, true
}

func lettersOf(mask uint32) []rune {
	var letters []rune
	for i, r := range []rune(alphabet) {
		if mask&(1<<i) != 0 {
			letters = append(letters, r)
		}
	}
	return letters
}
