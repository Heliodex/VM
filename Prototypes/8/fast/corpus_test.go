package fast

import (
	"bufio"
	"encoding/hex"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
	"testing"
	"time"
)

type (
	// buildStats is what one file's build cost: the steps the machine ran (the fuel), and the time.
	buildStats struct {
		steps int64
		elapsed time.Duration
	}

	corpusImport struct {
		name, file string
		raw []byte
	}

	// The corpus build (Phase 8): each file of the corpus through its imports, then layout, lex, parse and check, on the four stage programs, as the Phase 0 harness runs them. corpus.txt has the programs, the files, and the reference's outcome at each stage (gen/corpus.luau); the build checks every stage against it and times the whole.

	corpusFile struct {
		name string
		raw []byte
		imports []corpusImport
		expect map[string]string // stage -> "value <hex>", "error <message>" or "out_of_fuel"
	}

	corpusData struct {
		programs map[string]*Law
		files []*corpusFile
		lines, bytes int
	}
)

const (
	fuelCheck = int64(1e10)

	// Fuel of each stage (gen/corpus.luau, the same as the Phase 0 harness).
	fuelLayout = int64(1e10)
	fuelLex = int64(1e8)
	fuelParse = int64(5e8)
	fuelDesugar = int64(1e11)
)

// bytesOf is a string of bytes as a machine list of integers (the reference's bytesValue).
func bytesOf(b []byte) Value {
	var v Value = NIL

	for _, v0 := range slices.Backward(b) {
		v = &Cell{
			Head: Small(v0),
			Tail: v,
		}
	}

	return v
}

// desugarInput is the input of the desugarer: (imports . (declarations . (expression . (tests . (import codes . input test))))), with the names of the imports, the parse's payload (declarations . expression), no checks (the corpus has none), the import codes, and no input check.
func desugarInput(names, parsed, codes Value) Value {
	noInputCheck := &Con{
		Tag: 0,
		Payload: NIL,
	}
	pair := parsed.(*Cell)

	return &Cell{
		Head: names,
		Tail: &Cell{
			Head: pair.Head,
			Tail: &Cell{
				Head: pair.Tail,
				Tail: &Cell{
					Head: NIL,
					Tail: &Cell{
						Head: codes,
						Tail: noInputCheck,
					},
				},
			},
		},
	}
}

// listOf is a list of values, in order.
func listOf(items []Value) Value {
	var v Value = NIL

	for _, item := range slices.Backward(items) {
		v = &Cell{
			Head: item,
			Tail: v,
		}
	}

	return v
}

// outcomeText is an outcome in the cases' form: "value <hex>", "error <message>" or "out_of_fuel".
func outcomeText(t *testing.T, o Outcome) string {
	t.Helper()

	switch o.Status {
	case "value":
		b, err := EncodeValue(o.Value)
		if err != nil {
			t.Fatal(err)
		}

		return "value " + hex.EncodeToString(b)
	case "error":
		return "error " + o.Message
	}

	return o.Status
}

// payloadOf is a stage's result payload, when the stage went through (a tagged result of tag 0).
func payloadOf(o Outcome) (Value, bool) {
	if o.Status != "value" {
		return nil, false
	}

	c, ok := o.Value.(*Con)
	if !ok || c.Tag != 0 {
		return nil, false
	}

	return c.Payload, true
}

// buildFile runs one file's build: its imports, then the file. It gives each stage's outcome, and the steps and time.
func buildFile(data corpusData, f *corpusFile) (map[string]Outcome, buildStats, error) {
	var st buildStats

	outs := map[string]Outcome{}
	start := time.Now()
	run := func(stage string, input Value, fuel int64) (Outcome, Value, bool) {
		o := RunBody(data.programs[stage].Body, input, fuel)
		st.steps += o.Steps
		p, ok := payloadOf(o)

		return o, p, ok
	}

	var libraries, libraryCodes []Value

	for _, imp := range f.imports {
		laid, laidPayload, ok := run("layout", bytesOf(imp.raw), fuelLayout)
		if !ok {
			return outs, st, fmt.Errorf("import %s: layout refused (%s)", imp.file, laid.Status)
		}

		lexed, lexedPayload, ok := run("lex", laidPayload, fuelLex)
		if !ok {
			return outs, st, fmt.Errorf("import %s: lex refused (%s)", imp.file, lexed.Status)
		}

		_, parsedPayload, ok := run("parse", lexedPayload, fuelParse)
		if !ok {
			return outs, st, fmt.Errorf("import %s: parse refused", imp.file)
		}

		libraries = append(libraries, &Cell{
			Head: bytesOf([]byte(imp.name)),
			Tail: parsedPayload,
		})

		// The library's machine expression, which the file's desugarer wraps around the file.
		if data.programs["desugar"] != nil {
			_, libCode, ok := run("desugar", desugarInput(NIL, parsedPayload, NIL), fuelDesugar)
			if !ok {
				return outs, st, fmt.Errorf("import %s: desugar refused", imp.file)
			}

			libraryCodes = append(libraryCodes, libCode)
		}
	}

	laid, bracketed, ok := run("layout", bytesOf(f.raw), fuelLayout)
	outs["layout"] = laid

	if !ok {
		return outs, st, nil
	}

	lexed, lexedPayload, ok := run("lex", bracketed, fuelLex)
	outs["lex"] = lexed

	if !ok {
		return outs, st, nil
	}

	parsed, parsedPayload, ok := run("parse", lexedPayload, fuelParse)
	outs["parse"] = parsed

	if !ok {
		return outs, st, nil
	}

	var request Value = &Con{
		Tag: 3,
		Payload: parsedPayload,
	}

	if len(libraries) > 0 {
		var cells Value = NIL

		for _, librarie := range slices.Backward(libraries) {
			cells = &Cell{
				Head: librarie,
				Tail: cells,
			}
		}

		request = &Con{
			Tag: 4,
			Payload: &Cell{
				Head: cells,
				Tail: parsedPayload,
			},
		}
	}

	checked, _, _ := run("check", request, fuelCheck)
	outs["check"] = checked

	// The file's desugarer, with the names and the machine expressions of its imports.
	var importNames []Value

	for _, imp := range f.imports {
		importNames = append(importNames, bytesOf([]byte(imp.name)))
	}

	if data.programs["desugar"] != nil {
		desugared, _, _ := run("desugar", desugarInput(listOf(importNames), parsedPayload, listOf(libraryCodes)), fuelDesugar)
		outs["desugar"] = desugared
	}

	st.elapsed = time.Since(start)

	return outs, st, nil
}

func readCorpus(t *testing.T) corpusData {
	t.Helper()

	path := os.Getenv("CORPUS")
	if path == "" {
		path = "testdata/corpus.txt"
	}

	f, err := os.Open(path)
	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	data := corpusData{
		programs: map[string]*Law{},
	}

	var cur *corpusFile

	sc := bufio.NewScanner(f)

	sc.Buffer(make([]byte, 1<<20), 1<<30)

	for sc.Scan() {
		switch line := sc.Text(); {
		case strings.HasPrefix(line, "# program "):
			fields := strings.Fields(line)

			prog, err := DecodeProgram(unhex(t, fields[3]))
			if err != nil {
				t.Fatalf("program %s: %v", fields[2], err)
			}

			data.programs[fields[2]] = prog
		case strings.HasPrefix(line, "# corpus: "):
			fields := strings.Fields(line)
			data.bytes, _ = strconv.Atoi(fields[2])
			data.lines, _ = strconv.Atoi(fields[4])
		case strings.HasPrefix(line, "file "):
			fields := strings.Fields(line)
			cur = &corpusFile{
				name: fields[1],
				raw: unhex(t, fields[2]),
				expect: map[string]string{},
			}
			data.files = append(data.files, cur)
		case strings.HasPrefix(line, "import "):
			fields := strings.Fields(line)
			cur.imports = append(cur.imports, corpusImport{
				name: fields[2],
				file: fields[3],
				raw: unhex(t, fields[4]),
			})
		case strings.HasPrefix(line, "expect "):
			fields := strings.SplitN(line, " ", 4)
			cur.expect[fields[2]] = fields[3]
		}
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	return data
}

// TestCorpus runs the corpus build and checks every stage of every file against the reference.
func TestCorpus(t *testing.T) {
	data := readCorpus(t)

	var total buildStats

	for _, f := range data.files {
		outs, st, err := buildFile(data, f)
		if err != nil {
			t.Errorf("%s: %v", f.name, err)
			continue
		}

		stages := []string{"layout", "lex", "parse", "check"}

		if _, ok := f.expect["desugar"]; ok {
			stages = append(stages, "desugar")
		}

		for _, stage := range stages {
			want, ok := f.expect[stage]
			if !ok {
				t.Errorf("%s: no reference for stage %s", f.name, stage)
				continue
			}

			if got := outcomeText(t, outs[stage]); got != want {
				t.Errorf("%s %s: got %.60s, want %.60s", f.name, stage, got, want)
			}
		}

		total.steps += st.steps
		total.elapsed += st.elapsed

		t.Logf("%-12s %6d steps  %8.3fs", f.name, st.steps, st.elapsed.Seconds())
	}

	t.Logf("corpus: %d files, %d bytes, %d lines; %d steps in %.3fs (%.1f M steps/s)", len(data.files), data.bytes, data.lines, total.steps, total.elapsed.Seconds(), float64(total.steps)/total.elapsed.Seconds()/1e6)
}
