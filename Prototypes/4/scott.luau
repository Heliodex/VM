--!strict
-- SCOTT NUMERALS
--
-- The number n is built from zero by the successor: zero = λz.λs. z and succ n = λz.λs. s n, so n is applied to a zero case and a successor case, and the successor case is handed the predecessor.
-- Every argument is used at most once, so a Scott numeral contains no share and no δ. That is the point of the switch: a δ fan can copy a numeral, because a δ fan only fails to copy a net that already holds δ (see fix.luau and the known limitations in validate.luau).
--
-- Arithmetic cannot be written without a use of a predecessor more than once, so addition and multiplication are recursive and tied through recursion.luau. Their recursive calls sit in the successor case, which is passed the code as its argument, as in fold, so they only unfold when that case is chosen.
--
-- Readback converts a Scott numeral to a Church numeral by recursion, and then reads that with numerals.luau, so the same observation decides what a number is in both encodings.
--
--   const S = require "./scott"
--
--   const report, value = S.readback(function(b)
--       return L.app(b, L.app(b, S.addition(b), S.numeral(b, 2)), S.numeral(b, 3))
--   end)
--   -- value is 5

const B = require "./builder"
const Bo = require "./booleans"
const H = require "./harness"
const L = require "./lambda"
const N = require "./numerals"
const Rec = require "./recursion"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port
type Net = Types.Net
-- How many steps a readback may take before it is given up on.
const BUDGET = 200000

-- λp.p
const function identity(
	b: Builder
): Port
	return L.lam(
		b, function(
			p: Port
		): Port
			return p
		end
	)
end

-- λz.λs. z
const function zero(
	b: Builder
): Port
	return L.lam(
		b, function(
			z: Port
		): Port
			-- s is never used, so the lambda over it erases it
			return L.lam(
				b, function(
					_s: Port
				): Port
					return z
				end
			)
		end
	)
end

-- λn.λz.λs. s n
const function successor(
	b: Builder
): Port
	return L.lam(
		b, function(
			n: Port
		): Port
			return L.lam(
				b, function(
					_z: Port
				): Port
					return L.lam(
						b, function(
							s: Port
						): Port
							return L.app(b, s, n)
						end
					)
				end
			)
		end
	)
end

-- The numeral k, built into b.
const function numeral(
	b: Builder,
	k: number
): Port
	if k < 0 or k ~= math.floor(k) then
		error(`a numeral is a natural number, not {k}`)
	end

	local value = zero(b)

	for _ = 1, k do
		value = L.app(b, successor(b), value)
	end

	return value
end

-- λn. n zero (λp.p): the predecessor of zero is zero.
const function predecessor(
	b: Builder
): Port
	return L.lam(
		b, function(
			n: Port
		): Port
			return L.app(b, L.app(b, n, zero(b)), identity(b))
		end
	)
end

-- λn. n true (λp. false)
const function isZero(
	b: Builder
): Port
	return L.lam(
		b, function(
			n: Port
		): Port
			return L.app(b, L.app(b, n, Bo.truth(b)), L.lam(
				b, function(
					_p: Port
				): Port
					return Bo.falsity(b)
				end
			))
		end
	)
end

-- R = λc.λm.λn. m (λc'. n) (λp.λc''. succ (c'' p n)) c. Addition is add 0 n = n and add (p+1) n = succ (add p n).
-- n is used by both cases, so it is copied first.
local function additionDefine(
	b: Builder
): Port
	return L.lam(
		b, function(
			c: Port
		): Port
			return L.lam(
				b, function(
					m: Port
				): Port
					return L.lam(
						b, function(
							n: Port
						): Port
							const ns = L.share(b, n, 2)
							const zeroCase = L.lam(
								b, function(
									_c1: Port
								): Port
									return ns[1]
								end
							)
							const succCase = L.lam(
								b, function(
									p: Port
								): Port
									return L.lam(
										b, function(
											c2: Port
										): Port
											return L.app(b, successor(b), L.app(b, L.app(b, Rec.recall(b, c2), p), ns[2]))
										end
									)
								end
							)

							return L.app(b, L.app(b, L.app(b, m, zeroCase), succCase), c)
						end
					)
				end
			)
		end
	)
end

-- Addition, built into b.
const function addition(
	b: Builder
): Port
	return Rec.tie(b, additionDefine)
end

-- R = λc.λm.λn. m (λc'. zero) (λp.λc''. add n (c'' p n)) c. Multiplication is 0*n = 0 and (p+1)*n = n + p*n.
local function multiplicationDefine(
	b: Builder
): Port
	return L.lam(
		b, function(
			c: Port
		): Port
			return L.lam(
				b, function(
					m: Port
				): Port
					return L.lam(
						b, function(
							n: Port
						): Port
							const ns = L.share(b, n, 2)
							const zeroCase = L.lam(
								b, function(
									_c1: Port
								): Port
									return zero(b)
								end
							)
							const succCase = L.lam(
								b, function(
									p: Port
								): Port
									return L.lam(
										b, function(
											c2: Port
										): Port
											const rest = L.app(b, L.app(b, Rec.recall(b, c2), p), ns[2])

											return L.app(b, L.app(b, addition(b), ns[1]), rest)
										end
									)
								end
							)

							return L.app(b, L.app(b, L.app(b, m, zeroCase), succCase), c)
						end
					)
				end
			)
		end
	)
end

-- Multiplication, built into b.
const function multiplication(
	b: Builder
): Port
	return Rec.tie(b, multiplicationDefine)
end

-- R = λc.λm.λf.λx. m (λc'. x) (λp.λc''. f (c'' p f x)) c. Applied to a Scott numeral m, this gives the Church numeral with the same value.
local function toChurchDefine(
	b: Builder
): Port
	return L.lam(
		b, function(
			c: Port
		): Port
			return L.lam(
				b, function(
					m: Port
				): Port
					return L.lam(
						b, function(
							f: Port
						): Port
							return L.lam(
								b, function(
									x: Port
								): Port
									const fs = L.share(b, f, 2)
									const xs = L.share(b, x, 2)
									const zeroCase = L.lam(
										b, function(
											_c1: Port
										): Port
											return xs[1]
										end
									)
									const succCase = L.lam(
										b, function(
											p: Port
										): Port
											return L.lam(
												b, function(
													c2: Port
												): Port
													const rest = L.app(b, L.app(b, L.app(b, Rec.recall(b, c2), p), fs[2]), xs[2])

													return L.app(b, fs[1], rest)
												end
											)
										end
									)

									return L.app(b, L.app(b, L.app(b, m, zeroCase), succCase), c)
								end
							)
						end
					)
				end
			)
		end
	)
end

-- The Church numeral with the same value as the Scott numeral `m`, built into b.
const function toChurch(
	b: Builder
): Port
	return Rec.tie(b, toChurchDefine)
end

-- Builds a value into a fresh builder, reduces it under the budget, and returns the report and the net.
const function evaluate(
	build: (Builder) -> Port,
	budget: number?
): (H.Report, Net)
	const b = B.new()
	build(b)
	const net = b:finish()

	return H.reduce(net, budget or BUDGET), net
end

-- The number that the Scott value built by `build` stands for, or nil if the net is not a numeral.
const function readback(
	build: (Builder) -> Port,
	budget: number?
): (H.Report, number?)
	const b = B.new()
	const value = build(b)
	L.app(b, toChurch(b), value)
	const net = b:finish()
	const report = H.reduce(net, budget or BUDGET)

	return report, N.readback(net)
end

return {
	identity = identity,
	zero = zero,
	successor = successor,
	numeral = numeral,
	predecessor = predecessor,
	isZero = isZero,
	addition = addition,
	multiplication = multiplication,
	toChurch = toChurch,
	evaluate = evaluate,
	readback = readback,
}
