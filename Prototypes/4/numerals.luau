--!strict
-- NATURAL NUMBERS AS CHURCH NUMERALS
--
-- The number n is the value λf.λx. f(f(...(f x))), with n applications of f to x, built with the lambda encoding of lambda.luau. Zero is λf.λx.x, where f is erased.
-- A numeral is a closed value, so its normal form is unique up to renaming and the value convention applies: exactly one free port, its principal root.
--
--   const N = require "./numerals"
--
--   const net = N.numeral(3)
--   H.reduce(net)
--   print(N.readback(net)) -- 3
--
-- Readback here is structural: it finds the k whose canonical net the normal form is isomorphic to. That works for numerals because their normal forms are canonical. It will not extend to function values, which need observation (applying them to probes) instead.

const Canon = require "./canon"
const B = require "./builder"
const L = require "./lambda"
const Net = require "./net"
const Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port

-- The numeral n, built into `b`. Returns its root, the principal port of the outermost abstraction.
const function church(
	b: Builder,
	n: number
): Port
	if n < 0 or n ~= math.floor(n) then
		error(`a numeral is a natural number, not {n}`)
	end

	return L.lam(b, function(
		f: Port
	): Port
		const fs = L.share(b, f, n)

		return L.lam(b, function(
			x: Port
		): Port
			-- f(f(...(f x))): the innermost application is the last copy of f
			local body = x

			for i = n, 1, -1 do
				body = L.app(b, fs[i], body)
			end

			return body
		end)
	end)
end

-- The numeral n as a net of its own, with its root free.
const function numeral(
	n: number
): Net
	const b = B.new()
	church(b, n)

	return b:finish()
end

-- The largest numeral readback will try. Each try builds and compares a net, so this bounds the work.
const MAX_READBACK = 64

-- The number that a normal form stands for, or nil if it is not a numeral.
-- It must have exactly one free port, and that port must be principal, as the value convention requires.
const function readback(
	net: Net
): number?
	local free = 0
	local principal = false

	for _, c in Net.liveCells(net) do
		for slot = 1, Net.portCount(net.Tag[c]) do
			const p = Net.port(c, slot)

			if (net.Link[p] or 0) == 0 then
				free += 1
				principal = Net.isPrincipal(p)
			end
		end
	end

	if free ~= 1 or not principal then
		return nil
	end

	for k = 0, MAX_READBACK do
		if Canon.isomorphic(net, numeral(k)) then
			return k
		end
	end

	return nil
end

return {
	church = church,
	numeral = numeral,
	readback = readback,
}
