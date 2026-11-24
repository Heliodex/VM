package fast

import (
	"bufio"
	"encoding/hex"
	"os"
	"strings"
	"testing"
)

type (
	parseError struct {
		s string
	}

	// programFixture is one line of testdata/programs.txt: a test's input and output, as the bootstrapped compile gives them (gen/programs.luau). A "-" is a value that holds a function, which the fixture does not cover.
	programFixture struct {
		path string
		line int
		input, output string
	}
)

const programsRoot = "../l2/programs/"

// programLoader reads an import, or a source, from the programs folder.
var programLoader = FileLoader(programsRoot)

// encodedHex is a value's binary form, as hex.
func encodedHex(t *testing.T, v Value) string {
	t.Helper()

	b, err := EncodeValue(v)
	if err != nil {
		t.Fatalf("encoding a value: %v", err)
	}

	return hex.EncodeToString(b)
}

func (e *parseError) Error() string {
	return "not a number: " + e.s
}

func sscanInt(s string, n *int) (int, error) {
	var v int

	for _, c := range s {
		if c < '0' || c > '9' {
			return 0, &parseError{s}
		}

		v = v*10 + int(c-'0')
	}

	*n = v

	return v, nil
}

// readProgramFixture reads testdata/programs.txt, in order.
func readProgramFixture(t *testing.T) []programFixture {
	t.Helper()

	f, err := os.Open("testdata/programs.txt")
	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	var out []programFixture

	sc := bufio.NewScanner(f)

	sc.Buffer(make([]byte, 1<<20), 1<<30)

	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 5 || fields[0] != "test" {
			t.Fatalf("programs.txt: a line that is not a test line: %q", sc.Text())
		}

		var line int

		if _, err := sscanInt(fields[2], &line); err != nil {
			t.Fatalf("programs.txt: %v", err)
		}

		out = append(out, programFixture{
			path: fields[1],
			line: line,
			input: fields[3],
			output: fields[4],
		})
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	return out
}

// TestPrograms runs every test of the 45 program files through the Go pipeline: each input and output expression is evaluated by the compiled program's declarations, and the program is run on the Go machine with the input. The result must be the expected output, and the expected output and input must be those the bootstrapped compile gives (testdata/programs.txt).
func TestPrograms(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	fixture := readProgramFixture(t)
	byPath := map[string]map[int]programFixture{}

	for _, fx := range fixture {
		if byPath[fx.path] == nil {
			byPath[fx.path] = map[int]programFixture{}
		}

		byPath[fx.path][fx.line] = fx
	}

	passed, total := 0, 0

	for path, tests := range byPath {
		text, ok := programLoader(path + ".l2")
		if !ok {
			t.Fatalf("%s: no program file", path)
		}

		c, err := stages.Compile(text, path+".l2", programLoader)
		if err != nil {
			t.Errorf("%s: %v", path, err)
			continue
		}

		file, err := ParseProgramFile(text)
		if err != nil {
			t.Fatalf("%s: %v", path, err)
		}

		for _, test := range file.Tests {
			total++
			fx, ok := tests[test.Line]

			if !ok {
				t.Errorf("%s:%d: no fixture for this test", path, test.Line)
				continue
			}

			input, err := c.Eval(test.Input)
			if err != nil {
				t.Errorf("%s:%d: the input %s: %v", path, test.Line, test.Input, err)
				continue
			}

			if fx.input != "-" && encodedHex(t, input) != fx.input {
				t.Errorf("%s:%d: the input %s evaluates to %s, the bootstrapped compile gives %s", path, test.Line, test.Input, encodedHex(t, input), fx.input)
				continue
			}

			want, err := c.Eval(test.Output)
			if err != nil {
				t.Errorf("%s:%d: the output %s: %v", path, test.Line, test.Output, err)
				continue
			}

			out := c.Run(input, evalFuel)
			if out.Status != "value" {
				t.Errorf("%s:%d: the program is %s: %s", path, test.Line, out.Status, out.Message)
				continue
			}

			got := encodedHex(t, out.Value)
			if got != encodedHex(t, want) {
				t.Errorf("%s:%d: the program gives %s, the output expression is %s", path, test.Line, got, encodedHex(t, want))
				continue
			}

			if fx.output != "-" && got != fx.output {
				t.Errorf("%s:%d: the program gives %s, the bootstrapped compile gives %s", path, test.Line, got, fx.output)
				continue
			}

			passed++
		}
	}

	t.Logf("%d of %d tests pass on the Go machine (%d program files)", passed, total, len(byPath))

	if total != len(fixture) {
		t.Errorf("the program files have %d tests, the fixture %d", total, len(fixture))
	}
}
