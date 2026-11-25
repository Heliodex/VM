package fast

import "testing"

// runProgramText compiles a program file given as text (a .l2 file, so its program section is laid out), and runs each of its tests. It returns one message for each test that fails.
func runProgramText(t *testing.T, text string) []string {
	t.Helper()

	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	file, err := ParseProgramFile(text)
	if err != nil {
		t.Fatalf("the file: %v", err)
	}

	c, err := stages.Compile(text, "probe.l2", nil)
	if err != nil {
		t.Fatalf("compile: %v", err)
	}

	var failures []string

	for _, test := range file.Tests {
		input, err := c.Eval(test.Input)
		if err != nil {
			failures = append(failures, test.Input+": "+err.Error())
			continue
		}

		want, err := c.Eval(test.Output)
		if err != nil {
			failures = append(failures, test.Output+": "+err.Error())
			continue
		}

		out := c.Run(input, test.Fuel)
		if out.Status != "value" || FormatValue(out.Value) != FormatValue(want) {
			failures = append(failures, test.Input+": got "+out.Status+" "+FormatValue(out.Value)+", want "+FormatValue(want))
		}
	}

	return failures
}

// A one-line if is valid as the last line of a block, and as an argument, as its bracketed form is.
func TestOneLineIf(t *testing.T) {
	probes := []string{
		"Probe: a one-line if as the last line of a block.\n---\n---\nfn x\n\tlet y = + x 1\n\tif (= y 1) 10 20\n---\n0 => 10 fuel 1000\n1 => 20 fuel 1000\n",
		"Probe: a one-line if as an argument.\n---\n---\nfn x\n\t+\n\t\tx\n\t\tif (= x 0) 5 6\n---\n0 => 5 fuel 1000\n1 => 7 fuel 1000\n",
		"Probe: a block if still works.\n---\n---\nfn x\n\tif (= x 0)\n\t\t5\n\telse\n\t\t6\n---\n0 => 5 fuel 1000\n1 => 6 fuel 1000\n",
	}

	for _, p := range probes {
		if f := runProgramText(t, p); len(f) != 0 {
			t.Fatalf("%q: failures %v", p[:30], f)
		}
	}
}
