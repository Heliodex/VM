package fast

import (
	"math/big"
	"testing"
)

// eqBody is the body: a = b, both literals.
func eqBody(a, b Value) *Node {
	return &Node{
		Op: OpPrim,
		Tag: primEq,
		Kids: []*Node{{Op: OpLit, Lit: a}, {Op: OpLit, Lit: b}},
	}
}

// list builds the list [vals...] of pair cells ending in nil.
func list(vals ...Value) Value {
	var v Value = NIL

	for i := len(vals) - 1; i >= 0; i-- {
		v = &Cell{Head: vals[i], Tail: v}
	}

	return v
}

// eqForms is the steps of a body that is = on two literals: the = form and its two literals, one step each. The comparison itself is one primitive, so it adds no steps, whatever its operands.
const eqForms = 3

func TestEqualAtoms(t *testing.T) {
	big1 := norm(new(big.Int).Lsh(big.NewInt(1), 100))
	big2 := norm(new(big.Int).Lsh(big.NewInt(1), 100))

	cases := []struct {
		name string
		a, b Value
		want Small
	}{
		{"integers, equal", Small(7), Small(7), 1},
		{"integers, different", Small(7), Small(8), 0},
		{"big integers, equal", big1, big2, 1},
		{"big and small integer, different", big1, Small(1), 0},
		{"nil and nil", NIL, NIL, 1},
		{"integer and nil", Small(0), NIL, 0},
		{"integer and cell", Small(0), &Cell{Head: Small(0), Tail: NIL}, 0},
		{"constructors, same tag and payload", &Con{Tag: 3, Payload: NIL}, &Con{Tag: 3, Payload: NIL}, 1},
		{"constructors, different tag", &Con{Tag: 3, Payload: NIL}, &Con{Tag: 4, Payload: NIL}, 0},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := RunBody(eqBody(c.a, c.b), NIL, 1e6)

			if out.Status != "value" || out.Value != c.want {
				t.Fatalf("got %s %v (%s), want %d", out.Status, out.Value, out.Message, c.want)
			}

			if out.Steps != eqForms {
				t.Fatalf("steps %d, want %d", out.Steps, eqForms)
			}
		})
	}
}

func TestEqualDeep(t *testing.T) {
	cases := []struct {
		name string
		a, b Value
		want Small
	}{
		{"lists, equal", list(Small(1), Small(2)), list(Small(1), Small(2)), 1},
		{"lists, differ in the second item", list(Small(1), Small(2)), list(Small(1), Small(3)), 0},
		{"lists, one a prefix of the other", list(Small(1)), list(Small(1), Small(2)), 0},
		{"nested pairs, equal", &Cell{Head: list(Small(1)), Tail: Small(2)}, &Cell{Head: list(Small(1)), Tail: Small(2)}, 1},
		{"empty list against itself", NIL, NIL, 1},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := RunBody(eqBody(c.a, c.b), NIL, 1e6)

			if out.Status != "value" || out.Value != c.want {
				t.Fatalf("got %s %v (%s), want %d", out.Status, out.Value, out.Message, c.want)
			}

			if out.Steps != eqForms {
				t.Fatalf("steps %d, want %d", out.Steps, eqForms)
			}
		})
	}
}

// Comparing two long lists is one primitive, so it costs what comparing two integers costs. This is the fuel gap the spec records.
func TestEqualLongListCostsOneStep(t *testing.T) {
	vals := make([]Value, 1000)
	for i := range vals {
		vals[i] = Small(i)
	}

	out := RunBody(eqBody(list(vals...), list(vals...)), NIL, 1e6)

	if out.Status != "value" || out.Value != Small(1) || out.Steps != eqForms {
		t.Fatalf("got %s %v after %d steps, want value 1 after %d", out.Status, out.Value, out.Steps, eqForms)
	}
}

// The comparison stops at the first difference, so a value that would be an error later is not reached.
func TestEqualStopsAtFirstDifference(t *testing.T) {
	a := &Cell{Head: Small(1), Tail: &Thunk{}}
	b := &Cell{Head: Small(2), Tail: &Thunk{}}

	out := RunBody(eqBody(a, b), NIL, 1e6)

	if out.Status != "value" || out.Value != Small(0) {
		t.Fatalf("got %s %v (%s), want 0", out.Status, out.Value, out.Message)
	}
}

func TestEqualRefusesFunctionsAndThunks(t *testing.T) {
	law := &Law{Arity: 1, Body: &Node{Op: OpArg, Index: 1}}

	cases := map[string][2]Value{
		"a law against an integer": {law, Small(1)},
		"a law against a law": {law, law},
		"a thunk against an integer": {&Thunk{}, Small(1)},
		"a thunk inside a list": {list(Small(1), &Thunk{}), list(Small(1), Small(1))},
	}

	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			out := RunBody(eqBody(c[0], c[1]), NIL, 1e6)

			if out.Status != "error" || out.Message != "equal of a function or a suspended value" {
				t.Fatalf("got %s (%q), want an error", out.Status, out.Message)
			}
		})
	}
}

// = keeps its tag and its arity, so the programs and the format are unchanged.
func TestEqIsTagSix(t *testing.T) {
	if primEq != 6 || primArity[primEq] != 2 {
		t.Fatalf("= is tag %d with arity %d, want tag 6 with arity 2", primEq, primArity[primEq])
	}
}
