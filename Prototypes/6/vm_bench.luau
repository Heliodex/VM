--!strict
-- Temporary benchmark for the VM: steps and steps per second on two workloads.
--   fib: a recursive function built from the VM's builders (calls, primitives, if, fix).
--   checker: the L2 checker on option.l2, repeated (a realistic L2 workload).

const L2 = require "./L2/l2"
const ProgramFile = require "./L2/programfile"
const Primitives = require "./interpreter/primitives"
const VM = require "./interpreter/vm"
const fs = require "@lute/fs"

const TAG = Primitives.TAG

local function readFile(path: string): string
	const handle = fs.open(path)
	const text = fs.read(handle)
	fs.close(handle)

	return text
end

local function resolve(name: string): string?
	const ok, text = pcall(readFile, `L2/programs/{name}`)

	if ok then
		return text :: string
	end

	return nil
end

-- fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)
local function fibProgram(n: number): VM.Expr
	const body = VM.ite(VM.prim(TAG.lt, VM.var(0), VM.int(2)), VM.var(0), VM.prim(TAG.add, VM.app(VM.var(1), VM.prim(TAG.sub, VM.var(0), VM.int(1))), VM.app(VM.var(1), VM.prim(TAG.sub, VM.var(0), VM.int(2)))))

	return VM.app(VM.fix, VM.lam(VM.lam(body)), VM.int(n))
end

local function timed(label: string, run: () -> VM.Outcome)
	const t0 = os.clock()
	const result = run()
	const elapsed = os.clock() - t0
	const steps = result.steps
	print(string.format("%s: %s, %d steps, %.3fs, %.2fM steps/s", label, result.status, steps, elapsed, steps / elapsed / 1e6))

	return result
end

-- The fib result must be the same before and after any change to the machine.
const fib = timed(
	"fib 22",
	function()
		return VM.run(fibProgram(22), 1e9)
	end
)
print(
	"  value " .. (
		if fib.status == "value" then
			VM.show(fib.value)
		else
			"-"
	)
)
-- The checker, run on option.l2 several times, with the program parsed once.
const tokenizer = L2.compile(readFile "L2/programs/boot/lex.l2", resolve, "boot/lex.l2")
const parser = L2.compile(readFile "L2/programs/boot/parse.l2", resolve, "boot/parse.l2")
const checkerProgram = L2.compile(readFile "L2/programs/boot/types.l2", resolve, "boot/types.l2")
const src = ProgramFile.parse(readFile "L2/programs/option.l2").program
local v: VM.Value = VM.NIL

for i = #src, 1, -1 do
	v = { kind = "cell"; head = string.byte(src, i) :: number; tail = v } :: VM.Cell
end

const tokenized = L2.run(tokenizer, v, 1e8)
const parsed = L2.run(parser, ((tokenized :: any).value :: VM.Con).payload, 5e8)
const request: VM.Value = { kind = "con"; tag = 3; payload = ((parsed :: any).value :: VM.Con).payload }
timed(
	"checker on option.l2 x 10",
	function()
		local total = 0
		local last: any = { status = "value"; value = VM.NIL; steps = 0 }

		for _ = 1, 10 do
			last = L2.run(checkerProgram, request, 1e10)
			total += last.steps
		end

		return { status = last.status; value = VM.NIL; steps = total } :: any
	end
)
