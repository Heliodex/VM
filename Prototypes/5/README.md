# Prototype 5: a reference interpreter

A strict, sequential interpreter for a small functional language with native data: integers, cells (pairs), nil, closures and pins. It is the spec for later prototypes, so any other implementation should agree with it on `examples.luau`.

| File | What it holds |
| --- | --- |
| `vm.luau` | The machine, the printer, and the builders for expressions. |
| `reader.luau` | The reader: text syntax to expressions. The syntax is described at the top of the file. |
| `examples.luau` | 31 programs built with the builders, each with a fuel budget and its expected outcome. |
| `text.luau` | 31 of the same programs in the text syntax, plus 13 sources the reader must reject. |
| `self.luau` | The self-interpreter: an interpreter for the language, written in the language, with the quoting that feeds it. |
| `self_run.luau` | Runs every example through the self-interpreter and checks it gives the same result. |
| `run.luau` | Runs every example and reject, and reports pass or fail. |

## Running

Run from this directory.

| What | Command |
| --- | --- |
| The checks | `luau run.luau` |
| The analyser | `luau-analyze vm.luau reader.luau examples.luau text.luau run.luau` |
| The self-interpreter checks | `luau self_run.luau` |
| The formatter | `luau-format vm.luau reader.luau examples.luau text.luau self.luau self_run.luau run.luau` |

The runner exits with status 1 if any check fails.

## The language

- **Values:** integers, `nil`, cells, closures and pins. Lists are nested cells ending in `nil`.
- **Expressions:** `int`, `nilv`, `var` (by index), `lam` (no name), `app` (curried), `cell`, `head`, `tail`, `ite` (only the branch taken is evaluated), `pin`, `force`, and `prim` on integers (`add`, `sub`, `mul`, `lt`, `eq`) or `isnil`.
- **Recursion:** `M.fix` is the strict fixed-point combinator. A recursive function is `app(fix, lam(lam(...)))`, and the outer binder, index 1 inside the inner body, refers to the function itself.
- **Pins:** a pin is a suspended expression. Creating one does not run it. Forcing it runs it once, and later forces return the same value.

## Fuel and outcomes

Every step of the machine costs one unit of fuel. A run ends in one of three ways:

- `value`, with the result,
- `error`, with a message (a type error, an unbound name, forcing a pin inside itself),
- `out_of_fuel`, when the budget runs out.

Out of fuel is a result, not a hang, so a diverging program can be tested like any other.

## Decisions and limits

- **No host recursion.** Pending work sits on an explicit stack. The 10,000-element loop in the examples runs in one Luau call frame.
- **Numbers are Luau numbers,** so integers are exact only up to 2^53.
- **Pins are memoised,** but the examples cannot see the difference except through step counts.
- **Variables are de Bruijn indices.** The machine never sees a name: `var 0` is the innermost binder, `var 1` the one outside it. The reader turns names into indices and rejects a name that is not bound, so the machine has no unbound-name errors from programs read from text. Names exist only in the reader and the surface syntax. The language has no symbol type, so a self-interpreter could not compare names anyway.
- **Expressions are built by Lua functions,** not parsed from text. Surface syntax is a later decision.
- **The printer is recursive** on nested data, which is fine for a reference but would need care for very deep structures.

## The self-interpreter

`self.luau` holds an interpreter for the language, written in the language, in `EVAL`. It takes a program as data, a pair `[tag args]` for each form, and an environment, and returns the value. The tags are listed at the top of `self.luau`.

The interpreter reuses the host's closures and pins. An object `lam` becomes a native `lam`, and an object `pin` becomes a native `pin`. So the machine's own errors and laziness apply to the object program, and the interpreter only has to work out the environment. This means the self-interpreter does not show that closures are unnecessary: it depends on them, which is the open question from before.

`self_run.luau` checks all 62 programs through the interpreter. The interpreted runs take about 60 to 100 times the steps of the direct runs, so the check takes around 9 seconds.

