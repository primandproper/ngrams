// Package hunspell reads Hunspell .aff and .dic files and expands stems into every form
// their affix flags generate. Only the subset of the format that es_MX uses is supported:
// FLAG UTF-8, cross products, and continuation classes on affixes.
package hunspell

import (
	"fmt"
	"io"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"
)

const (
	prefixKind = "PFX"
	suffixKind = "SFX"

	// maxContinuationDepth bounds chained affixes (canción → cancionero → cancioneros).
	maxContinuationDepth = 2
)

type (
	// affixRule is one PFX or SFX line from a Hunspell .aff file.
	affixRule struct {
		_             struct{} `json:"-"`
		condition     *regexp.Regexp
		strip         string
		add           string
		conditionText string
		cont          []rune
		cross         bool
	}

	// SuffixKey identifies one SFX rule the way the .aff file writes it.
	SuffixKey struct {
		_         struct{} `json:"-"`
		Strip     string
		Add       string
		Condition string
		Flag      rune
	}

	// AffixSet holds every prefix and suffix rule, keyed by flag.
	AffixSet struct {
		_        struct{} `json:"-"`
		prefixes map[rune][]affixRule
		suffixes map[rune][]affixRule
	}

	// Entry is one stem from a Hunspell .dic file, with its affix flags.
	Entry struct {
		_     struct{} `json:"-"`
		Stem  string
		Flags []rune
	}
)

// ParseAffixes reads the PFX and SFX rules from a .aff file, ignoring every other directive.
func ParseAffixes(r io.Reader) (*AffixSet, error) {
	set := &AffixSet{
		prefixes: map[rune][]affixRule{},
		suffixes: map[rune][]affixRule{},
	}
	cross := map[string]bool{}
	remaining := map[string]int{}

	err := eachLine(r, func(lineNum int, line string) error {
		fields := strings.Fields(line)
		if len(fields) < 4 || (fields[0] != prefixKind && fields[0] != suffixKind) {
			return nil
		}

		kind := fields[0]
		flag, _ := utf8.DecodeRuneInString(fields[1])
		key := kind + string(flag)

		if remaining[key] == 0 {
			count, convErr := strconv.Atoi(fields[3])
			if convErr != nil {
				return fmt.Errorf("affix header on line %d: %w", lineNum, convErr)
			}
			cross[key] = fields[2] == "Y"
			remaining[key] = count
			return nil
		}
		remaining[key]--

		rule, ruleErr := parseAffixRule(kind, fields[2:], cross[key])
		if ruleErr != nil {
			return fmt.Errorf("affix rule on line %d: %w", lineNum, ruleErr)
		}
		if kind == prefixKind {
			set.prefixes[flag] = append(set.prefixes[flag], rule)
		} else {
			set.suffixes[flag] = append(set.suffixes[flag], rule)
		}
		return nil
	})
	if err != nil {
		return nil, err
	}

	return set, nil
}

func parseAffixRule(kind string, fields []string, cross bool) (affixRule, error) {
	rule := affixRule{cross: cross}

	if fields[0] != "0" {
		rule.strip = fields[0]
	}

	add, cont, _ := strings.Cut(fields[1], "/")
	if add != "0" {
		rule.add = add
	}
	rule.cont = []rune(cont)

	condition := "."
	if len(fields) > 2 {
		condition = fields[2]
	}
	pattern := conditionToRegexp(condition)
	if kind == prefixKind {
		pattern = "^" + pattern
	} else {
		pattern += "$"
	}

	re, err := regexp.Compile(pattern)
	if err != nil {
		return affixRule{}, fmt.Errorf("compiling condition %q: %w", condition, err)
	}
	rule.condition = re
	rule.conditionText = condition

	return rule, nil
}

// DropSuffixes removes the given SFX rules. It fails if any is missing, so a dictionary
// update that renames or reshapes a rule can't silently bring it back.
func (s *AffixSet) DropSuffixes(keys []SuffixKey) error {
	for i := range keys {
		key := &keys[i]
		rules := s.suffixes[key.Flag]
		kept := slices.DeleteFunc(slices.Clone(rules), func(r affixRule) bool {
			return r.strip == key.Strip && r.add == key.Add && r.conditionText == key.Condition
		})
		if len(kept) == len(rules) {
			return fmt.Errorf("no SFX %c %s %s %s rule to drop", key.Flag, key.Strip, key.Add, key.Condition)
		}
		s.suffixes[key.Flag] = kept
	}
	return nil
}

// conditionToRegexp translates a Hunspell condition, which is only literals, '.', and
// bracketed character classes, into an unanchored regexp.
func conditionToRegexp(condition string) string {
	var b strings.Builder
	inClass := false
	for _, r := range condition {
		switch {
		case r == '[':
			inClass = true
			b.WriteRune(r)
		case r == ']':
			inClass = false
			b.WriteRune(r)
		case inClass || r == '.':
			b.WriteRune(r)
		default:
			b.WriteString(regexp.QuoteMeta(string(r)))
		}
	}
	return b.String()
}

func (r *affixRule) applySuffix(word string) (string, bool) {
	if !strings.HasSuffix(word, r.strip) || !r.condition.MatchString(word) {
		return "", false
	}
	return strings.TrimSuffix(word, r.strip) + r.add, true
}

func (r *affixRule) applyPrefix(word string) (string, bool) {
	if !strings.HasPrefix(word, r.strip) || !r.condition.MatchString(word) {
		return "", false
	}
	return r.add + strings.TrimPrefix(word, r.strip), true
}

// Expand calls emit with the stem and every form its flags generate. A form can be
// emitted more than once.
func (s *AffixSet) Expand(stem string, flags []rune, emit func(string)) {
	s.expandDepth(stem, flags, 0, emit)
}

func (s *AffixSet) expandDepth(stem string, flags []rune, depth int, emit func(string)) {
	emit(stem)

	var crossable []string
	for _, flag := range flags {
		for i := range s.suffixes[flag] {
			rule := &s.suffixes[flag][i]
			form, ok := rule.applySuffix(stem)
			if !ok {
				continue
			}
			emit(form)
			if rule.cross {
				crossable = append(crossable, form)
			}
			if len(rule.cont) > 0 && depth < maxContinuationDepth {
				s.expandDepth(form, rule.cont, depth+1, emit)
			}
		}
	}

	for _, flag := range flags {
		for i := range s.prefixes[flag] {
			rule := &s.prefixes[flag][i]
			if form, ok := rule.applyPrefix(stem); ok {
				emit(form)
			}
			if !rule.cross {
				continue
			}
			for _, suffixed := range crossable {
				if form, ok := rule.applyPrefix(suffixed); ok {
					emit(form)
				}
			}
		}
	}
}

// ParseDic reads a .dic file, dropping capitalized stems (proper nouns and
// abbreviations) since they aren't fair game in a word puzzle.
func ParseDic(r io.Reader) ([]Entry, error) {
	var entries []Entry
	err := eachLine(r, func(lineNum int, line string) error {
		fields := strings.Fields(line)
		if lineNum == 1 || len(fields) == 0 { // first line is the entry count
			return nil
		}

		stem, flags, _ := strings.Cut(fields[0], "/")
		first, _ := utf8.DecodeRuneInString(stem)
		if stem == "" || unicode.IsUpper(first) {
			return nil
		}
		entries = append(entries, Entry{Stem: stem, Flags: []rune(flags)})
		return nil
	})
	if err != nil {
		return nil, err
	}

	return entries, nil
}

// eachLine calls fn with every line and its 1-based line number. Source files are a few
// MB at most, so reading them whole is simpler than streaming.
func eachLine(r io.Reader, fn func(lineNum int, line string) error) error {
	data, err := io.ReadAll(r)
	if err != nil {
		return fmt.Errorf("reading: %w", err)
	}

	lineNum := 0
	for line := range strings.Lines(string(data)) {
		lineNum++
		if err = fn(lineNum, strings.TrimRight(line, "\r\n")); err != nil {
			return err
		}
	}

	return nil
}
