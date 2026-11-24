package fast

import (
	"testing"
)

// TestSeedFixedPoint compiles each stage's source with the seed stages, and checks that the law is the seed's own: the compiler, run on the machine, gives the stages it is made of. The seed is the fixed point (testdata/stages.txt), so the check is that the compiler compiles itself to the same bytes.
func TestSeedFixedPoint(t *testing.T) {
	stages, err := SeedStages()

	if err != nil {
		t.Fatal(err)
	}

	next, err := CompileStages(stages, programsRoot)

	if err != nil {
		t.Fatal(err)
	}

	for name := range StageSources {
		got, err := EncodeProgram(next[name])

		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}

		want, err := EncodeProgram(stages[name])

		if err != nil {
			t.Fatalf("%s: %v", name, err)
		}

		if string(got) != string(want) {
			t.Errorf("%s: the seed compiles its source to other bytes (%d, the seed %d)", name, len(got), len(want))
		}
	}
}

// TestSeedGenerations compiles the stages with the seed, and then with the stages that gives, and so on: the generations reach a fixed point when one is the same as the next, as bytes.
func TestSeedGenerations(t *testing.T) {
	gen, err := SeedStages()

	if err != nil {
		t.Fatal(err)
	}

	for i := 1; i <= 2; i++ {
		next, err := CompileStages(gen, programsRoot)

		if err != nil {
			t.Fatal(err)
		}

		same := 0

		for name := range StageSources {
			a, err := EncodeProgram(gen[name])

			if err != nil {
				t.Fatal(err)
			}

			b, err := EncodeProgram(next[name])

			if err != nil {
				t.Fatal(err)
			}

			if string(a) == string(b) {
				same++
			}
		}

		t.Logf("generation %d: %d of %d stages the same as the one before", i, same, len(StageSources))
		gen = next
	}
}
