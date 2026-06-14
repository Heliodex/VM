--!strict

type Hash = {
	read type: "#",
}
type Pin = {
	read type: "!",
	read pin: List,
}
type List = {
	read type: "$",
	read things: { Thing },
}
type Num = {
	read type: "@",
	read value: number,
	read op: string?,
}
type Thing = Hash | Pin | List | Num

local HASH: "#" = "#"
local PIN: "!" = "!"
local LIST: "$" = "$"
local NUM: "@" = "@"

local function serialise(t: Thing, noOps: boolean?): string
	if t.type == NUM then
		if not noOps and t.op then
			return t.op
		end
		return tostring(t.value)
	end

	if t.type == HASH then
		return HASH
	end

	if t.type == PIN then
		return PIN .. serialise(t.pin, noOps)
	end

	local elements: { string } = {}
	for i, elem in t.things do
		elements[i] = serialise(elem, noOps)
	end

	return `[{table.concat(elements, " ")}]`
end

local hash = table.freeze { type = HASH }

local function pin(list: List): Pin
	return table.freeze { type = PIN, pin = list }
end

local function list(things: { Thing }): List
	return table.freeze {
		type = LIST,
		things = table.freeze(things),
	}
end

local function num(value: number, op: string?): Num
	if value < 0 then
		error "Negative numbers are not supported at the moment"
	end
	if value % 1 ~= 0 then
		error "Non-integer numbers are not supported at the moment"
	end
	return table.freeze { type = NUM, value = value, op = op }
end

local OP1, OP2, OP3, OP4, OP5, OP6, OP7, OP8, OP9 =
	num(1, "OP1"),
	num(2, "OP2"),
	num(3, "OP3"),
	num(4, "OP4"),
	num(5, "OP5"),
	num(6, "OP6"),
	num(7, "OP7"),
	num(8, "OP8"),
	num(9, "OP9")

local empty = list {}

local equal

local function equalPin(a: Pin, b: Pin): boolean
	return equal(a.pin, b.pin)
end

local function equalList(a: List, b: List): boolean
	if #a.things ~= #b.things then
		return false
	end

	for i, t in a.things do
		if not equal(t, b.things[i]) then
			return false
		end
	end

	return true
end

local function equalNum(a: Num, b: Num): boolean
	return a.value == b.value
end

function equal(a: Thing, b: Thing): boolean
	return if a.type == HASH and b.type == HASH
		then true
		elseif a.type == PIN and b.type == PIN then equalPin(a, b)
		elseif a.type == LIST and b.type == LIST then equalList(a, b)
		elseif a.type == NUM and b.type == NUM then equalNum(a, b)
		else false
end

local function len(s: List): number
	return #s.things
end

local function firstrest(s: List): (Thing, List)
	if #s.things == 0 then
		error "Cannot take first/rest of an empty list"
	end
	return s.things[1], list { unpack(s.things, 2) }
end

local function addStart(x: Thing, y: List): List
	local yc = table.clone(y.things)
	table.move(yc, 1, #yc, 2)
	yc[1] = x
	return list(yc)
end

local function addEnd(y: List, x: Thing): List
	local yc = table.clone(y.things)
	table.insert(yc, x)
	return list(yc)
end

local function index(x: Thing, y: Thing, depth: number): Thing?
	local start = string.rep("    ", depth)

	local function printReturn(a: Thing?)
		if a then
			print(start .. serialise(a))
		end
		return a
	end

	print(`{start}/[{serialise(x)} {serialise(y)}]`)

	-- /[x #] = *~
	-- /[x !y] = *~
	-- /[x [.y]] = *~
	if y.type ~= NUM then
		print(`{start}! / non-num index`)
		return nil
	end

	-- /[x 0] = x
	if equal(y, num(0)) then
		return printReturn(x)
	end

	if x.type ~= LIST then
		print(`{start}! / positive index on non-list`)
		return nil
	end

	-- /[[x .y] 1] = x
	-- /[[x .y] 1 + z] = /[y z]
	if equal(y, num(1)) then
		return printReturn(x.things[1])
	end

	local _, y2 = firstrest(x)
	local z = num(y.value - 1)

	return index(y2, z, depth)
end

local reduce1, replace

local function replaceList(x: List, y: Thing, depth: number): List?
	local start = string.rep("    ", depth)

	local function printReturn(a: List?)
		if a then
			print(start .. serialise(a))
		end
		return a
	end

	-- &[[] x] = []
	if len(x) == 0 then
		return printReturn(empty)
	end

	-- &[[x .y] z] = [&[x z] .&[y z]]
	local x2, y2 = firstrest(x)

	local sy = serialise(y)
	print(`{start}[&[{serialise(x2)} {sy}] .&[{serialise(y2)} {sy}]]`)

	local rxz = replace(x2, y, depth + 1)
	if not rxz then
		return nil
	end

	print(`{start}[{serialise(rxz)} .&[{serialise(y2)} {sy}]]`)

	print(`{start}    &[{serialise(y2)} {sy}]]`)

	local ryz = replaceList(y2, y, depth + 1)
	if not ryz then
		return nil
	end

	return printReturn(addStart(rxz, ryz))
end

function replace(x: Thing, y: Thing, depth: number): Thing?
	local start = string.rep("    ", depth)

	local function printReturn(a: Thing?)
		if a then
			print(start .. serialise(a))
		end
		return a
	end

	print(`{start}&[{serialise(x)} {serialise(y)}]`)

	-- &[# x] = x
	if x.type == HASH then
		return y
	end
	-- &[!x y] = !x
	if x.type == PIN then
		return x
	end

	-- &[[] x] = []
	-- &[[x .y] z] = [&[x z] .&[y z]]
	if x.type == LIST then
		return replaceList(x, y, depth)
	end

	-- &[x y] = x
	return printReturn(x)
end

function reduce1(e: Thing, depth: number): Thing?
	if depth < 0 then
		error "Invalid depth"
	end
	if depth > 10 then
		error "Too deep!"
	end
	local start = string.rep("    ", depth)

	local function printReturn(a: Thing?)
		if a then
			print(start .. serialise(a))
		end
		return a
	end

	print(`{start}*{serialise(e)}`)
	if e.type ~= LIST then
		-- *x = *x
		print(`{start}! evaluate non-list`)
		return nil
	end

	if len(e) ~= 2 then
		-- *x = *x
		print(`{start}! evaluate non-2-list`)
		return nil
	end

	local a, b = e.things[1], e.things[2]

	if a.type == NUM then
		--[=[
			*[1 [x #]] = *~
			*[1 [x *y]] = *~
			*[1 [x [.y]]] = *~
			*[1 [x 0]]  = x
			*[1 [[x .y] 1]] = x
			*[1 [[x .y] 1 + z]] = *[1 [y z]]
		]=]
		if a.value == 1 and b.type == LIST and len(b) == 2 then
			return index(b.things[1], b.things[2], depth)
		end
		--[=[
			*[2 #] = 0
			*[2 *x] = 1
			*[2 [.x]] = 2
			*[2 x] = 3
		]=]
		if a.value == 2 then
			local n = if b.type == HASH
				then 0
				elseif b.type == PIN then 1
				elseif b.type == LIST then 2
				else 3

			return printReturn(num(n))
		end
		--[=[
			*[3 [x x]] = 0
			*[3 [x y]] = 1
		]=]
		if a.value == 3 and b.type == LIST and len(b) == 2 then
			local x, y = b.things[1], b.things[2]

			return printReturn(num(if equal(x, y) then 0 else 1))
		end
		--[=[
			*[4 #] = *~
			*[4 *x] = *~
			*[4 [.x]] = *~
			*[4 x] = 1 + x
		]=]
		if a.value == 4 then
			if b.type ~= NUM then
				print(`{start}! 4 on non-num`)
				return nil
			end

			return printReturn(num(b.value + 1))
		end
		--[=[
			*[5 [0 x y]] = x
			*[5 [1 x y]] = y
		]=]
		if a.value == 5 and b.type == LIST and len(b) == 3 then
			local c, x, y = b.things[1], b.things[2], b.things[3]

			if equal(c, num(0)) then
				return printReturn(x)
			end
			if equal(c, num(1)) then
				return printReturn(y)
			end

			print(`{start}! 5 on non-loobean`)
			return nil
		end
		--[=[
			*[6 [[.x] y]] = [y .x]
		]=]
		if a.value == 6 and b.type == LIST and len(b) == 2 then
			local x, y = b.things[1], b.things[2]

			if x.type ~= LIST then
				print(`{start}! 6 arg 1 non-list`)
				return nil
			end

			return printReturn(addStart(y, x))
		end
		--[=[
			*[7 [[.x] y]] = [.x y]
		]=]
		if a.value == 7 and b.type == LIST and len(b) == 2 then
			local x, y = b.things[1], b.things[2]

			if x.type ~= LIST then
				print(`{start}! 7 arg 1 non-list`)
				return nil
			end

			return printReturn(addEnd(x, y))
		end
		--[=[
			*[8 [x .y]] = y
		]=]
		if a.value == 8 and b.type == LIST and len(b) >= 1 then
			local _, y = firstrest(b)

			return printReturn(y)
		end
		--[=[
		*[9 [x y z]] = *[*[y x] *[z x]]
		]=]
		if a.value == 9 and b.type == LIST and len(b) == 3 then
			local x, y, z = b.things[1], b.things[2], b.things[3]

			local sx = serialise(x)
			local s2 = `*[{serialise(z)} {sx}]`
			print(`{start}*[*[{serialise(y)} {sx}] {s2}]`)

			local ryx = reduce1(list { y, x }, depth + 1)
			if ryx == nil then
				return nil
			end

			print(`{start}*[{serialise(ryx)} {s2}]`)

			local rzx = reduce1(list { z, x }, depth + 1)
			if rzx == nil then
				return nil
			end

			return reduce1(list { ryx, rzx }, depth)
		end
	end
	--[=[
		*[!x y] = *&[x y]
	]=]
	if a.type == PIN then
		local ap = a.pin
		print(`{start}*&[{serialise(ap)} {serialise(b)}]`)

		local axy = replace(ap, b, depth + 1)
		if not axy then
			print(`{start}! failed to replace in pin`)
			return nil
		end

		return printReturn(reduce1(axy, depth + 1))
	end

	if a.type == LIST then
		--[=[
			*[[] x] = x
		]=]
		if len(a) == 0 then
			return printReturn(b)
		end
		--[=[
			*[[x .y] z] = *[y *[x z]]
		]=]
		local x, y = firstrest(a)

		print(`{start}*[{serialise(y)} *[{serialise(x)} {serialise(b)}]]`)

		local rxz = reduce1(list { x, b }, depth + 1)
		if not rxz then
			print(`{start}! failed to reduce *[{serialise(x)} {serialise(b)}]`)
			return nil
		end

		return reduce1(list { y, rxz }, depth)
	end

	print(`{start}! no matching reduction rule`)
	return nil
end

local tests: {
	{
		read eval: Thing,
		read res: Thing?,
	}
} = {
	{
		eval = list { OP1, list { list { num(5), num(6) }, num(1) } },
		res = num(5),
	},
	{
		eval = list { OP1, list { list { num(5), num(6) }, num(2) } },
		res = num(6),
	},
	{
		eval = list {
			OP1,
			list { list { num(5), num(6), num(7), num(8) }, num(4) },
		},
		res = num(8),
	},

	{
		eval = list { OP4, num(1) },
		res = num(2),
	},

	{
		eval = list { OP6, list { list { num(5), num(6) }, num(4) } },
		res = list { num(4), num(5), num(6) },
	},

	{
		eval = list { OP7, list { list { num(5), num(6) }, num(7) } },
		res = list { num(5), num(6), num(7) },
	},

	-- {
	-- 	eval = list { OP9, list { OP4, num(1) } },
	-- 	res = num(2),
	-- },

	{
		eval = list { list { OP4, OP4 }, num(2) },
		res = num(4),
	},
	{
		eval = list {
			pin(list {
				OP4,
				hash,
			}),
			num(5),
		},
		res = num(6),
	},
	{
		eval = list {
			list {
				pin(list {
					OP4,
					hash,
				}),
				pin(list {
					OP4,
					hash,
				}),
			},
			num(5),
		},
		res = num(7),
	},
	{
		eval = list {
			list {
				pin(list {
					OP4,
					hash,
				}),
				pin(list {
					OP6,
					list { list { num(4) }, hash },
				}),
				pin(list {
					OP7,
					list { hash, num(5) },
				}),
			},
			num(5),
		},
		res = list { num(6), num(4), num(5) },
	},

	-- decrement attempt
	{
		eval = list {
			list {
				-- first, make an [a c]
				pin(list {
					OP6,
					list {
						list { num(0, "c") }, -- counter
						hash,
					},
				}),

				-- next, increment
				pin(list {
					OP1,
					list { hash, num(2) },
				}),
				pin(list {
					OP4,
					hash,
				}),
			},
			num(5, "a"),
		},
	},
}

for i, test in tests do
	local rd = reduce1(test.eval, 0)
	local out
	if rd == nil then
		print "~~"
		print()
	else
		out = serialise(rd, true)
		print("=", out)
		print()
	end

	local expected = test.res and serialise(test.res, true)
	if out ~= expected then
		print(`Test failed: expected {expected}, got {out}`)
		break
	end
end
