# Prototype 7: a cost-first core

Status: plan. Nothing is implemented yet. The plan is written in order of work: the measurements come first, and each phase has an exit test.

## Goal

A purely functional VM whose core is small enough to implement in a few hundred lines on any host, and whose speed comes from doing less work (fewer steps, better algorithms, jets for the hot paths, memoised pure calls). Machine tuning comes last, not first.

## Why: the evidence from Prototypes 5 and 6

Checking `L2/programs/boot/types.l2` with the L2 checker, which is written in L2 and run on the Prototype 6 machine:

| Measure | Value | Source |
| --- | --- | --- |
| Input | 39,420 bytes, 913 lines | `wc` |
| Machine steps | 299,622,490 (identical on every machine) | `vm_bench.luau`, commit `3e5cf1c` |
| Reference machine | 49.4 s (about 6M steps/s) | commit `aafa9cc` |
| Fast machine | 30.3 s (about 10M steps/s) | commit `3e5cf1c` |
| Hybrid machine | 16.2 s (about 18.5M steps/s) | commit `aafa9cc` |
| Steps per source byte | about 7,600 | 299.6M / 39,420 |

Conclusions that shape this plan:

- **The step count is the problem, not the step rate.** The hybrid is close to what a tree or closure machine in Luau can do per step. A machine rewrite might give about 2×. The target needs about 45× fewer steps at the same host speed, or a mix of fewer steps and jets.
- **The checker is probably doing too much work.** The state is association lists (`lookupM`, `hdOr`), and `subst (bindsOf …)` is called once per declaration, which probably re-walks the bindings each time. If the cost grows quadratically with input size, the fix is in `types.l2`, not the VM. This is a hypothesis until Phase 0 tests it.
- **Names are lists of bytes.** Every name comparison walks a list, and every string is a list of cells. Interned names would make equality a single comparison.
- **The step-parity invariant will not survive jets or memoisation** unless the design says how fuel is charged. The section "Fuel, jets and memo" below handles this.

## Prior work this plan takes from

- **PLAN and Pallas.** The closest existing design. Five opcodes (law constructor, kind match, nat match, increment, pin), so the core is easy to implement. Laws are closed supercombinators. Self-reference is built into a law's body, so no `fix` wrapper is needed. Apps are closures (partial application) or thunks (saturated). A pin is a *storage identity* for a normalised value (hashed and deduplicated), separate from laziness. Jets replace a pinned law, matched by its hash, with native code that must give the same result.
- **Nock and Urbit.** The same lesson from the other side. Nock's twelve opcodes make decrement hard, which Prototype 2 ran into. Urbit's answer is jets for arithmetic and hashing, plus cached hashes (`mug`), so equality and memo keys are cheap. Urbit's subject-object addressing is awkward without jets, so this plan does not copy it.
- **Interaction combinators (Prototype 4).** Every local rewrite is one step, so step counts balloon on a sequential host. Eager reduction under λ made recursion fail until Lafont's passive codes were added. The passive-code idea is kept for serialisation and for pins. Interaction combinators are not a speed path on Luau.
- **Interaction calculus and HVM.** Optimal sharing inside lambdas, with no hand-written thunks. The wins are on duplication-heavy and parallel workloads, and a sequential checker gets the bookkeeping cost without the benefit. Not used in this prototype. Revisit only for a native, parallel host.

## Speed target

The target has three parts. Each one is measured on a fixed reference host, and the harness records the host and the Luau version with every result.

**1. A user-facing time budget.** This is the only part that needs a decision from the project owner. Proposed, not agreed:

- Interactive: checking a 500-line L2 program in under 200 ms on the reference host.
- Batch: a full build of a 5,000-line program (lex, parse, check, desugar, run its tests) in under 5 s.

**2. A step budget, derived from the time budget.** Convert seconds into steps using the throughput the host actually achieves:

    steps budget = time budget × measured steps per second

At the hybrid's 18.5M steps/s, the interactive budget is about 3.7M steps for 500 lines, about 7,400 steps per line. The current checker spends about 330,000 steps per line (299.6M / 913), so the gap is about 45×. This assumes checking cost is linear in the input. Phase 0 tests that assumption.

**3. A relative check that does not depend on the host.** Steps and fuel are host-independent, so they are the primary numbers. Add two ratios so that a result has meaning even when the host changes:

- steps per input unit (per line, and per AST node once a parsed tree is the input), which should stay flat as the input grows;
- the bootstrapped checker's time divided by the time of the Luau checker (`L2/checker.luau`) on the same input. The Luau checker is not on the VM, so this ratio shows how much the bootstrap and the machine cost.

**Harness rules.** The benchmark runs each workload several times and reports the median. It reports steps, fuel, allocations (counted by the machine), host time, and the two ratios. A second run of the same input is a separate benchmark: with memoisation it should do near-zero work, and that is measured too (Phase 7).

**Open decisions for the speed target** (listed again in "Decisions" below):

- Which workload is the user-facing one: interactive re-check after an edit, a full batch build, or a long-running service?
- Does the target need to hold on Luau, or only on a future native host? On Luau, the step rate is capped near 18M steps/s, so a 200 ms budget needs fewer than about 4M steps. That may force a native host.

## Core design (draft)

### What is kept, dropped and replaced

| From Prototype 5 and 6 | In Prototype 7 | Why |
| --- | --- | --- |
| Integers, nil, cells, constructors (`construct`, `tagof`, `payload`) | Kept. Constructors become one `case` form with a branch per tag | Pattern matching is one dispatch, not a test and then a payload read |
| `fix` for recursion | Dropped. A law refers to itself by `self` | No wrapper closure per recursive call |
| Environment chains and de Bruijn lookup | Dropped. Laws are closed, and their only inputs are their arguments and `self` | Lambda lifting is done by the compiler, so lookup is an index into a flat argument array |
| `pin` as a memoised suspended expression | Split in two: `delay` and `force` for laziness, `pin` for storage identity (hashed, interned) | PLAN keeps these apart, and they need different costs and different rules |
| The hybrid and arena machines | Dropped. One machine, with an explicit stack | Two code paths are the complexity the project is trying to shed |
| Lists of bytes for strings and names | Open decision (see "Decisions") | Interned names and a byte kind would make equality and lexing cheap |

### Values

- integer (53-bit, as now), nil, cell (a pair), constructor (a tag and a payload);
- law: a name hash, an arity, a body, and no free variables;
- app: a law or closure applied to fewer than its arity arguments;
- thunk: a saturated app, evaluated at most once (`force`);
- pin: a value in normal form, interned by its hash so that equal pins are one object.

Every value can be hashed. Hashes are computed lazily and cached on the object (the `mug` approach), so the cost is paid only when a hash is needed.

### Forms

Target: about ten to twelve forms, enforced by the spec. Any addition needs a reason written in the spec.

- `lit n`, `nil`: literals.
- `arg i`, `self`: the arguments of the current law, and the law itself.
- `call f e₁ … eₙ`: application, curried in meaning, saturating when it has enough arguments.
- `cell a b`, `con tag e`: construction.
- `case e {tag → branch …}`: dispatch on a constructor's tag, with a payload binding. Compiles to a jump table.
- `prim op a b`: integer and kind primitives, the same table as now.
- `if c t e`: branch on an integer.
- `let x = e in b`: evaluate once, so that a shared value is not recomputed.
- `delay e`, `force e`: a thunk, and its evaluation.
- `pin e`: evaluate to normal form and intern.

Fuel: one unit per form evaluated, as in the reference. A `call` costs one unit more than its body's forms. This keeps the reference's fuel rule, so `out_of_fuel` stays deterministic.

### Fuel, jets and memo

These three features change the work done. They must not change the answer, and they must say what they do to fuel. The rules:

- **Memo.** A memo entry stores the result of a call and the fuel that call used. A hit charges that stored fuel and does no work. So the fuel is exactly what the reference would have charged, and only the work drops. The memo key is the law's hash and the hashes of its arguments.
- **Jets.** A jet replaces a law, matched by the law's hash, with native code. It must return the same result as the reference body on every input. Its fuel is a declared formula in the jet's own definition, not the reference step count. The formula is checked on the test suite against the reference. A jet whose fuel cannot be made to match is marked as "work only", and the parity check then compares results but not fuel for that law.
- **Work.** A separate counter counts real host operations (allocations, table reads, jet calls). Fuel and work are reported side by side. The step parity invariant of Prototypes 5 and 6 becomes: fuel is identical, and results are identical. Work is measured, not checked.

### Execution

One machine, with an explicit stack and a single dispatch loop. Compiling each law to Luau closures (as `runDirect` did) is an optimisation for leaf forms only, and it may not add a second machine. The stack overflow that forced the hybrid is avoided because the stack is explicit.

<!-- next: phases -->
