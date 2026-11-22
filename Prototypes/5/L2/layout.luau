--!strict
-- THE L2 LAYOUT LAYER
--
-- Turns an indented .l2 file into the bracketed L2 that the parser reads (see INDENTATION.md). The rewrite changes only the layout: the tokens are the same, so the tree is the same, and a file in .prog form is never passed through here.
--
-- The indentation is tabs only. A line with more indentation than the line before it is a child of that line. The rules, by the form a line starts with:
--
--   let x = e            the rest of the lines at this level are its body; if the line has children, they are the value
--   letrec x = fn args   as let, with the children as the body of the fn
--   if c                 its children are the then-branch; the next line at its level, `else`, has the children of the else-branch
--   anything else        with children, the line is an application, with its children as the further arguments
--
-- A block with one expression is wrapped in parentheses. A let, an if and an application are bracketed here, so the source has no closing brackets for them. Errors give the line of the source.
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
		local tabs = string.match(raw, "^\t*") or ""
		local content = string.sub(raw, #tabs + 1)
		content = string.gsub(content, "%s+$", "")

		if string.match(raw, "^ ") then
			fail(lineNo, "indent with tabs, not spaces")
		end

		if content ~= "" and string.sub(content, 1, 1) ~= ";" then
			local indent = #tabs

			while #stack > 0 and stack[#stack].indent >= indent do
				table.remove(stack)
			end

			local node: Node = { text = content; line = lineNo; children = {} }

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

local render: ({ Node }) -> string

-- The text of a value that has children: its header, in brackets, with the children as its body.
local function blockText(node: Node): string
	return "(" .. node.text .. "\n" .. render(node.children) .. ")"
end

-- A sequence of sibling lines is one expression. A let or an if takes the lines after it as its body.
render = function(nodes: { Node }): string
	if #nodes == 0 then
		fail(0, "a block needs an expression")
	end

	const n = nodes[1]
	const rest: { Node } = table.move(nodes, 2, #nodes, 1, {})

	local kw, body = string.match(n.text, "^(letrec) (.*)$")

	if kw == nil then
		kw, body = string.match(n.text, "^(let) (.*)$")
	end

	if kw ~= nil then
		local name, value = string.match(body :: string, "^([^=]-) = (.*)$")

		if name == nil then
			fail(n.line, "a let needs = after its name")
		end

		name = string.gsub(name :: string, "%s+$", "")

		local valueText = value :: string

		if #n.children > 0 then
			valueText = "(" .. valueText .. "\n" .. render(n.children) .. ")"
		end

		if #rest == 0 then
			fail(n.line, "a let needs a body after it")
		end

		const keyword = kw :: string
		return "(" .. keyword .. " " .. name .. " = " .. valueText .. "\n" .. render(rest) .. ")"
	end

	local cond = string.match(n.text, "^if (.*)$")

	if cond ~= nil then
		if #n.children == 0 then
			fail(n.line, "an if needs its then-branch below it")
		end

		if #rest == 0 or rest[1].text ~= "else" or #rest[1].children == 0 then
			fail(n.line, "an if needs an else line, with its branch below it, at the same indent")
		end

		if #rest > 1 then
			fail(rest[2].line, "an else ends the if, and more lines follow it")
		end

		return "(if " .. (cond :: string) .. "\n(" .. render(n.children) .. ")\n(" .. render(rest[1].children) .. "))"
	end

	if n.text == "else" then
		fail(n.line, "an else with no if before it")
	end

	if #rest > 0 then
		fail(rest[1].line, "a line with no body is followed by more lines")
	end

	if #n.children > 0 then
		return blockText(n)
	end

	return n.text
end

M.layout = function(text: string): string
	const roots = buildTree(text)

	if #roots == 0 then
		fail(0, "the file is empty")
	end

	return render(roots)
end

return M
