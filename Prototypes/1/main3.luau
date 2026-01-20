--!strict

type Num = {
	read type: "@",
	read value: number,
}
type Thing = Set | Num
type Set = {
	read type: "$",
	read things: { [string]: boolean },
}

local NUM: "@" = "@"
local SET: "$" = "$"

local function serialise(t: Thing): string
	if t.type == NUM then
		return tostring(t.value)
	end

	local elements = {}
	for key, _ in t.things do
		table.insert(elements, key)
	end
	table.sort(elements)
	return "{" .. table.concat(elements, " ") .. "}"
end

local function num(value: number): Num
	return table.freeze { type = NUM, value = value } :: Num
end

local function set(things: { Thing }): Set
	local thingSet = {}
	for _, t in things do
		thingSet[serialise(t)] = true
	end
	return table.freeze { type = SET, things = table.freeze(thingSet) } :: Set
end

local empty = set {}

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

	return set(elements)
end

local function equalNum(a: Num, b: Num): boolean
	return a.value == b.value
end

local equal

local function equalSet(a: Set, b: Set): boolean
	for key, _ in a.things do
		if not b.things[key] then
			return false
		end
	end

	for key, _ in b.things do
		if not a.things[key] then
			return false
		end
	end

	return true
end

function equal(a: Thing, b: Thing): boolean
	return if a.type == NUM and b.type == NUM
		then equalNum(a, b)
		elseif a.type == SET and b.type == SET then equalSet(a, b)
		else false
end

local function size(s: Set): number
	local i = 0
	for _ in s.things do
		i += 1
	end
	return i
end

local function arraySetTable(arraySet: Set, red: (Set) -> Thing?): { Thing }?
	local tab = {}

	for part in arraySet.things do
		local p = deserialise(part)
		if p.type ~= SET then
			return nil
		end

		-- this part must contain a Num and a Set
		local n2: Num?, s2: Set?

		for k, _ in p.things do
			local t = deserialise(k)
			if t.type == NUM then
				n2 = t
			else
				s2 = t
			end
		end

		if not n2 then
			return nil
		end
		if not s2 then
			return nil
		end

		local st = red(s2)
		if not st then
			return nil
		end

		tab[n2.value] = st
	end

	return tab
end

local function reduce1(e: Thing, depth: number): Thing?
	print(string.rep(" ", depth) .. "-", serialise(e))
	if e.type == NUM then
		return e -- *a:@ -> a
	end

	if size(e) == 0 then
		return e -- *{} -> {}
	end

	if size(e) == 1 then
		-- extract the single element
		-- kind of like a pin<>
		local only: string
		for k, _ in e.things do
			only = k
		end
		return reduce1(deserialise(only), depth + 1) -- *{a} -> *a
	end

	if size(e) ~= 2 then
		return nil
	end

	-- now we're talking
	-- the set needs to contain a Num and a Set

	local n: Num?, s: Set?

	for k, _ in e.things do
		local t = deserialise(k)
		if t.type == NUM then
			n = t
		else
			s = t
		end
	end

	if not n then
		return nil
	end
	if not s then
		return nil
	end

	-- print("Found num and set:", serialise(n), serialise(s))

	-- opcodes

	-- 0: set size
	-- til the mathematical term for this is cardinality
	if n.value == 0 then
		return num(size(s)) -- *{0 a:$} -> size(a)
	end

	-- 1: increment
	-- I was going to make this add up all the numbers in a set. Tried it, surprise! It's not useful at all because it only works if every number is different.
	if n.value == 1 then
		local st = reduce1(s, depth + 1)
		if not st or st.type ~= NUM then
			return nil
		end
		return num(st.value + 1) -- *{1 a:@} -> a + 1
	end

	if n.value == 2 then
		local ast = arraySetTable(s, function(sube: Set): Thing?
			return reduce1(sube, depth + 1)
		end)
		if not ast then
			return nil
		end

		print "array set table"
		for i, v in ast do
			print(" ", i, serialise(v))
		end

		return nil
	end

	return nil
end

local function reduce(e: Thing): Thing?
	return reduce1(e, 0)
end

-- array: {{1 {a}} {2{b}} {3 {c}}}

local tests = {
	-- generic
	{
		num(0),
		empty,
		set { num(1) },
		set { empty, set { empty } },
		set { empty, set { set { num(1) } } },
	},

	-- 0
	{
		set { num(0), set {} },
		set { num(0), set { num(1) } },
		set { num(0), set { num(1), num(2), num(3) } },
	},

	-- 1
	{
		set { num(1), set { set { num(1) } } },
		set { num(1), set { num(1) } },
		set { num(1), set { set { num(1), set { num(40) } } } },
	},

	-- 2
	{
		set {
			num(2),
			set {
				set { num(1), set { num(1) } },
				set { num(2), set { num(2) } },
				set { num(3), set { num(3) } },
			},
		},
	},
}

-- test serialise and deserialise
for i, testgroup in tests do
	for _, test in testgroup do
		local s = serialise(test)
		local d = deserialise(s)
		if not equal(test, d) then
			print(`Serialization round-trip failed for {s}`)
			return
		end
	end
end

for i, testgroup in tests do
	print("Tests group", i)
	for _, test in testgroup do
		local rd = reduce(test)
		if rd == nil then
			print "~~"
			print()
			continue
		end
		print("=", serialise(rd))
		print()
	end
end
