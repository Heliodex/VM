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

<!-- next: speed target -->
