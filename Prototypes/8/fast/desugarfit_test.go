package fast

import (
	"fmt"
	"math/big"
	"math/rand"
	"os"
	"strings"
	"testing"
)

// desugarLaw is the law of the corpus's owner (the one "# law" line that names it), decoded; it is the law the desugarer's body calls. The corpus file is the 2,500-line build with the desugarer.
func desugarLaw(t *testing.T, owner string) *Law {
	t.Helper()

	raw, err := os.ReadFile("testdata/corpus2500_desugar.txt")
	if err != nil {
		t.Fatal(err)
	}

	for line := range strings.SplitSeq(string(raw), "\n") {
		if !strings.HasPrefix(line, "# law ") {
			continue
		}

		f := strings.Fields(line)
		if f[2] != owner {
			continue
		}

		v, err := DecodeValue(unhex(t, f[4]))
		if err != nil {
			t.Fatal(err)
		}

		return v.(*Law)
	}

	t.Fatalf("no law %s in the corpus", owner)

	return nil
}

// nameValue is a list of bytes, as the desugarer's names are.
func nameValue(b []int64) Value {
	items := make([]Value, len(b))

	for i, c := range b {
		items[i] = Small(c)
	}

	return listOf(items)
}

// posInCall runs the desugarer's posIn with the jets off. Its arguments are the head function, the same law applied to the head function (the desugarer's same, which posIn calls with two arguments), the names, the name and the index. The call's own forms are seven: the call and its six parts.
func posInCall(posIn, hd, same *Law, names [][]int64, n []int64, i int64) (Outcome, error) {
	items := make([]Value, len(names))

	for k, name := range names {
		items[k] = nameValue(name)
	}

	body := &Node{
		Op: OpCall,
		Kids: []*Node{
			{
				Op: OpLit,
				Lit: posIn,
			},
			{
				Op: OpLit,
				Lit: hd,
			},
			{
				Op: OpLit,
				Lit: &App{
					Law: same,
					Args: []Value{hd},
				},
			},
			{
				Op: OpArg,
				Index: 1,
			},
			{
				Op: OpLit,
				Lit: nameValue(n),
			},
			{
				Op: OpLit,
				Lit: Small(i),
			},
		},
	}
	saved := JetsOn
	JetsOn = false

	defer func() {
		JetsOn = saved
	}()

	out := RunBody(body, listOf(items), 1<<40)
	if out.Status != "value" {
		return out, fmt.Errorf("status %s: %s", out.Status, out.Message)
	}

	return out, nil
}

// randomName is a name of up to maxLen bytes from a small alphabet, so that equal names and prefixes both occur.
func randomName(r *rand.Rand, maxLen int) []int64 {
	n := r.Intn(maxLen + 1)
	out := make([]int64, n)

	for i := range out {
		out[i] = int64('a' + r.Intn(3))
	}

	return out
}

// randomNames is a list of names, each up to maxLen bytes, from the small alphabet.
func randomNames(r *rand.Rand, count, maxLen int) [][]int64 {
	out := make([][]int64, count)

	for i := range out {
		out[i] = randomName(r, maxLen)
	}

	return out
}

// sameCall runs the law on the two names, with the jets off, and gives the steps. The law has arity 3: its first argument is the head function it calls (desugar:hd@8, which the recursion passes on unchanged), and the names are the second and third. The law itself is the callee, in slot 0. The call's own forms are five: the call, the law, the head function, the first name and the second.
func sameCall(law, hd *Law, a, b []int64, fuel int64) (Outcome, error) {
	body := &Node{
		Op: OpCall,
		Kids: []*Node{
			{
				Op: OpLit,
				Lit: law,
			},
			{
				Op: OpLit,
				Lit: hd,
			},
			{
				Op: OpArg,
				Index: 1,
			},
			{
				Op: OpLit,
				Lit: nameValue(b),
			},
		},
	}
	saved := JetsOn
	JetsOn = false

	defer func() {
		JetsOn = saved
	}()

	out := RunBody(body, nameValue(a), fuel)
	if out.Status != "value" {
		return out, fmt.Errorf("status %s: %s", out.Status, out.Message)
	}

	return out, nil
}

// sameValue is equality of two results: integers, or the same value otherwise.
func sameValue(a, b Value) bool {
	x, okA := a.(Small)
	y, okB := b.(Small)

	return okA && okB && x == y
}

// solveGeneric is the exact least-squares solution of rows · x = ys over the rationals (the normal equations, by Gaussian elimination). It reports false when the system is singular.
func solveGeneric(rows [][]int64, ys []int64) ([]*big.Rat, bool) {
	if len(rows) == 0 {
		return nil, false
	}

	n := len(rows[0])
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

// TestDesugarPosInFit fits the arm costs of the desugarer's posIn (desugar:posIn@241) to its steps with the jets off, after the cost of its calls of same, and checks the fit exactly.
func TestDesugarPosInFit(t *testing.T) {
	posIn := desugarLaw(t, "desugar:posIn@241")
	hd := desugarLaw(t, "desugar:hd@8")
	same := desugarLaw(t, "desugar:same@25")
	r := rand.New(rand.NewSource(2))

	var (
		rows [][]int64
		ys []int64
	)

	for range 3000 {
		names := randomNames(r, r.Intn(6), 4)
		n := randomName(r, 4)

		if len(names) > 0 && r.Intn(2) == 0 {
			n = append([]int64(nil), names[r.Intn(len(names))]...)
		}

		i := int64(r.Intn(5))

		out, err := posInCall(posIn, hd, same, names, n, i)
		if err != nil {
			t.Fatal(err)
		}

		// The walk of the names, as the jet does it: the arms it takes, and the cost of its calls of same.
		listItems := make([]Value, len(names))

		for k, name := range names {
			listItems[k] = nameValue(name)
		}

		res, arms, sameCost, ok := posInWalk(listOf(listItems), nameValue(n), i)
		if !ok {
			t.Fatal("the walk gives up on a case")
		}

		if !sameValue(out.Value, res) {
			t.Fatalf("the walk gives %v, the body gives %v", res, out.Value)
		}

		rows = append(rows, []int64{arms[posInNext], arms[posInFound], arms[posInNil]})
		ys = append(ys, out.Steps-7-sameCost)
	}

	x, ok := solveGeneric(rows, ys)
	if !ok {
		t.Fatalf("singular over %d cases", len(rows))
	}

	var fitted []string

	for _, v := range x {
		fitted = append(fitted, v.RatString())
	}

	t.Logf("desugar posIn: fitted arm costs (next, found, nil) %s over %d cases", strings.Join(fitted, ", "), len(rows))

	for i := range x {
		if !x[i].IsInt() {
			t.Fatalf("arm %d has a fractional cost %s", i, x[i].RatString())
		}
	}

	for k, row := range rows {
		var total int64

		for j := range row {
			total += row[j] * x[j].Num().Int64()
		}

		if total != ys[k] {
			t.Fatalf("case %d: the fit gives %d, the steps are %d", k, total, ys[k])
		}
	}
}

// TestDesugarSameFit fits the arm costs of the desugarer's same (owner desugar:same@25) to its steps with the jets off, and checks the fit exactly.
func TestDesugarSameFit(t *testing.T) {
	law := desugarLaw(t, "desugar:same@25")
	hd := desugarLaw(t, "desugar:hd@8")
	r := rand.New(rand.NewSource(1))

	var (
		rows [][]int64
		ys []int64
	)

	for range 4000 {
		a := randomName(r, 7)
		b := randomName(r, 7)

		if r.Intn(3) == 0 {
			b = append([]int64(nil), a...)
		}

		out, err := sameCall(law, hd, a, b, 1<<40)
		if err != nil {
			t.Fatal(err)
		}

		var w [sameArms]int64

		if _, ok := sameWalk(nameValue(a), nameValue(b), &w); !ok {
			t.Fatal("the walk gives up on a name")
		}

		// The arms are one per walk, so a constant term would be their sum: the call's own forms (5) are taken off instead.
		rows = append(rows, append([]int64(nil), w[:]...))
		ys = append(ys, out.Steps-5)
	}

	x, ok := solveGeneric(rows, ys)
	if !ok {
		t.Fatalf("singular: an arm never occurs in %d cases", len(rows))
	}

	var fitted []string

	for _, v := range x {
		fitted = append(fitted, v.RatString())
	}

	t.Logf("desugar same: fitted costs %s over %d cases", strings.Join(fitted, ", "), len(rows))

	for i := range x {
		if !x[i].IsInt() {
			t.Fatalf("arm %d has a fractional cost %s", i, x[i].RatString())
		}
	}

	for k, row := range rows {
		var total int64

		for i := range row {
			total += row[i] * x[i].Num().Int64()
		}

		if total != ys[k] {
			t.Fatalf("case %d: the fit gives %d, the steps are %d", k, total, ys[k])
		}
	}
}
