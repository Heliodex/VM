package fast

import (
	"math/big"
	"strconv"
	"strings"
	"testing"
)

// argsOfCase gives the arguments of a case's call from its input: the input itself for one argument, and the parts of a pair (or a pair of pairs) for more.
func argsOfCase(t *testing.T, input Value, n int) []Value {
	t.Helper()

	cur := input
	out := make([]Value, 0, n)

	for i := range n {
		if i == n-1 {
			out = append(out, cur)
			break
		}

		c, ok := cur.(*Cell)
		if !ok {
			t.Fatal("a case whose input is not the pair of its arguments")
		}

		out = append(out, c.Head)
		cur = c.Tail
	}

	return out
}

// checkTable fails when the table in the code is not the fitted costs.
func checkTable(t *testing.T, name string, fitted, table []int64) {
	t.Helper()

	for i := range fitted {
		if fitted[i] != table[i] {
			t.Errorf("%s: arm %d costs %d in the code, the fit says %d", name, i, table[i], fitted[i])
		}
	}
}

// nodeCount is the number of forms in a body: each is one step of the wrapper a case's program writes around the law (the forms are evaluated once each, since the wrapper has no branch).
func nodeCount(n *Node) int64 {
	if n == nil {
		return 0
	}

	c := int64(1)

	for _, k := range n.Kids {
		c += nodeCount(k)
	}

	return c + nodeCount(n.Else)
}

// fitRowsOf reads the cases of one law (by the prefix of their names): each row is the arm counts of its walk, and y is the steps the reference took, less the wrapper's forms. walk gives the arm counts of a case's arguments, or false when the walk gives up.
func fitRowsOf(t *testing.T, prefix string, nargs, arms int, walk func(args []Value, w []int64) bool) (rows [][]int64, ys []int64) {
	t.Helper()

	for _, c := range readCases(t) {
		if !strings.HasPrefix(c[0], prefix) || c[5] != "value" {
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

		w := make([]int64, arms)
		if !walk(argsOfCase(t, input, nargs), w) {
			continue
		}

		steps, err := strconv.ParseInt(c[6], 10, 64)
		if err != nil {
			t.Fatal(err)
		}

		rows = append(rows, w)
		ys = append(ys, steps-nodeCount(prog.Body))
	}

	return
}

// solveArms is the least-squares solution of rows · x = ys, exactly, over the rationals (the normal equations, by Gaussian elimination). It reports false when an arm never occurs.
func solveArms(rows [][]int64, ys []int64, n int) ([]*big.Rat, bool) {
	a := make([][]*big.Rat, n)

	for i := range a {
		a[i] = make([]*big.Rat, n+1)

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
			return nil, false
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

	x := make([]*big.Rat, n)

	for i := range n {
		x[i] = (&big.Rat{}).Quo(a[i][n], a[i][i])
	}

	return x, true
}

// checkFit fits the costs of one walk's arms to the reference's steps, and checks that the fitted costs are integers that give every row exactly. It logs the costs, to be written into the table.
func checkFit(t *testing.T, name string, rows [][]int64, ys []int64, n int) []int64 {
	t.Helper()

	x, ok := solveArms(rows, ys, n)
	if !ok {
		t.Fatalf("%s: an arm never occurs in %d cases: the system is singular", name, len(rows))
	}

	costs := make([]int64, n)

	var fitted []string

	for i := range x {
		if !x[i].IsInt() {
			t.Errorf("%s: arm %d has a fractional cost %s", name, i, x[i].RatString())
		}

		costs[i] = x[i].Num().Int64()
		fitted = append(fitted, x[i].RatString())
	}

	t.Logf("%s: fitted costs %s over %d cases", name, strings.Join(fitted, ", "), len(rows))

	for k, r := range rows {
		var total int64

		for i := range r {
			total += r[i] * costs[i]
		}

		if total != ys[k] {
			t.Fatalf("%s: case %d costs %d by the fitted table, the reference took %d", name, k, total, ys[k])
		}
	}

	return costs
}

// TestListJetCosts fits the arm costs of the four list jets, and checks that the table in listjets.go gives every case of each exactly.
func TestListJetCosts(t *testing.T) {
	lenRows, lenYs := fitRowsOf(t, "jet check:lenOf@55 ", 1, lenArms, func(args []Value, w []int64) bool {
		var a [lenArms]int64

		_, ok := lenOfWalk(args[0], &a)

		copy(w, a[:])

		return ok
	})

	checkTable(t, "lenOf", checkFit(t, "lenOf", lenRows, lenYs, lenArms), costLenOf[:])

	kidRows, kidYs := fitRowsOf(t, "jet check:envKid@292 ", 2, ekArms, func(args []Value, w []int64) bool {
		var a [ekArms]int64

		_, ok := envKidWalk(args[0], args[1], &a)

		copy(w, a[:])

		return ok
	})

	checkTable(t, "envKid", checkFit(t, "envKid", kidRows, kidYs, ekArms), costEnvKid[:])

	putRows, putYs := fitRowsOf(t, "jet check:envPut@302 ", 3, epArms, func(args []Value, w []int64) bool {
		var a [epArms]int64

		_, ok := envPutWalk(args[0], args[1], args[2], &a)

		copy(w, a[:])

		return ok
	})

	checkTable(t, "envPut", checkFit(t, "envPut", putRows, putYs, epArms), costEnvPut[:])

	sameRows, sameYs := fitRowsOf(t, "jet parse:same@20 ", 2, psArms, func(args []Value, w []int64) bool {
		var a [psArms]int64

		_, ok := parseSameWalk(args[0], args[1], &a)

		copy(w, a[:])

		return ok
	})

	checkTable(t, "parse same", checkFit(t, "parse same", sameRows, sameYs, psArms), costParseSame[:])
}
