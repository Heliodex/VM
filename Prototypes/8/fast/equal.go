package fast

// primEq is the tag of `=` (SPEC.md section 6). It is deep equality: on two integers it is the integer comparison, as before, and on other values it compares their contents. Like every primitive it costs one step, the form's own, whatever the size of its operands.
const primEq = 6

// deepEqual compares two values, and gives whether they are the same, or an error message when the comparison reaches a value it cannot compare. It visits the heads and the tails in order, and stops at the first difference, so a value after the difference is not reached.
//
// Two values are the same when they have the same kind and the same contents: integers by value, nil, cells by head and tail, constructors by tag and payload. A law, a partial application or a suspended value (a thunk) is an error when the walk reaches it: none of them has a comparison that is well defined on the values it stands for.
//
// The walk is a loop over tails, so a long list uses no more Go stack than a short one.
func deepEqual(a, b Value) (bool, string) {
	for {
		if k := KindOf(a); k == 3 || k == 6 {
			return false, "equal of a function or a suspended value"
		}

		if k := KindOf(b); k == 3 || k == 6 {
			return false, "equal of a function or a suspended value"
		}

		ka, kb := KindOf(a), KindOf(b)
		if ka != kb {
			return false, ""
		}

		switch ka {
		case 0:
			return compare(a, b) == 0, ""
		case 1:
			return true, ""
		case 2:
			ca, cb := a.(*Cell), b.(*Cell)

			same, msg := deepEqual(ca.Head, cb.Head)
			if msg != "" || !same {
				return false, msg
			}

			a, b = ca.Tail, cb.Tail
		case 5:
			ca, cb := a.(*Con), b.(*Con)
			if ca.Tag != cb.Tag {
				return false, ""
			}

			a, b = ca.Payload, cb.Payload
		default:
			panic("fast: a value of no kind")
		}
	}
}
