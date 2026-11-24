# Prototype 7, Phase 4: the fast machine (Go)

The core of `SPEC.md`, run on Go. It reads the binary format of section 12, and runs programs with the fuel rule of section 6. The Luau reference (`reference/`) is the oracle: every case here gives the reference's status, steps, value bytes and error message.

## Files

- `value.go`: the values, and the integer operations (`Small` for any integer that fits in int64, `*big.Int` for the rest; a result that fits is always a `Small`).
- `node.go`: forms, with their parts resolved (children, alternatives, else branch). The reader builds them directly, so a law's body is in this form when it is read.
- `format.go`: the writer and the reader of section 12, byte for byte the same as `reference/format.luau`, with the same messages.
- `eval.go`: the evaluator, the one machine. A node is evaluated by a call that returns its value; a call in tail position is returned to a loop (`runBody`), so a loop of any length uses the stack of one call. Operands are kept on one stack. The steps, fuel, errors and outcomes are the spec's, form for form. A body owns its frame and gives it back to a per-run pool when nothing refers to it any more (`getFrame`, `putFrame`).
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
- `desugarjets.go`, `desugarfit_test.go`: the jets for the desugarer's `same` and `posIn` (desugar:same@25, desugar:posIn@241), with their arm costs fitted to the steps with the jets off.
- `jets.go` also keeps each law's jet on the law, looked up once.
- `convert.go`, `convert_test.go`: the converter (Prototype 8, step 1): the desugarer's output (a `Code` value) read as a Prototype 6 expression, then lowered to the core as `reference/lower.luau` does. `gen/convert.luau` writes `testdata/convert.txt`, the bootstrapped compile's Code values and program laws, which the test checks byte for byte.
- `hash.go`: the content hash, the implementation's keys (see "Keys" below).
- `memo.go`, `memo_test.go`: the memo (SPEC.md section 7), and the incremental measurement.
- `corpus_test.go`: the corpus build (Phase 8), against `testdata/corpus.txt`, or the file named by `CORPUS` (for example `CORPUS=testdata/corpus2500.txt`, the 2,500-line corpus).
- `profile_test.go`: the core's profile of the checker (`PROFILE=1`).
- `fast_test.go`: runs every case in `testdata/cases.txt` with the jets on and off, and times the checker.
- `jets_test.go`: checks that every jet still names a law of the checker's program or the corpus's.
- `gen/gen.luau`: writes `testdata/cases.txt` from the reference.
- `gen/corpus.luau`: writes `testdata/corpus.txt` from the reference, with a `# law` line for each law of the stage programs and its owner. `gen/corpus2500.luau` is the same for the 2,500-line corpus (`testdata/corpus2500.txt`).

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

A jet is native code that replaces one law's body (SPEC.md section 3, decision 11). The machine picks it by the law's content hash (fast/README.md "Keys"), so a program never names a jet. A jet:

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

With the desugarer, the build of the same 17 files (`testdata/corpus2500_desugar.txt`) also runs the desugarer on each library, which gives the import expressions, and on each file, after its check: 437,289,529 core steps, a median of about 1.82 s over five runs after the corpora were regenerated from the current compiler (the 17 files are now 2,813 lines, not 2,500; before that, 1.31 s for 381,160,207 steps), against 1.28 s and 298,923,075 steps without it (the same host, the same five runs; `testdata/corpus2500.txt`). The desugarer is 119,813,160 steps of the build (46% more). Its two hottest laws have jets (`desugarjets.go`): the name comparison, desugar:same@25, and the index of a name, desugar:posIn@241, which together were 37M of its interpreted steps; the build's steps are unchanged by them. Before the jets the build was about 1.53 s. It still misses the 1 s target for 2,500 lines by about 26%: most of the desugarer's remaining interpreted steps are in desugar:top (27M), which has no jet. The desugarer's input is the parse, the import names and expressions, with no checks (the corpus has none) and no input check, so the input boundary's cost is left out.

The corpus is the four boot files and the 20 standard-library files (24 files, 2,590 lines); the 2,500-line corpus is the boot files and 13 of the libraries (17 files, `testdata/corpus2500.txt`), and it is the one the speed target is measured on (1.31 s, median of five, on the regenerated 24-file corpus of 2,903 lines, 301,852,138 steps; before the regeneration it was 0.91 s for 2,590 lines). The build runs each through its imports and then layout, lex, parse and check, on four core programs, and checks every stage against the reference. It takes 263,212,747 core steps and 0.905 s, median of five (0.891 s best), with the jets on (2.46 s with them off), against a 1 s target for 2,500 lines, which the 2,590-line build meets by linear extrapolation (about 0.91 s at 2,500 lines; see the plan, Phase 8). With the memo on, a cold build takes 2.5 s, and an unchanged rebuild takes 0.04 s.

The memo (decisions 13 and 14) is off by default. Turn it on with `MemoOn`, and it stores only calls of at least `MemoMinFuel` (1,000) steps. A one-declaration change to the checker re-checks 270 calls.

## Keys: the content hash

The memo and the jet table (SPEC.md section 7) are keyed by the content hash of a value, which the spec does not define (decision 18). This implementation defines it as follows (`hash.go`, the vectors in `hash_test.go`):

- The content hash of a value that has a binary form is 32 bytes, and two values have the same hash exactly when they have the same binary form (with overwhelming probability).
- An integer, nil or a law: the SHA-256 of the value's encoding in SPEC.md section 12.3, without the header byte. A law's hash is that of its own encoding: its tag, its arity and its body.
- A cell, a constructor or a partial application: the SHA-256 of a one-byte tag and the content hashes of its parts, so a new node costs one hash once its parts' hashes are known. The tags are `C` for a cell (head, then tail), `K` for a constructor (its tag as a magnitude, then its payload) and `A` for a partial application (the law, then the arguments in order, each preceded by the count).
- A value with no binary form (a thunk) has no hash, and a primitive that needs one is an error.
- The header byte is left out so that a value's hash is the same whether it is written alone or inside another value. Example: the law `inc` (SPEC.md section 9) is `05 01 1a 00 11 01 10 02 01`, and its hash is `1b4ec34d dd5d101a ad9fd988 9cdf35b5 68a2b93f 2a2061cc 9819af67 768bb2dd`.

A memo key is the law's hash and the hashes of its arguments (memo.go). A jet is picked by the law's hash (jets.go).

## The pipeline, the seed, and the driver (Prototype 8)

The compiler runs on this machine. `pipeline.go` runs the five stage programs (layout, tokenizer, parser, checker, desugarer) as `boot_pipeline.luau` does, and `convert.go` turns the desugarer's output into the law the machine runs.

- `testdata/stages.txt` is the seed: the five stage programs, embedded in the build. It is the compiler's second generation. The first generation was the host's lowering of the stage sources; compiled with it, the stages give the second generation, and the second generation compiles to itself (`TestSeedFixedPoint`, `TestSeedGenerations`). `l2 seed` rebuilds it and checks the fixed point.
- `programfile.go` splits a program file into its four sections, as `programfile.luau` does.
- `programs_test.go` runs the 148 tests of the 45 program files through the Go pipeline: each input and output expression is evaluated, the program runs on the machine, and both must give the bootstrapped compile's encodings (`testdata/programs.txt`, from `gen/programs.luau`). All 148 pass.
- `cmd/l2`: `l2 run [-root dir] file.l2` runs a program file's tests (printing each value), `l2 eval file.l2 expr` evaluates an expression, and `l2 seed` writes the stages. The root is the programs folder, which imports are read under (default `../../6/L2/programs/`).

Timings on this host, one run each, from the driver: `lib/abs.l2` (three tests) about 0.08 s, including loading the seed. `boot/types.l2` (19 tests, the checker itself) about 3.2 s. The compile is most of that; it is the stage programs running, with no jets on the stage laws beyond the corpus's own.

## The parity fixtures (Prototype 8, step 1)

Each Luau oracle that the Go side must agree with is exported as a fixture in `testdata/`, written by a generator in `gen/` while the Luau code still exists. The Go tests read the fixtures, not the Luau code.

| Fixture | Generator | Test | What it checks |
| --- | --- | --- | --- |
| `programs.txt` | `gen/programs.luau` | `programs_test.go` | the 148 tests of the 45 program files: input and output encodings, and the run on the Go machine |
| `refusals.txt` | `gen/refusals.luau` | `refusals_test.go` | the 31 malformed programs: the stage that refuses each, and its reason |
| `checker.txt` | `gen/checker.luau` (sources in `gen/checker_sources.luau`) | `checker_test.go` | the pure checker's outcome on 164 sources: 161 agree, 3 skipped |
| `layout.txt` | `gen/layout.luau` | `layout_test.go` | the layout stage on 1,284 inputs (about 70 s) |
| `cases/`, `l2cases.txt` | `gen/cases.luau` | `cases_test.go` | the 6 case programs and their 13 tests |
| `desugar.txt` | `gen/desugar.luau` | `desugar_test.go` | the desugarer's outcome on 87 expressions and programs: 87 agree, 3 skipped |
| `convert.txt` | `gen/convert.luau` | `convert_test.go` | the converter's law and the desugarer's Code value, for 17 files |

The desugarer parity's corpus of 44 library-style programs is not exported: the program-file tests and the converter fixture cover the same forms.
