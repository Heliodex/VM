# Prototype 7, Phase 4: the fast machine (Go)

The core of `SPEC.md`, run on Go. It reads the binary format of section 12, and runs programs with the fuel rule of section 6. The Luau reference (`reference/`) is the oracle: every case here gives the reference's status, steps, value bytes and error message.

## Files

- `value.go`: the values, and the integer operations (`Small` for any integer that fits in int64, `*big.Int` for the rest; a result that fits is always a `Small`).
- `node.go`: forms, with their parts resolved (children, alternatives, else branch). The reader builds them directly, so a law's body is in this form when it is read.
- `format.go`: the writer and the reader of section 12, byte for byte the same as `reference/format.luau`, with the same messages.
- `machine.go`: the machine. One loop, with an explicit stack of continuations, as in the reference. Operands are kept on one stack, and each continuation remembers where its own operands start.
- `prim.go`: the fourteen primitives, and the pin table (interned by the value's binary form).
- `fast_test.go`: runs every case in `testdata/cases.txt`, and times the checker.
- `gen/gen.luau`: writes `testdata/cases.txt` from the reference.

## Running

    go test ./...                       # every case, and the checker's steps and speed
    go test -run TestChecker -v ./...   # the checker alone, with the speed against the reference
    forkmat -all -w .                   # the formatter for this folder

To regenerate the cases (from the measurement folder, because the L2 compiler reads paths from there):

    cd Prototypes/7/measure && lute run ../fast/gen/gen.luau > ../fast/testdata/cases.txt

## The cases

Each line of `testdata/cases.txt` is one case: a name, a mode (`body`: the body with the frame `[NIL, input]`, as the reference's `runForm`; or `run`: the law applied to the input, one entry), the program bytes, the input bytes, the fuel, and the reference's outcome.

- 50 hand-written cases: one for each rule of section 3, each primitive and its errors, partial and over-application, self-reference, out of fuel, big integers, pins, and a program 20,000 forms deep.
- 50 Prototype 5 examples, with the budget `cross_run` gives them.
- 147 tests of the Prototype 6 L2 programs, with the same budgets.
- The checker: the variant `types.l2` (`measure/boot/`) on Prototype 6's `types.l2`, the Phase 0 benchmark.

## Limits of this version

- The machine reads the bytes of a program into a tree of resolved nodes, not into one flat array. The flat layout is the next step if the speed target needs it.
- Readers and writers recurse, as the Go call stack allows (up to 1 GB by default, so far deeper than the 20,000 tested). The spec asks for no depth limit; the Go stack is the limit here.
- The reference's inline checks in `interp_run.luau` are not ported one by one. Each rule they test is covered by a hand-written case, and the spec's examples keep their step counts (`call (lit inc) (lit 41)` is 7 steps).
