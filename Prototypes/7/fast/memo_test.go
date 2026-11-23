package fast

import (
	"os"
	"strconv"
	"testing"
	"time"
)

// TestCasesWithMemo runs every case with the memo on: cold, and then again against the warm memo. Each run must give the same values and steps as the spec: the memo changes only the work.
func TestCasesWithMemo(t *testing.T) {
	MemoOn = true

	defer func() {
		MemoOn = false

		ResetMemo()
	}()

	ResetMemo()
	checkCases(t)
	t.Logf("cold: %d hits, %d misses, %d stores, memo %d entries", MemoCounts.Hits, MemoCounts.Misses, MemoCounts.Stores, MemoSize())

	MemoCounts = MemoStats{}

	checkCases(t)
	t.Logf("warm: %d hits, %d misses, %d stores, %d fuel charged by hits", MemoCounts.Hits, MemoCounts.Misses, MemoCounts.Stores, MemoCounts.ChargedFuel)
}

func mustInt(t *testing.T, s string) int64 {
	t.Helper()

	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		t.Fatal(err)
	}

	return n
}

func testingEnv(name string) string {
	return os.Getenv(name)
}

// TestMemoIncremental measures the memo on the checker (PROFILE-style: it runs only when MEMO is set). Work is the steps the machine runs, which is the fuel used less the fuel the memo's hits charged (they do no work). It runs the checker without the memo, cold with it, again on the same input (warm), and on the input with one declaration changed, against the memo the first two left.
func TestMemoIncremental(t *testing.T) {
	if testingEnv("MEMO") == "" {
		t.Skip("set MEMO=1 to measure the memo")
	}

	base := map[string]string{}

	var (
		baseInput, changedInput, baseProg, changedProg []byte
		baseSteps, changedSteps int64
	)

	for _, c := range readCases(t) {
		switch c[0] {
		case "checker: variant types.l2 on types.l2":
			baseProg, baseInput = unhex(t, c[2]), unhex(t, c[3])
			baseSteps = mustInt(t, c[6])
		case "checker: variant types.l2 with div10 changed":
			changedProg, changedInput = unhex(t, c[2]), unhex(t, c[3])
			changedSteps = mustInt(t, c[6])
		}
	}

	_ = base
	run := func(name string, prog, input []byte, want int64) {
		p, err := DecodeProgram(prog)
		if err != nil {
			t.Fatal(err)
		}

		in, err := DecodeValue(input)
		if err != nil {
			t.Fatal(err)
		}

		before := MemoCounts
		start := time.Now()
		out := RunBody(p.Body, in, 1e10)
		elapsed := time.Since(start)

		if out.Status != "value" || out.Steps != want {
			t.Fatalf("%s: %s after %d steps, want value after %d", name, out.Status, out.Steps, want)
		}

		charged := MemoCounts.ChargedFuel - before.ChargedFuel

		t.Logf("%-28s fuel %11d  work %11d (%.1f%%)  hits %6d  misses %6d  stores %6d  %.3fs", name, out.Steps, out.Steps-charged, 100*float64(out.Steps-charged)/float64(out.Steps), MemoCounts.Hits-before.Hits, MemoCounts.Misses-before.Misses, MemoCounts.Stores-before.Stores, elapsed.Seconds())
	}
	MemoOn = false

	ResetMemo()
	run("no memo", baseProg, baseInput, baseSteps)

	MemoOn = true

	ResetMemo()
	run("memo, cold", baseProg, baseInput, baseSteps)
	run("memo, same input again", baseProg, baseInput, baseSteps)
	run("memo, one declaration changed", changedProg, changedInput, changedSteps)
	ResetMemo()
	run("memo, changed input cold", changedProg, changedInput, changedSteps)

	MemoOn = false

	ResetMemo()
}
