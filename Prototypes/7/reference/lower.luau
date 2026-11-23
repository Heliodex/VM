--!strict
-- LOWERING: PROTOTYPE 5 AND 6 EXPRESSIONS TO THE CORE (SPEC.md)
--
-- Prototypes 5 and 6 (and the L2 compiler, which produces their expressions) use a machine with environments. The core has none: every law is closed. So a lambda or a pin is closed by lambda lifting. Its free variables become leading arguments of a law, a closure is a partial application of that law to its free variables, and a pin is a thunk of a call of the law.
--
-- Each expression is lowered with the depth of binders in scope (its level), and a map from the level of each variable the current law can see to the argument that holds it. A variable's level is depth - 1 - index, so the innermost binder has the highest level.
--
--   Lower.expr(e): form            lowers a top-level expression, with no binders in scope
--   Lower.closedClosure(body): law  a closed closure (an input that is a lambda at the top level), as a law of arity 1
--
-- The mapping of the constructs:
--   quote v                 lit v (nil is the core's nil)
--   var i                   arg (the slot the map gives the variable's level)
--   lam body                a law of arity (free + 1): lit law, or call (lit law) applied to the free variables
--   pin e                   delay (call (lit law) nil free...): a law of arity (free + 1), its first argument a dummy
--   cell a b                cell a b
--   index n e               prim head or tail, once per step of n's binary address
--   force e                 force e
--   if c t e                if c t e
--   apply f a               call f a
--   prim tag a b            prim (the core's tag of the same name)
--   construct tag e         con tag e
--   tagof e                 prim 12 e
--   payload e               prim 13 e

const Primitives = require "../../6/interpreter/primitives"
const VM = require "../../6/interpreter/vm"
const Format = require "./format"
const Types = require "./types"

type Expr = VM.Expr
type Form = Types.Form
type Law = Types.Law
const NIL = Format.NIL
-- The core's primitive tag of each name (SPEC.md section 4).
const CORE_TAG: { [string]: number } = {
	add = 0,
	sub = 1,
	mul = 2,
	div = 3,
	mod = 4,
	lt = 5,
	eq = 6,
	kind = 7,
}

-- The free levels of an expression: the variables it refers to whose binders are below base. depth is the number of binders in scope where the expression sits.
const function freeLevels(e: Expr, depth: number, base: number, acc: { boolean })
	if e.op == "var" then
		const lvl = depth - 1 - e.index

		if lvl < base then
			acc[lvl] = true
		end
	elseif e.op == "lam" then
		freeLevels(e.body, depth + 1, base, acc)
	elseif e.op == "pin" then
		freeLevels(e.e, depth, base, acc)
	elseif e.op == "force" or e.op == "construct" or e.op == "tagof" or e.op == "payload" or e.op == "index" then
		freeLevels(e.e, depth, base, acc)
	elseif e.op == "cell" then
		freeLevels(e.head, depth, base, acc)
		freeLevels(e.tail, depth, base, acc)
	elseif e.op == "if" then
		freeLevels(e.c, depth, base, acc)
		freeLevels(e.t, depth, base, acc)
		freeLevels(e.e, depth, base, acc)
	elseif e.op == "apply" then
		freeLevels(e.f, depth, base, acc)
		freeLevels(e.arg, depth, base, acc)
	elseif e.op == "prim" then
		freeLevels(e.a, depth, base, acc)

		if e.b ~= nil then
			freeLevels(e.b, depth, base, acc)
		end
	end
end

-- The free levels in order, as a list.
const function sortedFree(e: Expr, depth: number, base: number): { number }
	local acc: { boolean } = {}
	freeLevels(e, depth, base, acc)
	local out: { number } = {}

	for lvl in acc do
		table.insert(out, lvl)
	end

	table.sort(out)

	return out
end

-- The address of index n: its binary digits below the leading 1, from the first step to the last. 0 is head, 1 is tail.
const function steps(n: number): { number }
	local bits: { number } = {}
	local m = n

	while m > 1 do
		table.insert(bits, m % 2)
		m = (m - m % 2) / 2
	end

	local out: { number } = {}

	for i = #bits, 1, -1 do
		table.insert(out, bits[i])
	end

	return out
end

-- The hook that expr may set: it is told each law as the law is made, closed or not, with the lambda it came from. The jet tests use it to find the laws the jets replace (the lambda's owner says which function it is).
local lawHook: ((Expr, Law) -> ())? = nil
local lower: (e: Expr, depth: number, map: { number }) -> Form

-- The arguments that hold the given levels in the current law's frame.
const function argsOf(levels: { number }, map: { number }): { Form }
	local args: { Form } = {}

	for _, lvl in levels do
		const slot = map[lvl]

		if slot == nil then
			error(`lower: a free variable at level {lvl} is not in the law's frame`, 0)
		end

		const arg: Form = { op = "arg"; index = slot }
		table.insert(args, arg)
	end

	return args
end

lower = function(e: Expr, depth: number, map: { number }): Form
	if e.op == "quote" then
		if type(e.value) == "number" then
			return { op = "lit"; value = e.value }
		end

		if type(e.value) == "table" and e.value.kind == "nil" then
			return { op = "lit"; value = NIL }
		end

		error("lower: a quoted value is an integer or nil", 0)
	elseif e.op == "var" then
		const lvl = depth - 1 - e.index
		const slot = map[lvl]

		if slot == nil then
			-- No binder: an unbound name. The machine gives an error for it at run time, so the lowering gives a slot that no frame has, which fails the same way.
			return { op = "arg"; index = 2 ^ 40 }
		end

		return { op = "arg"; index = slot }
	elseif e.op == "lam" then
		const free = sortedFree(e.body, depth + 1, depth)
		local inner: { number } = {}

		for i, lvl in free do
			inner[lvl] = i
		end

		inner[depth] = #free + 1
		const law: Law = { kind = "law"; arity = #free + 1; body = lower(e.body, depth + 1, inner) }

		if lawHook ~= nil then
			lawHook(e, law)
		end

		if #free == 0 then
			return { op = "lit"; value = law }
		end

		return { op = "call"; f = { op = "lit"; value = law }; args = argsOf(free, map) }
	elseif e.op == "pin" then
		const free = sortedFree(e.e, depth, depth)
		local inner: { number } = {}

		for i, lvl in free do
			inner[lvl] = i
		end

		const law: Law = { kind = "law"; arity = #free + 1; body = lower(e.e, depth, inner) }
		local args: { Form } = { { op = "lit"; value = NIL } }

		for _, a in argsOf(free, map) do
			table.insert(args, a)
		end

		return { op = "delay"; call = { op = "call"; f = { op = "lit"; value = law }; args = args } }
	elseif e.op == "cell" then
		return { op = "cell"; a = lower(e.head, depth, map); b = lower(e.tail, depth, map) }
	elseif e.op == "index" then
		local form = lower(e.e, depth, map)

		for _, step in steps(e.n) do
			const step_form: Form = {
				op = "prim",
				tag = if step == 0 then
					8
				else
					9,
				args = { form },
			}
			form = step_form
		end

		return form
	elseif e.op == "force" then
		return { op = "force"; e = lower(e.e, depth, map) }
	elseif e.op == "if" then
		return { op = "if"; c = lower(e.c, depth, map); t = lower(e.t, depth, map); e = lower(e.e, depth, map) }
	elseif e.op == "apply" then
		return { op = "call"; f = lower(e.f, depth, map); args = { lower(e.arg, depth, map) } }
	elseif e.op == "prim" then
		const name = Primitives.BY_TAG[e.tag].name
		const tag = CORE_TAG[name]

		if tag == nil then
			error(`lower: the primitive {name} has no core tag`, 0)
		end

		local args: { Form } = { lower(e.a, depth, map) }

		if e.b ~= nil then
			table.insert(args, lower(e.b, depth, map))
		end

		return { op = "prim"; tag = tag; args = args }
	elseif e.op == "construct" then
		return { op = "con"; tag = e.tag; e = lower(e.e, depth, map) }
	elseif e.op == "tagof" then
		return { op = "prim"; tag = 12; args = { lower(e.e, depth, map) } }
	elseif e.op == "payload" then
		return { op = "prim"; tag = 13; args = { lower(e.e, depth, map) } }
	end

	error(`lower: an expression {e.op} is not known`, 0)
end

-- Lowers a top-level expression: no binders, so the map is empty.
const function expr(e: Expr, hook: ((Expr, Law) -> ())?): Form
	lawHook = hook
	const form = lower(e, 0, {})
	lawHook = nil

	return form
end

-- A closed closure: the body of a lambda at the top level, with no environment, as a law of arity 1. Its variable of index 0 is its argument.
const function closedClosure(body: Expr): Law
	return { kind = "law"; arity = 1; body = lower(body, 1, { [0] = 1 }) }
end

return {
	expr = expr,
	closedClosure = closedClosure,
}
