package fast

import (
	"fmt"
	"strconv"
	"strings"
)

// The L2 program file (Prototypes/6/L2/programfile.luau): four sections, separated by three lines that hold only ---. The first is a header, the second the imports (name = path), the third the program, and the fourth the tests. A test is an input, =>, an output, and fuel; it may span lines that start with a space or a tab.
//
// The program section is text, as the file has it: the compiler lays it out (a file named .l2 is indented).

// ProgramImport is an import: its name in the program, and the path of its file.
type ProgramImport struct {
	Line int
	Name string
	File string
}

// ProgramTest is a test: its input and its output (expressions of the program), its fuel, and its outcome: value, error, out_of_fuel or not_data.
type ProgramTest struct {
	Line int
	Input string
	Output string
	Outcome string
	Fuel int64
}

// ProgramFile is a program file split into its sections.
type ProgramFile struct {
	Header string
	Imports []ProgramImport
	Program string
	Tests []ProgramTest
}

// ParseProgramFile splits a program file into its sections, as programfile.luau's parse does.
func ParseProgramFile(text string) (*ProgramFile, error) {
	raw := strings.Split(text+"\n", "\n")
	lines := make([]string, len(raw))

	for i, l := range raw {
		lines[i] = strings.TrimSuffix(l, "\r")
	}

	var separators []int

	for i, l := range lines {
		if strings.TrimSpace(l) == "---" {
			separators = append(separators, i)
		}
	}

	if len(separators) != 3 {
		return nil, fmt.Errorf("a program file has four sections, separated by three lines of ---, but this one has %d such lines", len(separators))
	}

	first, second, third := separators[0], separators[1], separators[2]
	file := &ProgramFile{Header: strings.Join(lines[:first], "\n")}
	seen := map[string]bool{}

	for i := first + 1; i < second; i++ {
		line := strings.TrimSpace(lines[i])

		if line == "" {
			continue
		}

		imp, err := parseProgramImport(line, i+1)

		if err != nil {
			return nil, err
		}

		if seen[imp.Name] {
			return nil, fmt.Errorf("line %d: %s is imported twice", i+1, imp.Name)
		}

		seen[imp.Name] = true
		file.Imports = append(file.Imports, imp)
	}

	// A test starts on a line of its own; the lines after it that start with a space or a tab continue it.
	for i := third + 1; i < len(lines); {
		if strings.TrimSpace(lines[i]) == "" {
			i++

			continue
		}

		start := i
		parts := []string{lines[i]}
		i++

		for i < len(lines) && strings.TrimSpace(lines[i]) != "" && (lines[i][0] == ' ' || lines[i][0] == '\t') {
			parts = append(parts, lines[i])
			i++
		}

		test, err := parseProgramTest(strings.Join(parts, "\n"), start+1)

		if err != nil {
			return nil, err
		}

		file.Tests = append(file.Tests, test)
	}

	if len(file.Tests) == 0 {
		return nil, fmt.Errorf("a program file needs at least one test")
	}

	file.Program = strings.Join(lines[second+1:third], "\n")

	return file, nil
}

// parseProgramImport reads name = path.
func parseProgramImport(text string, line int) (ProgramImport, error) {
	name, file, ok := strings.Cut(text, "=")
	name = strings.TrimSpace(name)
	file = strings.TrimSpace(file)

	if !ok || name == "" || file == "" || strings.ContainsAny(name+file, " \t") {
		return ProgramImport{}, fmt.Errorf("line %d: an import is name = path, but this is %s", line, text)
	}

	return ProgramImport{Line: line, Name: name, File: file}, nil
}

// parseProgramTest reads input => output fuel n.
func parseProgramTest(text string, line int) (ProgramTest, error) {
	arrow := strings.Index(text, " => ")

	if arrow < 0 {
		return ProgramTest{}, fmt.Errorf("line %d: a test needs => between its input and its output", line)
	}

	input := strings.TrimSpace(text[:arrow])
	rest := text[arrow+4:]
	fuelAt := strings.Index(rest, " fuel ")

	if fuelAt < 0 {
		return ProgramTest{}, fmt.Errorf("line %d: a test needs fuel and a number of steps after its output", line)
	}

	output := strings.TrimSpace(rest[:fuelAt])
	fuelText := strings.TrimSpace(rest[fuelAt+6:])
	fuel, err := strconv.ParseInt(fuelText, 10, 64)

	if err != nil || fuel <= 0 {
		return ProgramTest{}, fmt.Errorf("line %d: fuel must be a whole number above zero, not %s", line, fuelText)
	}

	test := ProgramTest{Line: line, Input: input, Output: output, Outcome: "value", Fuel: fuel}

	switch output {
	case "error", "out_of_fuel", "not_data":
		test.Outcome = output
		test.Output = ""
	}

	return test, nil
}
