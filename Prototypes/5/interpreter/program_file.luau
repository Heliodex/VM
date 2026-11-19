--!strict
-- THE PROGRAM FILE
--
-- A program file keeps a program with its documentation and its tests. It has three sections, separated by lines that hold only ---:
--
--   header text, for people, which is not read
--   ---
--   the program, in the reader's syntax, which reader.luau reads unchanged
--   ---
--   the tests, one to a line
--
-- A test line is an input, then =>, then an output, then fuel and a number of steps:
--
--   <input> => <output> fuel <n>
--
-- An input and a value output are written in the data format of data.luau. An output may instead be one of the outcomes of a run, error, out_of_fuel or not_data, when the test expects that outcome. Blank lines in the test section are skipped. A file needs at least one test.
--
--   ProgramFile.parse(text): File      raises an error, with the line, if the file is not well formed

const Data = require "./data"
const Reader = require "./reader"
const VM = require "./vm"

export type Test = {
	line: number,
	input: VM.Value,
	outcome: string,
	output: string?,
	fuel: number,
}

export type File = {
	header: string,
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

-- The data text for a list of bytes, in the data format: cons and each byte, ending in nil. The empty list is nil.
const function bytesText(
	codes: { number }
): string
	local parts: { string } = {}

	for _, code in codes do
		table.insert(parts, "cons")
		table.insert(parts, tostring(code))
	end

	table.insert(parts, "nil")
	return table.concat(parts, " ")
end

-- Replaces each string literal in a test's text with the data text of its bytes, so a test can write "abc" where the data format would write a list. The rest of the text is kept as it is. A string that is never closed, or has a bad escape, is an error.
const function expandStrings(
	text: string,
	lineNo: number
): string
	local out: { string } = {}
	local i = 1

	while i <= #text do
		const quote = string.find(text, '"', i, true)

		if quote == nil then
			table.insert(out, string.sub(text, i))
			break
		end

		table.insert(out, string.sub(text, i, quote - 1))

		const ok, codes, after = pcall(Reader.scanString, text, quote, lineNo)

		if not ok then
			error(`line {lineNo}: {string.gsub(tostring(codes), "^line %d+: ", "")}`, 0)
		end

		table.insert(out, bytesText(codes :: { number }))
		i = after :: number
	end

	return table.concat(out)
end

-- Reads one test line, which is on line lineNo of the file.
const function parseTest(
	text: string,
	lineNo: number
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

	local input: VM.Value
	local ok, err = pcall(function()
		input = Data.read(expandStrings(inputText, lineNo))
	end)

	if not ok then
		error(`line {lineNo}: the input: {tostring(err)}`, 0)
	end

	local outcome: string
	local output: string? = nil

	if outputText == "error" or outputText == "out_of_fuel" or outputText == "not_data" then
		outcome = outputText
	else
		local okOut, value = pcall(function()
			return Data.read(expandStrings(outputText, lineNo))
		end)

		if not okOut then
			error(`line {lineNo}: the output: {tostring(value)}`, 0)
		end

		outcome = "value"
		output = Data.write(value)
	end

	return {
		line = lineNo,
		input = input,
		outcome = outcome,
		output = output,
		fuel = tonumber(fuelText) :: number,
	}
end

-- Reads a program file.
const function parse(
	text: string
): File
	const lines = splitLines(text)
	local separators: { number } = {}

	for i, line in lines do
		if trim(line) == "---" then
			table.insert(separators, i)
		end
	end

	if #separators ~= 2 then
		error(`a program file has three sections, separated by two lines of ---, but this one has {#separators} such lines`, 0)
	end

	const first = separators[1]
	const second = separators[2]
	const header = table.concat(lines, "\n", 1, first - 1)
	const programText = table.concat(lines, "\n", first + 1, second - 1)

	local program: VM.Expr
	local ok, err = pcall(function()
		program = Reader.parse(programText)
	end)

	if not ok then
		-- The reader counts lines from the start of the program section, so its line k is line first + k of the file.
		const readerLine, reason = string.match(tostring(err), "^line (%d+): (.*)$")

		if readerLine then
			error(`line {first + tonumber(readerLine :: string) :: number}: {reason}`, 0)
		end

		error(`the program, which starts on line {first + 1}: {tostring(err)}`, 0)
	end

	local tests: { Test } = {}

	for i = second + 1, #lines do
		const line = trim(lines[i])

		if line ~= "" then
			table.insert(tests, parseTest(line, i))
		end
	end

	if #tests == 0 then
		error("a program file needs at least one test", 0)
	end

	return {
		header = header,
		program = program,
		programLine = first + 1,
		tests = tests,
	}
end

return {
	parse = parse,
}
