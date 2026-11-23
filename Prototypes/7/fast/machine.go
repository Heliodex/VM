package fast

type (
	// Outcome is the result of a run (SPEC.md section 5). Status is "value", "error" or "out_of_fuel". Steps is the fuel used (section 6). A run that nests its evaluations deeper than MaxNesting ends with "host_limit", a status of the host, which the spec does not have (eval.go).
	Outcome struct {
		Status string
		Value Value
		Message string
		Steps int64
	}
)

// StepHook, when set, is told the law of each step the machine charges: the frame's law for a form, and the callee for an entry. It is for measurement (the core's profile); the results do not depend on it.
var StepHook func(law Value)

// Run applies a program (a law of arity 1) to an input. The application is a law entry, so it costs one step (SPEC.md section 5).
func Run(program *Law, input Value, fuel int64) Outcome {
	return runRecursive(fuel, func(r *recRun) Value {
		return r.apply(program, []Value{input})
	})
}

// RunBody evaluates the body of a law of arity 1 with the input as its argument, with no law entry: the frame is [NIL, input]. It is the reference's runForm, which the examples and the L2 tests use.
func RunBody(body *Node, input Value, fuel int64) Outcome {
	return runRecursive(fuel, func(r *recRun) Value {
		v, _ := r.eval(body, []Value{NIL, input}, false)

		return v
	})
}

func fail(msg string, steps int64) Outcome {
	return Outcome{
		Status: "error",
		Message: msg,
		Steps: steps,
	}
}
