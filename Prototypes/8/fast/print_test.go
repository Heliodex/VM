package fast

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// splitProgram splits a program file into the text before its program section (its description, imports, and the --- that opens the program), the program section, and the text after it (the --- that closes it, and the tests). It fails when the file does not have four sections.
func splitProgram(text string) (head, program, tail string, ok bool) {
	lines := strings.Split(text, "\n")

	var seps []int

	for i, l := range lines {
		if l == "---" {
			seps = append(seps, i)
		}
	}

	if len(seps) != 3 {
		return "", "", "", false
	}

	head = strings.Join(lines[:seps[1]+1], "\n") + "\n"
	program = strings.Join(lines[seps[1]+1:seps[2]], "\n") + "\n"
	tail = strings.Join(lines[seps[2]:], "\n")

	return head, program, tail, true
}

// printFile prints a program file's program section in the indented form, and checks it: the printed file must compile to the same program as the original. It gives the new text of the file, or an error.
func printFile(stages Stages, path, text string) (string, error) {
	head, program, tail, ok := splitProgram(text)
	if !ok {
		return "", errNotFourSections
	}

	parsed, err := stages.ParseSection(program)
	if err != nil {
		return "", err
	}

	printed, err := PrintSection(parsed)
	if err != nil {
		return "", err
	}

	return head + printed + tail, nil
}

var errNotFourSections = os.ErrInvalid

// programLaw is the encoding of a file's compiled program, the law the machine runs.
func programLaw(t *testing.T, stages Stages, path, text string) string {
	t.Helper()

	c, err := stages.Compile(text, path, FileLoader(programsRoot))
	if err != nil {
		t.Fatalf("%s: %v", path, err)
	}

	b, err := EncodeProgram(c.Law)
	if err != nil {
		t.Fatalf("%s: %v", path, err)
	}

	return string(b)
}

// TestPrintProgramFiles prints each program file in the indented form and checks that it compiles to the same program. With PRINT_MIGRATE=1 the printed files are written, which is the migration.
func TestPrintProgramFiles(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	var files []string

	err = filepath.Walk(programsRoot, func(path string, info os.FileInfo, err error) error {
		if err == nil && !info.IsDir() && strings.HasSuffix(path, ".l2") {
			files = append(files, path)
		}

		return err
	})
	if err != nil {
		t.Fatal(err)
	}

	migrate := os.Getenv("PRINT_MIGRATE") == "1"
	failed := 0

	for _, path := range files {
		raw, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}

		text := string(raw)

		printed, err := printFile(stages, path, text)
		if err != nil {
			failed++
			t.Errorf("%s: print: %v", path, err)
			continue
		}

		if programLaw(t, stages, path, printed) != programLaw(t, stages, path, text) {
			failed++
			t.Errorf("%s: the printed file compiles to a different program", path)
			continue
		}

		if out := os.Getenv("PRINT_OUT"); out != "" {
			rel, _ := filepath.Rel(programsRoot, path)
			dst := filepath.Join(out, rel)
			if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(dst, []byte(printed), 0o644); err != nil {
				t.Fatal(err)
			}
		}

		if migrate && printed != text {
			if err := os.WriteFile(path, []byte(printed), 0o644); err != nil {
				t.Fatal(err)
			}
		}
	}

	t.Logf("%d program files printed; %d failed", len(files), failed)
}
