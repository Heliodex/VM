--!strict
-- BOOLEANS AND CONDITIONALS
--
-- Booleans are Church booleans, so they are values built with lambda.luau and need no rules of their own:
--   true         = λa.λb. a
--   false        = λa.λb. b
--   conditional  = λc.λt.λe. c t e
-- A conditional applies its condition to the two branches, so `if c x y` is `x` when `c` is true and `y` otherwise.
--
-- Readback is observational, as for numerals (see observe.luau). A boolean is applied to the probe and an eraser, and the result is compared with the same observation of `true` and of `false`.
-- That makes `false` and the numeral 0 indistinguishable, since both erase the probe: the two are different values, but nothing observed here separates them. Numbers are read back by scott.luau, so the two readbacks should not be applied to the same value.

const B = require "../engine/builder"
const Canon = require "../engine/canon"
const L = require "./lambda"
const Observe = require "../engine/observe"
const Types = require "../engine/types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port

-- λa.λb. a
const function truth(
	b: Builder
): Port
	return L.lam(
		b, function(
			a: Port
		): Port
			return L.lam(
				b, function(
					_unused: Port
				): Port
					return a
				end
			)
		end
	)
end

-- λa.λb. b
const function falsity(
	b: Builder
): Port
	return L.lam(
		b, function(
			_unused: Port
		): Port
			return L.lam(
				b, function(
					second: Port
				): Port
					return second
				end
			)
		end
	)
end

-- The boolean `value`, built into `b`.
const function boolean(
	b: Builder,
	value: boolean
): Port
	if value then
		return truth(b)
	end

	return falsity(b)
end

-- λc.λt.λe. c t e
const function conditional(
	b: Builder
): Port
	return L.lam(
		b, function(
			c: Port
		): Port
			return L.lam(
				b, function(
					t: Port
				): Port
					return L.lam(
						b, function(
							e: Port
						): Port
							return L.app(b, L.app(b, c, t), e)
						end
					)
				end
			)
		end
	)
end

-- A boolean as a net of its own, with its root free.
const function booleanNet(
	value: boolean
): Net
	const b = B.new()
	boolean(b, value)

	return b:finish()
end

-- What each boolean observes as. Computed once, since it never changes.
local observedTrue: Net? = nil
local observedFalse: Net? = nil

-- The boolean that a closed value stands for, or nil if it is neither.
const function readback(
	original: Net
): boolean?
	const seen = Observe.observe(original)

	if not seen then
		return nil
	end

	if observedTrue == nil then
		observedTrue = Observe.observe(booleanNet(true))
	end

	if observedFalse == nil then
		observedFalse = Observe.observe(booleanNet(false))
	end

	if observedTrue and Canon.isomorphic(seen, observedTrue) then
		return true
	end

	if observedFalse and Canon.isomorphic(seen, observedFalse) then
		return false
	end

	return nil
end

return {
	truth = truth,
	falsity = falsity,
	boolean = boolean,
	conditional = conditional,
	booleanNet = booleanNet,
	readback = readback,
}
