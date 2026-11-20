--!strict
-- THE PRINTER
--
-- Writes an expression as text in the reader's syntax, so that reading the text gives back the same expression. It is the reverse of reader.luau, for programs that exist only as expressions, and for showing a program in the form it is written in.
--
-- The machine has no names, so the printer invents them. The binder of a fn is named by its depth: the first fn, the outermost, is v0, and a lam inside it is v1, and so on. A variable with index i, under d binders, refers to the binder at depth d - 1 - i, and so is printed with that binder's name. A variable that points past the outermost binder is not bound by anything, so it cannot be printed, and printing it is an error.
--
-- A chain of applications is printed flat, (f a b), which the reader reads as ((f a) b), so the expression is the same.
--
--   Printer.print(e): string      raises an error for a variable that is not bound

const VM = require "../interpreter/vm"
const Primitives = require "../interpreter/primitives"

const function binderName(
	depth: number
): string
	return `v{depth}`
end

-- Prints e, which has depth binders around it.
local printAt: (e: VM.Expr, depth: number) -> string

printAt = function(
	e: VM.Expr,
	depth: number
): string
	if e.op == "quote" then
		if e.value == VM.NIL then
			return "~"
		end

		return tostring(e.value)
	elseif e.op == "var" then
		const binder = depth - 1 - e.index

		if binder < 0 then
			error(`a variable with index {e.index} has no binder around it`, 0)
		end

		return binderName(binder)
	elseif e.op == "lam" then
		return `(fn {binderName(depth)} {printAt(e.body, depth + 1)})`
	elseif e.op == "pin" then
		return `(pin {printAt(e.e, depth)})`
	elseif e.op == "cell" then
		-- Walk the spine of right-nested cells: every head is an item, and the tail that is not a cell is the last item.
		local parts: { string } = {}
		local cur: VM.Expr = e

		while cur.op == "cell" do
			table.insert(parts, printAt((cur :: VM.CellExpr).head, depth))
			cur = (cur :: VM.CellExpr).tail
		end

		table.insert(parts, printAt(cur, depth))
		return "[" .. table.concat(parts, " ") .. "]"
	elseif e.op == "head" then
		return `(head {printAt(e.e, depth)})`
	elseif e.op == "tail" then
		return `(tail {printAt(e.e, depth)})`
	elseif e.op == "force" then
		return `(force {printAt(e.e, depth)})`
	elseif e.op == "if" then
		return `(if {printAt(e.c, depth)} {printAt(e.t, depth)} {printAt(e.e, depth)})`
	end

	if e.op == "apply" then
		-- Walk down the chain of applications, collecting the arguments in order.
		local args: { VM.Expr } = {}
		local f: VM.Expr = e

		while f.op == "apply" do
			table.insert(args, 1, f.arg)
			f = f.f
		end

		local parts = { printAt(f, depth) }

		for _, arg in args do
			table.insert(parts, printAt(arg, depth))
		end

		return "(" .. table.concat(parts, " ") .. ")"
	end

	-- The only expression left is a primitive. Kind is unary, and the rest are binary.
	if e.op == "prim" then
		if e.b == nil then
			return `(kind {printAt(e.a, depth)})`
		end

		return `({Primitives.BY_TAG[e.tag].symbol} {printAt(e.a, depth)} {printAt((e.b :: VM.Expr), depth)})`
	end

	error("unknown expression", 0)
end

-- Prints a whole program. Its outermost binders are the ones the reader gives to a fn, from depth 0.
const function print(
	e: VM.Expr
): string
	return printAt(e, 0)
end

return {
	print = print,
}
