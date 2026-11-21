--!strict
-- SESSIONS
--
-- A session keeps the definitions it has been given, so that a later input can use them, as in a REPL. Each form of an input is one of three results:
--   defined  a definition, which is now in the session
--   value    an expression, with its value (nil if it did not finish within the budget) and how its reduction ended
--   error    a form that could not be read or compiled, with what went wrong and the byte offset where it was found
-- An error in one form does not stop the others, and it does not change the session.
--
--   const Session = require "./session"
--
--   local session = Session.new()
--   for _, result in Session.evaluate(session, "(define double (lambda (n) (+ n n))) (double 4)", 400000) do
--       -- result.kind is "defined", then "value"
--   end

const H = require "../engine/harness"
const Compile = require "./compile"
const Reader = require "./reader"
const V = require "./values"

export type Result = {
	kind: "defined" | "value" | "error",
	name: string?,
	value: V.Value?,
	outcome: string?,
	steps: number?,
	message: string?,
	at: number?,
}
export type Session = {
	compile: Compile.Session,
}

-- A new session, with no definitions.
const function new(): Session
	return {
		compile = Compile.newSession(),
	}
end

-- An error's message, without the position that the compiler puts in front of it.
const function messageOf(err: any): string
	local text = tostring(err)
	-- errors raised in the compiler start with "file:line: "
	local stripped = string.gsub(text, "^[^%s]*%.luau:%d+: ", "")

	return stripped
end

-- The name a definition gives, from its form.
local function nameOf(form: Reader.Expr): string?
	const items = form.items

	if items == nil or items[2] == nil or items[2].kind ~= "sym" then
		return nil
	end

	return items[2].name
end

-- The results of a form, built with their kinds fixed.
local function definedResult(name: string?): Result
	return {
		kind = "defined",
		name = name,
	}
end

local function valueResult(value: V.Value?, outcome: string, steps: number): Result
	return {
		kind = "value",
		value = value,
		outcome = outcome,
		steps = steps,
	}
end

local function errorResult(message: string, at: number?): Result
	return {
		kind = "error",
		message = message,
		at = at,
	}
end

-- Evaluates each form of `source` in order, in the session, and returns one result for each. `budget` is the number of steps each expression may take. `plain` says the budget is only a limit: a form that uses it up is reported as not finishing, without the cycle check that tests use (see harness.luau).
const function evaluate(session: Session, source: string, budget: number, plain: boolean?): { Result }
	const results: { Result } = {}
	const readOk, forms = pcall(Reader.read, source)

	if not readOk then
		table.insert(results, errorResult(messageOf(forms), nil))

		return results
	end

	for _, form in forms :: { Reader.Expr } do
		if Compile.isDefinition(form) then
			const ok, err = pcall(Compile.define, session.compile, form)

			if ok then
				table.insert(results, definedResult(nameOf(form)))
			else
				table.insert(results, errorResult(messageOf(err), Compile.failedAt()))
			end
		else
			const expression = Compile.expression(session.compile, form)
			const ok, report, value = pcall(V.read, expression, budget, plain)

			if ok then
				table.insert(results, valueResult(value, (report :: H.Report).outcome, (report :: H.Report).steps))
			else
				table.insert(results, errorResult(messageOf(report), Compile.failedAt()))
			end
		end
	end

	return results
end

return {
	new = new,
	evaluate = evaluate,
}
