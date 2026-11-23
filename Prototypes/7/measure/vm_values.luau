--!strict
-- THE VALUES OF PROTOTYPE 6, AS THE MEASUREMENT READS THEM
--
-- Converts between a list of bytes and a machine list, and reads a machine list back as a string or as Lua values, with the machine's own types (Prototype 6's VM.Value). The owner of an expression is set by compile.luau on the table itself, so it is read with rawget: that is the only untyped access the measurement makes.

const VM = require "../../6/interpreter/vm"

export type Value = VM.Value

-- The machine list of the bytes of a string.
const function bytesValue(s: string): Value
	local v: Value = VM.NIL

	for i = #s, 1, -1 do
		const cell: VM.Cell = { kind = "cell"; head = string.byte(s, i) :: number; tail = v }
		v = cell
	end

	return v
end

-- The text of a machine list of bytes.
const function textOf(v: Value): string
	local out: { string } = {}
	local cur: Value = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, string.char(cur.head :: number))
		cur = cur.tail
	end

	return table.concat(out)
end

-- The items of a machine list, in order.
const function itemsOf(v: Value): { Value }
	local out: { Value } = {}
	local cur: Value = v

	while type(cur) == "table" and cur.kind == "cell" do
		table.insert(out, cur.head)
		cur = cur.tail
	end

	return out
end

-- The owner of an expression, as the measurement's compile step set it, or "?" if it has none.
const function ownerOf(e: VM.Expr): string
	const owner = (e :: VM.Expr & { owner: string? }).owner

	return owner or "?"
end

return {
	bytesValue = bytesValue,
	textOf = textOf,
	itemsOf = itemsOf,
	ownerOf = ownerOf,
}
