--!strict
-- RECURSION PROBES
--
-- Small nets that show why general recursion does not work with the current lambda encoding. See RECURSION.md for what each result means.
-- Each probe is reduced with plain stepping under a fixed budget, because the harness fingerprints every state and is too slow for nets that grow.
--
--   luau recursionprobe.luau

const A = require "./arithmetic"
const B = require "./builder"
const F = require "./fix"
const G = require "./gadgets"
const L = require "./lambda"
const Li = require "./lists"
const Net = require "./net"
const N = require "./numerals"
const Rules = require "./rules"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port
const BUDGET = 20000

const function probe(
	name: string,
	build: (Builder) -> ()
)
	const b = B.new()
	build(b)
	const net = b:finish()
	local steps = 0

	while steps < BUDGET and Rules.step(net) do
		steps += 1
	end

	if steps < BUDGET then
		print(`{name}: normal form after {steps} steps, reads back as {N.readback(net) or "nothing"}`)
	else
		print(`{name}: no normal form within {BUDGET} steps, {#Net.liveCells(net)} cells live`)
end end

-- λx. x x
const function selfApply(
	b: Builder
): Port
	return L.lam(
		b, function(
			x: Port
		): Port
			const xs = L.share(b, x, 2)

			return L.app(b, xs[1], xs[2])
		end
	)
end

-- step = λrec. λl. l H 0 rec, with H = λh.λt.λr. t (the reproducer from RECURSION.md)
const function step(
	b: Builder
): Port
	return L.lam(
		b, function(
			rec: Port
		): Port
			return L.lam(
				b, function(
					l: Port
				): Port
					const h = L.lam(
						b, function(
							_h: Port
						): Port
							return L.lam(
								b, function(
									t: Port
								): Port
									return L.lam(
										b, function(
											_r: Port
										): Port
											return t
										end
									)
								end
							)
						end
					)
					const nc = L.lam(
						b, function(
							_r: Port
						): Port
							return N.church(b, 0)
						end
					)

					return L.app(b, L.app(b, L.app(b, l, h), nc), rec)
				end
			)
		end
	)
end

-- A fixed point tied as a cycle instead of with Z: the result of f r is fanned out by one delta into the output and r itself.
const function knot(
	b: Builder,
	f: Port
): Port
	const g = b:gamma()
	b:wire(g.principal, f)
	const fan = G.autodualMultiplexer(b, 2)
	b:wire(g.aux1, fan.principal)
	b:wire(fan.ports[2], g.aux2)

	return fan.ports[1]
end

-- 1. Copying a value that contains a share fan, with another share fan.
probe(
	"(λx. x x) 1", function(
		b: Builder
	)
		L.app(b, selfApply(b), N.church(b, 1))
	end
)
probe(
	"(λx. x x) 2", function(
		b: Builder
	)
		L.app(b, selfApply(b), N.church(b, 2))
	end
)
probe(
	"(λn. add n n) 2", function(
		b: Builder
	)
		const f = L.lam(
			b, function(
				n: Port
			): Port
				const ns = L.share(b, n, 2)

				return L.app(b, L.app(b, A.addition(b), ns[1]), ns[2])
			end
		)
		L.app(b, f, N.church(b, 2))
	end
)
-- 2. Recursion through Z, which needs x x on a shared x.
probe(
	"Z step nil", function(
		b: Builder
	)
		L.app(b, L.app(b, F.fixpoint(b), step(b)), Li.nilValue(b))
	end
)
-- 3. Recursion through a cycle, which needs no self-application.
probe(
	"knot step nil", function(
		b: Builder
	)
		L.app(b, knot(b, step(b)), Li.nilValue(b))
	end
)
probe(
	"(λr. 0) (knot step)", function(
		b: Builder
	)
		const k = L.lam(
			b, function(
				_r: Port
			): Port
				return N.church(b, 0)
			end
		)
		L.app(b, k, knot(b, step(b)))
	end
)
