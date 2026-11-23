--!strict
-- THE PROTOTYPE 7 REFERENCE INTERPRETER (SPEC.md)
--
-- A small, clear machine for the core. It is the oracle for the faster machines of Phase 4, so it is written for clarity, not speed. It keeps its pending work on an explicit stack of continuations, so the depth of a program is not limited by the call stack of the host.
--
-- Each form evaluated costs one step, and each saturated law entry costs one step. A return costs nothing. Fuel is checked before each step, so a run with fuel n takes at most n steps, and a run that uses up its fuel gives out_of_fuel. The steps are the run's fuel used (SPEC.md section 6).
--
--   Interp.run(program, input, fuel)   the program (a law of arity 1) applied to the input
--   Interp.runForm(form, input, fuel)  a form as the body of a law of arity 1, with the input as its argument; the wrapper costs no step (for the spec's examples)
--
-- Both give an outcome: { status = "value", value, steps }, { status = "error", message, steps }, or { status = "out_of_fuel", steps }.

const Format = require "./format"
const Int = require "./int"
const Types = require "./types"

type Value = Types.Value
type Form = Types.Form
type Law = Types.Law
type Thunk = Types.Thunk
type Outcome = Types.Outcome
-- The slots of one invocation of a law: slot 0 is the law, then the arguments, then what let and case push.
type Env = { slots: { Value } }
-- A continuation: what to do with the next value. Each kind has the fields it needs.
type Items = { t: "items"; items: { Form }; vals: { Value }; i: number; fin: string; form: Form; env: Env }
type Restore = { t: "restore"; env: Env; len: number }
type ApplyRest = { t: "applyrest"; rest: { Value } }
type ForceStore = { t: "forcestore"; thunk: Thunk }
type Cont = Items | Restore | ApplyRest | ForceStore
-- Placeholders for the machine's registers when a mode does not use them.
const NOFORM: Form = { op = "lit"; value = Format.NIL }
const NOENV: Env = { slots = {} }

-- The kind number of a value (SPEC.md section 1).
const function kindOf(v: Value): number
	if type(v) == "number" then
		return 0
	end

	if v.kind == "big" then
		return 0
	elseif v.kind == "nil" then
		return 1
	elseif v.kind == "cell" then
		return 2
	elseif v.kind == "law" or v.kind == "app" then
		return 3
	elseif v.kind == "con" then
		return 5
	end

	return 6
end

const function isInt(v: Value): boolean
	return type(v) == "number" or v.kind == "big"
end

-- The primitives (SPEC.md section 4). Each gives a value, or an error message.
const function primitive(tag: number, vals: { Value }): (Value?, string?)
	const a = vals[1]
	const b = vals[2]

	if tag == 0 or tag == 1 or tag == 2 or tag == 3 or tag == 4 or tag == 5 or tag == 6 then
		if not isInt(a) or not isInt(b) then
			return nil, "the integer operation " .. tostring(tag) .. " needs integers"
		end

		const x: Int.Int = a :: Int.Int
		const y: Int.Int = b :: Int.Int

		if tag == 0 then
			return Int.add(x, y), nil
		elseif tag == 1 then
			return Int.sub(x, y), nil
		elseif tag == 2 then
			return Int.mul(x, y), nil
		elseif tag == 3 then
			if Int.sign(y) == 0 then
				return nil, "division by zero"
			end

			return Int.divFloor(x, y), nil
		elseif tag == 4 then
			if Int.sign(y) == 0 then
				return nil, "modulus by zero"
			end

			return Int.modFloor(x, y), nil
		elseif tag == 5 then
			return
				if Int.compare(x, y) < 0 then
					1
				else
					0, nil
		end

		return
			if Int.compare(x, y) == 0 then
				1
			else
				0, nil
	elseif tag == 12 then
		const cell: Types.Cell = { kind = "cell", head = a, tail = b }

		return cell, nil
	elseif tag == 7 then
		return kindOf(a), nil
	elseif tag == 8 then
		if type(a) ~= "table" or a.kind ~= "cell" then
			return nil, "head of a value that is not a cell"
		end

		return a.head, nil
	elseif tag == 9 then
		if type(a) ~= "table" or a.kind ~= "cell" then
			return nil, "tail of a value that is not a cell"
		end

		return a.tail, nil
	elseif tag == 10 then
		if type(a) == "table" and a.kind == "con" then
			return a.tag, nil
		end

		return -1, nil
	elseif tag == 11 then
		if type(a) ~= "table" or a.kind ~= "con" then
			return nil, "payload of a value that is not a constructor"
		end

		return a.payload, nil
	end

	return nil, "primitive " .. tostring(tag) .. " does not exist"
end

-- The subforms a form evaluates first, in order, and what finishes it. A form with no subforms is not here.
const function itemsOf(form: Form): ({ Form }, string)
	if form.op == "call" then
		local items: { Form } = { form.f }

		for _, a in form.args do
			table.insert(items, a)
		end

		return items, "call"
	elseif form.op == "delay" then
		local items: { Form } = { form.call.f }

		for _, a in form.call.args do
			table.insert(items, a)
		end

		return items, "delay"
	elseif form.op == "con" then
		return { form.e }, "con"
	elseif form.op == "case" then
		return { form.e }, "case"
	elseif form.op == "if" then
		return { form.c }, "if"
	elseif form.op == "let" then
		return { form.e }, "let"
	elseif form.op == "force" then
		return { form.e }, "force"
	elseif form.op == "prim" then
		return form.args, "prim"
	end

	error("binary: a form with no subforms: " .. form.op, 0)
end

type Mode = "eval" | "ret" | "apply"

-- The machine. mode is "eval" (form, env), "ret" (value), or "apply" (fv, args). The continuations are of the types above.
const function machine(mode0: Mode, form0: Form, env0: Env, fv0: Value, args0: { Value }, fuel: number): Outcome
	local k: { Cont } = {}
	local steps = 0
	local mode = mode0
	local form = form0
	local env = env0
	local value: Value = Format.NIL
	local fv = fv0
	local args = args0

	while true do
		if mode == "eval" then
			if steps >= fuel then
				return { status = "out_of_fuel"; steps = steps }
			end

			steps += 1

			if form.op == "lit" then
				value = form.value
				mode = "ret"
			elseif form.op == "arg" then
				const slot: Value? = env.slots[form.index + 1]

				if slot == nil then
					return { status = "error"; message = "no slot " .. tostring(form.index) .. " in the frame"; steps = steps }
				end

				value = slot
				mode = "ret"
			else
				const items, fin = itemsOf(form)
				table.insert(k, { t = "items"; items = items; vals = {}; i = 1; fin = fin; form = form; env = env } :: Cont)
				form = items[1]
			end
		elseif mode == "apply" then
			local law: Law
			local all: { Value } = {}

			if type(fv) == "table" and fv.kind == "app" then
				law = fv.law

				for _, a in fv.args do
					table.insert(all, a)
				end

				for _, a in args do
					table.insert(all, a)
				end
			elseif type(fv) == "table" and fv.kind == "law" then
				law = fv
				all = args
			else
				return { status = "error"; message = "a call of a value that is not a function"; steps = steps }
			end

			const arity = law.arity
			const n = #all

			if n < arity then
				if n == 0 then
					value = law
				else
					value = { kind = "app"; law = law; args = all }
				end

				mode = "ret"
			else
				if steps >= fuel then
					return { status = "out_of_fuel"; steps = steps }
				end

				steps += 1
				local rest: { Value } = {}

				for i = arity + 1, n do
					table.insert(rest, all[i])
				end

				if #rest > 0 then
					table.insert(k, { t = "applyrest"; rest = rest } :: Cont)
				end

				local slots: { Value } = { law }

				for i = 1, arity do
					slots[i + 1] = all[i]
				end

				env = { slots = slots }
				form = law.body
				mode = "eval"
			end
		else
			-- A value goes to the continuation on top.
			const c = table.remove(k)

			if c == nil then
				return { status = "value"; value = value; steps = steps }
			end

			if c.t == "items" then
				c.vals[c.i] = value

				if c.i < #c.items then
					c.i += 1
					table.insert(k, c)
					form = c.items[c.i]
					env = c.env
					mode = "eval"
				else
					const vals = c.vals
					const f = c.form
					const e = c.env
					const fin = c.fin

					if fin == "con" then
						if f.op ~= "con" then
							error("machine: a con finish on another form", 0)
						end

						value = { kind = "con"; tag = f.tag; payload = vals[1] }
						mode = "ret"
					elseif fin == "call" then
						const all: { Value } = {}

						for i = 2, #vals do
							table.insert(all, vals[i])
						end

						fv = vals[1]
						args = all
						mode = "apply"
					elseif fin == "delay" then
						const all: { Value } = {}

						for i = 2, #vals do
							table.insert(all, vals[i])
						end

						const thunk: Thunk = { kind = "thunk"; f = vals[1]; args = all; done = false; result = nil }
						value = thunk
						mode = "ret"
					elseif fin == "prim" then
						if f.op ~= "prim" then
							error("machine: a prim finish on another form", 0)
						end

						const result, message = primitive(f.tag, vals)

						if message ~= nil or result == nil then
							return { status = "error"; message = message or "a primitive gave nothing"; steps = steps }
						end

						value = result
						mode = "ret"
					elseif fin == "if" then
						if f.op ~= "if" then
							error("machine: an if finish on another form", 0)
						end

						const c0 = vals[1]

						if not isInt(c0) then
							return { status = "error"; message = "if needs an integer condition"; steps = steps }
						end

						form =
							if Int.sign(c0 :: Int.Int) ~= 0 then
								f.t
							else
								f.e
						env = e
						mode = "eval"
					elseif fin == "let" then
						if f.op ~= "let" then
							error("machine: a let finish on another form", 0)
						end

						table.insert(k, { t = "restore"; env = e; len = #e.slots } :: Cont)
						table.insert(e.slots, vals[1])
						form = f.body
						env = e
						mode = "eval"
					elseif fin == "case" then
						if f.op ~= "case" then
							error("machine: a case finish on another form", 0)
						end

						const scrut = vals[1]

						if type(scrut) ~= "table" or scrut.kind ~= "con" then
							return { status = "error"; message = "case of a value that is not a constructor"; steps = steps }
						end

						local branch: Form? = nil
						local pushed: Value = scrut

						for _, alt in f.alts do
							if alt.tag == scrut.tag then
								branch = alt.body
								pushed = scrut.payload
								break
							end
						end

						if branch == nil then
							if f.elseBody == nil then
								return { status = "error"; message = "no branch for the constructor's tag " .. tostring(scrut.tag); steps = steps }
							end

							branch = f.elseBody
						end

						table.insert(k, { t = "restore"; env = e; len = #e.slots } :: Cont)
						table.insert(e.slots, pushed)
						form = branch :: Form
						env = e
						mode = "eval"
					elseif fin == "force" then
						const th = vals[1]

						if type(th) ~= "table" or th.kind ~= "thunk" then
							return { status = "error"; message = "force of a value that is not a thunk"; steps = steps }
						end

						if th.done then
							value = th.result :: Value
							mode = "ret"
						else
							table.insert(k, { t = "forcestore"; thunk = th } :: Cont)
							fv = th.f
							args = th.args
							mode = "apply"
						end
					else
						return { status = "error"; message = "machine: unknown finish " .. fin; steps = steps }
					end
				end
			elseif c.t == "restore" then
				for i = #c.env.slots, c.len + 1, -1 do
					c.env.slots[i] = nil
				end
			elseif c.t == "applyrest" then
				fv = value
				args = c.rest
				mode = "apply"
			elseif c.t == "forcestore" then
				c.thunk.done = true
				c.thunk.result = value
			end
		end
	end
end

-- Runs a program (a law of arity 1) on an input.
const function run(program: Law, input: Value, fuel: number): Outcome
	if program.arity ~= 1 then
		error("a program is a law of arity 1", 0)
	end

	return machine("apply", NOFORM, NOENV, program, { input }, fuel)
end

-- Runs a form as the body of a law of arity 1, with the input as its argument. The wrapper costs no step.
const function runForm(form: Form, input: Value, fuel: number): Outcome
	return machine("eval", form, { slots = { Format.NIL; input } }, Format.NIL, {}, fuel)
end

return {
	run = run,
	runForm = runForm,
	kindOf = kindOf,
	primitive = primitive,
}
