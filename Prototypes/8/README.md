# Prototype 8: the machine, and the compiler it runs

This prototype keeps only the code that runs L2 programs: the virtual machine, the converter from the compiler's output to machine code, and the driver. The Luau implementations that the earlier prototypes used as oracles are being removed; their checks live on as fixtures in `fast/testdata/`.

## Layout

- `l2/`: the L2 sources, shared by every implementation of the machine. `l2/programs/` holds the program files (45, with `boot/` for the five compiler stages and `lib/` for the standard library). `l2/SPEC.md`, `RECORDS.md` and `INDENTATION.md` are the language's specification.
- `fast/`: the Go implementation. The machine (`eval.go`, `format.go`, `hash.go`, `jets.go` and the jet files, `memo.go`, `node.go`, `prim.go`, `value.go`), the converter (`convert.go`), the pipeline that runs the compiler's stages (`pipeline.go`, `programfile.go`), the seed compiler (`testdata/stages.txt`), and the driver (`cmd/l2`). Its README describes the machine and the fixtures.

Further implementations of the machine go beside `fast/`, each as its own module, and read the same `l2/` sources.

## Status

- The seed compiler is its own fixed point: the five stages, compiled by the seed, give the seed's bytes.
- All 148 program tests, and every parity fixture, pass on the Go machine.
- The Luau implementations were removed from Prototypes 6 and 7; they remain in git history. Everything the tests need is in `l2/` and `fast/testdata/`, so the suite does not depend on them.

## Commands

From `Prototypes/8/fast`:

    go test ./...                       the whole suite (about two minutes)
    go run ./cmd/l2 run file.l2         run a program file's tests
    go run ./cmd/l2 eval file.l2 expr   evaluate an expression in the file's scope
    go run ./cmd/l2 seed                rebuild the seed, and check that it is a fixed point
