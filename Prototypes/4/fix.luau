--!strict
-- FIXED POINTS
--
-- A recursive definition is a value that takes its own recursive call as an argument, and a fixed-point combinator turns that into the recursive function itself: `fix f` is `f (fix f)`.
-- This is the strict Z combinator, which has the shape
--   Z = λf. (λx. f (λv. x x v)) (λx. f (λv. x x v))
-- Both copies of `f` and of `x` are made with `share`, so nothing is left unused.
--
-- Use recursion.luau instead, which recurses through codes and terminates. This module is kept to show why Z cannot work here.
-- Known problem: interaction nets reduce everywhere, including inside lambdas that are never applied. A recursive call under a lambda therefore unfolds as soon as the lambda is built, and the unfolding never stops, so recursion over a list does not finish even for the empty list. Some divergent terms also end in stuck cyclic nets (`Z I` and `(λx.x x)(λx.x x)` both do), which the harness reports as finished. Recursion needs a different design before this module can be used.
-- There are two causes, both shown by recursionprobe.luau. First, `share` copies with delta, and delta cannot copy a net that holds delta (Lafont's Lemma 3): copying `x` in `x x` meets the fans already inside the value, so `(λx. x x) 2` grows without end. Second, any recursive value holds the fan that copies it, so it copies itself under the lambda for ever. Tying the knot as a cycle instead of with Z avoids self-application but still diverges, even when the result is erased.
--
--   const F = require "./fix"
--
--   const b = B.new()
--   const fix = F.fixpoint(b)

const B = require "./builder"
const L = require "./lambda"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port

-- λx. f (λv. x x v), where `f` is the port given. Built once for each copy of `f` that Z needs.
const function selfApply(
	b: Builder,
	f: Port
): Port
	return L.lam(
		b, function(
			x: Port
		): Port
			-- x appears twice inside the inner abstraction, so it is shared first
			const xs = L.share(b, x, 2)
			const inner = L.lam(
				b, function(
					v: Port
				): Port
					return L.app(b, L.app(b, xs[1], xs[2]), v)
				end
			)

			return L.app(b, f, inner)
		end
	)
end

-- λf. (λx. f (λv. x x v)) (λx. f (λv. x x v))
const function fixpoint(
	b: Builder
): Port
	return L.lam(
		b, function(
			f: Port
		): Port
			-- f is needed by both copies of the self-application
			const fs = L.share(b, f, 2)

			return L.app(b, selfApply(b, fs[1]), selfApply(b, fs[2]))
		end
	)
end

return {
	fixpoint = fixpoint,
}
