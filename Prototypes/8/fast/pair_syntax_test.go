package fast

import "testing"

// ⟨a b⟩ is the pair (a . b): the same value, the same checked type, and the same desugared code. The dot form is still read.
func TestAngledPairsAreDotPairs(t *testing.T) {
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

	pairs := [][2]string{
		{"⟨1 2⟩", "(1 . 2)"},
		{"⟨1 ⟨2 3⟩⟩", "(1 . (2 . 3))"},
		{"[⟨1 2⟩ 3]", "[(1 . 2) 3]"},
		{"⟨\"a\" ~⟩", "(\"a\" . ~)"},
		{"⟨(+ 1 2) 2⟩", "((+ 1 2) . 2)"},
	}

	for _, p := range pairs {
		got, err := c.Eval(p[0])
		if err != nil {
			t.Fatalf("%s: %v", p[0], err)
		}

		want, err := c.Eval(p[1])
		if err != nil {
			t.Fatalf("%s: %v", p[1], err)
		}

		if FormatValue(got) != FormatValue(want) {
			t.Fatalf("%s gives %s, %s gives %s", p[0], FormatValue(got), p[1], FormatValue(want))
		}
	}
}

// The angled form has exactly two parts, and no dot inside it.
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

	for _, text := range []string{"⟨1 . 2⟩", "⟨1 2 3⟩", "⟨1 2", "⟩", "⟨1⟩"} {
		if _, err := c.Eval(text); err == nil {
			t.Fatalf("%s: got a value, want an error", text)
		}
	}
}

// The checker gives the same type for ⟨a b⟩ as for (a . b), in an expression and in a type.
func TestAngledPairsCheckLikeDotPairs(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	for _, p := range [][2]string{
		{"⟨1 2⟩", "(1 . 2)"},
		{"⟨1 ⟨\"a\" 3⟩⟩", "(1 . (\"a\" . 3))"},
	} {
		got, ok := stages.CheckText(p[0])
		want, okWant := stages.CheckText(p[1])
		if !ok || !okWant {
			t.Fatalf("%s or %s is refused by the checker", p[0], p[1])
		}

		if got != want {
			t.Fatalf("%s checks as %q, %s as %q", p[0], got, p[1], want)
		}
	}
}
