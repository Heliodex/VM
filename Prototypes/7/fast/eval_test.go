package fast

import "testing"

// countdown is a law of arity 1 whose body is: if n = 0 then 0 else self (n - 1), a tail call, where n is arg 1 and self is arg 0.
func countdown() *Law {
	cond := &Node{
		Op: OpPrim,
		Tag: 6,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 1,
			},
			{
				Op: OpLit,
				Lit: Small(0),
			},
		},
	}
	sub := &Node{
		Op: OpPrim,
		Tag: 1,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 1,
			},
			{
				Op: OpLit,
				Lit: Small(1),
			},
		},
	}
	rec := &Node{
		Op: OpCall,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 0,
			},
			sub,
		},
	}
	body := &Node{
		Op: OpIf,
		Kids: []*Node{
			cond,
			{
				Op: OpLit,
				Lit: Small(0),
			},
			rec,
		},
	}

	return &Law{
		Arity: 1,
		Body: body,
	}
}

// TestTailCallsDoNotNest: a loop of thirty million tail calls runs in the stack of one call, with the spec's steps (ten a turn, and the entry).
func TestTailCallsDoNotNest(t *testing.T) {
	const n = 3000000

	if out := Run(countdown(), Small(n), 1e9); out.Status != "value" || out.Steps != 10*n+6 {
		t.Fatalf("countdown %d: %s after %d steps, want value after %d", n, out.Status, out.Steps, 10*n+6)
	}
}

// total is a law of arity 1 whose body is: if n = 0 then 0 else n + self (n - 1), which nests one call in each step.
func total() *Law {
	cond := &Node{
		Op: OpPrim,
		Tag: 6,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 1,
			},
			{
				Op: OpLit,
				Lit: Small(0),
			},
		},
	}
	sub := &Node{
		Op: OpPrim,
		Tag: 1,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 1,
			},
			{
				Op: OpLit,
				Lit: Small(1),
			},
		},
	}
	rec := &Node{
		Op: OpCall,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 0,
			},
			sub,
		},
	}
	add := &Node{
		Op: OpPrim,
		Tag: 0,
		Kids: []*Node{
			{
				Op: OpArg,
				Index: 1,
			},
			rec,
		},
	}
	body := &Node{
		Op: OpIf,
		Kids: []*Node{
			cond,
			{
				Op: OpLit,
				Lit: Small(0),
			},
			add,
		},
	}

	return &Law{
		Arity: 1,
		Body: body,
	}
}

// TestNestedCallsWithinLimit: a call nested in calls, a hundred thousand deep, gives its value.
func TestNestedCallsWithinLimit(t *testing.T) {
	const n = 100000

	if out := Run(total(), Small(n), 1e10); out.Status != "value" {
		t.Fatalf("total %d: %s", n, out.Status)
	}
}

// TestNestingLimitEndsTheRun: past MaxNesting the run ends with host_limit, not with the Go stack overflowing.
func TestNestingLimitEndsTheRun(t *testing.T) {
	const n = 400000

	if out := Run(total(), Small(n), 1e12); out.Status != "host_limit" {
		t.Fatalf("total %d: %s, want host_limit", n, out.Status)
	}
}
