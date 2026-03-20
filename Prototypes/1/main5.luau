--!strict

-- this prototype because Sets are hard to work with at a low level and lists seem more useful

type Num = {
	read type: "@",
	read value: number,
}
type Thing = List | Num
type List = {
	read type: "$",
	read things: { Thing },
}

local NUM: "@" = "@"
local LIST: "$" = "$"

local function serialise(t: Thing): string
	if t.type == NUM then
		return tostring(t.value)
	end

	local elements: { string } = {}
	for i, elem in t.things do
		elements[i] = serialise(elem)
	end
	-- table.sort(elements)
	return "{" .. table.concat(elements, " ") .. "}"
end

local function num(value: number): Num
	if value < 0 then
		error "Negative numbers are not supported at the moment"
	end
	if value % 1 ~= 0 then
		error "Non-integer numbers are not supported at the moment"
	end
	return table.freeze { type = NUM, value = value } :: Num
end

local function list(things: { Thing }): List
	return table.freeze { type = LIST, things = table.freeze(things) } :: List
end

local empty = list {}

local function deserialise(s: string): Thing
	if string.sub(s, 1, 1) ~= "{" then
		local n = tonumber(s)
		if n == nil then
			error(`Invalid number: {s}`)
		end
		return num(n)
	end

	local news = string.sub(s, 2, -2)
	local elements = {}

	local lastElem: { string } = {}
	local braceLevel = 0
	for i = 1, #news do
		local c = string.sub(news, i, i)
		if c == " " and braceLevel == 0 then
			if #lastElem > 0 then
				table.insert(elements, deserialise(table.concat(lastElem)))
				lastElem = {}
			end
			continue
		end

		if c == "{" then
			braceLevel += 1
		elseif c == "}" then
			braceLevel -= 1
		end
		table.insert(lastElem, c)
	end
	if #lastElem > 0 then
		table.insert(elements, deserialise(table.concat(lastElem)))
	end

	return list(elements)
end

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

local TRUE, FALSE = num(0), num(1) -- loobeans

local SIZE, PART, SUM, CHECK, TYPE, SPLIT = 1, 2, 3, 4, 5, 6

local function h_size(t: Thing): Num?
	if t.type ~= LIST then
		return nil
	end
	return num(len(t))
end

local function h_part(t: Thing): Thing?
	if t.type ~= LIST then
		return nil
	end

	local pn, pl = t.things[1], t.things[2]
	if pn.type ~= NUM then
		return nil
	end

	if pl.type ~= LIST then
		return nil
	end

	return pl.things[pn.value + 1] -- sorry, luau...
end

local function h_sum(t: Thing): Num?
	if t.type ~= LIST then
		return nil
	end

	local total = 0

	for _, e in t.things do
		if e.type ~= NUM then
			return nil
		end

		total += e.value
	end

	return num(total)
end

local function h_check(t: Thing): Num?
	if t.type ~= LIST then
		return nil
	end

	local prev: Thing?

	for _, e in t.things do
		if prev and not equal(prev, e) then
			return FALSE
		end

		prev = e
	end
	return TRUE
end

local function h_type(t: Thing): Num?
	return if t.type == NUM then TRUE else FALSE
end

-- *a
local function reduce1(e: Thing, depth: number): Thing?
	print(string.rep(" ", depth) .. "-", serialise(e))
	if e.type == NUM then
		return e -- *a:@ -> a
	end

	-- if len(e) == 0 then
	-- 	return e -- *{} -> {}
	-- end

	-- if len(e) == 1 then
	-- 	-- extract the single element
	-- 	-- kind of like a pin<>
	-- 	local only = e.things[1]
	-- 	return reduce1(only, depth + 1) -- *{a} -> *a
	-- end

	if len(e) ~= 2 then
		return nil
	end

	-- now we're talking
	-- the list needs to be {l:$ a2:$}
	local l, a2 = e.things[1], e.things[2]
	if l.type ~= LIST or len(l) ~= 2 then
		return nil
	end

	-- l needs to be {n:@ a}
	local n, a = l.things[1], l.things[2]
	if n.type ~= NUM then
		return nil
	end

	-- so the list is {{n:@ a} a2}

	-- print("Found num and list:", serialise(n), serialise(l))

	-- opcodes

	-- *{{SIZE a} b} -> size(*{b a})
	if n.value == SIZE then
		local rab = reduce1(list { a2, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_size(rab)
	end

	-- *{{PART a} b} -> part(*{b a})
	if n.value == PART then
		local rab = reduce1(list { a2, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_part(rab)
	end

	-- *{{SUM a} b} -> sum(*{b a})
	if n.value == SUM then
		local rab = reduce1(list { a2, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_sum(rab)
	end

	-- *{{CHECK a} b} -> check(*{b a})
	if n.value == CHECK then
		local rab = reduce1(list { a2, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_check(rab)
	end

	-- *{{TYPE a} b} -> type(*{b a})
	if n.value == TYPE then
		local rab = reduce1(list { a2, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_type(rab)
	end

	-- *{{SPLIT a} {b c}} -> *{*{b a} *{c a}}
	if n.value == SPLIT then
		if a2.type ~= LIST or len(a2) ~= 2 then
			return nil
		end

		local b, c = a2.things[1], a2.things[2]

		local rba = reduce1(list { b, a }, depth + 1)
		if rba == nil then
			return nil
		end

		local rca = reduce1(list { c, a }, depth + 1)
		if rca == nil then
			return nil
		end

		return reduce1(list { rba, rca }, depth + 1)
	end

	return nil
end

local function a_size(a: Thing, b: Thing): Thing
	return list { list { num(SIZE), a }, b }
end

local function a_part(a: Thing, b: Thing): Thing
	return list { list { num(PART), a }, b }
end

local function a_sum(a: Thing, b: Thing): Thing
	return list { list { num(SUM), a }, b }
end

local function a_check(a: Thing, b: Thing): Thing
	return list { list { num(CHECK), a }, b }
end

local function a_type(a: Thing, b: Thing): Thing
	return list { list { num(TYPE), a }, b }
end

local function a_split(a: Thing, b: Thing): Thing
	return list { list { num(SPLIT), a }, b }
end

local tests: {
	{
		eval: Thing,
		res: Thing?,
	}
} = {
	-- generic
	{
		eval = num(0),
		res = num(0),
	},
	{
		eval = empty,
	},
	{
		eval = list { num(1) },
	},
	{
		eval = list { empty, list { empty } },
	},
	{
		eval = list { empty, list { list { num(1) } } },
	},

	-- size
	{
		eval = a_size(num(0), num(0)),
	},
	{
		eval = a_size(empty, num(0)),
	},
	{
		eval = a_size(empty, empty),
	},
	{
		eval = a_size(list { num(0) }, empty),
	},
	{
		eval = a_size(empty, list { num(0) }),
	},
	{
		eval = a_size(empty, list { num(0), num(0) }),
	},
	{
		eval = a_size(empty, list { num(SIZE), num(0) }),
	},
}

-- test serialise and deserialise
for _, test in tests do
	for _, thing in { test.eval, test.res } do
		if thing == nil then
			continue
		end
		local s = serialise(thing)
		local d = deserialise(s)
		if not equal(thing, d) then
			print(`Serialization round-trip failed for {s}`)
			return
		end
	end
end

local function reduce(e: Thing): Thing?
	return reduce1(e, 0)
end

for _, test in tests do
	local rd = reduce(test.eval)
	local out
	if rd == nil then
		print "~~"
		print()
	else
		out = serialise(rd)
		print("=", out)
		print()
	end

	local expected = test.res and serialise(test.res)
	if out ~= expected then
		print(`Test failed: expected {expected}, got {out}`)
		break
	end
end
