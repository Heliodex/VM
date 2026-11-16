--!strict
-- RECURSION THROUGH CODES
--
-- A recursive value cannot hold itself: interaction nets reduce everywhere, so a value that contains its own recursive call unfolds for ever (see RECURSION.md). Instead it holds nothing of itself and takes its own code as an argument, R = λc. ..., and passes the code on to whichever branch needs to recurse. Only that branch copies the code and decodes one copy, and it does so under a variable that stays unbound until the branch is chosen, so nothing unfolds early.
-- The code has no δ in it, so a δ fan can copy it (codes.luau), and decoding it gives back R, which is then applied to the other copy.
--
-- Cost is linear in the data: length of an n-element list takes about 133 + 78n steps, and the net stays under a few hundred cells.
--
--   const Rec = require "./recursion"
--
--   const b = B.new()
--   L.app(b, Rec.length(b), list) -- reduces to a numeral
--
-- `fold` builds R for a fold over a Scott list, and `tie` turns any R into the recursive function. Inside R, `recall` on the code argument is the recursive call.

const A = require "./arithmetic"
const B = require "./builder"
const Codes = require "./codes"
const L = require "./lambda"
const Net = require "./net"
const N = require "./numerals"
const Rules = require "./rules"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port
-- How many steps R may take to reach its normal form before it is encoded.
const BUDGET = 100000

-- The recursive function, from a port carrying the code of R: one copy of the code is decoded into R, and R is applied to the other.
const function recall(
	b: Builder,
	code: Port
): Port
	const copies = L.share(b, code, 2)
	const d = Codes.decoder(b, 1)
	b:wire(copies[1], d.principal)

	return L.app(b, d.ports[1], copies[2])
end

-- The recursive function defined by `define`, which builds R = λc. ... into the builder it is given and returns its root.
-- R is built and reduced on its own first, because only a cut-free net can be encoded. Its code is then built into `b` and recalled.
const function tie(
	b: Builder,
	define: (Builder) -> Port
): Port
	const own = B.new()
	define(own)
	const r = own:finish()
	local steps = 0

	while Rules.step(r) do
		steps += 1

		if steps >= BUDGET then
			error(`R did not reach a normal form within {BUDGET} steps`)
	end end

	if #Codes.freePorts(r) ~= 1 then
		error "R must be a closed value, with its root as its only free port"
	end

	return recall(b, Codes.encode(b, r))
end

-- R's normal form, as a net of its own, which says how big the code of a recursive definition is.
const function size(
	define: (Builder) -> Port
): number
	const own = B.new()
	define(own)
	const r = own:finish()

	while Rules.step(r) do
	end

	return #Net.liveCells(r)
end

-- R for a fold over a list: λc.λl. l (λh.λt.λc'. step h (recall c' t)) (λc'. 0) c.
-- The code goes in as the last argument of the list's case, so the cons branch gets it and the nil branch erases it. `step` builds the function that combines a head with the folded tail.
const function fold(
	step: (Builder) -> Port
): (Builder) -> Port
	return function(
		b: Builder
	): Port
		return L.lam(
			b, function(
				c: Port
			): Port
				return L.lam(
					b, function(
						l: Port
					): Port
						const consCase = L.lam(
							b, function(
								h: Port
							): Port
								return L.lam(
									b, function(
										t: Port
									): Port
										return L.lam(
											b, function(
												again: Port
											): Port
												return L.app(b, L.app(b, step(b), h), L.app(b, recall(b, again), t))
											end
										)
									end
								)
							end
						)
						const nilCase = L.lam(
							b, function(
								_again: Port
							): Port
								return N.church(b, 0)
							end
						)

						return L.app(b, L.app(b, L.app(b, l, consCase), nilCase), c)
					end
				)
			end
		)
end end

-- The length of a list: each head is dropped and the folded tail is incremented.
const function length(
	b: Builder
): Port
	return tie(
		b, fold(function(
			own: Builder
		): Port
			return L.lam(
				own, function(
					_h: Port
				): Port
					return A.successor(own)
				end
			)
		end)
	)
end

-- The sum of a list of numerals.
const function sum(
	b: Builder
): Port
	return tie(b, fold(A.addition))
end

return {
	fold = fold,
	length = length,
	sum = sum,
	recall = recall,
	tie = tie,
	size = size,
}
