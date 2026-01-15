-- Lamba Calculus-based VM

type Var = {
	type: "var",
	name: string,
}
type Thing = Fn | App | Var
type App = {
	type: "app",
	func: Fn,
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

local function app(func: Fn, arg: Thing): App
	return { type = "app", func = func, arg = arg }
end

local function fn(param: Var, body: Thing): Fn
	return { type = "fn", param = param, body = body }
end

local function view(e: Thing): string
	return if e.type == "var"
		then e.name
		elseif e.type == "app" then `({view(e.func)})({view(e.arg)})`
		else `λ{e.param.name}.{view(e.body)}`
end

local xpr = app(fn(var "x", var "x"), fn(var "y", var "y"))
print(view(xpr))

local sub

local function subVar(e: Var, from: Var, to: Var): Var
	return if e.name == from.name then to else e
end

local function subFn(e: Fn, from: Var, to: Var): Fn
	return fn(subVar(e.param, from, to), sub(e.body, from, to))
end

local function subApp(e: App, from: Var, to: Var): App
	return app(subFn(e.func, from, to), sub(e.arg, from, to))
end

function sub(e: Thing, from: Var, to: Var): Thing
	return if e.type == "var"
		then subVar(e, from, to)
		elseif e.type == "app" then subApp(e, from, to)
		else subFn(e, from, to)
end

print(view(sub(xpr, var "x", var "z")))
print(view(sub(xpr, var "y", var "z")))
