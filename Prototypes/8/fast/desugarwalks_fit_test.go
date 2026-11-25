package fast

import (
	"fmt"
	"math/rand"
	"strings"
	"testing"
)

// walkCall runs a desugarer list walk (inList, primIn or lookupCtorFrom) with the jets on or off: the call is the law with the head function, the same applied to it, the input (the table or the names) and the key. The frame is [NIL, input], as the desugarer's own calls are.
func walkCall(law, hd, same *Law, input, key Value, jets bool) Outcome {
	body := &Node{
		Op: OpCall,
		Kids: []*Node{
			{Op: OpLit, Lit: law},
			{Op: OpLit, Lit: hd},
			{Op: OpLit, Lit: &App{Law: same, Args: []Value{hd}}},
			{Op: OpArg, Index: 1},
			{Op: OpLit, Lit: key},
		},
	}

	saved := JetsOn
	JetsOn = jets

	defer func() {
		JetsOn = saved
	}()

	return RunBody(body, input, 1<<40)
}

// walkCase is one random input to a walk: its table (a list of names, or of (key . value) entries), and the key.
type walkCase struct {
	input Value
	key Value
}

// randomWalkCase draws a case: a table of up to five entries, and a key that is often one of the entries' keys.
func randomWalkCase(r *rand.Rand, pairs bool) walkCase {
	names := randomNames(r, r.Intn(6), 4)
	key := randomName(r, 4)

	if len(names) > 0 && r.Intn(2) == 0 {
		key = append([]int64(nil), names[r.Intn(len(names))]...)
	}

	items := make([]Value, len(names))

	for k, name := range names {
		if pairs {
			items[k] = &Cell{Head: nameValue(name), Tail: Small(r.Intn(1000))}
		} else {
			items[k] = nameValue(name)
		}
	}

	return walkCase{input: listOf(items), key: nameValue(key)}
}

// harnessForms is the steps of walkCall's own body: its call and its five children.
const harnessForms = 6

// fitWalk fits the arm costs of one walk to its steps with the jets off, over random cases, and checks the fit exactly. walk gives the walk's own result and arms for a case.
func fitWalk(t *testing.T, label string, law, hd, same *Law, pairs bool, walk func(input, key Value) (Value, []int64, int64, bool)) []int64 {
	t.Helper()

	r := rand.New(rand.NewSource(3))

	var (
		rows [][]int64
		ys []int64
	)

	for range 3000 {
		c := randomWalkCase(r, pairs)

		out := walkCall(law, hd, same, c.input, c.key, false)
		if out.Status != "value" {
			t.Fatalf("%s: status %s: %s", label, out.Status, out.Message)
		}

		res, arms, sameCost, ok := walk(c.input, c.key)
		if !ok {
			t.Fatalf("%s: the walk gives up on a case the body accepts", label)
		}

		if !sameResult(out.Value, res) {
			t.Fatalf("%s: the walk gives %T %v, the body gives %T %v", label, res, res, out.Value, out.Value)
		}

		// The harness's own forms: the call and its five children, six steps. They are subtracted rather than fitted, since every walk ends in exactly one of its found and nil arms, which makes a constant column dependent on those two.
		rows = append(rows, append([]int64(nil), arms...))
		ys = append(ys, out.Steps-sameCost-harnessForms)
	}

	x, ok := solveGeneric(rows, ys)
	if !ok {
		t.Fatalf("%s: singular over %d cases", label, len(rows))
	}

	fitted := make([]int64, len(x))

	var names []string

	for i, v := range x {
		if !v.IsInt() {
			t.Fatalf("%s: unknown %d has a fractional value %s", label, i, v.RatString())
		}

		fitted[i] = v.Num().Int64()

		names = append(names, v.RatString())
	}

	t.Logf("%s: fitted arm costs %s over %d cases", label, strings.Join(names, ", "), len(rows))

	for k, row := range rows {
		var total int64

		for j := range row {
			total += row[j] * x[j].Num().Int64()
		}

		if total != ys[k] {
			t.Fatalf("%s: case %d: the fit gives %d, the steps are %d", label, k, total, ys[k])
		}
	}

	return fitted
}

// TestDesugarWalksFit fits the arm costs of inList, primIn and lookupCtorFrom to their steps with the jets off, and checks the fit exactly. The fitted costs are the ones in desugarwalks.go; a change to the desugarer's source changes them.
func TestDesugarWalksFit(t *testing.T) {
	hd := desugarLaw(t, "desugar:hd@8")
	same := desugarLaw(t, "desugar:same@25")

	inList := desugarLaw(t, "desugar:inList@41")
	primIn := desugarLaw(t, "desugar:primIn@57")
	lookup := desugarLaw(t, "desugar:lookupCtorFrom@120")

	inCost := fitWalk(t, "inList", inList, hd, same, false, func(input, key Value) (Value, []int64, int64, bool) {
		res, arms, sameCost, ok := inListWalk(input, key)

		return res, arms[:], sameCost, ok
	})

	primCost := fitWalk(t, "primIn", primIn, hd, same, true, func(input, key Value) (Value, []int64, int64, bool) {
		res, arms, sameCost, ok := assocWalk(input, key, Small(-1))

		return res, arms[:], sameCost, ok
	})

	lookupCost := fitWalk(t, "lookupCtorFrom", lookup, hd, same, true, func(input, key Value) (Value, []int64, int64, bool) {
		res, arms, sameCost, ok := assocWalk(input, key, ctorNone)

		return res, arms[:], sameCost, ok
	})

	fmt.Printf("costInList = %v\ncostAssocPrimIn = %v\ncostAssocLookup = %v\n", inCost, primCost, lookupCost)
}

// TestDesugarWalksJetsAgree runs the three walks with the jets on and off, over random cases: the same value and the same steps, which the jets must keep.
func TestDesugarWalksJetsAgree(t *testing.T) {
	hd := desugarLaw(t, "desugar:hd@8")
	same := desugarLaw(t, "desugar:same@25")

	cases := []struct {
		label string
		law *Law
		pairs bool
	}{
		{"inList", desugarLaw(t, "desugar:inList@41"), false},
		{"primIn", desugarLaw(t, "desugar:primIn@57"), true},
		{"lookupCtorFrom", desugarLaw(t, "desugar:lookupCtorFrom@120"), true},
	}

	r := rand.New(rand.NewSource(4))

	for _, c := range cases {
		for range 1000 {
			w := randomWalkCase(r, c.pairs)

			off := walkCall(c.law, hd, same, w.input, w.key, false)
			on := walkCall(c.law, hd, same, w.input, w.key, true)

			if off.Status != on.Status || off.Steps != on.Steps || !sameResult(off.Value, on.Value) {
				t.Fatalf("%s: jets off gives %s %v after %d steps, jets on %s %v after %d", c.label, off.Status, off.Value, off.Steps, on.Status, on.Value, on.Steps)
			}
		}
	}
}

// sameResult is equality of two results by their contents, with the machine's deep equality (equal.go).
func sameResult(a, b Value) bool {
	same, msg := deepEqual(a, b)

	return msg == "" && same
}
