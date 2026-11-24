package fast

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"testing"
)

func mustRead(t *testing.T, path string) []byte {
	t.Helper()

	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	return b
}

// TestCoreProfile is the core's profile of the checker, by owning function: each step the spec charges, attributed to the law whose frame runs it (the law's content hash, mapped to the owner the generator recorded). It runs with the jets off, so every step is the spec's. It is a measurement, so it runs only when PROFILE is set.
func TestCoreProfile(t *testing.T) {
	type row struct {
		name string
		steps int64
	}

	if os.Getenv("PROFILE") == "" {
		t.Skip("set PROFILE=1 to run the core's profile")
	}

	owners := map[[32]byte]string{}

	for line := range strings.SplitSeq(string(mustRead(t, casesFile)), "\n") {
		if !strings.HasPrefix(line, "# law ") {
			continue
		}

		fields := strings.Fields(line)

		v, err := DecodeValue(unhex(t, fields[4]))
		if err != nil {
			t.Fatal(err)
		}

		l, ok := v.(*Law)
		if !ok {
			t.Fatalf("a law line that is not a law: %s", fields[1])
		}

		h, err := LawHash(l)
		if err != nil {
			t.Fatal(err)
		}

		owners[h] = fields[2]
	}

	counts := map[string]int64{}

	var total int64

	JetsOn = false

	defer func() {
		JetsOn = true
	}()

	StepHook = func(law Value) {
		total++
		l, ok := law.(*Law)

		if !ok {
			counts["top"]++

			return
		}

		h, err := LawHash(l)
		if err != nil {
			counts["?"]++

			return
		}

		if owner, ok := owners[h]; ok {
			counts[owner]++
		} else {
			counts["(no owner)"]++
		}
	}

	defer func() {
		StepHook = nil
	}()

	for _, c := range readCases(t) {
		if c[0] != "checker: variant types.l2 on types.l2" {
			continue
		}

		prog, err := DecodeProgram(unhex(t, c[2]))
		if err != nil {
			t.Fatal(err)
		}

		input, err := DecodeValue(unhex(t, c[3]))
		if err != nil {
			t.Fatal(err)
		}

		out := RunBody(prog.Body, input, 1e10)
		if out.Status != "value" {
			t.Fatalf("the checker gave %s", out.Status)
		}

		if total != out.Steps {
			t.Fatalf("the hook saw %d steps, the run took %d", total, out.Steps)
		}
	}

	var rows []row

	for name, n := range counts {
		rows = append(rows, row{name, n})
	}

	sort.Slice(rows, func(i, j int) bool {
		if rows[i].steps != rows[j].steps {
			return rows[i].steps > rows[j].steps
		}

		return rows[i].name < rows[j].name
	})
	fmt.Printf("core profile of the checker: %d steps\n", total)

	for i, r := range rows {
		if i == 25 {
			break
		}

		fmt.Printf("  %-18s %12d  %5.2f%%\n", r.name, r.steps, 100*float64(r.steps)/float64(total))
	}
}
