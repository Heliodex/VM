--!strict
-- THE PROGRAM AS DATA
--
-- A program is an Expr, which the machine runs. This module turns it into a data value and back, so a program can be stored and sent as data, and the self-interpreter can read it.
--
-- A program is quoted as a pair [tag args], where tag is an integer for the form and args is a proper list of its parts:
--
--   0 quote, args (value)           1 nil, args ()           2 var, args (index)
--   3 lam, args (body)              4 pin, args (e)          5 cell, args (head tail)
--   6 head, args (e)                7 tail, args (e)         8 force, args (e)
--   9 if, args (c t e)             10 apply, args (f arg)
--  11 +, args (a b)               12 -, args (a b)         13 mul, args (a b)
--  14 div, args (a b)             15 mod, args (a b)
--  16 <, args (a b)               17 =, args (a b)         18 kind, args (a)
--
-- toValue(e) quotes an expression. fromValue(v) reads a quoted program back, and checks it: a tag that is not known, or a list of the wrong length, is an error, so a program from outside cannot make the machine see a form it does not have. toExpr(v) gives an expression that evaluates to the data value v, which is what the self-interpreter quotes with.
--
-- Both are recursive on the depth of the program, not on the length of a list, since a list is a chain of tails walked one step at a time.

const M = require "./vm"

-- The primitives, by their tag, with the arity of each.
const PRIMITIVE_TAGS: { [string]: number } = {
	add = 11,
	sub = 12,
	mul = 13,
	div = 14,
	mod = 15,
	lt = 16,
	eq = 17,
	kind = 18,
}

const PRIMITIVE_NAMES: { [number]: string } = {
	[11] = "add",
	[12] = "sub",
	[13] = "mul",
	[14] = "div",
	[15] = "mod",
	[16] = "lt",
	[17] = "eq",
	[18] = "kind",
}

const function cell(
	head: M.Value,
	tail: M.Value
): M.Value
	return ({
		kind = "cell",
		head = head,
		tail = tail,
	} :: M.Cell)
end

-- A proper list of values, ending in nil.
const function list(
	items: { M.Value }
): M.Value
	local v: M.Value = M.NIL

	for i = #items, 1, -1 do
		v = cell(items[i], v)
	end

	return v
end

const function node(
	tag: number,
	args: { M.Value }
): M.Value
	return cell(tag, list(args))
end

-- Quotes an expression as a data value.
local toValue: (e: M.Expr) -> M.Value

toValue = function(
	e: M.Expr
): M.Value
	if e.op == "quote" then
		return node(0, { e.value })
	elseif e.op == "nil" then
		return node(1, {})
	elseif e.op == "var" then
		return node(2, { e.index })
	elseif e.op == "lam" then
		return node(3, { toValue(e.body) })
	elseif e.op == "pin" then
		return node(4, { toValue(e.e) })
	elseif e.op == "cell" then
		return node(5, { toValue(e.head), toValue(e.tail) })
	elseif e.op == "head" then
		return node(6, { toValue(e.e) })
	elseif e.op == "tail" then
		return node(7, { toValue(e.e) })
	elseif e.op == "force" then
		return node(8, { toValue(e.e) })
	elseif e.op == "if" then
		return node(9, { toValue(e.c), toValue(e.t), toValue(e.e) })
	elseif e.op == "apply" then
		return node(10, { toValue(e.f), toValue(e.arg) })
	end

	const tag = PRIMITIVE_TAGS[e.name]

	if e.b == nil then
		return node(tag, { toValue(e.a) })
	end

	return node(tag, { toValue(e.a), toValue((e.b :: M.Expr)) })
end

-- The items of a proper list of exactly n values.
const function items(
	v: M.Value,
	n: number
): { M.Value }
	local out: { M.Value } = {}
	local cur = v

	for i = 1, n do
		if type(cur) ~= "table" or cur.kind ~= "cell" then
			error(string.format("a form has %d parts, but was given %d", n, i - 1), 0)
		end

		out[i] = cur.head
		cur = cur.tail
	end

	if cur ~= M.NIL then
		error(string.format("a form has %d parts, but was given more", n), 0)
	end

	return out
end

const function isInteger(
	v: M.Value
): boolean
	return type(v) == "number" and v == math.floor(v)
end

-- Reads a quoted program back as an expression. The builders check the primitive names and the integers they are given, and this checks the shape of everything else.
local fromValue: (v: M.Value) -> M.Expr

fromValue = function(
	v: M.Value
): M.Expr
	if type(v) ~= "table" or v.kind ~= "cell" then
		error("a program is a pair [tag args]", 0)
	end

	const tag = v.head

	if not isInteger(tag) or (tag :: number) < 0 or (tag :: number) > 18 then
		error(`a program has no form with tag {tostring(tag)}`, 0)
	end

	const n = tag :: number
	const parts = v.tail

	if n == 0 then
		const a = items(parts, 1)[1]

		if not isInteger(a) then
			error("a quoted value must be an integer", 0)
		end

		return M.int(a :: number)
	elseif n == 1 then
		items(parts, 0)
		return M.nilv()
	elseif n == 2 then
		const index = items(parts, 1)[1]

		if not isInteger(index) or (index :: number) < 0 then
			error("a variable index must be a whole number, not negative", 0)
		end

		return M.var(index :: number)
	elseif n == 3 then
		return M.lam(fromValue(items(parts, 1)[1]))
	elseif n == 4 then
		return M.pin(fromValue(items(parts, 1)[1]))
	elseif n == 5 then
		const pair = items(parts, 2)
		return M.cell(fromValue(pair[1]), fromValue(pair[2]))
	elseif n == 6 then
		return M.head(fromValue(items(parts, 1)[1]))
	elseif n == 7 then
		return M.tail(fromValue(items(parts, 1)[1]))
	elseif n == 8 then
		return M.force(fromValue(items(parts, 1)[1]))
	elseif n == 9 then
		const three = items(parts, 3)
		return M.ite(fromValue(three[1]), fromValue(three[2]), fromValue(three[3]))
	elseif n == 10 then
		const pair = items(parts, 2)
		return M.app(fromValue(pair[1]), fromValue(pair[2]))
	elseif n == 18 then
		return M.prim("kind", fromValue(items(parts, 1)[1]))
	end

	const name = PRIMITIVE_NAMES[n]
	const pair = items(parts, 2)
	return M.prim(name, fromValue(pair[1]), fromValue(pair[2]))
end

-- An expression that evaluates to the data value v. Integers and nil are literals, and a cell is a cell built at run time, so the expression is the same shape as v.
const function toExpr(
	v: M.Value
): M.Expr
	if type(v) == "number" then
		return M.int(v)
	end

	if v == M.NIL then
		return M.nilv()
	end

	if v.kind == "cell" then
		return M.cell(toExpr(v.head), toExpr(v.tail))
	end

	error("only data can be turned into an expression", 0)
end

return {
	toValue = toValue,
	fromValue = fromValue,
	toExpr = toExpr,
}
