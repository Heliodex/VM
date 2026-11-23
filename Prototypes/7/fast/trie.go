package fast

// The jets for findB and setB, the radix-4 trie of the checker (measure/boot/types.l2). A node is TNode (binding . (c0 . (c1 . (c2 . c3)))), and the empty trie is TEmpty; TEmpty is tag 0 and TNode tag 1 in the trie's type. A binding is Unbound i (tag 0) or Bound t (tag 1), and the lookup of id 0 gives the node's own binding.
//
// Each level of the recursion is one entry of the law, and each entry takes one of six arms, counted here as the body would take them:
//
//	armEmpty   the trie is empty (findB gives Unbound 0; setB makes a node and enters again)
//	armZero    the id is 0 at a node (the node's own binding; setB replaces it)
//	armR0 …    the id is r mod 4 at a node, with r = 0, 1, 2 or 3, so the recursion goes to child r
//
// A jet walks the same path and counts the arms. Its fuel is the sum of the arms' costs, which are fitted to the reference's steps (fast/gen and the fit in trie_test.go), so the cost of a call is exact on every case. A walk that meets anything the body would reject (a value that is not a trie, a negative id) gives up, and the body runs.

const (
	armEmpty = iota
	armZero
	armR0
	armR1
	armR2
	armR3
)

var (
	// The costs of the arms, in steps, counting the entry of the law (fitted; see trie_test.go).

	costFindB = [6]int64{50, 68, 100, 101, 102, 102}
	costSetB = [6]int64{70, 75, 111, 120, 130, 130}
	unboundZero Value = &Con{
		Tag: 0,
		Payload: Small(0),
	}
	emptyTrie Value = &Con{
		Tag: 0,
		Payload: NIL,
	}
)

// the cost of a walk: its arms times their costs.
func armsCost(w, costs [6]int64) (total int64) {
	for i := range w {
		total += w[i] * costs[i]
	}

	return
}

// build4 is the node's children again, as (c0 . (c1 . (c2 . c3))).
func build4(k [4]Value) Value {
	return &Cell{
		Head: k[0],
		Tail: &Cell{
			Head: k[1],
			Tail: &Cell{
				Head: k[2],
				Tail: k[3],
			},
		},
	}
}

// kids4 reads the four children of a node, (c0 . (c1 . (c2 . c3))). It gives up on a shape the body would not read as four.
func kids4(v Value) ([4]Value, bool) {
	var out [4]Value

	cur := v

	for i := range 3 {
		c, ok := cur.(*Cell)
		if !ok {
			return out, false
		}

		out[i] = c.Head
		cur = c.Tail
	}

	out[3] = cur

	return out, true
}

// node reads a trie's node: its binding, and its children. ok is false for a value that is not a TNode.
func node(v Value) (Value, [4]Value, bool) {
	c, ok := v.(*Con)
	if !ok || c.Tag != 1 {
		return nil, [4]Value{}, false
	}

	p, ok := c.Payload.(*Cell)
	if !ok {
		return nil, [4]Value{}, false
	}

	k, ok := kids4(p.Tail)
	if !ok {
		return nil, [4]Value{}, false
	}

	return p.Head, k, true
}

// findBWalk is findB: the binding of id in the trie, and the arms its path takes. The id is a non-negative integer (a negative one would not end, and the body decides that).
func findBWalk(bs Value, id int64, w *[6]int64) (Value, bool) {
	if id < 0 {
		return nil, false
	}

	for {
		c, ok := bs.(*Con)
		if !ok {
			return nil, false
		}

		switch c.Tag {
		case 0:
			w[armEmpty]++

			return unboundZero, true
		case 1:
			binding, k, ok := node(bs)
			if !ok {
				return nil, false
			}

			if id == 0 {
				w[armZero]++

				return binding, true
			}

			q := id / 4
			r := id - 4*q
			w[armR0+int(r)]++
			bs = k[r]
			id = q
		default:
			return nil, false
		}
	}
}

// setBWalk is setB: the trie with id set to b, and the arms its path takes.
func setBWalk(bs Value, id int64, b Value, w *[6]int64) (Value, bool) {
	c, ok := bs.(*Con)
	if !ok {
		return nil, false
	}

	switch c.Tag {
	case 0:
		w[armEmpty]++
		fresh := &Con{
			Tag: 1,
			Payload: &Cell{
				Head: unboundZero,
				Tail: build4([4]Value{emptyTrie, emptyTrie, emptyTrie, emptyTrie}),
			},
		}

		return setBWalk(fresh, id, b, w)
	case 1:
		binding, k, ok := node(bs)
		if !ok {
			return nil, false
		}

		if id == 0 {
			w[armZero]++

			return &Con{
				Tag: 1,
				Payload: &Cell{
					Head: b,
					Tail: c.Payload.(*Cell).Tail,
				},
			}, true
		}

		q := id / 4
		r := id - 4*q
		w[armR0+int(r)]++
		child, ok := setBWalk(k[r], q, b, w)

		if !ok {
			return nil, false
		}

		k[r] = child

		return &Con{
			Tag: 1,
			Payload: &Cell{
				Head: binding,
				Tail: build4(k),
			},
		}, true
	}

	return nil, false
}

func init() {
	// findB (fst of the lowered law of measure/boot/types.l2, owner findB@84): arity 2, the trie and the id. The fuel is the entry and the body, summed over the arms.
	register("d2fdaaf956192038f56048a9263a908b2f03f9e7bd62466bbfbffde57f5b42ce", func(args []Value) (Value, int64, bool) {
		id, ok := args[1].(Small)
		if !ok {
			return nil, 0, false
		}

		var w [6]int64

		res, ok := findBWalk(args[0], int64(id), &w)
		if !ok {
			return nil, 0, false
		}

		return res, armsCost(w, costFindB), true
	})

	// setB (owner setB@100): arity 3, the trie, the id and the binding.
	register("d2dac5d69d05121a2ceb05b0bad4b064c58c31648eee78322bfe6700b4f769f8", func(args []Value) (Value, int64, bool) {
		id, ok := args[1].(Small)
		if !ok || id < 0 {
			return nil, 0, false
		}

		var w [6]int64

		res, ok := setBWalk(args[0], int64(id), args[2], &w)
		if !ok {
			return nil, 0, false
		}

		return res, armsCost(w, costSetB), true
	})
}
