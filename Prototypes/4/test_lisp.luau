--!strict
-- TESTS OF THE COMMAND LINE
--
-- Runs lisp.luau as a program, the way a user would, and checks what it prints and how it exits.
-- Run with: lute run test_lisp.luau
-- The checks in validate.luau cover the session and the values; these cover the runner and the REPL.

const fs = require "@std/fs"
const process = require "@std/process"

local total = 0
local failures = 0

local function report(
	ok: boolean,
	label: string
)
	total += 1

	if not ok then
		failures += 1
	end

	print(`{if ok then "PASS" else "FAIL"}  {label}`)
end

-- Runs lisp.luau with the given arguments, optionally feeding `input` to its standard input through the shell.
local function lisp(
	args: { string },
	input: string?
): (string, number)
	local result
	if input == nil then
		result = process.run({ "lute", "run", "lisp.luau", table.unpack(args) })
	else
		result = process.run({ "/bin/sh", "-c", `printf '%s' '{input}' | lute run lisp.luau` })
	end

	return result.stdout, result.exitcode
end

-- The expression mode.
do
	const out, code = lisp({ "-e", "(+ 2 3)" })
	report(out == "5\n" and code == 0, "-e prints the value of an expression")

	const outErr, codeErr = lisp({ "-e", "(+ 'a 1)" })
	report(outErr == "#error\n" and codeErr == 0, "-e prints #error for a wrong-kind value")

	const outBad, codeBad = lisp({ "-e", "(car" })
	report(string.find(outBad, "never closed", 1, true) ~= nil and codeBad == 1, "-e exits with 1 on a reader error")

	const outUnbound, codeUnbound = lisp({ "-e", "(nope 1)" })
	report(string.find(outUnbound, "unbound name nope", 1, true) ~= nil and codeUnbound == 1, "-e reports an unbound name and exits with 1")
end

-- The file mode: each expression's value, in order, and definitions without output.
do
	const path = "lisp_test_program.lisp"
	fs.writeStringToFile(path, "(define sq (lambda (n) (* n n)))\n(sq 4)\n(sq 5)\n")
	const out, code = lisp({ path })
	report(out == "16\n25\n" and code == 0, "a file prints the value of each expression")
	fs.remove(path)
end

-- The REPL, fed by the shell: definitions persist, errors do not stop it, and :quit leaves.
do
	const out, code = lisp({}, "(define x 4)\n(* x x)\n(car 1)\n:quit\n")
	report(string.find(out, "16", 1, true) ~= nil and string.find(out, "#error", 1, true) ~= nil and code == 0, "the REPL keeps definitions and prints values")
	report(string.find(out, ";; defined x", 1, true) ~= nil, "the REPL says what it defined")
end

-- A form spread over several lines is read as one.
do
	const out, code = lisp({}, "(define f (lambda (n)\n(+ n 1)))\n(f 1)\n:quit\n")
	report(string.find(out, "2", 1, true) ~= nil and code == 0, "the REPL reads a form that runs over several lines")
end

print(`{total - failures} of {total} checks passed`)

if failures > 0 then
	process.exit(1)
end
