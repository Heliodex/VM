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
type Name = {
	read kind: "Name",
	read name: string,
}

type Expr = Fn | Name

type AST = Fn

local function isWhitespace(c: string): boolean
	return c == " " or c == "\n" or c == "\t"
end

local function isControl(c: string): boolean
	return c == "(" or c == ")" or isWhitespace(c)
end

type Result<T, E> = { ok: true, value: T } | { ok: false, error: E }

local function parseName(p: ToParse): Result<string, string>
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
		return { ok = false, error = "Expected a name" }
	end

	return { ok = true, value = table.concat(name) }
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

local parseFunction

local function parseExpr(
	p: ToParse,
	scope: { [string]: true }
): Result<Expr, string>
	if next(p) == "(" then
		local fnResult = parseFunction(p, scope)
		if not fnResult.ok then
			return fnResult
		end

		return {
			ok = true,
			value = fnResult.value,
		}
	end

	local nameResult = parseName(p)
	if not nameResult.ok then
		return nameResult
	end

	if not scope[nameResult.value] then
		return { ok = false, error = `Undefined variable '{nameResult.value}'` }
	end

	return {
		ok = true,
		value = {
			kind = "Name",
			name = nameResult.value,
		},
	}
end

function parseFunction(
	p: ToParse,
	scope: { [string]: true }
): Result<Fn, string>
	skipWhitespace(p)

	do
		local c = current(p)
		if c ~= "(" then
			return { ok = false, error = `Expected '(', got '{c}'` }
		end
		advance(p)
	end

	local paramResult = parseName(p)
	if not paramResult.ok then
		return paramResult
	end

	local binding = paramResult.value
	scope[binding] = true

	skipWhitespace(p)

	local exprResult = parseExpr(p, scope)
	if not exprResult.ok then
		return exprResult
	end

	local expr = exprResult.value

	do
		local c = current(p)
		if c ~= ")" then
			return { ok = false, error = `Expected ')', got '{c}'` }
		end
		advance(p)
	end

	skipWhitespace(p)

	return {
		ok = true,
		value = {
			kind = "Fn",
			binding = binding,
			expr = expr,
		},
	}
end

local function parseAST(p: ToParse): Result<AST, string>
	local scope: { [string]: true } = {}

	return parseFunction(p, scope)
end

local function printTable(t: any, i: number?)
	local indent = i or 0

	for k, v in t do
		if type(v) == "table" then
			print(`{string.rep("  ", indent)}{k}:`)
			printTable(v, indent + 1)
		else
			if type(v) == "string" then
				v = `"{v}"`
			end
			print(`{string.rep("  ", indent)}{k}: {v}`)
		end
	end
end

local source = [[
(x x)
]]

local input = toParse(source)
local result = parseAST(input)

if result.ok then
	printTable(result.value)
else
	print("Error:", result.error)
end
