-- Lamba Calculus-based VM

type Var = {
	type: "var",
	name: string,
}
type Thing = Fn | App | Var
type P2t = { p2: Thing }
type App = {
	type: "app",
	p1: Thing,
} & P2t
type Fn = {
	type: "fn",
	p1: Var,
} & P2t

local function var(name: string): Var
	return { type = "var", name = name }
end

local function app(p1: Thing, p2: Thing): App
	return { type = "app", p1 = p1, p2 = p2 }
end

local function fn(p1: Var, p2: Thing): Fn
	return { type = "fn", p1 = p1, p2 = p2 }
end

local function view(e: Thing): string
	return if e.type == "var"
		then e.name
		elseif e.type == "app" then `[{view(e.p1)}]({view(e.p2)})`
		else `λ{view(e.p1)}.{view(e.p2)}`
end

local sub

local function subVar(e: Var, from: Var, to: Thing): Thing
	return if e.name == from.name then to else e
end

local function subFn(e: Fn, from: Var, to: Var): Fn
	return fn(sub(e.p1, from, to), sub(e.p2, from, to))
end

local function subApp(e: App, from: Var, to: Var): App
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
	return sub(e.p1.p2, e.p1.p1, e.p2)
end

local function equal(e1: Thing, e2: Thing): boolean
	return if e1.type == "var" and e2.type == "var"
		then e1.name == e2.name
		elseif e1.type == "app" and e2.type == "app" then equal(
			e1.p1,
			e2.p1
		) and equal(e1.p2, e2.p2)
		elseif e1.type == "fn" and e2.type == "fn" then equal(e1.p1, e2.p1)
			and equal(e1.p2, e2.p2)
		else false
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
}

for i, e in tests do
	print()
	print(i)
	reduce(e)
end
