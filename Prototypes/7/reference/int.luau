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
-- The module converts between these and the magnitudes of the binary format (SPEC.md section 12.2): unsigned LEB128, 7 bits per byte, least significant group first. It also does the arithmetic of the primitives, exactly: a result is never rounded.
--
--   Int.fromMagnitude(neg, bytes)   the integer with this sign and magnitude bytes
--   Int.magnitudeBytes(v)           the magnitude of v as bytes, least significant first
--   Int.lebGroups(bytes)            the LEB128 groups of a magnitude, least significant first; zero is {0}
--   Int.bytesFromGroups(groups)     the magnitude bytes of LEB128 groups, with no zero byte at the top
--   Int.sign(v)                     -1, 0 or 1
--   Int.isBig(v)                    whether v is a big integer
--   Int.equal(a, b)                 whether two integers are the same value
--   Int.add, Int.sub, Int.mul       exact results
--   Int.divFloor, Int.modFloor      floored quotient, and remainder with the sign of the divisor (a = b * q + r); the divisor must not be zero
--   Int.compare(a, b)               -1, 0 or 1

export type Big = { kind: "big", neg: boolean, bytes: { number } }
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

const function fromMagnitude(neg: boolean, bytes: { number }): Int
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

	return { kind = "big", neg = neg, bytes = trim }
end

const function magnitudeBytes(v: Int): { number }
	local out: { number } = {}

	if type(v) == "number" then
		local m =
			if v < 0 then
				-v
			else
				v

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

const function lebGroups(bytes: { number }): { number }
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
			acc += trim[i] * 2 ^ nacc
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

const function bytesFromGroups(groups: { number }): { number }
	local out: { number } = {}
	local acc = 0
	local nacc = 0

	for _, g in groups do
		acc += g * 2 ^ nacc
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

const function isBig(v: Int | { read kind: string }): boolean
	if type(v) == "number" then
		return false
	end

	return v.kind == "big"
end

const function sign(v: Int): number
	if type(v) == "number" then
		if v < 0 then
			return -1
		elseif v > 0 then
			return 1
		end

		return 0
	end

	return
		if v.neg then
			-1
		else
			1
end

const function equal(a: Int, b: Int): boolean
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

-- Magnitude arithmetic on byte arrays, least significant byte first.
const function magCompare(a: { number }, b: { number }): number
	if #a ~= #b then
		return
			if #a < #b then
				-1
			else
				1
	end

	for i = #a, 1, -1 do
		if a[i] ~= b[i] then
			return
				if a[i] < b[i] then
					-1
				else
					1
		end
	end

	return 0
end

const function magAdd(a: { number }, b: { number }): { number }
	local out: { number } = {}
	local carry = 0
	local n = math.max(#a, #b)

	for i = 1, n do
		local s = (a[i] or 0) + (b[i] or 0) + carry
		out[i] = s % 256
		carry =
			if s >= 256 then
				1
			else
				0
	end

	if carry > 0 then
		table.insert(out, carry)
	end

	return trimmed(out)
end

-- a - b, where a is at least b.
const function magSub(a: { number }, b: { number }): { number }
	local out: { number } = {}
	local borrow = 0

	for i = 1, #a do
		local d = a[i] - (b[i] or 0) - borrow

		if d < 0 then
			d += 256
			borrow = 1
		else
			borrow = 0
		end

		out[i] = d
	end

	return trimmed(out)
end

const function magMulSmall(a: { number }, m: number): { number }
	local out: { number } = {}
	local carry = 0

	for i = 1, #a do
		local p = a[i] * m + carry
		out[i] = p % 256
		carry = (p - p % 256) / 256
	end

	while carry > 0 do
		table.insert(out, carry % 256)
		carry = (carry - carry % 256) / 256
	end

	return trimmed(out)
end

const function magMul(a: { number }, b: { number }): { number }
	local out: { number } = {}

	for i = 1, #a + #b do
		out[i] = 0
	end

	for i = 1, #a do
		local carry = 0

		for j = 1, #b do
			local p = out[i + j - 1] + a[i] * b[j] + carry
			out[i + j - 1] = p % 256
			carry = (p - p % 256) / 256
		end

		local k = i + #b

		while carry > 0 do
			local p = out[k] + carry
			out[k] = p % 256
			carry = (p - p % 256) / 256
			k += 1
		end
	end

	return trimmed(out)
end

-- The quotient and remainder of magnitudes, by long division with one base-256 digit at a time, found by binary search.
const function magDivMod(a: { number }, b: { number }): ({ number }, { number })
	if magCompare(a, b) < 0 then
		return {}, a
	end

	local q: { number } = {}
	local rem: { number } = {}

	for i = #a, 1, -1 do
		-- rem = rem * 256 + a[i]
		local shifted: { number } = { a[i] }

		for j = 1, #rem do
			table.insert(shifted, rem[j])
		end

		rem = trimmed(shifted)
		local lo = 0
		local hi = 255

		while lo < hi do
			const mid = (lo + hi + 1) // 2

			if magCompare(magMulSmall(b, mid), rem) <= 0 then
				lo = mid
			else
				hi = mid - 1
			end
		end

		q[i] = lo
		rem = magSub(rem, magMulSmall(b, lo))
	end

	return trimmed(q), rem
end

-- Signed arithmetic. A number is fast-pathed when the exact result is in the number range; otherwise the byte form is used.
const function parts(v: Int): (boolean, { number })
	return sign(v) < 0, magnitudeBytes(v)
end

const function add(a: Int, b: Int): Int
	if type(a) == "number" and type(b) == "number" then
		const r = a + b

		if r >= -MAX_SAFE and r <= MAX_SAFE then
			return r
		end
	end

	const na, ma = parts(a)
	const nb, mb = parts(b)

	if na == nb then
		return fromMagnitude(na, magAdd(ma, mb))
	end

	if magCompare(ma, mb) >= 0 then
		return fromMagnitude(na, magSub(ma, mb))
	end

	return fromMagnitude(nb, magSub(mb, ma))
end

const function negate(a: Int): Int
	if type(a) == "number" then
		return -a
	end

	return fromMagnitude(not a.neg, a.bytes)
end

const function sub(a: Int, b: Int): Int
	return add(a, negate(b))
end

const function mul(a: Int, b: Int): Int
	if type(a) == "number" and type(b) == "number" then
		const r = a * b

		if r >= -MAX_SAFE and r <= MAX_SAFE then
			return r
		end
	end

	const na, ma = parts(a)
	const nb, mb = parts(b)

	return fromMagnitude(na ~= nb, magMul(ma, mb))
end

-- The floored quotient and remainder. The truncated quotient is found on magnitudes, then moved down by one when the remainder has the wrong sign.
const function divMod(a: Int, b: Int): (Int, Int)
	if type(a) == "number" and type(b) == "number" and a > -0x100000000 and a < 0x100000000 and b > -0x100000000 and b < 0x100000000 then
		local q = a // b
		local r = a - q * b

		return q, r
	end

	const na, ma = parts(a)
	const nb, mb = parts(b)
	const qm, rm = magDivMod(ma, mb)
	local q: Int = fromMagnitude(na ~= nb, qm)
	local r: Int = fromMagnitude(na, rm)

	if sign(r) ~= 0 and sign(r) ~= sign(b) then
		q = sub(q, 1)
		r = add(r, b)
	end

	return q, r
end

const function divFloor(a: Int, b: Int): Int
	local q = divMod(a, b)

	return q
end

const function modFloor(a: Int, b: Int): Int
	local _, r = divMod(a, b)

	return r
end

const function compare(a: Int, b: Int): number
	if type(a) == "number" and type(b) == "number" then
		if a == b then
			return 0
		end

		return
			if a < b then
				-1
			else
				1
	end

	const na = sign(a) < 0
	const nb = sign(b) < 0

	if na ~= nb then
		return
			if na then
				-1
			else
				1
	end

	const c = magCompare(magnitudeBytes(a), magnitudeBytes(b))

	return
		if na then
			-c
		else
			c
end

return {
	MAX_SAFE = MAX_SAFE,
	fromMagnitude = fromMagnitude,
	magnitudeBytes = magnitudeBytes,
	lebGroups = lebGroups,
	bytesFromGroups = bytesFromGroups,
	sign = sign,
	isBig = isBig,
	equal = equal,
	add = add,
	sub = sub,
	mul = mul,
	divFloor = divFloor,
	modFloor = modFloor,
	divMod = divMod,
	compare = compare,
}
