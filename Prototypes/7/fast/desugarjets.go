package fast

import (
	"encoding/hex"
)

// The jets for the desugarer (Prototypes/6/L2/programs/boot/desugar.l2), the stage the 2,500-line build runs after the check. Each one is keyed by its law's hash and fitted to the steps with the jets off (desugarfit_test.go). A jet also checks that the laws it calls are the desugarer's own (the head function is the hdOr law, the name comparison is the desugarer's same), so a call of another law runs the body.

// mustHash is the 32 bytes of a law's content hash, as written in the hex of this file.
func mustHash(s string) [32]byte {
	b, err := hex.DecodeString(s)
	if err != nil || len(b) != 32 {
		panic("fast: a hash is not 32 bytes of hex: " + s)
	}

	var h [32]byte

	copy(h[:], b)

	return h
}

var (
	// hdHash is desugar:hd@8, the head with a default. It is the hdOr law of the checker's and the layout's helpers, so the hdOr jet is its jet too.
	hdHash = mustHash("7dea60eed6b833b22695e1d7192478ba5d8bcd1c04497d4ada103c17a52fd5e6")

	// sameHash is desugar:same@25, the name comparison.
	sameHash = mustHash("e8eaeda2d75220340b37cce72d0953ea9ecb07aa65ebf62e5a768f27ad807a60")

	// posInHash is desugar:posIn@241, the index of a name in a list of names.
	posInHash = mustHash("5dd9f89c854cc340e1c0bbcf1503d461f3791bdf41fe741aa91c899c8b19ca6b")
)

// lawIs is whether v is the law with the content hash h.
func lawIs(v Value, h [32]byte) bool {
	l, ok := v.(*Law)

	if !ok {
		return false
	}

	got, err := LawHash(l)

	return err == nil && got == h
}

// costDesugarSame is the cost of each arm of the desugarer's same, in steps, counting the entry (fitted). Its body is the name comparison of same.go, with the head function inside its arms.
var costDesugarSame = [sameArms]int64{10, 10, 12, 46, 78}

// The arms of the desugarer's posIn: the walk goes on past a name that is not the one (posInNext), finds it (posInFound), or runs out of names (posInNil). Its calls of same cost by costDesugarSame, on top of these.
const (
	posInNext = iota
	posInFound
	posInNil
	posInArms
)

// costPosIn is the cost of each arm of posIn, in steps, counting the entry and its own forms but not its calls of same (fitted).
var costPosIn = [posInArms]int64{49, 27, 7}

// posInWalk is posIn on a list of names, the name n and the index i: the result, the arms its walk takes, and the cost of its calls of same. It gives up (ok false) on anything the body would not compare as lists of integers.
func posInWalk(names, n Value, i int64) (res Value, arms [posInArms]int64, sameCost int64, ok bool) {
	if !isListValue(n) {
		return nil, arms, 0, false
	}

	idx := i

	for {
		c, isCell := names.(*Cell)

		if !isCell {
			if _, isNil := names.(NilT); !isNil {
				return nil, arms, 0, false
			}

			arms[posInNil]++

			return Small(-1), arms, sameCost, true
		}

		if !isListValue(c.Head) {
			return nil, arms, 0, false
		}

		var w [sameArms]int64

		found, ok := sameWalk(c.Head, n, &w)

		if !ok {
			return nil, arms, 0, false
		}

		for k := range w {
			sameCost += w[k] * costDesugarSame[k]
		}

		if found == Small(1) {
			arms[posInFound]++

			return Small(idx), arms, sameCost, true
		}

		arms[posInNext]++
		idx++
		names = c.Tail
	}
}

// isListValue is a cell or nil: the values the name comparison walks.
func isListValue(v Value) bool {
	switch v.(type) {
	case *Cell, NilT:
		return true
	}

	return false
}

func init() {
	// same@25: arity 3. Its arguments are the head function, then the two names (the first name and the second).
	register("e8eaeda2d75220340b37cce72d0953ea9ecb07aa65ebf62e5a768f27ad807a60", func(args []Value) (Value, int64, bool) {
		if !lawIs(args[0], hdHash) {
			return nil, 0, false
		}

		var w [sameArms]int64

		res, ok := sameWalk(args[1], args[2], &w)
		if !ok {
			return nil, 0, false
		}

		var cost int64

		for i := range w {
			cost += w[i] * costDesugarSame[i]
		}

		return res, cost, true
	})

	// posIn@241: arity 5. Its arguments are the head function, the same law applied to the head function (the desugarer's same, which posIn calls with two arguments), the names, the name and the index.
	register("5dd9f89c854cc340e1c0bbcf1503d461f3791bdf41fe741aa91c899c8b19ca6b", func(args []Value) (Value, int64, bool) {
		if !lawIs(args[0], hdHash) {
			return nil, 0, false
		}

		app, isApp := args[1].(*App)

		if !isApp || len(app.Args) != 1 || !lawIs(app.Args[0], hdHash) || !lawIs(app.Law, sameHash) {
			return nil, 0, false
		}

		i, isSmall := args[4].(Small)

		if !isSmall || !isListValue(args[2]) {
			return nil, 0, false
		}

		res, arms, sameCost, ok := posInWalk(args[2], args[3], int64(i))

		if !ok {
			return nil, 0, false
		}

		cost := sameCost

		for k := range arms {
			cost += arms[k] * costPosIn[k]
		}

		return res, cost, true
	})
}
