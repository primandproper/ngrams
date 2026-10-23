package main

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"unicode"
)

// lexicon is one language's word data, all keyed by folded spelling.
type lexicon struct {
	_       struct{}          `json:"-"`
	display map[string]string // folded → spelling shown to the player
	freq    map[string]int    // folded → subtitle count; absent means obscure
	words   []string          // sorted, every valid word
	targets []string          // words fair to use as targets
}

var accentFolds = map[rune]rune{
	'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u',
}

// fold lowercases a word and strips accents, keeping ñ. It reports false for anything
// outside a-z and ñ (hyphens, apostrophes, digits, loanword accents).
func fold(word string) (string, bool) {
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

func loadLexicon(lang, dataDir string) (*lexicon, error) {
	switch lang {
	case "en":
		return loadEnglish(filepath.Join(dataDir, "en"))
	case "es":
		return loadSpanish(filepath.Join(dataDir, "es"))
	default:
		return nil, fmt.Errorf("unsupported language %q", lang)
	}
}

func loadEnglish(dir string) (*lexicon, error) {
	lex := &lexicon{display: map[string]string{}}

	err := eachLine(filepath.Join(dir, "enable1.txt"), func(_ int, line string) error {
		if word, ok := fold(strings.TrimSpace(line)); ok {
			lex.display[word] = word
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	if lex.freq, err = loadFrequencies(filepath.Join(dir, "en_50k.txt"), lex.display); err != nil {
		return nil, err
	}

	for word := range lex.display {
		if _, common := lex.freq[word]; common {
			lex.targets = append(lex.targets, word)
		}
	}
	lex.finish()

	return lex, nil
}

// Mexican Spanish uses neither voseo nor vosotros. es_MX's affix rules already leave
// out vosotros conjugations, but it keeps these voseo imperatives (matate, tené, vení).
// It also keeps r → 0 for -ír verbs, whose output (oí, reí) doubles as the standard
// yo preterite, so that one stays.
var voseoSuffixes = []suffixKey{
	{flag: 'ô', strip: "r", add: "te", condition: "[aei]r"},
	{flag: 'X', strip: "er", add: "é", condition: "er"},
	{flag: 'X', strip: "ir", add: "í", condition: "ir"},
}

// vosotrosStems are vosotros forms es_MX carries as bare stems, by way of RLA-ES's
// irregular conjugation list, found by scanning flagless stems for vosotros endings.
var vosotrosStems = map[string]bool{
	"andéis": true, "balbucisteis": true, "criais": true, "crieis": true, "dad": true,
	"dadle": true, "dadles": true, "dadme": true, "deis": true, "estéis": true,
	"fiais": true, "fieis": true, "friais": true, "guiais": true, "guieis": true,
	"jugaréis": true, "liais": true, "lieis": true, "piais": true, "pieis": true,
	"poded": true, "riais": true, "íd": true,
}

func loadSpanish(dir string) (*lexicon, error) {
	affixes, err := loadAffixes(filepath.Join(dir, "es_MX.aff"))
	if err != nil {
		return nil, err
	}
	if err = affixes.dropSuffixes(voseoSuffixes); err != nil {
		return nil, fmt.Errorf("dropping voseo rules: %w", err)
	}
	entries, err := loadDic(filepath.Join(dir, "es_MX.dic"))
	if err != nil {
		return nil, err
	}

	lex := &lexicon{display: map[string]string{}}
	stems := map[string]struct{}{}
	for i := range entries {
		if vosotrosStems[entries[i].stem] {
			continue
		}
		if stem, ok := fold(entries[i].stem); ok {
			stems[stem] = struct{}{}
		}
		affixes.expand(entries[i].stem, entries[i].flags, func(form string) {
			if word, ok := fold(form); ok {
				if _, seen := lex.display[word]; !seen {
					lex.display[word] = form
				}
			}
		})
	}

	if lex.freq, err = loadFrequencies(filepath.Join(dir, "es_50k.txt"), lex.display); err != nil {
		return nil, err
	}

	for stem := range stems {
		if _, common := lex.freq[stem]; common {
			lex.targets = append(lex.targets, stem)
		}
	}
	lex.finish()

	return lex, nil
}

// loadFrequencies reads a "word count" list, keeping only words already in display.
// Spellings that fold together have their counts summed, and the most common spelling
// becomes the display form.
func loadFrequencies(path string, display map[string]string) (map[string]int, error) {
	freq := map[string]int{}
	best := map[string]int{}

	err := eachLine(path, func(_ int, line string) error {
		spelling, countText, ok := strings.Cut(strings.TrimSpace(line), " ")
		if !ok {
			return nil
		}
		count, convErr := strconv.Atoi(countText)
		if convErr != nil {
			return fmt.Errorf("parsing count in %q: %w", line, convErr)
		}

		word, ok := fold(spelling)
		if !ok {
			return nil
		}
		if _, isValid := display[word]; !isValid {
			return nil
		}

		freq[word] += count
		if count > best[word] {
			best[word] = count
			display[word] = strings.ToLower(spelling)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	return freq, nil
}

func (l *lexicon) finish() {
	l.words = make([]string, 0, len(l.display))
	for word := range l.display {
		l.words = append(l.words, word)
	}
	slices.Sort(l.words)
	slices.Sort(l.targets)
}

// lookup reports whether s is a word, and whether any word starts with s.
func (l *lexicon) lookup(s string) (isWord, isPrefix bool) {
	i := sort.SearchStrings(l.words, s)
	if i == len(l.words) {
		return false, false
	}
	return l.words[i] == s, strings.HasPrefix(l.words[i], s)
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
