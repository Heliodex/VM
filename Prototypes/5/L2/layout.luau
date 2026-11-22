--!strict
-- THE L2 LAYOUT LAYER
--
-- Turns an indented .l2 file into the bracketed L2 that the parser reads (INDENTATION.md). The rewrite changes only the layout: the same tokens come out, so the tree is the same. A file in .prog form never passes through here.
--
-- The indentation is tabs only. A line with more indentation than the line before it is a child of that line. The forms:
--
--   let x = e              the lines after it at its level are its body; children, if any, are the value
--   letrec x = fn args     as let; the children are the body of the fn
--   let                    children are bindings, name = value; the lines after it at its level are the body: the block form let { }
--   letrec                 as let, with bindings that are fns: the block form letrec { }, a mutual group
--   fn args                children are its body, a sequence of lines
--   if c                   children are the then-branch; the else line at the same level has the else-branch
--   match e                children are the arms: `pat -> body`, or `pat` with children and then a `->` line
--   cond                   children are clauses: `test -> body`, or `_ -> body`
--   with e                 children are the field lines: name = value
--   C                      with children that are field lines: a record literal, or a record pattern in an arm
--   type T = C             children are the field lines of a record declaration: name: Type
--   f                      any other line with children: an application, the children its arguments, one per line
--
-- Brackets, and the braces of match, cond, with and records, are added here. A block of one expression is bracketed.
--
--   Layout.layout(text): string        raises an error, with the line, if the text does not lay out

export type Node = { text: string; line: number; children: { Node } }

local M = {}

local function fail(line: number, msg: string)
	error(string.format("line %d: %s", line, msg), 0)
end

-- The lines of the source as a tree: each line is a node, and the lines indented under it are its children.
local function buildTree(text: string): { Node }
	local roots: { Node } = {}
	local stack: { { indent: number; node: Node } } = {}
	local lineNo = 0

	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		lineNo += 1

		if string.match(raw, "^ ") then
			fail(lineNo, "indent with tabs, not spaces")
		end

		local tabs = string.match(raw, "^\t*") or ""
		local content = string.gsub(string.sub(raw, #tabs + 1), "%s+$", "")

		if content ~= "" and string.sub(content, 1, 1) ~= ";" then
			const indent = #tabs

			while #stack > 0 and stack[#stack].indent >= indent do
				table.remove(stack)
			end

			const node: Node = { text = content; line = lineNo; children = {} }

			if #stack == 0 then
				table.insert(roots, node)
			else
				table.insert(stack[#stack].node.children, node)
			end

			table.insert(stack, { indent = indent; node = node })
		end
	end

	return roots
end

local expr: (Node) -> string
local seq: ({ Node }) -> string

-- Whether every child is a field line, name = value.
local function allFields(children: { Node }): boolean
	if #children == 0 then
		return false
	end

	for _, c in children do
		if string.match(c.text, "^[%l_][%w_]* = ") == nil then
			return false
		end
	end

	return true
end

-- The field lines of a record, a with, or a record pattern, one to a line, inside its braces.
local function fieldLines(children: { Node }): string
	local out: { string } = {}

	for _, c in children do
		local name, value = string.match(c.text, "^([%l_][%w_]*) = (.*)$")

		if name == nil then
			fail(c.line, "a field is written name = value")
		end

		if #c.children > 0 then
			table.insert(out, name :: string .. " = " .. expr({ text = value :: string; line = c.line; children = c.children }))
		else
			table.insert(out, name :: string .. " = " .. (value :: string))
		end
	end

	return table.concat(out, "\n")
end

-- The arms of a match or the clauses of a cond. An arm may be `pat -> body`, or `pat` with children (a record pattern) and a `->` line after it.
local function armLines(children: { Node }): string
	local out: { string } = {}
	local i = 1

	while i <= #children do
		local c = children[i]
		const nxt = children[i + 1]

		if #c.children > 0 and nxt ~= nil and string.sub(nxt.text, 1, 2) == "->" then
			local body = string.gsub(string.sub(nxt.text, 3), "^ ", "")

			if #nxt.children > 0 then
				body = "(" .. seq(nxt.children) .. ")"
			end

			table.insert(out, c.text .. " {\n" .. fieldLines(c.children) .. "\n} -> " .. body)
			i += 2
		else
			local pat, body = string.match(c.text, "^(.-) %-> (.*)$")

			if pat == nil then
				pat = string.match(c.text, "^(.-) %->$")

				if pat == nil then
					fail(c.line, "an arm is written pat -> body")
				end

				if #c.children == 0 then
					fail(c.line, "an arm needs a body after its ->")
				end

				body = "(" .. seq(c.children) .. ")"
			elseif #c.children > 0 then
				fail(c.line, "an arm with a body on its line has no lines below it")
			end

			table.insert(out, (pat :: string) .. " -> " .. (body :: string))
			i += 1
		end
	end

	return table.concat(out, "\n")
end

-- A match, a cond or a with, as an expression: its own braces.
local function braced(n: Node): string?
	local scrut = string.match(n.text, "^match (.*)$")

	if scrut ~= nil then
		if #n.children == 0 then
			fail(n.line, "a match needs arms below it")
		end

		return "match " .. (scrut :: string) .. " {\n" .. armLines(n.children) .. "\n}"
	end

	if n.text == "cond" then
		if #n.children == 0 then
			fail(n.line, "a cond needs clauses below it")
		end

		return "cond {\n" .. armLines(n.children) .. "\n}"
	end

	local base = string.match(n.text, "^with (.*)$")

	if base ~= nil then
		if #n.children == 0 then
			fail(n.line, "a with needs field lines below it")
		end

		return "with " .. (base :: string) .. " {\n" .. fieldLines(n.children) .. "\n}"
	end

	return nil
end

-- One expression from one line and the lines below it.
expr = function(n: Node): string
	local b = braced(n)

	if b ~= nil then
		return b
	end

	if string.match(n.text, "^[%u]") and allFields(n.children) then
		return n.text .. " {\n" .. fieldLines(n.children) .. "\n}"
	end

	if #n.children == 0 then
		return n.text
	end

	if string.match(n.text, "^fn ") then
		return "(" .. n.text .. "\n" .. seq(n.children) .. ")"
	end

	if string.match(n.text, "^if ") or string.match(n.text, "^let ") or string.match(n.text, "^letrec ") then
		fail(n.line, "a let or an if takes its body on the lines after it, not as an argument")
	end

	local args: { string } = {}

	for _, c in n.children do
		table.insert(args, expr(c))
	end

	return "(" .. n.text .. "\n" .. table.concat(args, "\n") .. ")"
end

-- A let or letrec: its value, then the lines after it as its body.
local function letText(n: Node, rest: { Node }): string
	local kw, body = string.match(n.text, "^(letrec) (.*)$")

	if kw == nil then
		kw, body = string.match(n.text, "^(let) (.*)$")
	end

	local name, value = string.match(body :: string, "^([%l_][%w_]*) = (.*)$")

	if name == nil then
		fail(n.line, "a let is written let name = value")
	end

	local valueText: string

	if #n.children > 0 then
		valueText = expr({ text = value :: string; line = n.line; children = n.children })
	else
		valueText = value :: string
	end

	if #rest == 0 then
		fail(n.line, "a let needs a body after it")
	end

	return "(" .. (kw :: string) .. " " .. (name :: string) .. " = " .. valueText .. "\n" .. seq(rest) .. ")"
end

-- An if with its else line, as the branches of a bracketed if.
local function ifText(n: Node, rest: { Node }): string
	local cond = string.match(n.text, "^if (.*)$") :: string

	if #n.children == 0 then
		fail(n.line, "an if needs its then-branch below it")
	end

	if #rest == 0 or rest[1].text ~= "else" or #rest[1].children == 0 then
		fail(n.line, "an if needs an else line at its own level, with the else-branch below it")
	end

	if #rest > 1 then
		fail(rest[2].line, "an else ends the if, and more lines follow it")
	end

	return "(if " .. cond .. "\n(" .. seq(n.children) .. ")\n(" .. seq(rest[1].children) .. "))"
end

-- A let or letrec block: its children are the bindings, name = value, and the lines after it at its own level are the body.
local function blockLet(n: Node, rest: { Node }): string
	local kw = n.text

	if #n.children == 0 then
		fail(n.line, string.format("%s needs its bindings below it", kw))
	end

	if #rest == 0 then
		fail(n.line, string.format("%s needs its body on the lines after it, at the same level", kw))
	end

	local out: { string } = { kw .. " {" }

	for _, c in n.children do
		const name, value = string.match(c.text, "^([%l_][%w_]*) = (.*)$")

		if name == nil then
			fail(c.line, "the lines below a let or letrec are bindings, name = value; its body is at the same level as the let")
		end

		local valueText: string

		if #c.children > 0 then
			valueText = expr({ text = value :: string; line = c.line; children = c.children })
		else
			valueText = value :: string
		end

		table.insert(out, (name :: string) .. " = " .. valueText)
	end

	table.insert(out, "(" .. seq(rest) .. ")")
	table.insert(out, "}")

	return table.concat(out, "\n")
end

-- A sequence of sibling lines: one expression. A let or an if takes the lines after it as its body.
seq = function(nodes: { Node }): string
	if #nodes == 0 then
		fail(0, "a block needs an expression")
	end

	const n = nodes[1]
	const rest: { Node } = table.move(nodes, 2, #nodes, 1, {})

	if n.text == "let" or n.text == "letrec" then
		return blockLet(n, rest)
	end

	if string.match(n.text, "^let ") or string.match(n.text, "^letrec ") then
		return letText(n, rest)
	end

	if string.match(n.text, "^if ") then
		return ifText(n, rest)
	end

	if n.text == "else" then
		fail(n.line, "an else with no if before it")
	end

	if #rest > 0 then
		fail(rest[1].line, "a line is followed by more lines, but it is not a let or an if")
	end

	return expr(n)
end

-- The top of the file: record declarations, then the expression.
local function program(roots: { Node }): string
	local out: { string } = {}
	local i = 1

	while i <= #roots and string.match(roots[i].text, "^type ") do
		const d = roots[i]

		if #d.children > 0 then
			local lines: { string } = {}

			for _, c in d.children do
				if string.match(c.text, "^[%l_][%w_]*: ") == nil then
					fail(c.line, "a record field is written name: Type")
				end

				table.insert(lines, c.text)
			end

			table.insert(out, d.text .. " {\n" .. table.concat(lines, "\n") .. "\n}")
		else
			table.insert(out, d.text)
		end

		i += 1
	end

	local body = table.move(roots, i, #roots, 1, {})

	if #body == 0 then
		fail(0, "a program needs an expression after its declarations")
	end

	table.insert(out, seq(body))

	return table.concat(out, "\n")
end

M.layout = function(text: string): string
	const roots = buildTree(text)

	if #roots == 0 then
		fail(0, "the file is empty")
	end

	return program(roots)
end

return M
