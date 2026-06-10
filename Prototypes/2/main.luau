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
		print(`{start}! evaluate number`)
		return nil -- *x -> *x
	end

	if len(e) ~= 2 then
		print(`{start}! list is not length 2`)
		return nil -- *x -> *x
	end

	local a, b = e.things[1], e.things[2]

	if equal(b, SUM) then
		-- *[[] SUM] -> 0
		-- *[[[.x] .y] SUM] -> *[[x .y] SUM]
		-- *[[x .y] SUM] -> x + *[y SUM]
	end

	if equal(b, REST) then
		-- *[[x .y] REST] -> y
	end

	if equal(b, PART) then
		-- *[x [PART 0]] -> x
		-- *[[x .y] [PART 1]] -> x
		-- *[x [PART [.y]] -> *[x [PART y]]
		-- *[[x .y] [PART z]] -> *[y [PART z - 1]]
	end

	if b.type == LIST and len(b) == 2 and equal(b.things[1], START) then
		-- *[[.x] [START y]] -> [y .x]
	end

	if b.type == LIST and len(b) == 2 and equal(b.things[1], END) then
		-- *[[.x] [END y]] -> [.x y]
	end

	if equal(b, TYPE) then
		-- *[[.x] TYPE] -> 0
		-- *[x TYPE] -> 1
	end

	if equal(b, CHECK) then
		-- *[[] CHECK] -> 0
		-- *[[x] CHECK] -> 0
		-- *[[x x .y] CHECK] -> *[[x .y] CHECK]
		-- *[[x y .z] CHECK] -> 1
	end

	if equal(b, LEN) then
		-- *[[] LEN] -> 0
		-- *[[x] LEN] -> 1
		-- *[[x .y] LEN] -> 1 + *[.y LEN]
	end

	if equal(b, SPLIT) then
		-- *[[x y z] SPLIT] -> *[*[x y] *[x z]]
	end

	if b.type == LIST and len(b) == 3 and equal(b.things[1], IF) then
		-- *[0 [IF y z]] -> y
		-- *[1 [IF y z]] -> z
	end

	print(`{start}! no reduction rule matched`)
	return nil -- *x -> *x
end

local tests: {
	{
		read eval: Thing,
		read res: Thing?,
	}
} = {}

local function reduce(e: Thing): Thing?
	return reduce1(e, 0)
end

for i, test in tests do
	if i ~= #tests then
		continue
	end

	local rd = reduce(test.eval)
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
