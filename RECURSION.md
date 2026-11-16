# Recursion in the interaction-combinator prototype

Hand-off note. The problem: we need general recursion (for example `length` and `sum` over lists) in the interaction-combinator prototype in `Prototypes/4/`, without adding primitives beyond the six interaction rules. The attempt so far has not terminated for recursive functions over lists, and the reasons are only partly understood.

## Constraints

- Only the six interaction rules of Lafont's interaction combinators (γ, δ, ε; annihilation and commutation). No `REF` nodes, no global definitions, no native numbers. This is a deliberate project constraint from the author.
- Reduction is full and eager: every active pair is reduced, including inside lambdas that are never applied. This is inherent to interaction nets, not a choice in our code.
- The harness (`harness.luau`) reduces with a step budget and reports `reduced`, `exhausted` or `cycled`. A repeated state is detected by a fingerprint plus `Canon.isomorphic`.

## What exists

Everything is in `Prototypes/4/`:

- `net.luau`, `rules.luau`: the net structure and the six rules.
- `builder.luau`: builds nets with handles. `B.from(net)` builds onto an existing net.
- `lambda.luau`: values and terms. `lam` (abstraction is a γ with root as principal, variable on aux1, body on aux2), `app` (γ with function as principal, result on aux1, argument on aux2), `share(b, p, n)` (fans a port out to `n` uses via the autodual multiplexer `T(n)`), `erase`.
- `numerals.luau`: Church numerals and readback.
- `observe.luau`: observation. A value is applied to a probe `T = λy.λz. G(y,z)` and an eraser, then reduced with plain stepping. Readback compares observations, not nets.
- `booleans.luau`, `lists.luau` (Scott encoding: `nil = λc.λn.n`, `cons h t = λc.λn. c h t`), `arithmetic.luau` (successor, addition, product).
- `fix.luau` (uncommitted): the strict Z combinator, `Z f = (λx. f (λv. x x v)) (λx. f (λv. x x v))`, built with `share`. Its header describes the problem below.
- `validate.luau`: 78 checks, all passing, runs in about 0.06 s. Includes `cases.luau` (calculus cases) and readback checks.

The harness and validation are fine for everything that terminates. The problems below are specifically about recursion.

## The problem

We cannot define a recursive function over lists whose evaluation finishes. Even `length []` does not finish, where `length = Z (λrec.λl. l (λh.λt. succ (rec t)) 0)`.

Evidence (all from `Prototypes/4/` with the modules above, step caps 5000 unless noted):

| Case | Result |
|---|---|
| `Z (λrec.λl. zero)` applied to `0` | finishes, 41 steps |
| `Z (λrec.λl. λv. v)` applied to `1` | finishes, 21 steps |
| `Z (λrec.λl. (λr.0) rec)` applied to `0` | finishes, 42 steps |
| `Z (λrec.λl. (λr.0) rec ...)` with the call erased by a lambda | finishes, 49 steps |
| `Z (λrec.λl. rec)` applied to `[]` (E8) | does not finish, cells grow to ~5000 |
| `Z step` applied to `[]`, where `step = λrec.λl. l H 0 rec` and `H` never recurses (E2/E5) | does not finish, cells 31 |
| `Z step` applied to `[]`, with `step = λrec.λl. l (λh.λt.λr.t) 0 rec` (E4) | does not finish, cells grow to ~4000 |
| `Z step` applied to `[]`, where the recursive value is only reachable through a handler that is erased (E9) | does not finish, cells 29 |
| `step I []` with no `Z` (E1) | finishes, 13 steps |
| `Z` with `rec` unused by `step` (E3) | finishes, 85 steps |

The last rows show a pattern. The recursive value is harmless when it is applied or never reached. It is a problem when it is duplicated or erased inside a structure that consumes it, such as a list's case branch. Returning it as the result (E8) is a genuine infinite normal form (an infinite Böhm tree), so that one is expected.

A reproducer for the simplest failing case (E4 in the table) is in the appendix.

## Why this happens (current understanding)

1. **Eager reduction under λ.** IC reduces every active pair, even inside lambdas that are never applied. So a recursive call inside a branch unfolds as soon as the branch is built. No thunk or lambda delays it.
2. **Self-application duplicates active structure.** Z copies the self-application `x x` through `share`. The copies are δ-trees attached to λ-values that themselves contain self-applications. Duplicating or erasing those while they still contain redexes lets the unfolding repeat.
3. **Divergence can be stuck, not infinite.** Some divergent terms reduce to a stuck, cyclic net with no active pair. `Z I` and `(λx.x x)(λx.x x)` both do this. The harness reports them as `reduced`. So "did not finish" cannot be read off the reduction outcome, and a cycle check on the normal form would also flag legitimate values such as `λx.x x`.

Literature (see References) agrees with these points. Lafont (1997) shows a non-terminating net that reduces to itself, and says reduction can lock in irreducible cuts or vicious circles. Mazza et al. note that in the symmetric combinators only cut-free nets can be duplicated, so there is no direct fixpoint combinator, and they solve recursion with Lafont's construction instead.

## Findings (follow-up session)

`Prototypes/4/recursionprobe.luau` runs the probes below (budget 20000 steps).

| Probe | Result |
|---|---|
| `(λx. x x) 1` | normal form, reads back as 1 |
| `(λx. x x) 2` | no normal form, about 40000 cells, almost all δ–γ steps |
| `(λn. add n n) 2` | normal form, reads back as 4 |
| `Z step []` | no normal form, 41 cells |
| `knot step []`: a fixpoint tied as a cycle (one γ and one δ), with no self-application | no normal form, 33 cells |
| `(λr. 0) (knot step)`: the knot is erased at once | no normal form, 29 cells |

Two causes explain all the failures:

1. **δ cannot copy δ.** `share` copies with a δ fan. When a value that holds δ fans is copied and the two copies then meet each other, as in `x x`, the fans annihilate with the wrong partners (Lafont, Lemma 3). `(λx. x x) 2` fails and `(λn. add n n) 2` works, because only the first makes the copies interact. Z depends on `x x`, so Z cannot work with δ sharing.
2. **A recursive value has an infinite normal form.** `fix step = λl. l H 0 (fix step)`: the recursive occurrence sits under `λl`, and full reduction normalises under λ, so the net keeps expanding it. The knot shows this does not depend on Z: it has no self-application and still diverges, even when its result is erased straight away. Option 1 cannot fix this, because `rec` is still part of the body whatever consumes it.

So, within the six rules, the self-reference has to be **passive**: a cut-free net that does not reduce until something unpacks it. That is what Lafont's codes do (§2.5–2.7). Lafont's Theorem 1 also says every interaction system can be translated into the combinators. A lazy reference agent (option 4) could therefore be designed as its own interaction system and then compiled into γ, δ and ε through Lafont's translation, which keeps the constraint. This is slower, but it turns options 2 and 4 into the same plan.

## Options

### 1. Delayed recursion through the data (does not work, see Findings)

Pass the recursive function into the consumer at the moment the data is consumed, so the recursive call is an unconnected application until its branch is chosen:

```
step = λrec. λl. l H Nc rec
H    = λh. λt. λr. succ (r t)
Nc   = λr. 0
```

The recursive call is then made by `H` only when the cons branch fires. This reasoning is sound in principle, but the experiments above show it still does not finish when `rec` is consumed by a branch, so something else is also duplicating or erasing the self-application. The cause is not identified. This is the option that needs research.

### 2. Lafont codes (research track, inside the six rules)

Encode a cut-free net as a passive code, copy the code, and decode it when needed. The copier duplicates the code without reducing anything, so no active structure is copied. Lafont (1997) describes this construction as the way to get general recursion in interaction combinators, and Mazza et al. use it too.

Milestones:

1. **Round trip.** Encode a cut-free net (for example a numeral or `T(3)`) as a code, decode it, and check the result is isomorphic to the original.
2. **Copy without reduction.** Copy a code and check that no reduction happens until the decoder is attached.
3. **Recursion.** Store the self-reference as a code and decode it only when the list's case fires (option 1 with a passive self-reference).

Milestone 1 is well defined and testable with the existing harness. Milestone 3 is the riskiest, and I don't know yet how the decoder would be driven from the list.

### 3. Unrolling in the builder (works now, bounded)

The builder expands the recursion to the depth of the data. For `length`:

```
F(0) = λl. 0
F(d) = λl. l (λh.λt. succ (F(d-1) t)) 0
```

The depth is the length of a literal list, which the compiler knows. I tested this: `length []` = 0 in 5 steps, `length [7]` = 1 in 42 steps, `length [2,3,4]` = 3 in 80 steps. Limits: depth must be known when the program is built, code size grows linearly with depth, and loops not bounded by the data cannot be expressed.

A variant adds a fuel numeral, decremented at each level, returning a marker when it runs out. Every term then terminates, and "did not finish" becomes a readable value.

### 4. Lazy reference node (breaks the constraint)

HVM2 solves this with `REF` nodes, which unfold only when they meet a constructor, and which are not part of IC. This would work, but it breaks the six-rule constraint, so it needs the author's agreement first.

## Divergence detection (open question, separate from recursion)

Even with a working recursion scheme, the harness needs a way to report non-termination:

- Stuck cyclic normal forms look finished.
- A cycle check on the normal form would flag `λx.x x`, which is a value.
- Observation (applying the value to a probe) might separate them: a diverging value's observation should not finish within budget. This needs checking against the stuck cases above.

## Suggested next steps

1. Decide with the author whether option 2 (Lafont codes, within the rules) or option 4 (a new node) is acceptable. Option 2 is the research path, option 4 is the pragmatic one.
2. Start Milestone 1 of option 2: encode and decode a cut-free net, with a test in `validate.luau`.
3. Keep option 3 (with fuel) as the working fallback for literal data.
4. Decide the divergence semantics (see above) before adding recursion tests to `cases.luau`.

## Verification

- `luau-analyze` on each `.luau` file should be clean.
- `luau validate.luau` should report all checks passing. Current: 78.
- `luau main.luau` should exit 0 and produce no `class="fail"` entries.
- Run `luau-format` after each change to `Prototypes/4/*.luau` (project rule).

## Appendix: minimal reproducer

Requires the modules in `Prototypes/4/` (use `luau` from that directory).

```lua
--!strict
const B = require "./builder"
const L = require "./lambda"
const F = require "./fix"
const N = require "./numerals"
const Li = require "./lists"
const Rules = require "./rules"

-- step = λrec. λl. l H 0 rec, with H = λh.λt.λr. t
local b = B.new()
const step = L.lam(b, function(rec)
	return L.lam(b, function(l)
		const h = L.lam(b, function(_h)
			return L.lam(b, function(t)
				return L.lam(b, function(_r) return t end)
			end)
		end)
		const nc = L.lam(b, function(_r) return N.church(b, 0) end)
		return L.app(b, L.app(b, L.app(b, l, h), nc), rec)
	end)
end)
L.app(b, L.app(b, F.fixpoint(b), step), Li.nilValue(b))
const net = b:finish()

local steps = 0
while Rules.step(net) do
	steps += 1
	if steps > 5000 then
		print("did not finish within 5000 steps")
		break
	end
end
print("steps", steps)
```

## References

- Y. Lafont, "Interaction Combinators", *Information and Computation* 137 (1997). Figure 3 (non-terminating net), section on reduced nets, and the copying construction.
- Y. Lafont, "Interaction Nets", POPL 1990. Introduces the model.
- Mazza et al., "Observational Equivalence and Full Abstraction in the Symmetric Interaction Combinators" (arXiv:0906.0380). Notes that only cut-free nets can be duplicated, and solves recursion with Lafont's construction.
- HVM2 paper, `paper/HVM2.pdf` in the HigherOrderCO/HVM2 repository. Discusses eager reduction and divergence, and introduces `REF` nodes.
- HVM1 and HVM2 documentation on lazy cloning and `REF`.
