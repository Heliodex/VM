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

const B = require "../engine/builder"
const Bo = require "./booleans"
const Canon = require "../engine/canon"
const H = require "../engine/harness"
const L = require "./lambda"
const Net = require "../engine/net"
const Observe = require "../engine/observe"
const Rec = require "./recursion"
const Types = require "../engine/types"

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

-- R = λc.λm.λn. n (λc'. m) (λp.λc''. c'' (m - 1) p) c. Truncated subtraction: m - 0 = m, and m - (p+1) = (m - 1) - p, with 1 taken as the predecessor. The numeral to subtract is the scrutinee, so m is the one that is copied.
local function subtractionDefine(
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
							const ms = L.share(b, m, 2)
							const zeroCase = L.lam(
								b, function(
									_c1: Port
								): Port
									return ms[1]
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
											const smaller = L.app(b, predecessor(b), ms[2])

											return L.app(b, L.app(b, Rec.recall(b, c2), smaller), p)
										end
									)
								end
							)

							return L.app(b, L.app(b, L.app(b, n, zeroCase), succCase), c)
						end
					)
				end
			)
		end
	)
end

-- Truncated subtraction, built into b: m - n, which is 0 when n is larger.
const function subtraction(
	b: Builder
): Port
	return Rec.tie(b, subtractionDefine)
end

-- λm.λn. zero? (m - n): m is at most n.
const function lessEqual(
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
					return L.app(b, isZero(b), L.app(b, L.app(b, subtraction(b), m), n))
				end
			)
		end
	)
end

-- λm.λn. m ≤ n and n ≤ m, written as (m ≤ n) (n ≤ m) false, so that each of the two tests is used once.
const function equal(
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
					const ms = L.share(b, m, 2)
					const ns = L.share(b, n, 2)
					const first = L.app(b, L.app(b, lessEqual(b), ms[1]), ns[1])
					const second = L.app(b, L.app(b, lessEqual(b), ns[2]), ms[2])

					return L.app(b, L.app(b, first, second), Bo.falsity(b))
				end
			)
		end
	)
end

-- λm.λn. m < n, which is (m + 1) ≤ n.
const function less(
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
					return L.app(b, L.app(b, lessEqual(b), L.app(b, successor(b), m)), n)
				end
			)
		end
	)
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

-- The one free port of a net, if it has exactly one and it is a principal port.
const function freeRoot(
	net: Net
): Port?
	local root: Port? = nil
	local free = 0

	for _, c in Net.liveCells(net) do
		for slot = 1, Net.portCount(net.Tag[c]) do
			const p = Net.port(c, slot)

			if net.Link[p] == 0 then
				free += 1

				if Net.isPrincipal(p) then
					root = p
				end
			end
		end
	end

	if free == 1 then
		return root
	end

	return nil
end

-- The observation of the Scott value in `original` once it is converted to a Church numeral, or nil if the value or the conversion does not finish.
-- The value is reduced first, on a copy, so that its root is the principal port of its normal form. The original net is not changed.
const function observeChurch(
	original: Net,
	budget: number?
): (H.Report, Net?)
	const net: Net = {
		Tag = table.clone(original.Tag),
		Link = table.clone(original.Link),
		Active = table.clone(original.Active),
		Free = table.clone(original.Free),
	}
	const valueReport = H.reduce(net, budget or BUDGET)

	if valueReport.outcome ~= "reduced" then
		return valueReport, nil
	end

	const root = freeRoot(net)

	if not root then
		error "a value to read back must have exactly one free port, and it must be principal once reduced"
	end

	const b = B.from(net)
	L.app(b, toChurch(b), root)
	const report = H.reduce(net, budget or BUDGET)

	if report.outcome ~= "reduced" then
		return report, nil
	end

	return report, Observe.observe(net)
end

-- The largest numeral that readNet will try.
const MAX_READBACK = 64
-- What each numeral observes as, computed once for each numeral that is needed.
local references: {
	[number]: Net?,
} = {}

const function referenceFor(
	k: number
): Net?
	if references[k] == nil then
		const b = B.new()
		numeral(b, k)
		local _, observed = observeChurch(b:finish(), BUDGET)
		references[k] = observed
	end

	return references[k]
end

-- The number that a Scott value stands for, from its net, or nil if it stands for no numeral. The report is the reduction of the conversion, which is what a failure needs to explain itself.
-- A value is read by its observation, and a numeral is the one whose observation is the same, as in numerals of Church encoding. So a value that is not a numeral can only read back as one if it observes the same way.
const function readNet(
	original: Net,
	budget: number?
): (H.Report, number?)
	const report, seen = observeChurch(original, budget)

	if not seen then
		return report, nil
	end

	for k = 0, MAX_READBACK do
		const expected = referenceFor(k)

		if expected and Canon.isomorphic(seen, expected) then
			return report, k
		end
	end

	return report, nil
end

-- The number that the Scott value built by `build` stands for, or nil if it stands for no numeral.
const function readback(
	build: (Builder) -> Port,
	budget: number?
): (H.Report, number?)
	const b = B.new()
	build(b)

	return readNet(b:finish(), budget)
end

return {
	identity = identity,
	zero = zero,
	successor = successor,
	numeral = numeral,
	predecessor = predecessor,
	isZero = isZero,
	subtraction = subtraction,
	lessEqual = lessEqual,
	less = less,
	equal = equal,
	addition = addition,
	multiplication = multiplication,
	toChurch = toChurch,
	evaluate = evaluate,
	readNet = readNet,
	readback = readback,
}
