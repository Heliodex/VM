--!strict
-- INTEGERS OF ANY SIZE, FOR THE PHASE 3 REFERENCE
--
-- The VM's integers have no size limit (SPEC.md section 1). This module is the reference's representation of them, in the host's terms:
--
--   a number, when the value is in the range -(2^53 - 1) to 2^53 - 1, where every whole number is exact as a double;
--   a big integer, otherwise: { big = true, neg = boolean, bytes = {...} }, where bytes is the magnitude, least significant byte first, with no zero byte at the top end.
--
-- A value has exactly one representation: a big integer is never in the number range. So two integers are equal exactly when their representations are equal.
--
-- The module converts between these and the magnitudes of the binary format (SPEC.md section 12.2): unsigned LEB128, 7 bits per byte, least significant group first.
--
--   Int.fromMagnitude(neg, bytes)   the integer with this sign and magnitude bytes
--   Int.magnitudeBytes(v)           the magnitude of v as bytes, least significant first
--   Int.lebGroups(bytes)            the LEB128 groups of a magnitude, least significant first; zero is {0}
--   Int.bytesFromGroups(groups)     the magnitude bytes of LEB128 groups, with no zero byte at the top
--   Int.sign(v)                     -1, 0 or 1
--   Int.isBig(v)                    whether v is a big integer
--   Int.equal(a, b)                 whether two integers are the same value

export type Big = { big: boolean, neg: boolean, bytes: { number } }
export type Int = number | Big

-- The largest integer a double holds exactly, with the range the representation above uses for numbers.
const MAX_SAFE = 9007199254740991

-- Drops the zero bytes at the top end, so the magnitude has one representation.
const function trimmed(bytes: { number }): { number }
	local n = #bytes

	while n > 0 and bytes[n] == 0 do
		n -= 1
	end

	local out: { number } = {}

	for i = 1, n do
		out[i] = bytes[i]
	end

	return out
end

-- The magnitude as a number, when the magnitude is at most MAX_SAFE. Partial sums of a magnitude at most MAX_SAFE are exact, and a larger magnitude gives a larger float, so this check is exact.
const function magnitudeNumber(bytes: { number }): number?
	if #bytes > 7 then
		return nil
	end

	local value = 0
	local scale = 1

	for i = 1, #bytes do
		value += bytes[i] * scale
		scale *= 256
	end

	if value > MAX_SAFE then
		return nil
	end

	return value
end

local function fromMagnitude(neg: boolean, bytes: { number }): Int
	const trim = trimmed(bytes)
	const small = magnitudeNumber(trim)

	if small ~= nil then
		if neg then
			if small == 0 then
				return 0
			end

			return -small
		end

		return small
	end

	return { big = true, neg = neg, bytes = trim }
end

local function magnitudeBytes(v: Int): { number }
	local out: { number } = {}

	if type(v) == "number" then
		local m = if v < 0 then -v else v

		while m > 0 do
			local b = m % 256
			table.insert(out, b)
			m = (m - b) / 256
		end

		return out
	end

	for i = 1, #v.bytes do
		out[i] = v.bytes[i]
	end

	return out
end

local function lebGroups(bytes: { number }): { number }
	const trim = trimmed(bytes)

	if #trim == 0 then
		return { 0 }
	end

	local out: { number } = {}
	local acc = 0
	local nacc = 0
	local i = 1

	-- acc holds nacc bits not yet written, least significant first. Bytes are added as they are needed, and a group is taken from the bottom, so the groups come out least significant first.
	repeat
		if nacc < 7 and i <= #trim then
			acc += trim[i] * (2 ^ nacc)
			nacc += 8
			i += 1
		end

		local g = acc % 128
		acc = (acc - g) / 128
		nacc -= 7
		table.insert(out, g)
	until not (i <= #trim or acc > 0)

	return out
end

local function bytesFromGroups(groups: { number }): { number }
	local out: { number } = {}
	local acc = 0
	local nacc = 0

	for _, g in groups do
		acc += g * (2 ^ nacc)
		nacc += 7

		while nacc >= 8 do
			local b = acc % 256
			table.insert(out, b)
			acc = (acc - b) / 256
			nacc -= 8
		end
	end

	if acc > 0 then
		table.insert(out, acc)
	end

	return trimmed(out)
end

local function sign(v: Int): number
	if type(v) == "number" then
		if v < 0 then
			return -1
		elseif v > 0 then
			return 1
		end

		return 0
	end

	return if v.neg then -1 else 1
end

local function equal(a: Int, b: Int): boolean
	if type(a) == "number" and type(b) == "number" then
		return a == b
	end

	if type(a) == "number" or type(b) == "number" then
		return false
	end

	if a.neg ~= b.neg or #a.bytes ~= #b.bytes then
		return false
	end

	for i = 1, #a.bytes do
		if a.bytes[i] ~= b.bytes[i] then
			return false
		end
	end

	return true
end

return {
	MAX_SAFE = MAX_SAFE,
	fromMagnitude = fromMagnitude,
	magnitudeBytes = magnitudeBytes,
	lebGroups = lebGroups,
	bytesFromGroups = bytesFromGroups,
	sign = sign,
	isBig = function(v: any): boolean
		return type(v) == "table" and v.big == true
	end,
	equal = equal,
}
