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

	local st = reduce1(s, depth + 1)
	if not st then
		return nil
	end

	-- opcodes
	if n.value == 1 and st.type == NUM then
		return num(st.value + 1) -- *{1 a:@} -> a + 1
	end

	return nil
end

local function reduce(e: Thing): Thing?
	return reduce1(e, 0)
end

local tests = {
	num(0),
	empty,
	set { num(1) },
	set { empty, set { empty } },
	set { empty, set { set { num(1) } } },
	set { num(1), set { set { num(1) } } },
	set { num(1), set { num(1) } },
}

-- test serialise and deserialise
for _, test in tests do
	local s = serialise(test)
	local d = deserialise(s)
	if not equal(test, d) then
		print(`Serialization round-trip failed for {s}`)
		return
	end
end

for _, test in tests do
	local rd = reduce(test)
	if rd == nil then
		print "No reduction"
		print()
		continue
	end
	print("=", serialise(rd))
	print()
end
