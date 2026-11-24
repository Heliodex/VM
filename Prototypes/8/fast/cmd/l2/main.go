// Command l2 is the L2 driver of Prototype 8: it compiles an L2 program with the compiler the machine runs (the stage programs of testdata/stages.txt), and runs it on the Go machine.
//
//	l2 run [-root dir] file.l2           run the file's tests; each prints its value
//	l2 eval [-root dir] file.l2 expr     evaluate an expression with the file's declarations in scope
//	l2 seed [-root dir] [-out file]      compile the compiler's stages with the seed, and check that the result is a fixed point; write the stages
//
// The root is the programs folder, which imports and the compiler's sources are paths under (default ../l2/programs/ from Prototypes/8/fast).
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
	fmt.Fprintln(os.Stderr, "       l2 eval [-root dir] file.l2 expr")
	fmt.Fprintln(os.Stderr, "       l2 seed [-root dir] [-out file]")
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
	case "seed":
		seed(args)
	default:
		usage()
	}
}

// compile compiles a program file under the root, with the seed stages.
func compile(root, file string) (*fast.Compiled, string) {
	stages, err := fast.SeedStages()

	if err != nil {
		fail(err)
	}

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

func fail(err error) {
	fmt.Fprintln(os.Stderr, "l2:", err)
	os.Exit(1)
}

func run(args []string) {
	fs := flag.NewFlagSet("run", flag.ExitOnError)
	root := fs.String("root", defaultRoot, "the programs folder")
	fs.Parse(args)

	if fs.NArg() != 1 {
		usage()
	}

	c, text := compile(*root, fs.Arg(0))
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
	fs.Parse(args)

	if fs.NArg() != 2 {
		usage()
	}

	c, _ := compile(*root, fs.Arg(0))
	v, err := c.Eval(fs.Arg(1))

	if err != nil {
		fail(err)
	}

	fmt.Println(fast.FormatValue(v))
}

func seed(args []string) {
	fs := flag.NewFlagSet("seed", flag.ExitOnError)
	root := fs.String("root", defaultRoot, "the programs folder")
	out := fs.String("out", "", "the file to write the stages to (stdout when empty)")
	fs.Parse(args)

	stages, err := fast.SeedStages()

	if err != nil {
		fail(err)
	}

	// The generation the seed gives, then the one that gives: the compiler's fixed point is the one that gives itself.
	next, err := fast.CompileStages(stages, *root)

	if err != nil {
		fail(err)
	}

	again, err := fast.CompileStages(next, *root)

	if err != nil {
		fail(err)
	}

	text, err := fast.WriteStages(next)

	if err != nil {
		fail(err)
	}

	againText, err := fast.WriteStages(again)

	if err != nil {
		fail(err)
	}

	if text != againText {
		fail(fmt.Errorf("the stages are not a fixed point: the next generation differs"))
	}

	if *out == "" {
		fmt.Print(text)

		return
	}

	if err := os.WriteFile(*out, []byte(text), 0o644); err != nil {
		fail(err)
	}

	fmt.Fprintf(os.Stderr, "l2: wrote the stages to %s (a fixed point: the next generation is the same)\n", *out)
}
