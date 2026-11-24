package fast

import (
	"bufio"
	"encoding/hex"
	"os"
	"strings"
	"testing"
)

// TestLayoutParity runs the bootstrapped layout stage on each input of the layout parity run, and checks that its outcome (the text, or "error " and the message) is the Luau layout's, as testdata/layout.txt gives it (gen/layout.luau): the program sections as written, and copies with a line deleted, dedented or indented.
func TestLayoutParity(t *testing.T) {
	stages, err := SeedStages()

	if err != nil {
		t.Fatal(err)
	}

	f, err := os.Open("testdata/layout.txt")

	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 1<<20), 1<<30)
	inputs, agree := 0, 0

	for sc.Scan() {
		fields := strings.Fields(sc.Text())

		if len(fields) != 3 || fields[0] != "layout" {
			t.Fatalf("layout.txt: a line that is not a layout line: %q", sc.Text())
		}

		decode := func(s string) string {
			b, err := hex.DecodeString(s)

			if err != nil {
				t.Fatalf("layout.txt: %v", err)
			}

			return string(b)
		}

		src, want := decode(fields[1]), decode(fields[2])
		inputs++

		var got string
		payload, err := stages.run("layout", pipeBytes([]byte(src)), stageFuelLayout)

		if err != nil {
			got = "the layout stage is " + err.Error()
		} else if text, err := resultPayload(payload); err != nil {
			got = "error " + err.Error()
		} else {
			got = pipeText(text)
		}

		if got != want {
			t.Errorf("input %q: the bootstrapped layout gives %q, the Luau layout %q", src, got, want)

			continue
		}

		agree++
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	t.Logf("%d of %d layout inputs give the Luau layout's text or error", agree, inputs)
}
