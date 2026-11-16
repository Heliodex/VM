--!strict
-- VALUES AND THE LAMBDA CALCULUS
--
-- A value is a net with one free root port, the principal port of its outermost cell. Applying a value to another value is then a principal-to-principal meeting, which the six rules already reduce, so no value needs any rule of its own.
-- A closed value reduces to a normal form with no free port except its root. Two values that compute the same function need not reduce to isomorphic nets, because sharing can leave the copies arranged in different trees. So values are compared by what they do under probes (see numerals.luau), not by comparing nets.
--
-- Terms are built with the encoding of Lafont's "Interaction Combinators" for the lambda calculus:
--   abstraction  gamma cell: principal = root, aux1 = the variable, aux2 = the body
--   application  gamma cell: principal = the function, aux1 = the result, aux2 = the argument
-- The auxiliaries are paired so that the gamma-gamma rule wires the argument into the variable and the body into the result.
-- A variable used more than once is fanned out with `share`, and a variable that is never used is erased, so no term ever leaves a variable dangling.
--
--   const L = require "./lambda"
--
--   const b = B.new()
--   const identity = L.lam(b, function(x)
--       return x
--   end)
--   const v = L.app(b, identity, identity)
--   b:finish()

const B = require "./builder"
const G = require "./gadgets"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port

-- Discard a port: an eraser on it lets the net it belongs to vanish once the port is used.
const function erase(
	b: Builder,
	p: Port
)
	const e = b:epsilon()
	b:wire(p, e.principal)
end

-- Make `n` copies of the port `p`, one for each use of a variable. A port used once is simply returned, and an unused one is erased.
const function share(
	b: Builder,
	p: Port,
	n: number
): { Port }
	if n == 0 then
		erase(b, p)

		return {}
	end

	if n == 1 then
		return {
			p,
		}
	end

	const fan = G.autodualMultiplexer(b, n)
	b:wire(p, fan.principal)

	return fan.ports
end

-- An abstraction. `body` receives the variable's port and returns the root of the body. A variable the body never touches is erased here, so the caller never has to.
const function lam(
	b: Builder,
	body: (Port) -> Port
): Port
	const h = b:gamma()
	const x = h.aux1 :: Port
	const root = body(x)
	b:wire(h.aux2 :: Port, root)

	if b.net.Link[x] == 0 then
		erase(b, x)
	end

	return h.principal :: Port
end

-- An application of `fn` to `arg`. Returns the port that carries the result.
const function app(
	b: Builder,
	fn: Port,
	arg: Port
): Port
	const g = b:gamma()
	b:wire(g.principal, fn)
	b:wire(g.aux2 :: Port, arg)

	return g.aux1 :: Port
end

return {
	lam = lam,
	app = app,
	share = share,
	erase = erase,
}
