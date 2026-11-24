package fast

import (
	"math/big"
	"strconv"
	"strings"
	"testing"
)

// sameSecondName is the literal of the second argument of the one call in a case's program: call (lit same) (arg 1) (lit b).
func sameSecondName(t *testing.T, prog *Law) Value {
	t.Helper()

	node := prog.Body
	if node == nil || node.Op != OpCall || len(node.Kids) != 3 || node.Kids[2].Op != OpLit {
		t.Fatal("a same case that is not the call the generator writes")
	}

	return node.Kids[2].Lit
}

// sameRows reads the cases of same: each is the arm counts of its walk, and the steps the reference took, less the call's own forms (4: the call, the law, the first name and the second).
func sameRows(t *testing.T) (rows [][sameArms]int64, ys []int64) {
	t.Helper()

	for _, c := range readCases(t) {
		if !strings.HasPrefix(c[0], "jet same@39 ") || c[5] != "value" {
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

		// The second name is the literal of the call: the call's third part, found by walking the program's one call.
		second := sameSecondName(t, prog)

		var w [sameArms]int64

		if _, ok := sameWalk(input, second, &w); !ok {
			continue
		}

		steps, err := strconv.ParseInt(c[6], 10, 64)
		if err != nil {
			t.Fatal(err)
		}

		rows = append(rows, w)
		ys = append(ys, steps-4)
	}

	return
}

// solveN is the least-squares solution of rows · x = ys, exactly, over the rationals (the normal equations, by Gaussian elimination).
func solveN(rows [][sameArms]int64, ys []int64) ([sameArms]*big.Rat, bool) {
	const n = sameArms

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
			return [sameArms]*big.Rat{}, false
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

	return x, true
}

// TestSameCosts checks that the arm costs of same are the fitted ones, integers, and that they fit every case exactly.
func TestSameCosts(t *testing.T) {
	rows, ys := sameRows(t)
	x, ok := solveN(rows, ys)

	if !ok {
		t.Fatalf("an arm never occurs in %d cases: the system is singular", len(rows))
	}

	var fitted []string

	for i := range x {
		if !x[i].IsInt() {
			t.Errorf("arm %d has a fractional cost %s", i, x[i].RatString())
		}

		fitted = append(fitted, x[i].RatString())
	}

	t.Logf("same: fitted costs %s over %d cases", strings.Join(fitted, ", "), len(rows))

	for k, r := range rows {
		var total int64

		for i := range r {
			total += r[i] * costSame[i]
		}

		if total != ys[k] {
			t.Fatalf("same: case %d costs %d by the table, the reference took %d", k, total, ys[k])
		}
	}
}
