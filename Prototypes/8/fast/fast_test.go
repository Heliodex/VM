package fast

import (
	"bufio"
	"bytes"
	"encoding/hex"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The cases are written by gen/gen.luau, with the outcome the Luau reference gives for each. Every case must give the same status, the same steps, the same value bytes or the same message, and the program and input must read and write back to the same bytes.

const casesFile = "testdata/cases.txt"

// readCases gives the lines of the cases file that are cases (not comments and not blank), as fields.
func readCases(t *testing.T) [][]string {
	t.Helper()

	f, err := os.Open(casesFile)
	if err != nil {
		t.Fatalf("open %s: %v", casesFile, err)
	}

	defer f.Close()

	var out [][]string

	sc := bufio.NewScanner(f)

	sc.Buffer(make([]byte, 1<<20), 1<<30)

	for sc.Scan() {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		fields := strings.Split(line, "\t")
		if len(fields) != 9 {
			t.Fatalf("a case with %d fields: %q", len(fields), line)
		}

		out = append(out, fields)
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	return out
}

func unhex(t *testing.T, s string) []byte {
	t.Helper()

	b, err := hex.DecodeString(s)
	if err != nil {
		t.Fatalf("bad hex %q: %v", s, err)
	}

	return b
}

// TestChecker runs the checker benchmark on its own, and reports the steps per second against the reference's, as recorded in the cases file.
func TestChecker(t *testing.T) {
	var (
		refSteps int64
		refSeconds float64
	)

	f, err := os.ReadFile(casesFile)
	if err != nil {
		t.Fatal(err)
	}

	re := regexp.MustCompile(`# reference checker: \w+ after (\d+) steps in ([0-9.]+)s`)

	if m := re.FindSubmatch(f); m != nil {
		refSteps, _ = strconv.ParseInt(string(m[1]), 10, 64)
		refSeconds, _ = strconv.ParseFloat(string(m[2]), 64)
	} else {
		t.Skip("no reference timing in the cases file")
	}

	for _, c := range readCases(t) {
		if !strings.HasPrefix(c[0], "checker:") {
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

		fuel, _ := strconv.ParseInt(c[4], 10, 64)
		start := time.Now()
		out := RunBody(prog.Body, input, fuel)
		elapsed := time.Since(start).Seconds()

		if out.Status != c[5] {
			t.Fatalf("checker status %s, want %s", out.Status, c[5])
		}

		if out.Steps != refSteps {
			t.Fatalf("checker steps %d, reference %d", out.Steps, refSteps)
		}

		goRate := float64(out.Steps) / elapsed
		refRate := float64(refSteps) / refSeconds

		t.Logf("checker: %d steps in %.3fs, %.1f M steps/s; reference %.1f M steps/s; ratio %.1fx", out.Steps, elapsed, goRate/1e6, refRate/1e6, goRate/refRate)
	}
}

func checkCases(t *testing.T) {
	cases := readCases(t)

	t.Logf("%d cases", len(cases))

	for _, c := range cases {
		name, mode, progHex, inHex, fuelS, status, stepsS, valHex, msg := c[0], c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8]

		t.Run(name, func(t *testing.T) {
			progBytes := unhex(t, progHex)

			prog, err := DecodeProgram(progBytes)
			if err != nil {
				t.Fatalf("the program does not read: %v", err)
			}

			again, err := EncodeProgram(prog)
			if err != nil || !bytes.Equal(again, progBytes) {
				t.Fatalf("the program does not write back to its bytes: %v", err)
			}

			inBytes := unhex(t, inHex)

			input, err := DecodeValue(inBytes)
			if err != nil {
				t.Fatalf("the input does not read: %v", err)
			}

			if back, err := EncodeValue(input); err != nil || !bytes.Equal(back, inBytes) {
				t.Fatalf("the input does not write back to its bytes: %v", err)
			}

			fuel, err := strconv.ParseInt(fuelS, 10, 64)
			if err != nil {
				t.Fatal(err)
			}

			var out Outcome

			if mode == "body" {
				out = RunBody(prog.Body, input, fuel)
			} else {
				out = Run(prog, input, fuel)
			}

			wantSteps, err := strconv.ParseInt(stepsS, 10, 64)
			if err != nil {
				t.Fatal(err)
			}

			if out.Status != status {
				t.Fatalf("status %s, want %s (message %q)", out.Status, status, out.Message)
			}

			if out.Steps != wantSteps {
				t.Fatalf("steps %d, want %d", out.Steps, wantSteps)
			}

			switch status {
			case "value":
				got, err := EncodeValue(out.Value)
				if err != nil {
					t.Fatalf("the value has no binary form: %v", err)
				}

				if hex.EncodeToString(got) != valHex {
					t.Fatalf("value %x, want %s", got, valHex)
				}
			case "error":
				if out.Message != msg {
					t.Fatalf("message %q, want %q", out.Message, msg)
				}
			}
		})
	}
}

// TestCases runs every case with the jets on, as the machine runs by default.
func TestCases(t *testing.T) {
	JetsOn = true

	checkCases(t)
}

// TestCasesWithoutJets runs every case with the jets off: the spec code alone, which must give the same results and the same steps.
func TestCasesWithoutJets(t *testing.T) {
	JetsOn = false

	defer func() {
		JetsOn = true
	}()

	checkCases(t)
}
