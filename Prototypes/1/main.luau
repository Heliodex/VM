-- Lamba Calculus-based VM

type Var = {
	type: "var",
	name: string,
}
type Thing = Fn | App | Var
type App = {
	type: "app",
	func: Thing,
	arg: Thing,
}
type Fn = {
	type: "fn",
	param: Var,
	body: Thing,
}

local function var(name: string): Var
	return { type = "var", name = name }
end

local function app(func: Thing, arg: Thing): App
	return { type = "app", func = func, arg = arg }
end

local function fn(param: Var, body: Thing): Fn
	return { type = "fn", param = param, body = body }
end

local function view(e: Thing): string
	return if e.type == "var"
		then e.name
		elseif e.type == "app" then `[{view(e.func)}]({view(e.arg)})`
		else `λ{e.param.name}.{view(e.body)}`
end

local sub

local function subVar(e: Var, from: Var, to: Thing): Thing
	return if e.name == from.name then to else e
end

local function subFn(e: Fn, from: Var, to: Var): Fn
	return fn(sub(e.param, from, to), sub(e.body, from, to))
end

local function subApp(e: App, from: Var, to: Var): App
	return app(sub(e.func, from, to), sub(e.arg, from, to))
end

function sub(e: Thing, from: Var, to: Var): Thing
	return if e.type == "var"
		then subVar(e, from, to)
		elseif e.type == "app" then subApp(e, from, to)
		else subFn(e, from, to)
end

local function beta(e: App): Thing
	if e.func.type == "app" then
		local fn2 = beta(e.func)
		return app(fn2, e.arg)
	end
	if e.func.type == "var" then
		return e
	end
	return sub(e.func.body, e.func.param, e.arg)
end

local function equal(e1: Thing, e2: Thing): boolean
	return if e1.type == "var" and e2.type == "var"
		then e1.name == e2.name
		elseif e1.type == "app" and e2.type == "app" then equal(
			e1.func,
			e2.func
		) and equal(e1.arg, e2.arg)
		elseif e1.type == "fn" and e2.type == "fn" then equal(
			e1.param,
			e2.param
		) and equal(e1.body, e2.body)
		else false
end

local function reduce(e: Thing): Thing
	print("Reduce", view(e))
	if e.type == "app" then
		local newe = beta(e)
		return reduce(newe)
	end
	return e
end

local ltrue = fn(var "a", fn(var "b", var "a"))
local lfalse = fn(var "a", fn(var "b", var "b"))

local e1 = app(app(ltrue, var "x"), var "y")
print "e1"
local r1 = reduce(e1)

local e2 = app(app(lfalse, var "x"), var "y")
print "e2"
local r2 = reduce(e2)

print(equal(r1, r2))

-- local e3 = app(app(app(ltrue, var "x"), var "y"), var "z")
-- print "e3"
-- reduce(e3)
