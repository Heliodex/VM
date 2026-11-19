--!strict
-- THE PROGRAM FILE
--
-- A program file keeps a program with its documentation, the programs it uses, and its tests. It has four sections, separated by lines that hold only ---:
--
--   header text, for people, which is not read
--   ---
--   imports, one to a line: name = file
--   ---
--   the program, in the reader's syntax
--   ---
--   the tests, one to a line
--
-- An import binds name, inside the program, to the program of another file. The file is a path from the top of the programs folder, such as double.prog or lib/triple.prog, and it is read with the same format, so it can import in turn. The name is then a function the program can call. An imported program is closed: it cannot use the names of the file that imports it. Imports may not form a cycle, and a file may not import itself through others.
--
-- A test line is an input, then =>, then an output, then fuel and a number of steps:
--
--   <input> => <output> fuel <n>
--
-- The input and a value output are written in the reader's language, and each is evaluated to a value before the test runs. The names of the file's imports are in scope for them, so a test can call an imported function. An input may be a function, since it is only given to the program. An output must be data, since two functions cannot be compared, so a function there is refused. An output may instead be one of the outcomes of a run, error, out_of_fuel or not_data, when the test expects that outcome. Blank lines in the test section are skipped. A file needs at least one test.
--
--   ProgramFile.parse(text, resolve?, name?): File   raises an error, with the line, if the file is not well formed
--
-- resolve takes a file name and gives the text of that file, or nil if there is none. It is needed only when the file has imports. name is the name of this file, which is used to detect cycles.

const Data = require "../interpreter/data"
const Reader = require "./reader"
const VM = require "../interpreter/vm"

-- The budget for evaluating a test's input or expected output. These are literal values, so the budget only has to be generous.
const VALUE_FUEL = 1000000

export type Resolve = (name: string) -> string?

export type Test = {
	line: number,
	input: VM.Value,
	outcome: string,
	output: string?,
	fuel: number,
}

export type Import = {
	line: number,
	name: string,
	file: string,
}

export type File = {
	header: string,
	imports: { Import },
	program: VM.Expr,
	programLine: number,
	tests: { Test },
}

const function trim(
	s: string
): string
	return (string.match(s, "^%s*(.-)%s*$") :: string)
end

-- The lines of a text. The last line may be empty, if the text ends with a newline.
const function splitLines(
	text: string
): { string }
	local lines: { string } = {}

	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, (string.gsub(line, "\r$", "")))
	end

	return lines
end

-- The value that a source text gives in the reader's language. It must give a value, not an error or an out of fuel, and the error for a text that does not read or run is given the line of the test. what says which part of the test it is, for the message.
const function evalValue(
	text: string,
	lineNo: number,
	what: string,
	names: { string },
	values: { VM.Expr }
): VM.Value
	const ok, expr = pcall(Reader.parseWith, text, names, values)

	if not ok then
		error(`line {lineNo}: the {what}: {(string.gsub(tostring(expr), "^line %d+: ", ""))}`, 0)
	end

	const result = VM.run(expr :: VM.Expr, VALUE_FUEL)

	if result.status == "value" then
		return result.value
	elseif result.status == "error" then
		error(`line {lineNo}: the {what} raises an error: {result.message}`, 0)
	end

	error(`line {lineNo}: the {what} runs out of fuel`, 0)
end

-- Reads one test line, which is on line lineNo of the file.
const function parseTest(
	text: string,
	lineNo: number,
	names: { string },
	values: { VM.Expr }
): Test
	const arrow = string.find(text, " => ", 1, true)

	if arrow == nil then
		error(`line {lineNo}: a test needs => between its input and its output`, 0)
	end

	const inputText = trim(string.sub(text, 1, arrow - 1))
	const rest = string.sub(text, arrow + 4)
	const fuelAt = string.find(rest, " fuel ", 1, true)

	if fuelAt == nil then
		error(`line {lineNo}: a test needs fuel and a number of steps after its output`, 0)
	end

	const outputText = trim(string.sub(rest, 1, fuelAt - 1))
	const fuelText = trim(string.sub(rest, fuelAt + 6))

	if not string.match(fuelText, "^%d+$") or tonumber(fuelText) == 0 then
		error(`line {lineNo}: fuel must be a whole number above zero, not {fuelText}`, 0)
	end

	const input = evalValue(inputText, lineNo, "input", names, values)

	local outcome: string
	local output: string? = nil

	if outputText == "error" or outputText == "out_of_fuel" or outputText == "not_data" then
		outcome = outputText
	else
		const value = evalValue(outputText, lineNo, "output", names, values)
		const okOut, written = pcall(Data.write, value)

		if not okOut then
			error(`line {lineNo}: the output is not data: {tostring(written)}`, 0)
		end

		outcome = "value"
		output = written :: string
	end

	return {
		line = lineNo,
		input = input,
		outcome = outcome,
		output = output,
		fuel = tonumber(fuelText) :: number,
	}
end

-- Reads one import line, name = file, which is on line lineNo of the file. The name must be a name the reader accepts as a variable.
const function parseImport(
	text: string,
	lineNo: number
): Import
	const name, file = string.match(text, "^(%S+)%s*=%s*(%S+)$")

	if name == nil or file == nil then
		error(`line {lineNo}: an import is name = file, but this is {text}`, 0)
	end

	if not string.match(name, "^[%a_][%w_%-]*$") or Reader.isReserved(name :: string) then
		error(`line {lineNo}: {name} is not a name that can be bound`, 0)
	end

	return {
		line = lineNo,
		name = name :: string,
		file = file :: string,
	}
end

-- A path with its . and .. parts worked out, so that two paths to one file are equal. It is nil if the path climbs above the top of the folder.
const function normalize(
	path: string
): string?
	local parts: { string } = {}

	for part in string.gmatch(path, "[^/]+") do
		if part == "." then
			-- Stays where it is.
		elseif part == ".." then
			if #parts == 0 then
				return nil
			end

			table.remove(parts)
		else
			table.insert(parts, part)
		end
	end

	return table.concat(parts, "/")
end

-- Loads the program of one file. stack holds the names of the files that are being loaded around this one, so an import of one of them is a cycle.
local parseFile: (text: string, resolve: Resolve?, name: string?, stack: { string }) -> File

parseFile = function(
	text: string,
	resolve: Resolve?,
	name: string?,
	stack: { string }
): File
	const lines = splitLines(text)
	local separators: { number } = {}

	for i, line in lines do
		if trim(line) == "---" then
			table.insert(separators, i)
		end
	end

	if #separators ~= 3 then
		error(`a program file has four sections, separated by three lines of ---, but this one has {#separators} such lines`, 0)
	end

	const first = separators[1]
	const second = separators[2]
	const third = separators[3]
	const header = table.concat(lines, "\n", 1, first - 1)

	local imports: { Import } = {}
	local seen: { [string]: boolean } = {}

	for i = first + 1, second - 1 do
		const line = trim(lines[i])

		if line ~= "" then
			const import = parseImport(line, i)

			if seen[import.name] then
				error(`line {i}: {import.name} is imported twice`, 0)
			end

			seen[import.name] = true
			table.insert(imports, import)
		end
	end

	-- The programs of the imports are loaded first. The chain is this file and the files around it, so a cycle is found on the way.
	const chain = table.clone(stack)

	if name ~= nil then
		table.insert(chain, name :: string)
	end

	local names: { string } = {}
	local values: { VM.Expr } = {}

	for _, import in imports do
		if resolve == nil then
			error(`line {import.line}: the import {import.file} needs a folder of program files`, 0)
		end

		-- An import is a path from the top of the programs folder, and it is worked out before it is looked up.
		const path = normalize(import.file)

		if path == nil then
			error(`line {import.line}: {import.file} is outside the programs folder`, 0)
		end

		if table.find(chain, path :: string) ~= nil then
			error(`line {import.line}: the imports form a cycle through {path}`, 0)
		end

		const importText = (resolve :: Resolve)(path :: string)

		if importText == nil then
			error(`line {import.line}: cannot find {import.file}`, 0)
		end

		const ok, loaded = pcall(parseFile, importText :: string, resolve, path :: string, chain)

		if not ok then
			error(`line {import.line}: the import {import.file} is not well formed: {tostring(loaded)}`, 0)
		end

		table.insert(names, import.name)
		table.insert(values, (loaded :: File).program)
	end

	const programText = table.concat(lines, "\n", second + 1, third - 1)

	local program: VM.Expr
	local ok, err = pcall(function()
		program = Reader.parseWith(programText, names, values)
	end)

	if not ok then
		-- The reader counts lines from the start of the program section, so its line k is line second + k of the file.
		const readerLine, reason = string.match(tostring(err), "^line (%d+): (.*)$")

		if readerLine then
			error(`line {second + tonumber(readerLine :: string) :: number}: {reason}`, 0)
		end

		error(`the program, which starts on line {second + 1}: {tostring(err)}`, 0)
	end

	local tests: { Test } = {}

	for i = third + 1, #lines do
		const line = trim(lines[i])

		if line ~= "" then
			table.insert(tests, parseTest(line, i, names, values))
		end
	end

	if #tests == 0 then
		error("a program file needs at least one test", 0)
	end

	return {
		header = header,
		imports = imports,
		program = program,
		programLine = second + 1,
		tests = tests,
	}
end

-- Reads a program file. See the top of this file for resolve and name.
const function parse(
	text: string,
	resolve: Resolve?,
	name: string?
): File
	return parseFile(text, resolve, name, {})
end

return {
	parse = parse,
}
