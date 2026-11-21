--!strict
-- THE L2 PROGRAM FILE
--
-- The four-section format of L1 (interpreter-independent text), for L2 programs: a header, the imports, the program, and the tests, separated by lines that hold only ---. The imports are name = path lines, and a path is from the top of the programs folder. A test is an input, then =>, then an output, then fuel and a number of steps. It is one line, or it continues onto the lines after it that are indented, so the input or the output may span lines. The input and output are L2 expressions, and they may use the imports.
--
--   ProgramFile.parse(text): File     raises an error, with the line, if the file is not well formed
--
-- The program and the test expressions are not compiled here: that is l2.luau's job, so this module only splits the file.

export type Import = { line: number; name: string; file: string }
export type Test = { line: number; input: string; outcome: string; output: string?; fuel: number }
export type File = {
	header: string,
	imports: { Import },
	program: string,
	programLine: number,
	tests: { Test },
}

local function trim(s: string): string
	return string.match(s, "^%s*(.-)%s*$") :: string
end

local function splitLines(text: string): { string }
	local lines: { string } = {}

	for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
		table.insert(lines, (string.gsub(line, "\r$", "")))
	end

	return lines
end

local function parseImport(text: string, lineNo: number): Import
	const name, file = string.match(text, "^(%S+)%s*=%s*(%S+)$")

	if name == nil or file == nil then
		error(string.format("line %d: an import is name = path, but this is %s", lineNo, text), 0)
	end

	return { line = lineNo; name = name :: string; file = file :: string }
end

local function parseTest(text: string, lineNo: number): Test
	const arrow = string.find(text, " => ", 1, true)

	if arrow == nil then
		error(string.format("line %d: a test needs => between its input and its output", lineNo), 0)
	end

	const input = trim(string.sub(text, 1, arrow - 1))
	const rest = string.sub(text, arrow + 4)
	const fuelAt = string.find(rest, " fuel ", 1, true)

	if fuelAt == nil then
		error(string.format("line %d: a test needs fuel and a number of steps after its output", lineNo), 0)
	end

	const output = trim(string.sub(rest, 1, fuelAt - 1))
	const fuelText = trim(string.sub(rest, fuelAt + 6))

	if not string.match(fuelText, "^%d+$") or tonumber(fuelText) == 0 then
		error(string.format("line %d: fuel must be a whole number above zero, not %s", lineNo, fuelText), 0)
	end

	local outcome = "value"
	local outputText: string? = output

	if output == "error" or output == "out_of_fuel" or output == "not_data" then
		outcome = output
		outputText = nil
	end

	return {
		line = lineNo,
		input = input,
		outcome = outcome,
		output = outputText,
		fuel = tonumber(fuelText) :: number,
	}
end

local function parse(text: string): File
	const lines = splitLines(text)
	local separators: { number } = {}

	for i, line in lines do
		if trim(line) == "---" then
			table.insert(separators, i)
		end
	end

	if #separators ~= 3 then
		error(string.format("a program file has four sections, separated by three lines of ---, but this one has %d such lines", #separators), 0)
	end

	const first = separators[1]
	const second = separators[2]
	const third = separators[3]
	local imports: { Import } = {}
	local seen: { [string]: boolean } = {}

	for i = first + 1, second - 1 do
		const line = trim(lines[i])

		if line ~= "" then
			const import = parseImport(line, i)

			if seen[import.name] then
				error(string.format("line %d: %s is imported twice", i, import.name), 0)
			end

			seen[import.name] = true
			table.insert(imports, import)
		end
	end

	-- A test starts on a line of its own. Lines after it that start with a space or a tab continue it, so an input or an output may span lines.
	local tests: { Test } = {}
	local i = third + 1

	while i <= #lines do
		if trim(lines[i]) == "" then
			i += 1
		else
			const start = i
			local parts: { string } = { lines[i] }
			i += 1

			while i <= #lines and trim(lines[i]) ~= "" and string.match(lines[i], "^[ \t]") ~= nil do
				table.insert(parts, lines[i])
				i += 1
			end

			table.insert(tests, parseTest(table.concat(parts, "\n"), start))
		end
	end

	if #tests == 0 then
		error("a program file needs at least one test", 0)
	end

	return {
		header = table.concat(lines, "\n", 1, first - 1),
		imports = imports,
		program = table.concat(lines, "\n", second + 1, third - 1),
		programLine = second + 1,
		tests = tests,
	}
end

return {
	parse = parse,
}
