package lexicon

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/shoenig/test/must"
)

// spanishAff carries every voseo and vosotros rule the loader drops, which it requires.
const spanishAff = `SFX ô Y 2
SFX ô r te [aei]r
SFX ô ir íos ir
SFX X Y 5
SFX X er é er
SFX X ir í ir
SFX X ir íais ir
SFX X r ais ír
SFX X r s ír
SFX S Y 1
SFX S 0 es n
SFX J Y 1
SFX J er en er
`

// writeFiles writes name → contents under dir, creating parent directories.
func writeFiles(t *testing.T, dir string, files map[string]string) {
	t.Helper()

	for name, contents := range files {
		path := filepath.Join(dir, name)
		must.NoError(t, os.MkdirAll(filepath.Dir(path), 0o750))
		must.NoError(t, os.WriteFile(path, []byte(contents), 0o600))
	}
}

func TestFold(T *testing.T) {
	T.Parallel()

	T.Run("lowercases and strips accents", func(t *testing.T) {
		t.Parallel()

		word, ok := Fold("Canción")
		must.True(t, ok)
		must.Eq(t, "cancion", word)
	})

	T.Run("keeps ñ", func(t *testing.T) {
		t.Parallel()

		word, ok := Fold("Niño")
		must.True(t, ok)
		must.Eq(t, "niño", word)
	})

	T.Run("rejects anything outside a-z and ñ", func(t *testing.T) {
		t.Parallel()

		for _, word := range []string{"don't", "co-op", "r2d2", "naïve", ""} {
			_, ok := Fold(word)
			must.False(t, ok, must.Sprintf("folding %q", word))
		}
	})
}

func TestLexicon_Lookup(T *testing.T) {
	T.Parallel()

	lex := New(map[string]string{"cat": "cat", "cats": "cats", "dog": "dog"}, nil, nil, nil)

	T.Run("finds a word that is also a prefix", func(t *testing.T) {
		t.Parallel()

		isWord, isPrefix := lex.Lookup("cat")
		must.True(t, isWord)
		must.True(t, isPrefix)
	})

	T.Run("finds a prefix that isn't a word", func(t *testing.T) {
		t.Parallel()

		isWord, isPrefix := lex.Lookup("ca")
		must.False(t, isWord)
		must.True(t, isPrefix)
	})

	T.Run("finds neither past the last word", func(t *testing.T) {
		t.Parallel()

		isWord, isPrefix := lex.Lookup("zebra")
		must.False(t, isWord)
		must.False(t, isPrefix)
	})

	T.Run("finds neither between words", func(t *testing.T) {
		t.Parallel()

		isWord, isPrefix := lex.Lookup("cb")
		must.False(t, isWord)
		must.False(t, isPrefix)
	})
}

func TestLoad(T *testing.T) {
	T.Parallel()

	T.Run("loads english", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{
			"raw/en/enable1.txt":   "cat\ncats\ndog\nshit\n",
			"raw/en/en_50k.txt":    "cat 100\nshit 50\ndog 5\nzzz 1\n",
			"blocklists/en.txt":    "# comment\nshit\n\n",
			"blocklists/other.txt": "",
		})

		lex, err := Load("en", &Config{
			DataDir:      filepath.Join(dir, "raw"),
			BlocklistDir: filepath.Join(dir, "blocklists"),
			MinCount:     20,
		})
		must.NoError(t, err)

		must.Eq(t, 4, lex.Size())
		must.Eq(t, []string{"cat", "dog"}, lex.Targets())
		must.True(t, lex.Blocked("shit"))

		count, common := lex.Count("cat")
		must.True(t, common)
		must.Eq(t, 100, count)

		_, common = lex.Count("dog")
		must.False(t, common)
	})

	T.Run("drops english plurals and past tenses from answers", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		words := "bake\nbaked\nbos\nboss\ncat\ncats\nfree\nfreed\nbed\n"
		writeFiles(t, dir, map[string]string{
			"raw/en/enable1.txt": words,
			"raw/en/en_50k.txt":  strings.ReplaceAll(words, "\n", " 100\n"),
			"blocklists/en.txt":  "",
		})

		lex, err := Load("en", &Config{
			DataDir:      filepath.Join(dir, "raw"),
			BlocklistDir: filepath.Join(dir, "blocklists"),
			MinCount:     20,
		})
		must.NoError(t, err)

		must.Eq(t, []string{"bake", "bed", "bos", "boss", "cat", "free"}, lex.Answers())
		must.SliceLen(t, 9, lex.Targets())
	})

	T.Run("loads spanish, dropping voseo and vosotros", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{
			"raw/es/es_MX.aff":   spanishAff,
			"raw/es/es_MX.dic":   "5\ncanción/S\njoder/J\nvivir/X\ndad\nMéxico\n",
			"raw/es/es_full.txt": "canción 300\ncancion 10\njoder 200\ndad 90\ncanciones 50\nméxico 80\n",
			"blocklists/es.txt":  "joder\n",
		})

		lex, err := Load("es", &Config{
			DataDir:      filepath.Join(dir, "raw"),
			BlocklistDir: filepath.Join(dir, "blocklists"),
			MinCount:     20,
		})
		must.NoError(t, err)

		must.Eq(t, []string{"cancion"}, lex.Targets())
		must.Eq(t, []string{"cancion"}, lex.Answers())
		must.Eq(t, "canción", lex.Display("cancion"))

		count, common := lex.Count("cancion")
		must.True(t, common)
		must.Eq(t, 310, count)

		must.True(t, lex.Blocked("joden"), must.Sprint("forms of a blocked stem are blocked"))

		isWord, _ := lex.Lookup("vivi")
		must.False(t, isWord, must.Sprint("voseo rule dropped"))
		isWord, _ = lex.Lookup("dad")
		must.False(t, isWord, must.Sprint("vosotros stem dropped"))
		isWord, _ = lex.Lookup("mexico")
		must.False(t, isWord, must.Sprint("capitalized stem dropped"))
	})

	T.Run("keeps flagless spanish stems out of answers", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{
			"raw/es/es_MX.aff":   spanishAff,
			"raw/es/es_MX.dic":   "2\nvera/S\nseré\n",
			"raw/es/es_full.txt": "verá 500\nvera 10\nseré 300\n",
			"blocklists/es.txt":  "",
		})

		lex, err := Load("es", &Config{
			DataDir:      filepath.Join(dir, "raw"),
			BlocklistDir: filepath.Join(dir, "blocklists"),
			MinCount:     20,
		})
		must.NoError(t, err)

		must.Eq(t, []string{"sere", "vera"}, lex.Targets())
		must.Eq(t, []string{"vera"}, lex.Answers())
		must.Eq(t, "vera", lex.Display("vera"), must.Sprint("the stem's spelling beats its homograph"))
		must.Eq(t, "seré", lex.Display("sere"))
	})

	T.Run("rejects an unsupported language", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{"blocklists/fr.txt": ""})

		_, err := Load("fr", &Config{DataDir: dir, BlocklistDir: filepath.Join(dir, "blocklists")})
		must.Error(t, err)
	})

	T.Run("rejects a blocklist entry that isn't a plain word", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{"blocklists/en.txt": "co-op\n"})

		_, err := Load("en", &Config{DataDir: dir, BlocklistDir: filepath.Join(dir, "blocklists")})
		must.Error(t, err)
	})

	T.Run("fails on a missing dictionary", func(t *testing.T) {
		t.Parallel()

		dir := t.TempDir()
		writeFiles(t, dir, map[string]string{"blocklists/en.txt": ""})

		_, err := Load("en", &Config{DataDir: dir, BlocklistDir: filepath.Join(dir, "blocklists")})
		must.Error(t, err)
	})
}
