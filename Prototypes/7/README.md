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
- **The checker is doing too much work, in two ways (measured in Phase 0).** The name environment is an association list searched by name (`findE`), and that search is quadratic in the number of declarations. Separately, each declaration costs about 128,000 steps, much of it in `/` and `%` by 2 and list access, which return `Result` values that are matched at every step. The binding store is a binary trie, not an association list as first assumed. See `measure/README.md`.
- **Layout was the largest cost, and is now fixed (Phase 0, runs 5 and 6).** Before the change, the VM's layout pass was 49% of the corpus build and grew quadratically in lines. After it (Phase 1, run 6), layout is 11% of the corpus build and grows linearly. After the checker changes (Phase 1, run 8), the checker is 52% of the corpus build and grows linearly too; layout is 16%, parse 23%, lex 8%.
- **Names are lists of bytes.** Every name comparison walks a list, and every string is a list of cells. Interned names would make equality a single comparison.
- **The step-parity invariant will not survive jets or memoisation** unless the design says how fuel is charged. The section "Fuel, jets and memo" below handles this.

## Prior work this plan takes from

- **PLAN and Pallas.** The closest existing design. Five opcodes (law constructor, kind match, nat match, increment, pin), so the core is easy to implement. Laws are closed supercombinators. Self-reference is built into a law's body, so no `fix` wrapper is needed. Apps are closures (partial application) or thunks (saturated). A pin is a *storage identity* for a normalised value (hashed and deduplicated), separate from laziness. Jets replace a pinned law, matched by its hash, with native code that must give the same result.
- **Nock and Urbit.** The same lesson from the other side. Nock's twelve opcodes make decrement hard, which Prototype 2 ran into. Urbit's answer is jets for arithmetic and hashing, plus cached hashes (`mug`), so equality and memo keys are cheap. Urbit's subject-object addressing is awkward without jets, so this plan does not copy it.
- **Interaction combinators (Prototype 4).** Every local rewrite is one step, so step counts balloon on a sequential host. Eager reduction under λ made recursion fail until Lafont's passive codes were added. The passive-code idea is kept for serialisation and for pins. Interaction combinators are not a speed path on Luau.
- **Interaction calculus and HVM.** Optimal sharing inside lambdas, with no hand-written thunks. The wins are on duplication-heavy and parallel workloads, and a sequential checker gets the bookkeeping cost without the benefit. Not used in this prototype. Revisit only for a native, parallel host.

## Speed target

The target has three parts. Each one is measured on a fixed reference host, and the harness records the host and the Luau version with every result.

**1. The user-facing time budget (agreed).** A bootstrapped build of 2,500 lines of L2 takes under 1 s on the reference host, on the VM. The build is the bootstrapped compiler running on the VM, with imports included in the check. Running the program's tests is not part of the build. Interactive re-check is not a target for now.

The build's stages, as they stand:

- **Layout** (`boot/layout.l2`): on the VM, from the raw indented program section. Measured by the Phase 0 harness, and its output must equal the host layout's.
- **Lex, parse, check** (`boot/lex.l2`, `boot/parse.l2`, `boot/types.l2`): on the VM. The check is partial today (some forms report "this form is not checked yet") and has no import support yet.
- **Desugar**: not bootstrapped. It runs on the host, so it is not counted in the build. When it is bootstrapped, it joins the build.

So the target as stated is for a *bootstrapped front end*, layout through check. The full-compiler target waits for desugar to be bootstrapped.

**The build corpus.** The four boot files, which are the bootstrapped front end today (`Prototypes/6/L2/programs/boot/`: `layout.l2`, `lex.l2`, `parse.l2`, `types.l2`, 2,235 lines in all). The target size is 2,500 lines, so the corpus is 265 lines short. The top-up with library programs is not done. The corpus is re-measured when the bootstrapped compiler gains desugar, so the full compiler is measured as one piece. The size 2,500 is the project owner's figure. Note that Prototype 5's Luau L2 implementation is 4,478 lines in nine files, and the Luau pieces that the bootstrap replaces (lexer, parser, layout, checker, desugarer) total about 3,700 of those lines, so 2,500 lines is smaller than the old implementation.

**2. A step budget, derived from the time budget.** Convert seconds into steps using the throughput the host actually achieves:

    steps budget = time budget × measured steps per second

At the hybrid's 18.5M steps/s, the budget is about 18.5M steps for 2,500 lines, about 7,400 steps per line. With the Phase 1 changes (run 8), the bootstrapped front end on the 2,235-line corpus takes 592.5M steps, about 265,000 per line. At that average, 2,500 lines take about 663M steps, about 37× the budget at 18M steps/s (it was about 96× before the layout change and about 55× after it). The average no longer understates a larger build: the checker, layout and parse are all linear in lines now (the doubling ratios are about 2.0), so a 2,500-line build should cost about the corpus average per line. The corpus is still 265 lines short of the target size, so the 2,500-line figure is an extrapolation.

**3. A relative check that does not depend on the host.** Steps and fuel are host-independent, so they are the primary numbers. Add two ratios so that a result has meaning even when the host changes:

- steps per input unit (per line, and per AST node once a parsed tree is the input), which should stay flat as the input grows;
- the bootstrapped checker's time divided by the time of the Luau checker (`L2/checker.luau`) on the same input. The Luau checker is not on the VM, so this ratio shows how much the bootstrap and the machine cost.

**Harness rules.** The benchmark runs each workload several times and reports the median. It reports steps, fuel, allocations (counted by the machine), host time, and the two ratios. A second run of the same input is a separate benchmark: with memoisation it should do near-zero work, and that is measured too (Phase 7).

**Open questions for the speed target** (listed again in "Decisions" below):

- Does the target need to hold on Luau, or only on a future native host? On Luau the step rate is about 18M steps/s, so the budget is about 18M steps. That is reachable only if the roughly 37× reduction comes from algorithms and jets, not the machine. If it cannot be reached, the target needs a native host.
- Corpus: resolved as the four boot files now, with the top-up and the full compiler to follow (see "Speed target").

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

**Phase 0: measure Prototype 6** (done; harness and results in `measure/`, see `measure/README.md`). Prototype 6 was not changed. The measurement covered:

- validation: the checker on `types.l2` gives 299,622,490 steps on the hybrid and the counted machine, as `vm_bench` reports;
- the whole bootstrapped build on the corpus, each stage's steps reported separately (lex, parse, check), with the host stages timed alongside;
- a profile of the checker by form, by frame and by owning function;
- growth by owner, on 100 and 400 generated functions;
- scaling of the VM stages on generated programs of 25 to 1,600 functions.

Note: the plan first proposed scaling by repeating `types.l2`. It was replaced by generated programs, since repeating declarations needs renaming, and the generator gives a clean size series.

*Exit, met:* the checker's cost is superlinear, and the cost centres are named: the name environment search (quadratic), the binding trie's index arithmetic and access, and the `Result`-wrapped list accessors.

**Phase 1: fix the front end's algorithms, in L2.** Measured candidates, in order of the cost they remove:

- **Layout: done (run 6).** The profile (`measure/layout_profile.luau`) put about 87% of layout steps in `tlOf`, `hd` and `cat`, which grew 15 to 16 times from 100 to 400 functions. The cause was the text copying: each enclosing block copied the text of the blocks inside it, so nested blocks were copied once per level. The change builds the output as difference lists, in `measure/boot/layout.l2`, and copies each piece once, when it is flattened. Exit test, met: layout steps grow about 2.0 times per doubling of the input (linear), and the output equals the host's on all 57 inputs in `measure/layout_parity.luau` (the 44 L2 program files, 9 malformed inputs, and 4 generated programs). Layout steps on `types.l2` fell from 486M to 45M. Prototype 6's layout is kept as the baseline;
- **Name environment: done (run 8, `measure/results/checker_scaling_env.txt`).** The environment is a persistent trie on the bytes of the name, so a lookup walks the name, not the environment. The quadratic term is gone: the checker's steps double 1.94 to 2.08 times per doubling of the program, where they used to double 2.0 to 2.9.
- **Binding store: done (run 8, `results/checker_scaling_trie4.txt`).** Radix-4 instead of binary, so a lookup has about log4 levels, one division each, and the trie's children are read with `fst` and `snd`, not a walk. The division's `Result` is what the language gives for `/`, and it remains the floor for this machine.
- **Mutual group: done.** The binding store's `setB` and `setSlot` were a `letrec` group, and its dispatch cost about 8% of the checker's steps. They are one function now.
- **List accessors: partly done.** The hot loops (name comparison `same`, `memberI`, `lookupM`, and the environment walks) read each head once through the `head` builtin. What remains is about 12% of the checker's steps, spread over `tl`, `hdOr` and `first` at many call sites. Inlining them everywhere is a larger rewrite for a modest gain, so it is left as a follow-up, with its measured share.
- **The fixed-point combinator: not a Phase 1 item.** Every recursive call goes through the machine's `fix` (Z combinator), which is about 9% of the checker's steps. It is a property of how the desugarer compiles `letrec`, not of the checker's algorithms. Removing it is the core's self-reference (Phase 2).

- **Imports: done (run 7, first part).** The checker has a request, `InferI`, that carries each import as `(name . program)`. The checker infers and generalises each library itself, so the scheme is never transported as text or value across the boundary, and the output format is unchanged. Each library has its own range of type-variable ids, and the program starts above them. Exit, partly met: on `lex.l2` and `parse.l2` (which import `reverse` and `append`), and on the two files with no imports, the VM and the Luau checker agree (`measure/imports_run.luau`), and the corpus has no unbound imports. Also met: the wider `infer_run` suite gives the same answers on the variant (160 of 160), and a program that uses an unimported name is refused by both checkers, with the same message (`measure/README.md`). Imports are done.

Each change is measured on the same harness, and the variant lives in `measure/boot/` until it is promoted.

*Exit, met:* the checker's steps are linear in the size of the program on generated programs of 25 to 1,600 functions (ratios 1.94 to 2.08 per doubling), the 160 programs of `infer_run` give the same answers as the Luau checker (`measure/results/infer_run_*.txt`), imports agree with the Luau checker and an unimported name is refused by both (`imports_run.luau`, `negative_import_run.luau`), and layout's output equals the host's on 57 inputs (`layout_parity.luau`). The remaining accessor cost is a Phase 1 follow-up, not a blocker for the exit test.

**Phase 2: the core spec.** Write `Prototypes/7/SPEC.md`: the values, the forms, the fuel rule, the jet and memo rules, and the outcomes (`value`, `error`, `out_of_fuel`).

*Exit:* the spec has at most twelve forms, and each one has a rule and at least one example.

**Phase 3: the reference interpreter.** A small interpreter of the spec, with an explicit stack. It is the oracle, so it is written for clarity, not speed. Prototype 5's examples are ported to the core, through the L2 desugarer for the L2 programs.

*Exit:* every L2 program and every Prototype 5 example gives the same result on the reference interpreter as on Prototype 6, with the same fuel.

**Phase 4: the fast interpreter.** One machine that compiles each law's body to a flat form and runs it in a single loop with an explicit stack. Leaf forms may be Luau closures.

*Exit:* the same results and fuel as Phase 3 on every test, and at least 3× the reference machine's steps per second on the checker benchmark.

**Phase 5: jets, for the hot library functions.** Use the Phase 0 histogram to pick the top few functions. Candidates: name and byte-string equality, map lookup, list append and reverse, and the substitution walk. Each jet has a reference law, a native body, a declared fuel formula, and a parity test.

*Exit:* every jet agrees with its reference on the whole test suite, the fuel formulas match wherever they are claimed to, and the checker benchmark's steps and work drop by the amount the histogram predicted.

**Phase 6: interned names and a byte kind.** Phase 0 measured name comparison (`same`) at 4.3% of the checker's steps on `types.l2`, and its share grows with the environment. Phase 1 removes most of the environment search, so Phase 6 is worth doing only if its share is still large after Phase 1. If it is, intern names as pins and add a byte kind for source text, with lexing as a jet. Lexing is linear already (565–706 steps per byte), so the byte kind is for speed, not for growth.

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
- **Luau's ceiling.** On Luau, the step rate caps the design. If the build cannot be done within about 18M steps, the design will need a native host, and Phase 8 has to say so.
- **Corpus size.** The 2,500-line target is smaller than the Prototype 5 Luau implementation (4,478 lines). If the corpus is too small to show the costs that matter, the target is met on an easy input. Phase 0 checks this by reporting how the costs grow with size, on generated programs up to 3,209 lines.
- **The corpus is not yet the full compiler.** Desugar is not bootstrapped, and the checker has no imports. Until both are done, the build is a front end, and the target says so.

## Decisions

These need an answer from the project owner before the phase that depends on them.

1. **Resolved:** the workload is a build, and the target is 2,500 lines of L2 under 1 s on the reference host, for the bootstrapped build on the VM. The corpus is the four boot files, with a top-up to 2,500 and the full compiler to follow (see "Speed target").
1a. **Resolved:** imports are part of the bootstrapped build. The checker's request must carry the imported names and their schemes, so a file that imports library code is fully checked on the VM. This is new work in the checker (Phase 1).
2. **Host.** Luau only, or a native host later? On Luau the step rate caps the design (see Risks). Native hosts change the choice of jets and make uniqueness and parallelism worth considering.
3. **Fuel of jets** (before Phase 5). Option A: every jet declares a fuel formula and is checked against the reference. Option B: jets are "work only" and the parity check compares results alone. The plan assumes A, and uses B only where A cannot be stated.
4. **Strings and names** (before Phase 6). Option A: keep lists of bytes, and rely on interning and jets. Option B: a byte kind backed by the host's strings. The plan assumes B, but it waits for Phase 0 to show whether text is a large cost.
5. **Laziness.** Whether the core keeps `delay` and `force` as explicit forms, as drafted, or makes evaluation lazy by default. The plan assumes explicit forms, so that the cost of each thunk is visible in the fuel and work counts.

## Next step

Phase 1, on the measured candidates above, and the import support it depends on for a complete check. The first measurement to repeat after each change is the same harness, so the numbers stay comparable. The harness now times the layout stage on the VM too, so the layout's share is part of every later comparison.
