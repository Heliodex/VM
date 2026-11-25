package fast

import (
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"
)

// The indented printer: it turns the parse tree of a program section into the indented spelling the layer reads (Prototypes/8/l2/INDENTATION.md, section 11). A line is a node: its text, and the lines below it (its kids), one level deeper. Brackets are used only inline: a form that fits on its line, and has no block in it, is written as the bracketed form (a list, a pair, an application, an if). A form with a block (fn, let, letrec, match, with, a record, an application or an if that does not fit) is a line with its kids below it.
//
// The tags of the parser's trees are the constructors' numbers (parse.l2): Expr: EInt 0, EStr 1, ENil 2, EName 3, EList 4, EPair 5, EApp 6, EFn 7, ELet 8, EMutual 9, EIf 10, EMatch 11, ETry 12, ECheck 13, EUntyped 14, ERec 15, EWith 16. Pat: PCon 0, PBind 1, PWild 2, PRec 3. Ty: TName 0, TApp 1, TPair 2, TList 3, TFun 4, NoType 5, TRec 6.

// pnode is a line of the printed source, and the lines below it.
type pnode struct {
	text string
	kids []pnode
}

// printWidth is the widest line the printer writes, counting a tab as four columns and a codepoint as one.
const printWidth = 80

// tuple reads the first n items of a payload that is a right-nested tuple (⟨a b c⟩ is (a . (b . c))).
func tuple(v Value, n int) []Value {
	out := make([]Value, 0, n)

	for i := 0; i < n-1; i++ {
		c, ok := v.(*Cell)
		if !ok {
			panic(fmt.Sprintf("print: a payload of %d items is not a tuple", n))
		}

		out = append(out, c.Head)
		v = c.Tail
	}

	return append(out, v)
}

// items reads a list.
func items(v Value) []Value {
	var out []Value

	for {
		c, ok := v.(*Cell)
		if !ok {
			return out
		}

		out = append(out, c.Head)
		v = c.Tail
	}
}

func conOf(v Value) *Con {
	c, ok := v.(*Con)
	if !ok {
		panic(fmt.Sprintf("print: a %T, not a constructor", v))
	}

	return c
}

func intOf(v Value) int64 {
	s, ok := v.(Small)
	if !ok {
		panic(fmt.Sprintf("print: a %T, not an integer", v))
	}

	return int64(s)
}

// nameOf is the text of a name (a list of codepoints).
func nameOf(v Value) string {
	return pipeText(v)
}

// quoteString is a string literal, with the escapes the lexer reads.
func quoteString(v Value) string {
	var b strings.Builder

	b.WriteByte('"')

	for _, it := range items(v) {
		switch c := intOf(it); c {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\n':
			b.WriteString(`\n`)
		case '\t':
			b.WriteString(`\t`)
		case 0:
			b.WriteString(`\0`)
		default:
			b.WriteString(pipeText(&Cell{Head: Small(c), Tail: NIL}))
		}
	}

	b.WriteByte('"')

	return b.String()
}

// fits is whether a line of text, at a depth of indentation, is within the print width.
func fits(text string, depth int) bool {
	return 4*depth+utf8.RuneCountInString(text) <= printWidth
}

// inlineExpr is an expression written on one line, if it has no block: ok is false when it needs lines below it.
func inlineExpr(v Value) (string, bool) {
	c := conOf(v)

	switch c.Tag {
	case 0: // EInt
		return strconv.FormatInt(intOf(tuple(c.Payload, 3)[0]), 10), true
	case 1: // EStr
		return quoteString(tuple(c.Payload, 3)[0]), true
	case 2: // ENil
		return "~", true
	case 3: // EName
		return nameOf(tuple(c.Payload, 3)[0]), true
	case 4: // EList
		parts := []string{}

		for _, it := range items(tuple(c.Payload, 3)[0]) {
			s, ok := inlineAtom(it)
			if !ok {
				return "", false
			}

			parts = append(parts, s)
		}

		return "[" + strings.Join(parts, " ") + "]", true
	case 5: // EPair
		p := tuple(c.Payload, 4)

		a, ok := inlineAtom(p[0])
		if !ok {
			return "", false
		}

		b, ok := inlineAtom(p[1])
		if !ok {
			return "", false
		}

		return "⟨" + a + " " + b + "⟩", true
	case 6: // EApp
		p := tuple(c.Payload, 4)

		f, ok := inlineAtom(p[0])
		if !ok {
			return "", false
		}

		args := []string{}

		for _, it := range items(p[1]) {
			s, ok := inlineAtom(it)
			if !ok {
				return "", false
			}

			args = append(args, s)
		}

		return "(" + f + " " + strings.Join(args, " ") + ")", true
	case 10: // EIf
		p := tuple(c.Payload, 5)

		var parts []string

		for _, it := range p[:3] {
			s, ok := inlineAtom(it)
			if !ok {
				return "", false
			}

			parts = append(parts, s)
		}

		return "(if " + strings.Join(parts, " ") + ")", true
	case 12: // ETry: an application already has its brackets, so the ? follows them
		p := tuple(c.Payload, 3)

		e, ok := inlineAtom(p[0])
		if !ok {
			return "", false
		}

		if conOf(p[0]).Tag == 6 {
			return e + "?", true
		}

		return "(" + e + ")?", true
	case 13: // ECheck
		p := tuple(c.Payload, 3)

		e, ok := inlineAtom(p[0])
		if !ok {
			return "", false
		}

		return "(check " + e + ")", true
	case 14: // EUntyped
		p := tuple(c.Payload, 3)

		e, ok := inlineAtom(p[0])
		if !ok {
			return "", false
		}

		return "(untyped " + e + ")", true
	}

	return "", false
}

// inlineAtom is an expression written as an atom on one line. A try (e)? is wrapped, so that it reads as an atom.
func inlineAtom(v Value) (string, bool) {
	s, ok := inlineExpr(v)
	if !ok {
		return "", false
	}

	if conOf(v).Tag == 12 {
		return "(" + s + ")", true
	}

	return s, true
}

// fitInline is the expression on one line at a depth, if it has no block and fits.
func fitInline(v Value, depth int) (string, bool) {
	s, ok := inlineExpr(v)
	if !ok {
		return "", false
	}

	// An application or an if can be broken over lines, so it is written on one line only when it fits. Other forms (a name, a string, a list, a pair) are not broken, and stay on one line.
	if tag := conOf(v).Tag; (tag == 6 || tag == 10) && !fits(s, depth) {
		return "", false
	}

	return s, true
}

// mustInline is an expression that must be on one line, such as a scrutinee or a field's value.
func mustInline(v Value) string {
	s, ok := inlineExpr(v)
	if !ok {
		panic("print: an expression with lines below it is used inline")
	}

	return s
}

// patText is a pattern on one line (a record pattern is written by armNodes, since it has lines below it).
func patText(v Value) string {
	c := conOf(v)

	switch c.Tag {
	case 0: // PCon
		p := tuple(c.Payload, 4)
		name := nameOf(p[0])

		if _, isNil := p[1].(NilT); !isNil {
			return name + " " + nameOf(p[1])
		}

		return name
	case 1: // PBind
		return nameOf(tuple(c.Payload, 3)[0])
	case 2: // PWild
		return "_"
	}

	panic("print: a record pattern is written with lines below it")
}

// tyText is a type on one line.
func tyText(v Value) string {
	c := conOf(v)

	switch c.Tag {
	case 0: // TName
		return nameOf(tuple(c.Payload, 3)[0])
	case 1: // TApp
		p := tuple(c.Payload, 4)

		var parts []string

		for _, it := range items(p[1]) {
			parts = append(parts, tyText(it))
		}

		return "(" + nameOf(p[0]) + " " + strings.Join(parts, " ") + ")"
	case 2: // TPair
		p := tuple(c.Payload, 4)

		return "⟨" + tyText(p[0]) + " " + tyText(p[1]) + "⟩"
	case 3: // TList
		return "[" + tyText(tuple(c.Payload, 3)[0]) + "]"
	case 4: // TFun
		p := tuple(c.Payload, 4)

		return "(" + tyText(p[0]) + " -> " + tyText(p[1]) + ")"
	case 5: // NoType
		return ""
	}

	panic("print: a record type is written with lines below it")
}

// paramsText is the parameters of a fn: one name, or several in brackets.
func paramsText(names []Value) string {
	var parts []string

	for _, n := range names {
		parts = append(parts, nameOf(n))
	}

	if len(parts) == 1 {
		return parts[0]
	}

	return "(" + strings.Join(parts, " ") + ")"
}

// exprSeq is the lines of an expression in a block at a depth: a let or an if takes the lines after it as its body, so a block is a sequence of lines.
func exprSeq(v Value, depth int) []pnode {
	if s, ok := fitInline(v, depth); ok {
		return []pnode{{text: s}}
	}

	c := conOf(v)

	switch c.Tag {
	case 8: // ELet
		p := tuple(c.Payload, 6)
		kw := "let "

		if intOf(p[3]) == 1 {
			kw = "letrec "
		}

		head := bindingNode(kw+nameOf(p[0]), p[1], depth)

		return append([]pnode{head}, exprSeq(p[2], depth)...)
	case 9: // EMutual: a letrec block of bindings, then the body
		p := tuple(c.Payload, 4)

		block := pnode{text: "letrec"}

		for _, b := range items(p[0]) {
			bp := tuple(b, 4)
			block.kids = append(block.kids, bindingNode(nameOf(bp[0]), bp[1], depth+1))
		}

		return append([]pnode{block}, exprSeq(p[1], depth)...)
	case 10: // EIf: a block if
		p := tuple(c.Payload, 5)

		return ifNodes(p[0], p[1], p[2], depth)
	case 11: // EMatch
		p := tuple(c.Payload, 4)

		head := pnode{text: "match " + mustInline(p[0])}

		for _, arm := range items(p[1]) {
			ap := tuple(arm, 4)
			head.kids = append(head.kids, armNodes(ap[0], ap[1], depth+1)...)
		}

		return []pnode{head}
	}

	return []pnode{exprNode(v, depth)}
}

// ifNodes is an if as lines at a depth: the if line, its then-branch below it, any elseif lines, and the else.
func ifNodes(cond, then, els Value, depth int) []pnode {
	nodes := []pnode{{text: "if " + mustInline(cond), kids: exprSeq(then, depth+1)}}

	for {
		c := conOf(els)

		if c.Tag != 10 {
			break
		}

		p := tuple(c.Payload, 5)

		nodes = append(nodes, pnode{text: "elseif " + mustInline(p[0]), kids: exprSeq(p[1], depth+1)})
		els = p[2]
	}

	return append(nodes, pnode{text: "else", kids: exprSeq(els, depth+1)})
}

// armNodes is a match arm at a depth: its pattern and its body, on one line if the body fits there, else with the body below.
func armNodes(pat, body Value, depth int) []pnode {
	pc := conOf(pat)

	if pc.Tag == 3 { // PRec: the constructor with its fields below, then the body at the same level
		p := tuple(pc.Payload, 4)

		head := pnode{text: nameOf(p[0])}

		for _, f := range items(p[1]) {
			fp := tuple(f, 4)

			if _, isNil := fp[1].(NilT); isNil {
				head.kids = append(head.kids, pnode{text: nameOf(fp[0])})
			} else {
				head.kids = append(head.kids, pnode{text: nameOf(fp[0]) + " = " + nameOf(fp[1])})
			}
		}

		return append([]pnode{head}, arrowNodes("", body, depth)...)
	}

	return arrowNodes(patText(pat), body, depth)
}

// arrowNodes is the line of an arm, pat -> body, at a depth, with the body below when it does not fit on the line.
func arrowNodes(pat string, body Value, depth int) []pnode {
	head := "->"
	if pat != "" {
		head = pat + " ->"
	}

	if s, ok := inlineExpr(body); ok && fits(head+" "+s, depth) {
		return []pnode{{text: head + " " + s}}
	}

	return []pnode{{text: head, kids: exprSeq(body, depth+1)}}
}

// bindingNode is head = value, a let or a binding at a depth. A value that fits follows the = on the line; a fn takes its body below it; any other block is the lines below the line.
func bindingNode(head string, value Value, depth int) pnode {
	if s, ok := inlineExpr(value); ok && fits(head+" = "+s, depth) {
		return pnode{text: head + " = " + s}
	}

	c := conOf(value)

	if c.Tag == 7 { // EFn
		p := tuple(c.Payload, 4)

		return pnode{text: head + " = fn " + paramsText(items(p[0])), kids: exprSeq(p[1], depth+1)}
	}

	return pnode{text: head + " =", kids: exprSeq(value, depth+1)}
}

// exprNode is an expression as one line at a depth, with the lines below it when it has a block: an application across lines, a fn, a record, or a with.
func exprNode(v Value, depth int) pnode {
	if s, ok := fitInline(v, depth); ok {
		return pnode{text: s}
	}

	c := conOf(v)

	switch c.Tag {
	case 6: // EApp across lines: the head on the line, one argument to a line below
		p := tuple(c.Payload, 4)

		n := pnode{text: mustInline(p[0])}

		for _, a := range items(p[1]) {
			n.kids = append(n.kids, exprNode(a, depth+1))
		}

		return n
	case 7: // EFn
		p := tuple(c.Payload, 4)

		return pnode{text: "fn " + paramsText(items(p[0])), kids: exprSeq(p[1], depth+1)}
	case 15: // ERec: a constructor with its fields below
		p := tuple(c.Payload, 4)

		n := pnode{text: nameOf(p[0])}

		for _, f := range items(p[1]) {
			fp := tuple(f, 4)

			n.kids = append(n.kids, pnode{text: nameOf(fp[0]) + " = " + mustInline(fp[1])})
		}

		return n
	case 16: // EWith: the expression, then the fields below it
		p := tuple(c.Payload, 4)

		n := pnode{text: "with " + mustInline(p[0])}

		for _, f := range items(p[1]) {
			fp := tuple(f, 4)

			n.kids = append(n.kids, pnode{text: nameOf(fp[0]) + " = " + mustInline(fp[1])})
		}

		return n
	}

	panic(fmt.Sprintf("print: an expression of tag %d has lines below it in a place the layer does not take", c.Tag))
}

// typeDecl is a type declaration: a sum, one | line per constructor, or a record with its fields below it. A record constructor, in a sum or on its own, has its fields below its line.
func typeDecl(d Value) pnode {
	p := tuple(d, 4)

	head := nameOf(p[0])

	if ps := items(p[1]); len(ps) > 0 {
		var names []string

		for _, x := range ps {
			names = append(names, nameOf(x))
		}

		head += " " + strings.Join(names, " ")
	}

	cons := items(p[2])

	recordLines := func(cp []Value) pnode {
		n := pnode{text: nameOf(cp[0])}

		for _, f := range items(conOf(cp[1]).Payload) {
			fp := tuple(f, 4)

			n.kids = append(n.kids, pnode{text: nameOf(fp[0]) + ": " + tyText(fp[1])})
		}

		return n
	}

	if len(cons) == 1 {
		cp := tuple(cons[0], 3)

		if conOf(cp[1]).Tag == 6 {
			n := recordLines(cp)
			n.text = "type " + head + " = " + n.text

			return n
		}
	}

	n := pnode{text: "type " + head + " ="}

	for _, cn := range cons {
		cp := tuple(cn, 3)

		if conOf(cp[1]).Tag == 6 {
			r := recordLines(cp)
			r.text = "| " + r.text
			n.kids = append(n.kids, r)

			continue
		}

		line := "| " + nameOf(cp[0])

		if t := tyText(cp[1]); t != "" {
			line += " " + t
		}

		n.kids = append(n.kids, pnode{text: line})
	}

	return n
}

// serializeNodes writes lines, with one tab for each level of depth.
func serializeNodes(nodes []pnode, depth int, b *strings.Builder) {
	for _, n := range nodes {
		b.WriteString(strings.Repeat("\t", depth))
		b.WriteString(n.text)
		b.WriteByte('\n')

		serializeNodes(n.kids, depth+1, b)
	}
}

// PrintSection is the indented spelling of a program section: its type declarations, then its body. It takes the parse tree, Ok of (decls . expr) as the parse stage gives it, without the Ok.
func PrintSection(parsed Value) (text string, err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("%v", r)
		}
	}()

	parts := tuple(parsed, 2)

	var nodes []pnode

	for _, d := range items(parts[0]) {
		nodes = append(nodes, typeDecl(d))
	}

	nodes = append(nodes, exprSeq(parts[1], 0)...)

	var b strings.Builder

	serializeNodes(nodes, 0, &b)

	return b.String(), nil
}

// ParseSection is the parse tree of a program section, Ok of (decls . expr) as the parse stage gives it, after the layout that a file named .l2 gets (Compile does the same). It gives the payload of the Ok.
func (s Stages) ParseSection(text string) (Value, error) {
	section, err := pipeSource(text)
	if err != nil {
		return nil, err
	}

	payload, err := s.run("layout", section, stageFuelLayout)
	if err != nil {
		return nil, err
	}

	if section, err = resultPayload(payload); err != nil {
		return nil, fmt.Errorf("layout: %w", err)
	}

	payload, err = s.run("lex", section, stageFuelLex)
	if err != nil {
		return nil, err
	}

	if section, err = resultPayload(payload); err != nil {
		return nil, fmt.Errorf("lex: %w", err)
	}

	payload, err = s.run("parse", section, stageFuelParse)
	if err != nil {
		return nil, err
	}

	return resultPayload(payload)
}
