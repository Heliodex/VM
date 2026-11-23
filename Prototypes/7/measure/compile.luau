--!strict
-- COMPILES AN L2 FILE FOR THE PHASE 0 MEASUREMENT
--
-- Does what Prototype 6's L2.compile does, including the imports, and times each host stage: the layout, the Luau parser, the Luau checker, and the desugarer. Imports are compiled the same way, recursively, and their times are added up in imports. The compiled program is the same expression that L2.compile gives, except that every node carries an owner: the name of the function whose body contains it ("top" outside any function). The owner is what the profile charges steps to.
--
-- The raw program section is kept too. The VM's layout stage reads the raw section, so it is what a VM build starts from. The host layout is run here on the same section, and the two results are compared by the driver.

const fs = require "@lute/fs"
const ProgramFile = require "../../6/L2/programfile"
const Layout = require "../../6/L2/layout"
const Parser = require "../../6/L2/parser"
const Checker = require "../../6/L2/checker"
const Desugar = require "./desugar_named"

const PROGRAMS = "../../6/L2/programs/"

export type Timings = {
	layout: number,
	parse: number,
	check: number,
	desugar: number,
	-- The host time of every imported file, compiled inside this one.
	imports: number,
}

export type Compiled = {
	expr: any,
	scheme: any,
	timings: Timings,
	-- The program section after the host layout pass: bracketed text, which the Luau parser reads.
	source: string,
	-- The program section before layout: indented text, which the VM's layout stage reads.
	raw: string,
}

-- Gives each node its owner, top-down. A lambda with a label starts a new owner; a node that is already owned is not visited again, so a shared node keeps its first owner.
const function annotate(root: any)
	local work: { { any } } = { { root, "top" } }

	while #work > 0 do
		const item = table.remove(work) :: { any }
		const node = item[1]
		local owner = item[2] :: string

		if node.owner == nil then
			if node.op == "lam" and node.label ~= nil then
				owner = node.label
			end

			node.owner = owner

			for _, child in node do
				if type(child) == "table" and child.op ~= nil then
					table.insert(work, { child, owner })
				end
			end
		end
	end
end

const function resolve(name: string): string?
	const ok, text = pcall(function()
		const handle = fs.open(PROGRAMS .. name)
		const body = fs.read(handle)
		fs.close(handle)

		return body
	end)

	if ok then
		return text :: string
	end

	return nil
end

local compileFile: (text: string, name: string, stack: { string }) -> Compiled
compileFile = function(text: string, name: string, stack: { string }): Compiled
	-- A name that does not end in .l2 means the program section is not laid out by ProgramFile, so it is the raw indented text.
	const file = ProgramFile.parse(text, nil)
	const raw = file.program :: string

	const layoutStart = os.clock()
	const laidOut = Layout.layout(raw)
	const layoutTime = os.clock() - layoutStart

	const parseStart = os.clock()
	const program = Parser.parse(laidOut)
	const parseTime = os.clock() - parseStart

	const names: { string } = {}
	const values: { any } = {}
	local importSchemes: { { name: string, scheme: any } } = {}
	local importTime = 0
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

		const sub = compileFile(importText :: string, import.file, chain)
		importTime += sub.timings.layout + sub.timings.parse + sub.timings.check + sub.timings.desugar + sub.timings.imports
		table.insert(names, import.name)
		table.insert(values, sub.expr)
		table.insert(importSchemes, { name = import.name, scheme = sub.scheme })
	end

	const ctors = Desugar.buildCtors(program.decls)
	const checkStart = os.clock()
	const checked = Checker.check(program, importSchemes, name)
	const checkTime = os.clock() - checkStart

	const desugarStart = os.clock()
	const expr = Desugar.boundary(Desugar.wrapImports(Desugar.desugarProgram(checked.expr, names, ctors), values), checked.input, checked.inputExpect)
	const desugarTime = os.clock() - desugarStart

	annotate(expr)

	return {
		expr = expr,
		scheme = checked.scheme,
		source = laidOut,
		raw = raw,
		timings = {
			layout = layoutTime,
			parse = parseTime,
			check = checkTime,
			desugar = desugarTime,
			imports = importTime,
		},
	}
end

local function compile(text: string, name: string): Compiled
	return compileFile(text, name, {})
end

return {
	compile = compile,
	annotate = annotate,
}
