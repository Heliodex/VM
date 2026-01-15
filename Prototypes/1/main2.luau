--!strict
-- Lamba Calculus-based VM

type Var = {
	read type: "var",
	read name: string,
}
type Thing = Pt | Var
type Pt = {
	read type: "pt",
	read eval: boolean,
	read p1: Thing,
	read p2: Thing,
}

local function var(name: string): Var
	return table.freeze { type = "var", name = name } :: Var
end

local function pt(eval: boolean, p1: Thing, p2: Thing): Pt
	return table.freeze { type = "pt", eval = eval, p1 = p1, p2 = p2 } :: Pt
end

local function app(p1: Thing, p2: Thing): Pt
	return pt(true, p1, p2)
end

local function fn(p1: Thing, p2: Thing): Pt
	return pt(false, p1, p2)
end

local function view(e: Thing): string
	return if e.type == "var"
		then e.name
		else `{if e.eval then "|" else "λ"}{view(e.p1)}{view(e.p2)}`
end

local function equalVar(a: Var, b: Var): boolean
	return a.name == b.name
end

local equal

local function equalPt(a: Pt, b: Pt): boolean
	return equal(a.p1, b.p1) and equal(a.p2, b.p2)
end

function equal(a: Thing, b: Thing): boolean
	return if a.type == "var" and b.type == "var"
		then equalVar(a, b)
		elseif a.type == "pt" and b.type == "pt" then equalPt(a, b)
		else false
end

local function subVar(e: Var, from: Thing, to: Thing): Thing
	return if from.type == "var" and e.name == from.name then to else e
end

local sub

local function subPt(e: Pt, from: Thing, to: Thing): Thing
	return if equal(e, from)
		then to
		else pt(e.eval, sub(e.p1, from, to), sub(e.p2, from, to))
end

function sub(e: Thing, from: Thing, to: Thing): Thing
	return if e.type == "var" then subVar(e, from, to) else subPt(e, from, to)
end

local function beta(e: Pt): Thing
	return if e.p1.type == "var"
		then e
		elseif e.p1.eval then app(beta(e.p1), e.p2)
		else sub(e.p1.p2, e.p1.p1, e.p2)
end

local function reduce(e: Thing): Thing
	print("Reduce", view(e))
	if e.type ~= "pt" or not e.eval then
		return e
	end
	local newe = beta(e)
	return if equal(newe, e) then e else reduce(newe)
end

local ltrue = fn(var "a", fn(var "b", var "a"))
local lfalse = fn(var "a", fn(var "b", var "b"))

local tests = {
	app(app(ltrue, var "x"), var "y"),
	app(app(lfalse, var "x"), var "y"),
	app(app(app(ltrue, var "x"), var "y"), var "z"), -- app of a var to a var
	app(fn(app(var "x", var "y"), var "z"), app(var "x", var "y")),
	app(
		fn(app(var "x", var "y"), app(var "z", app(var "x", var "y"))),
		var "w"
	),
	app(fn(fn(var "x", var "y"), app(var "z", fn(var "x", var "y"))), var "w"),
}

for i, e in tests do
	print()
	print(i)
	reduce(e)
end
