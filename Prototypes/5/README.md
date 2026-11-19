# Prototype 5: a reference interpreter

A strict, sequential interpreter for a small functional language with native data: integers, cells (pairs), nil, closures and pins. It is the spec for later prototypes, so any other implementation should agree with it on the examples in `examples/`.

## Files

| Path | What it holds |
| --- | --- |
| `interpreter/vm.luau` | The machine, the printer, and the builders for expressions. |
| `interpreter/reader.luau` | The reader: text syntax to expressions. The syntax is described at the top of the file. |
| `examples/examples.luau` | 49 programs built with the builders, each with a fuel budget and its expected outcome. |
| `examples/text.luau` | 49 programs in the text syntax, plus 18 sources the reader must reject. |
| `examples/programs.luau` | 9 longer programs in the text syntax, using `letrec`: an accumulator, reverse, append, insertion sort, word counting, deep equality, a tree evaluator and gcd. |
| `self/self.luau` | The self-interpreter: an interpreter for the language, written in the language, with the quoting that feeds it. Functions are host closures. |
| `self/self_data.luau` | The closure-free self-interpreter, where a function is a cell. See the closure question below. |
| `run.luau` | Runs every example and reject, and reports pass or fail. |
| `self_run.luau` | Runs every example through the self-interpreter and checks it gives the same result. |
| `self_data_run.luau` | Runs every example through the closure-free interpreter, and shows the two probes where it differs. |
| `env_run.luau` | The environment experiment: a linked list against a skew binary random-access list, in the self-interpreter. |

## Running

Run from this directory.

| What | Command |
| --- | --- |
| The checks | `luau run.luau` |
| The self-interpreter checks | `luau self_run.luau` |
| The closure-free checks and probes | `luau self_data_run.luau` |
| The environment experiment | `luau env_run.luau` |
| The analyser | `luau-analyze interpreter/*.luau examples/*.luau self/*.luau run.luau self_run.luau self_data_run.luau` |
| The formatter | `luau-format interpreter/*.luau examples/*.luau self/*.luau run.luau self_run.luau self_data_run.luau` |

The runners exit with status 1 if any check fails.

## The language

- **Values:** integers, `nil`, cells, closures and pins. Lists are nested cells ending in `nil`.
- **Expressions:** `int`, `nilv`, `var` (by index), `lam` (no name), `app` (curried), `cell`, `head`, `tail`, `ite` (only the branch taken is evaluated), `pin`, `force`, and `prim` on integers (`add`, `sub`, `mul`, `div`, `mod`, `lt`, `eq`) or `kind`, which gives the kind of any value: 0 integer, 1 nil, 2 cell, 3 function, 4 pin. `(? x)` in the text syntax is shorthand for `(= (kind x) 1)`.
- **Division is floored.** `(div a b)` rounds down, not towards zero, and `(mod a b)` takes the sign of `b`, so `a = b * q + r` with `q = (div a b)` and `r = (mod a b)`. That is the rule of Luau's `//` and `%`, so a result can be checked against the host. Dividing by zero is an error.
- **Recursion:** `M.fix` is the strict fixed-point combinator. A recursive function is `app(fix, lam(lam(...)))`, and the outer binder, index 1 inside the inner body, refers to the function itself.
- **Local names:** `(let x e body)` binds `x` in `body` only, as sugar for applying a `lam`. It is not recursive.
- **Recursive functions:** `(letrec f (lam ...) body)` binds `f` to a function that can call itself. It is sugar for `let` with `fix`, so it costs nothing at run time: the programs in `examples/programs.luau` take the same number of steps with it as with `fix` written out.
- **Pins:** a pin is a suspended expression. Creating one does not run it. Forcing it runs it once, and later forces return the same value.

## Fuel and outcomes

Every step of the machine costs one unit of fuel. A run ends in one of three ways:

- `value`, with the result,
- `error`, with a message (a type error, an unbound name, forcing a pin inside itself),
- `out_of_fuel`, when the budget runs out.

Out of fuel is a result, not a hang, so a diverging program can be tested like any other.

## Decisions and limits

- **No host recursion.** Pending work sits on an explicit stack. The 10,000-element loop in the examples runs in one Luau call frame.
- **Integers are exact from -(2^53 - 1) to 2^53 - 1.** A result outside that range is an error (`add result is out of range`), and so is a literal outside it, which the reader rejects. The bound is 2^53 - 1, not 2^53, because a result at 2^53 may already have rounded. Division and remainder always stay in range, since `|a div b| <= |a|` and `|mod| < |b|`. Division is exact for every in-range operands: the quotient is corrected from the truncated quotient, not from `a - mod`, which can pass 2^53 and round.
- **No negative zero.** Every arithmetic result equal to zero is `0`, so `(* 0 -1)` prints as `0`, not `-0`.
- **Pins are memoised,** but the examples cannot see the difference except through step counts.
- **Variables are de Bruijn indices.** The machine never sees a name: `var 0` is the innermost binder, `var 1` the one outside it. The reader turns names into indices and rejects a name that is not bound, so the machine has no unbound-name errors from programs read from text. Names exist only in the reader and the surface syntax. The language has no symbol type, so a self-interpreter could not compare names anyway.
- **Expressions can be built two ways:** by the Lua builders in `vm.luau`, or read from the text syntax by `reader.luau`. Both give the same `Expr`, and the examples use each.
- **The printer is recursive** on nested data, which is fine for a reference but would need care for very deep structures.

## The self-interpreter

`self/self.luau` holds an interpreter for the language, written in the language, in `EVAL`. It takes a program as data, a pair `[tag args]` for each form, and an environment, and returns the value. The tags are listed at the top of the file.

The interpreter reuses the host's closures and pins. An object `lam` becomes a native `lam`, and an object `pin` becomes a native `pin`. So the machine's own errors and laziness apply to the object program, and the interpreter only has to work out the environment.

`self_run.luau` checks all 108 programs (the builder examples, the text examples and the longer programs) through the interpreter. The interpreted runs take about 60 to 100 times the steps of the direct runs, so the check takes around 9 seconds.

## The closure question

`self/self_data.luau` is the same interpreter with no object-level closures. A function is the cell `[1 [body env]]`, and `EVAL` applies it itself.

- It agrees with the direct machine on 97 of the 99 examples (the builder and text sets), with the two known differences below.
- It costs about 5 to 6 percent more steps than the host-closure version, and its `EVAL` is about 6 percent larger.
- It is not sound. A cell that has the shape of a function is applied as one, and `head` reads a function as an ordinary pair. `self_data_run.luau` shows both: applying the forged function `[1 [[0 [7 ~]] ~]]` gives 7 where the machine gives an error, and `head` of a function gives 1 where the machine gives an error.

**Conclusion:** the object language needs closures as a value kind. Making them data is cheap, but a data function cannot be told apart from a pair, and `kind` reports a data function as a cell, so it cannot tell them apart either. A native closure cannot be forged from object data, which is the only way to keep the machine's errors for function misuse. Closures stay. If functions are ever to be data, the language needs a function tag that object programs cannot construct, and that is a new primitive, which is no cheaper than keeping closures.

## The environment representation

`env_run.luau` compares two ways of keeping the self-interpreter's environment. The reference machine is unchanged, since this only affects how the self-interpreter stores bindings.

- **Linked list:** `[value rest]`. Adding a binding is one step. Reading index `n` walks `n` tails.
- **Skew binary random-access list:** a list of complete trees of sizes 1, 3, 7, and so on. Reading index `n` is logarithmic, but adding a binding takes more steps.

Both agree with the direct machine on all 99 programs. On a program nested to depth `d` that reads each binding once:

| depth | list steps | skew steps | skew / list |
| ---: | ---: | ---: | ---: |
| 4 | 2,225 | 2,859 | 1.28 |
| 8 | 5,201 | 6,510 | 1.25 |
| 16 | 12,977 | 14,501 | 1.12 |
| 32 | 35,825 | 31,836 | 0.89 |
| 64 | 110,705 | 69,187 | 0.62 |

The skew list only wins once a program has between 16 and 32 bindings in scope. The examples nest at most about three, so the linked list is the right choice for the spec. Leaving the environment as a list also means a Nock-style `/` (see below) would not help: it would only pay off with a balanced environment, which the examples don't need.

## Addresses instead of head and tail

Nock's `/` reaches a value by its position in a binary tree, which could replace `head` and `tail`. With list environments, the address of index `n` is `2^(n+2) - 2`, which passes the exact-integer limit of 2^53 at about 50 bindings. So addresses only make sense with a balanced environment, and the experiment above shows that is not worth it at the depths the examples use. `head` and `tail` stay.

