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

**1. The user-facing time budget (agreed).** A build of 2,500 lines of L2 takes under 1 s on the reference host. A build is lex, parse, check and desugar of the program. Running the program's tests is not part of the build. Interactive re-check is not a target for now.

**The build corpus.** A fixed set of L2 source, 2,500 lines in total. The proposed corpus is the L2 compiler's own sources in L2 (`Prototypes/6/L2/programs/boot/*.l2`, 2,235 lines), topped up with library programs to 2,500. The size is the project owner's figure. The exact files are a proposal. Note that Prototype 5's Luau L2 implementation is 4,478 lines in nine files (about 3,400 in the lexer, parser, layout, checker, desugarer and driver), so 2,500 lines is smaller than the old implementation.

**2. A step budget, derived from the time budget.** Convert seconds into steps using the throughput the host actually achieves:

    steps budget = time budget × measured steps per second

At the hybrid's 18.5M steps/s, the budget is about 18.5M steps for 2,500 lines, about 7,400 steps per line. The current checker alone spends about 330,000 steps per line (299.6M / 913), so the gap is about 44×. Lex, parse and desugar are not counted in that figure and are not measured yet, so the real gap is at least this large. This assumes cost is linear in the input. Phase 0 tests that assumption.

**3. A relative check that does not depend on the host.** Steps and fuel are host-independent, so they are the primary numbers. Add two ratios so that a result has meaning even when the host changes:

- steps per input unit (per line, and per AST node once a parsed tree is the input), which should stay flat as the input grows;
- the bootstrapped checker's time divided by the time of the Luau checker (`L2/checker.luau`) on the same input. The Luau checker is not on the VM, so this ratio shows how much the bootstrap and the machine cost.

**Harness rules.** The benchmark runs each workload several times and reports the median. It reports steps, fuel, allocations (counted by the machine), host time, and the two ratios. A second run of the same input is a separate benchmark: with memoisation it should do near-zero work, and that is measured too (Phase 7).

**Open questions for the speed target** (listed again in "Decisions" below):

- Does the target need to hold on Luau, or only on a future native host? On Luau the step rate is about 18M steps/s, so the budget is about 18M steps. That is reachable only if the 44× reduction comes from algorithms and jets, not the machine. If it cannot be reached, the target needs a native host.
- Is the corpus right? The 2,500 lines and the file choice are proposals.

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

## Phases

Each phase ends with an exit test. A phase is not finished until its test passes, and the harness numbers are committed with it.

**Phase 0: measure Prototype 6.** Freeze Prototype 6 as the baseline. Measure, without changing the machine:

- the checker on `types.l2` at 1×, 2× and 4× input (for example, the parsed declarations repeated with fresh names). Steps against size.
- a histogram of steps by form and by library function (`lookupM`, `subst`, `bindsOf`, `hdOr`, and the rest), and of allocations.

*Exit:* we know whether the checker's cost is linear, and we know the five largest cost centres. If it is quadratic, the cause is named.

**Phase 1: fix the checker's algorithms, in L2.** Only if Phase 0 finds a quadratic or a large avoidable cost. Candidates: union-find for type variables, a balanced map for the environment, and not converting the binding tree to a list per declaration. This runs on Prototype 6, so the gain is measured before any new machine exists.

*Exit:* steps against size is linear on the same inputs, with the checker's answers unchanged (`infer_run` and `checker_run` agree).

**Phase 2: the core spec.** Write `Prototypes/7/SPEC.md`: the values, the forms, the fuel rule, the jet and memo rules, and the outcomes (`value`, `error`, `out_of_fuel`).

*Exit:* the spec has at most twelve forms, and each one has a rule and at least one example.

**Phase 3: the reference interpreter.** A small interpreter of the spec, with an explicit stack. It is the oracle, so it is written for clarity, not speed. Prototype 5's examples are ported to the core, through the L2 desugarer for the L2 programs.

*Exit:* every L2 program and every Prototype 5 example gives the same result on the reference interpreter as on Prototype 6, with the same fuel.

**Phase 4: the fast interpreter.** One machine that compiles each law's body to a flat form and runs it in a single loop with an explicit stack. Leaf forms may be Luau closures.

*Exit:* the same results and fuel as Phase 3 on every test, and at least 3× the reference machine's steps per second on the checker benchmark.

**Phase 5: jets, for the hot library functions.** Use the Phase 0 histogram to pick the top few functions. Candidates: name and byte-string equality, map lookup, list append and reverse, and the substitution walk. Each jet has a reference law, a native body, a declared fuel formula, and a parity test.

*Exit:* every jet agrees with its reference on the whole test suite, the fuel formulas match wherever they are claimed to, and the checker benchmark's steps and work drop by the amount the histogram predicted.

**Phase 6: interned names and a byte kind.** If Phase 0 shows that name and string comparison is a large cost, intern names as pins and add a byte kind for source text, with lexing as a jet.

*Exit:* the lexer and the parser give the same token and tree output on every program file, and the name cost in the histogram drops to a small share.

**Phase 7: memo and incremental re-check.** Add the memo table for pure calls, with the fuel rule above. Benchmark two runs: a cold check, and a re-check of the same input and then of an input with one declaration changed.

*Exit:* the second run of an unchanged input does near-zero work, a one-declaration change costs work in proportion to that declaration, and fuel is identical with and without the memo.

**Phase 8: check against the speed target.** Run the harness on the reference host, and compare with the targets in "Speed target". Write the result in this README, including the misses.

*Exit:* a results table, a decision on whether the target needs a native host, and a list of what would change the decision.

## Risks

- **Fuel parity with jets and memo.** The fuel rule above is the answer, but a jet whose formula is hard to state will leave its law "work only", and the parity check gets weaker there. Keep the list of such laws short.
- **Hashing cost in Luau.** Hashing every value could cost more than it saves. The lazy, cached hash limits this, but Phase 7 must show the net gain.
- **Scope creep into syntax.** The surface stays L2. New syntax waits until the core and the speed target are measured.
- **Measuring on one host.** Every number is from one machine. The harness records the host, so a second host can be added later.
- **Luau's ceiling.** On Luau, the step rate caps the design. If the interactive target needs fewer than about 4M steps, the design will need a native host, and Phase 8 has to say so.

## Decisions

These need an answer from the project owner before the phase that depends on them.

1. **The user-facing workload and its time budget** (before Phase 8, and the step budget depends on it). The proposed budgets in "Speed target" are not agreed.
2. **Host.** Luau only, or a native host later? On Luau the step rate caps the design (see Risks). Native hosts change the choice of jets and make uniqueness and parallelism worth considering.
3. **Fuel of jets** (before Phase 5). Option A: every jet declares a fuel formula and is checked against the reference. Option B: jets are "work only" and the parity check compares results alone. The plan assumes A, and uses B only where A cannot be stated.
4. **Strings and names** (before Phase 6). Option A: keep lists of bytes, and rely on interning and jets. Option B: a byte kind backed by the host's strings. The plan assumes B, but it waits for Phase 0 to show whether text is a large cost.
5. **Laziness.** Whether the core keeps `delay` and `force` as explicit forms, as drafted, or makes evaluation lazy by default. The plan assumes explicit forms, so that the cost of each thunk is visible in the fuel and work counts.

## Next step

Phase 0. Freeze Prototype 6, then write the measurement harness in `Prototypes/7/measure/`, so that the baseline numbers for this plan come from the same tool that later phases use.
