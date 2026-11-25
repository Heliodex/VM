package fast

import "testing"

// The angled pair ⟨a b c⟩ nests to the right: ⟨a ⟨b c⟩⟩. Its values print in the same form.
func TestAngledPairValues(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	// A program file: a description, the imports, the program, and one test.
	file := "The identity.\n---\n\n---\nfn x\n\t(x)\n---\n0 => 0 fuel 1000\n"

	c, err := stages.Compile(file, "pairs.l2", nil)
	if err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		text, want string
	}{
		{"⟨1 2⟩", "⟨1 2⟩"},
		{"⟨1 ⟨2 3⟩⟩", "⟨1 ⟨2 3⟩⟩"},
		{"⟨1 2 3⟩", "⟨1 ⟨2 3⟩⟩"},
		{"⟨1 2 3 4⟩", "⟨1 ⟨2 ⟨3 4⟩⟩⟩"},
		{"[⟨1 2⟩ 3]", "[⟨1 2⟩ 3]"},
		{"⟨\"a\" ~⟩", "[[97]]"},
		{"⟨(+ 1 2) 2⟩", "⟨3 2⟩"},
	}

	for _, tc := range cases {
		got, err := c.Eval(tc.text)
		if err != nil {
			t.Fatalf("%s: %v", tc.text, err)
		}

		if FormatValue(got) != tc.want {
			t.Fatalf("%s gives %s, want %s", tc.text, FormatValue(got), tc.want)
		}
	}
}

// A pair with one part, a dot, or a missing bracket is refused, and so is the dot form.
func TestAngledPairsAreRefusedWhenMalformed(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	file := "The identity.\n---\n\n---\nfn x\n\t(x)\n---\n0 => 0 fuel 1000\n"

	c, err := stages.Compile(file, "pairs.l2", nil)
	if err != nil {
		t.Fatal(err)
	}

	for _, text := range []string{"⟨1 . 2⟩", "⟨1 2", "⟩", "⟨1⟩", "(1 . 2)", "((fst 1) . 2)"} {
		if _, err := c.Eval(text); err == nil {
			t.Fatalf("%s: got a value, want an error", text)
		}
	}
}

// The checker gives the angled pair's type, with each part in its own brackets where it needs them.
func TestAngledPairTypes(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		text, want string
	}{
		{"fn x\n\t⟨1 2⟩", "type (?v1 -> ⟨Int Int⟩)"},
		{"fn x\n\t⟨1 2 3⟩", "type (?v1 -> ⟨Int ⟨Int Int⟩⟩)"},
		{"fn x\n\t⟨1 ⟨\"a\" 3⟩⟩", "type (?v1 -> ⟨Int ⟨[Int] Int⟩⟩)"},
	}

	for _, tc := range cases {
		got, ok := stages.CheckText(tc.text)
		if !ok {
			t.Fatalf("%q is refused by the checker", tc.text)
		}

		if got != tc.want {
			t.Fatalf("%q checks as %q, want %q", tc.text, got, tc.want)
		}
	}
}
