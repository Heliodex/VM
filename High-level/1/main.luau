--!strict

-- A program is a list of functions.
type ToParse = {
	read src: { string },
	pos: number,
}

local function current(p: ToParse): string?
	if p.pos > #p.src then
		return nil
	end

	return p.src[p.pos]
end

local function advance(p: ToParse)
	p.pos += 1
end

local function next(p: ToParse): string?
	if p.pos + 1 > #p.src then
		return nil
	end

	return p.src[p.pos + 1]
end

local function toParse(src: string): ToParse
	return {
		src = string.split(src, ""),
		pos = 1,
	}
end

type Fn = {
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

type Name = {
	read kind: "Name",
	read name: string,
}

local function name(name: string): Name
	return {
		kind = "Name",
		name = name,
	}
end

type App = {
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

type Expr = Fn | Name | App

type AST = Fn

local function isWhitespace(c: string): boolean
	return c == " " or c == "\n" or c == "\t"
end

local function isControl(c: string): boolean
	return isWhitespace(c) or c == "(" or c == ")" or c == "[" or c == "]"
end

type Ok<T> = { ok: true, value: T }
type Err = { ok: false, error: string }
type Result<T> = Ok<T> | Err

local function ok<T>(value: T): Result<T>
	return { ok = true, value = value }
end

local function err(error: string): Err
	return { ok = false, error = error }
end

local errExpectedName = err "Expected a name"

local function errUndefinedVariable(name: string): Result<any>
	return err(`Undefined variable '{name}'`)
end

local function errExpectedChar(expected: string, got: string): Result<any>
	return err(`Expected '{expected}', got '{got}'`)
end

local function wrapErr(pre: string, e: Err): Result<any>
	return err(`{pre}: {e.error}`)
end

local function skipWhitespace(p: ToParse)
	while true do
		local c = current(p)
		if not c then
			break
		end

		if not isWhitespace(c) then
			break
		end
		advance(p)
	end
end

local parseName, parseExpr

local function parseFn(p: ToParse, scope: { [string]: true }): Result<Fn>
	skipWhitespace(p)

	do
		local c = current(p)
		local expected = "("
		if c ~= expected then
			return errExpectedChar(expected, c or "EOF")
		end
		advance(p)
	end

	local paramResult = parseName(p)
	if not paramResult.ok then
		return wrapErr("parseFunction", paramResult)
	end

	local binding = paramResult.value
	scope[binding] = true

	skipWhitespace(p)

	local exprResult = parseExpr(p, scope)
	if not exprResult.ok then
		return exprResult
	end

	local rexpr = exprResult.value

	do
		local c = current(p)
		local expected = ")"
		if c ~= expected then
			return errExpectedChar(expected, c or "EOF")
		end
		advance(p)
	end

	skipWhitespace(p)

	return ok(fn(binding, rexpr) :: Fn)
end

local function parseApp(p: ToParse, scope: { [string]: true }): Result<Expr>
	skipWhitespace(p)

	do
		local c = current(p)
		local expected = "["
		if c ~= expected then
			return errExpectedChar(expected, c or "EOF")
		end
		advance(p)
	end

	local fnResult = parseExpr(p, scope)
	if not fnResult.ok then
		return wrapErr("parseApp fn", fnResult)
	end

	local rfn = fnResult.value
	scope[rfn] = true

	skipWhitespace(p)

	local argResult = parseExpr(p, scope)
	if not argResult.ok then
		return wrapErr("parseApp arg", argResult)
	end

	local rarg = argResult.value

	do
		local c = current(p)
		local expected = "]"
		if c ~= expected then
			return errExpectedChar(expected, c or "EOF")
		end
		advance(p)
	end

	skipWhitespace(p)

	return ok(app(rfn, rarg) :: App)
end

function parseName(p: ToParse): Result<string>
	local name: { string } = {}

	while true do
		local c = current(p)
		if not c then
			break
		end

		if isControl(c) then
			break
		end

		table.insert(name, c)
		advance(p)
	end

	if #name == 0 then
		return errExpectedName
	end

	return ok(table.concat(name))
end

function parseExpr(p: ToParse, scope: { [string]: true }): Result<Expr>
	if current(p) == "(" then
		local fnResult = parseFn(p, scope)
		if not fnResult.ok then
			return fnResult
		end

		return ok(fnResult.value :: Expr)
	end

	if current(p) == "[" then
		local appResult = parseApp(p, scope)
		if not appResult.ok then
			return appResult
		end

		return ok(appResult.value :: Expr)
	end

	local nameResult = parseName(p)
	if not nameResult.ok then
		return wrapErr("parseExpr", nameResult)
	end

	local rname = nameResult.value

	if not scope[rname] then
		return errUndefinedVariable(rname)
	end

	return ok(name(rname) :: Expr)
end

local function parseAST(p: ToParse): Result<AST>
	local scope: { [string]: true } = {}

	return parseFn(p, scope)
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end

	if type(a) ~= "table" then
		return a == b
	end

	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end

	for k, v in b do
		if not deepEqual(v, a[k]) then
			return false
		end
	end

	return true
end

local function printTable(t: any, i: number?)
	local indent = i or 0

	for k, v in t do
		if type(v) == "table" then
			print(`{string.rep("  ", indent)}{k}:`)
			printTable(v, indent + 1)
			continue
		end

		if type(v) == "string" then
			v = `"{v}"`
		end
		print(`{string.rep("  ", indent)}{k}: {v}`)
	end
end

type TestCase = {
	read source: string,
	read expected: Result<AST>,
}

local tests: { TestCase } = {
	{
		source = [[
			b
		]],
		expected = errExpectedChar("(", "b"),
	},
	{
		source = [[
			(x x)
		]],
		expected = ok(fn("x", name "x")),
	},
	{
		source = [[
			(x y)
		]],
		expected = errUndefinedVariable "y",
	},
	{
		source = [[
			(xy)
		]],
		expected = wrapErr("parseExpr", errExpectedName),
	},
	{
		source = [[
			(x (y x))
		]],
		expected = ok(fn("x", fn("y", name "x")) :: AST),
	},
	{
		source = [[
			(x (y [y x]))
		]],
		expected = ok(fn("x", fn("y", app(name "y", name "x"))) :: AST),
	},
}

for _, test in tests do
	local input = toParse(test.source)
	local result = parseAST(input)

	if not deepEqual(result, test.expected) then
		-- error "Test failed: AST does not match expected"
		print "Expected:\n"
		printTable(test.expected)
		print "\nGot:\n"
		printTable(result)
		return
	end

	if result.ok then
		printTable(result.value)
	else
		print(`Error: {result.error}`)
	end
	print()
end

print "PASS"
