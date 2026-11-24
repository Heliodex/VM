package fast

import (
	"fmt"
	"math/big"
	"strconv"
	"strings"
	"testing"
)

// fitRows reads the cases of one family (findB or setB): each case is its arm counts and the steps the reference took, less the calls' own forms (4 for findB, 5 for setB, outside the law).
func fitRows(t *testing.T, prefix string, outer int64, setB bool) (rows [][6]int64, ys []int64) {
	t.Helper()

	for _, c := range readCases(t) {
		if !strings.HasPrefix(c[0], prefix) || c[5] != "value" || strings.Contains(c[0], "negative") {
			continue
		}

		prog, err := DecodeProgram(unhex(t, c[2]))
		if err != nil {
			t.Fatal(err)
		}

		call := prog.Body
		id, ok := call.Kids[2].Lit.(Small)

		if !ok {
			t.Fatalf("%s: the id is not a small integer", c[0])
		}

		input, err := DecodeValue(unhex(t, c[3]))
		if err != nil {
			t.Fatal(err)
		}

		var (
			w [6]int64
			walked bool
		)

		if setB {
			b := call.Kids[3].Lit
			_, walked = setBWalk(input, int64(id), b, &w)
		} else {
			_, walked = findBWalk(input, int64(id), &w)
		}

		if !walked {
			t.Fatalf("%s: the walk gives up on a case the body runs", c[0])
		}

		steps, err := strconv.ParseInt(c[6], 10, 64)
		if err != nil {
			t.Fatal(err)
		}

		rows = append(rows, w)
		ys = append(ys, steps-outer)
	}

	return
}

// solve gives the least-squares solution of rows · x = ys, exactly, by the normal equations and Gaussian elimination over the rationals.
func solve(rows [][6]int64, ys []int64) ([6]*big.Rat, error) {
	const n = 6

	var a [n][n + 1]*big.Rat

	for i := range a {
		for j := range a[i] {
			a[i][j] = &big.Rat{}
		}
	}

	for k, r := range rows {
		for i := range n {
			for j := range n {
				a[i][j].Add(a[i][j], (&big.Rat{}).SetInt64(r[i]*r[j]))
			}

			a[i][n].Add(a[i][n], (&big.Rat{}).SetInt64(r[i]*ys[k]))
		}
	}

	for col := range n {
		pivot := -1

		for row := col; row < n; row++ {
			if a[row][col].Sign() != 0 {
				pivot = row
				break
			}
		}

		if pivot < 0 {
			return [6]*big.Rat{}, fmt.Errorf("an arm never occurs (column %d): the system is singular", col)
		}

		a[col], a[pivot] = a[pivot], a[col]

		for row := range n {
			if row == col || a[row][col].Sign() == 0 {
				continue
			}

			factor := (&big.Rat{}).Quo(a[row][col], a[col][col])

			for j := col; j <= n; j++ {
				a[row][j].Sub(a[row][j], (&big.Rat{}).Mul(factor, a[col][j]))
			}
		}
	}

	var x [n]*big.Rat

	for i := range n {
		x[i] = (&big.Rat{}).Quo(a[i][n], a[i][i])
	}

	return x, nil
}

// TestTrieCosts checks that the arm costs of findB and setB are the fitted ones, and that they fit every case exactly: each case's steps are the arm counts times the costs, with no residual. A change to the reference's steps, or to a walk, fails here.
func TestTrieCosts(t *testing.T) {
	cases := []struct {
		name, prefix string
		outer int64
		setB bool
		costs [6]int64
	}{
		{"findB", "jet findB@84 ", 4, false, costFindB},
		{"setB", "jet setB@100 ", 5, true, costSetB},
	}

	for _, c := range cases {
		rows, ys := fitRows(t, c.prefix, c.outer, c.setB)

		x, err := solve(rows, ys)
		if err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}

		fitted := make([]string, 6)

		for i := range x {
			if !x[i].IsInt() {
				t.Errorf("%s: arm %d has a fractional cost %s", c.name, i, x[i].RatString())
			}

			fitted[i] = x[i].RatString()
		}

		t.Logf("%s: fitted costs %s over %d cases", c.name, strings.Join(fitted, ", "), len(rows))

		for k, r := range rows {
			var total int64

			for i := range r {
				total += r[i] * c.costs[i]
			}

			if total != ys[k] {
				t.Fatalf("%s: case %d costs %d by the table, the reference took %d", c.name, k, total, ys[k])
			}
		}
	}
}
