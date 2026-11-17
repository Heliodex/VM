# Prototype 4: interaction combinators and a small Lisp

Everything here runs on interaction-net reduction. The directories are layers: each one uses only those above it in the list.

| Directory | What it holds |
| --- | --- |
| `engine/` | Nets, the six interaction rules, the builder, the reduction harness, canonical forms and observation, the standard gadgets, and the codes that let a net be copied. |
| `calculus/` | The λ-calculus encoding, Church booleans, Scott numerals with arithmetic, recursion through codes, and Scott lists. |
| `language/` | The Lisp: the reader, tagged values, the compiler, sessions, and the printer. |
| `diagram/` | Drawing reduction steps as SVG, with the layout code in `diagram/drawing/`. |
| `checks/` | The validation suite, the command-line tests, and the test cases shared by the suite and the diagram tool. |
| `tools/` | `lisp.luau`, the Lisp REPL and runner; `main.luau`, which draws the reduction of each test case as a page. |
| `research/` | The fixed-point and recursion probes, kept as the record of why recursion works the way it does. |

## Running

Run these from this directory, since the paths are relative to it.

| What | Command | Runtime |
| --- | --- | --- |
| The validation suite | `lute run checks/validate.luau` (also works with `luau`) | lute or luau |
| The command-line tests | `lute run checks/test_lisp.luau` | lute |
| The Lisp REPL | `lute run tools/lisp.luau` | lute |
| Run a Lisp file | `lute run tools/lisp.luau program.lisp` | lute |
| Evaluate one expression | `lute run tools/lisp.luau -e "(+ 1 2)"` | lute |
| The reduction page | `luau tools/main.luau > reductions.html` | luau |
| The recursion probes | `luau research/recursionprobe.luau` | luau |

`tools/lisp.luau` and `checks/test_lisp.luau` use Lute's standard library (`@std/...`), so they need lute. The other modules use only plain Luau.

## Checking the code

- `lute check` over the `.luau` files should report no errors.
- `luau-format` formats the files in place.
