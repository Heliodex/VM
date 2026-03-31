--!strict

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

local TRUE, FALSE = num(1), num(2) -- imagine loobeans but worse

local TAKE, PART, SIZE, SUM, CHECK, TYPE, SPLIT = 0, 1, 2, 3, 4, 5, 6

local function h_size(t: Thing): Num?
	print(`size({serialise(t)})`)
	if t.type ~= LIST then
		return nil
	end
	return num(len(t))
end

local function h_part(a: Thing, b: Thing): Thing?
	if a.type ~= NUM then
		return nil
	end

	if a.value == 0 then
		return b
	end

	if b.type ~= LIST then
		return nil
	end

	return b.things[a.value] -- sorry, luau...
end

local function h_sum(t: Thing): Num?
	print(`sum({serialise(t)})`)
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
	print(`check({serialise(t)})`)
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
	print(`type({serialise(t)})`)
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
	-- the list needs to be {a {n:@ b}}
	local a, l = e.things[1], e.things[2]
	if l.type ~= LIST or len(l) ~= 2 then
		return nil
	end

	local n, b = l.things[1], l.things[2]
	if n.type ~= NUM then
		return nil
	end

	-- opcodes

	-- *{a {TAKE b}} -> b
	if n.value == TAKE then
		return b
	end

	-- *{a {PART b}} -> part(b, a)
	if n.value == PART then
		return h_part(b, a)
	end

	-- *{a {SIZE b}} -> size(*{b a})
	if n.value == SIZE then
		local rab = reduce1(list { b, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_size(rab)
	end

	-- *{a {SUM b}} -> sum(*{b a})
	if n.value == SUM then
		local rab = reduce1(list { b, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_sum(rab)
	end

	-- *{a {CHECK b}} -> check(*{b a})
	if n.value == CHECK then
		local rab = reduce1(list { b, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_check(rab)
	end

	-- *{a {TYPE b}} -> type(*{b a})
	if n.value == TYPE then
		local rab = reduce1(list { b, a }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_type(rab)
	end

	-- *{a {SPLIT {b c}}} -> *{*{a b} *{a c}}
	if n.value == SPLIT then
		if b.type ~= LIST or len(b) ~= 2 then
			return nil
		end

		local b2, c2 = b.things[1], b.things[2]

		local rba = reduce1(list { a, b2 }, depth + 1)
		if rba == nil then
			return nil
		end

		local rca = reduce1(list { a, c2 }, depth + 1)
		if rca == nil then
			return nil
		end

		return reduce1(list { rba, rca }, depth + 1)
	end

	return nil
end

local function a_take(a: Thing, b: Thing): Thing
	return list { a, list { num(TAKE), b } }
end

local function a_size(a: Thing, b: Thing): Thing
	return list { a, list { num(SIZE), b } }
end

local function a_part(a: Thing, b: Thing): Thing
	return list { a, list { num(PART), b } }
end

local function a_sum(a: Thing, b: Thing): Thing
	return list { a, list { num(SUM), b } }
end

local function a_check(a: Thing, b: Thing): Thing
	return list { a, list { num(CHECK), b } }
end

local function a_type(a: Thing, b: Thing): Thing
	return list { a, list { num(TYPE), b } }
end

local function a_split(a: Thing, b: Thing): Thing
	return list { a, list { num(SPLIT), b } }
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
	{
		eval = list { list { num(0) }, num(0) },
	},
	{
		eval = list { list { num(0), num(0) } },
	},

	-- take
	{
		eval = a_take(empty, num(0)),
		res = num(0),
	},
	{
		eval = a_take(num(1), num(0)),
		res = num(0),
	},
	{
		eval = a_take(num(1), empty),
		res = empty,
	},
	{
		eval = a_take(num(1), list { num(0) }),
		res = list { num(0) },
	},

	-- part
	{
		eval = a_part(num(1), num(0)),
		res = num(1),
	},
	{
		eval = a_part(num(1), num(1)),
	},
	{
		eval = a_part(empty, num(0)),
		res = empty,
	},
	{
		eval = a_part(empty, num(1)),
	},
	{
		eval = a_part(list { num(1) }, num(1)),
		res = num(1),
	},
	{
		eval = a_part(list { num(1), num(4), num(9), num(16) }, num(3)),
		res = num(9),
	},
	{
		eval = a_part(list { empty, list { num(5) } }, num(2)),
		res = list { num(5) },
	},

	-- the basis of if else, I guess
	{
		eval = a_part(list { num(1), num(2) }, TRUE),
		res = num(1),
	},
	{
		eval = a_part(list { num(1), num(2) }, FALSE),
		res = num(2),
	},
	{
		eval = a_part(list { num(1), num(2) }, num(3)),
	},

	-- size
	{
		eval = a_size(list { num(TAKE), empty }, num(1)),
		res = num(0),
	},
	{
		eval = a_size(list { num(TAKE), list { num(0) } }, num(0)),
		res = num(1),
	},
	{
		eval = a_size(
			list { num(TAKE), list { num(1), num(2), num(3) } },
			num(0)
		),
		res = num(3),
	},
	{
		eval = a_size(
			list { num(TAKE), list { empty, num(1), empty } },
			num(0)
		),
		res = num(3),
	},
	{
		eval = a_size(list { num(TAKE), list { empty, empty } }, num(0)),
		res = num(2),
	},

	-- sum
	{
		eval = a_sum(list { num(TAKE), num(0) }, num(0)),
	},
	{
		eval = a_sum(list { num(TAKE), empty }, num(0)),
		res = num(0),
	},
	{
		eval = a_sum(list { num(TAKE), list { empty } }, num(0)),
	},
	{
		eval = a_sum(list { num(TAKE), list { num(0) } }, num(0)),
		res = num(0),
	},
	{
		eval = a_sum(
			list { num(TAKE), list { num(0), num(0), num(0) } },
			num(0)
		),
		res = num(0),
	},
	{
		eval = a_sum(
			list { num(TAKE), list { num(1), num(2), num(3) } },
			num(0)
		),
		res = num(6),
	},
	{
		eval = a_sum(
			list { num(TAKE), list { num(1), num(2), empty } },
			num(0)
		),
	},

	-- check
	{
		eval = a_check(list { num(TAKE), num(0) }, num(0)),
	},
	{
		eval = a_check(list { num(TAKE), empty }, num(0)),
		res = TRUE,
	},
	{
		eval = a_check(list { num(TAKE), list { num(0) } }, num(0)),
		res = TRUE,
	},
	{
		eval = a_check(list { num(TAKE), list { num(0), num(0) } }, num(0)),
		res = TRUE,
	},
	{
		eval = a_check(list { num(TAKE), list { num(0), num(1) } }, num(0)),
		res = FALSE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { num(0), num(0), num(0) } },
			num(0)
		),
		res = TRUE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { num(0), num(1), num(0) } },
			num(0)
		),
		res = FALSE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { num(0), empty, num(0) } },
			num(0)
		),
		res = FALSE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { empty, list { empty } } },
			num(0)
		),
		res = FALSE,
	},
	{
		eval = a_check(list { num(TAKE), list { empty, empty } }, num(0)),
		res = TRUE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { list { num(0) }, list { num(0) } } },
			num(0)
		),
		res = TRUE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { list { num(0) }, list { num(0) } } },
			num(0)
		),
		res = TRUE,
	},
	{
		eval = a_check(
			list { num(TAKE), list { list { num(0) }, list { num(1) } } },
			num(0)
		),
		res = FALSE,
	},

	-- type
	{
		eval = a_type(list { num(TAKE), num(0) }, num(0)),
		res = TRUE,
	},
	{
		eval = a_type(list { num(TAKE), num(1) }, num(0)),
		res = TRUE,
	},
	{
		eval = a_type(list { num(TAKE), empty }, num(0)),
		res = FALSE,
	},
	{
		eval = a_type(list { num(TAKE), list { num(1) } }, num(0)),
		res = FALSE,
	},

	-- split
	-- ok moment of truth
	{
		eval = a_split(num(0), num(0)),
	},
	{
		eval = a_split(num(0), empty),
	},
	{
		eval = a_split(empty, num(0)),
	},
	{
		eval = a_split(list { num(0) }, num(0)),
	},
	{
		eval = a_split(list { num(0), num(0), num(0) }, num(0)),
	},
	{
		eval = a_split(list { num(TAKE), num(0) }, num(0)),
	},

	{
		eval = a_split(
			list { list { num(TAKE), num(2) }, num(0) },
			list {
				list { num(PART), num(2) },
				list { num(PART), num(1) },
			}
		),
		res = num(2),
	},
	--[=[
		*[a [2 [b c]]]          *[*[a b] *[a c]]
		*[a=[1 2] [2 b=[0 2] c=[1 [0 1]]]
		*[[1 2] [2 [[0 2] [1 [0 1]]]]

		*[*[[1 2] [0 2]] *[[1 2] [1 [0 1]]]]
			*[[1 2] [0 2]]
				1
			*[[1 2] [1 [0 1]]]
				[0 1]
		
		*[1 [0 1]]
		1

		*{a {SPLIT {b c}}} -> *{*{a b} *{a c}}
		*{a={{1} {2}} {SPLIT {b c}}}

		*{*{a={{1} {2}} {PART 0}}} *{a={{1} {2}} {TAKE {PART 0}}}}
			*{a={{1} {2}} {PART 0}}
				{1}
			*{a={{1} {2}} {TAKE {PART 0}}}
				{PART 0}
		
		*{{1} {PART 0}}
		1
	]=]
	{
		eval = a_split(
			list { num(1), num(2) },
			list {
				list { num(PART), num(1) },
				list { num(TAKE), list { num(PART), num(0) } },
			}
		),
		res = num(1),
	},
	{
		eval = a_split(
			list { num(1), num(2) },
			list {
				list { num(PART), num(0) },
				list { num(TAKE), list { num(PART), num(1) } },
			}
		),
		res = num(1),
	},
	{
		eval = a_split(
			list { num(1), num(2) },
			list {
				list { num(PART), num(0) },
				list { num(TAKE), list { num(PART), num(0) } },
			}
		),
		res = list { num(1), num(2) },
	},
	--[=[
		If *[a b] equals 0 return *[a c]
		If *[a b] equals 1 return *[a d]
		Otherwise: crash

		*[a 6 b c d]     *[a *[[c d] 0 *[[2 3] 0 *[a 4 4 b]]]]
		*[a 6 b c d]     *[a 2 [0 1] 2 [1 c d] [1 0] 2 [1 2 3] [1 0] 4 4 b]

		*[a *[[c d] 0 *[[2 3] 0 *[a 4 4 b]]]]
			*[[c d] 0 *[[2 3] 0 *[a 4 4 b]]]
				*[[2 3] 0 *[a 4 4 b]]
					*[a 4 4 b]
		
		{a {IF {b c d}}} -> part(*{a b}, {*{a c} *{a d}})
		{a {IF {b c d}}} -> *{{*{a c} *{a d}} {PART *{a b}}}

		*[a 2 [0 1] 2 [1 c d] [1 0] 2 [1 2 3] [1 0] 4 4 b]
		*[a [2 [[0 1] [2 [[1 [c d]] [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]]]]
		*[*[a [0 1]] *[a [2 [[1 [c d]] [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]]]
			*[a [0 1]]
			*[a [2 [[1 [c d]] [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]]
	]=]
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
