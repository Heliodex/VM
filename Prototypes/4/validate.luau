--!strict
-- VALIDATION OF THE TESTS IN cases.luau AND THE NUMERALS
--
-- Runs every case and checks only what it should reduce to, then checks that numerals read back to the number they were built from. No diagrams are drawn, so a run is fast.
-- Prints one line per check and exits with an error if any check fails. main.luau is for looking at reductions; this is for knowing whether they are right.
--
--   luau validate.luau

const Bo = require "./booleans"
const B = require "./builder"
const Canon = require "./canon"
const Cases = require "./cases"
const Codes = require "./codes"
const Compile = require "./compile"
const F = require "./fix"
const G = require "./gadgets"
const H = require "./harness"
const L = require "./lambda"
const Li = require "./lists"
const Printer = require "./printer"
const Session = require "./session"
const Reader = require "./reader"
const V = require "./values"
const S = require "./scott"
const Rules = require "./rules"
const Types = require "./types"

type Builder = B.Builder
type Net = Types.Net
type Port = Types.Port
const ARITH_BUDGET = 20000

-- The number that a net stands for, if it is a Scott numeral; nil otherwise.
local function numeralOf(
	net: Net
): number?
	const _, got = S.readNet(net)

	return got
end

-- How long a program may take to reduce, with the value read back.
const PROGRAM_BUDGET = 400000

-- Whether a program's value is the number n.
local function numberIs(
	value: V.Value?,
	n: number
): boolean
	return value ~= nil and value.kind == "number" and value.value == n
end

-- Whether a program's value is the symbol called `name`.
local function symbolIs(
	value: V.Value?,
	name: string
): boolean
	return value ~= nil and value.kind == "symbol" and value.name == name
end

-- The numbers of a program's value, if it is a list of numbers, from its start.
local function listOfProgram(
	src: string
): { number }?
	local _, value = V.read(Compile.build(src), PROGRAM_BUDGET)
	const values: { number } = {}

	while value ~= nil and value.kind == "pair" do
		const head = value.car

		if head == nil or head.kind ~= "number" or head.value == nil then
			return nil
		end

		table.insert(values, head.value)
		value = value.cdr
	end

	if value == nil or value.kind ~= "nil" then
		return nil
	end

	return values
end

-- The normal form of the Scott numeral n, which is cut-free and so can be encoded.
local function numeralNet(
	n: number
): Net
	const b = B.new()
	S.numeral(b, n)
	const net = b:finish()
	H.reduce(net, ARITH_BUDGET)

	return net
end
local failures = 0
local total = 0

const function report(
	ok: boolean,
	label: string
)
	total += 1

	if not ok then
		failures += 1
	end

	print(
		`{
			if ok then
				"PASS"
			else
				"FAIL"
		}  {label}`
	)
end

for _, test in Cases.tests do
	const limit = test.budget or H.DEFAULT_BUDGET
	const net = Cases.build(test.start)
	const result = H.reduce(net, limit)
	report(Cases.verdict(test, net, result), `{test.name}  ({H.describe(result)})`)
end

-- Booleans read back as themselves, and nothing else reads back as a boolean.
for _, value in {
	true,
	false,
} do
	const net = Bo.booleanNet(value)
	report(Bo.readback(net) == value, `{value} reads back as {value}`)
end

-- A conditional selects the branch its condition names, whether the branches are numbers or booleans.
for _, c in {
	true,
	false,
} do
	do
		const b = B.new()
		local term = Bo.conditional(b)
		term = L.app(b, term, Bo.boolean(b, c))
		term = L.app(b, term, S.numeral(b, 2))
		term = L.app(b, term, S.numeral(b, 5))
		const net = b:finish()
		const result = H.reduce(net, H.DEFAULT_BUDGET)
		const want =
			if c then
				2
			else
				5
		report(result.outcome == "reduced" and numeralOf(net) == want, `if {c} then 2 else 5 is {want}  ({H.describe(result)})`)
	end

	do
		const b = B.new()
		local term = Bo.conditional(b)
		term = L.app(b, term, Bo.boolean(b, c))
		term = L.app(b, term, Bo.boolean(b, true))
		term = L.app(b, term, Bo.boolean(b, false))
		const net = b:finish()
		const result = H.reduce(net, H.DEFAULT_BUDGET)
		report(result.outcome == "reduced" and Bo.readback(net) == c, `if {c} then true else false is {c}  ({H.describe(result)})`)
end end

-- Lists: build a list of numerals, take it apart, and read the parts back.
local function listOf(
	b: Builder,
	elements: { number }
): Port
	local list = Li.nilValue(b)

	for i = #elements, 1, -1 do
		list = L.app(b, L.app(b, Li.cons(b), S.numeral(b, elements[i])), list)
	end

	return list
end

-- Build a term with `build`, reduce it, and return the report and the net.
local function evaluate(
	build: (Builder) -> Port
): (H.Report, Net)
	const b = B.new()
	build(b)
	const net = b:finish()

	return H.reduce(net, H.DEFAULT_BUDGET), net
end

const DEFAULT = 9

for _, elements in {
	{},
	{
		4,
	},
	{
		2,
		3,
	},
} do
	const want = #elements == 0
	const result, net = evaluate(function(
		b
	)
		return L.app(b, Li.isNil(b), listOf(b, elements))
	end)
	report(result.outcome == "reduced" and Bo.readback(net) == want, `isNil of {#elements} elements is {want}  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		return L.app(
			b, L.app(
				b, Li.head(b), listOf(
					b, {
						2,
						3,
					}
				)
			), S.numeral(b, DEFAULT)
		)
	end)
	report(result.outcome == "reduced" and numeralOf(net) == 2, `head of [2, 3] is 2  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		const rest = L.app(
			b, L.app(
				b, Li.tail(b), listOf(
					b, {
						2,
						3,
					}
				)
			), S.numeral(b, DEFAULT)
		)

		return L.app(b, L.app(b, Li.head(b), rest), S.numeral(b, DEFAULT))
	end)
	report(result.outcome == "reduced" and numeralOf(net) == 3, `head of tail of [2, 3] is 3  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		return L.app(b, L.app(b, Li.head(b), Li.nilValue(b)), S.numeral(b, DEFAULT))
	end)
	report(result.outcome == "reduced" and numeralOf(net) == DEFAULT, `head of [] is the default {DEFAULT}  ({H.describe(result)})`)
end

do
	const result, net = evaluate(function(
		b
	)
		return L.app(
			b, Li.isNil(b), L.app(
				b, L.app(
					b, Li.tail(b), listOf(
						b, {
							2,
						}
					)
				), Bo.boolean(b, false)
			)
		)
	end)
	report(result.outcome == "reduced" and Bo.readback(net) == true, `tail of [2] is empty  ({H.describe(result)})`)
end

-- Values that are not booleans read back as nothing.
do
	const b = B.new()
	L.lam(
		b, function(
			x: Port
		): Port
			return x
		end
	)
	report(Bo.readback(b:finish()) == nil, "the identity does not read back as a boolean")
end

-- A value that is not a numeral reads back as nothing. λf.λx.λy.x is not one: applied to two values it gives an abstraction, not a numeral.
do
	const b = B.new()
	L.lam(
		b, function(
			_f
		)
			return L.lam(
				b, function(
					x
				)
					return L.lam(
						b, function(
							_y
						)
							return x
						end
					)
				end
			)
		end
	)
	const constant = b:finish()
	report(numeralOf(constant) == nil, "λf.λx.λy.x does not read back as a numeral")
end

-- Codes: a code has no δ in it, decoding it gives back the net it was made from, and a δ fan copies it so that each copy decodes to the same net.
const function steps(
	net: Net
): number
	local count = 0

	while count < ARITH_BUDGET and Rules.step(net) do
		count += 1
	end

	return count
end

const encodable: { {
	name: string,
	make: () -> Net,
} } = {
	{
		name = "T(4)",
		make = function()
			const b = B.new()
			G.autodualMultiplexer(b, 4)

			return b:finish()
		end,
	},
	{
		name = "T(2, 1)",
		make = function()
			const b = B.new()
			G.transpositor(b, 2, 1)

			return b:finish()
		end,
	},
	{
		name = "numeral 3",
		make = function()
			return numeralNet(3)
		end,
	},
}

for _, case in encodable do
	const original = case.make()
	const b = B.new()
	const code = Codes.encode(b, original)
	const clean = not Codes.hasDelta(b.net)
	const d = Codes.decoder(b, #Codes.freePorts(original))
	b:wire(code, d.principal)
	const net = b:finish()
	const taken = steps(net)
	report(clean and taken < ARITH_BUDGET and Canon.isomorphic(net, case.make()), `the code of {case.name} has no δ and decodes to it  ({taken} steps)`)
end

for n = 0, 3 do
	const b = B.new()
	const code = Codes.encode(b, numeralNet(n))
	const fan = b:delta()
	b:wire(code, fan.principal)
	b:wire(fan.aux1, Codes.decoder(b, 1).principal)
	b:wire(fan.aux2, Codes.decoder(b, 1).principal)
	const net = b:finish()
	const taken = steps(net)
	const twice = B.new()
	S.numeral(twice, n)
	S.numeral(twice, n)
	const expected = twice:finish()
	H.reduce(expected, ARITH_BUDGET)
	report(taken < ARITH_BUDGET and Canon.isomorphic(net, expected), `a δ fan copies the code of numeral {n} into two that decode  ({taken} steps)`)
end

-- Recursion through codes: length and sum fold over a list, and the recursive function on its own reduces to a normal form instead of unfolding.
do
	const b = B.new()
	Li.length(b)
	const net = b:finish()
	const taken = steps(net)
	report(taken < ARITH_BUDGET, `length on its own reaches a normal form  ({taken} steps)`)
end

for _, elements in {
	{},
	{
		7,
	},
	{
		7,
		8,
	},
	{
		1,
		2,
		3,
	},
} do
	local expected = 0

	for _, k in elements do
		expected += k
	end

	for _, case in {
		{
			name = "length",
			build = Li.length,
			want = #elements,
		},
		{
			name = "sum",
			build = Li.sum,
			want = expected,
		},
	} do
		const b = B.new()
		L.app(b, case.build(b), listOf(b, elements))
		const net = b:finish()
		const taken = steps(net)
		report(taken < ARITH_BUDGET and numeralOf(net) == case.want, `{case.name} of {#elements} elements is {case.want}  ({taken} steps)`)
end end

-- Scott numerals ---------------------------------------------------------------
-- Each numeral reads back as the number it was built from, and the arithmetic gives the right answers.
for k = 0, 4 do
	const result, got = S.readback(function(
		b
	)
		return S.numeral(b, k)
	end)
	report(got == k, `Scott numeral {k} reads back as {k}  ({H.describe(result)})`)
end

do
	const result, got = S.readback(function(
		b
	)
		return L.app(b, S.successor(b), S.numeral(b, 3))
	end)
	report(got == 4, `successor of 3 is 4  ({H.describe(result)})`)
end

for _, case in {
	{
		m = 3,
		want = 2,
	},
	{
		m = 0,
		want = 0,
	},
} do
	const result, got = S.readback(function(
		b
	)
		return L.app(b, S.predecessor(b), S.numeral(b, case.m))
	end)
	report(got == case.want, `predecessor of {case.m} is {case.want}  ({H.describe(result)})`)
end

for _, case in {
	{
		n = 0,
		want = true,
	},
	{
		n = 3,
		want = false,
	},
} do
	const result, net = S.evaluate(function(
		b
	)
		return L.app(b, S.isZero(b), S.numeral(b, case.n))
	end)
	report(result.outcome == "reduced" and Bo.readback(net) == case.want, `{case.n} is zero is {case.want}  ({H.describe(result)})`)
end

for _, case in {
	{
		m = 2,
		n = 3,
		want = 5,
	},
	{
		m = 0,
		n = 4,
		want = 4,
	},
	{
		m = 3,
		n = 0,
		want = 3,
	},
} do
	const result, got = S.readback(function(
		b
	)
		return L.app(b, L.app(b, S.addition(b), S.numeral(b, case.m)), S.numeral(b, case.n))
	end, ARITH_BUDGET)
	report(got == case.want, `{case.m} + {case.n} = {case.want}  ({H.describe(result)})`)
end

for _, case in {
	{
		m = 2,
		n = 3,
		want = 6,
	},
	{
		m = 0,
		n = 5,
		want = 0,
	},
	{
		m = 3,
		n = 0,
		want = 0,
	},
} do
	const result, got = S.readback(function(
		b
	)
		return L.app(b, L.app(b, S.multiplication(b), S.numeral(b, case.m)), S.numeral(b, case.n))
	end, ARITH_BUDGET * 4)
	report(got == case.want, `{case.m} * {case.n} = {case.want}  ({H.describe(result)})`)
end

-- Copies of a numeral are sound now: a value with three uses, and a list used two different ways, are both right.
do
	const result, got = S.readback(function(
		b
	)
		const xs = L.share(b, S.numeral(b, 2), 2)
		return L.app(b, L.app(b, S.addition(b), xs[1]), xs[2])
	end, ARITH_BUDGET)
	report(got == 4, `a numeral copied in two and added to itself is 4  ({H.describe(result)})`)
end

-- Whole lists: a list reads back as the Lua table of its numbers, from the start.
local function listBuilder(
	values: { number }
): (Builder) -> Port
	return function(
		b: Builder
	): Port
		local list = Li.nilValue(b)

		for i = #values, 1, -1 do
			list = L.app(b, L.app(b, Li.cons(b), S.numeral(b, values[i])), list)
		end

		return list
	end
end

local function sameList(
	got: { number }?,
	want: { number }
): boolean
	if got == nil or #got ~= #want then
		return false
	end

	for i, value in want do
		if got[i] ~= value then
			return false
		end
	end

	return true
end

for _, values in {
	{},
	{
		4,
	},
	{
		2,
		3,
	},
	{
		1,
		2,
		3,
		4,
	},
} do
	const got = Li.readback(listBuilder(values))
	report(sameList(got, values), `the list of {#values} numbers reads back as itself`)
end

-- A list made by a program, and one whose elements are computed.
report(sameList(listOfProgram("(cons 1 (cons 2 nil))"), { 1, 2 }), "a list made by a program reads back whole")
report(sameList(listOfProgram("(define inc (lambda (n) (+ n 10))) (cons (inc 1) (cons (inc 2) nil))"), { 11, 12 }), "a list of computed numbers reads back whole")

-- A number is not a list, so it does not read back as one.
report(Li.readback(function(
	b: Builder
): Port
	return S.numeral(b, 3)
end) == nil, "a number does not read back as a list")

-- Subtraction and comparison, as programs: each result is a number or a branch taken.
for _, case in {
	{
		src = "(- 5 2)",
		want = 3,
	},
	{
		src = "(- 2 5)",
		want = 0,
	},
	{
		src = "(- 3 3)",
		want = 0,
	},
	{
		src = "(- 7 0)",
		want = 7,
	},
	{
		src = "(- (+ 2 3) (* 2 2))",
		want = 1,
	},
	{
		src = "(if (= 3 3) 1 2)",
		want = 1,
	},
	{
		src = "(if (= 3 4) 1 2)",
		want = 2,
	},
	{
		src = "(if (= 0 0) 1 2)",
		want = 1,
	},
	{
		src = "(if (= 2 0) 1 2)",
		want = 2,
	},
	{
		src = "(if (< 2 3) 1 2)",
		want = 1,
	},
	{
		src = "(if (< 3 3) 1 2)",
		want = 2,
	},
	{
		src = "(if (<= 3 3) 1 2)",
		want = 1,
	},
	{
		src = "(if (<= 4 3) 1 2)",
		want = 2,
	},
	{
		src = "(if (zero? 0) 1 2)",
		want = 1,
	},
	{
		src = "(if (zero? 3) 1 2)",
		want = 2,
	},
	{
		src = "(if (= (+ 1 2) (- 6 3)) 9 8)",
		want = 9,
	},
} do
	const result, value = V.read(Compile.build(case.src), PROGRAM_BUDGET)
	report(numberIs(value, case.want), `{case.src}  is {case.want}  ({H.describe(result)})`)
end

-- Symbols: a quoted name reads back as that symbol, eq? compares symbols by name, and a quoted list reads back as its cons cells.
for _, name in {
	"a",
	"b",
} do
	const result, value = V.read(Compile.build("'" .. name), PROGRAM_BUDGET)
	report(symbolIs(value, name), `'{name} reads back as that symbol  ({H.describe(result)})`)
end

for _, case in {
	{
		src = "(if (eq? 'a 'a) 1 2)",
		want = 1,
	},
	{
		src = "(if (eq? 'a 'b) 1 2)",
		want = 2,
	},
} do
	const result, value = V.read(Compile.build(case.src), PROGRAM_BUDGET)
	report(numberIs(value, case.want), `{case.src}  is {case.want}  ({H.describe(result)})`)
end

do
	const result, value = V.read(Compile.build("(car '(a b))"), PROGRAM_BUDGET)
	report(symbolIs(value, "a"), `(car '(a b)) is the symbol a  ({H.describe(result)})`)
end

report(sameList(listOfProgram("'(1 2)"), { 1, 2 }), "a quoted list of numbers reads back whole")
report(sameList(listOfProgram("'()"), {}), "the empty quoted list is the empty list")
report(not pcall(function()
	Compile.evaluate("(define quote 1) 0")
end), "quote cannot be defined")

-- Tagged values: each program's value, written out, and the errors for values of the wrong kind.
-- A value is written as Lisp would write it, so a test compares its shape as well as its numbers.
for _, case in {
	{
		src = "'(1 (2 3))",
		want = "(1 (2 3))",
	},
	{
		src = "(cons 1 2)",
		want = "(1 . 2)",
	},
	{
		src = "(cdr '(1))",
		want = "()",
	},
	{
		src = "'()",
		want = "()",
	},
	{
		src = "(< 1 2)",
		want = "#t",
	},
	{
		src = "(eq? 'a 'b)",
		want = "#f",
	},
	{
		src = "(number? 'a)",
		want = "#f",
	},
	{
		src = "(null? '())",
		want = "#t",
	},
	{
		src = "(+ 'a 1)",
		want = "#error",
	},
	{
		src = "(succ 'a)",
		want = "#error",
	},
	{
		src = "(car '())",
		want = "#error",
	},
	{
		src = "(if 5 1 2)",
		want = "#error",
	},
} do
	const result, value = V.read(Compile.build(case.src), PROGRAM_BUDGET)
	report(result.outcome == "reduced" and Printer.show(value) == case.want, `{case.src}  is {case.want}  (is {Printer.show(value)})`)
end

-- Sessions: definitions persist, a bad form does not spoil the rest, and errors point at their form.
do
	const session = Session.new()
	const first = Session.evaluate(session, "(define double (lambda (n) (+ n n)))", PROGRAM_BUDGET)
	report(#first == 1 and first[1].kind == "defined" and first[1].name == "double", "a definition is reported as defined")

	const second = Session.evaluate(session, "(double 4)", PROGRAM_BUDGET)
	report(#second == 1 and second[1].kind == "value" and numberIs(second[1].value, 8), "a later input uses the definition")

	const third = Session.evaluate(session, "(double x)", PROGRAM_BUDGET)
	report(#third == 1 and third[1].kind == "error" and third[1].at == 9 and third[1].message == "unbound name x", "an unbound name is an error at its byte offset")

	const fourth = Session.evaluate(session, "(double 1) (car 5) (double 2)", PROGRAM_BUDGET)
	report(#fourth == 3 and numberIs(fourth[1].value, 2) and Printer.show(fourth[2].value) == "#error" and numberIs(fourth[3].value, 4), "forms after a wrong-kind value are still evaluated")

	const fifth = Session.evaluate(session, "(double 2", PROGRAM_BUDGET)
	report(#fifth == 1 and fifth[1].kind == "error" and string.find(fifth[1].message or "", "never closed", 1, true) ~= nil, "an unclosed form is a reader error")

	const sixth = Session.evaluate(Session.new(), "(double 2)", PROGRAM_BUDGET)
	report(#sixth == 1 and sixth[1].kind == "error", "a new session does not have the old definitions")

	const seventh = Session.evaluate(Session.new(), "(define loop (lambda (n) (loop n)))", PROGRAM_BUDGET)
	report(#seventh == 1 and seventh[1].kind == "defined", "a definition that never runs is still accepted")
end

-- Reader ----------------------------------------------------------------------
-- Each source reads back as the expressions it should, comments and spacing aside.
for index, case in {
	{
		src = "(+ 1 2)",
		want = "(+ 1 2)",
	},
	{
		src = "  ( lambda (x) x )\n; a comment (with brackets)\n 7",
		want = "(lambda (x) x) 7",
	},
	{
		src = "",
		want = "",
	},
	{
		src = "'(a 'b)",
		want = "(quote (a (quote b)))",
	},
} do
	const forms = Reader.read(case.src)
	const shown = {}

	for _, form in forms do
		table.insert(shown, Reader.show(form))
	end

	report(table.concat(shown, " ") == case.want, `source {index} reads as {case.want == "" and "nothing" or case.want}`)
end

-- Unbalanced brackets are errors, not silently accepted.
for _, src in {
	"(+ 1",
	")",
} do
	report(not pcall(Reader.read, src), `source {src} is rejected`)
end

-- Programs --------------------------------------------------------------------
-- Source text compiles and reduces to the value it should. A program is checked by reading its value back, so a stuck net does not pass.
for _, case in {
	{
		src = "3",
		want = 3,
	},
	{
		src = "(+ 2 3)",
		want = 5,
	},
	{
		src = "(* 2 3)",
		want = 6,
	},
	{
		src = "((lambda (x) 5) 9)",
		want = 5,
	},
	{
		src = "((lambda (x) (+ x x)) 4)",
		want = 8,
	},
	{
		src = "((lambda (f) (+ (f 1) (f 2))) (lambda (n) (+ n 10)))",
		want = 23,
	},
	{
		src = "(if true 1 2)",
		want = 1,
	},
	{
		src = "(if false 1 2)",
		want = 2,
	},
	{
		src = "(define double (lambda (n) (+ n n))) (double 3)",
		want = 6,
	},
	{
		src = "(define inc (lambda (x) (succ x))) (define twice (lambda (f) (lambda (x) (f (f x))))) ((twice inc) 0)",
		want = 2,
	},
	{
		src = "(if (null? (cdr (cons 1 nil))) 5 6)",
		want = 5,
	},
	-- The recursive call sits in the else branch, so these terminate only if the branch that is not chosen is never unfolded.
	{
		src = "(define length (lambda (l) (if (null? l) 0 (succ (length (cdr l)))))) (length nil)",
		want = 0,
	},
	{
		src = "(define length (lambda (l) (if (null? l) 0 (succ (length (cdr l)))))) (length (cons 1 (cons 2 nil)))",
		want = 2,
	},
	{
		src = "(define length (lambda (l) (if (null? l) 0 (succ (length (cdr l)))))) (length (cons 1 (cons 2 (cons 3 nil))))",
		want = 3,
	},
	-- A copied list, used two different ways: this was wrong with Church numerals.
	{
		src = "((lambda (x) (+ (car x) (car (cdr x)))) (cons 2 (cons 3 nil)))",
		want = 5,
	},
	{
		src = "(define sum (lambda (l) (if (null? l) 0 (+ (car l) (sum (cdr l)))))) (sum (cons 1 (cons 2 (cons 3 nil))))",
		want = 6,
	},
	{
		src = "((lambda (x) (+ x (+ x x))) 3)",
		want = 9,
	},
	-- A recursive function given a function argument is specialised on it, so the function is never copied at run time.
	{
		src = "(define rep (lambda (k l) (if (null? l) 0 (+ (k (car l)) (rep k (cdr l)))))) (rep (lambda (n) (+ n 10)) (cons 1 (cons 2 nil)))",
		want = 23,
	},
	{
		src = "(define rep (lambda (k l) (if (null? l) 0 (+ (k (car l)) (rep k (cdr l)))))) (rep (lambda (n) (+ n n)) (cons 1 (cons 2 nil)))",
		want = 6,
	},
	{
		src = "(define inc (lambda (n) (+ n 10))) (define rep (lambda (k l) (if (null? l) 0 (+ (k (car l)) (rep k (cdr l)))))) (rep inc (cons 1 (cons 2 nil)))",
		want = 23,
	},
	{
		src = "(define count (lambda (f l) (if (null? l) 0 (+ (f (car l)) (count f (cdr l)))))) (count (lambda (n) (* n 2)) (cons 1 (cons 2 (cons 3 nil))))",
		want = 12,
	},
	{
		src = "(define rep (lambda (k l) (if (null? l) 0 (+ (k (car l)) (rep k (cdr l)))))) ((lambda (x) (rep (lambda (n) (+ n x)) (cons 1 (cons 2 nil)))) 5)",
		want = 13,
	},
	-- A local recursive function may use the variables of the function it is in, which are passed to it.
	{
		src = "(define scale (lambda (n l) (if (null? l) 0 (+ (letrec tot (lambda (m) (if (null? m) 0 (+ (* n (car m)) (tot (cdr m))))) (tot l)) (scale n (cdr l)))))) (scale 2 (cons 1 (cons 2 nil)))",
		want = 10,
	},
	{
		src = "((lambda (k) (letrec sumk (lambda (l) (if (null? l) 0 (+ (k (car l)) (sumk (cdr l))))) (sumk (cons 1 (cons 2 nil))))) (lambda (x) (+ x 10)))",
		want = 23,
	},
	{
		src = "(define g (lambda (a b l) (if (null? l) 0 (+ (letrec h (lambda (m) (if (null? m) 0 (+ (+ a b) (h (cdr m))))) (h l)) (g a b (cdr l)))))) (g 1 2 (cons 0 nil))",
		want = 3,
	},
	-- A closed closure containing addition, used twice: this was wrong before closed arguments were substituted.
	{
		src = "((lambda (f) (+ (f 1) (f 2))) (lambda (n) (+ n 10)))",
		want = 23,
	},
	{
		src = "((lambda (x) ((lambda (g) (+ (g 1) (g 2))) (lambda (n) (+ n x)))) 10)",
		want = 23,
	},
	{
		src = "(define twice (lambda (g) (lambda (x) (g (g x))))) ((twice (lambda (n) (+ n 10))) 1)",
		want = 21,
	},
} do
	const result, value = V.read(Compile.build(case.src), PROGRAM_BUDGET)
	report(numberIs(value, case.want), `{case.src}  is {case.want}  ({H.describe(result)})`)
end

-- Programs that should not compile are rejected with an error.
for _, src in {
	"(f 1)",
	"(define x 1)",
	"(define x (+ x 1)) 0",
	"(lambda (x) x) (define y 2)",
	"(if true 1)",
	"(define + 1) 0",
	-- a function that depends on a variable of an enclosing lambda cannot be passed to a call
	"(define g (lambda (l) (if (null? l) 0 (+ ((lambda (f) (+ (f 1) (f 2))) (lambda (n) (+ n (car l)))) (g (cdr l)))))) (g (cons 5 nil))",
	-- a recursive call must pass its function arguments on unchanged
	"(define rep (lambda (k l) (if (null? l) 0 (+ (k (car l)) (rep (lambda (n) (succ n)) (cdr l)))))) (rep (lambda (n) (+ n 10)) (cons 1 (cons 2 nil)))",
	-- a local function can only be called
	"(define g (lambda (n l) (if (null? l) 0 (letrec h (lambda (m) (if (null? m) 0 h)) (h l))))) (g 1 nil)",
	-- a local function cannot call the function it is defined in
	"(define g (lambda (n l) (if (null? l) 0 (+ (letrec h (lambda (m) (if (null? m) 0 (g n m))) (h l)) (g n (cdr l)))))) (g 1 (cons 1 nil))",
	-- a recursive function given a function argument is not a value on its own
	"(define rep (lambda (k l) (if (null? l) 0 (+ (k (car l)) (rep k (cdr l)))))) (rep (lambda (n) (+ n 10)) rep)",
} do
	report(not pcall(function()
		Compile.evaluate(src)
	end), `rejects {src}`)
end

-- Known limitations ----------------------------------------------------------
-- These nets should loop, but they stop with no active pair left and no cycle seen while stepping. The harness reports them as `reduced`, the same as a real normal form, and nothing in the final net separates them from a value (the identity is also a net with a loop in it).
-- They are printed as KNOWN, not counted as checks. Each still has to be reported as `reduced`: if the harness changes that, it is a failure, so this list gets revisited.
const function limitation(
	label: string,
	net: Net
)
	const result = H.reduce(net, H.DEFAULT_BUDGET)

	if result.outcome == "reduced" then
		print(`KNOWN  {label}  ({H.describe(result)}; should not finish)`)
	else
		report(false, `{label} no longer stops as a stuck net, so move it back to the checks  ({H.describe(result)})`)
	end
end

-- λx. x x
const function selfApply(
	b: Builder
): Port
	return L.lam(
		b, function(
			x: Port
		): Port
			const xs = L.share(b, x, 2)

			return L.app(b, xs[1], xs[2])
		end
	)
end

-- Ω = (λx. x x)(λx. x x)
const function omega(
	b: Builder
): Port
	return L.app(b, selfApply(b), selfApply(b))
end

limitation("Z applied to the identity", Cases.build(function(
	b: Builder
)
	L.app(
		b, F.fixpoint(b), L.lam(
			b, function(
				x: Port
			): Port
				return x
			end
		)
	)
end))
limitation("omega, (λx.x x)(λx.x x)", Cases.build(function(
	b: Builder
)
	omega(b)
end))


if failures > 0 then
	error(`{failures} of {total} checks failed`)
end

print(`all {total} checks passed`)
