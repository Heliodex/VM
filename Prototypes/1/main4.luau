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

local function size(s: List): number
	return #s.things
end

local TRUE, FALSE = num(0), num(1) -- loobeans

local SIZE, TAKE, SUM, CHECK, TYPE, SPLIT = 1, 2, 3, 4, 5, 6

local function reduce1(e: Thing, depth: number): Thing?
	print(string.rep(" ", depth) .. "-", serialise(e))
	if e.type == NUM then
		return e -- *a:@ -> a
	end

	-- if size(e) == 0 then
	-- 	return e -- *{} -> {}
	-- end

	-- if size(e) == 1 then
	-- 	-- extract the single element
	-- 	-- kind of like a pin<>
	-- 	local only = e.things[1]
	-- 	return reduce1(only, depth + 1) -- *{a} -> *a
	-- end

	if size(e) ~= 2 then
		return nil
	end

	-- now we're talking
	-- the list needs to be {n:@ l:$}
	local pn, pl = e.things[1], e.things[2]

	if pn.type ~= NUM then
		return nil
	end
	local n: Num = pn

	if pl.type ~= LIST then
		return nil
	end
	local l: List = pl

	-- print("Found num and list:", serialise(n), serialise(l))

	-- opcodes

	-- size
	if n.value == SIZE then
		return num(size(l)) -- *{SIZE a:$} -> size(a)
	end

	-- take
	if n.value == TAKE then
		if size(l) ~= 2 then
			return nil
		end

		-- l needs to be {tn:@ tl:$}
		local ptn, ptl = l.things[1], l.things[2]
		if ptn.type ~= NUM then
			return nil
		end
		local tn: Num = ptn

		if ptl.type ~= LIST then
			return nil
		end
		local tl: List = ptl

		local v = tl.things[tn.value + 1] -- sorry, luau...
		if not v then
			return nil -- necessary?
		end
		return v -- *{TAKE {a:@ b:$}} -> a[b]
	end

	-- sum
	if n.value == SUM then
		local total = 0

		for _, e in l.things do
			local re = reduce1(e, depth + 1)
			if not re or re.type ~= NUM then
				return nil
			end

			total += re.value
		end
		return num(total) -- *{SUM {...a:$} -> sum(...*a)}
	end

	-- check
	if n.value == CHECK then
		local prev: Thing?
		-- print "Comparing:"

		for i, e in l.things do
			local re = reduce1(e, depth + 1)
			if not re then
				return nil
			end

			-- print(
			-- 	if prev then serialise(prev) else "nil",
			-- 	serialise(re),
			-- 	if prev then equal(prev, re) else "nil"
			-- )
			if prev and not equal(prev, re) then
				return FALSE
			end

			prev = re
		end
		return TRUE
	end

	-- type
	if n.value == TYPE then
		local rv = reduce1(l, depth + 1)
		if not rv then
			return nil
		end

		return if rv.type == NUM then TRUE else FALSE
		-- *{TYPE a:$} -> TRUE where *a:@
		-- *{TYPE a:$} -> FALSE where *a:$
	end

	-- split
	if n.value == SPLIT then
		if size(l) ~= 2 then
			return nil
		end

		-- l needs to be {tn:@ tl:$}
		local ptn, ptl = l.things[1], l.things[2]
		if ptn.type ~= NUM then
			return nil
		end
		local tn: Num = ptn

		if ptl.type ~= LIST then
			return nil
		end
		local tl: List = ptl

		local insts = {}

		for _, e in tl.things do
			local rv = reduce1(list { tn, e }, depth + 1)
			if not rv then
				return nil
			end

			table.insert(insts, rv)
		end

		return list(insts) -- *{SPLIT {a:@ b:$}} -> {*{a:@ b[1]} *{a:@ b[2]} ...}}
	end

	return nil
end

local function a_size(a: Thing): Thing
	return list { num(SIZE), a }
end

local function a_take(a: Thing): Thing
	return list { num(TAKE), a }
end

local function a_sum(a: Thing): Thing
	return list { num(SUM), a }
end

local function a_check(a: Thing): Thing
	return list { num(CHECK), a }
end

local function a_type(a: Thing): Thing
	return list { num(TYPE), a }
end

local function a_split(a: Thing): Thing
	return list { num(SPLIT), a }
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
		eval = a_size(num(0)),
	},
	{
		eval = a_size(empty),
		res = num(0),
	},
	{
		eval = a_size(list { num(1) }),
		res = num(1),
	},
	{
		eval = a_size(list { empty, num(1), empty }),
		res = num(3),
	},
	{
		eval = a_size(list { empty, empty }),
		res = num(2),
	},

	-- take
	{
		eval = a_take(num(0)),
	},
	{
		eval = a_take(list { num(5) }),
	},
	{ -- take 5
		eval = a_take(list { num(0), list { num(5) } }),
		res = num(5),
	},

	-- sum
	{
		eval = a_sum(num(0)),
	},
	{
		eval = a_sum(empty),
		res = num(0),
	},
	{
		eval = a_sum(list { num(0) }),
		res = num(0),
	},
	{
		eval = a_sum(list { num(0), num(0), num(0) }),
		res = num(0),
	},
	{
		eval = a_sum(list { num(1), num(2), num(3) }),
		res = num(6),
	},
	{
		eval = a_sum(list {
			num(1),
			num(2),
			a_take(list { num(0), list { num(5) } }),
		}),
		res = num(8),
	},
	{
		eval = a_sum(list {
			num(1),
			num(2),
			a_sum(list { num(1), num(2), num(3) }),
		}),
		res = num(9),
	},
	{
		eval = a_sum(list {
			num(1),
			num(2),
			a_sum(num(0)),
		}),
	},

	-- check
	{
		eval = a_check(num(0)),
	},
	{
		eval = a_check(empty),
		res = TRUE,
	},
	{
		eval = a_check(list { num(0) }),
		res = TRUE,
	},
	{
		eval = a_check(list { num(0), num(0), num(0) }),
		res = TRUE,
	},
	{
		eval = a_check(list { num(0), num(1), num(0) }),
		res = FALSE,
	},
	{
		eval = a_check(
			list { num(0), a_take(list { num(0), list { empty } }) }
		),
		res = FALSE,
	},
	{
		eval = a_check(list {
			a_take(list { num(0), list { empty } }),
			a_take(list { num(0), list { empty } }),
			a_take(list { num(0), list { empty } }),
		}),
		res = TRUE,
	},
	{
		eval = a_check(list {
			a_take(list { num(0), list { num(1) } }),
			a_take(list { num(0), list { num(1) } }),
		}),
		res = TRUE,
	},
	{
		eval = a_check(list {
			a_take(list { num(0), list { num(2), num(1) } }),
			a_take(list { num(0), list { num(2), num(2) } }),
		}),
		res = TRUE,
	},
	{
		eval = a_check(list {
			a_take(list { num(0), list { list { num(2), num(1) } } }),
			a_take(list { num(0), list { list { num(2), num(1) } } }),
		}),
		res = TRUE,
	},
	{
		eval = a_check(list {
			a_take(list { num(0), list { list { num(2), num(1) } } }),
			a_take(list { num(0), list { list { num(2), num(2) } } }),
		}),
		res = FALSE,
	},

	-- type
	{
		eval = a_type(empty),
	},
	{
		eval = a_type(a_take(list { num(0), list { num(0) } })),
		res = TRUE,
	},
	{
		eval = a_type(a_take(list { num(0), list { empty } })),
		res = FALSE,
	},
	{
		eval = a_type(
			a_take(list { num(0), list { list { num(1), num(2) } } })
		),
		res = FALSE,
	},

	{
		eval = a_check(list {
			a_type(a_take(list { num(0), list { list { num(0) } } })),
			a_type(a_take(list { num(0), list { list { empty } } })),
			a_type(a_take(list { num(0), list { list { num(1), num(2) } } })),
		}),
		res = TRUE,
	},

	-- split
	{
		eval = a_split(num(0)),
	},
	{
		eval = a_split(empty),
	},
	{
		eval = a_split(list { num(0), empty }),
		res = list {},
	},
	{
		eval = a_split(a_size(list { empty })),
		res = list { num(0) },
	},
	{
		eval = a_split(a_size(list {
			list { num(1) },
			list { num(2), num(3) },
			list { num(4), num(5), num(6) },
		})),
		res = list { num(1), num(2), num(3) },
	},
	{
		eval = a_split(a_sum(list {
			list { num(1) },
			list { num(2), num(3) },
			list { num(4), num(5), num(6) },
		})),
		res = list { num(1), num(5), num(15) },
	},
	{
		eval = a_split(a_check(list {
			empty,
			list { num(0) },
			list { num(0), num(0), num(0) },
			list { num(0), num(1), num(0) },

			list { num(0), a_take(list { num(0), list { empty } }) },
			list {
				a_take(list { num(0), list { empty } }),
				a_take(list { num(0), list { empty } }),
				a_take(list { num(0), list { empty } }),
			},
			list {
				a_take(list { num(0), list { num(1), num(2) } }),
				a_take(list { num(0), list { num(1), num(2) } }),
			},
			list {
				a_take(list { num(0), list { num(2), num(1) } }),
				a_take(list { num(0), list { num(1), num(2) } }),
			},
		})),
		res = list { TRUE, TRUE, TRUE, FALSE, FALSE, TRUE, TRUE, FALSE },
	},
	{
		eval = a_split(a_check(list {
			list { a_take(list { num(0), list { empty } }) },
			list { a_take(list { num(0), list { list { num(0) } } }) },
		})),
		res = list { TRUE, TRUE },
	},
	{
		eval = a_split(a_type(list {
			a_take(list { num(0), list { num(0) } }),
			a_take(list { num(0), list { empty } }),
			a_take(list { num(0), list { list { num(1), num(2) } } }),
		})),
		res = list { TRUE, FALSE, FALSE },
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
	end
end
