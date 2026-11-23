package fast

import "fmt"

type (
	// Env is a frame: slot 0 is the law, then the arguments, then what let and case push (SPEC.md section 2).
	Env struct {
		Slots []Value
	}

	// Outcome is the result of a run (SPEC.md section 5). Status is "value", "error" or "out_of_fuel". Steps is the fuel used (section 6).
	Outcome struct {
		Status string
		Value Value
		Message string
		Steps int64
	}

	contKind uint8

	// cont is a continuation: what to do with the next value. Each kind uses the fields it names.
	cont struct {
		kind contKind
		node *Node
		env *Env
		vbase, i, n int
		rest []Value
		th *Thunk
	}

	mode uint8
)

const (
	mEval mode = iota
	mRet
	mApply
)

const (
	// kItems: a form with children, waiting for the child at index i.
	kItems contKind = iota
	// kRestore: a let or a case body, after which the frame goes back to n slots.
	kRestore
	// kApplyRest: the arguments that a call has over the law's arity, to apply to its result.
	kApplyRest
	// kForce: a thunk, to store the result in once its call has run.
	kForce
)

func fail(msg string, steps int64) Outcome {
	return Outcome{
		Status: "error",
		Message: msg,
		Steps: steps,
	}
}

// machine runs the machine with an explicit stack. In mode mEval it evaluates node in env; in mApply it applies fv to args; in mRet it gives value to the continuation on top. Operands are kept on vs, and each items continuation remembers where its own operands start, so nothing is copied to make a frame.
func machine(m mode, node *Node, env *Env, fv Value, args []Value, fuel int64) Outcome {
	var (
		k []cont
		vs []Value
		steps int64
		value Value
	)

	for {
		switch m {
		case mEval:
			if steps >= fuel {
				return Outcome{
					Status: "out_of_fuel",
					Steps: steps,
				}
			}

			steps++

			switch node.Op {
			case OpLit:
				value = node.Lit
				m = mRet
			case OpArg:
				if node.Index < 0 || node.Index >= len(env.Slots) {
					return fail(fmt.Sprintf("no slot %d in the frame", node.Index), steps)
				}

				value = env.Slots[node.Index]
				m = mRet
			default:
				k = append(k, cont{
					kind: kItems,
					node: node,
					env: env,
					vbase: len(vs),
				})
				node = node.items()[0]
			}
		case mApply:
			var (
				law *Law
				all []Value
			)

			switch f := fv.(type) {
			case *App:
				law = f.Law
				all = make([]Value, 0, len(f.Args)+len(args))
				all = append(all, f.Args...)
				all = append(all, args...)
			case *Law:
				law = f
				all = args
			default:
				return fail("a call of a value that is not a function", steps)
			}

			n := len(all)
			if n < law.Arity {
				// Not saturated: a partial application, which is not a law entry and costs nothing.
				if n == 0 {
					value = law
				} else {
					value = &App{
						Law: law,
						Args: all,
					}
				}

				m = mRet

				continue
			}

			if steps >= fuel {
				return Outcome{
					Status: "out_of_fuel",
					Steps: steps,
				}
			}

			steps++

			if n > law.Arity {
				k = append(k, cont{
					kind: kApplyRest,
					rest: append([]Value(nil), all[law.Arity:]...),
				})
			}

			slots := make([]Value, law.Arity+1)
			slots[0] = law

			copy(slots[1:], all[:law.Arity])

			env = &Env{
				Slots: slots,
			}
			node = law.Body
			m = mEval
		case mRet:
			if len(k) == 0 {
				return Outcome{
					Status: "value",
					Value: value,
					Steps: steps,
				}
			}

			c := k[len(k)-1]

			switch c.kind {
			case kItems:
				// The child at c.i has finished with value. Its operands are the ones before it, so the operands are cut back to that point before it is added.
				vs = append(vs[:c.vbase+c.i], value)

				if items := c.node.items(); c.i+1 < len(items) {
					k[len(k)-1].i = c.i + 1
					node = items[c.i+1]
					env = c.env
					m = mEval

					continue
				}

				k = k[:len(k)-1]
				vals := vs[c.vbase:]
				m = mRet

				switch c.node.Op {
				case OpCall:
					fv = vals[0]
					args = append([]Value(nil), vals[1:]...)
					m = mApply
				case OpCell:
					value = &Cell{
						Head: vals[0],
						Tail: vals[1],
					}
				case OpCon:
					value = &Con{
						Tag: c.node.Tag,
						Payload: vals[0],
					}
				case OpCase:
					con, ok := vals[0].(*Con)
					if !ok {
						return fail("case of a value that is not a constructor", steps)
					}

					var branch *Node

					pushed := vals[0]

					for _, a := range c.node.Alts {
						if a.Tag == con.Tag {
							branch = a.Body
							pushed = con.Payload

							break
						}
					}

					if branch == nil {
						if c.node.Else == nil {
							return fail(fmt.Sprintf("no branch for the constructor's tag %d", con.Tag), steps)
						}

						branch = c.node.Else
					}

					k = append(k, cont{
						kind: kRestore,
						n: len(c.env.Slots),
						env: c.env,
					})
					c.env.Slots = append(c.env.Slots, pushed)
					node = branch
					env = c.env
					m = mEval
				case OpIf:
					if !isInt(vals[0]) {
						return fail("if needs an integer condition", steps)
					}

					if sign(vals[0]) != 0 {
						node = c.node.Kids[1]
					} else {
						node = c.node.Kids[2]
					}

					env = c.env
					m = mEval
				case OpLet:
					k = append(k, cont{
						kind: kRestore,
						n: len(c.env.Slots),
						env: c.env,
					})
					c.env.Slots = append(c.env.Slots, vals[0])
					node = c.node.Kids[1]
					env = c.env
					m = mEval
				case OpDelay:
					value = &Thunk{
						F: vals[0],
						Args: append([]Value(nil), vals[1:]...),
					}
				case OpForce:
					th, ok := vals[0].(*Thunk)
					if !ok {
						return fail("force of a value that is not a thunk", steps)
					}

					if th.Done {
						value = th.Result
					} else {
						k = append(k, cont{
							kind: kForce,
							th: th,
						})
						fv = th.F
						args = th.Args
						m = mApply
					}
				case OpPrim:
					res, msg := prim(c.node.Tag, vals)
					if msg != "" {
						return fail(msg, steps)
					}

					value = res
				}

				vs = vs[:c.vbase]
			case kRestore:
				c.env.Slots = c.env.Slots[:c.n]
				k = k[:len(k)-1]
			case kApplyRest:
				fv = value
				args = c.rest
				m = mApply
				k = k[:len(k)-1]
			case kForce:
				c.th.Done = true
				c.th.Result = value
				k = k[:len(k)-1]
			}
		}
	}
}

// Run applies a program (a law of arity 1) to an input. The application is a law entry, so it costs one step (SPEC.md section 5).
func Run(program *Law, input Value, fuel int64) Outcome {
	return machine(mApply, nil, nil, program, []Value{input}, fuel)
}

// RunBody evaluates the body of a law of arity 1 with the input as its argument, with no law entry: the frame is [NIL, input]. It is the reference's runForm, which the examples and the L2 tests use.
func RunBody(body *Node, input Value, fuel int64) Outcome {
	return machine(mEval, body, &Env{
		Slots: []Value{NIL, input},
	}, nil, nil, fuel)
}
