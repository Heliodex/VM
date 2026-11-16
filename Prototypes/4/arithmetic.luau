--!strict
-- ARITHMETIC ON CHURCH NUMERALS
--
-- Successor, addition and multiplication as lambda terms, so they are values built with lambda.luau and need no rules of their own.
-- Each is written as its textbook Church term, and `share` gives every variable as many uses as its term makes of it.
--
--   successor = λn.λf.λx. f (n f x)
--   addition  = λm.λn.λf.λx. m f (n f x)
--   product   = λm.λn.λf.λx. m (n f) x
--
-- Each builder returns the root of its value, so it can be applied with `L.app`.
-- To compute, apply the operator to numerals in one builder, reduce the net, and read the result back with `readback`.

const B = require "./builder"
const L = require "./lambda"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port

const function successor(
	b: Builder
): Port
	return L.lam(
		b, function(
			n: Port
		): Port
			return L.lam(
				b, function(
					f: Port
				): Port
					-- f is used twice: once inside n f, and once on the outside
					const fs = L.share(b, f, 2)

					return L.lam(
						b, function(
							x: Port
						): Port
							return L.app(b, fs[2], L.app(b, L.app(b, n, fs[1]), x))
						end
					)
				end
			)
		end
	)
end

const function addition(
	b: Builder
): Port
	return L.lam(
		b, function(
			m: Port
		): Port
			return L.lam(
				b, function(
					n: Port
				): Port
					return L.lam(
						b, function(
							f: Port
						): Port
							-- f is used by both m and n
							const fs = L.share(b, f, 2)

							return L.lam(
								b, function(
									x: Port
								): Port
									return L.app(b, L.app(b, m, fs[1]), L.app(b, L.app(b, n, fs[2]), x))
								end
							)
						end
					)
				end
			)
		end
	)
end

const function product(
	b: Builder
): Port
	return L.lam(
		b, function(
			m: Port
		): Port
			return L.lam(
				b, function(
					n: Port
				): Port
					return L.lam(
						b, function(
							f: Port
						): Port
							return L.lam(
								b, function(
									x: Port
								): Port
									return L.app(b, L.app(b, m, L.app(b, n, f)), x)
								end
							)
						end
					)
				end
			)
		end
	)
end

return {
	successor = successor,
	addition = addition,
	product = product,
}
