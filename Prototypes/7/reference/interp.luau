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

const Int = require "./int"
const Format = require "./format"

export type Outcome = { status: string, value: any?, message: string?, steps: number }

const NIL = Format.NIL

-- Pins are interned by their content: the same bytes give the same pin object.
const PINS: { [string]: any } = {}

-- The kind number of a value (SPEC.md section 1).
local function kindOf(v: any): number
	if type(v) == "number" or Int.isBig(v) then
		return 0
	end

	if v == NIL then
		return 1
	end

	if v.kind == "cell" then
		return 2
	end

	if v.kind == "law" or v.kind == "app" then
		return 3
	end

	if v.kind == "pin" then
		return 4
	end

	if v.kind == "con" then
		return 5
	end

	return 6
end

local function isInt(v: any): boolean
	return type(v) == "number" or Int.isBig(v)
end

-- The primitives (SPEC.md section 4). Each gives a value, or an error message.
local function primitive(tag: number, vals: { any }): (any?, string?)
	const a = vals[1]
	const b = vals[2]

	if tag == 0 or tag == 1 or tag == 2 or tag == 3 or tag == 4 or tag == 5 or tag == 6 then
		if not isInt(a) or not isInt(b) then
			return nil, "the integer operation " .. tostring(tag) .. " needs integers"
		end

		if tag == 0 then
			return Int.add(a, b), nil
		elseif tag == 1 then
			return Int.sub(a, b), nil
		elseif tag == 2 then
			return Int.mul(a, b), nil
		elseif tag == 3 then
			if Int.sign(b) == 0 then
				return nil, "division by zero"
			end

			return Int.divFloor(a, b), nil
		elseif tag == 4 then
			if Int.sign(b) == 0 then
				return nil, "modulus by zero"
			end

			return Int.modFloor(a, b), nil
		elseif tag == 5 then
			return if Int.compare(a, b) < 0 then 1 else 0, nil
		end

		return if Int.compare(a, b) == 0 then 1 else 0, nil
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
		if type(a) == "table" and a.kind == "thunk" then
			return nil, "a thunk cannot be pinned"
		end

		if type(a) == "table" and a.kind == "pin" then
			return a, nil
		end

		local ok, key = pcall(Format.encodeValue, a)

		if not ok then
			return nil, "a pin has no binary form: " .. tostring(key)
		end

		local existing = PINS[key]

		if existing ~= nil then
			return existing, nil
		end

		local pin = { kind = "pin", value = a }
		PINS[key] = pin

		return pin, nil
	elseif tag == 11 then
		if type(a) ~= "table" or a.kind ~= "pin" then
			return nil, "unpin of a value that is not a pin"
		end

		return a.value, nil
	elseif tag == 12 then
		if type(a) == "table" and a.kind == "con" then
			return a.tag, nil
		end

		return -1, nil
	elseif tag == 13 then
		if type(a) ~= "table" or a.kind ~= "con" then
			return nil, "payload of a value that is not a constructor"
		end

		return a.payload, nil
	end

	return nil, "primitive " .. tostring(tag) .. " does not exist"
end

-- The subforms a form evaluates first, in order, and what finishes it. A form with no subforms is not here.
local function itemsOf(form: any): ({ any }, string)
	const op = form.op

	if op == "call" then
		local items = { form.f }

		for _, a in form.args do
			table.insert(items, a)
		end

		return items, "call"
	elseif op == "delay" then
		local items = { form.call.f }

		for _, a in form.call.args do
			table.insert(items, a)
		end

		return items, "delay"
	elseif op == "cell" then
		return { form.a, form.b }, "cell"
	elseif op == "con" then
		return { form.e }, "con"
	elseif op == "case" then
		return { form.e }, "case"
	elseif op == "if" then
		return { form.c }, "if"
	elseif op == "let" then
		return { form.e }, "let"
	elseif op == "force" then
		return { form.e }, "force"
	elseif op == "prim" then
		return form.args, "prim"
	end

	error("binary: a form with no subforms: " .. tostring(op), 0)
end

-- The machine. mode is "eval" (form, env), "ret" (value), or "apply" (fv, args). The continuations are tables with a kind t: "items" (a form waiting for the values of its subforms), "restore" (pop the slots pushed by a let or a case), "applyrest" (apply the value to the arguments that the saturated call did not take), and "forcestore" (store the result in the thunk).
local function machine(mode0: string, form0: any, env0: any, fv0: any, args0: any, fuel: number): Outcome
	local k: { any } = {}
	local steps = 0
	local mode = mode0
	local form = form0
	local env = env0
	local value: any = nil
	local fv = fv0
	local args = args0

	while true do
		if mode == "eval" then
			if steps >= fuel then
				return { status = "out_of_fuel", steps = steps }
			end

			steps += 1
			const op = form.op

			if op == "lit" then
				value = form.value
				mode = "ret"
			elseif op == "arg" then
				value = env.slots[form.index + 1]

				if value == nil then
					return { status = "error", message = "no slot " .. tostring(form.index) .. " in the frame", steps = steps }
				end

				mode = "ret"
			else
				local items, fin = itemsOf(form)
				table.insert(k, { t = "items", items = items, vals = {}, i = 1, fin = fin, form = form, env = env })
				form = items[1]
			end
		elseif mode == "apply" then
			local law: any
			local all: { any }

			if type(fv) == "table" and fv.kind == "app" then
				law = fv.law
				all = {}

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
				return { status = "error", message = "a call of a value that is not a function", steps = steps }
			end

			const arity = law.arity
			const n = #all

			if n < arity then
				if n == 0 then
					value = law
				else
					value = { kind = "app", law = law, args = all }
				end

				mode = "ret"
			else
				if steps >= fuel then
					return { status = "out_of_fuel", steps = steps }
				end

				steps += 1

				local rest: { any } = {}

				for i = arity + 1, n do
					table.insert(rest, all[i])
				end

				if #rest > 0 then
					table.insert(k, { t = "applyrest", rest = rest })
				end

				local slots: { any } = { law }

				for i = 1, arity do
					slots[i + 1] = all[i]
				end

				env = { slots = slots }
				form = law.body
				mode = "eval"
			end
		else
			-- A value goes to the continuation on top.
			if #k == 0 then
				return { status = "value", value = value, steps = steps }
			end

			const c = table.remove(k) :: any

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

					if fin == "cell" then
						value = { kind = "cell", head = vals[1], tail = vals[2] }
						mode = "ret"
					elseif fin == "con" then
						value = { kind = "con", tag = f.tag, payload = vals[1] }
						mode = "ret"
					elseif fin == "call" then
						local all: { any } = {}

						for i = 2, #vals do
							table.insert(all, vals[i])
						end

						fv = vals[1]
						args = all
						mode = "apply"
					elseif fin == "delay" then
						local all: { any } = {}

						for i = 2, #vals do
							table.insert(all, vals[i])
						end

						value = { kind = "thunk", f = vals[1], args = all, done = false }
						mode = "ret"
					elseif fin == "prim" then
						const result, message = primitive(f.tag, vals)

						if message ~= nil then
							return { status = "error", message = message, steps = steps }
						end

						value = result
						mode = "ret"
					elseif fin == "if" then
						const c0 = vals[1]

						if not isInt(c0) then
							return { status = "error", message = "if needs an integer condition", steps = steps }
						end

						form = if Int.sign(c0) ~= 0 then f.t else f.e
						env = e
						mode = "eval"
					elseif fin == "let" then
						local len = #e.slots
						table.insert(k, { t = "restore", env = e, len = len })
						table.insert(e.slots, vals[1])
						form = f.body
						env = e
						mode = "eval"
					elseif fin == "case" then
						const scrut = vals[1]

						if type(scrut) ~= "table" or scrut.kind ~= "con" then
							return { status = "error", message = "case of a value that is not a constructor", steps = steps }
						end

						local branch: any = nil
						local pushed: any = nil

						for _, alt in f.alts do
							if alt.tag == scrut.tag then
								branch = alt.body
								pushed = scrut.payload

								break
							end
						end

						if branch == nil then
							if f.elseBody == nil then
								return { status = "error", message = "no branch for the constructor's tag " .. tostring(scrut.tag), steps = steps }
							end

							branch = f.elseBody
							pushed = scrut
						end

						local len = #e.slots
						table.insert(k, { t = "restore", env = e, len = len })
						table.insert(e.slots, pushed)
						form = branch
						env = e
						mode = "eval"
					elseif fin == "force" then
						const th = vals[1]

						if type(th) ~= "table" or th.kind ~= "thunk" then
							return { status = "error", message = "force of a value that is not a thunk", steps = steps }
						end

						if th.done then
							value = th.result
							mode = "ret"
						else
							table.insert(k, { t = "forcestore", thunk = th })
							fv = th.f
							args = th.args
							mode = "apply"
						end
					else
						return { status = "error", message = "machine: unknown finish " .. tostring(fin), steps = steps }
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
local function run(program: any, input: any, fuel: number): Outcome
	if type(program) ~= "table" or program.kind ~= "law" or program.arity ~= 1 then
		error("a program is a law of arity 1", 0)
	end

	return machine("apply", nil, nil, program, { input }, fuel)
end

-- Runs a form as the body of a law of arity 1, with the input as its argument. The wrapper costs no step.
local function runForm(form: any, input: any, fuel: number): Outcome
	return machine("eval", form, { slots = { NIL, input } }, nil, nil, fuel)
end

return {
	run = run,
	runForm = runForm,
	kindOf = kindOf,
	primitive = primitive,
}
