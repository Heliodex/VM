--!strict
-- CHECKS RECORDS, DESUGARED TO PAIRS AND RUN ON THE VM, AGAINST THE VALUES WORKED OUT BY HAND
--
--   lute run desugar_records_run.luau      (from Prototypes/5)

const Desugar = require "./L2/desugar"
const Parser = require "./L2/parser"
const VM = require "./interpreter/vm"

local failures = 0
local total = 0

local function run(label: string, src: string, expected: string)
	total += 1
	const parsed = Parser.parse(src)
	const ctors = Desugar.buildCtors(parsed.decls)
	const ok, res = pcall(function()
		const e = Desugar.desugarExpr(parsed.expr, {}, ctors)

		return VM.run(e, 1e6)
	end)
	local got: string

	if not ok then
		got = "error " .. tostring(res)
	else
		const out = res :: VM.Outcome

		if out.status == "value" then
			got = VM.show(out.value)
		else
			got = out.status
		end
	end

	if got ~= expected then
		failures += 1
		print(string.format("FAIL %s\n      expected %s\n      got      %s", label, expected, got))
	else
		print(string.format("ok   %s -> %s", label, got))
	end
end

const MS = "type MS = MS {\n\tst: Int\n\tfixed: Int\n\tcatch: Int\n}\n\n"
const MSV = "MS {\n\tst = 1\n\tfixed = 2\n\tcatch = 3\n}"
run("accessor", MS .. "fixed (" .. MSV .. ")", "2")
run("accessor, last field", MS .. "catch (" .. MSV .. ")", "3")
run("with keeps the other fields", MS .. "catch (with (" .. MSV .. ") {\n\tfixed = 9\n})", "3")
run("with changes the field", MS .. "fixed (with (" .. MSV .. ") {\n\tfixed = 9\n})", "9")
run("with changes the first field", MS .. "st (with (" .. MSV .. ") {\n\tst = 7\n})", "7")
run("pattern binds every field", MS .. "match (" .. MSV .. ") {\n\tMS {\n\t\tst = s\n\t\tfixed = f\n\t\tcatch = c\n\t} -> (+ s (+ f c))\n}", "6")
run("pattern with _", MS .. "match (" .. MSV .. ") {\n\tMS {\n\t\tst = _\n\t\tfixed = f\n\t\tcatch = _\n\t} -> f\n}", "2")
run("let of a record", MS .. "let m = " .. MSV .. "\n(+ (fixed m) (catch m))", "5")
run("record in a scrutinee needs parentheses", MS .. "match (" .. MSV .. ") {\n\t_ -> 1\n}", "1")
const ONE = "type One = One {\n\tv: Int\n}\n\n"
run("one-field record", ONE .. "v (One {\n\tv = 5\n})", "5")
run("one-field with", ONE .. "v (with (One {\n\tv = 5\n}) {\n\tv = 7\n})", "7")
run("one-field pattern", ONE .. "match (One {\n\tv = 4\n}) {\n\tOne {\n\t\tv = x\n\t} -> (+ x 1)\n}", "5")
const TR = "type Tr = TEmpty | TNode {\n\tvalue: Int\n\tleft: Int\n}\n\n"
run("record in a sum", TR .. "match (TNode {\n\tvalue = 3\n\tleft = 4\n}) {\n\tTEmpty -> 0\n\tTNode {\n\t\tvalue = v\n\t\tleft = l\n\t} -> (+ v l)\n}", "7")
run("nullary arm of a sum with records", TR .. "match TEmpty {\n\tTEmpty -> 0\n\tTNode {\n\t\tvalue = v\n\t\tleft = l\n\t} -> v\n}", "0")
run("missing field", MS .. "fixed (MS {\n\tst = 1\n\tfixed = 2\n})", "error line 7, column 8: MS needs the field catch")
run("unknown field", MS .. "MS {\n\tst = 1\n\tfixed = 2\n\tcatch = 3\n\tcolor = 4\n}", "error line 11, column 2: MS has no field color")
run("record constructor as a function", MS .. "MS 1", "error line 7, column 1: MS is a record: write its fields in braces")
print(string.format("%d of %d record checks passed", total - failures, total))
