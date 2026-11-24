package fast

import (
	"fmt"
	"sort"
)

// The converter (Prototype 8): the L2 compiler's output, turned into the law the machine runs.
//
// The desugarer (Prototypes/6/L2/programs/boot/desugar.l2) gives a Code value: its constructors, numbered as the type Code is declared (QInt 0 to CPrim2 14). The first step reads that value as an expression of the Prototype 6 machine, as boot_pipeline.luau's codeToExpr does. The second lowers it to the core, as reference/lower.luau does: every law is closed, so a lambda or a pin is closed by lambda lifting; a let, a constant and a fixed point of lambdas (a recursive function) each take the form the lowering gives them. The bytes of the result are the bytes the lowering gives for the same program (convert_test.go checks them against testdata/convert.txt).

// xop is the kind of an expression of the Prototype 6 machine (the forms of the Luau VM.Expr).
type xop uint8

const (
	xQuote xop = iota
	xVar
	xLam
	xPin
	xCell
	xIndex
	xForce
	xIf
	xApply
	xPrim
	xConstruct
	xTagof
	xPayload
)

// xexpr is an expression of the Prototype 6 machine. num is the index of a variable, the n of an index, the tag of a constructor, or the primitive's tag; kids are the parts (a lam has its body; an apply its function and its argument; a cell its head and tail; an if its condition, then and else; a prim one or two arguments; the others one). fix marks the fixed point, the lambda that a recursion is applied to (the Luau VM.fix, which the lowering finds by its identity).
type xexpr struct {
	op xop
	num int
	value Value
	kids []*xexpr
	fix bool
}

// convError is the failure of a conversion: the message, with the stage that found it.
type convError struct {
	msg string
}

func convFail(format string, args ...any) {
	panic(convError{msg: fmt.Sprintf(format, args...)})
}

// codeToExpr reads a Code value (the desugarer's output) as an expression of the Prototype 6 machine, as boot_pipeline.luau's codeToExpr does.
func codeToExpr(v Value) *xexpr {
	c, ok := v.(*Con)

	if !ok {
		convFail("convert: a code value is a constructor, not %T", v)
	}

	switch c.Tag {
	case 0: // QInt n
		return &xexpr{op: xQuote, value: convInt(c.Payload)}
	case 1: // QNil
		return &xexpr{op: xQuote, value: NIL}
	case 2: // CVar i
		return &xexpr{op: xVar, num: convIndex(c.Payload)}
	case 3: // CLam body
		return &xexpr{op: xLam, kids: []*xexpr{codeToExpr(c.Payload)}}
	case 4: // CApp (f . x): a fixed point applied to its function is the machine's fixed point
		p := convPair(c.Payload)
		f := codeToExpr(p.Head)

		if sameExpr(f, vmFix()) {
			f = vmFix()
		}

		return &xexpr{op: xApply, kids: []*xexpr{f, codeToExpr(p.Tail)}}
	case 5: // CCell (a . b)
		p := convPair(c.Payload)

		return &xexpr{op: xCell, kids: []*xexpr{codeToExpr(p.Head), codeToExpr(p.Tail)}}
	case 6: // CIndex (n . e)
		p := convPair(c.Payload)

		return &xexpr{op: xIndex, num: convIndex(p.Head), kids: []*xexpr{codeToExpr(p.Tail)}}
	case 7: // CIf (c . (t . e))
		p := convPair(c.Payload)
		rest := convPair(p.Tail)

		return &xexpr{op: xIf, kids: []*xexpr{codeToExpr(p.Head), codeToExpr(rest.Head), codeToExpr(rest.Tail)}}
	case 8: // CPin e
		return &xexpr{op: xPin, kids: []*xexpr{codeToExpr(c.Payload)}}
	case 9: // CForce e
		return &xexpr{op: xForce, kids: []*xexpr{codeToExpr(c.Payload)}}
	case 10: // CConstruct (tag . e)
		p := convPair(c.Payload)

		return &xexpr{op: xConstruct, num: convIndex(p.Head), kids: []*xexpr{codeToExpr(p.Tail)}}
	case 11: // CTagof e
		return &xexpr{op: xTagof, kids: []*xexpr{codeToExpr(c.Payload)}}
	case 12: // CPayload e
		return &xexpr{op: xPayload, kids: []*xexpr{codeToExpr(c.Payload)}}
	case 13: // CPrim1 (tag . a)
		p := convPair(c.Payload)

		return &xexpr{op: xPrim, num: convIndex(p.Head), kids: []*xexpr{codeToExpr(p.Tail)}}
	case 14: // CPrim2 (tag . (a . b))
		p := convPair(c.Payload)
		rest := convPair(p.Tail)

		return &xexpr{op: xPrim, num: convIndex(p.Head), kids: []*xexpr{codeToExpr(rest.Head), codeToExpr(rest.Tail)}}
	}

	convFail("convert: a code value has tag %d, which no constructor of Code has", c.Tag)

	return nil
}

// convPair is the head and tail of a pair (a payload with two parts).
func convPair(v Value) *Cell {
	c, ok := v.(*Cell)

	if !ok {
		convFail("convert: a code value's payload is a pair, not %T", v)
	}

	return c
}

// convInt is an integer of a code value.
func convInt(v Value) Value {
	if !isInt(v) {
		convFail("convert: a code value's integer is %T", v)
	}

	return v
}

// convIndex is an integer of a code value that is a small number (a tag, an index, a primitive).
func convIndex(v Value) int {
	s, ok := v.(Small)

	if !ok {
		convFail("convert: a code value's number is %T, not a small integer", v)
	}

	return int(s)
}

// vmFix is the fixed point of the Prototype 6 machine (VM.fix): lam(app(inner, inner)), inner = lam(app(var 1, lam(app(app(var 1, var 1), var 0)))). It is built fresh each time, since the conversion marks one copy.
func vmFix() *xexpr {
	inner := func() *xexpr {
		return &xexpr{op: xLam, kids: []*xexpr{{
			op: xApply,
			kids: []*xexpr{
				{op: xVar, num: 1},
				{op: xLam, kids: []*xexpr{{
					op: xApply,
					kids: []*xexpr{
						{op: xApply, kids: []*xexpr{{op: xVar, num: 1}, {op: xVar, num: 1}}},
						{op: xVar, num: 0},
					},
				}}},
			},
		}}}
	}

	return &xexpr{op: xLam, fix: true, kids: []*xexpr{{
		op: xApply,
		kids: []*xexpr{inner(), inner()},
	}}}
}

// sameExpr is whether two expressions have the same form (the fixed-point mark is not part of it).
func sameExpr(a, b *xexpr) bool {
	if a.op != b.op || a.num != b.num || len(a.kids) != len(b.kids) {
		return false
	}

	if a.op == xQuote && !sameQuote(a.value, b.value) {
		return false
	}

	for i := range a.kids {
		if !sameExpr(a.kids[i], b.kids[i]) {
			return false
		}
	}

	return true
}

// sameQuote is whether two quoted values are the same: integers, or nil.
func sameQuote(a, b Value) bool {
	switch x := a.(type) {
	case Small:
		y, ok := b.(Small)

		return ok && x == y
	case NilT:
		_, ok := b.(NilT)

		return ok
	}

	return false
}

// The primitives of the Prototype 6 machine: the tags of the eight that the core has, in its order (SPEC.md section 4). Its primitive names are the Luau interpreter's (primitives.luau).
var p6PrimNames = map[int]string{
	11: "add",
	12: "sub",
	13: "mul",
	14: "div",
	15: "mod",
	16: "lt",
	17: "eq",
	18: "kind",
}

var coreTags = map[string]int{
	"add": 0,
	"sub": 1,
	"mul": 2,
	"div": 3,
	"mod": 4,
	"lt": 5,
	"eq": 6,
	"kind": 7,
}

// The lowering's own constants: a variable bound to a closed value is not a slot of the frame, and its map entry is constBase - k, for the k-th constant form (1-based).
const constBase = -1000

// slots maps the level of each variable a law can see to the slot that holds it; -1 and -2 keep the count of captured arguments and the next free slot.
type slots map[int]int

func (m slots) copyOf() slots {
	out := make(slots, len(m))

	for k, v := range m {
		out[k] = v
	}

	return out
}

func isConstSlot(slot int, ok bool) bool {
	return ok && slot < constBase
}

// lowerer is one lowering: the constant forms it has made, which a conversion shares across its laws.
type lowerer struct {
	constForms []*Node
}

// lowerExpr lowers a top-level expression (no binders in scope), as Lower.expr does.
func (w *lowerer) lowerExpr(e *xexpr) *Node {
	return w.lower(e, 0, slots{-2: 2})
}

// freeLevels adds to acc the levels below base that the expression refers to, at a depth of binders.
func freeLevels(e *xexpr, depth, base int, acc map[int]bool) {
	if e.op == xVar {
		lvl := depth - 1 - e.num

		if lvl < base {
			acc[lvl] = true
		}

		return
	}

	for _, k := range e.kids {
		if e.op == xLam {
			freeLevels(k, depth+1, base, acc)
		} else {
			freeLevels(k, depth, base, acc)
		}
	}
}

// sortedFree is the free levels in order.
func sortedFree(e *xexpr, depth, base int) []int {
	acc := map[int]bool{}
	freeLevels(e, depth, base, acc)

	out := make([]int, 0, len(acc))

	for lvl := range acc {
		out = append(out, lvl)
	}

	sort.Ints(out)

	return out
}

// steps is the address of index n: its binary digits below the leading 1, from the first step to the last (0 is head, 1 is tail).
func steps(n int) []int {
	var bits []int

	for m := n; m > 1; m /= 2 {
		bits = append(bits, m%2)
	}

	out := make([]int, 0, len(bits))

	for i := len(bits) - 1; i >= 0; i-- {
		out = append(out, bits[i])
	}

	return out
}

// capturedLevels are the free levels of e that are not constants of the map: the arguments a lambda or a pin takes.
func capturedLevels(e *xexpr, depth, base int, m slots) []int {
	var out []int

	for _, lvl := range sortedFree(e, depth, base) {
		slot, ok := m[lvl]

		if !isConstSlot(slot, ok) {
			out = append(out, lvl)
		}
	}

	return out
}

// inheritConsts copies the constants of the map into a law's map, so that its body sees them too.
func inheritConsts(m slots, inner slots) {
	for lvl, slot := range m {
		if slot < constBase {
			inner[lvl] = slot
		}
	}
}

// slotForm is the form that gives a slot of the current law's frame. Slot 0 is the recursive function itself: the law applied to the outer variables it uses, which are its first arguments.
func slotForm(slot int, m slots) *Node {
	if slot != 0 {
		return argNode(slot)
	}

	count := m[-1]

	if count == 0 {
		return argNode(0)
	}

	args := make([]*Node, 0, count)

	for i := 1; i <= count; i++ {
		args = append(args, argNode(i))
	}

	return callNode(argNode(0), args)
}

// argsOf are the arguments that hold the given levels in the current law's frame.
func argsOf(levels []int, m slots) []*Node {
	args := make([]*Node, 0, len(levels))

	for _, lvl := range levels {
		slot, ok := m[lvl]

		if !ok {
			convFail("lower: a free variable at level %d is not in the law's frame", lvl)
		}

		args = append(args, slotForm(slot, m))
	}

	return args
}

// lamChain is a chain of lambdas as one law: the number of lambdas, and the body under them.
func lamChain(e *xexpr) (int, *xexpr) {
	n := 0
	cur := e

	for cur.op == xLam {
		n++
		cur = cur.kids[0]
	}

	return n, cur
}

// containsLam is whether an expression makes a lambda anywhere in it.
func containsLam(e *xexpr) bool {
	if e.op == xLam {
		return true
	}

	if e.op == xQuote || e.op == xVar {
		return false
	}

	for _, k := range e.kids {
		if containsLam(k) {
			return true
		}
	}

	return false
}

// capturesLevel is whether a lambda in e, at depth, captures the variable at level.
func capturesLevel(e *xexpr, depth, level int) bool {
	if e.op == xLam {
		for _, l := range sortedFree(e.kids[0], depth+1, depth) {
			if l == level {
				return true
			}
		}

		return false
	}

	for _, k := range e.kids {
		if capturesLevel(k, depth, level) {
			return true
		}
	}

	return false
}

// isLetApp is whether an application of a lambda is a let at depth, given the map: a let is used when the lambda's body makes no lambda, or when no lambda in it captures the law's own function (slot 0).
func isLetApp(e *xexpr, depth int, m slots) bool {
	if e.op != xApply {
		return false
	}

	f := e.kids[0]

	if f.op != xLam || f.fix {
		return false
	}

	if !containsLam(f.kids[0]) {
		return true
	}

	for lvl, slot := range m {
		if lvl >= 0 && slot == 0 && capturesLevel(f.kids[0], depth+1, lvl) {
			return false
		}
	}

	return true
}

// isFixOfLams is the argument of a fixed point that the desugarer writes for a recursive function: a lambda whose body is a lambda.
func isFixOfLams(e *xexpr) bool {
	return e.op == xLam && e.kids[0].op == xLam
}

// lowerFix lowers a recursive function: the lambda that binds the function (at depth), whose body is the function's own lambda. Inside, the function is slot 0, the law itself, applied to the outer variables it uses, so there is no fixed point.
func (w *lowerer) lowerFix(e *xexpr, depth int, m slots) *Node {
	value := e.kids[0]

	if value.op != xLam {
		convFail("lower: a recursive function that is not a lambda")
	}

	n, body := lamChain(value)
	free := capturedLevels(body, depth+1+n, depth, m)
	inner := slots{}
	inheritConsts(m, inner)

	for i, lvl := range free {
		inner[lvl] = i + 1
	}

	inner[depth] = 0

	for j := 1; j <= n; j++ {
		inner[depth+j] = len(free) + j
	}

	inner[-1] = len(free)
	inner[-2] = len(free) + n + 1
	law := &Law{Arity: len(free) + n, Body: w.lower(body, depth+1+n, inner)}

	return w.lawForm(law, free, m)
}

// lawForm is a law made in a frame: a literal when it is closed, or a call of the literal on the variables it takes.
func (w *lowerer) lawForm(law *Law, free []int, m slots) *Node {
	if len(free) == 0 {
		return litNode(law)
	}

	return callNode(litNode(law), argsOf(free, m))
}

// tryConstLet is an application of a lambda to a closed value that lowers to a literal: the lambda's variable is that constant, and its body is lowered in this frame. nil when it does not apply.
func (w *lowerer) tryConstLet(e *xexpr, depth int, m slots) *Node {
	if e.op != xApply || e.kids[0].op != xLam || e.kids[0].fix {
		return nil
	}

	if len(capturedLevels(e.kids[1], depth, depth, m)) > 0 {
		return nil
	}

	value := w.lower(e.kids[1], depth, m)

	if value.Op != OpLit {
		return nil
	}

	w.constForms = append(w.constForms, value)
	k := len(w.constForms)
	inner := m.copyOf()
	inner[depth] = constBase - k

	return w.lower(e.kids[0].kids[0], depth+1, inner)
}

// lower lowers an expression at a depth of binders, with the map of its frame.
func (w *lowerer) lower(e *xexpr, depth int, m slots) *Node {
	if constLet := w.tryConstLet(e, depth, m); constLet != nil {
		return constLet
	}

	switch e.op {
	case xQuote:
		return litNode(e.value)
	case xVar:
		lvl := depth - 1 - e.num
		slot, ok := m[lvl]

		if !ok {
			// No binder: an unbound name. The machine gives an error for it at run time, through a slot that no frame has.
			return argNode(1 << 40)
		}

		if isConstSlot(slot, true) {
			return w.constForms[(constBase-slot)-1]
		}

		return slotForm(slot, m)
	case xLam:
		n, body := lamChain(e)
		free := capturedLevels(body, depth+n, depth, m)
		inner := slots{}
		inheritConsts(m, inner)

		for i, lvl := range free {
			inner[lvl] = i + 1
		}

		for j := 1; j <= n; j++ {
			inner[depth+j-1] = len(free) + j
		}

		inner[-2] = len(free) + n + 1
		law := &Law{Arity: len(free) + n, Body: w.lower(body, depth+n, inner)}

		return w.lawForm(law, free, m)
	case xPin:
		free := capturedLevels(e.kids[0], depth, depth, m)
		inner := slots{}
		inheritConsts(m, inner)

		// The law's first argument is a dummy (slot 1), and the free variables are its arguments after it.
		for i, lvl := range free {
			inner[lvl] = i + 2
		}

		inner[-2] = len(free) + 2
		law := &Law{Arity: len(free) + 1, Body: w.lower(e.kids[0], depth, inner)}
		args := []*Node{litNode(NIL)}
		args = append(args, argsOf(free, m)...)

		return delayNode(litNode(law), args)
	case xCell:
		return primNode(12, w.lower(e.kids[0], depth, m), w.lower(e.kids[1], depth, m))
	case xIndex:
		form := w.lower(e.kids[0], depth, m)

		for _, step := range steps(e.num) {
			tag := 9

			if step == 0 {
				tag = 8
			}

			form = primNode(tag, form)
		}

		return form
	case xForce:
		return forceNode(w.lower(e.kids[0], depth, m))
	case xIf:
		return ifNode(w.lower(e.kids[0], depth, m), w.lower(e.kids[1], depth, m), w.lower(e.kids[2], depth, m))
	case xApply:
		if e.kids[0].fix && isFixOfLams(e.kids[1]) {
			return w.lowerFix(e.kids[1], depth, m)
		}

		if isLetApp(e, depth, m) {
			// An immediately applied lambda is a let: the argument is evaluated in this frame, and the lambda's variable is the next slot of the frame.
			slot := m[-2]
			inner := m.copyOf()
			inner[depth] = slot
			inner[-2] = slot + 1
			lambda := e.kids[0]

			return letNode(w.lower(e.kids[1], depth, m), w.lower(lambda.kids[0], depth+1, inner))
		}

		return w.lowerApply(e, depth, m)
	case xPrim:
		name, ok := p6PrimNames[e.num]

		if !ok {
			convFail("lower: the primitive with tag %d has no core tag", e.num)
		}

		tag, ok := coreTags[name]

		if !ok {
			convFail("lower: the primitive %s has no core tag", name)
		}

		args := make([]*Node, 0, len(e.kids))

		for _, k := range e.kids {
			args = append(args, w.lower(k, depth, m))
		}

		return primNode(tag, args...)
	case xConstruct:
		return conNode(e.num, w.lower(e.kids[0], depth, m))
	case xTagof:
		return primNode(10, w.lower(e.kids[0], depth, m))
	case xPayload:
		return primNode(11, w.lower(e.kids[0], depth, m))
	}

	convFail("lower: an expression of kind %d is not known", e.op)

	return nil
}

// lowerApply lowers an application: the arguments of a chain of applications, as one call (the head is not an application, or the fixed point's own application).
func (w *lowerer) lowerApply(e *xexpr, depth int, m slots) *Node {
	var args []*xexpr
	head := e

	for head.op == xApply && !head.kids[0].fix {
		args = append([]*xexpr{head.kids[1]}, args...)
		head = head.kids[0]
	}

	if head == e {
		// A fixed point that is not a lambda of a lambda: an application of it, as it is.
		return callNode(w.lower(e.kids[0], depth, m), []*Node{w.lower(e.kids[1], depth, m)})
	}

	forms := make([]*Node, 0, len(args))

	for _, a := range args {
		forms = append(forms, w.lower(a, depth, m))
	}

	headForm := w.lower(head, depth, m)

	// A call of a call is one call with all its arguments: a partial application of a law, applied to more, is the law applied to all of them.
	if headForm.Op == OpCall {
		all := append(append([]*Node{}, headForm.Kids[1:]...), forms...)

		return callNode(headForm.Kids[0], all)
	}

	return callNode(headForm, forms)
}

// The node constructors of the core's forms (node.go).

func litNode(v Value) *Node {
	return &Node{Op: OpLit, Lit: v}
}

func argNode(i int) *Node {
	return &Node{Op: OpArg, Index: i}
}

func callNode(f *Node, args []*Node) *Node {
	return &Node{Op: OpCall, Kids: append([]*Node{f}, args...)}
}

func delayNode(f *Node, args []*Node) *Node {
	return &Node{Op: OpDelay, Kids: append([]*Node{f}, args...)}
}

func primNode(tag int, args ...*Node) *Node {
	return &Node{Op: OpPrim, Tag: tag, Kids: args}
}

func conNode(tag int, e *Node) *Node {
	return &Node{Op: OpCon, Tag: tag, Kids: []*Node{e}}
}

func forceNode(e *Node) *Node {
	return &Node{Op: OpForce, Kids: []*Node{e}}
}

func ifNode(c, t, e *Node) *Node {
	return &Node{Op: OpIf, Kids: []*Node{c, t, e}}
}

func letNode(e, b *Node) *Node {
	return &Node{Op: OpLet, Kids: []*Node{e, b}}
}

// ConvertLaw turns the desugarer's output for a program (a Code value) into the program law the machine runs: the law of arity 1, whose body applies the program's expression to its input (argument 1), as the host's program does. It is an error when the value is not a Code value, or when the lowering would refuse it.
func ConvertLaw(code Value) (law *Law, err error) {
	defer func() {
		if r := recover(); r != nil {
			if ce, ok := r.(convError); ok {
				err = fmt.Errorf("%s", ce.msg)

				return
			}

			panic(r)
		}
	}()

	e := codeToExpr(code)
	w := &lowerer{}
	form := w.lowerExpr(e)

	return &Law{Arity: 1, Body: callNode(form, []*Node{argNode(1)})}, nil
}
