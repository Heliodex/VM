--!strict

local parser = require "./parser"
local types = require "./types"

type ToParse = parser.ToParse

local fn, app, num, name = types.fn, types.app, types.num, types.name
local current, advance, toParse = parser.current, parser.advance, parser.toParse

local function isWhitespace(c: string): boolean
	return c == " " or c == "\n" or c == "\t"
end

local function isDigit(c: string): boolean
	return c >= "0" and c <= "9"
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
local errExpectedNumber = err "Expected a number"
local errConvertNumber = err "Failed to convert digits to number"

local function errUndefinedVariable(n: string): Result<any>
	return err(`Undefined variable '{n}'`)
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

local function expect(p: ToParse, expected: string): Result<nil>
	local c = current(p)
	if c ~= expected then
		return errExpectedChar(expected, c or "EOF")
	end
	advance(p)
	return ok(nil)
end

local parseName, parseNum, parseExpr

local function parseFn(p: ToParse, scope: { [string]: true }): Result<types.Fn>
	skipWhitespace(p)

	local expectResult1 = expect(p, "(")
	if not expectResult1.ok then
		return expectResult1
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

	local expectResult2 = expect(p, ")")
	if not expectResult2.ok then
		return expectResult2
	end

	skipWhitespace(p)

	return ok(fn(binding, rexpr) :: types.Fn)
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

local function parseApp(p: ToParse, scope: { [string]: true }): Result<types.Expr>
	skipWhitespace(p)

	local expectResult1 = expect(p, "[")
	if not expectResult1.ok then
		return expectResult1
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

	local expectResult2 = expect(p, "]")
	if not expectResult2.ok then
		return expectResult2
	end

	skipWhitespace(p)

	return ok(app(rfn, rarg) :: types.App)
end

function parseNum(p: ToParse): Result<types.Num>
	local digits: { string } = {}

	while true do
		local c = current(p)
		if not c then
			break
		end

		if not isDigit(c) then
			break
		end

		table.insert(digits, c)
		advance(p)
	end

	if #digits == 0 then
		return errExpectedNumber
	end

	local value = tonumber(table.concat(digits))
	if not value then
		return errConvertNumber
	end

	return ok(num(value) :: types.Num)
end

function parseExpr(p: ToParse, scope: { [string]: true }): Result<types.Expr>
	if current(p) == "(" then
		local fnResult = parseFn(p, scope)
		if not fnResult.ok then
			return fnResult
		end

		return ok(fnResult.value :: types.Expr)
	end

	if current(p) == "[" then
		local appResult = parseApp(p, scope)
		if not appResult.ok then
			return appResult
		end

		return ok(appResult.value :: types.Expr)
	end

	if isDigit(current(p) or "") then
		local numResult = parseNum(p)
		if not numResult.ok then
			return numResult
		end

		return ok(numResult.value :: types.Expr)
	end

	local nameResult = parseName(p)
	if not nameResult.ok then
		return wrapErr("parseExpr", nameResult)
	end

	local rname = nameResult.value

	if not scope[rname] then
		return errUndefinedVariable(rname)
	end

	return ok(name(rname) :: types.Expr)
end

local function parseAST(p: ToParse): Result<types.AST>
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
	read expected: Result<types.AST>,
}

local tests: { TestCase } = {
	{
		source = [[
			b
		]],
		expected = errExpectedChar("(", "b"),
	},

	-- fn, name
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
		expected = ok(fn("x", fn("y", name "x")) :: types.AST),
	},

	-- app
	{
		source = [[
			(x (y [y x]))
		]],
		expected = ok(fn("x", fn("y", app(name "y", name "x"))) :: types.AST),
	},

	-- num
	{
		source = [[
			(x 123)
		]],
		expected = ok(fn("x", num(123)) :: types.AST),
	},
	{
		source = [[
			(1 123)
		]],
		expected = ok(fn("1", num(123)) :: types.AST),
	},
	{
		source = [[
			(x [x 123])
		]],
		expected = ok(fn("x", app(name "x", num(123))) :: types.AST),
	},
	{
		source = [[
			(x [1 123])
		]],
		expected = ok(fn("x", app(num(1), num(123))) :: types.AST),
	},
	{
		source = [[
			(x [(y [x y]) 123])
		]],
		expected = ok(
			fn("x", app(fn("y", app(name "x", name "y")), num(123))) :: types.AST
		),
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
