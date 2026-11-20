--!strict
-- THE L2 ENTRY POINT
--
-- Compiles an L2 program file, with its imports, to a machine expression, and evaluates the L2 expressions of its tests on that machine. The stages are the parser (parser.luau), the desugarer (desugar.luau), and the machine (interpreter/vm.luau). The type checker is not in the pipeline yet.
--
--   L2.compile(text, resolve, name): Compiled    raises an error, with the file's line, if the file does not compile
--   L2.evalText(compiled, text, fuel): Value     evaluates an expression of the file, with its imports in scope
--   L2.run(compiled, input, fuel): Result        applies the program to the input, as the lifecycle does
--
-- resolve takes a path from the top of the programs folder and gives the text of that file, or nil if there is none.

const VM = require "../interpreter/vm"
const Lifecycle = require "../interpreter/lifecycle"
const Parser = require "./parser"
const Desugar = require "./desugar"
const ProgramFile = require "./programfile"

const VALUE_FUEL = 1000000

export type Compiled = {
	expr: VM.Expr,
	names: { string },
	values: { VM.Expr },
	ctors: { [string]: Desugar.Ctor },
}

-- An error from the parser or the desugarer counts lines from the start of the program section. This moves it to the line of the file.
local function atFileLine(
	err: unknown,
	firstLine: number
): string
	const msg = tostring(err)
	const line, column, rest = string.match(msg, "^line (%d+), column (%d+): (.*)$")

	if line ~= nil and column ~= nil and rest ~= nil then
		return string.format("line %d, column %s: %s", (tonumber(line) :: number) + firstLine - 1, column, rest)
	end

	return msg
end

local compileFile: (text: string, resolve: (string) -> string?, name: string, stack: { string }) -> Compiled

compileFile = function(
	text: string,
	resolve: (string) -> string?,
	name: string,
	stack: { string }
): Compiled
	const file = ProgramFile.parse(text)
	local parsed: Parser.Program? = nil

	local ok, err = pcall(function()
		parsed = Parser.parse(file.program)
	end)

	if not ok then
		error(atFileLine(err, file.programLine), 0)
	end

	const program = parsed :: Parser.Program
	const ctors = Desugar.buildCtors(program.decls)
	local names: { string } = {}
	local values: { VM.Expr } = {}
	const chain = table.clone(stack)
	table.insert(chain, name)

	for _, import in file.imports do
		if table.find(chain, import.file) ~= nil then
			error(string.format("line %d: the imports form a cycle through %s", import.line, import.file), 0)
		end

		const importText = resolve(import.file)

		if importText == nil then
			error(string.format("line %d: cannot find %s", import.line, import.file), 0)
		end

		const sub = compileFile(importText :: string, resolve, import.file, chain)
		table.insert(names, import.name)
		table.insert(values, sub.expr)
	end

	local expr: VM.Expr

	ok, err = pcall(function()
		expr = Desugar.wrapImports(Desugar.desugarProgram(program, names, ctors), values)
	end)

	if not ok then
		error(atFileLine(err, file.programLine), 0)
	end

	return {
		expr = expr,
		names = names,
		values = values,
		ctors = ctors,
	}
end

local function compile(
	text: string,
	resolve: (string) -> string?,
	name: string
): Compiled
	return compileFile(text, resolve, name, {})
end

local function evalText(
	compiled: Compiled,
	text: string,
	fuel: number
): VM.Value
	const parsed = Parser.parse(text)
	const expr = Desugar.wrapImports(Desugar.desugarExpr(parsed.expr, compiled.names, compiled.ctors), compiled.values)
	const result = VM.run(expr, fuel)

	if result.status ~= "value" then
		error(string.format("the expression %s %s", text, if result.status == "error" then "raises an error: " .. result.message else "runs out of fuel"), 0)
	end

	return result.value
end

local function run(
	compiled: Compiled,
	input: VM.Value,
	fuel: number
): Lifecycle.Result
	return Lifecycle.run(compiled.expr, input, fuel)
end

return {
	compile = compile,
	evalText = evalText,
	run = run,
	VALUE_FUEL = VALUE_FUEL,
}
