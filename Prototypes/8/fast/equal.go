package fast

// primEqual is the tag of the deep equality primitive (SPEC.md section 6, decision 19). It is run by the machine, not by prim, because it charges a step for each pair of values it visits.
const primEqual = 13

// equal compares two values, and gives whether they are the same. It visits the pairs in order: the two values, then the heads of two cells, then their tails, and so on, and it stops at the first difference. Each pair visited is one step, charged before it is looked at, so a comparison of two integers costs one step, as `=` does. A comparison that runs out of fuel ends the run where the stepwise rule would.
//
// Two values are the same when they have the same kind and the same contents: integers by value, nil, cells by head and tail, constructors by tag and payload. A law, a partial application or a suspended value (a thunk) is an error when the walk reaches it: none of them has a comparison that is well defined on the values it stands for.
//
// The walk is a loop over tails, so a long list uses no more Go stack than a short one.
func (r *recRun) equal(a, b Value) bool {
	for {
		r.charge()

		if k := KindOf(a); k == 3 || k == 6 {
			r.fail("equal of a function or a suspended value")
		}

		if k := KindOf(b); k == 3 || k == 6 {
			r.fail("equal of a function or a suspended value")
		}

		ka, kb := KindOf(a), KindOf(b)
		if ka != kb {
			return false
		}

		switch ka {
		case 0:
			return compare(a, b) == 0
		case 1:
			return true
		case 2:
			ca, cb := a.(*Cell), b.(*Cell)
			if !r.equal(ca.Head, cb.Head) {
				return false
			}

			a, b = ca.Tail, cb.Tail
		case 5:
			ca, cb := a.(*Con), b.(*Con)
			if ca.Tag != cb.Tag {
				return false
			}

			a, b = ca.Payload, cb.Payload
		default:
			panic("fast: a value of no kind")
		}
	}
}
