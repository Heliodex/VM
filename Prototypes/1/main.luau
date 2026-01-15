-- Lamba Calculus-based VM

type Var = {
	type: "var",
	name: string,
}
type App = {
	type: "app",
	func: Fn,
	arg: Fn,
}
type Thing = Fn | App | Var
type Fn = {
	type: "fn",
	param: Var,
	body: Thing,
}

local function var(name: string): Var
	return { type = "var", name = name }
end

local function app(func: Fn, arg: Fn): App
	return { type = "app", func = func, arg = arg }
end

local function fn(param: Var, body: Fn | App | Var): Fn
	return { type = "fn", param = param, body = body }
end

local function view(e: Fn | App | Var): string
	if e.type == "var" then
		return e.name
	end
	if e.type == "app" then
		return `({view(e.func)})({view(e.arg)})`
	end
	return `λ{e.param.name}.{view(e.body)}`
end

local xpr = app(fn(var "x", var "x"), fn(var "y", var "y"))
print(view(xpr))
