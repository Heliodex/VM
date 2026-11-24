// Command l2 is the L2 driver of Prototype 8: it compiles L2 programs with the compiler the machine runs (its stages, in the seed), and runs them on the Go machine. Compiled programs and values are P8 files (Prototypes/8/FORMAT.md).
//
//	l2 run [-root dir] file.l2                  run the file's tests; each prints its value
//	l2 eval [-root dir] [-o out.p8] file.l2 expr  evaluate an expression with the file's declarations in scope; -o writes the value as a P8 file
//	l2 build [-root dir] -o out.p8 file.l2      compile a program file to a P8 file
//	l2 exec file.p8 [input.p8]                  run a compiled program on an input (a P8 value file; nil when absent)
//	l2 seed [-root dir] [-compiler c.p8] -out next.p8  compile the compiler's stage sources with a compiler, and write the result as the next generation
//
// Every command that compiles takes -compiler c.p8: the compiler to use, a P8 file of the five stages (default: the seed, testdata/seed.p8). Flags come before the file arguments. The root is the programs folder, which imports and the compiler's sources are paths under (default ../l2/programs/ from Prototypes/8/fast).
//
// Iterating on the language: edit the stage sources under the root, then compile them with the current compiler (l2 seed -compiler current.p8 -out next.p8), test with the next compiler (l2 run -compiler next.p8 file.l2), and repeat from next.p8 until seed reports a fixed point.
package main

import (
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"proto8fast"
)

const defaultRoot = "../l2/programs/"

func usage() {
	fmt.Fprintln(os.Stderr, "usage: l2 run [-root dir] file.l2")
	fmt.Fprintln(os.Stderr, "       l2 eval [-root dir] [-o out.p8] file.l2 expr")
	fmt.Fprintln(os.Stderr, "       l2 build [-root dir] -o out.p8 file.l2")
	fmt.Fprintln(os.Stderr, "       l2 exec file.p8 [input.p8]")
	fmt.Fprintln(os.Stderr, "       l2 seed [-root dir] -out file.p8 [-generation n]")
	os.Exit(2)
}

func main() {
	if len(os.Args) < 2 {
		usage()
	}

	args := os.Args[2:]

	switch os.Args[1] {
	case "run":
		run(args)
	case "eval":
		eval(args)
	case "build":
		build(args)
	case "exec":
		exec(args)
	case "seed":
		seed(args)
	default:
		usage()
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "l2:", err)
	os.Exit(1)
}

// loadCompiler reads the compiler from a P8 file, or the seed when path is empty, and the generation it records.
func loadCompiler(path string) (fast.Stages, uint64) {
	if path == "" {
		stages, err := fast.SeedStages()

		if err != nil {
			fail(err)
		}

		gen, err := fast.SeedGeneration()

		if err != nil {
			fail(err)
		}

		return stages, gen
	}

	data, err := os.ReadFile(path)

	if err != nil {
		fail(err)
	}

	stages, gen, err := fast.ReadCompiler(data)

	if err != nil {
		fail(fmt.Errorf("%s: %w", path, err))
	}

	return stages, gen
}

// compile compiles a program file under the root, with the stages.
func compile(stages fast.Stages, root, file string) (*fast.Compiled, string) {
	name, err := filepath.Rel(root, file)

	if err != nil || strings.HasPrefix(name, "..") {
		name = file
	}

	text, err := os.ReadFile(file)

	if err != nil {
		fail(err)
	}

	c, err := stages.Compile(string(text), filepath.ToSlash(name), fast.FileLoader(root))

	if err != nil {
		fail(err)
	}

	return c, string(text)
}

// writeBundle writes a bundle as a P8 file.
func writeBundle(path string, b fast.Bundle) {
	data, err := b.Encode()

	if err != nil {
		fail(err)
	}

	if err := os.WriteFile(path, data, 0o644); err != nil {
		fail(err)
	}
}

// readBundle reads a P8 file.
func readBundle(path string) fast.Bundle {
	data, err := os.ReadFile(path)

	if err != nil {
		fail(err)
	}

	b, err := fast.DecodeBundle(data)

	if err != nil {
		fail(fmt.Errorf("%s: %w", path, err))
	}

	return b
}

func run(args []string) {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	root := fs.String("root", defaultRoot, "the programs folder")
	compiler := fs.String("compiler", "", "a P8 file holding the compiler (default: the seed)")
	fs.Parse(args)

	if fs.NArg() != 1 {
		usage()
	}

	stages, _ := loadCompiler(*compiler)
	c, text := compile(stages, *root, fs.Arg(0))
	file, err := fast.ParseProgramFile(text)

	if err != nil {
		fail(err)
	}

	failures := 0

	for _, test := range file.Tests {
		input, err := c.Eval(test.Input)

		if err != nil {
			fmt.Printf("line %d: input %s: %v\n", test.Line, test.Input, err)
			failures++

			continue
		}

		want, err := c.Eval(test.Output)

		if err != nil {
			fmt.Printf("line %d: output %s: %v\n", test.Line, test.Output, err)
			failures++

			continue
		}

		out := c.Run(input, 1<<40)

		if out.Status != "value" {
			fmt.Printf("line %d: %s: %s\n", test.Line, out.Status, out.Message)
			failures++

			continue
		}

		if fast.FormatValue(out.Value) != fast.FormatValue(want) {
			fmt.Printf("line %d: %s, the test expects %s\n", test.Line, fast.FormatValue(out.Value), fast.FormatValue(want))
			failures++

			continue
		}

		fmt.Printf("line %d: %s\n", test.Line, fast.FormatValue(out.Value))
	}

	fmt.Printf("%d of %d tests pass\n", len(file.Tests)-failures, len(file.Tests))

	if failures > 0 {
		os.Exit(1)
	}
}

func eval(args []string) {
	fs := flag.NewFlagSet("eval", flag.ExitOnError)
	root := fs.String("root", defaultRoot, "the programs folder")
	out := fs.String("o", "", "write the value to this P8 file")
	compiler := fs.String("compiler", "", "a P8 file holding the compiler (default: the seed)")
	fs.Parse(args)

	if fs.NArg() != 2 {
		usage()
	}

	stages, _ := loadCompiler(*compiler)
	c, _ := compile(stages, *root, fs.Arg(0))
	v, err := c.Eval(fs.Arg(1))

	if err != nil {
		fail(err)
	}

	if *out != "" {
		b, err := fast.ValueBundle(v)

		if err != nil {
			fail(err)
		}

		writeBundle(*out, b)

		return
	}

	fmt.Println(fast.FormatValue(v))
}

func build(args []string) {
	fs := flag.NewFlagSet("build", flag.ExitOnError)
	root := fs.String("root", defaultRoot, "the programs folder")
	out := fs.String("o", "", "the P8 file to write")
	compiler := fs.String("compiler", "", "a P8 file holding the compiler (default: the seed)")
	fs.Parse(args)

	if fs.NArg() != 1 || *out == "" {
		usage()
	}

	stages, gen := loadCompiler(*compiler)
	c, _ := compile(stages, *root, fs.Arg(0))

	b, err := fast.ProgramBundle(c.Law, gen)

	if err != nil {
		fail(err)
	}

	writeBundle(*out, b)
}

func exec(args []string) {
	if len(args) < 1 || len(args) > 2 {
		usage()
	}

	program := readBundle(args[0])
	payload, ok := program.Entry("program")

	if !ok {
		fail(fmt.Errorf("%s has no program entry", args[0]))
	}

	law, err := fast.DecodeProgram(payload)

	if err != nil {
		fail(fmt.Errorf("%s: %w", args[0], err))
	}

	var input fast.Value = fast.NIL

	if len(args) == 2 {
		value := readBundle(args[1])
		payload, ok := value.Entry("value")

		if !ok {
			fail(fmt.Errorf("%s has no value entry", args[1]))
		}

		input, err = fast.DecodeValue(payload)

		if err != nil {
			fail(fmt.Errorf("%s: %w", args[1], err))
		}
	}

	out := fast.Run(law, input, 1<<40)

	if out.Status != "value" {
		fmt.Printf("%s: %s\n", out.Status, out.Message)
		os.Exit(1)
	}

	fmt.Println(fast.FormatValue(out.Value))
}

func seed(args []string) {
	fs := flag.NewFlagSet("seed", flag.ExitOnError)
	root := fs.String("root", defaultRoot, "the programs folder")
	out := fs.String("out", "", "the P8 file to write the next generation of the compiler to")
	compiler := fs.String("compiler", "", "a P8 file holding the compiler that compiles the sources (default: the seed)")
	fs.Parse(args)

	if fs.NArg() != 0 || *out == "" {
		usage()
	}

	stages, gen := loadCompiler(*compiler)

	// The stages the compiler gives from the sources, and then the stages that those give: the compiler is a fixed point when the two are the same.
	next, err := fast.CompileStages(stages, *root)

	if err != nil {
		fail(err)
	}

	again, err := fast.CompileStages(next, *root)

	if err != nil {
		fail(err)
	}

	fixed, differ, err := fast.SameStages(next, again)

	if err != nil {
		fail(err)
	}

	b, err := fast.StagesBundle(next, gen+1)

	if err != nil {
		fail(err)
	}

	writeBundle(*out, b)

	if fixed {
		fmt.Fprintf(os.Stderr, "l2: wrote generation %d to %s; it is a fixed point (the next generation has the same programs)\n", gen+1, *out)

		return
	}

	fmt.Fprintf(os.Stderr, "l2: wrote generation %d to %s; it is not a fixed point yet (the next generation differs in %s). Run seed again with -compiler %s to continue.\n", gen+1, *out, strings.Join(differ, ", "), *out)
}
