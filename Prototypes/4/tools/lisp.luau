--!strict
-- THE LISP REPL AND RUNNER
--
-- Run with lute:
--   lute run tools/lisp.luau                 a REPL: type expressions and definitions, one per line
--   lute run tools/lisp.luau program.lisp    run a file, printing the value of each expression
--   lute run tools/lisp.luau -e "(+ 1 2)"    evaluate one expression
--
-- In the REPL a form may run over several lines: input continues until its brackets are closed.
-- `:reset` forgets every definition, and `:quit` leaves.
-- Each expression may take at most BUDGET steps. An expression that does not finish in that is reported as such, and so is one that loops.
-- The exit status is 1 if any form in a file or with -e was an error.

const Printer = require "../language/printer"
const Reader = require "../language/reader"
const Session = require "../language/session"
const fs = require "@std/fs"
const io = require "@std/io"
const process = require "@std/process"

-- How many steps one expression may take.
const BUDGET = 400000

-- Where an error is, as text, if the compiler could say.
local function locationOf(at: number?): string
	if at == nil then
		return ""
	end

	return ` at byte {at}`
end

-- Prints the results of a source in the session, and returns how many of its forms were errors. Definitions are printed only if `showDefinitions` is set.
local function run(session: Session.Session, source: string, showDefinitions: boolean): number
	local errors = 0

	for _, result in Session.evaluate(session, source, BUDGET, true) do
		if result.kind == "defined" then
			if showDefinitions then
				print(`;; defined {result.name}`)
			end
		elseif result.kind == "value" then
			if result.outcome ~= "reduced" then
				print(`;; did not finish within {BUDGET} steps ({result.outcome})`)
				errors += 1
			elseif result.value == nil then
				print ";; a value that cannot be printed"
			else
				print(Printer.show(result.value))
			end
		else
			errors += 1
			print(`error{locationOf(result.at)}: {result.message}`)
		end
	end

	return errors
end

-- Splits text into its lines, without the newlines. A last line with no newline is kept.
local function linesOf(text: string): { string }
	const lines: { string } = {}
	local start = 1

	while true do
		const newline = string.find(text, "\n", start, true)

		if newline == nil then
			if start <= #text then
				table.insert(lines, string.sub(text, start))
			end

			break
		end

		table.insert(lines, string.sub(text, start, newline - 1))
		start = newline + 1
	end

	return lines
end

-- Whether the source ends inside a form, so that more lines are needed before it can be read.
local function isIncomplete(source: string): boolean
	const ok, err = pcall(Reader.read, source)

	if ok then
		return false
	end

	const message = tostring(err)

	return string.find(message, "unexpected end of input", 1, true) ~= nil or string.find(message, "is never closed", 1, true) ~= nil
end

-- The REPL. io.input returns everything that is piped in at once, and fails at its end, so the lines it returns are kept and handed out one at a time.
local function repl()
	local session = Session.new()
	local pending: { string } = {}
	local buffer = ""

	local function nextLine(prompt: string): string?
		if #pending > 0 then
			return table.remove(pending, 1)
		end

		const ok, text = pcall(io.input, prompt)

		if not ok or text == nil then
			return nil
		end

		pending = linesOf(text)

		if #pending == 0 then
			return ""
		end

		return table.remove(pending, 1)
	end

	while true do
		const line = nextLine(
			if buffer == "" then
				"lisp> "
			else
				"  ... "
		)

		if line == nil then
			break
		end

		if buffer == "" and string.match(line, "^%s*:quit%s*$") then
			break
		end

		if buffer == "" and string.match(line, "^%s*:reset%s*$") then
			session = Session.new()
			print ";; session cleared"
			continue
		end

		buffer =
			if buffer == "" then
				line
			else
				`{buffer}\n{line}`

		if string.match(buffer, "^%s*$") then
			buffer = ""
			continue
		end

		if isIncomplete(buffer) then
			continue
		end

		run(session, buffer, true)
		buffer = ""
	end
end

-- The arguments after the script's own name.
const args = process.args
local userArgs: { string } = {}

for i = 2, #args do
	table.insert(userArgs, args[i])
end

if #userArgs == 0 then
	repl()
	process.exit(0)
elseif userArgs[1] == "-e" then
	const source = userArgs[2]

	if source == nil then
		print 'usage: lute run tools/lisp.luau -e "expression"'
		process.exit(2)
	end

	const errors = run(Session.new(), source, false)
	process.exit(
		if errors > 0 then
			1
		else
			0
	)
else
	const ok, source = pcall(fs.readFileToString, userArgs[1])

	if not ok then
		print(`cannot read {userArgs[1]}`)
		process.exit(2)
	end

	const errors = run(Session.new(), source, false)
	process.exit(
		if errors > 0 then
			1
		else
			0
	)
end
