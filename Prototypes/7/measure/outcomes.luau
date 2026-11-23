--!strict
-- READING THE RESULTS OF PROTOTYPE 6'S MACHINE, FOR THE MEASUREMENT
--
-- Lifecycle.run gives a result that is a value only when its status says so, and a constructor's payload is only a constructor's. These helpers check the status or the kind, and give the narrowed value, so a harness that reads a result says what it expects, and fails with a message when the result is different.

const Lifecycle = require "../../6/interpreter/lifecycle"
const VM = require "../../6/interpreter/vm"

export type Value = VM.Value

-- The value of a run that finished with one.
const function valueOf(r: Lifecycle.Result): Value
	if r.status ~= "value" then
		error(`expected a value from the run, but it was {r.status}`, 0)
	end

	return r.value
end

-- The payload of a constructor.
const function payloadOf(v: Value): Value
	if type(v) ~= "table" or v.kind ~= "con" then
		error("expected a constructor", 0)
	end

	return v.payload
end

-- The tag of a constructor.
const function tagOf(v: Value): number
	if type(v) ~= "table" or v.kind ~= "con" then
		error("expected a constructor", 0)
	end

	return v.tag
end

-- The head and tail of a cell.
const function headOf(v: Value): Value
	if type(v) ~= "table" or v.kind ~= "cell" then
		error("expected a cell", 0)
	end

	return v.head
end

const function tailOf(v: Value): Value
	if type(v) ~= "table" or v.kind ~= "cell" then
		error("expected a cell", 0)
	end

	return v.tail
end

return {
	valueOf = valueOf,
	payloadOf = payloadOf,
	tagOf = tagOf,
	headOf = headOf,
	tailOf = tailOf,
}
