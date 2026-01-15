-- Lamba Calculus-based VM

type Var = {
	type: "var",
	name: string,
}
type Thing = Fn | App | Var
type Pt = { p1: Thing, p2: Thing }
type App = { type: "app" } & Pt
type Fn = { type: "fn" } & Pt

local function var(name: string): Var
	return { type = "var", name = name }
end

local function app(p1: Thing, p2: Thing): App
	return { type = "app", p1 = p1, p2 = p2 }
end

local function fn(p1: Thing, p2: Thing): Fn
	return { type = "fn", p1 = p1, p2 = p2 }
end

local function view(e: Thing): string
	return if e.type == "var"
		then e.name
		elseif e.type == "app" then `[{view(e.p1)}]({view(e.p2)})`
		else `λ{view(e.p1)}.{view(e.p2)}`
end

local equal

local function equalVar(e1: Var, e2: Var): boolean
	return e1.name == e2.name
end

local function equalApp(e1: App, e2: App): boolean
	return equal(e1.p1, e2.p1) and equal(e1.p2, e2.p2)
end

local function equalFn(e1: Fn, e2: Fn): boolean
	return equal(e1.p1, e2.p1) and equal(e1.p2, e2.p2)
end

function equal(e1: Thing, e2: Thing): boolean
	return if e1.type == "var" and e2.type == "var"
		then equalVar(e1, e2)
		elseif e1.type == "app" and e2.type == "app" then equalApp(e1, e2)
		elseif e1.type == "fn" and e2.type == "fn" then equalFn(e1, e2)
		else false
end

local sub

local function subVar(e: Var, from: Var, to: Thing): Thing
	return if e.name == from.name then to else e
end

local function subFn(e: Fn, from: Var, to: Var): Fn
	return fn(sub(e.p1, from, to), sub(e.p2, from, to))
end

local function subApp(e: App, from: Thing, to: Thing): Thing
	if equal(e, from) then
		return to
	end

	return app(sub(e.p1, from, to), sub(e.p2, from, to))
end

function sub(e: Thing, from: Var, to: Var): Thing
	return if e.type == "var"
		then subVar(e, from, to)
		elseif e.type == "app" then subApp(e, from, to)
		else subFn(e, from, to)
end

local function beta(e: App): Thing
	if e.p1.type == "app" then
		local fn2 = beta(e.p1)
		return app(fn2, e.p2)
	end
	if e.p1.type == "var" then
		return e
	end
	-- print("In", view(e.p1.p2), "sub", view(e.p1.p1), "to", view(e.p2))
	return sub(e.p1.p2, e.p1.p1, e.p2)
end

local function reduce(e: Thing): Thing
	print("Reduce", view(e))
	if e.type ~= "app" then
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
}

for i, e in tests do
	print()
	print(i)
	reduce(e)
end
