package fast

// Jets for four list helpers that the corpus runs most (fast/gen/gen.luau, section 10). Each walks its list as the body does, counting the arm each step takes, and gives up on anything the body would treat as an error, so the body runs and gives the error (the rule of decision 11). Each arm's cost is the steps of that arm, counting the entry (fitted to the reference; listjets_test.go checks it on every case).
//
// lenOf (the checker's length, check:lenOf@55):
//
//	if (= (@ l) 1) 0 (+ 1 (lenOf (tl l))): a nil ends the count; a cell adds one and goes on with its tail; any other value adds one, since its tail is nil (tl gives nil for a value that is not a cell), and nil then ends it.

import "slices"

const (
	lenNil = iota
	lenCell
	lenOther
	lenArms
)

// The name environment's lookup and insertion (check:envKid@292 and check:envPut@302). A node is a list of (key . child) pairs. The body refuses a key that is not an integer (the comparison is an error), so the walks give up there, and a value that is not a cell is a list that ends (head gives Err, not an error).

const (
	ekNone = iota // the list ends (or is not a cell): the empty node
	ekFound // the key is found: its child
	ekNext // the key is not this pair's: on to the next
	ekArms
)

const (
	epNone = iota // the list ends: the new pair goes at the end
	epFound // the key is found: the new pair replaces it, and the rest of the list is kept
	epNext // the key is not this pair's: it is kept, and the walk goes on
	epArms
)

const (
	psNilNil = iota // both are nil: 1
	psNilOther // a is nil, b is not: 0
	psCellNil // a is a cell, b is nil: 0
	psDiffer // both cells, their heads differ: 0
	psStep // both cells, their heads are equal: on to the tails
	psArms
)

var (
	// costEnvKid is the cost of each arm of envKid, in steps, counting its entry.
	costEnvKid = [ekArms]int64{70, 37, 63}

	// costEnvPut is the cost of each arm of envPut, in steps, counting its entry.
	costEnvPut = [epArms]int64{72, 65, 67}

	// costLenOf is the cost of each arm of lenOf, in steps, counting its entry.
	costLenOf = [lenArms]int64{7, 34, 80}

	// costParseSame is the cost of each arm of the parser's same, in steps, counting its entry.
	costParseSame = [psArms]int64{10, 10, 12, 62, 111}
)

// armsCostN is the cost of the arms of a walk, with the costs of each arm.
func armsCostN(w, costs []int64) (total int64) {
	for i := range w {
		total += w[i] * costs[i]
	}

	return
}

// envKidWalk is envKid: the child of the key, or the empty node, and the arms its walk takes.
func envKidWalk(kids, b Value, w *[ekArms]int64) (Value, bool) {
	for {
		c, ok := kids.(*Cell)
		if !ok {
			w[ekNone]++

			return &Con{
				Tag: 0,
				Payload: &Cell{
					Head: NIL,
					Tail: NIL,
				},
			}, true
		}

		p, ok := c.Head.(*Cell)
		if !ok || !isInt(p.Head) || !isInt(b) {
			return nil, false
		}

		if compare(p.Head, b) == 0 {
			w[ekFound]++

			return p.Tail, true
		}

		w[ekNext]++
		kids = c.Tail
	}
}

// lenOfWalk is lenOf: the length, and the arms its walk takes.
func lenOfWalk(l Value, w *[lenArms]int64) (Value, bool) {
	var n int64

	for {
		switch v := l.(type) {
		case NilT:
			w[lenNil]++

			return Small(n), true
		case *Cell:
			w[lenCell]++
			n++
			l = v.Tail
		default:
			// A value that is not a list: one more, and the tail of it is nil, which ends the count (its own entry is the nil arm).
			w[lenOther]++
			w[lenNil]++

			return Small(n + 1), true
		}
	}
}

// parseSameWalk is the parser's same (parse.l2, same@20): the body is a nil test on the first name, so a value that is not a list is not handled here (the walk gives up on it, and the body runs).
func parseSameWalk(a, b Value, w *[psArms]int64) (Value, bool) {
	for {
		switch av := a.(type) {
		case *Cell:
			if _, bNil := b.(NilT); bNil {
				w[psCellNil]++

				return Small(0), true
			}

			bc, bCell := b.(*Cell)
			if !bCell || !isInt(av.Head) || !isInt(bc.Head) {
				return nil, false
			}

			if compare(av.Head, bc.Head) != 0 {
				w[psDiffer]++

				return Small(0), true
			}

			w[psStep]++
			a, b = av.Tail, bc.Tail
		case NilT:
			if _, bNil := b.(NilT); bNil {
				w[psNilNil]++

				return Small(1), true
			}

			w[psNilOther]++

			return Small(0), true
		default:
			return nil, false
		}
	}
}

// rebuildBefore puts the pairs before the key in front of the rest: the rest is shared.
func rebuildBefore(before []Value, rest Value) Value {
	out := rest

	for _, b := range slices.Backward(before) {
		out = &Cell{
			Head: b,
			Tail: out,
		}
	}

	return out
}

// envPutWalk is envPut: the list with the pair (b . child) put in, and the arms its walk takes. The pairs before the key are rebuilt, and the rest is shared, as the body builds it.
func envPutWalk(kids, b, child Value, w *[epArms]int64) (Value, bool) {
	var before []Value

	for {
		c, ok := kids.(*Cell)

		// The pair being put in.
		pair := &Cell{
			Head: b,
			Tail: child,
		}

		if !ok {
			w[epNone]++

			return rebuildBefore(before, &Cell{
				Head: pair,
				Tail: NIL,
			}), true
		}

		p, ok := c.Head.(*Cell)
		if !ok || !isInt(p.Head) || !isInt(b) {
			return nil, false
		}

		if compare(p.Head, b) == 0 {
			w[epFound]++

			return rebuildBefore(before, &Cell{
				Head: pair,
				Tail: c.Tail,
			}), true
		}

		w[epNext]++

		before = append(before, c.Head)
		kids = c.Tail
	}
}

func init() {
	// check:lenOf@55: arity 1.
	register("2298ef3cfd2b21567e051f34d5863170062dad35c3709bd9f37d09492009109f", func(args []Value) (Value, int64, bool) {
		var w [lenArms]int64

		res, ok := lenOfWalk(args[0], &w)
		if !ok {
			return nil, 0, false
		}

		return res, armsCostN(w[:], costLenOf[:]), true
	})

	// check:envKid@292: arity 2, (kids, b).
	register("4ebaefaeb7147e6899bde716526cc4a377cb20530099a414edbd3a022e7afd85", func(args []Value) (Value, int64, bool) {
		var w [ekArms]int64

		res, ok := envKidWalk(args[0], args[1], &w)
		if !ok {
			return nil, 0, false
		}

		return res, armsCostN(w[:], costEnvKid[:]), true
	})

	// check:envPut@302: arity 3, (kids, b, child).
	register("8514ed55e670606cda618acdc3e3587222b948488fb2e776cb85fcd1b31ade00", func(args []Value) (Value, int64, bool) {
		var w [epArms]int64

		res, ok := envPutWalk(args[0], args[1], args[2], &w)
		if !ok {
			return nil, 0, false
		}

		return res, armsCostN(w[:], costEnvPut[:]), true
	})

	// parse:same@20: arity 2.
	register("830bcd29a9e7a470a2eb500987b7fd83d44bc730aa8d8c014b781ecead0ecb55", func(args []Value) (Value, int64, bool) {
		var w [psArms]int64

		res, ok := parseSameWalk(args[0], args[1], &w)
		if !ok {
			return nil, 0, false
		}

		return res, armsCostN(w[:], costParseSame[:]), true
	})
}
