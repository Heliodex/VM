--!strict
-- PRINTING VALUES
--
-- A value is written as Lisp would write it: numbers as digits, symbols by their names, booleans as #t and #f, the empty list as (), a list as its items in brackets, a pair that does not end in a list with a dot, and an error as #error.
-- The printer is the only place that decides how a value looks, so the REPL and the tests agree.
--
--   const Printer = require "./printer"
--
--   print(Printer.show(value))   -- (1 (2 3))

const V = require "./values"

-- Writes a value, which may be nil if a readback did not give one.
const function show(
	value: V.Value?
): string
	if value == nil then
		return "?"
	elseif value.kind == "number" then
		return tostring(value.value)
	elseif value.kind == "symbol" then
		return value.name :: string
	elseif value.kind == "boolean" then
		return if value.truth then "#t" else "#f"
	elseif value.kind == "nil" then
		return "()"
	elseif value.kind == "error" then
		return "#error"
	end

	-- a pair: a list if its tail is a list, otherwise a dotted pair
	const parts: { string } = {
		show(value.car),
	}
	local rest = value.cdr

	while rest ~= nil and rest.kind == "pair" do
		table.insert(parts, show(rest.car))
		rest = rest.cdr
	end

	if rest ~= nil and rest.kind == "nil" then
		return `({table.concat(parts, " ")})`
	end

	return `({table.concat(parts, " ")} . {show(rest)})`
end

return {
	show = show,
}
