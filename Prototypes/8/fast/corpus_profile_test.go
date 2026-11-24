package fast

import (
	"fmt"
	"os"
	"sort"
	"strings"
	"testing"
)

// TestCorpusProfile is the corpus's profile by owner: each interpreted step (the jets are on, so a jet's steps are not in it), attributed to the law whose frame runs it. The owner of each law is the one the corpus generator recorded, as a '# law' line of testdata/corpus.txt, keyed by the law's content hash. It is a measurement, so it runs only when PROFILE_CORPUS is set.
func TestCorpusProfile(t *testing.T) {
	if os.Getenv("PROFILE_CORPUS") == "" {
		t.Skip("set PROFILE_CORPUS=1 to run the corpus profile")
	}

	owners := map[[32]byte]string{}

	path := os.Getenv("CORPUS")
	if path == "" {
		path = "testdata/corpus.txt"
	}

	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}

	for line := range strings.SplitSeq(string(raw), "\n") {
		if !strings.HasPrefix(line, "# law ") {
			continue
		}

		f := strings.Fields(line)

		v, err := DecodeValue(unhex(t, f[4]))
		if err != nil {
			t.Fatal(err)
		}

		h, err := LawHash(v.(*Law))
		if err != nil {
			t.Fatal(err)
		}

		owners[h] = f[2]
	}

	counts := map[string]int64{}

	var interpreted int64

	StepHook = func(law Value) {
		interpreted++
		l, ok := law.(*Law)

		if !ok {
			counts["(no law)"]++

			return
		}

		h, err := LawHash(l)
		if err != nil {
			counts["(unhashed)"]++

			return
		}

		if o, ok := owners[h]; ok {
			counts[o]++

			if o == "top" || o == "parse:top" {
				counts[fmt.Sprintf("  law %x arity %d", h[:4], l.Arity)]++
			}
		} else {
			counts["(no owner)"]++
		}
	}
	data := readCorpus(t)

	var fuel int64

	for _, f := range data.files {
		_, st, err := buildFile(data, f)
		if err != nil {
			t.Fatal(err)
		}

		fuel += st.steps
	}

	type row struct {
		owner string
		steps int64
	}

	var rows []row

	StepHook = nil

	for k, v := range counts {
		rows = append(rows, row{k, v})
	}

	sort.Slice(rows, func(i, j int) bool {
		if rows[i].steps != rows[j].steps {
			return rows[i].steps > rows[j].steps
		}

		return rows[i].owner < rows[j].owner
	})
	fmt.Printf("interpreted %d of %d steps (%.1f%%)\n", interpreted, fuel, 100*float64(interpreted)/float64(fuel))

	for i, r := range rows {
		if i == 30 {
			break
		}

		fmt.Printf("  %-34s %12d %6.2f%%\n", r.owner, r.steps, 100*float64(r.steps)/float64(interpreted))
	}
}
