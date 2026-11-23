# Prototype 7, Phase 4: the fast machine (Go)

The core of `SPEC.md`, run on Go. It reads the binary format of section 12, and runs programs with the fuel rule of section 6. The Luau reference (`reference/`) is the oracle: every case here gives the reference's status, steps, value bytes and error message.

## Files

- `value.go`: the values, and the integer operations (`Small` for any integer that fits in int64, `*big.Int` for the rest; a result that fits is always a `Small`).
- `node.go`: forms, with their parts resolved (children, alternatives, else branch). The reader builds them directly, so a law's body is in this form when it is read.
- `format.go`: the writer and the reader of section 12, byte for byte the same as `reference/format.luau`, with the same messages.
- `eval.go`: the evaluator, the one machine. A node is evaluated by a call that returns its value; a call in tail position is returned to a loop (`runBody`), so a loop of any length uses the stack of one call. Operands are kept on one stack. The steps, fuel, errors and outcomes are the spec's, form for form.
- `machine.go`: the outcome type, `Run` and `RunBody`, and the step hook the profile uses.
- `eval_test.go`: a tail loop of three million calls, a call nested a hundred thousand deep, and the nesting limit.
- `corpus_profile_test.go`: the corpus's profile by owner (`PROFILE_CORPUS=1`).
- `prim.go`: the thirteen primitives (pins were removed, SPEC.md decision 16).
- `jets.go`: the jet table, and the helper jets (see "Jets" below).
- `trie.go`, `trie_test.go`: the jets for `findB` and `setB`, and the fit of their arm costs.
- `prune.go`, `prune_test.go`: the jet for `prune`, the checker's chase of a type variable, with the fit of its own arms (the `findB` calls are costed by the trie's table).
- `listjets.go`, `listjets_test.go`: the jets for `lenOf`, `envKid`, `envPut` and the parser's `same`, and the fit of their arm costs.
- `same.go`, `same_test.go`: the jet for the name comparison `same`, and the fit of its arm costs.
- `corpusjets.go`: the jets for the corpus's helpers `first`, `hd` and `kn`.
- `jets.go` also keeps each law's jet on the law, looked up once.
- `hash.go`: the content hash (SPEC.md section 12.7).
- `memo.go`, `memo_test.go`: the memo (SPEC.md section 7), and the incremental measurement.
- `corpus_test.go`: the corpus build (Phase 8), against `testdata/corpus.txt`.
- `profile_test.go`: the core's profile of the checker (`PROFILE=1`).
- `fast_test.go`: runs every case in `testdata/cases.txt` with the jets on and off, and times the checker.
- `jets_test.go`: checks that every jet still names a law of the checker's program or the corpus's.
- `gen/gen.luau`: writes `testdata/cases.txt` from the reference.
- `gen/corpus.luau`: writes `testdata/corpus.txt` from the reference, with a `# law` line for each law of the stage programs and its owner.

## Running

    go test ./...                       # every case, and the checker's steps and speed
    go test -run TestChecker -v ./...   # the checker alone, with the speed against the reference
    forkmat -all -w .                   # the formatter for this folder

To regenerate the cases (from the measurement folder, because the L2 compiler reads paths from there):

    cd Prototypes/7/measure && lute run ../fast/gen/gen.luau > ../fast/testdata/cases.txt

## The cases

Each line of `testdata/cases.txt` is one case: a name, a mode (`body`: the body with the frame `[NIL, input]`, as the reference's `runForm`; or `run`: the law applied to the input, one entry), the program bytes, the input bytes, the fuel, and the reference's outcome.

- 50 hand-written cases: one for each rule of section 3, each primitive and its errors, partial and over-application, self-reference, out of fuel, big integers, and a program 20,000 forms deep.
- 50 Prototype 5 examples, with the budget `cross_run` gives them.
- 147 tests of the Prototype 6 L2 programs, with the same budgets.
- The checker: the variant `types.l2` (`measure/boot/`) on Prototype 6's `types.l2`, the Phase 0 benchmark.

## Jets

A jet is native code that replaces one law's body (SPEC.md section 3, decision 11). The machine picks it by the law's content hash (section 12.7), so a program never names a jet. A jet:

- declares the fuel of the body it replaces, counting the entry, and the machine charges that fuel in one go;
- handles only the inputs it has checked, and gives up on anything else, so errors and out-of-fuel points stay the spec's;
- is used only when the whole call fits in the fuel left;
- is fixed in the build. There are no work-only jets.

There are seven jets on the checker and on the corpus's helpers, and nine more on the corpus's list helpers (below):

- `tl`, `hdOr` and `stP`, the small helpers, with their fuel measured on the reference (a cell takes 12 steps for `tl` and `hdOr`, anything else 53; `stP` takes 12 for a constructor). Their laws use `head` or `tail` as a match on the kind of the list, so they are re-measured whenever the desugarer changes.
- `same`, the name comparison: a walk of two lists of bytes, with the arm costs fitted to the reference's steps (`same_test.go`).
- `first` (the checker's and the parser's) and `hd` (the layout's), a match on a cell, 12 steps, and 53 on anything else; `kn` (the parser's token kinds), 10 + 5k for kind k, and it gives up past 15 (`corpusjets.go`).
- `prune`, the checker's chase of a type variable through the trie (`prune.go`): its own arms are a constructor (22 steps), an unbound variable (35) and a bound one (33), and each `findB` it calls is costed by the trie's table.
- `lenOf` (the checker's length), `envKid` and `envPut` (the name environment's lookup and insertion), and the parser's `same` (a different body from the checker's `same`: its test on a list is a nil test, so a value that is not a list is refused): each walks its list and counts its arms (`listjets.go`).
- `findB` and `setB`, the radix-4 trie's lookup and update. Each is a whole recursion, not one level: a walk takes the same path as the body and counts the six arms (empty, a zero id, and the four children). The arm costs are fitted to the reference's steps (`trie_test.go`), and the fit is exact on every case, including the fuel edges (exactly the call's steps, and one less).

The steps are unchanged, by design. The checker takes 68,125,825 core steps and about 0.18 s with the jets, on one host (the figures for the checker alone are in the plan's Phase 8 section).

## Limits of this version

- The machine reads the bytes of a program into a tree of resolved nodes, not into one flat array. The flat layout was tried and was slower (see the plan's experiments).
- **Nesting limit (a host limit, not in the spec).** A nested evaluation takes about a kilobyte of the Go stack, and the default stack is one gigabyte, so a run nested deeper than `MaxNesting` (400,000 evaluations, about 130,000 calls nested in calls) ends with the status `host_limit`, not with the stack overflowing. The spec asks for no depth limit; tail calls are not nested, so only nesting counts. The old explicit-stack machine had none, and a deeper program needs the limit raised (with `debug.SetMaxStack`) or the evaluator made iterative again.
- Readers and writers recurse, as the Go call stack allows (up to 1 GB by default, so far deeper than the 20,000 tested). The spec asks for no depth limit; the Go stack is the limit here.
- The reference's inline checks in `interp_run.luau` are not ported one by one. Each rule they test is covered by a hand-written case, and the spec's examples keep their step counts (`call (lit inc) (lit 41)` is 7 steps).

## The corpus build and the memo

The corpus is the four boot files and the 20 standard-library files (24 files, 2,590 lines). The build runs each through its imports and then layout, lex, parse and check, on four core programs, and checks every stage against the reference. It takes 263,212,747 core steps and about 0.94 s here (best of five), with the jets on (2.46 s with them off), against a 1 s target for 2,500 lines, which the 2,590-line build meets by linear extrapolation (about 0.91 s at 2,500 lines; see the plan, Phase 8). With the memo on, a cold build takes 2.5 s, and an unchanged rebuild takes 0.04 s.

The memo (decisions 13 and 14) is off by default. Turn it on with `MemoOn`, and it stores only calls of at least `MemoMinFuel` (1,000) steps. A one-declaration change to the checker re-checks 270 calls.
