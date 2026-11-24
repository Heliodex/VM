package fast

import (
	"strconv"
	"strings"
	"testing"
)

// TestPruneCosts fits the arm costs of prune's own steps. The findB calls inside prune are costed by the findB table (trie.go), so they are taken off the reference's steps first; what is left is the walk's own arms, and the fit must be exact on every case.
func TestPruneCosts(t *testing.T) {
	var (
		rows [][]int64
		ys []int64
	)

	for _, c := range readCases(t) {
		if !strings.HasPrefix(c[0], "jet check:prune@126 ") || c[5] != "value" {
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

		args := argsOfCase(t, input, 2)

		var (
			w [pArms]int64
			fw [6]int64
		)

		if _, ok := pruneWalk(args[0], args[1], &w, &fw); !ok {
			continue
		}

		steps, err := strconv.ParseInt(c[6], 10, 64)
		if err != nil {
			t.Fatal(err)
		}

		rows = append(rows, append([]int64(nil), w[:]...))
		ys = append(ys, steps-nodeCount(prog.Body)-armsCost(fw, costFindB))
	}

	costs := checkFit(t, "prune", rows, ys, pArms)

	checkTable(t, "prune", costs, costPrune[:])
}
