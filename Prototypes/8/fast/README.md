# Prototype 8: the fast machine (Go)

The core of L2 (`l2/SPEC.md`), run on Go. It reads the binary format of section 12 of `Prototypes/7/SPEC.md`, and runs programs with the fuel rule of section 6. The Luau implementations that earlier prototypes used as oracles have been removed; their checks are kept as fixtures in `testdata/`, which the tests read. The Luau code and the generators that wrote the fixtures are in the git history of Prototypes 6 and 7.

## Files

The machine:

- `value.go`: the values, and the integer operations (`Small` for any integer that fits in int64, `*big.Int` for the rest; a result that fits is always a `Small`).
- `node.go`: forms, with their parts resolved (children, alternatives, else branch). The reader builds them directly, so a law's body is in this form when it is read.
- `format.go`: the writer and the reader of section 12, with the same messages as the Luau reader it replaced.
- `eval.go`: the evaluator, the one machine. A node is evaluated by a call that returns its value; a call in tail position is returned to a loop (`runBody`), so a loop of any length uses the stack of one call. Operands are kept on one stack. The steps, fuel, errors and outcomes are the spec's, form for form. A body owns its frame and gives it back to a per-run pool when nothing refers to it any more (`getFrame`, `putFrame`).
- `machine.go`: the outcome type, `Run` and `RunBody`, and the step hook the profile uses.
- `prim.go`: the thirteen primitives (pins were removed, SPEC.md decision 16).
- `equal.go`: the deep equality that `=` (tag 6) runs, `deepEqual` (SPEC.md section 6, decision 12). It is one step, like every primitive, and its walk is not charged for the size of its operands.
- `hash.go`: the content hash, the implementation's keys (see "Keys" below).
- `memo.go`: the memo (SPEC.md section 7).

The jets (see "Jets" below):

- `jets.go`: the jet table, and the helper jets. It also keeps each law's jet on the law, looked up once.
- `trie.go`: the jets for `findB` and `setB`, the radix-4 trie's lookup and update.
- `prune.go`: the jet for `prune`, the checker's chase of a type variable.
- `listjets.go`: the jets for `lenOf`, `envKid`, `envPut` and the parser's `same`.
- `same.go`: the jet for the name comparison `same`.
- `corpusjets.go`: the jets for the corpus's helpers `first`, `hd` and `kn`.
- `desugarjets.go`: the jets for the desugarer's `same` and `posIn`.

The compiler, the file format and the driver:

- `convert.go`: the converter. The desugarer's output (a `Code` value) is read as an expression, then lowered to the core.
- `pipeline.go`: runs the five stage programs (layout, tokenizer, parser, checker, desugarer) on the machine.
- `programfile.go`: splits a program file into its four sections (header, imports, program, tests).
- `p8.go`: the P8 container, which reads and writes `.p8` files (`FORMAT.md`, in the parent folder).
- `cmd/l2/main.go`: the driver (see "Running" below).

Tests, and their fixtures:

- `eval_test.go`: a tail loop of three million calls, a call nested a hundred thousand deep, and the nesting limit.
- `fast_test.go`: runs every case in `testdata/cases.txt` with the jets on and off, and times the checker.
- `cases_test.go`: the case programs in `testdata/cases/` and `testdata/l2cases.txt`.
- `programs_test.go`: the 148 tests of the 45 program files in `l2/programs/`, through the Go pipeline.
- `pipeline_test.go`: the seed's fixed point and its generations.
- `p8_test.go`: the P8 container, its round trip and its refusals.
- `checker_test.go`, `layout_test.go`, `refusals_test.go`, `desugar_test.go`, `convert_test.go`: the parity fixtures (below).
- `corpus_test.go`: the corpus build, against `testdata/corpus.txt` or the file named by `CORPUS`.
- `corpus_profile_test.go`, `profile_test.go`: the profiles (`PROFILE_CORPUS=1`, `PROFILE=1`).
- `jets_test.go`: checks that every jet still names a law of the checker's program or the corpus's.
- `trie_test.go`, `prune_test.go`, `listjets_test.go`, `same_test.go`, `desugarfit_test.go`: the fit of each jet's arm costs.
- `memo_test.go`, `hash_test.go`, `format_test.go`: the memo, the content hash, and the format.

## Running

From this folder (`Prototypes/8/fast`):

    go test ./...                       # every case, the parity fixtures, and the checker's steps and speed
    go test -run TestChecker -v ./...   # the checker alone, with its speed
    forkmat -all -w .                   # the formatter for this folder

The fixtures in `testdata/` are static: nothing regenerates them in this prototype. To change one, change the test that reads it, or the program it describes, and update the fixture by hand.

## The cases

Each line of `testdata/cases.txt` is one case: a name, a mode (`body`: the body with the frame `[NIL, input]`; or `run`: the law applied to the input, one entry), the program bytes, the input bytes, the fuel, and the expected outcome.

- 50 hand-written cases: one for each rule of section 3, each primitive and its errors, partial and over-application, self-reference, out of fuel, big integers, and a program 20,000 forms deep.
- 50 Prototype 5 examples, with the budget `cross_run` gives them.
- 147 tests of the Prototype 6 L2 programs, with the same budgets.
- The checker: the variant `types.l2` on Prototype 6's `types.l2`, the Phase 0 benchmark.

## Jets

A jet is native code that replaces one law's body (SPEC.md section 3, decision 11). The machine picks it by the law's content hash (see "Keys" below), so a program never names a jet. A jet:

- declares the fuel of the body it replaces, counting the entry, and the machine charges that fuel in one go;
- handles only the inputs it has checked, and gives up on anything else, so errors and out-of-fuel points stay the spec's;
- is used only when the whole call fits in the fuel left;
- is fixed in the build. There are no work-only jets.

There are seven jets on the checker and on the corpus's helpers, and nine more on the corpus's list helpers:

- `tl`, `hdOr` and `stP`, the small helpers, with their fuel measured on the reference (a cell takes 12 steps for `tl` and `hdOr`, anything else 53; `stP` takes 12 for a constructor). Their laws use `head` or `tail` as a match on the kind of the list, so they must be re-measured whenever the desugarer changes.
- `same`, the name comparison: a walk of two lists of bytes, with the arm costs fitted to the reference's steps (`same_test.go`).
- `first` (the checker's and the parser's) and `hd` (the layout's), a match on a cell, 12 steps, and 53 on anything else; `kn` (the parser's token kinds), 10 + 5k for kind k, and it gives up past 15 (`corpusjets.go`).
- `prune`, the checker's chase of a type variable through the trie (`prune.go`): its own arms are a constructor (22 steps), an unbound variable (35) and a bound one (33), and each `findB` it calls is costed by the trie's table.
- `lenOf` (the checker's length), `envKid` and `envPut` (the name environment's lookup and insertion), and the parser's `same` (a different body from the checker's `same`: its test on a list is a nil test, so a value that is not a list is refused): each walks its list and counts its arms (`listjets.go`).
- `findB` and `setB`, the radix-4 trie's lookup and update. Each is a whole recursion, not one level: a walk takes the same path as the body and counts the six arms (empty, a zero id, and the four children). The arm costs are fitted to the reference's steps (`trie_test.go`), and the fit is exact on every case, including the fuel edges (exactly the call's steps, and one less).

The steps are unchanged, by design. The checker takes 68,125,825 core steps and about 0.18 s with the jets, on one host.

## Limits of this version

- The machine reads the bytes of a program into a tree of resolved nodes, not into one flat array. The flat layout was tried and was slower.
- **Nesting limit (a host limit, not in the spec).** A nested evaluation takes about a kilobyte of the Go stack, and the default stack is one gigabyte, so a run nested deeper than `MaxNesting` (400,000 evaluations, about 130,000 calls nested in calls) ends with the status `host_limit`, not with the stack overflowing. The spec asks for no depth limit; tail calls are not nested, so only nesting counts. A deeper program needs the limit raised (with `debug.SetMaxStack`) or the evaluator made iterative again.
- Readers and writers recurse, as the Go call stack allows (up to 1 GB by default, so far deeper than the 20,000 tested). The spec asks for no depth limit; the Go stack is the limit here.
- The Luau reference's inline checks are not ported one by one. Each rule they tested is covered by a hand-written case, and the spec's examples keep their step counts (`call (lit inc) (lit 41)` is 7 steps).

## The corpus build and the memo

The corpus is the four boot files and the 20 standard-library files (24 files, 2,590 lines), in `testdata/corpus.txt`. The build runs each file through its imports and then layout, lex, parse and check, on four core programs, and checks every stage against the fixture. It takes 263,212,747 core steps and 0.905 s, median of five (0.891 s best), with the jets on (2.46 s with them off), against a 1 s target for 2,500 lines. The 2,500-line corpus is the boot files and 13 of the libraries (17 files), and it is the one the target is measured on; the build meets the target by linear extrapolation (about 0.91 s at 2,500 lines), not by a run of that size. With the memo on, a cold build takes 2.5 s, and an unchanged rebuild takes 0.04 s.

With the desugarer, the build of the 17 files (`testdata/corpus2500_desugar.txt`) also runs the desugarer on each library, which gives the import expressions, and on each file, after its check: 437,289,529 core steps, a median of about 1.82 s over five runs (against 1.28 s and 298,923,075 steps without it). The desugarer is 119,813,160 steps of the build (46% more). Its two hottest laws have jets (`desugarjets.go`): desugar:same@25 and desugar:posIn@241, which together were 37M of its interpreted steps. It still misses the 1 s target for 2,500 lines by about 26%: most of the desugarer's remaining interpreted steps are in desugar:top (27M), which has no jet. The desugarer's input is the parse, the import names and expressions, with no checks, so the input boundary's cost is left out.

The memo (decisions 13 and 14) is off by default. Turn it on with `MemoOn`, and it stores only calls of at least `MemoMinFuel` (1,000) steps. A one-declaration change to the checker re-checks 270 calls.

## Keys: the content hash

The memo and the jet table (SPEC.md section 7) are keyed by the content hash of a value, which the spec does not define (decision 18). This implementation defines it as follows (`hash.go`, the vectors in `hash_test.go`):

- The content hash of a value that has a binary form is 32 bytes, and two values have the same hash exactly when they have the same binary form (with overwhelming probability).
- An integer, nil or a law: the SHA-256 of the value's encoding in SPEC.md section 12.3, without the header byte. A law's hash is that of its own encoding: its tag, its arity and its body.
- A cell, a constructor or a partial application: the SHA-256 of a one-byte tag and the content hashes of its parts, so a new node costs one hash once its parts' hashes are known. The tags are `C` for a cell (head, then tail), `K` for a constructor (its tag as a magnitude, then its payload) and `A` for a partial application (the law, then the arguments in order, each preceded by the count).
- A value with no binary form (a thunk) has no hash, and a primitive that needs one is an error.
- The header byte is left out so that a value's hash is the same whether it is written alone or inside another value. Example: the law `inc` (SPEC.md section 9) is `05 01 1a 00 11 01 10 02 01`, and its hash is `1b4ec34d dd5d101a ad9fd988 9cdf35b5 68a2b93f 2a2061cc 9819af67 768bb2dd`.

A memo key is the law's hash and the hashes of its arguments (`memo.go`). A jet is picked by the law's hash (`jets.go`).

## The pipeline, the seed, and the driver

The compiler runs on this machine. `pipeline.go` runs the five stage programs, and `convert.go` turns the desugarer's output into the law the machine runs.

- `testdata/seed.p8` is the seed: a P8 file holding the five stage programs (generation 2; see `FORMAT.md`). It is embedded in the build. `TestSeedFixedPoint` and `TestSeedGenerations` check that the seed compiles its own stage sources to itself. `l2 seed` rebuilds it and reports whether it is a fixed point.
- `programs_test.go` runs the 148 tests of the 45 program files through the Go pipeline: each input and output expression is evaluated, the program runs on the machine, and both must give the encodings in `testdata/programs.txt`.
- `cmd/l2`: `l2 run [-root dir] file.l2` runs a program file's tests (printing each value), `l2 eval file.l2 expr` evaluates an expression, `l2 build`, `l2 exec` and `l2 seed` work with P8 files, and any command takes `-compiler c.p8`. The root is the programs folder, which imports are read under (default `../l2/programs/`).

Timings on this host, one run each, from the driver: `lib/abs.l2` (three tests) about 0.08 s, including loading the seed. `boot/types.l2` (19 tests, the checker itself) about 3.2 s. The compile is most of that; it is the stage programs running, with no jets on the stage laws beyond the corpus's own.

## The parity fixtures

Each check against the old Luau oracles is kept as a fixture in `testdata/`, and the Go tests read the fixture, not the Luau code.

| Fixture | Test | What it checks |
| --- | --- | --- |
| `programs.txt` | `programs_test.go` | the 148 tests of the 45 program files: input and output encodings, and the run on the Go machine |
| `refusals.txt` | `refusals_test.go` | the 31 malformed programs: the stage that refuses each, and its reason |
| `checker.txt` | `checker_test.go` | the pure checker's outcome on 164 sources: 161 agree, 3 skipped |
| `layout.txt` | `layout_test.go` | the layout stage on 1,284 inputs: a SHA-256 of each text, or each error message (about 70 s) |
| `cases/`, `l2cases.txt` | `cases_test.go` | the 6 case programs and their 13 tests |
| `desugar.txt` | `desugar_test.go` | the desugarer's outcome on 87 expressions and programs: 87 agree, 3 skipped |
| `convert.txt` | `convert_test.go` | the converter's law and the desugarer's Code value, for 17 files |
| `corpus.txt`, `corpus2500_desugar.txt` | `corpus_test.go` | the corpus build's stages, and the build with the desugarer |
| `cases.txt` | `fast_test.go` | the machine's outcomes, with the jets on and off |

The desugarer parity's corpus of 44 library-style programs is not exported: the program-file tests and the converter fixture cover the same forms.
