package fast

import "fmt"

// pins interns pins by their content: the same bytes give the same pin, as in the reference (SPEC.md section 4, primitive 10). It is a process-wide table, as the reference's is.
var pins = map[string]*Pin{}

// bit is the integer 1 for true, and 0 for false.
func bit(b bool) Value {
	if b {
		return Small(1)
	}

	return Small(0)
}

// pinOf is primitive 10: a pin of a value that is not a thunk, interned by its binary form.
func pinOf(a Value) (Value, string) {
	switch x := a.(type) {
	case *Pin:
		return x, ""
	case *Thunk:
		return nil, "a thunk cannot be pinned"
	}

	key, err := EncodeValue(a)
	if err != nil {
		return nil, "a pin has no binary form: " + err.Error()
	}

	if p, ok := pins[string(key)]; ok {
		return p, ""
	}

	p := &Pin{
		Value: a,
	}
	pins[string(key)] = p

	return p, ""
}

// prim applies primitive tag to vals (SPEC.md section 4). It gives the result, or a message when the primitive is an error. The message is empty when there is none.
func prim(tag int, vals []Value) (Value, string) {
	if tag >= 0 && tag <= 6 && (!isInt(vals[0]) || !isInt(vals[1])) {
		return nil, fmt.Sprintf("the integer operation %d needs integers", tag)
	}

	switch tag {
	case 0:
		return add(vals[0], vals[1]), ""
	case 1:
		return sub(vals[0], vals[1]), ""
	case 2:
		return mul(vals[0], vals[1]), ""
	case 3:
		if sign(vals[1]) == 0 {
			return nil, "division by zero"
		}

		return divFloor(vals[0], vals[1]), ""
	case 4:
		if sign(vals[1]) == 0 {
			return nil, "modulus by zero"
		}

		return modFloor(vals[0], vals[1]), ""
	case 5:
		return bit(compare(vals[0], vals[1]) < 0), ""
	case 6:
		return bit(compare(vals[0], vals[1]) == 0), ""
	case 7:
		return Small(KindOf(vals[0])), ""
	case 8:
		c, ok := vals[0].(*Cell)
		if !ok {
			return nil, "head of a value that is not a cell"
		}

		return c.Head, ""
	case 9:
		c, ok := vals[0].(*Cell)
		if !ok {
			return nil, "tail of a value that is not a cell"
		}

		return c.Tail, ""
	case 10:
		return pinOf(vals[0])
	case 11:
		p, ok := vals[0].(*Pin)
		if !ok {
			return nil, "unpin of a value that is not a pin"
		}

		return p.Value, ""
	case 12:
		if c, ok := vals[0].(*Con); ok {
			return Small(c.Tag), ""
		}

		return Small(-1), ""
	case 14:
		return &Cell{
			Head: vals[0],
			Tail: vals[1],
		}, ""
	case 13:
		c, ok := vals[0].(*Con)
		if !ok {
			return nil, "payload of a value that is not a constructor"
		}

		return c.Payload, ""
	}

	return nil, fmt.Sprintf("primitive %d does not exist", tag)
}
