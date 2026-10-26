package lexicon

import (
	"bytes"
	"fmt"
	"io"
	"maps"
	"os"
	"path/filepath"
	"slices"

	"github.com/primandproper/ngrams/generator/internal/hunspell"
)

// Mexican Spanish uses neither voseo nor vosotros. es_MX's affix rules mostly leave
// vosotros out, but these slip through, found by sweeping every SFX rule for voseo and
// vosotros endings. es_MX also keeps r → 0 for -ír verbs, whose output (oí, reí) doubles
// as the standard yo preterite, so that one stays.
var nonMexicanSuffixes = []hunspell.SuffixKey{
	{Flag: 'ô', Strip: "r", Add: "te", Condition: "[aei]r"}, // voseo: matate
	{Flag: 'X', Strip: "er", Add: "é", Condition: "er"},     // voseo: tené
	{Flag: 'X', Strip: "ir", Add: "í", Condition: "ir"},     // voseo: vení
	{Flag: 'X', Strip: "ir", Add: "íais", Condition: "ir"},  // vosotros: adquiríais
	{Flag: 'X', Strip: "r", Add: "ais", Condition: "ír"},    // vosotros: oíais
	{Flag: 'X', Strip: "r", Add: "s", Condition: "ír"},      // vosotros: sonreís
	{Flag: 'ô', Strip: "ir", Add: "íos", Condition: "ir"},   // vosotros: divertíos
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

// loadSpanish expands es_MX into every form. Only .dic stems become targets, since they
// are close to base forms (infinitives, singular nouns, masculine singular adjectives).
// Answers further need affix flags: the flagless stems are mostly irregular conjugations
// and abbreviations (seré, podrán, dpto), and a stem displays as the dictionary spells
// it rather than as its most common homograph (vera, not verá).
func loadSpanish(dir string, minCount int, blocked map[string]bool) (*Lexicon, error) {
	affixes, err := parseFile(filepath.Join(dir, "es_MX.aff"), hunspell.ParseAffixes)
	if err != nil {
		return nil, err
	}
	if err = affixes.DropSuffixes(nonMexicanSuffixes); err != nil {
		return nil, fmt.Errorf("dropping voseo and vosotros rules: %w", err)
	}
	entries, err := parseFile(filepath.Join(dir, "es_MX.dic"), hunspell.ParseDic)
	if err != nil {
		return nil, err
	}

	// Blocklist entries are stems, so every form expanded from one is blocked too.
	display := map[string]string{}
	allBlocked := maps.Clone(blocked)
	stems := map[string]struct{}{}
	flagged := map[string]string{}
	for i := range entries {
		if vosotrosStems[entries[i].Stem] {
			continue
		}
		stem, ok := Fold(entries[i].Stem)
		if ok {
			stems[stem] = struct{}{}
			if len(entries[i].Flags) > 0 {
				flagged[stem] = entries[i].Stem
			}
		}
		stemBlocked := ok && blocked[stem]
		affixes.Expand(entries[i].Stem, entries[i].Flags, func(form string) {
			word, valid := Fold(form)
			if !valid {
				return
			}
			if _, seen := display[word]; !seen {
				display[word] = form
			}
			if stemBlocked {
				allBlocked[word] = true
			}
		})
	}

	freq, top, err := loadFrequencies(filepath.Join(dir, "es_full.txt"), display, minCount)
	if err != nil {
		return nil, err
	}

	maps.Copy(display, flagged)

	var targets []string
	for stem := range stems {
		if top[stem] && !allBlocked[stem] {
			targets = append(targets, stem)
		}
	}

	lex := New(display, freq, allBlocked, targets)
	lex.answers = slices.DeleteFunc(slices.Clone(lex.targets), func(stem string) bool {
		_, ok := flagged[stem]
		return !ok
	})
	return lex, nil
}

func parseFile[T any](path string, parse func(io.Reader) (T, error)) (T, error) {
	var zero T

	data, err := os.ReadFile(path)
	if err != nil {
		return zero, fmt.Errorf("reading %s: %w", path, err)
	}

	parsed, err := parse(bytes.NewReader(data))
	if err != nil {
		return zero, fmt.Errorf("parsing %s: %w", path, err)
	}

	return parsed, nil
}
