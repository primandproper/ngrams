package hunspell

import (
	"slices"
	"strings"
	"testing"

	"github.com/shoenig/test/must"
)

const testAffixes = `SET UTF-8
FLAG UTF-8

SFX S Y 2
SFX S 0 s [aeiou]
SFX S 0 es [^aeiou]

PFX R Y 1
PFX R 0 re .

SFX C N 1
SFX C 0 ero/S n
`

func parseTestAffixes(t *testing.T) *AffixSet {
	t.Helper()

	set, err := ParseAffixes(strings.NewReader(testAffixes))
	must.NoError(t, err)

	return set
}

func expandAll(set *AffixSet, stem, flags string) []string {
	var forms []string
	set.Expand(stem, []rune(flags), func(form string) {
		forms = append(forms, form)
	})
	slices.Sort(forms)
	return slices.Compact(forms)
}

func TestAffixSet_Expand(T *testing.T) {
	T.Parallel()

	T.Run("applies suffixes, prefixes, and their cross product", func(t *testing.T) {
		t.Parallel()

		set := parseTestAffixes(t)

		must.Eq(t, []string{"gato", "gatos", "regato", "regatos"}, expandAll(set, "gato", "SR"))
	})

	T.Run("picks the suffix whose condition matches", func(t *testing.T) {
		t.Parallel()

		set := parseTestAffixes(t)

		must.Eq(t, []string{"pan", "panes"}, expandAll(set, "pan", "S"))
	})

	T.Run("follows continuation classes", func(t *testing.T) {
		t.Parallel()

		set := parseTestAffixes(t)

		must.Eq(t, []string{"pan", "panero", "paneros"}, expandAll(set, "pan", "C"))
	})

	T.Run("emits only the stem without flags", func(t *testing.T) {
		t.Parallel()

		set := parseTestAffixes(t)

		must.Eq(t, []string{"sol"}, expandAll(set, "sol", ""))
	})
}

func TestAffixSet_DropSuffixes(T *testing.T) {
	T.Parallel()

	T.Run("removes the named rule", func(t *testing.T) {
		t.Parallel()

		set := parseTestAffixes(t)

		must.NoError(t, set.DropSuffixes([]SuffixKey{{Flag: 'S', Add: "es", Condition: "[^aeiou]"}}))
		must.Eq(t, []string{"pan"}, expandAll(set, "pan", "S"))
		must.Eq(t, []string{"gato", "gatos"}, expandAll(set, "gato", "S"))
	})

	T.Run("fails on a rule that doesn't exist", func(t *testing.T) {
		t.Parallel()

		set := parseTestAffixes(t)

		must.Error(t, set.DropSuffixes([]SuffixKey{{Flag: 'S', Add: "os", Condition: "o"}}))
	})
}

func TestParseAffixes(T *testing.T) {
	T.Parallel()

	T.Run("fails on a malformed rule count", func(t *testing.T) {
		t.Parallel()

		_, err := ParseAffixes(strings.NewReader("SFX S Y many\n"))
		must.Error(t, err)
	})
}

func TestParseDic(T *testing.T) {
	T.Parallel()

	T.Run("reads stems and flags, skipping the count line", func(t *testing.T) {
		t.Parallel()

		entries, err := ParseDic(strings.NewReader("2\ngato/SR\nsol\n"))
		must.NoError(t, err)

		must.Eq(t, []Entry{
			{Stem: "gato", Flags: []rune("SR")},
			{Stem: "sol", Flags: []rune{}},
		}, entries)
	})

	T.Run("drops capitalized stems", func(t *testing.T) {
		t.Parallel()

		entries, err := ParseDic(strings.NewReader("2\nMéxico/S\nONU\n"))
		must.NoError(t, err)

		must.SliceEmpty(t, entries)
	})
}
