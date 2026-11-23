# Prototype 7, Phase 4: the fast machine (Go)

The core of `SPEC.md`, run on Go. It reads the binary format of section 12, and runs programs with the fuel rule of section 6. The Luau reference (`reference/`) is the oracle: every case here gives the reference's status, steps, value bytes and error message.

## Files

- `value.go`: the values, and the integer operations (`Small` for any integer that fits in int64, `*big.Int` for the rest; a result that fits is always a `Small`).
- `node.go`: forms, with their parts resolved (children, alternatives, else branch). The reader builds them directly, so a law's body is in this form when it is read.
- `format.go`: the writer and the reader of section 12, byte for byte the same as `reference/format.luau`, with the same messages.
- `machine.go`: the machine. One loop, with an explicit stack of continuations, as in the reference. Operands are kept on one stack, and each continuation remembers where its own operands start.
- `prim.go`: the fourteen primitives, and the pin table (interned by the value's binary form).
- `jets.go`: the jet table, and the helper jets (see "Jets" below).
- `trie.go`, `trie_test.go`: the jets for `findB` and `setB`, and the fit of their arm costs.
- `hash.go`: the content hash (SPEC.md section 12.7).
- `memo.go`, `memo_test.go`: the memo (SPEC.md section 7), and the incremental measurement.
- `corpus_test.go`: the corpus build (Phase 8), against `testdata/corpus.txt`.
- `profile_test.go`: the core's profile of the checker (`PROFILE=1`).
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

A jet is native code that replaces one law's body (SPEC.md section 3, decision 11). The machine picks it by the law's content hash (section 12.7), so a program never names a jet. A jet:

- declares the fuel of the body it replaces, counting the entry, and the machine charges that fuel in one go;
- handles only the inputs it has checked, and gives up on anything else, so errors and out-of-fuel points stay the spec's;
- is used only when the whole call fits in the fuel left;
- is fixed in the build. There are no work-only jets.

There are five jets on the checker:

- `tl`, `hdOr` and `stP`, the small helpers, with their fuel measured on the reference.
- `findB` and `setB`, the radix-4 trie's lookup and update. Each is a whole recursion, not one level: a walk takes the same path as the body and counts the six arms (empty, a zero id, and the four children). The arm costs are fitted to the reference's steps (`trie_test.go`), and the fit is exact on every case, including the fuel edges (exactly the call's steps, and one less).

On the checker, the jets are used about 565,000 times and replace 62.8% of the core's steps (68.0 million of 108.4 million). The steps are unchanged, by design, and the run takes about 1.2 s with the jets against 2.5 s without, on one host.

## Limits of this version

- The machine reads the bytes of a program into a tree of resolved nodes, not into one flat array. The flat layout is the next step if the speed target needs it.
- Readers and writers recurse, as the Go call stack allows (up to 1 GB by default, so far deeper than the 20,000 tested). The spec asks for no depth limit; the Go stack is the limit here.
- The reference's inline checks in `interp_run.luau` are not ported one by one. Each rule they test is covered by a hand-written case, and the spec's examples keep their step counts (`call (lit inc) (lit 41)` is 7 steps).

## The corpus build and the memo

The corpus is the four boot files (2,235 lines). The build runs each through its imports and then layout, lex, parse and check, on four core programs, and checks every stage against the reference. It takes about 5.5 s here (down from 6.9 s, after the simplifications in the plan's experiments section), against a 1 s target for 2,500 lines (see the plan, Phase 8). With the memo on, a cold build takes about twice as long, and an unchanged rebuild takes 0.04 s.

The memo (decisions 13 and 14) is off by default. Turn it on with `MemoOn`, and it stores only calls of at least `MemoMinFuel` (1,000) steps. A one-declaration change to the checker re-checks 270 calls.
