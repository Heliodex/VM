package fast

import (
	"bufio"
	"encoding/hex"
	"os"
	"strings"
	"testing"
)

// refusalFixture is one line of testdata/refusals.txt: a malformed program, the stage that refuses it (reader for the file reader), and the message the bootstrapped compile gives (gen/refusals.luau).
type refusalFixture struct {
	stage, text, reason, message string
}

func readRefusalFixture(t *testing.T) []refusalFixture {
	t.Helper()

	f, err := os.Open("testdata/refusals.txt")
	if err != nil {
		t.Fatal(err)
	}

	defer f.Close()

	var out []refusalFixture

	sc := bufio.NewScanner(f)

	sc.Buffer(make([]byte, 1<<20), 1<<30)

	for sc.Scan() {
		fields := strings.Fields(sc.Text())
		if len(fields) != 5 || fields[0] != "refusal" {
			t.Fatalf("refusals.txt: a line that is not a refusal line: %q", sc.Text())
		}

		var fx refusalFixture

		fx.stage = fields[1]

		for i, dst := range []*string{&fx.text, &fx.reason, &fx.message} {
			b, err := hex.DecodeString(fields[2+i])
			if err != nil {
				t.Fatalf("refusals.txt: %v", err)
			}

			*dst = string(b)
		}

		out = append(out, fx)
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	return out
}

// TestRefusals checks that each malformed program is refused by the stage that finds its fault, with a message that names the case's reason. The reader refuses a file before any stage runs.
func TestRefusals(t *testing.T) {
	stages, err := SeedStages()
	if err != nil {
		t.Fatal(err)
	}

	cases := readRefusalFixture(t)

	var exact int

	for _, fx := range cases {
		if fx.stage == "reader" {
			_, err := ParseProgramFile(fx.text)
			if err == nil {
				t.Errorf("the reader accepts a malformed file (%s)", fx.reason)
				continue
			}

			if !strings.Contains(err.Error(), fx.reason) {
				t.Errorf("the reader says %q, the case expects %q", err.Error(), fx.reason)
			}

			if err.Error() == fx.message {
				exact++
			}

			continue
		}

		_, err := stages.Compile(fx.text, "malformed.prog", FileLoader(""))
		if err == nil {
			t.Errorf("the stages accept a malformed program: %s", fx.reason)
			continue
		}

		message := err.Error()
		if fx.stage != "import" && !strings.HasPrefix(message, fx.stage+":") {
			t.Errorf("%s: refused by another stage: %q", fx.reason, message)
			continue
		}

		if !strings.Contains(message, fx.reason) {
			t.Errorf("%s: %s refuses it with %q, the case expects %q", fx.stage, fx.reason, message, fx.reason)
			continue
		}

		if message == fx.message {
			exact++
		}
	}

	t.Logf("%d refusals checked; %d give the bootstrapped compile's message exactly (the others carry the stage's name in front)", len(cases), exact)
}
