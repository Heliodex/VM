--!strict

export type Fn = {
	read kind: "Fn",
	read binding: string,
	read expr: Expr,
}

local function fn(binding: string, expr: Expr): Fn
	return {
		kind = "Fn",
		binding = binding,
		expr = expr,
	}
end

export type Name = {
	read kind: "Name",
	read name: string,
}

local function name(name: string): Name
	return {
		kind = "Name",
		name = name,
	}
end

export type App = {
	read kind: "App",
	read fn: Expr,
	read arg: Expr,
}

local function app(fn: Expr, arg: Expr): App
	return {
		kind = "App",
		fn = fn,
		arg = arg,
	}
end

export type Num = {
	read kind: "Num",
	read value: number,
}

local function num(value: number): Num
	return {
		kind = "Num",
		value = value,
	}
end

export type Expr = Fn | Name | App | Num

export type AST = Fn

return {
	fn = fn,
	name = name,
	app = app,
	num = num,
}