--!strict
-- THE REFERENCE INTERPRETER
--
-- A strict, sequential machine for a small functional language with native data: integers, cells (pairs), nil, closures and pins. Recursion comes from fixed points, not from a special form.
--
-- This is the spec for later prototypes: any implementation should agree with it on the examples in examples.luau.
--
-- The machine keeps its pending work on an explicit stack, so the depth of the Luau call stack does not grow with the program. Each step costs one unit of fuel, and a run that uses up its fuel reports "out_of_fuel" rather than hanging.
--
-- Integers are Luau numbers. They are exact from -MAX_INTEGER to MAX_INTEGER, and a result or a literal outside that range is an error.
--
-- Expressions, values, frames and outcomes are each a union of tables tagged by one field (op, kind, k and status). The builders at the bottom of this file are the only intended way to make expressions.

-- EXPRESSIONS

export type Expr =
	| QuoteExpr
	| NilExpr
	| VarExpr
	| LamExpr
	| PinExpr
	| CellExpr
	| HeadExpr
	| TailExpr
	| ForceExpr
	| IfExpr
	| ApplyExpr
	| PrimExpr
	| RaiseExpr

export type RaiseExpr = { op: "raise", e: Expr }
export type QuoteExpr = { op: "quote", value: number }
export type NilExpr = { op: "nil" }
-- index counts the binders between the variable and its binder, so 0 is the innermost.
export type VarExpr = { op: "var", index: number }
export type LamExpr = { op: "lam", body: Expr }
export type PinExpr = { op: "pin", e: Expr }
export type CellExpr = { op: "cell", head: Expr, tail: Expr }
export type HeadExpr = { op: "head", e: Expr }
export type TailExpr = { op: "tail", e: Expr }
export type ForceExpr = { op: "force", e: Expr }
export type IfExpr = { op: "if", c: Expr, t: Expr, e: Expr }
export type ApplyExpr = { op: "apply", f: Expr, arg: Expr }
-- b is absent for the unary primitive kind
export type PrimExpr = { op: "prim", name: string, a: Expr, b: Expr? }

-- VALUES

export type Nil = { kind: "nil" }
export type Cell = { kind: "cell", head: Value, tail: Value }
export type Closure = { kind: "closure", body: Expr, env: Binding? }
-- result is set once the pin has been forced. busy is set while it is being forced, so a pin that forces itself is caught.
export type Pin = { kind: "pin", expr: Expr, env: Binding?, busy: boolean, result: Value? }
export type Value = number | Nil | Cell | Closure | Pin

-- A linked list of variable bindings, innermost first.
export type Binding = { value: Value, rest: Binding? }

-- OUTCOMES

export type Outcome =
	| { status: "value", value: Value, steps: number }
	| { status: "error", message: string, steps: number }
	| { status: "out_of_fuel", steps: number }

-- The pending work of the machine. Each frame says what to do with the next value.
type Frame =
	| { k: "cell", expr: Expr, env: Binding? }
	| { k: "cellhead", head: Value }
	| { k: "head" | "tail" | "force" | "raise" }
	| { k: "if", t: Expr, e: Expr, env: Binding? }
	| { k: "apply", arg: Expr, env: Binding? }
	| { k: "argument", arg: Expr, env: Binding?, fn: Closure }
	| { k: "update", pin: Pin }
	| { k: "binary", name: string, b: Expr, env: Binding? }
	| { k: "second", name: string, first: Value }
	| { k: "kind" }

-- The frame for kind, which has no fields, so one table serves every use.
const KIND_FRAME = ({
	k = "kind",
} :: Frame)

const NIL: Nil = {
	kind = "nil",
}

-- The largest magnitude an integer may have: 2^53 - 1. Below 2^53 every integer is exact as a double, so a result at or past 2^53 may already have rounded (2^53 - 1 plus 1 gives 2^53 exactly), and it is an error rather than a wrong answer.
const MAX_INTEGER = 9007199254740991

const function fail(
	message: string
): never
	error(
		{
			vmError = message,
		}, 0
	)
end

const function lookup(
	env: Binding?,
	index: number
): Value
	local e = env
	local i = index

	while e do
		if i == 0 then
			return e.value
		end

		i -= 1
		e = e.rest
	end

	return fail("no variable at index " .. index)
end

-- The remainder of a divided by b, taking the sign of b, so that a = b * div + mod. Only for integers in range.
const function floored_mod(
	a: number,
	b: number
): number
	-- math.fmod is exact on doubles, and its result takes the sign of a. It is shifted by b when the signs differ.
	local r = math.fmod(a, b)

	if r ~= 0 and (r < 0) ~= (b < 0) then
		r += b
	end

	return r
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
	div = function(
		a,
		b
	)
		if b == 0 then
			return fail "div by zero"
		end

		-- Floored, and exact. math.fmod leaves a - fmod(a, b) as the truncated quotient times b, which has magnitude at most |a|, so it is exact on doubles. Adding b to the remainder could push a - r past 2^53 and round, so the floor is taken as a correction to the truncated quotient instead.
		local r = math.fmod(a, b)
		local q = (a - r) / b

		if r ~= 0 and (r < 0) ~= (b < 0) then
			q -= 1
		end

		return q
	end,
	mod = function(
		a,
		b
	)
		if b == 0 then
			return fail "mod by zero"
		end

		return floored_mod(a, b)
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

const function binary(
	name: string,
	a: Value,
	b: Value
): number
	const f = BINARY[name]

	if not f then
		return fail("unknown operation " .. name)
	end

	if type(a) ~= "number" or type(b) ~= "number" then
		return fail(name .. " needs integers")
	end

	const result = f(a, b)

	if result > MAX_INTEGER or result < -MAX_INTEGER then
		return fail(name .. " result is out of range")
	end

	-- Zero is written as 0, not -0, so that it prints the same way whatever produced it.
	if result == 0 then
		return 0
	end

	return result
end

-- The kind of a value: 0 integer, 1 nil, 2 cell, 3 function, 4 pin.
const function kindOf(
	v: Value
): number
	if type(v) == "number" then
		return 0
	end

	if v == NIL then
		return 1
	end

	if v.kind == "cell" then
		return 2
	end

	if v.kind == "closure" then
		return 3
	end

	return 4
end

-- The message of a raised value: its bytes, if it is a list of integers from 0 to 255, and otherwise its printed form. Set once show is defined, below.
local raisedText: (v: Value) -> string

-- Runs a program with a budget of steps. The result is always one of the outcomes above.
const function run(
	program: Expr,
	fuel: number
): Outcome
	local stack: { Frame } = {}
	local depth = 0
	local steps = 0

	const function push(
		frame: Frame
	)
		depth += 1
		stack[depth] = frame
	end

	const function loop(): Outcome
		local expr: Expr = program
		local env: Binding? = nil
		local value: Value = NIL
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
				if expr.op == "quote" then
					value = expr.value
					returning = true
				elseif expr.op == "nil" then
					value = NIL
					returning = true
				elseif expr.op == "var" then
					value = lookup(env, expr.index)
					returning = true
				elseif expr.op == "lam" then
					value = {
						kind = "closure",
						body = expr.body,
						env = env,
					}
					returning = true
				elseif expr.op == "pin" then
					value = {
						kind = "pin",
						expr = expr.e,
						env = env,
						busy = false,
					}
					returning = true
				elseif expr.op == "cell" then
					push {
						k = "cell",
						expr = expr.tail,
						env = env,
					}
					expr = expr.head
				elseif expr.op == "head" or expr.op == "tail" or expr.op == "force" or expr.op == "raise" then
					push {
						k = expr.op,
					}
					expr = expr.e
				elseif expr.op == "if" then
					push {
						k = "if",
						t = expr.t,
						e = expr.e,
						env = env,
					}
					expr = expr.c
				elseif expr.op == "apply" then
					push {
						k = "apply",
						arg = expr.arg,
						env = env,
					}
					expr = expr.f
				else
					-- The only expression left is a primitive.
					if expr.b == nil then
						push(KIND_FRAME)
					else
						push {
							k = "binary",
							name = expr.name,
							b = expr.b,
							env = env,
						}
					end

					expr = expr.a
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

				if frame.k == "cell" then
					push {
						k = "cellhead",
						head = value,
					}
					expr = frame.expr
					env = frame.env
					returning = false
				elseif frame.k == "cellhead" then
					value = {
						kind = "cell",
						head = frame.head,
						tail = value,
					}
				elseif frame.k == "head" or frame.k == "tail" then
					if type(value) ~= "table" or value.kind ~= "cell" then
						return fail(frame.k .. " of a non-cell")
					end

					value =
						if frame.k == "head" then
							value.head
						else
							value.tail
				elseif frame.k == "if" then
					if type(value) ~= "number" then
						return fail "if needs an integer condition"
					end

					expr =
						if value ~= 0 then
							frame.t
						else
							frame.e
					env = frame.env
					returning = false
				elseif frame.k == "apply" then
					if type(value) ~= "table" or value.kind ~= "closure" then
						return fail "applying a non-function"
					end

					push {
						k = "argument",
						arg = frame.arg,
						env = frame.env,
						fn = value,
					}
					expr = frame.arg
					env = frame.env
					returning = false
				elseif frame.k == "argument" then
					expr = frame.fn.body
					env = {
						value = value,
						rest = frame.fn.env,
					}
					returning = false
				elseif frame.k == "force" then
					if type(value) ~= "table" or value.kind ~= "pin" then
						return fail "forcing a non-pin"
					end

					const result = value.result

					if result then
						value = result
					else
						if value.busy then
							return fail "a pin forced itself"
						end

						const pin: Pin = value
						pin.busy = true
						push {
							k = "update",
							pin = pin,
						}
						expr = pin.expr
						env = pin.env
						returning = false
					end
				elseif frame.k == "update" then
					frame.pin.result = value
					frame.pin.busy = false
				elseif frame.k == "binary" then
					push {
						k = "second",
						name = frame.name,
						first = value,
					}
					expr = frame.b
					env = frame.env
					returning = false
				elseif frame.k == "second" then
					value = binary(frame.name, frame.first, value)
				elseif frame.k == "raise" then
					return fail(raisedText(value))
				else
					-- The only frame left is kind.
					value = kindOf(value)
				end
			end
		end
	end

	-- fail raises a table with a vmError field. Anything else is a bug in the machine, so it is passed on unchanged.
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
const function show(
	v: Value
): string
	if type(v) == "number" then
		return tostring(v)
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

	local parts: { string } = {}
	local cur: Value = v

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

raisedText = function(
	v: Value
): string
	local bytes: { string } = {}
	local cur = v

	while type(cur) == "table" and cur.kind == "cell" do
		const h = cur.head

		if type(h) ~= "number" or h < 0 or h > 255 or h ~= math.floor(h) then
			return show(v)
		end

		table.insert(bytes, string.char(h))
		cur = cur.tail
	end

	if cur ~= NIL then
		return show(v)
	end

	return table.concat(bytes)
end

-- BUILDERS

local M = {}
M.run = run
M.show = show
M.NIL = NIL
M.MAX_INTEGER = MAX_INTEGER

function M.int(
	n: number
): Expr
	if n > MAX_INTEGER or n < -MAX_INTEGER then
		error(string.format("integer %s is out of range", tostring(n)), 0)
	end

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

-- A variable, by its index: 0 is the innermost binder, 1 the one outside it, and so on.
function M.var(
	index: number
): Expr
	return {
		op = "var",
		index = index,
	}
end

-- A function of one parameter. The parameter is not named: variables refer to it by index.
function M.lam(
	body: Expr
): Expr
	return {
		op = "lam",
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

-- A primitive on integers: add, sub, mul, div, mod, lt, eq. div and mod are floored, and dividing by zero is an error. The unary primitive kind takes no b, and works on any value.
-- The name and the number of arguments are checked here, so a bad primitive fails when it is built, not when the machine reaches it.
function M.prim(
	name: string,
	a: Expr,
	b: Expr?
): Expr
	if name == "kind" then
		if b ~= nil then
			error("kind takes one argument, but was given two", 0)
		end
	elseif BINARY[name] == nil then
		error(string.format("unknown primitive %s", name), 0)
	elseif b == nil then
		error(string.format("%s takes two arguments, but was given one", name), 0)
	end

	return {
		op = "prim",
		name = name,
		a = a,
		b = b,
	}
end

-- Stops the run with an error whose message is the value of e: its bytes if it is a list of bytes, otherwise its printed form. The value is evaluated first, so the message can be built by the program.
function M.raise(
	e: Expr
): Expr
	return {
		op = "raise",
		e = e,
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
-- Recursive functions are written as M.app(M.fix, M.lam(M.lam(...))). The outer lambda binds the function itself, so inside the body of the inner one it is index 1.
-- The indices below are counted from each variable's own binder: inside λx, f is 1; inside λv, x is 1 and v is 0.
const inner = M.lam(M.app(M.var(1), M.lam(M.app(M.var(1), M.var(1), M.var(0)))))
M.fix = M.lam(M.app(inner, inner))

return M
