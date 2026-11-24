package fast

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"os"
	"strings"
	"testing"
)

// convertFixture reads testdata/convert.txt: for each file of the corpus, the program law the Luau host gives (gen/convert.luau).
func convertFixture(t *testing.T) map[string]string {
	t.Helper()

	f, err := os.Open("testdata/convert.txt")
	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	out := map[string]string{}
	sc := bufio.NewScanner(f)

	sc.Buffer(make([]byte, 1<<20), 1<<30)

	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 3 || fields[0] != "law" && fields[0] != "code" {
			t.Fatalf("convert.txt: a line that is neither a law nor a code line: %q", sc.Text())
		}

		out[fields[0]+" "+fields[1]] = fields[2]
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	return out
}

// fileCode runs a program file through the bootstrapped compile as the host does (boot_pipeline.luau's compileTextInner): its layout, tokenizer and parser; each import, compiled the same way, which gives its parsed form and its machine expression; its checker, with the request InferT, which gives the checks and the input test; and its desugarer, with the imports' names and expressions. It gives the parsed form of the file and the desugarer's output.
func fileCode(data corpusData, raw []byte, imports []corpusImport) (Value, Value, error) {
	run := func(stage string, input Value, fuel int64) (Outcome, Value, bool) {
		o := RunBody(data.programs[stage].Body, input, fuel)
		p, ok := payloadOf(o)

		return o, p, ok
	}

	var libraries, libraryCodes, names []Value

	for _, imp := range imports {
		_, libParsed, libCode, err := fileCodeOf(data, imp.raw, nil)
		if err != nil {
			return nil, nil, fmt.Errorf("import %s: %w", imp.file, err)
		}

		names = append(names, bytesOf([]byte(imp.name)))
		libraries = append(libraries, &Cell{
			Head: bytesOf([]byte(imp.name)),
			Tail: libParsed,
		})
		libraryCodes = append(libraryCodes, libCode)
	}

	_, bracketed, ok := run("layout", bytesOf(raw), fuelLayout)
	if !ok {
		return nil, nil, fmt.Errorf("layout refused")
	}

	_, lexedPayload, ok := run("lex", bracketed, fuelLex)
	if !ok {
		return nil, nil, fmt.Errorf("lex refused")
	}

	_, parsed, ok := run("parse", lexedPayload, fuelParse)
	if !ok {
		return nil, nil, fmt.Errorf("parse refused")
	}

	pair, ok := parsed.(*Cell)
	if !ok {
		return nil, nil, fmt.Errorf("the parse's payload is not a pair")
	}

	// The checker's request InferT (tag 5): the libraries, then the program.
	checked := RunBody(data.programs["check"].Body, &Con{
		Tag: 5,
		Payload: &Cell{
			Head: listOf(libraries),
			Tail: parsed,
		},
	}, fuelCheck)
	if checked.Status != "value" {
		return nil, nil, fmt.Errorf("the checker refused the program: %s", checked.Status)
	}

	checkValue := checked.Value

	if con, isCon := checkValue.(*Con); isCon && con.Tag == 0 {
		checkValue = con.Payload
	}

	// The checker's result: (text . (errors . (checks . input test))).
	result, ok := checkValue.(*Cell)
	if !ok {
		return nil, nil, fmt.Errorf("the checker's result is not a pair")
	}

	errs, ok := result.Tail.(*Cell)
	if !ok {
		return nil, nil, fmt.Errorf("the checker's result has no errors part")
	}

	rest, ok := errs.Tail.(*Cell)
	if !ok {
		return nil, nil, fmt.Errorf("the checker's result has no checks part")
	}

	input := &Cell{
		Head: listOf(names),
		Tail: &Cell{
			Head: pair.Head,
			Tail: &Cell{
				Head: pair.Tail,
				Tail: &Cell{
					Head: rest.Head,
					Tail: &Cell{
						Head: listOf(libraryCodes),
						Tail: rest.Tail,
					},
				},
			},
		},
	}
	desugared := RunBody(data.programs["desugar"].Body, input, fuelDesugar)
	code, ok := payloadOf(desugared)

	if !ok {
		return nil, nil, fmt.Errorf("the desugarer refused the program: %s", desugared.Status)
	}

	return parsed, code, nil
}

// fileCodeOf is fileCode for a file with no imports of its own (the libraries of the corpus have none), as the parsed form and the code.
func fileCodeOf(data corpusData, raw []byte, imports []corpusImport) (Value, Value, Value, error) {
	parsed, code, err := fileCode(data, raw, imports)

	return nil, parsed, code, err
}

// TestConvertMatchesLowering checks that the converter, given the desugarer's output for each file of the 2,500-line corpus, gives the program law the Luau lowering gives, byte for byte.
func TestConvertMatchesLowering(t *testing.T) {
	want := convertFixture(t)

	t.Setenv("CORPUS", "testdata/corpus2500_desugar.txt")

	data := readCorpus(t)

	var checked int

	for _, f := range data.files {
		fixture, ok := want["law "+f.name]
		if !ok {
			continue
		}

		_, code, err := fileCode(data, f.raw, f.imports)
		if err != nil {
			t.Fatalf("%s: %v", f.name, err)
		}

		// The desugarer's output itself: the host's bootstrapped compile gives the same Code value.
		encoded, err := EncodeValue(code)
		if err != nil {
			t.Fatalf("%s: encoding the code value: %v", f.name, err)
		}

		if want, ok := want["code "+f.name]; !ok || hex.EncodeToString(encoded) != want {
			t.Errorf("%s: the desugarer's code value differs from the bootstrapped compile's", f.name)
		}

		law, err := ConvertLaw(code)
		if err != nil {
			t.Fatalf("%s: %v", f.name, err)
		}

		got, err := EncodeProgram(law)
		if err != nil {
			t.Fatalf("%s: encoding the law: %v", f.name, err)
		}

		if hex.EncodeToString(got) != fixture {
			t.Errorf("%s: the converter's law differs from the lowering (%d bytes, want %d)", f.name, len(got), len(fixture)/2)
		}

		checked++
	}

	if checked*2 != len(want) {
		t.Fatalf("checked %d files of a fixture of %d lines", checked, len(want))
	}

	t.Logf("%d files: the converter's laws are the lowering's bytes", checked)
}
