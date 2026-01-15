--!strict
-- Lamba Calculus-based VM

type Var = {
	read type: "var",
	read name: string,
}
type Thing = Pt | Var
type Pt = {
	read type: "pt",
	read _1: Thing,
	read _2: Thing,
}

local function var(name: string): Var
	return table.freeze { type = "var", name = name } :: Var
end

local function p(a1: Thing, a2: Thing): Pt
	return table.freeze { type = "pt", _1 = a1, _2 = a2 } :: Pt
end

local function view(e: Thing): string
	return if e.type == "var" then e.name else `({view(e._1)}{view(e._2)})`
end

local function equalVar(a: Var, b: Var): boolean
	return a.name == b.name
end

local equal

local function equalPt(a: Pt, b: Pt): boolean
	return equal(a._1, b._1) and equal(a._2, b._2)
end

function equal(a: Thing, b: Thing): boolean
	return if a.type == "var" and b.type == "var"
		then equalVar(a, b)
		elseif a.type == "pt" and b.type == "pt" then equalPt(a, b)
		else false
end

local function sub(e: Thing, from: Thing, to: Thing): Thing
	return if equal(e, from)
		then to
		elseif e.type == "var" then e
		else p(sub(e._1, from, to), sub(e._2, from, to))
end

local function beta(e: Pt): Thing
	return if e._1.type == "var" then e else sub(e._1._2, e._1._1, e._2)
end

local function reduce(e: Thing): Thing
	print("-", view(e))
	if e.type == "var" then
		return e
	end
	local newe = beta(e)
	return if equal(newe, e) then e else reduce(newe)
end

local A, B, C, D, E, F, G =
	var "A", var "B", var "C", var "D", var "E", var "F", var "G"

local tests = {
	A,
	p(A, B),
	p(A, p(B, C)),
	p(p(B, C), A),
	p(p(C, p(D, E)), A),
	p(p(C, p(D, C)), A),
	p(p(C, p(C, C)), A),
}

for i, e in tests do
	print(i)
	reduce(e)
end
