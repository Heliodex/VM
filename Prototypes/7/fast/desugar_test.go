package fast

import (
	"bufio"
	"encoding/hex"
	"os"
	"strconv"
	"strings"
	"testing"
)

// fromHexList reads a hex list field: comma-separated hex items, or - for none.
func fromHexList(t *testing.T, field string) []string {
	t.Helper()

	if field == "-" {
		return nil
	}

	var out []string

	for _, item := range strings.Split(field, ",") {
		b, err := hex.DecodeString(item)

		if err != nil {
			t.Fatalf("desugar.txt: %v", err)
		}

		out = append(out, string(b))
	}

	return out
}

// TestDesugarParity runs the bootstrapped desugarer on each input of the parity run and checks its outcome, in the parity run's notation, against the Luau desugarer's (testdata/desugar.txt, from gen/desugar.luau): the expressions with and without imports, and the programs, checked first. An input both refuse is skipped.
func TestDesugarParity(t *testing.T) {
	stages, err := SeedStages()

	if err != nil {
		t.Fatal(err)
	}

	f, err := os.Open("testdata/desugar.txt")

	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<30)
	total, agree, skipped := 0, 0, 0

	for sc.Scan() {
		fields := strings.Fields(sc.Text())

		if len(fields) != 7 || fields[0] != "desugar" {
			t.Fatalf("desugar.txt: a line that is not a desugar line: %q", sc.Text())
		}

		decode := func(s string) string {
			b, err := hex.DecodeString(s)

			if err != nil {
				t.Fatalf("desugar.txt: %v", err)
			}

			return string(b)
		}

		kind, name, src := fields[1], decode(fields[2]), decode(fields[3])
		imports := fromHexList(t, fields[4])
		var values []int64

		for _, v := range fromHexList(t, fields[5]) {
			n, err := strconv.ParseInt(v, 10, 64)

			if err != nil {
				t.Fatalf("desugar.txt: %v", err)
			}

			values = append(values, n)
		}

		want := decode(fields[6])
		total++

		got, ok := stages.DesugarText(src, imports, values, kind == "program")

		if want == "skip" {
			skipped++

			if ok {
				t.Errorf("%s: the bootstrapped desugarer gives %q, the parity run skips it", name, got)
			}

			continue
		}

		if !ok {
			t.Errorf("%s: the bootstrapped desugarer refuses the source, the Luau desugarer gives %q", name, want)

			continue
		}

		if got != want {
			t.Errorf("%s: the bootstrapped desugarer gives %q, the Luau desugarer %q", name, got, want)

			continue
		}

		agree++
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	t.Logf("%d of %d inputs give the Luau desugarer's notation; %d skipped", agree, total, skipped)
}
