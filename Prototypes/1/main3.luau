--!strict

type Num = {
	read type: "num",
	read value: number,
}
type Thing = Pt | Num
type Pt = {
	read type: "pt",
	read _1: Thing,
	read _2: Thing,
}

local function num(value: number): Num
	return table.freeze { type = "num", value = value } :: Num
end

local function p(a1: Thing, a2: Thing): Pt
	return table.freeze { type = "pt", _1 = a1, _2 = a2 } :: Pt
end

local function view(e: Thing): string
	return if e.type == "num" then tostring(e.value) else `({view(e._1)} {view(e._2)})`
end

local function equalNum(a: Num, b: Num): boolean
	return a.value == b.value
end

local equal

local function equalPt(a: Pt, b: Pt): boolean
	return equal(a._1, b._1) and equal(a._2, b._2)
end

function equal(a: Thing, b: Thing): boolean
	return if a.type == "num" and b.type == "num"
		then equalNum(a, b)
		elseif a.type == "pt" and b.type == "pt" then equalPt(a, b)
		else false
end

local function reduce(e: Thing): Thing
	print("-", view(e))
	if e.type == "num" then
		return e
	end

	return e
end

local tests = {
	p(num(1), num(2)),
	p(p(num(3), num(4)), num(5)),
	p(num(6), p(num(7), num(8))),
}

for _, test in tests do
	print("=", view(reduce(test)))
end

