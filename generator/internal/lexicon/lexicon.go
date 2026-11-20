// Package lexicon loads one language's word data: every valid word, how common each is,
// which are blocked or excluded, which blocked words a player can unlock, and which are fair
// to use as targets and answers.
package lexicon

import (
	"fmt"
	"maps"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// targetRank is how far down its frequency list a word can sit and still be a target.
// It matches the 50k lists the prototype started with, so a longer list changes only
// which found words count as common.
const targetRank = 50000

type (
	// Lexicon is one language's word data, all keyed by folded spelling.
	Lexicon struct {
		_       struct{}          `json:"-"`
		display map[string]string // folded → spelling shown to the player
		freq    map[string]int    // folded → subtitle count; absent means obscure
		blocked map[string]bool   // valid, but never a target, and boards avoid them
		profane map[string]bool   // blocked words a player can turn on: swearing, not slurs
		words   []string          // sorted, every valid word
		targets []string          // sorted, words fair to use as targets
		answers []string          // sorted, targets in base form, fair to use as word answers
	}

	// Config says where a language's data lives and how to judge commonness.
	Config struct {
		_            struct{} `json:"-"`
		DataDir      string
		BlocklistDir string
		// ExclusionDir holds <lang>.txt lists of real words that are never targets or answers:
		// names and foreign words the frequency list counts as common.
		ExclusionDir string
		// MinCount is the fewest subtitle occurrences for a word to count as common.
		MinCount int
	}
)

// New builds a lexicon from folded words. display maps every valid word to the spelling
// shown to the player, freq holds the common words' counts, profane words must be blocked,
// and targets must be valid words. Every target is also an answer.
func New(display map[string]string, freq map[string]int, blocked, profane map[string]bool, targets []string) *Lexicon {
	l := &Lexicon{
		display: display,
		freq:    freq,
		blocked: blocked,
		profane: profane,
		words:   slices.Sorted(maps.Keys(display)),
		targets: slices.Clone(targets),
	}
	slices.Sort(l.targets)
	l.answers = l.targets

	return l
}

// Load reads a supported language's dictionary, frequency list, blocklists, and exclusions.
// BlocklistDir holds two lists per language: <lang>.txt, words blocked for everyone, and
// <lang>-profanity.txt, words blocked until a player turns curse words on.
func Load(lang string, cfg *Config) (*Lexicon, error) {
	blocked, err := loadWordList(filepath.Join(cfg.BlocklistDir, lang+".txt"))
	if err != nil {
		return nil, err
	}
	profane, err := loadWordList(filepath.Join(cfg.BlocklistDir, lang+"-profanity.txt"))
	if err != nil {
		return nil, err
	}
	excluded, err := loadWordList(filepath.Join(cfg.ExclusionDir, lang+".txt"))
	if err != nil {
		return nil, err
	}

	switch lang {
	case "en":
		return loadEnglish(filepath.Join(cfg.DataDir, "en"), cfg.MinCount, blocked, profane, excluded)
	case "es":
		return loadSpanish(filepath.Join(cfg.DataDir, "es"), cfg.MinCount, blocked, profane, excluded)
	default:
		return nil, fmt.Errorf("unsupported language %q", lang)
	}
}

// Display returns the spelling shown to the player for a folded word.
func (l *Lexicon) Display(word string) string {
	if shown, ok := l.display[word]; ok {
		return shown
	}
	return word
}

// Count returns a word's subtitle count, and false if the word isn't common.
func (l *Lexicon) Count(word string) (int, bool) {
	count, ok := l.freq[word]
	return count, ok
}

// Blocked reports whether a word is valid but offensive.
func (l *Lexicon) Blocked(word string) bool {
	return l.blocked[word]
}

// Profane reports whether a blocked word is one a player can turn on.
func (l *Lexicon) Profane(word string) bool {
	return l.profane[word]
}

// Size is the number of valid words.
func (l *Lexicon) Size() int {
	return len(l.words)
}

// Targets returns the words fair to use as targets, sorted. Callers must not modify it.
func (l *Lexicon) Targets() []string {
	return l.targets
}

// Answers returns the targets in base form, sorted. Callers must not modify it.
func (l *Lexicon) Answers() []string {
	return l.answers
}

// Words returns every valid word, sorted. Callers must not modify it.
func (l *Lexicon) Words() []string {
	return l.words
}

// Lookup reports whether s is a word, and whether any word starts with s.
func (l *Lexicon) Lookup(s string) (isWord, isPrefix bool) {
	i := sort.SearchStrings(l.words, s)
	if i == len(l.words) {
		return false, false
	}
	return l.words[i] == s, strings.HasPrefix(l.words[i], s)
}

var accentFolds = map[rune]rune{
	'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
}

// Fold lowercases a word and strips accents, keeping ñ. It reports false for anything
// outside a-z and ñ (hyphens, apostrophes, digits, loanword accents).
func Fold(word string) (string, bool) {
	var b strings.Builder
	for _, r := range word {
		r = unicode.ToLower(r)
		if plain, ok := accentFolds[r]; ok {
			r = plain
		}
		if (r < 'a' || r > 'z') && r != 'ñ' {
			return "", false
		}
		b.WriteRune(r)
	}
	return b.String(), b.Len() > 0
}

// loadWordList reads one word per line, ignoring blank lines and # comments.
func loadWordList(path string) (map[string]bool, error) {
	words := map[string]bool{}
	err := eachLine(path, func(lineNum int, line string) error {
		entry, _, _ := strings.Cut(line, "#")
		if entry = strings.TrimSpace(entry); entry == "" {
			return nil
		}
		word, ok := Fold(entry)
		if !ok {
			return fmt.Errorf("line %d: %q isn't a plain word", lineNum, entry)
		}
		words[word] = true
		return nil
	})
	if err != nil {
		return nil, err
	}
	return words, nil
}

// loadEnglish reads ENABLE and its frequency list. A word on both blocklists stays blocked
// for everyone.
func loadEnglish(dir string, minCount int, never, profane, excluded map[string]bool) (*Lexicon, error) {
	blocked := maps.Clone(never)
	unlockable := map[string]bool{}
	for word := range profane {
		blocked[word] = true
		if !never[word] {
			unlockable[word] = true
		}
	}

	display := map[string]string{}
	err := eachLine(filepath.Join(dir, "enable1.txt"), func(_ int, line string) error {
		if word, ok := Fold(strings.TrimSpace(line)); ok {
			display[word] = word
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	freq, top, err := loadFrequencies(filepath.Join(dir, "en_50k.txt"), display, minCount)
	if err != nil {
		return nil, err
	}

	var targets []string
	for word := range display {
		if top[word] && !blocked[word] && !excluded[word] {
			targets = append(targets, word)
		}
	}

	lex := New(display, freq, blocked, unlockable, targets)
	lex.answers = slices.DeleteFunc(slices.Clone(lex.targets), func(word string) bool {
		return englishInflection(word, display)
	})
	return lex, nil
}

// englishInflection reports whether word looks like a plural or past tense of another
// word: a stem plus "s", "ed", or "d". ENABLE carries no lemmas, so this guesses, and it
// drops some base forms (need, from nee) along with the inflections. Words ending in
// "ss" are never plurals.
func englishInflection(word string, display map[string]string) bool {
	isWord := func(stem string) bool {
		_, ok := display[stem]
		return len(stem) >= 2 && ok
	}

	switch {
	case strings.HasSuffix(word, "ss"):
		return false
	case strings.HasSuffix(word, "s"):
		return isWord(strings.TrimSuffix(word, "s"))
	case strings.HasSuffix(word, "ed"):
		return isWord(strings.TrimSuffix(word, "ed")) || isWord(strings.TrimSuffix(word, "d"))
	default:
		return false
	}
}

// loadFrequencies reads a "word count" list, most common first, keeping only words
// already in display. Spellings that fold together have their counts summed, and the
// most common spelling becomes the display form. It returns the words counted at least
// minCount times, and the set ranked within targetRank.
func loadFrequencies(path string, display map[string]string, minCount int) (freq map[string]int, top map[string]bool, err error) {
	freq = map[string]int{}
	top = map[string]bool{}
	best := map[string]int{}

	err = eachLine(path, func(lineNum int, line string) error {
		spelling, countText, ok := strings.Cut(strings.TrimSpace(line), " ")
		if !ok {
			return nil
		}
		count, convErr := strconv.Atoi(countText)
		if convErr != nil {
			return fmt.Errorf("parsing count in %q: %w", line, convErr)
		}

		word, ok := Fold(spelling)
		if !ok {
			return nil
		}
		if _, isValid := display[word]; !isValid {
			return nil
		}

		freq[word] += count
		if lineNum <= targetRank {
			top[word] = true
		}
		if count > best[word] {
			best[word] = count
			display[word] = strings.ToLower(spelling)
		}
		return nil
	})
	if err != nil {
		return nil, nil, err
	}

	maps.DeleteFunc(freq, func(_ string, count int) bool { return count < minCount })

	return freq, top, nil
}

// eachLine calls fn with every line of a file and its 1-based line number. Source files
// are a few MB at most, so reading them whole is simpler than streaming.
func eachLine(path string, fn func(lineNum int, line string) error) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("reading %s: %w", path, err)
	}

	lineNum := 0
	for line := range strings.Lines(string(data)) {
		lineNum++
		if err = fn(lineNum, strings.TrimRight(line, "\r\n")); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
	}

	return nil
}
