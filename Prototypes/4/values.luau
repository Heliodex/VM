--!strict
-- TAGGED VALUES
--
-- A Lisp value is one of six kinds, and is itself a sum: it is a function that takes one case for each kind, and applies the case for its own kind to its fields. So
--   number n    = λc1…c6. c1 n         symbol s  = λc1…c6. c2 s
--   pair a d    = λc1…c6. c3 a d       nil       = λc1…c6. c4
--   boolean b   = λc1…c6. c5 b         error     = λc1…c6. c6
-- Taking a value apart is applying it to its cases, so no kind is ever compared with another, and the cases that are not chosen are erased.
-- Every field is used by one case only, so a field is never shared, and the copying problem of duplicated nets (see fix.luau) does not arise from the values themselves.
-- The payloads are the encodings of their own modules: a number is a Scott numeral (scott.luau), a symbol is the Scott numeral of its id, a boolean is a Church boolean (booleans.luau).
-- A value that is an error is what a builtin gives when its arguments are of the wrong kind, so a type mistake is a value, not a crash.
--
--   const V = require "./values"
--
--   local result = V.read(function(b) return V.numberValue(b, 3) end)  -- {kind = "number", value = 3}

const B = require "./builder"
const Bo = require "./booleans"
const H = require "./harness"
const L = require "./lambda"
const S = require "./scott"
const Types = require "./types"

type Builder = B.Builder
type Port = Types.Port

-- What a value can be, read back from a net. Only the fields of its kind are set.
export type Value = {
	kind: "number" | "symbol" | "pair" | "nil" | "boolean" | "error",
	value: number?,
	truth: boolean?,
	name: string?,
	car: Value?,
	cdr: Value?,
}

-- The kinds, in the order of the cases.
const NUMBER = 1
const SYMBOL = 2
const PAIR = 3
const NIL = 4
const BOOLEAN = 5
const ERROR = 6
const KINDS = 6
-- How many fields each kind has, by kind.
const ARITY = {
	1,
	1,
	2,
	0,
	1,
	0,
}

-- A case: what to do with the fields of a value, and with any further arguments the value is applied to.
type Body = (Builder, { Port }, { Port }) -> Port

-- Forward declarations, since the cases of the kinds refer to one another.
local numberValue: (Builder, number) -> Port
local errorValue: (Builder) -> Port
local booleanValue: (Builder, boolean) -> Port

-- Symbols are numbers: each name is given the next id the first time it is used, and the id is the payload. The ids are shared by every program in the session, so a name keeps its id.
local symbolIds: {
	[string]: number,
} = {}
local symbolNames: {
	[number]: string,
} = {}

const function symbolId(
	name: string
): number
	local id = symbolIds[name]

	if id == nil then
		id = #symbolNames + 1
		symbolIds[name] = id
		symbolNames[id] = name
	end

	return id
end

const function symbolName(
	id: number
): string?
	return symbolNames[id]
end

-- Builds λ over `n` arguments, then calls `k` with their ports.
local function lamsOver(
	b: Builder,
	n: number,
	k: ({ Port }) -> Port
): Port
	local function go(
		collected: { Port }
	): Port
		if #collected == n then
			return k(collected)
		end

		return L.lam(
			b, function(
				x: Port
			): Port
				const next = table.clone(collected)
				table.insert(next, x)

				return go(next)
			end
		)
	end

	return go({})
end

-- The value of the given kind, with the given fields.
local function make(
	b: Builder,
	kind: number,
	fields: { Port }
): Port
	return lamsOver(b, KINDS, function(
		cases: { Port }
	): Port
		local value = cases[kind]

		for _, field in fields do
			value = L.app(b, value, field)
		end

		return value
	end)
end

-- Applies the value `v` to a case for each kind: the case for its own kind gets its fields, and gets `extras` as further arguments. A kind with no body in `bodies` takes `default`.
-- The result is still waiting for the extra arguments, which the caller applies.
local function dispatch(
	b: Builder,
	v: Port,
	bodies: {
		[number]: Body,
	},
	extras: number,
	default: Body
): Port
	local value = v

	for kind = 1, KINDS do
		const body = bodies[kind] or default
		const case = lamsOver(b, ARITY[kind], function(
			fields: { Port }
		): Port
			return lamsOver(b, extras, function(
				args: { Port }
			): Port
				return body(b, fields, args)
			end)
		end)
		value = L.app(b, value, case)
	end

	return value
end

local function errorBody(
	b: Builder,
	_fields: { Port },
	_args: { Port }
): Port
	return errorValue(b)
end

local function constantBody(
	v: boolean
): Body
	return function(
		b: Builder,
		_fields: { Port },
		_args: { Port }
	): Port
		return booleanValue(b, v)
	end
end

-- The number n, with a Scott numeral as payload.
numberValue = function(
	b: Builder,
	n: number
): Port
	return make(b, NUMBER, { S.numeral(b, n) })
end

-- A number whose payload is the given Scott numeral.
local function numberFromPayload(
	b: Builder,
	payload: Port
): Port
	return make(b, NUMBER, { payload })
end

-- The symbol with the given id, with its id as payload.
local function symbolValue(
	b: Builder,
	id: number
): Port
	return make(b, SYMBOL, { S.numeral(b, id) })
end

-- The pair of two values.
local function consValue(
	b: Builder,
	car: Port,
	cdr: Port
): Port
	return make(b, PAIR, { car, cdr })
end

local function nilValue(
	b: Builder
): Port
	return make(b, NIL, {})
end

booleanValue = function(
	b: Builder,
	v: boolean
): Port
	return make(b, BOOLEAN, { if v then Bo.truth(b) else Bo.falsity(b) })
end

-- A boolean whose payload is the given Church boolean.
local function booleanFromPayload(
	b: Builder,
	payload: Port
): Port
	return make(b, BOOLEAN, { payload })
end

errorValue = function(
	b: Builder
): Port
	return make(b, ERROR, {})
end

-- `if cond then yes else no`, or with a further argument `extra`, which is passed to whichever branch is chosen, as the code of a recursive call is.
-- The condition must be a boolean; anything else is an error value.
local function ifValue(
	b: Builder,
	cond: Port,
	yes: Port,
	no: Port,
	extra: Port?
): Port
	const bodies: {
		[number]: Body,
	} = {
		[BOOLEAN] = function(
			b: Builder,
			fields: { Port },
			args: { Port }
		): Port
			local value = L.app(b, L.app(b, fields[1], args[1]), args[2])

			if args[3] then
				value = L.app(b, value, args[3])
			end

			return value
		end,
	}
	local value = dispatch(b, cond, bodies, if extra then 3 else 2, errorBody)
	value = L.app(b, value, yes)
	value = L.app(b, value, no)

	if extra then
		value = L.app(b, value, extra)
	end

	return value
end

-- A builtin of one argument, which is a function value.
local function fn1(
	f: (Builder, Port) -> Port
): (Builder) -> Port
	return function(
		b: Builder
	): Port
		return L.lam(
			b, function(
				x: Port
			): Port
				return f(b, x)
			end
		)
	end
end

-- A builtin of two arguments, which is a curried function value.
local function fn2(
	f: (Builder, Port, Port) -> Port
): (Builder) -> Port
	return function(
		b: Builder
	): Port
		return L.lam(
			b, function(
				x: Port
			): Port
				return L.lam(
					b, function(
						y: Port
					): Port
						return f(b, x, y)
					end
				)
			end
		)
	end
end

-- Applies a builder's port to the given arguments, in order.
local function applyAll(
	b: Builder,
	fn: Port,
	args: { Port }
): Port
	local value = fn

	for _, arg in args do
		value = L.app(b, value, arg)
	end

	return value
end

-- The result of an operation on two numbers, or an error value if either is not a number. `op` gets the two Scott numerals, each used once, and `wrap` makes the value of its result.
local function onNumbers(
	b: Builder,
	x: Port,
	y: Port,
	op: (Builder, Port, Port) -> Port,
	wrap: (Builder, Port) -> Port
): Port
	return dispatch(b, x, {
		[NUMBER] = function(
			b: Builder,
			fx: { Port },
			_args: { Port }
		): Port
			return dispatch(b, y, {
				[NUMBER] = function(
					b: Builder,
					fy: { Port },
					_args2: { Port }
				): Port
					return wrap(b, op(b, fx[1], fy[1]))
				end,
			}, 0, errorBody)
		end,
	}, 0, errorBody)
end

-- The result of an operation on one number, or an error value if it is not a number.
local function onNumber(
	b: Builder,
	x: Port,
	op: (Builder, Port) -> Port,
	wrap: (Builder, Port) -> Port
): Port
	return dispatch(b, x, {
		[NUMBER] = function(
			b: Builder,
			fx: { Port },
			_args: { Port }
		): Port
			return wrap(b, op(b, fx[1]))
		end,
	}, 0, errorBody)
end

-- The builtins of the language, by name. Each is a builder function, which gives the value of the builtin in the net it is given.
const builtins: {
	[string]: (Builder) -> Port,
} = {
	["+"] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return onNumbers(b, x, y, function(
			b: Builder,
			p: Port,
			q: Port
		): Port
			return applyAll(b, S.addition(b), { p, q })
		end, numberFromPayload)
	end),
	["-"] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return onNumbers(b, x, y, function(
			b: Builder,
			p: Port,
			q: Port
		): Port
			return applyAll(b, S.subtraction(b), { p, q })
		end, numberFromPayload)
	end),
	["*"] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return onNumbers(b, x, y, function(
			b: Builder,
			p: Port,
			q: Port
		): Port
			return applyAll(b, S.multiplication(b), { p, q })
		end, numberFromPayload)
	end),
	["="] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return onNumbers(b, x, y, function(
			b: Builder,
			p: Port,
			q: Port
		): Port
			return applyAll(b, S.equal(b), { p, q })
		end, booleanFromPayload)
	end),
	["<"] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return onNumbers(b, x, y, function(
			b: Builder,
			p: Port,
			q: Port
		): Port
			return applyAll(b, S.less(b), { p, q })
		end, booleanFromPayload)
	end),
	["<="] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return onNumbers(b, x, y, function(
			b: Builder,
			p: Port,
			q: Port
		): Port
			return applyAll(b, S.lessEqual(b), { p, q })
		end, booleanFromPayload)
	end),
	succ = fn1(function(
		b: Builder,
		x: Port
	): Port
		return onNumber(b, x, function(
			b: Builder,
			p: Port
		): Port
			return applyAll(b, S.successor(b), { p })
		end, numberFromPayload)
	end),
	["zero?"] = fn1(function(
		b: Builder,
		x: Port
	): Port
		return onNumber(b, x, function(
			b: Builder,
			p: Port
		): Port
			return applyAll(b, S.isZero(b), { p })
		end, booleanFromPayload)
	end),
	["eq?"] = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		-- y is dispatched once, and x is passed to the case it selects, which dispatches x once more. So each value is used once. Numbers and symbols are equal when their payloads are; nil is equal to nil; anything else is not equal.
		const yCases: {
			[number]: Body,
		} = {
			[NUMBER] = function(
				b: Builder,
				fy: { Port },
				args: { Port }
			): Port
				return dispatch(b, args[1], {
					[NUMBER] = function(
						b: Builder,
						fx: { Port },
						_args: { Port }
					): Port
						return booleanFromPayload(b, applyAll(b, S.equal(b), { fx[1], fy[1] }))
					end,
				}, 0, constantBody(false))
			end,
			[SYMBOL] = function(
				b: Builder,
				fy: { Port },
				args: { Port }
			): Port
				return dispatch(b, args[1], {
					[SYMBOL] = function(
						b: Builder,
						fx: { Port },
						_args: { Port }
					): Port
						return booleanFromPayload(b, applyAll(b, S.equal(b), { fx[1], fy[1] }))
					end,
				}, 0, constantBody(false))
			end,
			[NIL] = function(
				b: Builder,
				_fy: { Port },
				args: { Port }
			): Port
				return dispatch(b, args[1], { [NIL] = constantBody(true) }, 0, constantBody(false))
			end,
		}
		local value = dispatch(b, y, yCases, 1, constantBody(false))

		return L.app(b, value, x)
	end),
	cons = fn2(function(
		b: Builder,
		x: Port,
		y: Port
	): Port
		return consValue(b, x, y)
	end),
	car = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, {
			[PAIR] = function(
				b: Builder,
				fx: { Port },
				_args: { Port }
			): Port
				return fx[1]
			end,
		}, 0, errorBody)
	end),
	cdr = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, {
			[PAIR] = function(
				b: Builder,
				fx: { Port },
				_args: { Port }
			): Port
				return fx[2]
			end,
		}, 0, errorBody)
	end),
	["nil"] = function(
		b: Builder
	): Port
		return nilValue(b)
	end,
	["true"] = function(
		b: Builder
	): Port
		return booleanValue(b, true)
	end,
	["false"] = function(
		b: Builder
	): Port
		return booleanValue(b, false)
	end,
	["null?"] = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, { [NIL] = constantBody(true) }, 0, constantBody(false))
	end),
	["pair?"] = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, { [PAIR] = constantBody(true) }, 0, constantBody(false))
	end),
	["number?"] = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, { [NUMBER] = constantBody(true) }, 0, constantBody(false))
	end),
	["symbol?"] = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, { [SYMBOL] = constantBody(true) }, 0, constantBody(false))
	end),
	["boolean?"] = fn1(function(
		b: Builder,
		x: Port
	): Port
		return dispatch(b, x, { [BOOLEAN] = constantBody(true) }, 0, constantBody(false))
	end),
}

-- The value of a field of the value that `build` makes, when that value is of the given kind: the field is read as its own value. Used for readback.
local function fieldOf(
	build: (Builder) -> Port,
	kind: number,
	index: number
): (Builder) -> Port
	return function(
		b: Builder
	): Port
		const v = build(b)

		return dispatch(b, v, {
			[kind] = function(
				b: Builder,
				fields: { Port },
				_args: { Port }
			): Port
				return fields[index]
			end,
		}, 0, errorBody)
	end
end

-- Reads a value back, as a Lua table. The reduction of the value is reported, and the value is nil if the net is not a value of the language.
-- The kind is read first, as the number of the case the value takes; then the payload is read as its own encoding.
local function read(
	build: (Builder) -> Port,
	budget: number?
): (H.Report, Value?)
	const report, kind = S.readback(function(
		b: Builder
	): Port
		const v = build(b)
		const bodies: {
			[number]: Body,
		} = {}

		for k = 1, KINDS do
			bodies[k] = function(
				b: Builder,
				_fields: { Port },
				_args: { Port }
			): Port
				return S.numeral(b, k)
			end
		end

		return dispatch(b, v, bodies, 0, errorBody)
	end, budget)

	if kind == nil then
		return report, nil
	end

	if kind == NUMBER then
		const _, n = S.readback(fieldOf(build, NUMBER, 1), budget)

		return report, if n == nil then nil else { kind = "number", value = n }
	elseif kind == SYMBOL then
		const _, id = S.readback(fieldOf(build, SYMBOL, 1), budget)

		if id == nil then
			return report, nil
		end

		const name = symbolName(id)

		if name == nil then
			return report, nil
		end

		return report, { kind = "symbol", name = name }
	elseif kind == PAIR then
		const _, car = read(fieldOf(build, PAIR, 1), budget)
		const _2, cdr = read(fieldOf(build, PAIR, 2), budget)

		if car == nil or cdr == nil then
			return report, nil
		end

		return report, { kind = "pair", car = car, cdr = cdr }
	elseif kind == NIL then
		return report, { kind = "nil" }
	elseif kind == BOOLEAN then
		const b = B.new()
		fieldOf(build, BOOLEAN, 1)(b)
		const net = b:finish()
		H.reduce(net, budget)
		const truth = Bo.readback(net)

		return report, if truth == nil then nil else { kind = "boolean", truth = truth }
	end

	return report, { kind = "error" }
end

return {
	builtins = builtins,
	numberValue = numberValue,
	symbolValue = symbolValue,
	consValue = consValue,
	nilValue = nilValue,
	booleanValue = booleanValue,
	errorValue = errorValue,
	ifValue = ifValue,
	symbolId = symbolId,
	symbolName = symbolName,
	read = read,
}
