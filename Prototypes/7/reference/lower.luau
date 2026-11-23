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
--   lam body                a law of arity (free + 1), or of the chain's arguments: lit law, or call (lit law) applied to the free variables
--   pin e                   delay (call (lit law) nil free...): a law of arity (free + 1), its first argument a dummy
--   cell a b                prim cons a b (primitive 14)
--   index n e               prim head or tail, once per step of n's binary address
--   force e                 force e
--   if c t e                if c t e
--   apply (lam b) a         let a in b, when no lambda in b makes a closure: the variable is the next slot of the frame
--   apply f a               call f a (a call of a call is one call with all its arguments)
--   letrec (fix of a lambda) a recursive law: arg 0 is the law itself
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
local lowerFix: (e: Expr, depth: number, map: { number }) -> Form

-- The form that gives a slot of the current law's frame. Slot 0 is the recursive function itself, which is the law applied to the outer variables it uses (map[-1] counts them, and they are its first arguments), so a partial application of the law, not the law alone. With no outer variables, it is the law.
const function slotForm(slot: number, map: { number }): Form
	if slot ~= 0 then
		return { op = "arg"; index = slot }
	end

	const count = map[-1] or 0

	if count == 0 then
		return { op = "arg"; index = 0 }
	end

	local args: { Form } = {}

	for i = 1, count do
		const a: Form = { op = "arg"; index = i }
		table.insert(args, a)
	end

	return { op = "call"; f = { op = "arg"; index = 0 }; args = args }
end

-- The arguments that hold the given levels in the current law's frame.
const function argsOf(levels: { number }, map: { number }): { Form }
	local args: { Form } = {}

	for _, lvl in levels do
		const slot = map[lvl]

		if slot == nil then
			error(`lower: a free variable at level {lvl} is not in the law's frame`, 0)
		end

		table.insert(args, slotForm(slot, map))
	end

	return args
end

-- A chain of lambdas (a curried function of several arguments) as one law of several arguments: the number of lambdas in the chain, and the body under them.
const function lamChain(e: Expr): (number, Expr)
	local n = 0
	local cur: Expr = e

	while cur.op == "lam" do
		n += 1
		cur = cur.body
	end

	return n, cur
end

-- Whether an expression makes a lambda anywhere in it.
local function containsLam(e: Expr): boolean
	if e.op == "lam" then
		return true
	end

	if e.op == "apply" then
		return containsLam(e.f) or containsLam(e.arg)
	elseif e.op == "if" then
		return containsLam(e.c) or containsLam(e.t) or containsLam(e.e)
	elseif e.op == "cell" then
		return containsLam(e.head) or containsLam(e.tail)
	elseif e.op == "prim" then
		return containsLam(e.a) or e.b ~= nil and containsLam(e.b)
	elseif e.op == "pin" or e.op == "force" or e.op == "construct" or e.op == "tagof" or e.op == "payload" or e.op == "index" then
		return containsLam(e.e)
	end

	return false
end

-- An application of a lambda to one argument: a let.
-- Whether a lambda in e, at binder depth depth, captures the variable at level.
local function capturesLevel(e: Expr, depth: number, level: number): boolean
	if e.op == "lam" then
		for _, l in sortedFree(e.body, depth + 1, depth) do
			if l == level then
				return true
			end
		end

		return false
	end

	if e.op == "apply" then
		return capturesLevel(e.f, depth, level) or capturesLevel(e.arg, depth, level)
	elseif e.op == "if" then
		return capturesLevel(e.c, depth, level) or capturesLevel(e.t, depth, level) or capturesLevel(e.e, depth, level)
	elseif e.op == "cell" then
		return capturesLevel(e.head, depth, level) or capturesLevel(e.tail, depth, level)
	elseif e.op == "prim" then
		return capturesLevel(e.a, depth, level) or e.b ~= nil and capturesLevel(e.b, depth, level)
	elseif e.op == "pin" or e.op == "force" or e.op == "construct" or e.op == "tagof" or e.op == "payload" or e.op == "index" then
		return capturesLevel(e.e, depth, level)
	end

	return false
end

-- Whether an application of a lambda is a let at depth, given the map of the current law. A let is used when the lambda's body makes no lambda, or when none of its lambdas captures the law's own function (slot 0): a closure that captures it rebuilds the partial application from every outer variable, which costs more than the closure did.
const function isLetApp(e: Expr, depth: number, map: { number }): boolean
	if e.op ~= "apply" then
		return false
	end

	const f = (e :: VM.ApplyExpr).f

	-- The fixed point is a lambda too, but it is not a let: applied to a function it is the recursion of the desugarer's letrec and of its mutual groups.
	if f.op ~= "lam" or f == VM.fix then
		return false
	end

	if not containsLam(f.body) then
		return true
	end

	for lvl, slot in map do
		if lvl >= 0 and slot == 0 and capturesLevel(f.body, depth + 1, lvl) then
			return false
		end
	end

	return true
end

-- Whether a let at depth can be used: a lambda in its body may not capture the function itself (slot 0) of the law, which costs a rebuilt partial application at every closure.
-- The argument of a fixed point that the desugarer writes for a recursive function: a lambda whose body is a lambda.
const function isFixOfLams(e: Expr): boolean
	if e.op ~= "lam" then
		return false
	end

	return e.body.op == "lam"
end

-- A recursive function, written as fix applied to a lambda that binds the function itself (the desugarer's letrec). Inside its body the function is arg 0, the law itself, applied to the outer variables it uses. So there is no fixed point: a recursive call is a call of the law, and the law is one law. The lambda's own argument is the law's first argument after the outer variables.
-- e is the lambda that binds the function (at level depth); its body is the function's own lambda (at depth + 1), whose body is at depth + 2.
lowerFix = function(e: Expr, depth: number, map: { number }): Form
	if e.op ~= "lam" then
		error("lower: a fixed point of something that is not a lambda", 0)
	end

	const value = e.body

	if value.op ~= "lam" then
		error("lower: a recursive function that is not a lambda", 0)
	end

	-- The function's own lambdas are at depth + 1 onwards, so its body is under n of them.
	const n, body = lamChain(value)
	const free = sortedFree(body, depth + 1 + n, depth)
	local inner: { number } = {}

	for i, lvl in free do
		inner[lvl] = i
	end

	inner[depth] = 0

	for j = 1, n do
		inner[depth + j] = #free + j
	end

	inner[-1] = #free
	inner[-2] = #free + n + 1
	const law: Law = { kind = "law"; arity = #free + n; body = lower(body, depth + 1 + n, inner) }

	if lawHook ~= nil then
		lawHook(value, law)
	end

	if #free == 0 then
		return { op = "lit"; value = law }
	end

	return { op = "call"; f = { op = "lit"; value = law }; args = argsOf(free, map) }
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

		return slotForm(slot, map)
	elseif e.op == "lam" then
		const n, body = lamChain(e)
		const free = sortedFree(body, depth + n, depth)
		local inner: { number } = {}

		for i, lvl in free do
			inner[lvl] = i
		end

		for j = 1, n do
			inner[depth + j - 1] = #free + j
		end

		inner[-2] = #free + n + 1
		const law: Law = { kind = "law"; arity = #free + n; body = lower(body, depth + n, inner) }

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

		-- The law's first argument is a dummy (slot 1), and the free variables are its arguments after it (slots 2 onwards).
		for i, lvl in free do
			inner[lvl] = i + 1
		end

		inner[-2] = #free + 2
		const law: Law = { kind = "law"; arity = #free + 1; body = lower(e.e, depth, inner) }
		local args: { Form } = { { op = "lit"; value = NIL } }

		for _, a in argsOf(free, map) do
			table.insert(args, a)
		end

		return { op = "delay"; call = { op = "call"; f = { op = "lit"; value = law }; args = args } }
	elseif e.op == "cell" then
		return { op = "prim"; tag = 14; args = { lower(e.head, depth, map), lower(e.tail, depth, map) } }
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
	elseif e.op == "apply" and e.f == VM.fix and isFixOfLams(e.arg) then
		return lowerFix(e.arg, depth, map)
	elseif isLetApp(e, depth, map) then
		-- An immediately applied lambda is a let: the argument is evaluated in this frame, and the lambda's variable is the next slot of the frame, so no law is made and nothing is entered (SPEC.md section 3, let).
		const slot = map[-2] or 0
		local inner: { number } = {}

		for lvl, sl in map do
			inner[lvl] = sl
		end

		inner[depth] = slot
		inner[-2] = slot + 1
		const app = e :: VM.ApplyExpr
		const lambda = app.f :: VM.LamExpr

		return { op = "let"; e = lower(app.arg, depth, map); body = lower(lambda.body, depth + 1, inner) }
	elseif e.op == "apply" then
		-- The arguments of a chain of applications, as one call (the head is not an application, or the fixed point's own application).
		local args: { Expr } = {}
		local head: Expr = e :: Expr

		while head.op == "apply" and head.f ~= VM.fix do
			table.insert(args, 1, head.arg)
			head = head.f
		end

		if head == e then
			-- A fixed point that is not a lambda of a lambda (not a recursive function): an application of it, as it is.
			return { op = "call"; f = lower(e.f, depth, map); args = { lower(e.arg, depth, map) } }
		end

		local forms: { Form } = {}

		for _, a in args do
			table.insert(forms, lower(a, depth, map))
		end

		-- A call of a call is one call with all the arguments: a partial application of a law, applied to more, is the law applied to all of them (the core's calls are curried in effect, SPEC.md section 3).
		const headForm = lower(head, depth, map)

		if headForm.op == "call" then
			local all: { Form } = {}

			for _, a in headForm.args do
				table.insert(all, a)
			end

			for _, a in forms do
				table.insert(all, a)
			end

			return { op = "call"; f = headForm.f; args = all }
		end

		return { op = "call"; f = headForm; args = forms }
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
	const form = lower(e, 0, { [-2] = 2 })
	lawHook = nil

	return form
end

-- A closed closure: the body of a lambda at the top level, with no environment, as a law of arity 1. Its variable of index 0 is its argument.
const function closedClosure(body: Expr): Law
	return { kind = "law"; arity = 1; body = lower(body, 1, { [0] = 1, [-2] = 2 }) }
end

return {
	expr = expr,
	closedClosure = closedClosure,
}
