# Prototype 7: a cost-first core

Status: implemented through Phase 8. The speed target is met for the front end on this host, measured directly on a 2,500-line corpus with a margin of about 13% (see Phase 8). With the desugarer the 2,500-line build takes a median of 1.26 s; that is accepted as the full compiler's time, and the 1 s target is not met for it (`fast/README.md`). The plan is written in order of work: the measurements come first, and each phase has an exit test.

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
- **Desugar**: bootstrapped in `Prototypes/6/L2/programs/boot/desugar.l2`, and checked against the host desugarer on the program files and the checks (`measure/desugar_run.luau`). It is counted in the build with the desugarer (`testdata/corpus2500_desugar.txt`): 381,160,207 steps and a median of 1.26 s, with jets on its two hottest laws (`fast/desugarjets.go`).

So the target as stated is for a *bootstrapped front end*, layout through check. The full compiler, with the desugarer, is the 1.26 s build above. The user accepted that time in place of the 1 s target for it.

**The build corpus.** The four boot files, which are the bootstrapped front end today (`Prototypes/6/L2/programs/boot/`: `layout.l2`, `lex.l2`, `parse.l2`, `types.l2`, 2,235 lines in all). The target size is 2,500 lines, so the corpus is 265 lines short. The top-up is done: the standard library (Prototype 6's `lib` folder, 20 files, 355 lines) makes the corpus 24 files and 2,590 lines, so it is larger than the target. The corpus is re-measured when the bootstrapped compiler gains desugar, so the full compiler is measured as one piece. The size 2,500 is the project owner's figure. Note that Prototype 5's Luau L2 implementation is 4,478 lines in nine files, and the Luau pieces that the bootstrap replaces (lexer, parser, layout, checker, desugarer) total about 3,700 of those lines, so 2,500 lines is smaller than the old implementation.

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
| `pin` as a memoised suspended expression | Split in two: `delay` and `force` for laziness; `pin` for storage identity was removed later (SPEC.md decision 16) | PLAN keeps these apart, and they need different costs and different rules |
| The hybrid and arena machines | Dropped. One machine, with an explicit stack | Two code paths are the complexity the project is trying to shed |
| Lists of bytes for strings and names | Open decision (see "Decisions") | Interned names and a byte kind would make equality and lexing cheap |

### Values

- integer (53-bit, as now), nil, cell (a pair), constructor (a tag and a payload);
- law: a name hash, an arity, a body, and no free variables;
- app: a law or closure applied to fewer than its arity arguments;
- thunk: a saturated app, evaluated at most once (`force`);
- pin: removed (SPEC.md decision 16). A pin was a value in normal form, interned by its hash; the content hash of a compound value (decision 13) gives the same identity without it.

Every value can be hashed. Hashes are computed lazily and cached on the object (the `mug` approach), so the cost is paid only when a hash is needed.

### Forms

Target: about ten to twelve forms, enforced by the spec. Any addition needs a reason written in the spec.

- `lit n`, `nil`: literals.
- `arg i`, `self`: the arguments of the current law, and the law itself.
- `call f e₁ … eₙ`: application, curried in meaning, saturating when it has enough arguments.
- `cell a b`, `con tag e`: construction.
- `case e {tag → branch …}`: dispatch on a constructor's tag, with a payload binding. Compiles to a jump table. *Removed (SPEC.md decision 17): nothing built it, and a match is a chain of `tagof` tests.*
- `prim op a b`: integer and kind primitives, the same table as now.
- `if c t e`: branch on an integer.
- `let x = e in b`: evaluate once, so that a shared value is not recomputed.
- `delay e`, `force e`: a thunk, and its evaluation.
- `pin e`: removed (SPEC.md decision 16). A pin of a value is not a form: a suspended expression is `delay`, and its value is `force`.

Fuel: one unit per form evaluated, as in the reference. A `call` costs one unit more than its body's forms. This keeps the reference's fuel rule, so `out_of_fuel` stays deterministic.

### Fuel, jets and memo

These three features change the work done. They must not change the answer, and they must say what they do to fuel. The rules:

- **Memo.** A memo entry stores the result of a call and the fuel that call used. A hit charges that stored fuel and does no work. So the fuel is exactly what the reference would have charged, and only the work drops. The memo key is the law's hash and the hashes of its arguments.
- **Jets.** A jet replaces a law, matched by the law's hash, with native code. It must return the same result as the reference body on every input. Its fuel is a declared formula in the jet's own definition, not the reference step count. The formula is checked on the test suite and on generated inputs against the reference. A law whose fuel cannot be stated as a formula gets no jet: there are no work-only jets (SPEC.md decision 11), so fuel is the same on every machine.
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
- **List accessors: moved to Phase 2 and Phase 5 (measured, `measure/README.md`).** The hot loops read each head once through the `head` builtin, which helped a little. Inlining the rest into `match` on the builtin did not help (+0.3% steps), so the cost is not the closure call. It is the `Result` that `head`, `tail` and `/` return, and that is in the language, not the checker. The remedies are a core read of a list without a `Result` (Phase 2) and a jet for the hot list operations (Phase 5). About 12% of the checker's steps are in these accessors.
- **The fixed-point combinator: not a Phase 1 item.** Every recursive call goes through the machine's `fix` (Z combinator), which is about 9% of the checker's steps. It is a property of how the desugarer compiles `letrec`, not of the checker's algorithms. Removing it is the core's self-reference (Phase 2).

- **Imports: done (run 7, first part).** The checker has a request, `InferI`, that carries each import as `(name . program)`. The checker infers and generalises each library itself, so the scheme is never transported as text or value across the boundary, and the output format is unchanged. Each library has its own range of type-variable ids, and the program starts above them. Exit, partly met: on `lex.l2` and `parse.l2` (which import `reverse` and `append`), and on the two files with no imports, the VM and the Luau checker agree (`measure/imports_run.luau`), and the corpus has no unbound imports. Also met: the wider `infer_run` suite gives the same answers on the variant (160 of 160), and a program that uses an unimported name is refused by both checkers, with the same message (`measure/README.md`). Imports are done.

Each change is measured on the same harness, and the variant lives in `measure/boot/` until it is promoted.

*Exit, met:* the checker's steps are linear in the size of the program on generated programs of 25 to 1,600 functions (ratios 1.94 to 2.08 per doubling), the 160 programs of `infer_run` give the same answers as the Luau checker (`measure/results/infer_run_*.txt`), imports agree with the Luau checker and an unimported name is refused by both (`imports_run.luau`, `negative_import_run.luau`), and layout's output equals the host's on 57 inputs (`layout_parity.luau`). The remaining accessor cost is a Phase 1 follow-up, not a blocker for the exit test.

**Phase 2: the core spec.** Done: `Prototypes/7/SPEC.md`. (It was written with eleven forms and twelve primitives; decisions 15 to 17 leave nine forms and thirteen primitives.) It has seven kinds of value, twelve primitives with no `Result` at the time, the outcomes, the fuel rule, the memo rule (a hit charges the stored fuel), the jet rule (declared fuel, with no work-only jets), and examples.

The binary format is part of the spec (section 12), modelled on Prototype 5's. It is implemented and tested in the Luau reference (`reference/format.luau`, with `reference/int.luau` for integers of any size, and `reference/format_run.luau`: 50 checks, including the spec's bytes, round trips of values and programs, a program 20,000 forms deep, and each refusal with its reason). It is iterative, so depth is not a host limit.

*Exit, met (at eleven forms; the count is nine now):* the spec had eleven forms, each with a rule and an example, and seven examples in section 9 with their expected outcomes. Phase 3 checks the examples by running them.

Decisions taken in the spec (section 11, each revisable): laziness is explicit (`delay`, `force`); jet fuel is a declared formula, and there are no work-only jets (decision 11); strings stay lists of integers; pins are wrappers read through `unpin`; errors end the run and are not values; calls are strict; the step rule is one per form and one per law entry.

The two costs Phase 1 measured are answered in the core: recursion is `arg 0` (no fixed-point combinator, about 9% of the checker's steps), and `div`, `head` and `tail` are primitives with no `Result` (the program tests first, about 12% of the checker's steps were the accessors).

**Phase 3: the reference interpreter.** A small interpreter of the spec, with an explicit stack. It is the oracle, so it is written for clarity, not speed. Prototype 5's examples are ported to the core, through the L2 desugarer for the L2 programs.

*Exit, met in part (`reference/README.md`):* the reference agrees with Prototype 5's 50 examples and Prototype 6's 147 L2 program tests on every result: 193 agree, and 4 differ on purpose, each named. The first is the integer range, which the spec removes (decision 8); the second is a Prototype 5 pin, whose kind 4 the core gives to a suspended expression as kind 6 (decided: kind 6, SPEC.md decision 10). The fuel is not the same: the spec's step rule is not Prototype 5's or 6's count, so the reference reports its own steps beside theirs (786k against 624k on the examples; 313k against 339k on the L2 tests, at this phase; the lowering has since made the reference's programs smaller, 514k and 121k, see `reference/README.md`) and gives each budget 20 times the other machine's. The spec's examples have their step counts in `reference/interp_run.luau` (`call (lit inc) (lit 41)` is 7, by hand). The phase added two primitives to the spec, `tagof` and `payload` (decision 9), which lowering Prototype 6's expressions showed were needed.

*Decided:* the kind of a suspended expression is 6, the thunk's kind, as the spec has it (SPEC.md decision 10). Prototype 5's example expects 4 and is superseded for the core; the reference records it as a named difference.

**Phase 4: the fast interpreter.** One machine that compiles each law's body to a flat form and runs it in a single loop with an explicit stack. *Superseded in this run by a recursive evaluator with the same steps (Decisions, item 8); the result below is for the explicit-stack machine.* Leaf forms may be Luau closures.

*Exit:* the same results and fuel as Phase 3 on every test, and at least 3× the reference machine's steps per second on the checker benchmark.

*Result, met (`fast/`, `fast/README.md`):* the Go machine gives the reference's status, steps, value bytes and error messages on all 248 generated cases: 50 hand-written (one for each rule and primitive, and the errors), the 50 Prototype 5 examples, and the 147 Prototype 6 L2 tests. On the checker benchmark it takes exactly the reference's steps (141,778,148), and runs at 37.8 M steps/s against the reference's 3.0 M, which is 12.7×, on one host. The steps are checked, the timings are one run each. Not done: the machine reads a program into a tree of resolved nodes, not a flat array, which the 3× target does not need; the 36 inline checks of `interp_run.luau` are covered by the rules they test, not ported one by one.

**Phase 5: jets, for the hot library functions.** Use the Phase 0 histogram to pick the top few functions. Candidates: name and byte-string equality, map lookup, list append and reverse, and the substitution walk. Each jet has a reference law, a native body, a declared fuel formula, and a parity test.

*Result, met (`fast/jets.go`, `fast/trie.go`, `fast/README.md`):* the mechanism works, and every jet is exact. A jet is picked by the law's content hash, with no hint from the program; it charges the fuel its body would use, and gives up on any input it has not checked, so every error and every out-of-fuel point is the spec's. The jets are `tl`, `hdOr` and `stP` (the helpers) and `findB` and `setB` (the trie's lookup and update, each a whole recursion). They are used about 565,000 times on the checker and replace 62.8% of its core steps (68.0 million of 108.4 million); the steps are unchanged, as the fuel rule requires. The wall time drops from about 2.5 s to about 1.2 s on one host, a factor of about two. Each jet's fuel is measured on the reference, and the trie jets' arm costs are fitted to it with no residual, on 340 generated cases with the fuel edges; the whole suite passes with the jets on and off. Against the histogram: `findB` and `setB` were predicted at about 47% of the Prototype 6 profile, and the jets replace 62.8% of the core's steps, a little more, because the core counts differently.

*Exit:* every jet agrees with its reference on the whole test suite, the fuel formulas match wherever they are claimed to, and the checker benchmark's steps and work drop by the amount the histogram predicted.

**Phase 6: interned names and a byte kind.** Phase 0 measured name comparison (`same`) at 4.3% of the checker's steps on `types.l2`, and its share grows with the environment. Phase 1 removes most of the environment search, so Phase 6 is worth doing only if its share is still large after Phase 1. If it is, intern names as pins and add a byte kind for source text, with lexing as a jet. Lexing is linear already (565–706 steps per byte), so the byte kind is for speed, not for growth.

*Decision: not done (measured).* The core's profile of the checker (Phase 6 measurement, `fast/profile_test.go`) has name comparison (`same`) at 7.0% of the steps, and the environment's own operations at about 11% more. Interning names would remove the comparison, and nothing near that: the corpus build (Phase 8) takes about 6.9 s against a 1 s target, so removing 7% of the steps cannot close the gap. It would also change the lexer, the parser and the fuel of every name operation (a spec change and a rewrite of the boot programs). The name operations are better left as they are until the speed target needs them, and then the first step is a jet on `same`, which keeps the fuel.

*Exit:* the lexer and the parser give the same token and tree output on every program file, and the name cost in the histogram drops to a small share.

**Phase 7: memo and incremental re-check.** Add the memo table for pure calls, with the fuel rule above. Benchmark two runs: a cold check, and a re-check of the same input and then of an input with one declaration changed.

*Result, met (`fast/memo.go`, `fast/memo_test.go`, decisions 13 and 14):* the memo keys a saturated call by its law's content hash and the content hashes of its arguments, and a hit charges the stored fuel. The fuel is identical with and without it on every case, cold and warm. Two spec changes were needed: compound values are hashed from their parts (decision 13), and functions may be keys (decision 14). The second matters: with the memo keyed on data only, a one-declaration change still re-checked 90% of the checker's work, because the calls that pass a continuation never hit. With functions in the key, the changed declaration re-checks 270 calls (8,009 steps of work, against 108 million for a cold run); an unchanged input re-checks in 3 steps. The price is on the cold run: 1.15 s without the memo and about 2.5 s with it, and the memo stores a bounded set of entries (calls of at least 1,000 steps, `MemoMinFuel`), since without the threshold a cold corpus build stored 9.3 million entries and used 4.7 GB. The memo is off unless turned on.

*Exit:* the second run of an unchanged input does near-zero work, a one-declaration change costs work in proportion to that declaration, and fuel is identical with and without the memo.

**Phase 8: check against the speed target.** Run the harness on the reference host, and compare with the targets in "Speed target". Write the result in this README, including the misses.

*Result: the target is met on this host, measured directly on a 2,500-line corpus, with a margin of about 13% (`fast/corpus_test.go`, `CORPUS=testdata/corpus2500.txt`).* The corpus is the four boot files and 13 of the 20 standard-library files: 17 files, exactly 2,500 lines, 87,699 bytes (`fast/gen/corpus2500.luau`). Each file goes through its imports, then layout, lex, parse and check, on the four stage programs. Every stage of every file matches the reference, and the corpus's expect lines are the reference's outcomes. The build takes 260,297,203 core steps (about 104,000 per line). On this host, with the jets on, it takes 0.87 s (median of five; 0.86 to 0.93 s over the runs). The larger corpus of 2,590 lines (all 20 libraries) takes about 0.94 s, the same work per line. The stages are linear in lines (Phase 1).

Against the target (2,500 lines under 1 s), the measured numbers, all on the 2,500-line corpus unless stated:

| Configuration | Core steps | Time | Against the target |
| --- | ---: | ---: | --- |
| Jets on, memo off (default) | 260,297,203 | 0.87 s (median of 5) | met, margin about 13% |
| Jets off, memo off | 260,297,203 | about 2.4 s (2,590-line corpus, 2.46 s) | not met |
| Memo on, cold | 260,297,203 | about 2.5 s (2,590-line corpus) | not met (the memo costs a cold build) |
| Memo on, warm (same corpus again) | 260,297,203 | about 0.04 s (2,590-line corpus) | met, but only for an unchanged input |
| Jets on, `GOGC=400` (a host setting) | 260,297,203 | about 0.83 s (2,590-line corpus, 0.86 to 0.90 s) | met |

The checker alone (types.l2, jets on): 68,125,825 steps in about 0.16 s.

*With the desugarer.* The desugarer (`Prototypes/6/L2/programs/boot/desugar.l2`) now runs in the build: on each library, for the import expressions, and on each file, after its check. On the 2,500-line corpus (`testdata/corpus2500_desugar.txt`) the build takes 380,110,363 core steps and a median of about 1.53 s over five runs (1.51 to 1.60 s), against 260,297,203 steps and 0.90 s without it on the same host (`testdata/corpus2500.txt`). The desugarer is 119,813,160 steps (46% more) and about 0.63 s. So the 1 s target is missed by about 50% once the desugarer is counted. Its input has no checks (the corpus has none) and no input check, so the boundary's cost is left out. Nothing here is tuned: the desugarer has no jets, so its steps are all interpreted.

*Decision.* The target is met on this host by a direct measurement. The margin is about 13%, which is above the run-to-run noise (about 4%), but it is a margin on one host. Earlier in this run the 2,500-line figure was an extrapolation from the 2,590-line corpus (about 0.91 s); the direct measurement on the later build is 0.87 s, and the 2,590-line corpus on the same build takes about 0.94 s. The work that closed the gap, from about 2.9 times the target at the start of the run, was: the evaluator (about a quarter of the time), recycled frames (about 8%), the constants of the lowering and the mutual group's desugaring (fewer steps and smaller frames), the `head` and `tail` matches (about 13% of the steps), jets for five hot laws, the cache of a law's jet, and the removal of an unused form, which changes no step. The steps per line fell from 142,000 to about 104,000. The interpreted steps are about a third of the corpus's steps; the rest run as jets. A native host is not needed for the target on this host. Whether the target should hold on a slower host is not measured.

## Speed experiments

The corpus build on the Go machine, on this host, with the steps (core steps) and the time. Each entry is a single change, measured as the corpus time before and after.

- **Machine.** A continuation kept only its node, frame and child index; a leaf operand (lit or arg) is evaluated in place, as its own step; a node's children are read into pools; a law's jet is cached on the law (the lookup hashed 32 bytes on every call, about 7%). The explicit-stack loop was replaced by a recursive evaluator (about 26% faster on the corpus), with tail calls in a loop. Frames are recycled per run (a body gives its frame back when nothing refers to it; about 8% on the 2,500-line corpus). Each of these keeps the steps: the suite (cases, the corpus's expect lines, the memo and the jets on and off) passes unchanged.
- **Lowering: constants.** A variable bound to a closed value (a top-level function, or an integer) is a constant, not a frame slot, so a law no longer carries every top-level function it calls as an argument. The mutual group of the parser had 42 arguments per call; now it has 15. The corpus goes from 317.3 million steps to 307.4 million (with the mutual group below) and from 1.8 s to 1.43 s.
- **Desugar: mutual groups** (the measurement's copy of the desugarer; Prototype 6's is unchanged). A member's branch binds only the names of the group its body mentions (332.0 million steps to 317.3 million), and the dispatch on the member is a balanced tree of tests, not a chain (to 303.0 million). The expect lines of all 24 files are unchanged.
- **Jets, four list helpers** (`lenOf`, `envKid`, `envPut` and the parser's `same`): 1.37 s to 1.17 s, steps unchanged. **A jet for `prune`**: the corpus to 1.04 s, the checker from 0.36 s to 0.19 s.
- **Desugar: `match` on `head` or `tail`** (the measurement's copy). A match on `head x` or `tail x` with an `Ok` arm and an `Err` arm tests the kind of `x` and binds the part directly, so the `Ok` value is not built and tested by its tag. The expect lines are unchanged. The corpus goes from 303.0 million steps to 263.2 million, the checker from 76.3 million to 68.1 million. The eleven jets that use `head` or `tail` are re-hashed and re-fitted (a cell takes 12 steps for `tl`, `hdOr`, `first` and `hd`, and anything else 53).
- **Pins removed** (SPEC.md decision 16): the steps are unchanged; the three renumbered primitives change the law hashes, so the fourteen jets are re-hashed from the corpus. **The `case` form removed** (decision 17): no pipeline program used it, and the corpora are byte-identical.
- **Measured and not adopted:** the collector setting (`GOGC=400` gives about 8%; a host setting, not in the library); `GOGC=off` (slower, page faults); the flat program layout (Phase 4, about 7% slower); a table of preboxed small integers (no change); a balanced tree for the tag chains (about 1%, not done).

**Next candidates, not done.**
- The parser's largest unnamed law (about 5% of the remaining steps) is a large anonymous match on the token structure; it is not a jet candidate without a name.
- The mutual group's call goes through the dispatch law (a second entry for each member call). Binding the members once per group would remove it; that changes the desugarer's shape.

## Next step

Phases 1 to 8 are done, and the speed target is met on this host by a direct measurement, with a margin of about 13%. The spec has nine forms and thirteen primitives, and the shortcuts are no longer defined by it (decisions 16 to 18). Open: the parser's anonymous laws and the mutual group's dispatch (both speed, not required); and the owner's decision on the host's collector setting (decision 10 in "Decisions").

## Risks

- **Fuel parity with jets and memo.** The fuel rule above is the answer. A law whose formula is hard to state gets no jet, so it runs at the speed of the spec code. Keep track of the laws this leaves out, since they are the speed the Phase 8 target has to live with.
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
2. **Host: decided.** Luau through Phase 3 (the reference interpreter, the binary format and the front end). Go from Phase 4, for the fast machine, with the Go implementation reading the same binary format and checked against the Luau reference on the spec's examples and fuel. The front end (boot L2 and the Luau desugarer) stays in Luau, and it serialises core programs for the Go machine. Go's `math/big` is the reason; the small-integer fast path keeps the common case fast in either language.
3. **Resolved: fuel of jets.** Every jet declares a fuel formula, checked against the reference on the suite and on generated inputs. There are no work-only jets, so a law whose fuel cannot be stated gets no jet (SPEC.md decision 11). The reason is determinism: a work-only jet would make steps and out-of-fuel depend on which jets are installed.
4. **Resolved: strings and names stay lists of integers (option A).** Phase 6 was measured and not done (name comparison is 3% of the checker's steps, and the jet on `same` covers it). A byte kind would change the lexer, the parser and their fuel, and the corpus does not need it.
5. **Laziness.** Whether the core keeps `delay` and `force` as explicit forms, as drafted, or makes evaluation lazy by default. The plan assumes explicit forms, so that the cost of each thunk is visible in the fuel and work counts.
6. **Resolved: the content hash.** It is SHA-256 of a value's binary encoding without the header byte (fast/README.md "Keys"). It names a law, keys a memo, selects a jet, and interns a pin. Jets are chosen by the hash of the law, so no hint from a program is needed.
7. **Resolved: jets are for laws only.** Primitives stay primitives: a jet on one would add a law entry to its fuel for no gain. A new primitive needs a spec change with its reason (SPEC.md decision 12). Work that fuel does not count, such as `pin` encoding a whole value, is a known gap, closed by a spec change rather than a jet.
8. **Resolved (this run): the machine is recursive.** The explicit-stack machine (Phase 4) was replaced by a recursive evaluator with the same steps, form for form, and a loop for tail calls (`fast/eval.go`). It is about a quarter faster. The one cost is a host limit: a run nested deeper than `MaxNesting` (400,000 evaluations) ends with the status `host_limit`, which the spec does not have, instead of the Go stack overflowing. The spec asks for no depth limit; the host limit is documented in `fast/README.md`. The owner may prefer the iterative machine back if deep programs matter more than speed.
9. **Resolved (this run): pins are removed** (SPEC.md decision 16): the pin and unpin primitives, the pin value and its binary part. The spec has thirteen primitives.
10. **Open for the owner: the host's collector setting.** `GOGC=400` gives about 8% on the corpus (0.86 to 0.90 s against 0.94 to 0.96 s). It is a runtime setting of the host, not of the library, so it is not set in the code; a host that runs the VM can set it.
11. **Resolved (this run): the `case` form is removed** (SPEC.md decision 17). Nothing built it, and a jump table would save about 3% of the checker's steps, which is recorded in the spec as the reason to bring it back.
12. **Resolved (this run): the shortcuts are not part of the spec** (SPEC.md decision 18). The content hash was the key of the memo and the jets, so it leaves the spec, and the Go implementation keeps its definition in `fast/README.md`.
