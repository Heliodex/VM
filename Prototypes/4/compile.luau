--!strict
-- COMPILING PROGRAMS TO NETS
--
-- Turns the expressions of reader.luau into a net, which the six rules then reduce to the value of the program.
-- The language is small on purpose:
--   3                  a natural number, a Church numeral
--   true, false        Church booleans
--   x                  a variable, or a builtin (see BUILTINS below)
--   (lambda (x y) e)   a function of two arguments, curried underneath
--   (f a b)            application, curried: ((f a) b)
--   (if c t e)         both branches are built, then c picks one, as in booleans.luau
--   (define f e)       a top-level definition, visible to everything after it
-- The last form of a program is the expression whose value it is. Every form before it is a definition.
--
-- Variables are copied with `share` and erased with `erase` automatically. Before a binding is built, its body is counted for uses of its name, and each use takes one copy from the binding's pool, so nothing is left dangling or used twice.
--
-- Recursion: a top-level definition of a function may refer to its own name. Such a definition is compiled through recursion.luau, where the name stands for the recursive call, passed in as a code.
-- So the body of a recursive function must be closed: it may use its parameters, builtins and earlier definitions, but not variables of an enclosing lambda.
--
--   const Compile = require "./compile"
--
--   const report, net = Compile.evaluate("(define double (lambda (n) (+ n n))) (double 3)")
--   -- reading back net gives 6

const A = require "./arithmetic"
const B = require "./builder"
const Bo = require "./booleans"
const H = require "./harness"
const L = require "./lambda"
const Li = require "./lists"
const N = require "./numerals"
const Rec = require "./recursion"
const Reader = require "./reader"
const Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port
type Expr = Reader.Expr

-- What a name stands for in a scope.
-- A "param" is a variable of an enclosing lambda, and a "self" is the recursive call of the function being defined. Both hold a pool of copies, one for each use still to come.
-- A "def" is a top-level definition, compiled afresh at each use. Its scope is the top-level scope as it was before the definition, so it is closed.
type Binding = {
	kind: "param" | "self" | "def",
	name: string,
	pool: { Port }?,
	expr: Expr?,
	scope: Scope?,
	recursive: boolean?,
}
type Scope = {
	[string]: Binding,
}
-- The names that are always in scope, each built fresh wherever it is used.
const BUILTINS: {
	[string]: (Builder) -> Port,
} = {
	["+"] = A.addition,
	["*"] = A.product,
	succ = A.successor,
	["true"] = Bo.truth,
	["false"] = Bo.falsity,
	["nil"] = Li.nilValue,
	cons = Li.cons,
	isNil = Li.isNil,
	head = Li.head,
	tail = Li.tail,
}
-- Words with a meaning of their own, which a name may not be bound to.
const KEYWORDS: {
	[string]: boolean,
} = {
	lambda = true,
	["if"] = true,
	define = true,
}

const function isSym(
	e: Expr?,
	name: string
): boolean
	return e ~= nil and e.kind == "sym" and e.name == name
end

const function contains(
	names: { string },
	name: string
): boolean
	for _, n in names do
		if n == name then
			return true
		end
	end

	return false
end

-- The names from position `from` on.
const function rest(
	names: { string },
	from: number
): { string }
	const out: { string } = {}

	for i = from, #names do
		table.insert(out, names[i])
	end

	return out
end

-- A lambda with its parameter names and body.
type Lambda = {
	names: { string },
	body: Expr,
}
-- The lambda that `e` is, if it is one.
const function lambdaParts(
	e: Expr
): Lambda?
	if e.kind ~= "list" then
		return nil
	end

	const items = e.items :: { Expr }

	if not isSym(items[1], "lambda") or #items ~= 3 or items[2].kind ~= "list" then
		return nil
	end

	const names: { string } = {}

	for _, item in items[2].items :: { Expr } do
		if item.kind ~= "sym" then
			return nil
		end

		const name = item.name :: string

		if KEYWORDS[name] or BUILTINS[name] or contains(names, name) then
			return nil
		end

		table.insert(names, name)
	end

	if #names == 0 then
		return nil
	end

	return {
		names = names,
		body = items[3],
	}
end

-- How many copies of `name` the expression `e` takes. An inner lambda that binds the name again hides it.
-- A recursive name is `routed`: an if passes it into its branches as one code, which the chosen branch then copies for its own uses, so the two branches together take one copy, not one each. Every other name is counted plainly.
local countIn

-- How many times `name` is used free in (lambda names body).
local function countFree(
	name: string,
	names: { string },
	body: Expr,
	routed: boolean
): number
	if contains(names, name) then
		return 0
	end

	return countIn(name, body, routed)
end

countIn = function(
	name: string,
	e: Expr,
	routed: boolean
): number
	if e.kind == "num" then
		return 0
	elseif e.kind == "sym" then
		return if e.name == name then 1 else 0
	end

	const lambda = lambdaParts(e)

	if lambda then
		return countFree(name, lambda.names, lambda.body, routed)
	end

	const items = e.items :: { Expr }

	if routed and isSym(items[1], "if") and #items == 4 then
		const condition = countIn(name, items[2], routed)
		const branches = countIn(name, items[3], routed) + countIn(name, items[4], routed)

		return condition + if branches > 0 then 1 else 0
	end

	local total = 0

	for _, item in items do
		total += countIn(name, item, routed)
	end

	return total
end

local compile

-- The lambda over names[i], then the ones after it, with the body under all of them. Each parameter's pool holds one copy for each use in what follows it.
local function bindParams(
	names: { string },
	i: number,
	body: Expr,
	scope: Scope,
	b: Builder
): Port
	const name = names[i]

	return L.lam(
		b, function(
			x: Port
		): Port
			const copies = L.share(b, x, countFree(name, rest(names, i + 1), body, false))
			const inner = table.clone(scope)
			inner[name] = {
				kind = "param",
				name = name,
				pool = copies,
			}

			if i == #names then
				return compile(body, inner, b)
			end

			return bindParams(names, i + 1, body, inner, b)
		end
	)
end

-- A value for a variable or a recursive call, taken from its pool.
local function takeCopy(
	binding: Binding,
	b: Builder
): Port
	const pool = binding.pool :: { Port }

	if #pool == 0 then
		error(`internal: no copy of {binding.name} is left, so its uses were miscounted`)
	end

	const p = table.remove(pool, 1) :: Port

	if binding.kind == "self" then
		return Rec.recall(b, p)
	end

	return p
end

local compileRecursive

-- A top-level definition, built where it is used. A recursive one is tied through recursion.luau, which builds its code once into the net being built.
local function useDefinition(
	binding: Binding,
	b: Builder
): Port
	if binding.recursive then
		return Rec.tie(b, function(
			own: Builder
		): Port
			return compileRecursive(binding, own)
		end)
	end

	return compile(binding.expr :: Expr, binding.scope :: Scope, b)
end

-- R = λcode. λparams. body, where a use of the defined name in the body stands for a recall of the code. The code gets one copy for each such use.
compileRecursive = function(
	binding: Binding,
	own: Builder
): Port
	const lambda = lambdaParts(binding.expr :: Expr) :: Lambda
	const names, body = lambda.names, lambda.body
	const name = binding.name

	return L.lam(
		own, function(
			code: Port
		): Port
			const copies = L.share(own, code, countFree(name, names, body, true))
			const scope = table.clone(binding.scope :: Scope)
			scope[name] = {
				kind = "self",
				name = name,
				pool = copies,
			}

			return bindParams(names, 1, body, scope, own)
		end
	)
end

-- The name of the function being defined, if the scope is inside its body.
const function selfNameOf(
	scope: Scope
): string?
	for name, binding in scope do
		if binding.kind == "self" then
			return name
		end
	end

	return nil
end

-- An if whose branches use the recursive name. Each branch is a lambda that takes the code as its argument, so the code only unfolds in the branch the condition chooses. The unchosen branch is erased with its argument unsupplied.
local function compileRoutedIf(
	selfName: string,
	items: { Expr },
	scope: Scope,
	b: Builder
): Port
	-- the one copy of the code that the chosen branch receives
	const code = table.remove(scope[selfName].pool :: { Port }, 1) :: Port
	const condition = compile(items[2], scope, b)
	const branch = function(
		e: Expr
	): Port
		return L.lam(
			b, function(
				k: Port
			): Port
				const inner = table.clone(scope)
				inner[selfName] = {
					kind = "self",
					name = selfName,
					pool = L.share(b, k, countIn(selfName, e, true)),
				}

				return compile(e, inner, b)
			end
		)
	end
	const yes = branch(items[3])
	const no = branch(items[4])

	return L.app(b, L.app(b, L.app(b, condition, yes), no), code)
end

-- The port that the expression `e` evaluates to, built into `b`.
compile = function(
	e: Expr,
	scope: Scope,
	b: Builder
): Port
	if e.kind == "num" then
		return N.church(b, e.value :: number)
	elseif e.kind == "sym" then
		const name = e.name :: string
		const binding = scope[name]

		if binding then
			if binding.kind == "def" then
				return useDefinition(binding, b)
			end

			return takeCopy(binding, b)
		end

		const builtin = BUILTINS[name]

		if builtin then
			return builtin(b)
		end

		error(`unbound name {name}`)
	end

	const items = e.items :: { Expr }

	if #items == 0 then
		error "an empty list is not an expression"
	end

	if isSym(items[1], "lambda") then
		const lambda = lambdaParts(e)

		if not lambda then
			error "a lambda is (lambda (x ...) body), with at least one distinct parameter"
		end

		return bindParams(lambda.names, 1, lambda.body, scope, b)
	end

	if isSym(items[1], "if") then
		if #items ~= 4 then
			error "an if is (if condition then else)"
		end

		const selfName = selfNameOf(scope)

		if selfName and countIn(selfName, items[3], true) + countIn(selfName, items[4], true) > 0 then
			return compileRoutedIf(selfName, items, scope, b)
		end

		const condition = compile(items[2], scope, b)
		const yes = compile(items[3], scope, b)
		const no = compile(items[4], scope, b)

		return L.app(b, L.app(b, condition, yes), no)
	end

	if isSym(items[1], "define") then
		error "a definition can only be a top-level form"
	end

	local fn = compile(items[1], scope, b)

	for i = 2, #items do
		fn = L.app(b, fn, compile(items[i], scope, b))
	end

	return fn
end

-- The name and expression of a top-level definition, or nil for any other form.
const function asDefinition(
	form: Expr
): (string?, Expr?)
	if form.kind ~= "list" then
		return nil, nil
	end

	const items = form.items :: { Expr }

	if not isSym(items[1], "define") then
		return nil, nil
	end

	if #items ~= 3 or items[2].kind ~= "sym" then
		error "a definition is (define name expression)"
	end

	const name = items[2].name :: string

	if KEYWORDS[name] or BUILTINS[name] then
		error(`{name} is a builtin and cannot be defined`)
	end

	return name, items[3]
end

-- The port that the whole program evaluates to, built into `b`. The forms are definitions, followed by the one expression whose value it is.
const function program(
	forms: { Expr },
	b: Builder
): Port
	const scope: Scope = {}

	for i, form in forms do
		const name, expr = asDefinition(form)

		if name and expr then
			if i == #forms then
				error(`the program ends in the definition of {name}, not in a value`)
			end

			const recursive = countIn(name, expr, false) > 0

			if recursive and not lambdaParts(expr) then
				error(`{name} refers to itself, but only a function can recurse`)
			end

			scope[name] = {
				kind = "def",
				name = name,
				expr = expr,
				scope = table.clone(scope),
				recursive = recursive,
			}
		else
			if i ~= #forms then
				error "only the last form of a program may be an expression"
			end

			return compile(form, scope, b)
		end
	end

	error "the program has no expression to evaluate"
end

-- Reads and compiles the source, then reduces the net under the budget. The program's value is the net's only free port, so N.readback reads it.
const function evaluate(
	source: string,
	budget: number?
): (H.Report, Net)
	const b = B.new()
	program(Reader.read(source), b)
	const net = b:finish()

	return H.reduce(net, budget or H.DEFAULT_BUDGET), net
end

return {
	evaluate = evaluate,
}
