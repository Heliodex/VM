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

<!-- next: core design -->
