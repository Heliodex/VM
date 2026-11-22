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
	| VarExpr
	| LamExpr
	| PinExpr
	| CellExpr
	| IndexExpr
	| ForceExpr
	| IfExpr
	| ApplyExpr
	| PrimExpr
	| ConstructExpr
	| TagofExpr
	| PayloadExpr
-- A quoted value is data: an integer, or nil. nil is quoted, so there is no expression for it of its own.
export type QuoteExpr = { op: "quote"; value: Value }
-- index counts the binders between the variable and its binder, so 0 is the innermost.
export type VarExpr = { op: "var"; index: number }
export type LamExpr = { op: "lam"; body: Expr }
export type PinExpr = { op: "pin"; e: Expr }
export type CellExpr = { op: "cell"; head: Expr; tail: Expr }
-- The part of e that an address names. n is at least 2: its binary digits after the leading 1 are the steps, from the first step to the last, with 0 for head and 1 for tail. So 2 is head, 3 is tail, 4 is head of head, and 5 is tail of head.
export type IndexExpr = { op: "index"; n: number; e: Expr }
export type ForceExpr = { op: "force"; e: Expr }
export type IfExpr = { op: "if"; c: Expr; t: Expr; e: Expr }
export type ApplyExpr = { op: "apply"; f: Expr; arg: Expr }
-- The primitive is its tag, from primitives.luau. b is absent for the unary primitive kind
export type PrimExpr = { op: "prim"; tag: number; a: Expr; b: Expr? }
-- A constructor is a tag, a whole number from 0 up, with one payload. tagof gives the tag of a constructor, or -1 for any other value. payload gives the payload of a constructor, and is an error for any other value. A match is a tagof test, then a payload.
export type ConstructExpr = { op: "construct"; tag: number; e: Expr }
export type TagofExpr = { op: "tagof"; e: Expr }
export type PayloadExpr = { op: "payload"; e: Expr }
-- VALUES
export type Nil = { kind: "nil" }
export type Cell = { kind: "cell"; head: Value; tail: Value }
export type Closure = { kind: "closure"; body: Expr; env: Binding?; id: number? }
-- result is set once the pin has been forced. busy is set while it is being forced, so a pin that forces itself is caught.
export type Pin = { kind: "pin"; expr: Expr; env: Binding?; busy: boolean; result: Value?; id: number? }
export type Con = { kind: "con"; tag: number; payload: Value }
export type Value = number | Nil | Cell | Closure | Pin | Con
-- A linked list of variable bindings, innermost first.
export type Binding = { value: Value; rest: Binding? }
-- OUTCOMES
export type Outcome =
	| { status: "value"; value: Value; steps: number }
	| { status: "error"; message: string; steps: number }
	| { status: "out_of_fuel"; steps: number }
-- The pending work of the machine. Each frame says what to do with the next value.
type Frame =
	| { k: "cell"; expr: Expr; env: Binding?; head: Value? }
	| { k: "force"; pin: Pin? }
	| { k: "construct"; tag: number }
	| { k: "tagof" }
	| { k: "payload" }
	| { k: "index"; n: number }
	| { k: "if"; t: Expr; e: Expr; env: Binding? }
	| { k: "apply"; arg: Expr; env: Binding?; fn: Closure? }
	| { k: "prim"; tag: number; b: Expr?; env: Binding?; first: Value? }
const Primitives = require "./primitives"
const NIL: Nil = {
	kind = "nil",
}
-- The largest magnitude an integer may have: 2^53 - 1. Below 2^53 every integer is exact as a double, so a result at or past 2^53 may already have rounded (2^53 - 1 plus 1 gives 2^53 exactly), and it is an error rather than a wrong answer.
const MAX_INTEGER = 9007199254740991

-- A failure ends the run with an error outcome. It is returned, not thrown, so the loop returns it like any other outcome.
const function failed(message: string, steps: number): Outcome
	return {
		status = "error",
		message = message,
		steps = steps,
	}
end

const function lookup(env: Binding?, index: number): Value?
	local e = env
	local i = index

	while e do
		if i == 0 then
			return e.value
		end

		i -= 1
		e = e.rest
	end

	return nil
end

const function binary(tag: number, a: Value, b: Value): (number?, string?)
	const row = Primitives.BY_TAG[tag]

	if row == nil or row.operation == nil then
		return nil, "unknown operation " .. tostring(tag)
	end

	const name = row.name

	if type(a) ~= "number" or type(b) ~= "number" then
		return nil, name .. " needs integers"
	end

	const operation = row.operation :: (number, number) -> (number?, string?)
	const result, message = operation(a, b)

	if message ~= nil then
		return nil, message
	end

	const value = result :: number

	if value > MAX_INTEGER or value < -MAX_INTEGER then
		return nil, name .. " result is out of range"
	end

	-- Zero is written as 0, not -0, so that it prints the same way whatever produced it.
	if value == 0 then
		return 0, nil
	end

	return value, nil
end

-- The kind of a value: 0 integer, 1 nil, 2 cell, 3 function, 4 pin.
const function kindOf(v: Value): number
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

	if v.kind == "con" then
		return 5
	end

	return 4
end

-- Runs a program with a budget of steps. The result is always one of the outcomes above.
-- initialEnv is the environment the program starts in, which is empty unless given. It lets a host pass in a value that has no expression form, such as a function, as a variable.
-- THE FAST MACHINE
--
-- The same machine as runReference, with the same steps, fuel and outcomes, on a different layout. An expression is compiled once into an arena of integers: one opcode, and up to three child nodes, per node. The stack is parallel arrays (kind, node, environment, data), not a table per frame. A closure or a pin keeps the node of its body, so entering it is a read, not a lookup.
const OP_QUOTE = 1
const OP_VAR = 2
const OP_LAM = 3
const OP_PIN = 4
const OP_CELL = 5
const OP_INDEX = 6
const OP_FORCE = 7
const OP_IF = 8
const OP_APPLY = 9
const OP_PRIM = 10
const OP_CONSTRUCT = 11
const OP_TAGOF = 12
const OP_PAYLOAD = 13
-- Frame kinds.
const FR_CELL = 1
const FR_INDEX = 2
const FR_IF = 3
const FR_APPLY = 4
const FR_CONSTRUCT = 5
const FR_TAGOF = 6
const FR_PAYLOAD = 7
const FR_FORCE = 8
const FR_PRIM = 9
-- The arena. Node 0 is not used, so a child of 0 means none. op, a, b and c are a node's opcode and children; n is a var index, a tag or an index; val is a quoted value, or the body or expression of a lam or pin.
local arenaOp: { number } = {}
local arenaA: { number } = {}
local arenaB: { number } = {}
local arenaC: { number } = {}
local arenaN: { number } = {}
local arenaVal: { any } = {}
local arenaCount = 0
-- The node of each expression already compiled, so a shared expression, or a closure's body, is compiled once.
local nodeOfExpr: { [any]: number } = setmetatable({}, { __mode = "k" })
local nodeOf: (Expr) -> number

local function newNode(): number
	arenaCount += 1

	return arenaCount
end

nodeOf = function(e: Expr): number
	const known = nodeOfExpr[e]

	if known ~= nil then
		return known
	end

	const id = newNode()

	if e.op == "quote" then
		arenaOp[id] = OP_QUOTE
		arenaVal[id] = e.value
	elseif e.op == "var" then
		arenaOp[id] = OP_VAR
		arenaN[id] = e.index
	elseif e.op == "lam" then
		arenaOp[id] = OP_LAM
		arenaVal[id] = e.body
		arenaA[id] = nodeOf(e.body)
	elseif e.op == "pin" then
		arenaOp[id] = OP_PIN
		arenaVal[id] = e.e
		arenaA[id] = nodeOf(e.e)
	elseif e.op == "cell" then
		arenaOp[id] = OP_CELL
		arenaA[id] = nodeOf(e.head)
		arenaB[id] = nodeOf(e.tail)
	elseif e.op == "index" then
		arenaOp[id] = OP_INDEX
		arenaN[id] = e.n
		arenaA[id] = nodeOf(e.e)
	elseif e.op == "force" then
		arenaOp[id] = OP_FORCE
		arenaA[id] = nodeOf(e.e)
	elseif e.op == "if" then
		arenaOp[id] = OP_IF
		arenaA[id] = nodeOf(e.c)
		arenaB[id] = nodeOf(e.t)
		arenaC[id] = nodeOf(e.e)
	elseif e.op == "apply" then
		arenaOp[id] = OP_APPLY
		arenaA[id] = nodeOf(e.f)
		arenaB[id] = nodeOf(e.arg)
	elseif e.op == "construct" then
		arenaOp[id] = OP_CONSTRUCT
		arenaN[id] = e.tag
		arenaA[id] = nodeOf(e.e)
	elseif e.op == "tagof" then
		arenaOp[id] = OP_TAGOF
		arenaA[id] = nodeOf(e.e)
	elseif e.op == "payload" then
		arenaOp[id] = OP_PAYLOAD
		arenaA[id] = nodeOf(e.e)
	else
		-- A primitive, the only expression left.
		arenaOp[id] = OP_PRIM
		arenaN[id] = (e :: PrimExpr).tag
		arenaA[id] = nodeOf((e :: PrimExpr).a)
		arenaB[id] =
			if (e :: PrimExpr).b ~= nil then
				nodeOf((e :: PrimExpr).b :: Expr)
			else
				0
	end

	nodeOfExpr[e] = id

	return id
end

const function run(program: Expr, fuel: number, initialEnv: Binding?): Outcome
	const root = nodeOf(program)
	-- The stack: kind, node, environment and data of each frame. The data is the first operand of a primitive, the function of an application, the head of a cell, the pin being forced, or the value waiting for a pin's result.
	local frameKind: { number } = {}
	local frameNode: { number } = {}
	local frameEnv: { any } = {}
	local frameData: { any } = {}
	local depth = 0
	local steps = 0
	local node = root
	local env: Binding? = initialEnv
	local value: Value = NIL
	local returning = false

	const function push(kind: number, at: number, e: Binding?, data: any)
		depth += 1
		frameKind[depth] = kind
		frameNode[depth] = at
		frameEnv[depth] = e
		frameData[depth] = data
	end

	while true do
		if steps >= fuel then
			return {
				status = "out_of_fuel",
				steps = steps,
			}
		end

		steps += 1

		if not returning then
			const op = arenaOp[node]

			if op == OP_VAR then
				const found = lookup(env, arenaN[node])

				if found == nil then
					return failed("no variable at index " .. arenaN[node], steps)
				end

				value = found
				returning = true
			elseif op == OP_QUOTE then
				value = arenaVal[node]
				returning = true
			elseif op == OP_APPLY then
				push(FR_APPLY, node, env, nil)
				node = arenaA[node]
			elseif op == OP_IF then
				push(FR_IF, node, env, nil)
				node = arenaA[node]
			elseif op == OP_CELL then
				push(FR_CELL, node, env, nil)
				node = arenaA[node]
			elseif op == OP_PRIM then
				push(FR_PRIM, node, env, nil)
				node = arenaA[node]
			elseif op == OP_LAM then
				value = {
					kind = "closure",
					body = arenaVal[node],
					env = env,
					id = arenaA[node],
				}
				returning = true
			elseif op == OP_PIN then
				value = {
					kind = "pin",
					expr = arenaVal[node],
					env = env,
					busy = false,
					id = arenaA[node],
				}
				returning = true
			elseif op == OP_FORCE then
				push(FR_FORCE, node, nil, nil)
				node = arenaA[node]
			elseif op == OP_CONSTRUCT then
				push(FR_CONSTRUCT, node, nil, nil)
				node = arenaA[node]
			elseif op == OP_TAGOF then
				push(FR_TAGOF, node, nil, nil)
				node = arenaA[node]
			elseif op == OP_PAYLOAD then
				push(FR_PAYLOAD, node, nil, nil)
				node = arenaA[node]
			else
				-- OP_INDEX, the last opcode.
				push(FR_INDEX, node, nil, nil)
				node = arenaA[node]
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

			const kind = frameKind[depth]
			const at = frameNode[depth]
			const frameEnvHere = frameEnv[depth]
			const data = frameData[depth]
			frameEnv[depth] = nil
			frameData[depth] = nil
			depth -= 1

			if kind == FR_CELL then
				if data == nil then
					-- The head is done. The frame waits again, now for the tail.
					push(FR_CELL, at, frameEnvHere, value)
					node = arenaB[at]
					env = frameEnvHere
					returning = false
				else
					value = {
						kind = "cell",
						head = data,
						tail = value,
					}
				end
			elseif kind == FR_IF then
				if type(value) ~= "number" then
					return failed("if needs an integer condition", steps)
				end

				node =
					if value ~= 0 then
						arenaB[at]
					else
						arenaC[at]
				env = frameEnvHere
				returning = false
			elseif kind == FR_APPLY then
				if data == nil then
					-- The function is done. The frame waits again, now for the argument.
					if type(value) ~= "table" or value.kind ~= "closure" then
						return failed("applying a non-function", steps)
					end

					push(FR_APPLY, at, frameEnvHere, value)
					node = arenaB[at]
					env = frameEnvHere
					returning = false
				else
					const fn: Closure = data
					node = fn.id or nodeOf(fn.body)
					env = {
						value = value,
						rest = fn.env,
					}
					returning = false
				end
			elseif kind == FR_PRIM then
				if arenaB[at] ~= 0 and data == nil then
					-- The first operand is done. The frame waits again, now for the second.
					push(FR_PRIM, at, frameEnvHere, value)
					node = arenaB[at]
					env = frameEnvHere
					returning = false
				elseif arenaB[at] == 0 then
					-- The only unary primitive is kind.
					value = kindOf(value)
				else
					const result, message = binary(arenaN[at], data :: Value, value)

					if message ~= nil then
						return failed(message, steps)
					end

					value = result :: number
				end
			elseif kind == FR_CONSTRUCT then
				value = {
					kind = "con",
					tag = arenaN[at],
					payload = value,
				}
			elseif kind == FR_TAGOF then
				value =
					if type(value) == "table" and value.kind == "con" then
						value.tag
					else
						-1
			elseif kind == FR_PAYLOAD then
				if type(value) ~= "table" or value.kind ~= "con" then
					return failed("a payload of a non-constructor", steps)
				end

				value = value.payload
			elseif kind == FR_FORCE then
				if data ~= nil then
					-- The pin's expression is done, so its value is the pin's result.
					const done: Pin = data :: Pin
					done.result = value
					done.busy = false
				else
					if type(value) ~= "table" or value.kind ~= "pin" then
						return failed("forcing a non-pin", steps)
					end

					const pin: Pin = value

					if pin.result then
						value = pin.result :: Value
					else
						if pin.busy then
							return failed("a pin forced itself", steps)
						end

						pin.busy = true
						push(FR_FORCE, at, nil, pin)
						node = pin.id or nodeOf(pin.expr)
						env = pin.env
						returning = false
					end
				end
			else
				-- FR_INDEX: the steps of the address, low bit first. The low bit is the last step, so the steps are applied from the high end.
				local path: { number } = {}
				local n = arenaN[at]

				while n > 1 do
					table.insert(path, n % 2)
					n = math.floor(n / 2)
				end

				for i = #path, 1, -1 do
					if type(value) ~= "table" or value.kind ~= "cell" then
						const side =
							if path[i] == 0 then
								"head"
							else
								"tail"

						return failed(side .. " of a non-cell", steps)
					end

					value =
						if path[i] == 0 then
							value.head
						else
							value.tail
				end
			end
		end
	end
end

const function runReference(program: Expr, fuel: number, initialEnv: Binding?): Outcome
	local stack: { Frame } = {}
	local depth = 0
	local steps = 0

	const function push(frame: Frame)
		depth += 1
		stack[depth] = frame
	end

	const function loop(): Outcome
		local expr: Expr = program
		local env: Binding? = initialEnv
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
				elseif expr.op == "var" then
					const found = lookup(env, expr.index)

					if found == nil then
						return failed("no variable at index " .. expr.index, steps)
					end

					value = found
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
				elseif expr.op == "force" then
					push {
						k = "force",
					}
					expr = expr.e
				elseif expr.op == "construct" then
					push {
						k = "construct",
						tag = expr.tag,
					}
					expr = expr.e
				elseif expr.op == "tagof" then
					push {
						k = "tagof",
					}
					expr = expr.e
				elseif expr.op == "payload" then
					push {
						k = "payload",
					}
					expr = expr.e
				elseif expr.op == "index" then
					push {
						k = "index",
						n = expr.n,
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
					-- The only expression left is a primitive: its first operand is evaluated, then its second if it has one.
					push {
						k = "prim",
						tag = expr.tag,
						b = expr.b,
						env = env,
					}
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
					if frame.head == nil then
						-- The head is done. The frame waits again, now for the tail.
						frame.head = value
						push(frame)
						expr = frame.expr
						env = frame.env
						returning = false
					else
						value = {
							kind = "cell",
							head = frame.head,
							tail = value,
						}
					end
				elseif frame.k == "index" then
					-- The steps of the address, low bit first. The low bit is the last step, so the steps are applied from the high end.
					local path: { number } = {}
					local n = frame.n

					while n > 1 do
						table.insert(path, n % 2)
						n = math.floor(n / 2)
					end

					for i = #path, 1, -1 do
						if type(value) ~= "table" or value.kind ~= "cell" then
							local side =
								if path[i] == 0 then
									"head"
								else
									"tail"

							return failed(side .. " of a non-cell", steps)
						end

						value =
							if path[i] == 0 then
								value.head
							else
								value.tail
					end
				elseif frame.k == "if" then
					if type(value) ~= "number" then
						return failed("if needs an integer condition", steps)
					end

					expr =
						if value ~= 0 then
							frame.t
						else
							frame.e
					env = frame.env
					returning = false
				elseif frame.k == "apply" then
					if frame.fn == nil then
						-- The function is done. The frame waits again, now for the argument.
						if type(value) ~= "table" or value.kind ~= "closure" then
							return failed("applying a non-function", steps)
						end

						frame.fn = value :: Closure
						push(frame)
						expr = frame.arg
						env = frame.env
						returning = false
					else
						expr = frame.fn.body
						env = {
							value = value,
							rest = frame.fn.env,
						}
						returning = false
					end
				elseif frame.k == "construct" then
					value = {
						kind = "con",
						tag = frame.tag,
						payload = value,
					}
				elseif frame.k == "tagof" then
					value =
						if type(value) == "table" and value.kind == "con" then
							value.tag
						else
							-1
				elseif frame.k == "payload" then
					if type(value) ~= "table" or value.kind ~= "con" then
						return failed("a payload of a non-constructor", steps)
					end

					value = value.payload
				elseif frame.k == "force" then
					if frame.pin ~= nil then
						-- The pin's expression is done, so its value is the pin's result.
						frame.pin.result = value
						frame.pin.busy = false
					else
						if type(value) ~= "table" or value.kind ~= "pin" then
							return failed("forcing a non-pin", steps)
						end

						const result = value.result

						if result then
							value = result
						else
							if value.busy then
								return failed("a pin forced itself", steps)
							end

							const pin: Pin = value
							pin.busy = true
							frame.pin = pin
							push(frame)
							expr = pin.expr
							env = pin.env
							returning = false
						end
					end
				elseif frame.k == "prim" then
					if frame.b ~= nil and frame.first == nil then
						-- The first operand is done. The frame waits again, now for the second.
						frame.first = value
						push(frame)
						expr = frame.b
						env = frame.env
						returning = false
					elseif frame.b == nil then
						-- The only unary primitive is kind.
						value = kindOf(value)
					else
						const result, message = binary(frame.tag, frame.first :: Value, value)

						if message ~= nil then
							return failed(message, steps)
						end

						value = result :: number
					end
				end
			end
		end
	end

	return loop()
end

-- Prints a value the way the examples write expected results: integers as numbers, lists as (1 2 3), improper pairs as (1 . 2).
const function show(v: Value): string
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

	if v.kind == "con" then
		return `<con {tostring(v.tag)} {show(v.payload)}>`
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

-- BUILDERS
local M = {}
M.run = run
M.runReference = runReference
M.show = show
M.NIL = NIL
M.MAX_INTEGER = MAX_INTEGER

function M.int(n: number): Expr
	if n > MAX_INTEGER or n < -MAX_INTEGER then
		error(string.format("integer %s is out of range", tostring(n)), 0)
	end

	return {
		op = "quote",
		value = n,
	}
end

-- nil, as a quoted value.
function M.nilv(): Expr
	return {
		op = "quote",
		value = NIL,
	}
end

-- A variable, by its index: 0 is the innermost binder, 1 the one outside it, and so on.
function M.var(index: number): Expr
	return {
		op = "var",
		index = index,
	}
end

-- A function of one parameter. The parameter is not named: variables refer to it by index.
function M.lam(body: Expr): Expr
	return {
		op = "lam",
		body = body,
	}
end

-- Curried application: app(f, a, b) is app(app(f, a), b).
function M.app(f: Expr, ...: Expr): Expr
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

function M.cell(head: Expr, tail: Expr): Expr
	return {
		op = "cell",
		head = head,
		tail = tail,
	}
end

-- The part of e that the address n names. See IndexExpr.
function M.index(n: number, e: Expr): Expr
	if n < 2 or n > MAX_INTEGER or n ~= math.floor(n) then
		error(string.format("an index is a whole number from 2 up, not %s", tostring(n)), 0)
	end

	return {
		op = "index",
		n = n,
		e = e,
	}
end

-- The head (side 0) or tail (side 1) of e. The head or tail of an index is the same index with one more step, so a chain of them is one step, as long as the address stays in range.
local function step(side: number, e: Expr): Expr
	if e.op == "index" and e.n < 2 ^ 50 then
		return M.index(2 * e.n + side, e.e)
	end

	return M.index(2 + side, e)
end

function M.head(e: Expr): Expr
	return step(0, e)
end

function M.tail(e: Expr): Expr
	return step(1, e)
end

-- Evaluates t if c is nonzero, otherwise e. Only the branch taken is evaluated.
function M.ite(c: Expr, t: Expr, e: Expr): Expr
	return {
		op = "if",
		c = c,
		t = t,
		e = e,
	}
end

-- Suspends e. It is not evaluated until forced, and is evaluated at most once.
function M.pin(e: Expr): Expr
	return {
		op = "pin",
		e = e,
	}
end

function M.force(e: Expr): Expr
	return {
		op = "force",
		e = e,
	}
end

-- A constructor with the given tag, from 0 up, and payload e.
function M.construct(tag: number, e: Expr): Expr
	if tag < 0 or tag > MAX_INTEGER or tag ~= math.floor(tag) then
		error(string.format("a constructor tag is a whole number from 0 up, not %s", tostring(tag)), 0)
	end

	return {
		op = "construct",
		tag = tag,
		e = e,
	}
end

-- The tag of the constructor e gives, or -1 for any other value.
function M.tagof(e: Expr): Expr
	return {
		op = "tagof",
		e = e,
	}
end

-- The payload of the constructor e gives. It is an error for any other value.
function M.payload(e: Expr): Expr
	return {
		op = "payload",
		e = e,
	}
end

-- A primitive, by its tag, from the table in primitives.luau. The binary ones are the integer operations: div and mod are floored, and dividing by zero is an error. The unary primitive kind takes no b, and works on any value.
-- The tag and the number of arguments are checked here, so a bad primitive fails when it is built, not when the machine reaches it.
function M.prim(tag: number, a: Expr, b: Expr?): Expr
	const row = Primitives.BY_TAG[tag]

	if row == nil then
		error(string.format("unknown primitive %s", tostring(tag)), 0)
	end

	if row.arity == 1 then
		if b ~= nil then
			error(string.format("%s takes one argument, but was given two", row.name), 0)
		end
	elseif b == nil then
		error(string.format("%s takes two arguments, but was given one", row.name), 0)
	end

	return {
		op = "prim",
		tag = tag,
		a = a,
		b = b,
	}
end

-- A proper list of expressions, ending in nil.
function M.list(items: { Expr }): Expr
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
