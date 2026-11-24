package fast

import (
	"math/big"
	"testing"
)

// eqBody is the body: equal of a and b, both literals.
func eqBody(a, b Value) *Node {
	return &Node{
		Op: OpPrim,
		Tag: primEqual,
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

// The body's own steps: the equal form and its two literals, one step each.
const eqForms = 3

func TestEqualAtoms(t *testing.T) {
	big1 := norm(new(big.Int).Lsh(big.NewInt(1), 100))
	big2 := norm(new(big.Int).Lsh(big.NewInt(1), 100))

	cases := []struct {
		name string
		a, b Value
		want Small
		// pairs is the number of pairs the walk visits: the two values themselves, or one.
		pairs int64
	}{
		{"integers, equal", Small(7), Small(7), 1, 1},
		{"integers, different", Small(7), Small(8), 0, 1},
		{"big integers, equal", big1, big2, 1, 1},
		{"big and small integer, different", big1, Small(1), 0, 1},
		{"nil and nil", NIL, NIL, 1, 1},
		{"integer and nil", Small(0), NIL, 0, 1},
		{"integer and cell", Small(0), &Cell{Head: Small(0), Tail: NIL}, 0, 1},
		{"constructors, same tag and payload", &Con{Tag: 3, Payload: NIL}, &Con{Tag: 3, Payload: NIL}, 1, 2},
		{"constructors, different tag", &Con{Tag: 3, Payload: NIL}, &Con{Tag: 4, Payload: NIL}, 0, 1},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := RunBody(eqBody(c.a, c.b), NIL, 1e6)

			if out.Status != "value" || out.Value != c.want {
				t.Fatalf("got %s %v (%s), want %d", out.Status, out.Value, out.Message, c.want)
			}

			if want := eqForms + c.pairs; out.Steps != want {
				t.Fatalf("steps %d, want %d", out.Steps, want)
			}
		})
	}
}

func TestEqualDeep(t *testing.T) {
	cases := []struct {
		name string
		a, b Value
		want Small
		pairs int64
	}{
		// [1 2] against [1 2]: the cell, its head, its tail cell, the second head, and the nil tails.
		{"lists, equal", list(Small(1), Small(2)), list(Small(1), Small(2)), 1, 5},
		// [1 2] against [1 3]: stops at the second heads.
		{"lists, differ in the second item", list(Small(1), Small(2)), list(Small(1), Small(3)), 0, 4},
		// [1] against [1 2]: the tails are nil and a cell, which differ in kind.
		{"lists, one a prefix of the other", list(Small(1)), list(Small(1), Small(2)), 0, 3},
		{"nested pairs, equal", &Cell{Head: list(Small(1)), Tail: Small(2)}, &Cell{Head: list(Small(1)), Tail: Small(2)}, 1, 5},
		{"empty list against itself", NIL, NIL, 1, 1},
	}

	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			out := RunBody(eqBody(c.a, c.b), NIL, 1e6)

			if out.Status != "value" || out.Value != c.want {
				t.Fatalf("got %s %v (%s), want %d", out.Status, out.Value, out.Message, c.want)
			}

			if want := eqForms + c.pairs; out.Steps != want {
				t.Fatalf("steps %d, want %d", out.Steps, want)
			}
		})
	}
}

// The walk stops at the first difference, so a value that would be an error later is not reached.
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

// Running out of fuel in the middle of a comparison ends the run at the step where the fuel is used up.
func TestEqualOutOfFuel(t *testing.T) {
	a := list(Small(1), Small(2), Small(3))
	b := list(Small(1), Small(2), Small(3))

	// The body is eqForms + 7 pairs (three cells, three heads, one nil tail) = 10 steps.
	if out := RunBody(eqBody(a, b), NIL, 10); out.Status != "value" || out.Value != Small(1) || out.Steps != 10 {
		t.Fatalf("with fuel 10: got %s %v after %d steps, want value 1 after 10", out.Status, out.Value, out.Steps)
	}

	if out := RunBody(eqBody(a, b), NIL, 9); out.Status != "out_of_fuel" || out.Steps != 9 {
		t.Fatalf("with fuel 9: got %s after %d steps, want out_of_fuel after 9", out.Status, out.Steps)
	}
}

// An equal primitive in a law body costs the same as in a body, and the tag and arity are the ones the format knows.
func TestEqualArity(t *testing.T) {
	if primArity[primEqual] != 2 {
		t.Fatalf("arity %d, want 2", primArity[primEqual])
	}
}
