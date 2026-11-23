package fast

import "fmt"

// The evaluator. A node is evaluated by a call, and its value is returned, so the Go stack holds the forms that are waiting: an operand is evaluated before the operation, as the spec's order says (SPEC.md section 3). The steps are the spec's: a node is charged when it is entered, and a saturated entry of a law is charged when it is applied. Errors and running out of fuel end the run by a panic, which Run and RunBody recover.
//
// A call in tail position is not a recursion: its body returns the call to a loop (runBody), which applies it, so a loop of any length uses the Go stack of one call.
//
// The depth of nested evaluations is limited (MaxNesting): a run that goes deeper ends with the status "host_limit", which the spec does not have, rather than with the Go stack overflowing.

type (
	// recRun is one run: its steps and fuel, its depth of nested evaluations, the operands on vs, and the tail call a body returns (tailFv, tailArgs).
	recRun struct {
		steps, fuel int64
		depth int
		vs []Value
		tailFv Value
		tailArgs []Value
	}

	// stopRun is the panic that ends a run with an outcome other than a value.
	stopRun struct {
		o Outcome
	}
)

// MaxNesting is the deepest a run may nest its evaluations (a form inside a form, a call inside a call). It bounds the Go stack: a nested evaluation takes about a kilobyte of it, and the default Go stack is one gigabyte. A run that goes deeper ends with the status "host_limit".
var MaxNesting = 400000

// makeFrame is the frame of a saturated entry of law: slot 0 is the law, then the arguments the law already had, then the new ones (the first arity - len(have) of args). The arguments after those are returned as extra, to apply to the result.
func makeFrame(law *Law, have, args []Value) (slots, extra []Value) {
	from := law.Arity - len(have)
	slots = make([]Value, law.Arity+1)
	slots[0] = law

	copy(slots[1:], have)
	copy(slots[1+len(have):], args[:from])

	if len(args) > from {
		extra = append([]Value(nil), args[from:]...)
	}

	return slots, extra
}

// partial gives the partial application of law to the arguments it has, when they are fewer than its arity: the law itself when there are none, otherwise an application. It is not an entry, so it costs nothing.
func partial(law *Law, have, args []Value) Value {
	if len(have)+len(args) == 0 {
		return law
	}

	all := make([]Value, 0, len(have)+len(args))
	all = append(all, have...)
	all = append(all, args...)

	return &App{
		Law: law,
		Args: all,
	}
}

// charge is the step of a form or an entry: out of fuel before it, or one more step.
func (r *recRun) charge() {
	if r.steps >= r.fuel {
		panic(stopRun{
			Outcome{
				Status: "out_of_fuel",
				Steps: r.steps,
			},
		})
	}

	r.steps++
}

// entry is the step of a law entry, and the hook that is told of it.
func (r *recRun) entry(law *Law) {
	r.charge()

	if StepHook != nil {
		StepHook(law)
	}
}

func (r *recRun) fail(msg string) {
	panic(stopRun{fail(msg, r.steps)})
}

// argOf gives the value of an argument: its slot in the frame.
func (r *recRun) argOf(node *Node, env []Value) Value {
	if node.Index < 0 || node.Index >= len(env) {
		r.fail(fmt.Sprintf("no slot %d in the frame", node.Index))
	}

	return env[node.Index]
}

// resolve gives the law of a function value and the arguments it already has. A value that is not a function fails. It is charged nothing.
func (r *recRun) resolve(fv Value) (*Law, []Value) {
	switch f := fv.(type) {
	case *App:
		return f.Law, f.Args
	case *Law:
		return f, nil
	}

	r.fail("a call of a value that is not a function")

	return nil, nil
}

// eval gives the value of node in env. In tail position, a call is not applied: eval returns (nil, true) and sets tailFv and tailArgs, for runBody to apply. Each node is charged when it is entered, and a node nested too deep ends the run (MaxNesting).
func (r *recRun) eval(node *Node, env []Value, tail bool) (Value, bool) {
	r.depth++

	if r.depth > MaxNesting {
		panic(stopRun{
			Outcome{
				Status: "host_limit",
				Message: fmt.Sprintf("the run nests its evaluations deeper than %d", MaxNesting),
				Steps: r.steps,
			},
		})
	}

	r.charge()

	if StepHook != nil {
		StepHook(env[0])
	}

	var (
		v Value
		t bool
	)

	switch node.Op {
	case OpLit:
		v = node.Lit
	case OpArg:
		v = r.argOf(node, env)
	case OpCall:
		v, t = r.call(node, env, tail)
	case OpCon:
		v = r.conOf(node, env)
	case OpCase:
		v, t = r.caseOf(node, env, tail)
	case OpIf:
		v, t = r.ifOf(node, env, tail)
	case OpLet:
		v, t = r.letOf(node, env, tail)
	case OpDelay:
		v = r.delay(node, env)
	case OpForce:
		v = r.force(node, env)
	case OpPrim:
		v = r.prim(node, env)
	default:
		panic("the form is not one the machine knows")
	}

	r.depth--

	return v, t
}

// conOf gives a constructor of the value of its child.
func (r *recRun) conOf(node *Node, env []Value) Value {
	v, _ := r.eval(node.Kids[0], env, false)

	return &Con{
		Tag: node.Tag,
		Payload: v,
	}
}

// ifOf evaluates an if: its condition, then the branch it picks.
func (r *recRun) ifOf(node *Node, env []Value, tail bool) (Value, bool) {
	v, _ := r.eval(node.Kids[0], env, false)
	if !isInt(v) {
		r.fail("if needs an integer condition")
	}

	if sign(v) != 0 {
		return r.eval(node.Kids[1], env, tail)
	}

	return r.eval(node.Kids[2], env, tail)
}

// letOf evaluates a let: its value, then its body with the value in the frame.
func (r *recRun) letOf(node *Node, env []Value, tail bool) (Value, bool) {
	v, _ := r.eval(node.Kids[0], env, false)

	return r.eval(node.Kids[1], append(env, v), tail)
}

// caseOf evaluates a case: its scrutinee, then the branch for its tag, with the payload (or the scrutinee, for the else branch) in the frame.
func (r *recRun) caseOf(node *Node, env []Value, tail bool) (Value, bool) {
	v, _ := r.eval(node.Kids[0], env, false)
	con, ok := v.(*Con)

	if !ok {
		r.fail("case of a value that is not a constructor")
	}

	var branch *Node

	pushed := v

	for _, a := range node.Alts {
		if a.Tag == con.Tag {
			branch = a.Body
			pushed = con.Payload

			break
		}
	}

	if branch == nil {
		if node.Else == nil {
			r.fail(fmt.Sprintf("no branch for the constructor's tag %d", con.Tag))
		}

		branch = node.Else
	}

	return r.eval(branch, append(env, pushed), tail)
}

// operands evaluates kids in order, onto the operand stack, and gives the window of their values. The window is valid until the stack is cut back below it.
func (r *recRun) operands(kids []*Node, env []Value) []Value {
	base := len(r.vs)

	for _, a := range kids {
		v, _ := r.eval(a, env, false)
		r.vs = append(r.vs, v)
	}

	return r.vs[base:]
}

// call evaluates a call: its function, then its arguments. In tail position the call is returned to runBody, with its arguments (which it reads at once, before anything else is evaluated).
func (r *recRun) call(node *Node, env []Value, tail bool) (Value, bool) {
	base := len(r.vs)
	fv, _ := r.eval(node.Kids[0], env, false)
	args := r.operands(node.Kids[1:], env)

	if tail {
		r.tailFv = fv
		r.tailArgs = args
		r.vs = r.vs[:base]

		return nil, true
	}

	v := r.apply(fv, args)
	r.vs = r.vs[:base]

	return v, false
}

// delay gives the thunk of a call: its function and its arguments, evaluated now.
func (r *recRun) delay(node *Node, env []Value) Value {
	base := len(r.vs)
	vals := r.operands(node.Kids, env)
	th := &Thunk{
		F: vals[0],
		Args: append([]Value(nil), vals[1:]...),
	}
	r.vs = r.vs[:base]

	return th
}

// force gives the value of a thunk: its stored result, or the call that computes it, which is stored.
func (r *recRun) force(node *Node, env []Value) Value {
	v, _ := r.eval(node.Kids[0], env, false)
	th, ok := v.(*Thunk)

	if !ok {
		r.fail("force of a value that is not a thunk")
	}

	if th.Done {
		return th.Result
	}

	res := r.apply(th.F, th.Args)
	th.Done = true
	th.Result = res

	return res
}

// prim evaluates a primitive on its operands.
func (r *recRun) prim(node *Node, env []Value) Value {
	base := len(r.vs)
	vals := r.operands(node.Kids, env)
	res, msg := prim(node.Tag, vals)
	r.vs = r.vs[:base]

	if msg != "" {
		r.fail(msg)
	}

	return res
}

// apply applies fv to args, not in tail position: the value of the call. The arguments are read before anything else is evaluated.
func (r *recRun) apply(fv Value, args []Value) Value {
	for {
		law, have := r.resolve(fv)
		if len(have)+len(args) < law.Arity {
			return partial(law, have, args)
		}

		// A saturated call with nothing already applied: a jet reads the arguments where they are, so no frame is built for it.
		if JetsOn && len(have) == 0 && len(args) == law.Arity {
			if fn := jetFor(law); fn != nil {
				if res, cost, ok := fn(args); ok && r.steps+cost <= r.fuel {
					r.steps += cost

					return res
				}
			}
		}

		slots, extra := makeFrame(law, have, args)
		if len(extra) > 0 {
			// Over-applied: the law is entered, and its result is applied to the rest.
			r.entry(law)

			v := r.runBody(law, slots)
			fv, args = v, extra

			continue
		}

		if JetsOn && len(have) > 0 {
			if fn := jetFor(law); fn != nil {
				if res, cost, ok := fn(slots[1:]); ok && r.steps+cost <= r.fuel {
					r.steps += cost

					return res
				}
			}
		}

		if MemoOn {
			if key, ok := memoKey(law, slots[1:]); ok {
				if e, hit := memo[key]; hit {
					if r.steps+e.fuel <= r.fuel {
						r.steps += e.fuel
						MemoCounts.Hits++
						MemoCounts.ChargedFuel += e.fuel

						return e.value
					}
				} else {
					MemoCounts.Misses++
					start := r.steps
					v := r.enterAndRun(law, slots)

					if r.steps-start >= MemoMinFuel {
						memo[key] = memoEntry{
							value: v,
							fuel: r.steps - start,
						}
						MemoCounts.Stores++
					}

					return v
				}
			}
		}

		return r.enterAndRun(law, slots)
	}
}

// enterAndRun is a saturated entry of law with its frame: its step, then its body, with the tail calls it makes.
func (r *recRun) enterAndRun(law *Law, slots []Value) Value {
	r.entry(law)
	return r.runBody(law, slots)
}

// runBody gives the value of law's body in its frame. A tail call the body makes is applied here, in a loop: a saturated call of a law with a jet may take the jet, and a call that is over-applied is applied to its rest after its law's body. A tail call is not memoised (the memo is for calls that are not in a loop).
func (r *recRun) runBody(law *Law, frame []Value) Value {
	for {
		if v, tail := r.eval(law.Body, frame, true); !tail {
			return v
		}

		fv, args := r.tailFv, r.tailArgs
		r.tailFv, r.tailArgs = nil, nil
		next, have := r.resolve(fv)

		if len(have)+len(args) < next.Arity {
			return partial(next, have, args)
		}

		if JetsOn && len(have) == 0 && len(args) == next.Arity {
			if fn := jetFor(next); fn != nil {
				if res, cost, ok := fn(args); ok && r.steps+cost <= r.fuel {
					r.steps += cost

					return res
				}
			}
		}

		slots, extra := makeFrame(next, have, args)
		if len(extra) > 0 {
			r.entry(next)

			res := r.runBody(next, slots)

			return r.apply(res, extra)
		}

		if JetsOn && len(have) > 0 {
			if fn := jetFor(next); fn != nil {
				if res, cost, ok := fn(slots[1:]); ok && r.steps+cost <= r.fuel {
					r.steps += cost

					return res
				}
			}
		}

		r.entry(next)

		law, frame = next, slots
	}
}

// runRecursive runs f with a fresh run, and gives its outcome: a value, an error, out of fuel or a host limit.
func runRecursive(fuel int64, f func(r *recRun) Value) (out Outcome) {
	r := &recRun{
		fuel: fuel,
	}

	defer func() {
		if p := recover(); p != nil {
			stop, ok := p.(stopRun)
			if !ok {
				panic(p)
			}

			out = stop.o
		}
	}()

	v := f(r)

	return Outcome{
		Status: "value",
		Value: v,
		Steps: r.steps,
	}
}
