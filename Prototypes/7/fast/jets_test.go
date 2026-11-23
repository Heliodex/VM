package fast

import (
	"encoding/hex"
	"testing"
)

// laws gives the hash of every law in a tree of forms, including the laws inside laws.
func laws(t *testing.T, n *Node, seen map[[32]byte]bool) {
	t.Helper()

	if n == nil {
		return
	}

	if n.Op == OpLit {
		if l, ok := n.Lit.(*Law); ok {
			h, err := LawHash(l)
			if err != nil {
				t.Fatal(err)
			}

			seen[h] = true

			laws(t, l.Body, seen)
		}
	}

	for _, k := range n.Kids {
		laws(t, k, seen)
	}

	for _, a := range n.Alts {
		laws(t, a.Body, seen)
	}

	laws(t, n.Else, seen)
}

// TestJetHashesAreInTheChecker checks that every jet still names a law of the checker's program. A jet whose hash is no longer there is never used, so it would make the checker slower without failing anything; this test is what catches it.
func TestJetHashesAreInTheChecker(t *testing.T) {
	for _, c := range readCases(t) {
		if c[0] != "checker: variant types.l2 on types.l2" {
			continue
		}

		prog, err := DecodeProgram(unhex(t, c[2]))
		if err != nil {
			t.Fatal(err)
		}

		seen := map[[32]byte]bool{}

		laws(t, prog.Body, seen)

		// The corpus's helpers (corpusjets.go) are laws of the corpus's stage programs, not of the checker's, so a jet may name a law of either.
		data := readCorpus(t)

		for _, p := range data.programs {
			laws(t, p.Body, seen)
		}

		for h := range jets {
			if !seen[h] {
				t.Errorf("the jet for %s names no law of the checker's or the corpus's programs", hex.EncodeToString(h[:4]))
			}
		}

		return
	}

	t.Fatal("no checker case")
}
