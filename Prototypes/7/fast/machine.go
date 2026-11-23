package fast

import "fmt"

type (
	// Outcome is the result of a run (SPEC.md section 5). Status is "value", "error" or "out_of_fuel". Steps is the fuel used (section 6).
	Outcome struct {
		Status string
		Value Value
		Message string
		Steps int64
	}

	contKind uint8

	// cont is a continuation: what to do with the next value. Each kind uses the fields it names. It is kept small, since every form that has children pushes one: the rarer kinds keep their fields in ext.
	cont struct {
		kind contKind
		node *Node
		env []Value // kItems: the frame; kApplyRest: the arguments over the arity
		vbase, i int
		ext *contExt
	}

	// contExt holds the fields of the continuations that are rarely pushed: a thunk to store into (kForce), and a memoised call's key and the step it began at (kMemo).
	contExt struct {
		th *Thunk
		key string
		start int64
	}

	mode uint8
)

const (
	mEval mode = iota
	mRet
	mApply
	// mItems: the children of node, from index i, are evaluated. A leaf (lit, arg) is evaluated in place, as its own step, and a form with children is evaluated with a continuation.
	mItems
	// mFinish: every child of node is done, and its values are vs[vbase:]. The form is finished.
	mFinish
)

const (
	// kItems: a form with children, waiting for the child at index i.
	kItems contKind = iota
	// kApplyRest: the arguments that a call has over the law's arity, to apply to its result.
	kApplyRest
	// kForce: a thunk, to store the result in once its call has run.
	kForce
	// kMemo: a memoised call, to store its result under key, with the fuel it used since start.
	kMemo
)

// StepHook, when set, is told the law of each step the machine charges: the frame's law for a form, and the callee for an entry. It is for measurement (the core's profile); the results do not depend on it.
var StepHook func(law Value)

func fail(msg string, steps int64) Outcome {
	return Outcome{
		Status: "error",
		Message: msg,
		Steps: steps,
	}
}

// machine runs the machine with an explicit stack. In mode mEval it evaluates node in env; in mApply it applies fv to args; in mRet it gives value to the continuation on top. Operands are kept on vs, and each items continuation remembers where its own operands start, so nothing is copied to make a frame.
func machine(m mode, node *Node, env []Value, fv Value, args []Value, fuel int64) Outcome {
	var (
		k []cont
		vs []Value
		steps int64
		value Value
		vbase, i int // mItems and mFinish: where node's operands start, and the next child
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

			if StepHook != nil {
				StepHook(env[0])
			}

			switch node.Op {
			case OpLit:
				value = node.Lit
				m = mRet
			case OpArg:
				if node.Index < 0 || node.Index >= len(env) {
					return fail(fmt.Sprintf("no slot %d in the frame", node.Index), steps)
				}

				value = env[node.Index]
				m = mRet
			default:
				vbase = len(vs)
				i = 0
				m = mItems
			}
		case mItems:
			items := node.items()

			var pending bool

			for ; i < len(items); i++ {
				c := items[i]
				if c.Op != OpLit && c.Op != OpArg {
					// A form with children: its continuation records where its operands start and which child it waits for.
					k = append(k, cont{
						kind: kItems,
						node: node,
						env: env,
						vbase: vbase,
						i: i,
					})
					node = c
					m = mEval
					pending = true

					break
				}

				// A leaf is a step of its own, as in mEval, so the fuel and the steps are the same as with a continuation.
				if steps >= fuel {
					return Outcome{
						Status: "out_of_fuel",
						Steps: steps,
					}
				}

				steps++

				if StepHook != nil {
					StepHook(env[0])
				}

				if c.Op == OpLit {
					vs = append(vs, c.Lit)
					continue
				}

				if c.Index < 0 || c.Index >= len(env) {
					return fail(fmt.Sprintf("no slot %d in the frame", c.Index), steps)
				}

				vs = append(vs, env[c.Index])
			}

			if !pending {
				m = mFinish
			}
		case mFinish:
			cnode := node
			vals := vs[vbase:]
			m = mRet

			switch cnode.Op {
			case OpCall:
				fv = vals[0]
				// The arguments alias the operands, which are cut back below. They are read once, to build the frame or a partial application (which copies them), so nothing outlives the operands.
				args = vals[1:]
				m = mApply
			case OpCon:
				value = &Con{
					Tag: cnode.Tag,
					Payload: vals[0],
				}
			case OpCase:
				con, ok := vals[0].(*Con)
				if !ok {
					return fail("case of a value that is not a constructor", steps)
				}

				var branch *Node

				pushed := vals[0]

				for _, a := range cnode.Alts {
					if a.Tag == con.Tag {
						branch = a.Body
						pushed = con.Payload

						break
					}
				}

				if branch == nil {
					if cnode.Else == nil {
						return fail(fmt.Sprintf("no branch for the constructor's tag %d", con.Tag), steps)
					}

					branch = cnode.Else
				}

				node = branch

				env = append(env, pushed)
				m = mEval
			case OpIf:
				if !isInt(vals[0]) {
					return fail("if needs an integer condition", steps)
				}

				if sign(vals[0]) != 0 {
					node = cnode.Kids[1]
				} else {
					node = cnode.Kids[2]
				}

				m = mEval
			case OpLet:
				node = cnode.Kids[1]

				env = append(env, vals[0])
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
						ext: &contExt{
							th: th,
						},
					})
					fv = th.F
					args = th.Args
					m = mApply
				}
			case OpPrim:
				res, msg := prim(cnode.Tag, vals)
				if msg != "" {
					return fail(msg, steps)
				}

				value = res
			}

			vs = vs[:vbase]
		case mApply:
			var (
				law *Law
				have []Value // the arguments a partial application already has (fewer than the arity)
			)

			switch f := fv.(type) {
			case *App:
				law = f.Law
				have = f.Args
			case *Law:
				law = f
			default:
				return fail("a call of a value that is not a function", steps)
			}

			if len(have)+len(args) < law.Arity {
				// Not saturated: a partial application, which is not a law entry and costs nothing. It copies its arguments, which may alias the operands of a call (see the call's finish).
				if len(have)+len(args) == 0 {
					value = law
				} else {
					all := make([]Value, 0, len(have)+len(args))
					all = append(all, have...)
					all = append(all, args...)
					value = &App{
						Law: law,
						Args: all,
					}
				}

				m = mRet

				continue
			}

			// The frame, built straight from the function's arguments and the new ones: slot 0 is the law, then the arguments in order. What is over the arity is applied to the result, later.
			from := law.Arity - len(have)
			slots := make([]Value, law.Arity+1)
			slots[0] = law

			copy(slots[1:], have)
			copy(slots[1+len(have):], args[:from])

			var extra []Value

			if len(args) > from {
				extra = args[from:]
			}

			saturated := len(extra) == 0
			args := slots[1:]

			// A saturated call of a law that has a jet: the jet gives the result and the fuel the body would use (jets.go). It is taken only when the whole call fits in the fuel; otherwise the body runs and stops at the spec's step.
			if JetsOn && saturated {
				if fn := jetFor(law); fn != nil {
					if res, cost, ok := fn(args); ok && steps+cost <= fuel {
						steps += cost
						value = res
						m = mRet

						continue
					}
				}
			}

			var (
				// A memoised call (memo.go): a hit charges the stored fuel, if the whole call fits in the fuel; a miss is stored when the call returns.
				memoKeyOf string
				memoOn bool
			)

			if MemoOn && saturated {
				if key, ok := memoKey(law, args); ok {
					if e, hit := memo[key]; hit {
						if steps+e.fuel <= fuel {
							steps += e.fuel
							MemoCounts.Hits++
							MemoCounts.ChargedFuel += e.fuel
							value = e.value
							m = mRet

							continue
						}
					} else {
						MemoCounts.Misses++
						memoKeyOf = key
						memoOn = true
					}
				}
			}

			start := steps

			if steps >= fuel {
				return Outcome{
					Status: "out_of_fuel",
					Steps: steps,
				}
			}

			steps++

			if memoOn {
				k = append(k, cont{
					kind: kMemo,
					ext: &contExt{
						key: memoKeyOf,
						start: start,
					},
				})
			}

			if len(extra) > 0 {
				k = append(k, cont{
					kind: kApplyRest,
					env: append([]Value(nil), extra...),
				})
			}

			env = slots

			if StepHook != nil {
				StepHook(law)
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

			c := &k[len(k)-1]

			switch c.kind {
			case kItems:
				// The child at c.i has finished with value. Its operands are the ones before it, so the operands are cut back to that point before it is added.
				cnode, cenv, cvbase, ci := c.node, c.env, c.vbase, c.i
				vs = append(vs[:cvbase+ci], value)
				k = k[:len(k)-1]
				node, env, vbase, i = cnode, cenv, cvbase, ci+1
				m = mItems
			case kApplyRest:
				fv = value
				args = c.env
				m = mApply
				k = k[:len(k)-1]
			case kForce:
				c.ext.th.Done = true
				c.ext.th.Result = value
				k = k[:len(k)-1]
			case kMemo:
				// A call that used little fuel saves little work, and an entry for it costs memory: only calls of at least MemoMinFuel steps are stored (memo.go). The fuel is the same either way.
				if steps-c.ext.start >= MemoMinFuel {
					memo[c.ext.key] = memoEntry{
						value: value,
						fuel: steps - c.ext.start,
					}
					MemoCounts.Stores++
				}

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
	return machine(mEval, body, []Value{NIL, input}, nil, nil, fuel)
}
