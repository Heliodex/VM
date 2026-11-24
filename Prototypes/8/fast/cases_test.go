package fast

import (
	"bufio"
	"os"
	"strings"
	"testing"
)

// TestCaseFixture runs the case programs of testdata/cases (the programs the program files do not cover) through the Go pipeline, and checks each test's input and output encodings against the bootstrapped compile's (testdata/l2cases.txt, from gen/cases.luau). The cases are programs with a checker failure at the input boundary, records with a with and a match, a mutual group, an early return, a user sum, and an import.
func TestCaseFixture(t *testing.T) {
	stages, err := SeedStages()

	if err != nil {
		t.Fatal(err)
	}

	f, err := os.Open("testdata/l2cases.txt")

	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	type fixtureLine struct {
		line int
		input, output string
	}

	byName := map[string]map[int]fixtureLine{}
	var order []string
	sc := bufio.NewScanner(f)

	for sc.Scan() {
		fields := strings.Fields(sc.Text())

		if len(fields) != 5 || fields[0] != "case" {
			t.Fatalf("cases.txt: a line that is not a case line: %q", sc.Text())
		}

		var line int

		if _, err := sscanInt(fields[2], &line); err != nil {
			t.Fatalf("cases.txt: %v", err)
		}

		if byName[fields[1]] == nil {
			byName[fields[1]] = map[int]fixtureLine{}
			order = append(order, fields[1])
		}

		byName[fields[1]][line] = fixtureLine{line: line, input: fields[3], output: fields[4]}
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	loader := FileLoader(programsRoot)
	total := 0

	for _, name := range order {
		text, err := os.ReadFile("testdata/cases/" + name + ".case")

		if err != nil {
			t.Fatal(err)
		}

		c, err := stages.Compile(string(text), name+".case", loader)

		if err != nil {
			t.Errorf("%s: %v", name, err)

			continue
		}

		file, err := ParseProgramFile(string(text))

		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}

		for _, test := range file.Tests {
			total++
			fx, ok := byName[name][test.Line]

			if !ok {
				t.Errorf("%s:%d: no fixture", name, test.Line)

				continue
			}

			input, err := c.Eval(test.Input)

			if err != nil {
				t.Errorf("%s:%d: the input: %v", name, test.Line, err)

				continue
			}

			if got := encodedHex(t, input); got != fx.input {
				t.Errorf("%s:%d: the input evaluates to %s, the bootstrapped compile gives %s", name, test.Line, got, fx.input)

				continue
			}

			out := c.Run(input, evalFuel)

			if out.Status != "value" {
				t.Errorf("%s:%d: the program is %s: %s", name, test.Line, out.Status, out.Message)

				continue
			}

			if got := encodedHex(t, out.Value); got != fx.output {
				t.Errorf("%s:%d: the program gives %s, the bootstrapped compile gives %s", name, test.Line, got, fx.output)
			}
		}
	}

	t.Logf("%d case tests over %d programs", total, len(order))

}
