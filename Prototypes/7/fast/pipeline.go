package fast

import (
	_ "embed"
	"encoding/hex"
	"fmt"
	"os"
	"strings"
	"sync"
)

// The pipeline (Prototype 8): the L2 compiler, run on the machine, and the program it gives, run on the machine.
//
// The compiler is five stage programs, each a law: the layout, the tokenizer, the parser, the checker and the desugarer (Prototypes/6/L2/programs/boot). A program file is compiled by running them in turn, as boot_pipeline.luau does: its imports first, each compiled the same way; then the program's own section. The desugarer's output is a Code value, which converter.go turns into the law the machine runs.
//
// The stage programs are the seed (testdata/stages.txt): the compiler's first generation, compiled from the stage sources. A stage source compiled by the seed gives the same bytes as the seed, which is the fixed point that pipeline_test.go checks.

//go:embed testdata/stages.txt
var seedSource string

// The fuel of each stage, as the corpus build gives it (corpus_test.go).
const (
	stageFuelLayout = int64(1e10)
	stageFuelLex = int64(1e8)
	stageFuelParse = int64(5e8)
	stageFuelCheck = int64(1e10)
	stageFuelDesugar = int64(1e11)
	evalFuel = int64(1 << 40)
)

// Stages are the stage programs of the compiler, by name: layout, lex, parse, check and desugar.
type Stages map[string]*Law

var (
	seedOnce sync.Once
	seedStages Stages
	seedErr error
)

// SeedStages are the stage programs of testdata/stages.txt, which is embedded in the build.
func SeedStages() (Stages, error) {
	seedOnce.Do(func() {
		seedStages, seedErr = ParseStages(seedSource)
	})

	return seedStages, seedErr
}

// ParseStages reads stage programs from text: a line stage <name> <hex>, one per stage.
func ParseStages(text string) (Stages, error) {
	out := Stages{}

	for _, line := range strings.Split(text, "\n") {
		fields := strings.Fields(line)

		if len(fields) == 0 {
			continue
		}

		if len(fields) != 3 || fields[0] != "stage" {
			return nil, fmt.Errorf("stages: a line that is not a stage line: %.40q", line)
		}

		b, err := hex.DecodeString(fields[2])

		if err != nil {
			return nil, fmt.Errorf("stages: %s: %w", fields[1], err)
		}

		law, err := DecodeProgram(b)

		if err != nil {
			return nil, fmt.Errorf("stages: %s: %w", fields[1], err)
		}

		out[fields[1]] = law
	}

	for _, name := range []string{"layout", "lex", "parse", "check", "desugar"} {
		if out[name] == nil {
			return nil, fmt.Errorf("stages: no %s stage", name)
		}
	}

	return out, nil
}

// pipeBytes is a list of bytes, as the stages read text.
func pipeBytes(b []byte) Value {
	items := make([]Value, len(b))

	for i, c := range b {
		items[i] = Small(c)
	}

	return pipeList(items)
}

// pipeList is a list of values, in order.
func pipeList(items []Value) Value {
	var v Value = NIL

	for i := len(items) - 1; i >= 0; i-- {
		v = &Cell{Head: items[i], Tail: v}
	}

	return v
}

// pipeText is the text of a list of bytes, for messages.
func pipeText(v Value) string {
	var b strings.Builder

	for {
		c, ok := v.(*Cell)

		if !ok {
			break
		}

		s, ok := c.Head.(Small)

		if !ok {
			b.WriteString("?")
		} else {
			b.WriteByte(byte(s))
		}

		v = c.Tail
	}

	return b.String()
}

// resultPayload is the payload of a stage's result: tag 0 is success, and tag 1 a message.
func resultPayload(v Value) (Value, error) {
	con, ok := v.(*Con)

	if !ok {
		return nil, fmt.Errorf("a stage gave %T, not a result", v)
	}

	if con.Tag == 0 {
		return con.Payload, nil
	}

	return nil, fmt.Errorf("%s", pipeText(con.Payload))
}

// run runs a stage on its input, with its fuel, and gives its result.
func (s Stages) run(name string, input Value, fuel int64) (Value, error) {
	law := s[name]

	if law == nil {
		return nil, fmt.Errorf("no %s stage", name)
	}

	o := RunBody(law.Body, input, fuel)

	if o.Status != "value" {
		return nil, fmt.Errorf("the %s stage is %s", name, o.Status)
	}

	return o.Value, nil
}

// stageInput is the input of the desugarer: (imports . (declarations . (expression . (checks . (import codes . input test))))).
func stageInput(names, parsed, checks, codes, inputTest Value) Value {
	pair := parsed.(*Cell)

	return &Cell{
		Head: names,
		Tail: &Cell{
			Head: pair.Head,
			Tail: &Cell{
				Head: pair.Tail,
				Tail: &Cell{
					Head: checks,
					Tail: &Cell{
						Head: codes,
						Tail: inputTest,
					},
				},
			},
		},
	}
}

// Compiled is a program file compiled by the pipeline: its law, and what its tests need to be evaluated with it.
type Compiled struct {
	Law *Law

	stages Stages
	parsed Value // the file's parse: (declarations . expression)
	code Value // the desugarer's output
	importNames []Value
	importCodes []Value
}

// Loader gives the text of an import by its path, and false when there is none.
type Loader func(path string) (string, bool)

// Compile compiles a program file, given as text, under the name it is known by. A name that ends in .l2 has its section laid out first, as the bootstrapped compile does. Each import is compiled the same way, with load.
func (s Stages) Compile(text, name string, load Loader) (*Compiled, error) {
	file, err := ParseProgramFile(text)

	if err != nil {
		return nil, err
	}

	section := pipeBytes([]byte(file.Program))

	if strings.HasSuffix(name, ".l2") {
		payload, err := s.run("layout", section, stageFuelLayout)

		if err != nil {
			return nil, err
		}

		if section, err = resultPayload(payload); err != nil {
			return nil, fmt.Errorf("layout: %w", err)
		}
	}

	payload, err := s.run("lex", section, stageFuelLex)

	if err != nil {
		return nil, err
	}

	if section, err = resultPayload(payload); err != nil {
		return nil, fmt.Errorf("lex: %w", err)
	}

	payload, err = s.run("parse", section, stageFuelParse)

	if err != nil {
		return nil, err
	}

	parsed, err := resultPayload(payload)

	if err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}

	var importNames, importCodes, libraries []Value

	for _, imp := range file.Imports {
		impText, ok := load(imp.File)

		if !ok {
			return nil, fmt.Errorf("line %d: cannot find %s", imp.Line, imp.File)
		}

		lib, err := s.Compile(impText, imp.File, load)

		if err != nil {
			return nil, fmt.Errorf("import %s: %w", imp.File, err)
		}

		importNames = append(importNames, pipeBytes([]byte(imp.Name)))
		importCodes = append(importCodes, lib.code)
		libraries = append(libraries, &Cell{Head: pipeBytes([]byte(imp.Name)), Tail: lib.parsed})
	}

	// The checker's request InferT (tag 5): the libraries, then the program. Its result is (text . (errors . (checks . input test))).
	request := &Con{Tag: 5, Payload: &Cell{Head: pipeList(libraries), Tail: parsed}}
	checked := RunBody(s["check"].Body, request, stageFuelCheck)

	if checked.Status != "value" {
		return nil, fmt.Errorf("the checker is %s", checked.Status)
	}

	result, ok := checked.Value.(*Cell)

	if !ok {
		return nil, fmt.Errorf("the checker's result is not a pair")
	}

	errs, ok := result.Tail.(*Cell)

	if !ok {
		return nil, fmt.Errorf("the checker's result has no errors")
	}

	if errs.Head != NIL {
		if first, ok := errs.Head.(*Cell); ok {
			return nil, fmt.Errorf("check: %s", pipeText(first.Head))
		}
	}

	rest, ok := errs.Tail.(*Cell)

	if !ok {
		return nil, fmt.Errorf("the checker's result has no checks")
	}

	payload, err = s.runDesugar(stageInput(pipeList(importNames), parsed, rest.Head, pipeList(importCodes), rest.Tail))

	if err != nil {
		return nil, err
	}

	code, err := resultPayload(payload)

	if err != nil {
		return nil, fmt.Errorf("desugar: %w", err)
	}

	law, err := ConvertLaw(code)

	if err != nil {
		return nil, err
	}

	return &Compiled{
		Law: law,
		stages: s,
		parsed: parsed,
		code: code,
		importNames: importNames,
		importCodes: importCodes,
	}, nil
}

// runDesugar runs the desugarer on its input.
func (s Stages) runDesugar(input Value) (Value, error) {
	return s.run("desugar", input, stageFuelDesugar)
}

// Eval evaluates an expression with the program's declarations and imports in scope, as boot_pipeline.luau's evalExpr does: the expression is read, desugared with the file's declarations, and run on the machine with no input. It gives the value.
func (c *Compiled) Eval(text string) (Value, error) {
	tokens, err := c.stages.run("lex", pipeBytes([]byte(text)), stageFuelLex)

	if err != nil {
		return nil, err
	}

	payload, err := resultPayload(tokens)

	if err != nil {
		return nil, fmt.Errorf("lex: %w", err)
	}

	parsedPayload, err := c.stages.run("parse", payload, stageFuelParse)

	if err != nil {
		return nil, err
	}

	parsed, err := resultPayload(parsedPayload)

	if err != nil {
		return nil, fmt.Errorf("parse: %w", err)
	}

	expr := parsed.(*Cell).Tail
	file := c.parsed.(*Cell)
	testParsed := &Cell{Head: file.Head, Tail: expr}
	noInputCheck := &Con{Tag: 0, Payload: NIL}

	desugared, err := c.stages.runDesugar(stageInput(pipeList(c.importNames), testParsed, NIL, pipeList(c.importCodes), noInputCheck))

	if err != nil {
		return nil, err
	}

	code, err := resultPayload(desugared)

	if err != nil {
		return nil, fmt.Errorf("desugar: %w", err)
	}

	form, err := ConvertForm(code)

	if err != nil {
		return nil, err
	}

	out := RunBody(form, NIL, evalFuel)

	if out.Status != "value" {
		return nil, fmt.Errorf("the expression is %s: %s", out.Status, out.Message)
	}

	return out.Value, nil
}

// Run runs the program on an input, with its fuel: the outcome, as the machine gives it.
func (c *Compiled) Run(input Value, fuel int64) Outcome {
	return Run(c.Law, input, fuel)
}

// StageSources are the sources of the stage programs, by stage, relative to the programs folder (Prototypes/6/L2/programs).
var StageSources = map[string]string{
	"layout": "boot/layout.l2",
	"lex": "boot/lex.l2",
	"parse": "boot/parse.l2",
	"check": "boot/types.l2",
	"desugar": "boot/desugar.l2",
}

// FileLoader reads the files under a programs folder: the imports and the sources of the stages are paths under it.
func FileLoader(root string) Loader {
	if root != "" && !strings.HasSuffix(root, "/") {
		root += "/"
	}

	return func(path string) (string, bool) {
		b, err := os.ReadFile(root + path)

		if err != nil {
			return "", false
		}

		return string(b), true
	}
}

// CompileStages compiles each stage's source with the stages from, which gives the next generation of the stages (the compiler compiling itself, when from is the compiler).
func CompileStages(from Stages, root string) (Stages, error) {
	load := FileLoader(root)
	next := Stages{}

	for name, path := range StageSources {
		text, ok := load(path)

		if !ok {
			return nil, fmt.Errorf("%s: no source", path)
		}

		c, err := from.Compile(text, path, load)

		if err != nil {
			return nil, fmt.Errorf("%s: %w", name, err)
		}

		next[name] = c.Law
	}

	return next, nil
}

// WriteStages writes stages as text, the format ParseStages reads, with the stages in a fixed order.
func WriteStages(s Stages) (string, error) {
	var b strings.Builder

	for _, name := range []string{"layout", "lex", "parse", "check", "desugar"} {
		law := s[name]

		if law == nil {
			return "", fmt.Errorf("no %s stage", name)
		}

		bytes, err := EncodeProgram(law)

		if err != nil {
			return "", fmt.Errorf("%s: %w", name, err)
		}

		fmt.Fprintf(&b, "stage %s %s\n", name, hex.EncodeToString(bytes))
	}

	return b.String(), nil
}

// FormatValue is a value as text: an integer, ~ for nil, [a b] for a list, (a . b) for a pair, and K<tag>(payload) for a constructor. A law is <law>.
func FormatValue(v Value) string {
	switch x := v.(type) {
	case Small:
		return fmt.Sprintf("%d", int64(x))
	case NilT:
		return "~"
	case *Cell:
		var items []string
		var cur Value = x

		for {
			c, ok := cur.(*Cell)

			if !ok {
				break
			}

			items = append(items, FormatValue(c.Head))
			cur = c.Tail
		}

		if cur == NIL {
			return "[" + strings.Join(items, " ") + "]"
		}

		return "(" + FormatValue(x.Head) + " . " + FormatValue(x.Tail) + ")"
	case *Con:
		return fmt.Sprintf("K%d(%s)", x.Tag, FormatValue(x.Payload))
	case *Law:
		return "<law>"
	}

	return fmt.Sprintf("<%T>", v)
}
