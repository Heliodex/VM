package fast

import (
	"bufio"
	"encoding/hex"
	"os"
	"strings"
	"testing"
)

// TestCheckerParity runs the pure checker (request Infer) on each source of the parity run, and checks its outcome against the Luau checker's, as testdata/checker.txt gives it (gen/checker.luau): 161 sources give a type or errors that agree, and 3 that the parser refuses are skipped.
func TestCheckerParity(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	f, err := os.Open("testdata/checker.txt")
	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	sc := bufio.NewScanner(f)

	sc.Buffer(make([]byte, 1<<20), 1<<30)

	compared, skipped := 0, 0

	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 4 || fields[0] != "check" {
			t.Fatalf("checker.txt: a line that is not a check line: %q", sc.Text())
		}

		decode := func(s string) string {
			b, err := hex.DecodeString(s)
			if err != nil {
				t.Fatalf("checker.txt: %v", err)
			}

			return string(b)
		}
		name, src, want := decode(fields[1]), decode(fields[2]), decode(fields[3])
		got, ok := stages.CheckText(src)

		if want == "skip" {
			skipped++

			if ok {
				t.Errorf("%s: the bootstrapped checker gives %q, the parity run skips it", name, got)
			}

			continue
		}

		compared++

		if !ok {
			t.Errorf("%s: the bootstrapped checker refuses the source, the Luau checker gives %q", name, want)
			continue
		}

		if got != want {
			t.Errorf("%s: the bootstrapped checker gives %q, the Luau checker %q", name, got, want)
		}
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	t.Logf("%d sources compared, %d skipped", compared, skipped)
}
