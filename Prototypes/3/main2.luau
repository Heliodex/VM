--!strict

type Hash = {
	read type: "#",
}
type Eval = {
	read type: "*",
	read eval: List,
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
type Thing = Hash | Eval | List | Num

local HASH: "#" = "#"
local EVAL: "*" = "*"
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

	if t.type == EVAL then
		return EVAL .. serialise(t.eval, noOps)
	end

	local elements: { string } = {}
	for i, elem in t.things do
		elements[i] = serialise(elem, noOps)
	end

	return `[{table.concat(elements, " ")}]`
end

local hash = table.freeze { type = HASH }

local function eval(list: List): Eval
	return table.freeze { type = EVAL, eval = list }
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

local function equalEval(a: Eval, b: Eval): boolean
	return equal(a.eval, b.eval)
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
		elseif a.type == EVAL and b.type == EVAL then equalEval(a, b)
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
	return list { x, unpack(y.things) }
end

local function addEnd(y: List, x: Thing): List
	return list { unpack(y.things), x }
end

local function reduce1(e: Thing, depth: number): Thing?
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
		if a.value == 1 and b.type == LIST then
			if len(b) ~= 2 then
				print(`{start}! !1 on non-2-list`)
				return nil
			end

			local xy, z1 = b.things[1], b.things[2]
			if z1.type ~= NUM then
				print(`{start}! 1 non-num index`)
				return nil
			end

			if equal(z1, num(0)) then
				return printReturn(xy)
			end

			if xy.type ~= LIST then
				print(`{start}! 1 positive index on non-list`)
				return nil
			end

			if equal(z1, num(1)) then
				return printReturn(xy.things[1])
			end

			local _, y = firstrest(xy)
			local z = num(z1.value - 1)

			return reduce1(list { num(1), list { y, z } }, depth)
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
				elseif b.type == EVAL then 1
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
				print(`{start}! !4 on non-num`)
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

			print(`{start}! !5 on non-loobean`)
			return nil
		end
		--[=[
			*[6 [[.x] y]] = [y .x]
		]=]
		if a.value == 6 and b.type == LIST and len(b) == 2 then
			local x, y = b.things[1], b.things[2]

			if x.type ~= LIST then
				print(`{start}! !6 arg 1 non-list`)
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
				print(`{start}! !7 arg 1 non-list`)
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
			*[9 [x y]] = *[x y]
		]=]
		if a.value == 9 and b.type == LIST and len(b) == 2 then
			-- might be useless idk let's find out
			return reduce1(b, depth)
		end
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
		eval = list { OP4, num(1) },
		res = num(2),
	},
	{
		eval = list { OP1, list { list { num(5), num(6) }, num(1) } },
		res = num(5),
	},
	{
		eval = list { OP1, list { list { num(5), num(6) }, num(2) } },
		res = num(6),
	},
	{
		eval = list { OP9, list { OP4, num(1) } },
		res = num(2),
	},
	{
		eval = list { list { OP4, OP4 }, num(2) },
		res = num(4),
	},
	{
		eval = list {
			list {
				OP4,
				list { OP1 },
			},
			num(2),
		},
		res = num(2),
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
