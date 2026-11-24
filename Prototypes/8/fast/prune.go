package fast

// The jet for prune (measure/boot/types.l2, owner prune@126): the chase of a type variable through the bindings of the checker's trie. Its body, as a walk of the same paths:
//
//	TCon p: the type is a constructor of tag 1, and is returned: pTCon
//	TVar id: findB of id, and then, if it is Bound u, prune of u (pBound); if it is Unbound, the type itself is returned (pUnbound)
//
// findB is a jet of its own (trie.go), and each of its calls inside prune is a call of that jet, so its steps are the findB arms, costed by costFindB. prune's own arms are the three above, fitted to the reference (prune_test.go).

const (
	pTCon = iota
	pUnbound
	pBound
	pArms
)

// costPrune is the cost of each arm of prune's own steps, in steps, counting its entry (fitted; see prune_test.go).
var costPrune = [pArms]int64{22, 35, 33}

// pruneWalk is prune: the type, and the arms its own walk takes and the arms of each findB it calls.
func pruneWalk(bs, t Value, w *[pArms]int64, fw *[6]int64) (Value, bool) {
	for {
		c, ok := t.(*Con)
		if !ok {
			return nil, false
		}

		switch c.Tag {
		case 1:
			w[pTCon]++

			return t, true
		case 0:
			id, ok := c.Payload.(Small)
			if !ok || id < 0 {
				return nil, false
			}

			bind, ok := findBWalk(bs, int64(id), fw)
			if !ok {
				return nil, false
			}

			b, ok := bind.(*Con)
			if !ok {
				return nil, false
			}

			switch b.Tag {
			case 1:
				w[pBound]++
				t = b.Payload
			case 0:
				w[pUnbound]++

				return t, true
			default:
				return nil, false
			}
		default:
			return nil, false
		}
	}
}

func init() {
	// prune@126: arity 2, the trie and the type. The fuel is its own arms, and the findB calls.
	register("584760e6947018adf101e6fd7d9052ece11e7e74c74cc222ceb6e5c624695835", func(args []Value) (Value, int64, bool) {
		var (
			w [pArms]int64
			fw [6]int64
		)

		res, ok := pruneWalk(args[0], args[1], &w, &fw)
		if !ok {
			return nil, 0, false
		}

		var cost int64

		for i := range w {
			cost += w[i] * costPrune[i]
		}

		return res, cost + armsCost(fw, costFindB), true
	})
}
