package fast

import (
	"errors"
	"fmt"
	"math/big"
	"slices"
)

type (
	// ---- reading

	reader struct {
		s []byte
		p int
		// nodePool and kidPool are the pools the forms are read into, so a program's nodes are a few large arrays, not many small objects: the collector scans every object it finds, and a program is scanned each cycle.
		nodePool []Node
		kidPool []*Node
	}

	// ---- writing

	writer struct {
		buf []byte
	}
)

// The binary format of SPEC.md section 12. The writer and the reader follow the Luau reference (reference/format.luau), byte for byte, and give the same messages.

const (
	valueHeader = 1
	programHeader = 2
	vNil = 0
	vCell = 1
	vPos = 2
	vNeg = 3
	vCon = 4
	vLaw = 5
	vApp = 6
	vPin = 7
	fLit = 0x10
	fArg = 0x11
	fCall = 0x12
	fCon = 0x14
	fCase = 0x15
	fIf = 0x16
	fLet = 0x17
	fDelay = 0x18
	fForce = 0x19
	fPrim = 0x1a

	// maxPos is 2^53 - 1: the largest position a reader accepts (SPEC.md section 12.2).
	maxPos = 1<<53 - 1
)

// bigOf is the value of 7-bit groups.
func bigOf(groups []byte) *big.Int {
	v := &big.Int{}

	for _, group := range slices.Backward(groups) {
		v.Lsh(v, 7)
		v.Or(v, big.NewInt(int64(group)))
	}

	return v
}

func (r *reader) byteOf(what string) (byte, error) {
	if r.p >= len(r.s) {
		return 0, fmt.Errorf("binary: the bytes end before %s is complete", what)
	}

	b := r.s[r.p]
	r.p++

	return b, nil
}

// groups reads one LEB128 magnitude, and gives its bytes as 7-bit groups, least significant first. It refuses a magnitude that is not in its shortest form.
func (r *reader) groups(what string) ([]byte, error) {
	var out []byte

	for {
		b, err := r.byteOf(what)
		if err != nil {
			return nil, err
		}

		out = append(out, b&127)

		if b < 128 {
			if b == 0 && len(out) > 1 {
				return nil, errors.New("binary: a number is not in its shortest form")
			}

			return out, nil
		}
	}
}

// integer reads the magnitude of an integer, after its sign tag. Negative zero is refused.
func (r *reader) integer(neg bool) (Value, error) {
	groups, err := r.groups("an integer")
	if err != nil {
		return nil, err
	}

	m := bigOf(groups)

	if neg {
		if m.Sign() == 0 {
			return nil, errors.New("binary: negative zero is not a value")
		}

		m.Neg(m)
	}

	return norm(m), nil
}

// kids is a slice of n children, from the reader's pool.
func (r *reader) kids(n int) []*Node {
	if len(r.kidPool) < n {
		r.kidPool = make([]*Node, max(n, 1024))
	}

	s := r.kidPool[:n:n]
	r.kidPool = r.kidPool[n:]

	return s
}

// node is a new node, from the reader's pool.
func (r *reader) node(n Node) *Node {
	if len(r.nodePool) == 0 {
		r.nodePool = make([]Node, 256)
	}

	p := &r.nodePool[0]
	r.nodePool = r.nodePool[1:]
	*p = n

	return p
}

// pos reads a position: a magnitude that is at most 2^53 - 1.
func (r *reader) pos(what string) (int, error) {
	groups, err := r.groups(what)
	if err != nil {
		return 0, err
	}

	v := bigOf(groups)
	if !v.IsInt64() || v.Int64() > maxPos {
		return 0, fmt.Errorf("binary: %s is past 2^53 - 1, the largest position", what)
	}

	return int(v.Int64()), nil
}

// mag writes a non-negative magnitude as LEB128 (SPEC.md section 12.2).
func (w *writer) mag(n uint64) {
	for {
		b := byte(n & 127)
		n >>= 7

		if n == 0 {
			w.buf = append(w.buf, b)

			return
		}

		w.buf = append(w.buf, b|128)
	}
}

// magBig writes the magnitude of an integer of any size.
func (w *writer) magBig(x *big.Int) {
	m := (&big.Int{}).Abs(x)
	if m.IsUint64() {
		w.mag(m.Uint64())
		return
	}

	for mask := big.NewInt(127); m.Sign() > 0; {
		g := (&big.Int{}).And(m, mask).Uint64()

		m.Rsh(m, 7)

		if m.Sign() > 0 {
			g |= 128
		}

		w.buf = append(w.buf, byte(g))
	}
}

func (w *writer) integer(v Value) {
	if sign(v) < 0 {
		w.buf = append(w.buf, vNeg)
	} else {
		w.buf = append(w.buf, vPos)
	}

	switch x := v.(type) {
	case *big.Int:
		w.magBig(x)
	case Small:
		if x < 0 {
			w.mag(uint64(-(int64(x) + 1)) + 1)
		} else {
			w.mag(uint64(x))
		}
	}
}

// pos writes a position, which is a count, an index, a tag or an arity.
func (w *writer) pos(n int) error {
	if n < 0 {
		return errors.New("binary: a position must be a whole number from 0 up")
	}

	w.mag(uint64(n))

	return nil
}

func (w *writer) value(v Value) error {
	switch x := v.(type) {
	case *App:
		w.buf = append(w.buf, vApp)

		if err := w.value(x.Law); err != nil {
			return err
		}

		if err := w.pos(len(x.Args)); err != nil {
			return err
		}

		for _, a := range x.Args {
			if err := w.value(a); err != nil {
				return err
			}
		}
	case *Cell:
		w.buf = append(w.buf, vCell)

		if err := w.value(x.Head); err != nil {
			return err
		}

		return w.value(x.Tail)
	case *Con:
		w.buf = append(w.buf, vCon)

		if err := w.pos(x.Tag); err != nil {
			return err
		}

		return w.value(x.Payload)
	case *Law:
		w.buf = append(w.buf, vLaw)

		if err := w.pos(x.Arity); err != nil {
			return err
		}

		return w.form(x.Body)
	case *Pin:
		if _, ok := x.Value.(*Thunk); ok {
			return errors.New("binary: a pin of a thunk has no binary form")
		}

		w.buf = append(w.buf, vPin)

		return w.value(x.Value)
	case *Thunk:
		return errors.New("binary: a thunk has no binary form")
	case *big.Int, Small:
		w.integer(v)
	case NilT:
		w.buf = append(w.buf, vNil)
	}

	return nil
}

func (w *writer) form(n *Node) error {
	switch n.Op {
	case OpLit:
		w.buf = append(w.buf, fLit)

		return w.value(n.Lit)
	case OpArg:
		w.buf = append(w.buf, fArg)

		return w.pos(n.Index)
	case OpCall, OpDelay:
		if n.Op == OpDelay {
			w.buf = append(w.buf, fDelay)
		} else {
			w.buf = append(w.buf, fCall)
		}

		if err := w.pos(len(n.Kids) - 1); err != nil {
			return err
		}

		for _, k := range n.Kids {
			if err := w.form(k); err != nil {
				return err
			}
		}

		return nil
	case OpCon:
		w.buf = append(w.buf, fCon)

		if err := w.pos(n.Tag); err != nil {
			return err
		}

		return w.form(n.Kids[0])
	case OpCase:
		w.buf = append(w.buf, fCase)

		if err := w.form(n.Kids[0]); err != nil {
			return err
		}

		if err := w.pos(len(n.Alts)); err != nil {
			return err
		}

		for _, a := range n.Alts {
			if err := w.pos(a.Tag); err != nil {
				return err
			}

			if err := w.form(a.Body); err != nil {
				return err
			}
		}

		if n.Else == nil {
			w.buf = append(w.buf, 0)

			return nil
		}

		w.buf = append(w.buf, 1)

		return w.form(n.Else)
	case OpIf:
		w.buf = append(w.buf, fIf)

		for _, k := range n.Kids {
			if err := w.form(k); err != nil {
				return err
			}
		}

		return nil
	case OpLet:
		w.buf = append(w.buf, fLet)

		for _, k := range n.Kids {
			if err := w.form(k); err != nil {
				return err
			}
		}

		return nil
	case OpForce:
		w.buf = append(w.buf, fForce)

		return w.form(n.Kids[0])
	case OpPrim:
		if n.Tag < 0 || n.Tag >= len(primArity) {
			return fmt.Errorf("binary: primitive %d does not exist", n.Tag)
		}

		if len(n.Kids) != primArity[n.Tag] {
			return fmt.Errorf("binary: primitive %d takes %d arguments, but is given %d", n.Tag, primArity[n.Tag], len(n.Kids))
		}

		w.buf = append(w.buf, fPrim)

		if err := w.pos(n.Tag); err != nil {
			return err
		}

		for _, k := range n.Kids {
			if err := w.form(k); err != nil {
				return err
			}
		}

		return nil
	}

	return errors.New("binary: a form of no kind")
}

func (r *reader) value() (Value, error) {
	t, err := r.byteOf("a value")
	if err != nil {
		return nil, err
	}

	switch t {
	case vNil:
		return NIL, nil
	case vCell:
		h, err := r.value()
		if err != nil {
			return nil, err
		}

		tl, err := r.value()
		if err != nil {
			return nil, err
		}

		return &Cell{
			Head: h,
			Tail: tl,
		}, nil
	case vPos:
		return r.integer(false)
	case vNeg:
		return r.integer(true)
	case vCon:
		tag, err := r.pos("a tag")
		if err != nil {
			return nil, err
		}

		p, err := r.value()
		if err != nil {
			return nil, err
		}

		return &Con{
			Tag: tag,
			Payload: p,
		}, nil
	case vLaw:
		arity, err := r.pos("an arity")
		if err != nil {
			return nil, err
		}

		if arity < 1 {
			return nil, errors.New("binary: an arity is at least 1")
		}

		body, err := r.form()
		if err != nil {
			return nil, err
		}

		return &Law{
			Arity: arity,
			Body: body,
		}, nil
	case vApp:
		lv, err := r.value()
		if err != nil {
			return nil, err
		}

		law, ok := lv.(*Law)
		if !ok {
			return nil, errors.New("binary: a partial application needs a law")
		}

		n, err := r.pos("a count")
		if err != nil {
			return nil, err
		}

		if n < 1 || n >= law.Arity {
			return nil, errors.New("binary: a partial application has fewer arguments than its law's arity, and at least one")
		}

		var args []Value

		for range n {
			a, err := r.value()
			if err != nil {
				return nil, err
			}

			args = append(args, a)
		}

		return &App{
			Law: law,
			Args: args,
		}, nil
	case vPin:
		v, err := r.value()
		if err != nil {
			return nil, err
		}

		return &Pin{
			Value: v,
		}, nil
	}

	return nil, fmt.Errorf("binary: tag %d is not a value", t)
}

func (r *reader) form() (*Node, error) {
	t, err := r.byteOf("a form")
	if err != nil {
		return nil, err
	}

	switch t {
	case fLit:
		v, err := r.value()
		if err != nil {
			return nil, err
		}

		return r.node(Node{
			Op: OpLit,
			Lit: v,
		}), nil
	case fArg:
		i, err := r.pos("an index")
		if err != nil {
			return nil, err
		}

		return r.node(Node{
			Op: OpArg,
			Index: i,
		}), nil
	case fCall, fDelay:
		n, err := r.pos("a count")
		if err != nil {
			return nil, err
		}

		// The parts are appended as they are read, so a count larger than the bytes cannot allocate what it claims.
		var kids []*Node

		for i := 0; i <= n; i++ {
			k, err := r.form()
			if err != nil {
				return nil, err
			}

			kids = append(kids, k)
		}

		if t == fDelay {
			return r.node(Node{
				Op: OpDelay,
				Kids: kids,
			}), nil
		}

		return r.node(Node{
			Op: OpCall,
			Kids: kids,
		}), nil
	case fCon:
		tag, err := r.pos("a tag")
		if err != nil {
			return nil, err
		}

		e, err := r.form()
		if err != nil {
			return nil, err
		}

		return r.node(Node{
			Op: OpCon,
			Tag: tag,
			Kids: []*Node{e},
		}), nil
	case fCase:
		e, err := r.form()
		if err != nil {
			return nil, err
		}

		k, err := r.pos("a count")
		if err != nil {
			return nil, err
		}

		n := r.node(Node{
			Op: OpCase,
			Kids: []*Node{e},
		})
		seen := map[int]bool{}

		for range k {
			tag, err := r.pos("a tag")
			if err != nil {
				return nil, err
			}

			if seen[tag] {
				return nil, fmt.Errorf("binary: the case has tag %d twice", tag)
			}

			seen[tag] = true

			body, err := r.form()
			if err != nil {
				return nil, err
			}

			n.Alts = append(n.Alts, Alt{
				Tag: tag,
				Body: body,
			})
		}

		flag, err := r.byteOf("the else flag")
		if err != nil {
			return nil, err
		}

		switch flag {
		case 0:
		case 1:
			if n.Else, err = r.form(); err != nil {
				return nil, err
			}
		default:
			return nil, errors.New("binary: the else flag is 0 or 1")
		}

		return n, nil
	case fIf:
		kids := r.kids(3)

		for i := range kids {
			if kids[i], err = r.form(); err != nil {
				return nil, err
			}
		}

		return r.node(Node{
			Op: OpIf,
			Kids: kids,
		}), nil
	case fLet:
		e, err := r.form()
		if err != nil {
			return nil, err
		}

		b, err := r.form()
		if err != nil {
			return nil, err
		}

		return r.node(Node{
			Op: OpLet,
			Kids: []*Node{e, b},
		}), nil
	case fForce:
		e, err := r.form()
		if err != nil {
			return nil, err
		}

		return r.node(Node{
			Op: OpForce,
			Kids: []*Node{e},
		}), nil
	case fPrim:
		op, err := r.pos("a primitive")
		if err != nil {
			return nil, err
		}

		if op >= len(primArity) {
			return nil, fmt.Errorf("binary: primitive %d does not exist", op)
		}

		kids := r.kids(primArity[op])

		for i := range kids {
			if kids[i], err = r.form(); err != nil {
				return nil, err
			}
		}

		return r.node(Node{
			Op: OpPrim,
			Tag: op,
			Kids: kids,
		}), nil
	}

	return nil, fmt.Errorf("binary: tag %d is not a form", t)
}

// DecodeProgram reads bytes that must be exactly one program.
func DecodeProgram(s []byte) (*Law, error) {
	if len(s) < 1 || s[0] != programHeader {
		return nil, errors.New("binary: the bytes are not a program")
	}

	r := &reader{
		s: s,
		p: 1,
	}

	arity, err := r.pos("an arity")
	if err != nil {
		return nil, err
	}

	if arity != 1 {
		return nil, errors.New("binary: a program is a law of arity 1")
	}

	body, err := r.form()
	if err != nil {
		return nil, err
	}

	if r.p < len(s) {
		return nil, errors.New("binary: there are bytes after the program")
	}

	return &Law{
		Arity: 1,
		Body: body,
	}, nil
}

// DecodeValue reads bytes that must be exactly one value.
func DecodeValue(s []byte) (Value, error) {
	if len(s) < 1 || s[0] != valueHeader {
		return nil, errors.New("binary: the bytes are not a value")
	}

	r := &reader{
		s: s,
		p: 1,
	}

	v, err := r.value()
	if err != nil {
		return nil, err
	}

	if r.p < len(s) {
		return nil, errors.New("binary: there are bytes after the value")
	}

	return v, nil
}

// EncodeProgram writes a program: a law of arity 1, with the program header.
func EncodeProgram(l *Law) ([]byte, error) {
	if l.Arity != 1 {
		return nil, errors.New("binary: a program is a law of arity 1")
	}

	w := &writer{
		buf: []byte{programHeader},
	}

	w.mag(1)

	if err := w.form(l.Body); err != nil {
		return nil, err
	}

	return w.buf, nil
}

// EncodeValue writes a value, with the value header (SPEC.md section 12.1).
func EncodeValue(v Value) ([]byte, error) {
	w := &writer{
		buf: []byte{valueHeader},
	}

	if err := w.value(v); err != nil {
		return nil, err
	}

	return w.buf, nil
}
