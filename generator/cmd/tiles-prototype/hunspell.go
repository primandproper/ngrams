package main

import (
	"fmt"
	"regexp"
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
		_         struct{} `json:"-"`
		condition *regexp.Regexp
		strip     string
		add       string
		cont      []rune
		cross     bool
	}

	// affixSet holds every prefix and suffix rule, keyed by flag. Only the subset of
	// the format that es_MX uses is supported: FLAG UTF-8, cross products, and
	// continuation classes on affixes.
	affixSet struct {
		_        struct{} `json:"-"`
		prefixes map[rune][]affixRule
		suffixes map[rune][]affixRule
	}

	// dicEntry is one stem from a Hunspell .dic file, with its affix flags.
	dicEntry struct {
		_     struct{} `json:"-"`
		stem  string
		flags []rune
	}
)

func loadAffixes(path string) (*affixSet, error) {
	set := &affixSet{
		prefixes: map[rune][]affixRule{},
		suffixes: map[rune][]affixRule{},
	}
	cross := map[string]bool{}
	remaining := map[string]int{}

	err := eachLine(path, func(lineNum int, line string) error {
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

	return rule, nil
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

// expand calls emit with the stem and every form its flags generate.
func (s *affixSet) expand(stem string, flags []rune, emit func(string)) {
	s.expandDepth(stem, flags, 0, emit)
}

func (s *affixSet) expandDepth(stem string, flags []rune, depth int, emit func(string)) {
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

// loadDic reads a Hunspell .dic file, dropping capitalized stems (proper nouns and
// abbreviations) since they aren't fair game in a word puzzle.
func loadDic(path string) ([]dicEntry, error) {
	var entries []dicEntry
	err := eachLine(path, func(lineNum int, line string) error {
		fields := strings.Fields(line)
		if lineNum == 1 || len(fields) == 0 { // first line is the entry count
			return nil
		}

		stem, flags, _ := strings.Cut(fields[0], "/")
		first, _ := utf8.DecodeRuneInString(stem)
		if stem == "" || unicode.IsUpper(first) {
			return nil
		}
		entries = append(entries, dicEntry{stem: stem, flags: []rune(flags)})
		return nil
	})
	if err != nil {
		return nil, err
	}

	return entries, nil
}
