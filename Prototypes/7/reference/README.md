# The Phase 3 reference

The reference is the oracle for the faster machines of Phase 4. It is written for clarity, in Luau, and follows `SPEC.md`. Phase 3's exit test is that it agrees with Prototypes 5 and 6 on every example and every L2 program test, and that it gives the spec's examples their step counts.

## Files

| File | What it is |
| --- | --- |
| `int.luau` | Integers of any size: a number when exact, a byte array otherwise. Exact add, sub, mul, floored div and mod, and comparison. |
| `format.luau` | The binary format (SPEC.md section 12). Iterative writer and reader, so the depth of a program is not limited by the host. |
| `interp.luau` | The machine. Each form costs one step, each saturated law entry one step, and a return costs nothing. Continuations are on an explicit stack. |
| `lower.luau` | Lowers a Prototype 5 or 6 expression to the core: lambda lifting for `lam`, a delay for `pin`, head and tail primitives for `index`, and the primitives `tagof` and `payload`. |
| `cross_run.luau` | The exit test: the reference against Prototype 5's examples and Prototype 6's L2 program tests, on the same inputs. |
| `interp_run.luau` | The reference's own checks: the spec's examples with their step counts, the primitives on big integers against identities, the errors, deep programs, and the thunk memo. |
| `format_run.luau` | The format's checks: the spec's bytes, round trips, and each refusal with its reason. |

Run each from this folder with `lute run <file>`. The outputs are in `*.txt` beside them.

## Results

- `interp_run.luau`: **40 of 40** checks pass. The step count of `call (lit inc) (lit 41)` is 7, worked out by hand.
- `format_run.luau`: **51 of 51** checks pass.
- `cross_run.luau`: **193 agree**, 4 differ on purpose (named below), **0 disagree**. Prototype 5's 50 examples and Prototype 6's 147 L2 program tests (all 44 files) are covered.

## What differs, and why

Four comparisons disagree on purpose. Each is recorded in `cross_run.luau` with its reason, and none is hidden:

1. **The integer range** (three examples). Prototype 5 gives an "out of range" error for add, sub and mul past 2^53. The spec removes that limit (SPEC.md section 1 and decision 8), so the reference gives the exact result. Those three Prototype 5 examples expect the old behaviour, and they are superseded by the spec.
2. **The kind of a pin** (one example). Prototype 5 reports a pin as kind 4. A Prototype 5 pin is a suspended expression: creating one does not run it, and forcing runs it once. The core models that as a thunk, kind 6. The spec gives pins their own kind 4 for stored values (decision 4), so a suspended expression is a thunk. This is decided: SPEC.md decision 10 keeps kind 6.

## Fuel

The exit test asks for the same fuel as Prototype 6. It is not met, by design: the spec's step rule (one per form, one per law entry, SPEC.md section 6) is not Prototype 5's or 6's count, so the step totals differ. The totals are reported, not compared:

| Set | Prototype's steps | Reference's steps |
| --- | ---: | ---: |
| Prototype 5 examples (50) | 786,116 | 624,051 |
| L2 program tests (147), on the values | 312,543 | 339,092 |

The reference is given a budget of 20 times the other machine's fuel, so a program that runs out of fuel on the other machine must also run out on the reference, and one that finishes must finish.

## How the lowering works

- A `lam` becomes a closed law. Its free variables come first as arguments, so a closure is a partial application of that law.
- A `pin` becomes a `delay` of a call of a closed law, so it is a thunk.
- A variable with no binder (an unbound name) gives a slot that no frame has, so it fails at run time, as the machine's "no variable" error does.
- `index n` becomes a chain of `head` and `tail` primitives, in the order of the address bits.
- `tagof` and `payload` become the primitives 12 and 13 (added to the spec in this phase; see below).

## Changes to the spec in this phase

- **Constructor tags are read by primitives.** `tagof` (12) and `payload` (13) were added. Lowering Prototype 6's expressions showed that the core could not read a constructor's tag for an open set of tags. The form count stays at eleven (SPEC.md decision 9).
- **Integers are unbounded**, and that is now the reference's behaviour (decision 8).

## Open decisions

- **Speed of the reference.** It is slow by design. Nothing here is tuned; Phase 4 is where the speed is.
