package fast

type (
	// Op is the kind of a form (SPEC.md section 3).
	Op uint8

	// Node is a form, with its parts resolved, so the machine reads it without looking anything up. Its children are in Kids, in the order of SPEC.md section 12.4:
	//
	//	lit:   Lit
	//	arg:   Index
	//	call:  Kids = f, e1 … en (also delay, which holds a call)
	//	cell:  Kids = a, b
	//	con:   Tag, Kids = e
	//	if:    Kids = c, t, e
	//	let:   Kids = e, b
	//	force: Kids = e
	//	prim:  Tag, Kids = the arguments
	Node struct {
		Op Op
		Lit Value
		Index, Tag int
		Kids []*Node
		Else *Node
	}
)

const (
	OpLit Op = iota
	OpArg
	OpCall
	OpCon
	OpIf
	OpLet
	OpDelay
	OpForce
	OpPrim
)

// primArity is the number of arguments of each primitive (SPEC.md section 4), by tag.
var primArity = []int{2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 2, 2}

// items are the children a form evaluates, in order, before it finishes. A case, an if, a let and a con evaluate only their first child first; the rest are used when it finishes.
func (n *Node) items() []*Node {
	switch n.Op {
	case OpCall, OpDelay, OpPrim:
		return n.Kids
	}

	return n.Kids[:1]
}
