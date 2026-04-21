--!strict

type Num = {
	read type: "@",
	read value: number,
	read op: boolean?,
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

local function num(value: number, op: boolean?): Num
	if value < 0 then
		error "Negative numbers are not supported at the moment"
	end
	if value % 1 ~= 0 then
		error "Non-integer numbers are not supported at the moment"
	end
	return table.freeze { type = NUM, value = value, op = op } :: Num
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

local TRUE, FALSE = num(0), num(1) -- imagine loobeans but if they were loobeans

local function op(n: number)
	return num(n, true)
end

local TAKE, PART, SIZE, SUM, CHECK, TYPE, SPLIT =
	op(0), op(1), op(2), op(3), op(4), op(5), op(6)

local function h_size(t: Thing): Num?
	print(`size({serialise(t)})`)
	if t.type ~= LIST then
		return nil
	end
	return num(len(t))
end

local function h_part(a: Thing, b: Thing): Thing?
	if b.type ~= NUM then
		return nil
	end

	if b.value == 0 then
		return a
	end

	if a.type ~= LIST then
		return nil
	end

	return a.things[b.value] -- YEAHH!!! WOOOO00T!! THANK YOU LUAU!!!!!!!!
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
	if n.type == LIST and len(n) == 2 then
		-- autocons
		local b2, c2 = n.things[1], n.things[2]

		local rabc = reduce1(list { a, list { b2, c2 } }, depth + 1)
		if rabc == nil then
			return nil
		end

		local rad = reduce1(list { a, b }, depth + 1)
		if rad == nil then
			return nil
		end

		return list { rabc, rad } -- *{a {{b c} d}} -> {*{a {b c}} *{a d}} (no *)
	end

	if n.type ~= NUM then
		return nil
	end

	-- opcodes

	-- *{a {TAKE b}} -> b
	if equal(n, TAKE) then
		return b
	end

	-- *{a {PART b}} -> part(a, b)
	if equal(n, PART) then
		return h_part(a, b)
	end

	-- *{a {SIZE b}} -> size(*{a b})
	if equal(n, SIZE) then
		local rab = reduce1(list { a, b }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_size(rab)
	end

	-- *{a {SUM b}} -> sum(*{a b})
	if equal(n, SUM) then
		local rab = reduce1(list { a, b }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_sum(rab)
	end

	-- *{a {CHECK b}} -> check(*{a b})
	if equal(n, CHECK) then
		local rab = reduce1(list { a, b }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_check(rab)
	end

	-- *{a {TYPE b}} -> type(*{a b})
	if equal(n, TYPE) then
		local rab = reduce1(list { a, b }, depth + 1)
		if rab == nil then
			return nil
		end
		return h_type(rab)
	end

	-- *{a {SPLIT {b c}}} -> *{*{a b} *{a c}}
	if equal(n, SPLIT) then
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
	return list { a, list { TAKE, b } }
end

local function a_size(a: Thing, b: Thing): Thing
	return list { a, list { SIZE, b } }
end

local function a_part(a: Thing, b: Thing): Thing
	return list { a, list { PART, b } }
end

local function a_sum(a: Thing, b: Thing): Thing
	return list { a, list { SUM, b } }
end

local function a_check(a: Thing, b: Thing): Thing
	return list { a, list { CHECK, b } }
end

local function a_type(a: Thing, b: Thing): Thing
	return list { a, list { TYPE, b } }
end

local function a_split(a: Thing, b: Thing): Thing
	return list { a, list { SPLIT, b } }
end

local function a_if(a: Thing, b: Thing, c: Thing, d: Thing): Thing
	--[[
		{a {SPLIT {{PART 0} {SPLIT {{TAKE {c d}} {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}}}}
		a_split(a, {{PART 0} {SPLIT {{TAKE {c d}} {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}})
		a_split(a, a_split({PART 0}, {{TAKE {c d}} {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}))
		a_split(a, a_split({PART 0}, {{TAKE {c d}} a_split({TAKE 0}, {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}})}))
		a_split(a, a_split({PART 0}, {{TAKE {c d}} a_split({TAKE 0}, {{TAKE {1 2}} a_sum({TAKE PART}, {{TAKE X} b})})}))
	]]
	return a_split(
		a,
		a_split(
			list { PART, num(0) },
			list {
				list { TAKE, list { c, d } },
				a_split(
					list { TAKE, num(0) },
					list {
						list { TAKE, list { num(1), num(2) } },
						a_sum(
							list { TAKE, PART },
							list {
								list {
									TAKE,
									num(1) --[[X]],
								},
								b,
							}
						),
					}
				),
			}
		)
	)
end

local function a_if2(a: Thing, b: Thing, c: Thing, d: Thing): Thing
	--[[
		{a {SPLIT {{PART 0} {SPLIT {{TAKE {c d}} {{TAKE 0} {SUM {{TAKE X} b}}}}}}}}
		a_split(a, {{PART 0} {SPLIT {{TAKE {c d}} {{TAKE 0} {SUM {{TAKE X} b}}}}}})
		a_split(a, split({PART 0}, {{TAKE {c d}} {{TAKE 0} {SUM {{TAKE X} b}}}}))
		a_split(a, split({PART 0}, {{TAKE {c d}} a_sum({TAKE 0}, {{TAKE X} b})}))
	]]
	return a_split(
		a,
		a_split(
			list { PART, num(0) },
			list {
				list { TAKE, list { c, d } },
				a_sum(
					list { TAKE, num(0) },
					list {
						list {
							TAKE,
							num(1) --[[X]],
						},
						b,
					}
				),
			}
		)
	)
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

	-- autocons
	{
		eval = list {
			num(0),
			list { list { TAKE, num(1) }, list { TAKE, num(2) } },
		},
		res = list { num(1), num(2) },
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

	{
		eval = a_part(list { num(1), num(2) }, TRUE),
		res = list { num(1), num(2) },
	},
	{
		eval = a_part(list { num(1), num(2) }, FALSE),
		res = num(1),
	},
	{
		eval = a_part(list { num(1), num(2) }, num(2)),
		res = num(2),
	},
	{
		eval = a_part(list { num(1), num(2) }, num(3)),
	},

	-- size
	{
		eval = a_size(num(1), list { TAKE, empty }),
		res = num(0),
	},
	{
		eval = a_size(num(0), list { TAKE, list { num(0) } }),
		res = num(1),
	},
	{
		eval = a_size(num(0), list { TAKE, list { num(1), num(2), num(3) } }),
		res = num(3),
	},
	{
		eval = a_size(num(0), list { TAKE, list { empty, num(1), empty } }),
		res = num(3),
	},
	{
		eval = a_size(num(0), list { TAKE, list { empty, empty } }),
		res = num(2),
	},

	-- sum
	{
		eval = a_sum(num(0), list { TAKE, num(0) }),
	},
	{
		eval = a_sum(num(0), list { TAKE, empty }),
		res = num(0),
	},
	{
		eval = a_sum(num(0), list { TAKE, list { empty } }),
	},
	{
		eval = a_sum(num(0), list { TAKE, list { num(0) } }),
		res = num(0),
	},
	{
		eval = a_sum(num(0), list { TAKE, list { num(0), num(0), num(0) } }),
		res = num(0),
	},
	{
		eval = a_sum(num(0), list { TAKE, list { num(1), num(2), num(3) } }),
		res = num(6),
	},
	{
		eval = a_sum(num(0), list { TAKE, list { num(1), num(2), empty } }),
	},
	{
		eval = a_sum(list { num(1), num(2), num(3) }, list { PART, num(0) }),
		res = num(6),
	},
	{
		eval = a_sum(
			list { num(0), list { num(1), num(2) }, list { PART, num(0) } },
			list {
				SPLIT,
				list {
					list { PART, num(2) },
					list { PART, num(3) },
				},
			}
		),
		res = num(3),
	},

	-- check
	{
		eval = a_check(num(0), list { TAKE, num(0) }),
	},
	{
		eval = a_check(num(0), list { TAKE, empty }),
		res = TRUE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { num(0) } }),
		res = TRUE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { num(0), num(0) } }),
		res = TRUE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { num(0), num(1) } }),
		res = FALSE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { num(0), num(0), num(0) } }),
		res = TRUE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { num(0), num(1), num(0) } }),
		res = FALSE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { num(0), empty, num(0) } }),
		res = FALSE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { empty, list { empty } } }),
		res = FALSE,
	},
	{
		eval = a_check(num(0), list { TAKE, list { empty, empty } }),
		res = TRUE,
	},
	{
		eval = a_check(
			num(0),
			list { TAKE, list { list { num(0) }, list { num(0) } } }
		),
		res = TRUE,
	},
	{
		eval = a_check(
			num(0),
			list { TAKE, list { list { num(0) }, list { num(0) } } }
		),
		res = TRUE,
	},
	{
		eval = a_check(
			num(0),
			list { TAKE, list { list { num(0) }, list { num(1) } } }
		),
		res = FALSE,
	},

	-- type
	{
		eval = a_type(num(0), list { TAKE, num(0) }),
		res = TRUE,
	},
	{
		eval = a_type(num(0), list { TAKE, num(1) }),
		res = TRUE,
	},
	{
		eval = a_type(num(0), list { TAKE, empty }),
		res = FALSE,
	},
	{
		eval = a_type(num(0), list { TAKE, list { num(1) } }),
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
		eval = a_split(list { TAKE, num(0) }, num(0)),
	},

	{
		eval = a_split(
			list { list { TAKE, num(2) }, num(0) },
			list {
				list { PART, num(2) },
				list { PART, num(1) },
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
				list { PART, num(1) },
				list { TAKE, list { PART, num(0) } },
			}
		),
		res = num(1),
	},
	{
		eval = a_split(
			list { num(1), num(2) },
			list {
				list { PART, num(0) },
				list { TAKE, list { PART, num(1) } },
			}
		),
		res = num(1),
	},
	{
		eval = a_split(
			list { num(1), num(2) },
			list {
				list { PART, num(0) },
				list { TAKE, list { PART, num(0) } },
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
				a
		*[a *[a [2 [[1 [c d]] [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]]]
			*[a [2 [b=[1 [c d]] c=[[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]]
			*[*[a [1 [c d]]] *[a [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]
				*[a [1 [c d]]]
					[c d]
			*[[c d] *[a [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]
				*[a [[b=1 c=0] d=[2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]
				[*[a [1 0]] *[a [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]
					*[a [1 0]]
						0
				[0 *[a [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]
					*[a [2 [b=[1 [2 3]] c=[[1 0] [4 [4 b]]]]]]
					*[*[a [1 [2 3]]] *[a [[1 0] [4 [4 b]]]]]
						*[a [1 [2 3]]]
							[2 3]
					*[[2 3] *[a [[1 0] [4 [4 b]]]]]
						*[a [[b=1 c=0] d=[4 [4 b]]]]
						[*[a 1 0] *[a [4 [4 b]]]]
							*[a 1 0]
								0
						[0 *[a [4 [4 b]]]]
							*[a [4 [4 b]]]
							+*[a [4 b]]
								*[a 4 b]
								+*[a b]
							++*[a b]
						[0 ++*[a b]]
					*[[2 3] [0 ++*[a b]]]
					/[++*[a b] [2 3]]
				[0 /[++*[a b] [2 3]]]
			*[[c d] [0 /[++*[a b] [2 3]]]]
			/[/[++*[a b] [2 3]] [c d]]
		*[a /[/[++*[a b] [2 3]] [c d]]]

		*{*{a {c d}} {PART *{1 {SUM *{a b}}}}}
			{PART *{1 {SUM *{a b}}}}
				*{1 {SUM *{a b}}}
				sum({*{a b} 1})
			{PART sum({*{a b} 1})}
		*{*{a {c d}} {PART sum({*{a b} 1})}}
			*{a {c d}}
			{*{a c} *{a d}}
		*{{*{a c} *{a d}} {PART sum({*{a b} 1})}}
		part(sum({*{a b} 1}), {*{a c} *{a d}})
		part(*{a b}+1, {*{a c} *{a d}})


		*[a [2 [[PART 0] [2 [[1 [c d]] [[1 0] [2 [[1 [2 3]] [[1 0] [4 [4 b]]]]]]]]]]]

		*{a=a {SPLIT {b={PART 0} c={SPLIT {{TAKE {c d}} {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}}}}
		*{*{a {PART 0}} *{a {2 {{TAKE {c d}} {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}}}
			*{a {PART 0}}
				a
		*{a *{a {SPLIT {{TAKE {c d}} {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}}}
			*{a {SPLIT {b={TAKE {c d}} c={{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}}
			*{*{a {TAKE {c d}}} *{a {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}
				*{a {TAKE {c d}}}
					{c d}
			*{{c d} *{a {{TAKE 0} {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}}
				*{a {{b=TAKE c=0} d={SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}
				{*{a {TAKE 0}} *{a {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}
					*{a {TAKE 0}}
						0
				{0 *{a {SPLIT {{TAKE {1 2}} {{TAKE PART} {SUM {{TAKE X} b}}}}}}}
					*{a {SPLIT {b={TAKE {1 2}} c={{TAKE PART} {SUM {{TAKE X} b}}}}}}
					*{*{a {TAKE {1 2}}} *{a {{TAKE PART} {SUM {{TAKE X} b}}}}}
						*{a {TAKE {1 2}}}
							{1 2}
					*{{1 2} *{a {{TAKE PART} {SUM {{TAKE X} b}}}}}
						*{a {{b=TAKE c=PART} d={SUM {{TAKE X} b}}}}
						{*{a TAKE PART} *{a {SUM {{TAKE X} b}}}}
							*{a TAKE PART}
								PART
						{PART *{a {SUM {{TAKE X} b}}}}
							*{a {SUM {{TAKE X} b}}}
							sum(*{a {{TAKE X} b}})
								*{a {{TAKE X} b}}
								{*{a {TAKE X}} *{a b}}
									*{a {TAKE X}}
										X
								{X *{a b}}
							sum({X *{a b}})
						{PART sum({X *{a b}})}
					*{{1 2} {PART sum({X *{a b}})}}
					part({1 2}, sum({X *{a b}}))
				{0 part({1 2}, sum({X *{a b}}))}
			*{{c d} {0 part({1 2}, sum({X *{a b}}))}}
			part({c d}, part({1 2}, sum({X *{a b}})))
		*{a part({c d}, part({1 2}, sum({X *{a b}})))}
	]=]
	{
		eval = a_if(num(100), list { TAKE, TRUE }, num(300), num(400)),
	},
	--[=[
		*{a=a {SPLIT {b={PART 0} c={SPLIT {{TAKE {c d}} {{TAKE 0} {SUM {{TAKE X} b}}}}}}}}
		*{*{a {PART 0}} *{a {2 {{TAKE {c d}} {{TAKE 0} {SUM {{TAKE X} b}}}}}}}
			*{a {PART 0}}
				a
		*{a *{a {SPLIT {{TAKE {c d}} {{TAKE 0} {SUM {{TAKE X} b}}}}}}}
			*{a {SPLIT {b={TAKE {c d}} c={{TAKE 0} {SUM {{TAKE X} b}}}}}}
			*{*{a {TAKE {c d}}} *{a {{TAKE 0} {SUM {{TAKE X} b}}}}}
				*{a {TAKE {c d}}}
					{c d}
			*{{c d} *{a {{TAKE 0} {SUM {{TAKE X} b}}}}}
				*{a {{b=TAKE c=0} d={SUM {{TAKE X} b}}}}
				{*{a {TAKE 0}} *{a {SUM {{TAKE X} b}}}}
					*{a {TAKE 0}}
						0
				{0 *{a {SUM {{TAKE X} b}}}}
					*{a {SUM {{TAKE X} b}}}
					sum(*{a {{TAKE X} b}})
						*{a {{TAKE X} b}}
						{*{a {TAKE X}} *{a b}}
							*{a {TAKE X}}
								X
						{X *{a b}}
					sum({X *{a b}})
				{0 sum({X *{a b}})}
			*{{c d} {0 sum({X *{a b}})}}
			part({c d}, sum({X *{a b}}))
		*{a part({c d}, sum({X *{a b}}))}

		{100 {6 {{1 0} {6 {{0 {300 400}} {{0 0} {3 {{0 1} {0 0}}}}}}}}}
		{100 {SPLIT {{PART 0} {SPLIT {{TAKE {300 400}} {{TAKE 0} {SUM {{TAKE 1} {TAKE TRUE}}}}}}}}}
	]=]
	{
		eval = a_if2(num(100), list { TAKE, TRUE }, num(300), num(400)),
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
