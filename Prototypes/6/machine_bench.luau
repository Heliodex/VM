--!strict
-- MACHINE BENCHMARK
--
-- Times the fast machine (VM.run) and the reference machine (VM.runReference) on two workloads, and checks that both give the same steps. Workloads: fib 22 on the VM's builders, and the L2 checker checking types.l2 itself (the request infer_run builds).
--
--   lute run machine_bench.luau      (from Prototypes/6)

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

local function bytesValue(s: string): VM.Value
	local v: VM.Value = VM.NIL

	for i = #s, 1, -1 do
		v = { kind = "cell"; head = string.byte(s, i) :: number; tail = v } :: VM.Cell
	end

	return v
end

-- fib n = if n < 2 then n else fib (n - 1) + fib (n - 2)
local function fibProgram(n: number): VM.Expr
	const body = VM.ite(VM.prim(TAG.lt, VM.var(0), VM.int(2)), VM.var(0), VM.prim(TAG.add, VM.app(VM.var(1), VM.prim(TAG.sub, VM.var(0), VM.int(1))), VM.app(VM.var(1), VM.prim(TAG.sub, VM.var(0), VM.int(2)))))

	return VM.app(VM.fix, VM.lam(VM.lam(body)), VM.int(n))
end

local function bench(label: string, machine: any, program: VM.Expr, fuel: number): number
	const t0 = os.clock()
	const result = machine(program, fuel)
	const elapsed = os.clock() - t0
	print(string.format("%s: %s, %d steps, %.3fs, %.2fM steps/s", label, result.status, result.steps, elapsed, result.steps / elapsed / 1e6))

	return elapsed
end

const fibExpr = fibProgram(22)
bench("fib 22, reference", VM.runReference, fibExpr, 1e9)
bench("fib 22, fast", VM.run, fibExpr, 1e9)
bench("fib 22, direct", VM.runDirect, fibExpr, 1e9)
bench("fib 22, hybrid", VM.runHybrid, fibExpr, 1e9)
-- The checker on types.l2: the program is parsed once, then the checker's request is run on each machine.
const tokenizer = L2.compile(readFile "L2/programs/boot/lex.l2", resolve, "boot/lex.l2")
const parser = L2.compile(readFile "L2/programs/boot/parse.l2", resolve, "boot/parse.l2")
const checkerProgram = L2.compile(readFile "L2/programs/boot/types.l2", resolve, "boot/types.l2")
const src = ProgramFile.parse(readFile "L2/programs/boot/types.l2", "boot/types.l2").program :: string
const tokenized: any = L2.run(tokenizer, bytesValue(src), 1e8)
const parsed: any = L2.run(parser, tokenized.value.payload, 5e8)
const request: VM.Value = { kind = "con"; tag = 3; payload = parsed.value.payload }
-- L2.run calls VM.run on the module when it runs, so the reference machine is put in its place for the reference timing, then the fast one is restored.
const fastRun = VM.run

const function timedChecker(label: string, machine: any): number
	const vmModule: any = VM
	vmModule.run = machine
	const t0 = os.clock()
	const result = L2.run(checkerProgram, request, 1e10)
	const elapsed = os.clock() - t0
	vmModule.run = fastRun
	print(string.format("%s: %s, %d steps, %.3fs, %.2fM steps/s", label, result.status, result.steps, elapsed, result.steps / elapsed / 1e6))

	return result.steps
end

timedChecker("checker on types.l2, reference", VM.runReference)
timedChecker("checker on types.l2, fast", fastRun)
timedChecker("checker on types.l2, direct", VM.runDirect)
timedChecker("checker on types.l2, hybrid", VM.runHybrid)
