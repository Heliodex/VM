--!strict
-- THE REFERENCE INTERPRETER
--
-- A strict, sequential machine for a small functional language with native data: integers, cells (pairs), nil, closures and pins. Recursion comes from fixed points, not from a special form.
--
-- This is the spec for later prototypes: any implementation should agree with it on the examples in examples.luau.
--
-- The machine keeps its pending work on an explicit stack, so the depth of the Luau call stack does not grow with the program. Each step costs one unit of fuel, and a run that uses up its fuel reports "out_of_fuel" rather than hanging.
--
-- Numbers are Luau numbers, so integers are exact only up to 2^53.
--
-- Expressions are plain tables with an op field. The builders at the bottom of this file are the only intended way to make them.

type Expr = {
	[string]: any,
}
type Outcome = {
	status: string,
	value: any?,
	message: string?,
	steps: number,
}
const NIL = {
	kind = "nil",
}

local function fail(
	message: string
): never
	error(
		{
			vmError = message,
		}, 0
	)
end

local function lookup(
	env: any,
	name: string
): any
	local e = env

	while e do
		if e.name == name then
			return e.value
		end

		e = e.rest
	end

	return fail("unbound variable " .. name)
end

const BINARY: {
	[string]: (number, number) -> number,
} = {
	add = function(
		a,
		b
	)
		return a + b
	end,
	sub = function(
		a,
		b
	)
		return a - b
	end,
	mul = function(
		a,
		b
	)
		return a * b
	end,
	lt = function(
		a,
		b
	)
		return
			if a < b then
				1
			else
				0
	end,
	eq = function(
		a,
		b
	)
		return
			if a == b then
				1
			else
				0
	end,
}

local function integer(
	v: any,
	name: string
): number
	if type(v) ~= "number" then
		fail(name .. " needs integers")
	end

	return v
end

local function binary(
	name: string,
	a: any,
	b: any
): number
	const f = BINARY[name]

	if not f then
		fail("unknown operation " .. name)
	end

	return f(integer(a, name), integer(b, name))
end

local function unary(
	name: string,
	v: any
): number
	if name == "isnil" then
		return
			if v == NIL then
				1
			else
				0
	end

	return fail("unknown operation " .. name)
end

-- Runs a program with a budget of steps. The result is always one of:
--   status "value" with the value,
--   status "error" with a message (a type error, an unbound name, and so on),
--   status "out_of_fuel".
local function run(
	program: Expr,
	fuel: number
): Outcome
	local stack: { any } = {}
	local depth = 0
	local steps = 0

	local function push(
		frame: any
	)
		depth += 1
		stack[depth] = frame
	end

	local function loop(): Outcome
		local expr: any = program
		local env: any = nil
		local value: any = nil
		local returning = false

		while true do
			if steps >= fuel then
				return {
					status = "out_of_fuel",
					steps = steps,
				}
			end

			steps += 1

			if not returning then
				-- Evaluate expr in env. Either finish with a value, or push a frame and move to a subexpression.
				const op = expr.op

				if op == "quote" then
					value = expr.value
					returning = true
				elseif op == "nil" then
					value = NIL
					returning = true
				elseif op == "var" then
					value = lookup(env, expr.name)
					returning = true
				elseif op == "lam" then
					value = {
						kind = "closure",
						param = expr.param,
						body = expr.body,
						env = env,
					}
					returning = true
				elseif op == "pin" then
					value = {
						kind = "pin",
						expr = expr.e,
						env = env,
						forced = false,
						busy = false,
					}
					returning = true
				elseif op == "cell" then
					push {
						k = "cell",
						expr = expr.tail,
						env = env,
					}
					expr = expr.head
				elseif op == "head" or op == "tail" or op == "force" then
					push {
						k = op,
					}
					expr = expr.e
				elseif op == "if" then
					push {
						k = "if",
						t = expr.t,
						e = expr.e,
						env = env,
					}
					expr = expr.c
				elseif op == "apply" then
					push {
						k = "apply",
						arg = expr.arg,
						env = env,
					}
					expr = expr.f
				elseif op == "prim" then
					if expr.b == nil then
						push {
							k = "unary",
							name = expr.name,
						}
					else
						push {
							k = "binary",
							name = expr.name,
							b = expr.b,
							env = env,
						}
					end

					expr = expr.a
				else
					fail("unknown expression " .. tostring(op))
				end
			else
				-- Hand value to the innermost frame.
				if depth == 0 then
					return {
						status = "value",
						value = value,
						steps = steps,
					}
				end

				const frame = stack[depth]
				stack[depth] = nil
				depth -= 1
				const k = frame.k

				if k == "cell" then
					push {
						k = "cellhead",
						head = value,
					}
					expr = frame.expr
					env = frame.env
					returning = false
				elseif k == "cellhead" then
					value = {
						kind = "cell",
						head = frame.head,
						tail = value,
					}
				elseif k == "head" or k == "tail" then
					if type(value) ~= "table" or value.kind ~= "cell" then
						fail(k .. " of a non-cell")
					end

					value =
						if k == "head" then
							value.head
						else
							value.tail
				elseif k == "if" then
					if type(value) ~= "number" then
						fail "if needs an integer condition"
					end

					expr =
						if value ~= 0 then
							frame.t
						else
							frame.e
					env = frame.env
					returning = false
				elseif k == "apply" then
					push {
						k = "argument",
						fn = value,
					}
					expr = frame.arg
					env = frame.env
					returning = false
				elseif k == "argument" then
					const fn = frame.fn

					if type(fn) ~= "table" or fn.kind ~= "closure" then
						fail "applying a non-function"
					end

					expr = fn.body
					env = {
						name = fn.param,
						value = value,
						rest = fn.env,
					}
					returning = false
				elseif k == "force" then
					if type(value) ~= "table" or value.kind ~= "pin" then
						fail "forcing a non-pin"
					end

					if value.forced then
						value = value.value
					else
						if value.busy then
							fail "a pin forced itself"
						end

						value.busy = true
						push {
							k = "update",
							pin = value,
						}
						expr = value.expr
						env = value.env
						returning = false
					end
				elseif k == "update" then
					frame.pin.value = value
					frame.pin.forced = true
					frame.pin.busy = false
				elseif k == "binary" then
					push {
						k = "second",
						name = frame.name,
						first = value,
					}
					expr = frame.b
					env = frame.env
					returning = false
				elseif k == "second" then
					value = binary(frame.name, frame.first, value)
				elseif k == "unary" then
					value = unary(frame.name, value)
				else
					fail("unknown continuation " .. tostring(k))
	end end end end

	const ok, result: any = pcall(loop)

	if ok then
		return result
	end

	if type(result) == "table" and result.vmError then
		return {
			status = "error",
			message = result.vmError,
			steps = steps,
		}
	end

	error(result, 0)
end

-- Prints a value the way the examples write expected results: integers as numbers, lists as (1 2 3), improper pairs as (1 . 2).
local function show(
	v: any
): string
	if type(v) == "number" then
		return tostring(v)
	end

	if type(v) ~= "table" then
		return "?"
	end

	if v == NIL then
		return "()"
	end

	if v.kind == "closure" then
		return "<fn>"
	end

	if v.kind == "pin" then
		return "<pin>"
	end

	if v.kind == "cell" then
		local parts: { string } = {}
		local cur = v

		while type(cur) == "table" and cur.kind == "cell" do
			table.insert(parts, show(cur.head))
			cur = cur.tail
		end

		if cur ~= NIL then
			table.insert(parts, ".")
			table.insert(parts, show(cur))
		end

		return "(" .. table.concat(parts, " ") .. ")"
	end

	return "?"
end

-- BUILDERS
local M = {}
M.run = run
M.show = show

function M.int(
	n: number
): Expr
	return {
		op = "quote",
		value = n,
	}
end

function M.nilv(): Expr
	return {
		op = "nil",
	}
end

function M.var(
	name: string
): Expr
	return {
		op = "var",
		name = name,
	}
end

function M.lam(
	param: string,
	body: Expr
): Expr
	return {
		op = "lam",
		param = param,
		body = body,
	}
end

-- Curried application: app(f, a, b) is app(app(f, a), b).
function M.app(
	f: Expr,
	...: Expr
): Expr
	local e = f

	for _, arg in {
		...,
	} do
		e = {
			op = "apply",
			f = e,
			arg = arg,
		}
	end

	return e
end

function M.cell(
	head: Expr,
	tail: Expr
): Expr
	return {
		op = "cell",
		head = head,
		tail = tail,
	}
end

function M.head(
	e: Expr
): Expr
	return {
		op = "head",
		e = e,
	}
end

function M.tail(
	e: Expr
): Expr
	return {
		op = "tail",
		e = e,
	}
end

-- Evaluates t if c is nonzero, otherwise e. Only the branch taken is evaluated.
function M.ite(
	c: Expr,
	t: Expr,
	e: Expr
): Expr
	return {
		op = "if",
		c = c,
		t = t,
		e = e,
	}
end

-- Suspends e. It is not evaluated until forced, and is evaluated at most once.
function M.pin(
	e: Expr
): Expr
	return {
		op = "pin",
		e = e,
	}
end

function M.force(
	e: Expr
): Expr
	return {
		op = "force",
		e = e,
	}
end

-- A primitive on integers: add, sub, mul, lt, eq. The unary primitive isnil takes no b.
function M.prim(
	name: string,
	a: Expr,
	b: Expr?
): Expr
	return {
		op = "prim",
		name = name,
		a = a,
		b = b,
	}
end

-- A proper list of expressions, ending in nil.
function M.list(
	items: { Expr }
): Expr
	local e = M.nilv()

	for i = #items, 1, -1 do
		e = M.cell(items[i], e)
	end

	return e
end

-- The fixed-point combinator for a strict language, Z = λf. (λx. f (λv. x x v)) (λx. f (λv. x x v)).
-- Recursive functions are written as M.app(M.fix, M.lam("rec", M.lam(...))), where rec stands for the function itself.
const inner = M.lam("x", M.app(M.var "f", M.lam("v", M.app(M.var "x", M.var "x", M.var "v"))))
M.fix = M.lam("f", M.app(inner, inner))

return M
