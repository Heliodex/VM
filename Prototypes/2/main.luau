--!strict

-- Welcome back

type Num = {
	read type: "@",
	read value: number,
	read op: string?,
}
type Thing = List | Num
type List = {
	read type: "$",
	read things: { Thing },
}

local NUM: "@" = "@"
local LIST: "$" = "$"

local function serialise(t: Thing, useOps: boolean): string
	if t.type == NUM then
		if useOps and t.op then
			return t.op
		end
		return tostring(t.value)
	end

	local elements: { string } = {}
	for i, elem in t.things do
		elements[i] = serialise(elem, useOps)
	end

	return `[{table.concat(elements, " ")}]`
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

local function list(things: { Thing }): List
	return table.freeze {
		type = LIST,
		--[[table.freeze(things)]]
		things = things,
	}
end

local empty = list {}

local function equalNum(a: Num, b: Num): boolean
	return a.value == b.value
end

local equal

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

function equal(a: Thing, b: Thing): boolean
	return if a.type == NUM and b.type == NUM
		then equalNum(a, b)
		elseif a.type == LIST and b.type == LIST then equalList(a, b)
		else false
end

local function len(s: List): number
	return #s.things
end

local TRUE, FALSE = num(0, "TRUE"), num(1, "FALSE") -- imagine loobeans but if they were loobeans

local SUM, REST, PART, START, END, TYPE, CHECK, LEN, SPLIT, IF =
	num(0, "SUM"),
	num(1, "REST"),
	num(2, "PART"),
	num(3, "START"),
	num(4, "END"),
	num(5, "TYPE"),
	num(6, "CHECK"),
	num(7, "LEN"),
	num(8, "SPLIT"),
	num(9, "IF")

local function firstrest(s: List): (Thing, List)
	if #s.things == 0 then
		error "Cannot take first/rest of an empty list"
	end
	return s.things[1], list { unpack(s.things, 2) }
end

local function firstsecondrest(s: List): (Thing, Thing, List)
	if #s.things == 0 then
		error "Cannot take first/second/rest of an empty list"
	end
	if #s.things == 1 then
		error "Cannot take second/rest of a list with only one element"
	end
	return s.things[1], s.things[2], list { unpack(s.things, 3) }
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
			print(start .. serialise(a, true))
		end
		return a
	end

	print(`{start}*{serialise(e, true)}`)
	if e.type == NUM then
		-- *x -> *x
		print(`{start}! evaluate number`)
		return nil
	end

	if len(e) <= 1 then
		-- *x -> *x
		print(`{start}! not enough elements to match any rules`)
		return nil
	end

	local a, b = e.things[1], e.things[2]

	-- SUM
	if equal(b, SUM) and a.type == LIST then
		-- *[[] SUM] -> 0
		if equal(a, empty) then
			return printReturn(num(0))
		end

		local x, y = firstrest(a)

		-- *[[[.x] .y] SUM] -> *[[x .y] SUM]
		if x.type == LIST then
			return nil
		end

		-- *[[x .y] SUM] -> x + *[y SUM]
		local ysum = reduce1(list { y, SUM }, depth + 1)
		if ysum == nil then
			return nil
		end

		if ysum.type ~= NUM then
			error "Expected a number"
		end

		return printReturn(num(x.value + ysum.value))
	end

	-- REST
	if equal(b, REST) and a.type == LIST then
		-- *[[x .y] REST] -> y
		if equal(a, empty) then
			return nil
		end

		local _, y = firstrest(a)
		return printReturn(y)
	end

	-- PART
	if b.type == LIST and len(b) == 2 and equal(b.things[1], PART) then
		local b2 = b.things[2]

		-- *[x [PART 0]] -> x
		if equal(b2, num(0)) then
			return printReturn(a)
		end

		-- *[[x .y] [PART 1]] -> x
		if a.type == LIST and len(a) >= 1 and equal(b2, num(1)) then
			return printReturn(a.things[1])
		end

		-- *[x [PART [.y]] -> *[x [PART y]]
		if b2.type == LIST then
			return nil
		end

		-- *[[x .y] [PART z]] -> *[y [PART z - 1]]
		if a.type == LIST and len(a) >= 1 then
			local _, y = firstrest(a)

			return printReturn(list {
				y,
				list { PART, num(b2.value - 1) },
			})
		end
	end

	-- START
	if b.type == LIST and len(b) == 2 and equal(b.things[1], START) then
		-- *[[.x] [START y]] -> [y .x]
		if a.type == LIST then
			local y = b.things[2]

			return printReturn(addStart(y, a))
		end
	end

	if b.type == LIST and len(b) == 2 and equal(b.things[1], END) then
		-- *[[.x] [END y]] -> [.x y]
		if a.type == LIST then
			local y = b.things[2]

			return printReturn(addEnd(a, y))
		end
	end

	-- TYPE
	if equal(b, TYPE) then
		-- *[[.x] TYPE] -> 0
		if a.type == LIST then
			return printReturn(num(0))
		end

		-- *[x TYPE] -> 1
		return printReturn(num(1))
	end

	-- CHECK
	if equal(b, CHECK) and a.type == LIST then
		-- *[[] CHECK] -> 0
		if equal(a, empty) then
			return printReturn(num(0))
		end

		-- *[[x] CHECK] -> 0
		if len(a) == 1 then
			return printReturn(num(0))
		end

		-- *[[x x .y] CHECK] -> *[[x .y] CHECK]
		local p1, p2, rest = firstsecondrest(a)
		if equal(p1, p2) then
			return printReturn(list { addStart(p1, rest), CHECK })
		end

		-- *[[x y .z] CHECK] -> 1
		return printReturn(num(1))
	end

	-- LEN
	if equal(b, LEN) and a.type == LIST then
		-- *[[] LEN] -> 0
		if equal(a, empty) then
			return printReturn(num(0))
		end

		-- *[[x] LEN] -> 1
		if len(a) == 1 then
			return printReturn(num(1))
		end

		-- *[[x .y] LEN] -> 1 + *[y LEN]
		local _, y = firstrest(a)

		local ylen = reduce1(list { y, LEN }, depth + 1)
		if ylen == nil then
			return nil
		end

		if ylen.type ~= NUM then
			error "Expected a number"
		end

		return printReturn(num(1 + ylen.value))
	end

	if equal(b, SPLIT) and a.type == LIST then
		-- *[[x y z] SPLIT] -> *[*[x y] *[x z]]
		if len(a) == 3 then
			local x, y, z = a.things[1], a.things[2], a.things[3]

			local rxy = reduce1(list { list { x, y }, SPLIT }, depth + 1)
			if rxy == nil then
				return nil
			end

			local rxz = reduce1(list { list { x, z }, SPLIT }, depth + 1)
			if rxz == nil then
				return nil
			end

			return printReturn(
				reduce1(list { list { rxy, rxz }, SPLIT }, depth + 1)
			)
		end
	end

	if b.type == LIST and len(b) == 3 and equal(b.things[1], IF) then
		local x, y = b.things[2], b.things[3]

		-- 	*[0 [IF x y]] -> x
		if equal(a, num(0)) then
			return printReturn(x)
		end

		-- *[1 [IF x y]] -> y
		if equal(a, num(1)) then
			return printReturn(y)
		end
	end

	-- *[x y] -> *[x y]
	if len(e) == 2 then
		return nil
	end

	-- *[x y .z] -> *[*[x y] .z]
	if len(e) > 2 then
		local x, y, z = firstsecondrest(e)
		local rxy = reduce1(list { x, y }, depth + 1)
		if rxy == nil then
			return nil
		end

		return printReturn(reduce1(addStart(rxy, z), depth + 1))
	end

	-- *x -> *x
	print(`{start}! no reduction rule matched`)
	return nil
end

local tests: {
	{
		read eval: Thing,
		read res: Thing?,
	}
} = {
	{
		eval = list {},
	},
	{
		eval = num(1),
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
