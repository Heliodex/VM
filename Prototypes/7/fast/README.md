# Prototype 7, Phase 4: the fast machine (Go)

The core of `SPEC.md`, run on Go. It reads the binary format of section 12, and runs programs with the fuel rule of section 6. The Luau reference (`reference/`) is the oracle: every case here gives the reference's status, steps, value bytes and error message.

## Files

- `value.go`: the values, and the integer operations (`Small` for any integer that fits in int64, `*big.Int` for the rest; a result that fits is always a `Small`).
- `node.go`: forms, with their parts resolved (children, alternatives, else branch). The reader builds them directly, so a law's body is in this form when it is read.
- `format.go`: the writer and the reader of section 12, byte for byte the same as `reference/format.luau`, with the same messages.
- `machine.go`: the machine. One loop, with an explicit stack of continuations, as in the reference. Operands are kept on one stack, and each continuation remembers where its own operands start.
- `prim.go`: the fourteen primitives, and the pin table (interned by the value's binary form).
- `jets.go`: the jet table, and the three jets (see "Jets" below).
- `hash.go`: the content hash (SPEC.md section 12.7).
- `fast_test.go`: runs every case in `testdata/cases.txt` with the jets on and off, and times the checker.
- `jets_test.go`: checks that every jet still names a law of the checker's program.
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

## Jets

A jet is native code that replaces one law's body (SPEC.md section 3, decision 11). The machine picks it by the law's content hash, so a program never names a jet. A jet:

- declares the fuel of the body it replaces, counting the entry, and the machine charges that fuel in one go;
- handles only the inputs it has checked, and gives up on anything else, so errors and out-of-fuel points stay the spec's;
- is used only when the whole call fits in the fuel left;
- is fixed in the build. There are no work-only jets.

The three jets are for the helpers of `measure/boot/types.l2` (the checker's `tl`, `hdOr` and `stP`), with the fuel measured on the reference. On the checker they are taken about 490,000 times, replacing about 11.9 million of its 141.8 million steps. The checker's steps are unchanged, and its wall time changes by about 5%, within the noise of one host.

The bulk of the checker's steps are in `findB` and `setB`, which are recursive. Recursion is lowered through the `fix` combinator, so a jet on either would replace one level, not the recursion. That needs the lowering to turn `fix` into self-reference first, which changes the core programs and so the reference. It is the next step.

## Limits of this version

- The machine reads the bytes of a program into a tree of resolved nodes, not into one flat array. The flat layout is the next step if the speed target needs it.
- Readers and writers recurse, as the Go call stack allows (up to 1 GB by default, so far deeper than the 20,000 tested). The spec asks for no depth limit; the Go stack is the limit here.
- The reference's inline checks in `interp_run.luau` are not ported one by one. Each rule they test is covered by a hand-written case, and the spec's examples keep their step counts (`call (lit inc) (lit 41)` is 7 steps).
