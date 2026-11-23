// Package fast is the Phase 4 machine of Prototype 7: the core of SPEC.md, run on Go.
//
// It reads the binary format of SPEC.md section 12, and runs programs with the fuel rule of section 6. It is checked against the Luau reference (reference/), which is the oracle: the same results, the same steps and the same messages on every case in testdata/.
//
// Integers are Small (any integer that fits in int64) or *big.Int (any other integer). The two never overlap: a result that fits in int64 is always a Small, so equal integers have one representation.
package fast

import "math/big"

type (
	// Law is a closed function of Arity arguments, whose body is Body. Its identity is the pointer: two laws with the same bytes are two laws, as in the reference.
	Law struct {
		Arity int
		Body *Node

		// hash is the content hash, kept once LawHash has computed it (hash.go).
		hash [32]byte
		hashed bool

		// jet is the law's jet, looked up once (jets.go): the table is fixed after init, so the answer does not change.
		jet jetFn
		jetKnown bool
	}

	// NilT is the nil value, the empty list. There is one.
	NilT struct{}

	// Small is an integer that fits in an int64.
	Small int64

	// Value is one of: Small, *big.Int, NilT, *Cell, *Con, *Law, *App, *Pin or *Thunk.
	Value any

	// App is a partial application of Law to Args, which are fewer than the law's arity.
	App struct {
		Law *Law
		Args []Value

		// hash, data and hashed cache hashOf (hash.go).
		hash [32]byte
		data, hashed bool
	}

	// Cell is a pair (Head . Tail).
	Cell struct {
		Head, Tail Value

		// hash, data and hashed cache hashOf (hash.go).
		hash [32]byte
		data, hashed bool
	}

	// Con is a constructor: a tag and a payload.
	Con struct {
		Tag int
		Payload Value

		// hash, data and hashed cache hashOf (hash.go).
		hash [32]byte
		data, hashed bool
	}

	// Pin is a value in normal form, interned by its content: equal pins are the same pointer.
	Pin struct {
		Value Value

		// hash, data and hashed cache hashOf (hash.go).
		hash [32]byte
		data, hashed bool
	}

	// Thunk is a delayed call of F to Args. It runs once; its result is kept in Result.
	Thunk struct {
		F Value
		Args []Value
		Done bool
		Result Value
	}
)

// NIL is the nil value.
var NIL Value = NilT{}

// KindOf is the kind number of a value (SPEC.md section 1).
func KindOf(v Value) int {
	switch v.(type) {
	case *App, *Law:
		return 3
	case *Cell:
		return 2
	case *Con:
		return 5
	case *Pin:
		return 4
	case *Thunk:
		return 6
	case *big.Int, Small:
		return 0
	case NilT:
		return 1
	}

	panic("fast: a value of no kind")
}

// isInt reports whether v is an integer.
func isInt(v Value) bool {
	switch v.(type) {
	case *big.Int, Small:
		return true
	}

	return false
}

// norm gives a big.Int as a Value: a Small when it fits in int64, so the representation is unique.
func norm(b *big.Int) Value {
	if b.IsInt64() {
		return Small(b.Int64())
	}

	return b
}

// sign is the sign of an integer: -1, 0 or 1.
func sign(v Value) int {
	switch x := v.(type) {
	case *big.Int:
		return x.Sign()
	case Small:
		switch {
		case x < 0:
			return -1
		case x > 0:
			return 1
		}

		return 0
	}

	panic("fast: sign of a value that is not an integer")
}

// toBig is an integer as a *big.Int. It is a fresh value, so the caller may change it.
func toBig(v Value) *big.Int {
	switch x := v.(type) {
	case *big.Int:
		return (&big.Int{}).Set(x)
	case Small:
		return big.NewInt(int64(x))
	}

	panic("fast: toBig of a value that is not an integer")
}

// add, sub and mul are exact. The fast path is on Small; an overflow goes to math/big.
func add(a, b Value) Value {
	if x, ok := a.(Small); ok {
		if y, ok := b.(Small); ok {
			if s := x + y; y >= 0 && s >= x || y < 0 && s < x {
				return s
			}
		}
	}

	return norm((&big.Int{}).Add(toBig(a), toBig(b)))
}

// compare is -1, 0 or 1 as a is less than, equal to or greater than b.
func compare(a, b Value) int {
	if x, ok := a.(Small); ok {
		if y, ok := b.(Small); ok {
			switch {
			case x < y:
				return -1
			case x > y:
				return 1
			}

			return 0
		}
	}

	return toBig(a).Cmp(toBig(b))
}

func floorDivMod(a, b Value) (Value, Value) {
	if x, ok := a.(Small); ok {
		if y, ok := b.(Small); ok && !(x == -1<<63 && y == -1) {
			q := x / y
			r := x % y

			if r != 0 && r < 0 != (y < 0) {
				q--
				r += y
			}

			return q, r
		}
	}

	x := toBig(a)
	y := toBig(b)
	q, r := (&big.Int{}).QuoRem(x, y, &big.Int{})

	if r.Sign() != 0 && r.Sign() < 0 != (y.Sign() < 0) {
		q.Sub(q, big.NewInt(1))
		r.Add(r, y)
	}

	return norm(q), norm(r)
}

// divFloor and modFloor round the quotient down, and give the remainder the sign of the divisor, so a = b*div + mod. The divisor must not be zero.
func divFloor(a, b Value) Value {
	q, _ := floorDivMod(a, b)

	return q
}

func modFloor(a, b Value) Value {
	_, r := floorDivMod(a, b)

	return r
}

func mul(a, b Value) Value {
	if x, ok := a.(Small); ok {
		if y, ok := b.(Small); ok {
			// Both fit in 32 bits, so the product fits in 64.
			if x >= -(1<<31) && x < 1<<31 && y >= -(1<<31) && y < 1<<31 {
				return x * y
			}
		}
	}

	return norm((&big.Int{}).Mul(toBig(a), toBig(b)))
}

func sub(a, b Value) Value {
	if x, ok := a.(Small); ok {
		if y, ok := b.(Small); ok {
			if d := x - y; y >= 0 && d <= x || y < 0 && d > x {
				return d
			}
		}
	}

	return norm((&big.Int{}).Sub(toBig(a), toBig(b)))
}
