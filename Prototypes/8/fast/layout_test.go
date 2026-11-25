package fast

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// layoutInput is one input of the layout parity run: its name, and its source.
type layoutInput struct {
	name, src string
}

// layoutSnippets are the inputs the generated ones did not cover (gen/layout.luau).
var layoutSnippets = []string{
	"let lineErr = fn (ln msg)\n\tErr msg\nlet isLowerB = fn c\n\tc\nfn x\n\tx",
	"let f = fn x\n\tErr (g x)\nb",
	"fn x\n\tOk 1",
	"let f = fn x\n\tOk x\nf 1",
}

// copyWithout is the lines with line i (0-based) replaced, or removed when replacement is nil.
func copyWithout(lines []string, i int, replacement *string) string {
	out := make([]string, 0, len(lines))

	for j, l := range lines {
		if j == i {
			if replacement != nil {
				out = append(out, *replacement)
			}

			continue
		}

		out = append(out, l)
	}

	return strings.Join(out, "\n")
}

// programSection is the lines of a program file's program section: between its second and third lines of ---.
func programSection(text string) []string {
	lines := strings.Split(text, "\n")

	var seps []int

	for i, l := range lines {
		if l == "---" {
			seps = append(seps, i)
		}
	}

	if len(seps) != 3 {
		return nil
	}

	return lines[seps[1]+1 : seps[2]]
}

// layoutInputs rebuilds the inputs of the layout parity run from the program files under root, as gen/layout.luau generates them: the program section of every .l2 file, its copies with a line deleted, dedented or indented (at most 40 lines of a long file, spread evenly), and the snippets.
func layoutInputs(t *testing.T, root string) (out []layoutInput) {
	t.Helper()

	const maxLines = 40

	var names []string

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}

		if !d.IsDir() && strings.HasSuffix(d.Name(), ".l2") {
			rel, err := filepath.Rel(root, path)
			if err != nil {
				return err
			}

			names = append(names, filepath.ToSlash(rel))
		}

		return nil
	})
	if err != nil {
		t.Fatal(err)
	}

	sort.Strings(names)

	for _, name := range names {
		text, err := os.ReadFile(root + name)
		if err != nil {
			t.Fatal(err)
		}

		lines := programSection(string(text))
		if len(lines) == 0 {
			continue
		}

		out = append(out, layoutInput{
			name: name + " as written",
			src: strings.Join(lines, "\n"),
		})
		stride := max((len(lines)+maxLines-1)/maxLines, 1)

		for i := 1; i <= len(lines); i += stride {
			l := lines[i-1]
			out = append(out, layoutInput{
				name: fmt.Sprintf("%s line %d deleted", name, i),
				src: copyWithout(lines, i-1, nil),
			})

			if strings.HasPrefix(l, "\t") {
				dedented := l[1:]
				out = append(out, layoutInput{
					name: fmt.Sprintf("%s line %d dedented", name, i),
					src: copyWithout(lines, i-1, &dedented),
				})
			}

			indented := "\t" + l
			out = append(out, layoutInput{
				name: fmt.Sprintf("%s line %d indented", name, i),
				src: copyWithout(lines, i-1, &indented),
			})
		}
	}

	for i, src := range layoutSnippets {
		out = append(out, layoutInput{
			name: fmt.Sprintf("snippet %d", i+1),
			src: src,
		})
	}

	return
}

// TestLayoutParity rebuilds the inputs of the layout parity run from the program files, and checks the bootstrapped layout stage's outcome on each against the Luau layout's, as testdata/layout.txt gives it: the SHA-256 of a text, or the message of an error (gen/layout.luau, layout_digest.py). 1,284 inputs.
func TestLayoutParity(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	inputs := layoutInputs(t, programsRoot)

	f, err := os.Open("testdata/layout.txt")
	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	sc := bufio.NewScanner(f)
	n, agree := 0, 0

	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 4 || fields[0] != "layout" {
			t.Fatalf("layout.txt: a line that is not a layout line: %q", sc.Text())
		}

		if n >= len(inputs) {
			t.Fatalf("layout.txt has more inputs than the program files give (%d)", len(inputs))
		}

		nameBytes, err := hex.DecodeString(fields[1])
		if err != nil {
			t.Fatalf("layout.txt: %v", err)
		}

		in := inputs[n]
		if string(nameBytes) != in.name {
			t.Fatalf("input %d is %q, the fixture has %q: the program files have changed", n, in.name, string(nameBytes))
		}

		var got string

		n++

		source, err := pipeSource(in.src)
		if err != nil {
			t.Fatalf("%s: %v", in.name, err)
		}

		payload, err := stages.run("layout", source, stageFuelLayout)
		if err != nil {
			got = "the layout stage is " + err.Error()
		} else if text, err := resultPayload(payload); err != nil {
			got = "error " + err.Error()
		} else {
			sum := sha256.Sum256([]byte(pipeText(text)))
			got = "text " + hex.EncodeToString(sum[:])
		}

		want := fields[2] + " " + fields[3]

		if fields[2] == "error" {
			msg, err := hex.DecodeString(fields[3])
			if err != nil {
				t.Fatalf("layout.txt: %v", err)
			}

			want = "error " + string(msg)
		}

		if got != want {
			t.Errorf("%s: the bootstrapped layout gives %.120q, the Luau layout %.120q", in.name, got, want)
			continue
		}

		agree++
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	if n != len(inputs) {
		t.Fatalf("the fixture has %d inputs, the program files give %d", n, len(inputs))
	}

	t.Logf("%d of %d layout inputs give the Luau layout's text or error", agree, n)
}
