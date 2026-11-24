package fast

import (
	_ "embed"
	"fmt"
	"os"
	"slices"
	"strings"
	"sync"
)

type (
	// Loader gives the text of an import by its path, and false when there is none.
	Loader func(path string) (string, bool)

	// Stages are the stage programs of the compiler, by name: layout, lex, parse, check and desugar.
	Stages map[string]*Law

	// Compiled is a program file compiled by the pipeline: its law, and what its tests need to be evaluated with it.
	Compiled struct {
		Law *Law
		stages Stages
		parsed, // the file's parse: (declarations . expression)
		code Value // the desugarer's output
		importNames, importCodes []Value
	}
)

const (
	evalFuel = int64(1 << 40)
	stageFuelCheck = int64(1e10)
	stageFuelDesugar = int64(1e11)

	// The fuel of each stage, as the corpus build gives it (corpus_test.go).
	stageFuelLayout = int64(1e10)
	stageFuelLex = int64(1e8)
	stageFuelParse = int64(5e8)
)

var (
	// StageSources are the sources of the stage programs, by stage, relative to the programs folder (Prototypes/8/l2/programs).
	StageSources = map[string]string{
		"check": "boot/types.l2",
		"desugar": "boot/desugar.l2",
		"layout": "boot/layout.l2",
		"lex": "boot/lex.l2",
		"parse": "boot/parse.l2",
	}
	seedBundle Bundle
	seedErr error
	seedOnce sync.Once

	// The pipeline (Prototype 8): the L2 compiler, run on the machine, and the program it gives, run on the machine.
	//
	// The compiler is five stage programs, each a law: the layout, the tokenizer, the parser, the checker and the desugarer (Prototypes/8/l2/programs/boot). A program file is compiled by running them in turn, as boot_pipeline.luau does: its imports first, each compiled the same way; then the program's own section. The desugarer's output is a Code value, which converter.go turns into the law the machine runs.
	//
	// The stage programs are the seed (testdata/seed.p8, a P8 file, Prototypes/8/FORMAT.md): the compiler's second generation, compiled from the stage sources. A stage source compiled by the seed gives the same bytes as the seed, which is the fixed point that pipeline_test.go checks.

	//go:embed testdata/seed.p8
	seedSource []byte
	seedStages Stages
)

// Run runs the program on an input, with its fuel: the outcome, as the machine gives it.
func (c *Compiled) Run(input Value, fuel int64) Outcome {
	return Run(c.Law, input, fuel)
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

// FormatValue is a value as text: an integer, ~ for nil, [a b] for a list, (a . b) for a pair, and K<tag>(payload) for a constructor. A law is <law>.
func FormatValue(v Value) string {
	switch x := v.(type) {
	case *Cell:
		var (
			items []string
			cur Value = x
		)

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
	case NilT:
		return "~"
	case Small:
		return fmt.Sprintf("%d", int64(x))
	}

	return fmt.Sprintf("<%T>", v)
}

// FormatCode is a Code value (the desugarer's output) in the notation of the parity run (measure/desugar_run.luau's showCode): Q n, N, V i, (L body), (A f a), (C h t), (I n e), (IF c t e), (P e), (F e), (K tag e), (T e), (Y e), (R tag a) or (R tag a b).
func FormatCode(v Value) string {
	con, ok := v.(*Con)
	if !ok {
		return fmt.Sprintf("<%T>", v)
	}

	pair := func() *Cell {
		c, _ := con.Payload.(*Cell)

		return c
	}

	switch con.Tag {
	case 0:
		return fmt.Sprintf("Q%s", FormatValue(con.Payload))
	case 1:
		return "N"
	case 2:
		return fmt.Sprintf("V%s", FormatValue(con.Payload))
	case 3:
		return "(L " + FormatCode(con.Payload) + ")"
	case 4:
		p := pair()

		return "(A " + FormatCode(p.Head) + " " + FormatCode(p.Tail) + ")"
	case 5:
		p := pair()

		return "(C " + FormatCode(p.Head) + " " + FormatCode(p.Tail) + ")"
	case 6:
		p := pair()

		return "(I " + FormatValue(p.Head) + " " + FormatCode(p.Tail) + ")"
	case 7:
		p := pair()
		rest := p.Tail.(*Cell)

		return "(IF " + FormatCode(p.Head) + " " + FormatCode(rest.Head) + " " + FormatCode(rest.Tail) + ")"
	case 8:
		return "(P " + FormatCode(con.Payload) + ")"
	case 9:
		return "(F " + FormatCode(con.Payload) + ")"
	case 10:
		p := pair()

		return "(K " + FormatValue(p.Head) + " " + FormatCode(p.Tail) + ")"
	case 11:
		return "(T " + FormatCode(con.Payload) + ")"
	case 12:
		return "(Y " + FormatCode(con.Payload) + ")"
	case 13:
		p := pair()

		return "(R " + FormatValue(p.Head) + " " + FormatCode(p.Tail) + ")"
	}

	p := pair()
	rest := p.Tail.(*Cell)

	return "(R " + FormatValue(p.Head) + " " + FormatCode(rest.Head) + " " + FormatCode(rest.Tail) + ")"
}

// SeedBundle is the seed as a P8 file (testdata/seed.p8, embedded in the build).
func SeedBundle() (Bundle, error) {
	seedOnce.Do(func() {
		seedBundle, seedErr = DecodeBundle(seedSource)
		if seedErr != nil {
			return
		}

		seedStages, seedErr = StagesFromBundle(seedBundle)
	})

	return seedBundle, seedErr
}

// SeedGeneration is the generation of the seed's stages: the compiler's second generation (TestSeedGenerations).
func SeedGeneration() (uint64, error) {
	b, err := SeedBundle()
	if err != nil {
		return 0, err
	}

	return b.Generation, nil
}

// SeedStages are the stage programs of the seed.
func SeedStages() (Stages, error) {
	if _, err := SeedBundle(); err != nil {
		return nil, err
	}

	return seedStages, nil
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

// runDesugar runs the desugarer on its input.
func (s Stages) runDesugar(input Value) (Value, error) {
	return s.run("desugar", input, stageFuelDesugar)
}

// canonVars renames the type variables of a message by where they first appear: ?12 and ?7 become ?v1 and ?v2, so two checkers that number them differently agree.
func canonVars(s string) string {
	names := map[string]string{}

	var b strings.Builder

	for i := 0; i < len(s); i++ {
		if s[i] != '?' {
			b.WriteByte(s[i])
			continue
		}

		j := i + 1

		for j < len(s) && s[j] >= '0' && s[j] <= '9' {
			j++
		}

		if j == i+1 {
			b.WriteByte('?')
			continue
		}

		id := s[i+1 : j]
		if names[id] == "" {
			names[id] = fmt.Sprintf("?v%d", len(names)+1)
		}

		b.WriteString(names[id])

		i = j - 1
	}

	return b.String()
}

// pipeList is a list of values, in order.
func pipeList(items []Value) Value {
	var v Value = NIL

	for _, item := range slices.Backward(items) {
		v = &Cell{
			Head: item,
			Tail: v,
		}
	}

	return v
}

// pipeBytes is a list of bytes, as the stages read text.
func pipeBytes(b []byte) Value {
	items := make([]Value, len(b))

	for i, c := range b {
		items[i] = Small(c)
	}

	return pipeList(items)
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

// CheckText is the outcome of the pure checker (request Infer, tag 3) on a program's source, read as the parity run reads it: the source is tokenized and parsed as it is, and the outcome is "type <t>" or "error <messages>", with the type variables renamed by where they first appear. ok is false when the parser refuses the source, or when a form is not handled yet.
func (s Stages) CheckText(src string) (string, bool) {
	tokens, err := s.run("lex", pipeBytes([]byte(src)), stageFuelLex)
	if err != nil {
		return "", false
	}

	tokenPayload, err := resultPayload(tokens)
	if err != nil {
		return "", false
	}

	parsed, err := s.run("parse", tokenPayload, stageFuelParse)
	if err != nil {
		return "", false
	}

	program, err := resultPayload(parsed)
	if err != nil {
		return "", false
	}

	checked := RunBody(s["check"].Body, &Con{
		Tag: 3,
		Payload: program,
	}, stageFuelCheck)
	if checked.Status != "value" {
		return "the checker " + checked.Status, true
	}

	out, ok := checked.Value.(*Cell)
	if !ok {
		return "", false
	}

	text := pipeText(out.Head)
	errsCell, ok := out.Tail.(*Cell)

	if !ok {
		return "", false
	}

	var errs []string

	for cur := errsCell.Head; ; {
		c, ok := cur.(*Cell)
		if !ok {
			break
		}

		errs = append(errs, pipeText(c.Head))
		cur = c.Tail
	}

	if strings.Contains(text, "this form is not checked yet") {
		return "", false
	}

	for _, e := range errs {
		if strings.Contains(e, "this form is not checked yet") {
			return "", false
		}
	}

	if len(errs) == 0 {
		return "type " + canonVars(text), true
	}

	return "error " + canonVars(strings.Join(errs, "\n")), true
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
	noInputCheck := &Con{
		Tag: 0,
		Payload: NIL,
	}
	testParsed := &Cell{
		Head: file.Head,
		Tail: expr,
	}

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
		libraries = append(libraries, &Cell{
			Head: pipeBytes([]byte(imp.Name)),
			Tail: lib.parsed,
		})
	}

	// The checker's request InferT (tag 5): the libraries, then the program. Its result is (text . (errors . (checks . input test))).
	request := &Con{
		Tag: 5,
		Payload: &Cell{
			Head: pipeList(libraries),
			Tail: parsed,
		},
	}
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

// DesugarText is the outcome of the desugarer on a source, in the notation of the parity run: "value <code>" or "error <message>". The source is parsed as it is. With checked, it is checked first (request InferT with no libraries), and its check nodes and input test go to the desugarer; otherwise the desugarer gets no checks and no input test, and the imports are given the integer values (their machine expressions). ok is false when the parser refuses the source, or the checker does.
func (s Stages) DesugarText(src string, imports []string, values []int64, checked bool) (string, bool) {
	tokens, err := s.run("lex", pipeBytes([]byte(src)), stageFuelLex)
	if err != nil {
		return "", false
	}

	tokenPayload, err := resultPayload(tokens)
	if err != nil {
		return "", false
	}

	parsedOut, err := s.run("parse", tokenPayload, stageFuelParse)
	if err != nil {
		return "", false
	}

	parsed, err := resultPayload(parsedOut)
	if err != nil {
		return "", false
	}

	var checks, inputTest Value = NIL, &Con{
		Tag: 0,
		Payload: NIL,
	}

	if checked {
		request := &Con{
			Tag: 5,
			Payload: &Cell{
				Head: NIL,
				Tail: parsed,
			},
		}
		result := RunBody(s["check"].Body, request, stageFuelCheck)

		if result.Status != "value" {
			return "", false
		}

		pair, ok := result.Value.(*Cell)
		if !ok {
			return "", false
		}

		errs, ok := pair.Tail.(*Cell)
		if !ok || errs.Head != NIL {
			return "", false
		}

		rest, ok := errs.Tail.(*Cell)
		if !ok {
			return "", false
		}

		checks, inputTest = rest.Head, rest.Tail
	}

	names := make([]Value, len(imports))

	for i, n := range imports {
		names[i] = pipeBytes([]byte(n))
	}

	codes := make([]Value, len(values))

	for i, v := range values {
		codes[i] = &Con{
			Tag: 0,
			Payload: Small(v),
		}
	}

	out, err := s.runDesugar(stageInput(pipeList(names), parsed, checks, pipeList(codes), inputTest))
	if err != nil {
		return "", false
	}

	con, ok := out.(*Con)
	if !ok {
		return "", false
	}

	if con.Tag == 0 {
		return "value " + FormatCode(con.Payload), true
	}

	return "error " + pipeText(con.Payload), true
}
