package fast

import (
	"strings"
	"testing"
)

// codepoints gives the items of a list of codepoints as Go ints, and fails the test when the list is not a proper list of integers.
func codepoints(t *testing.T, v Value) []int64 {
	t.Helper()

	var out []int64

	for {
		c, ok := v.(*Cell)
		if !ok {
			if v != NIL {
				t.Fatalf("the list does not end in nil: %v", v)
			}

			return out
		}

		s, ok := c.Head.(Small)
		if !ok {
			t.Fatalf("an item that is not an integer: %v", c.Head)
		}

		out = append(out, int64(s))
		v = c.Tail
	}
}

func TestPipeSourceDecodesCodepoints(t *testing.T) {
	cases := []struct {
		text string
		want []int64
	}{
		{"", nil},
		{"ab", []int64{97, 98}},
		{"é", []int64{233}},
		{"⟨a⟩", []int64{0x27E8, 97, 0x27E9}},
		{"𝔸", []int64{0x1D538}},
		{"a b", []int64{97, 0xA0, 98}},
	}

	for _, c := range cases {
		v, err := pipeSource(c.text)
		if err != nil {
			t.Fatalf("%q: %v", c.text, err)
		}

		got := codepoints(t, v)
		if len(got) != len(c.want) {
			t.Fatalf("%q: got %v, want %v", c.text, got, c.want)
		}

		for i := range got {
			if got[i] != c.want[i] {
				t.Fatalf("%q: got %v, want %v", c.text, got, c.want)
			}
		}
	}
}

// Bytes that are not UTF-8 are refused, with the offset of the first one that is wrong.
func TestPipeSourceRefusesInvalidUTF8(t *testing.T) {
	cases := map[string]string{
		"a lone continuation byte": "a\x80b",
		"a truncated sequence": "a\xe2\x9f",
		"a byte that is never used": "\xff",
		"an encoded surrogate": "\xed\xa0\x80",
		"an overlong encoding": "\xc0\xaf",
	}

	for name, text := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := pipeSource(text); err == nil || !strings.Contains(err.Error(), "not UTF-8") {
				t.Fatalf("got %v, want a refusal", err)
			}
		})
	}
}

// The text of a list of codepoints is its UTF-8, and an item that is not a codepoint is "?".
func TestPipeTextRoundTrip(t *testing.T) {
	for _, text := range []string{"", "ab", "é", "⟨a⟩", "𝔸 and more"} {
		v, err := pipeSource(text)
		if err != nil {
			t.Fatal(err)
		}

		if got := pipeText(v); got != text {
			t.Fatalf("%q came back as %q", text, got)
		}
	}

	bad := &Cell{Head: Small(0xD800), Tail: &Cell{Head: Small(-1), Tail: &Cell{Head: Small(0x110000), Tail: NIL}}}
	if got := pipeText(bad); got != "???" {
		t.Fatalf("got %q, want ???", got)
	}
}

// A string literal holds codepoints: "é" is the one item 233, not the two bytes of its UTF-8.
func TestStringLiteralIsCodepoints(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	// A program file: a description, the imports, the program, and the tests. The program is the identity, so the file is complete.
	file := "The identity.\n---\n\n---\nfn x\n\t(x)\n---\n0 => 0 fuel 1000\n"

	c, err := stages.Compile(file, "text.l2", nil)
	if err != nil {
		t.Fatal(err)
	}

	for text, want := range map[string][]int64{
		`"é"`: {233},
		`"⟨"`: {0x27E8},
		`"ab"`: {97, 98},
	} {
		v, err := c.Eval(text)
		if err != nil {
			t.Fatalf("%s: %v", text, err)
		}

		got := codepoints(t, v)
		if len(got) != len(want) || got[0] != want[0] || (len(want) > 1 && got[1] != want[1]) {
			t.Fatalf("%s: got %v, want %v", text, got, want)
		}
	}
}
