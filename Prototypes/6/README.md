# Prototype 5: a reference interpreter

A strict, sequential interpreter for a small functional language with native data: integers, cells (pairs), nil, closures and pins. It is the spec for later prototypes, so any other implementation should agree with it on the examples in `examples/`.

## Languages

The bootstrap: the L1 reader is also written in L1, in `L1/programs/boot/`. Three stages, each a program file, are joined by `read.prog`: `tokenize.prog` turns source bytes into tokens, `parse.prog` builds the syntax tree, and `compile.prog` gives the quoted form of the expression. `read.prog` takes `[source [names values]]`: the source as a list of bytes, and the names and quoted values of the imports its program uses, bound as `parseWith` binds them. It gives the same quoted program that `Code.toValue` gives for the Luau reader. The fixed point holds: the L1 reader compiled by the Luau reader reads its own stages and itself, and the quoted results are the same as those of the Luau reader (`boot_run.luau` checks this and then runs the L1 reader that stage 0 compiled on every source). `boot_run.luau` checks this on every example, every reject, and the program sections of every program file that imports nothing, including the three stage sources, so the L1 reader reads its own code. A refusal is a value, `[1 message]`, with a message but no line number. A success is `[0 quoted]`. The L1 reader agrees with the Luau reader on which sources it refuses, and the message is checked by the stage tests.

The reader's language is **L1** (language 1). Its keyword for a function is `fn`; the machine's expression for one is still called `lam`, since it is the same node the machine has always run. Its files are in `L1/`: the reader, the printer, the program-file format, the L1 programs and the L1 self-interpreter. Its tests are in `L1/examples/` and `L1/programs/`. The machine, the data and binary formats, the lifecycle and the driver are in `interpreter/`. They work on the expressions every language compiles to, so a later language can reuse them and add its own folder beside `L1/`.

The second language is **L2** (language 2). It is typed, and it has the surface forms the reader of L1 does not: a built-in `Result` with `?` for early return, `match` on sums, `check` and `untyped` for values from untyped code, and pairs `(a . b)` distinct from lists `[a b]`. A type error is reported at its position, and every error in a program is reported, not only the first. Its specification is `L2/SPEC.md`, and it compiles to the same machine expressions L1 does. Division by zero, and `head` or `tail` of nil, give `Err` values that a program can handle. What still ends a run is integer overflow, running out of fuel, and a pin that forces itself. Its files are in `L2/`, and its program files are in `L2/programs/`, with the standard library in `L2/programs/lib/`.

## Files

| Path | What it holds |
| --- | --- |
| `interpreter/vm.luau` | The machine, the printer, and the builders for expressions. |
| `L1/reader.luau` | The reader: text syntax to expressions. The syntax is described at the top of the file. |
| `interpreter/code.luau` | A program as data: the tag table, and the conversion between an expression and its quoted value, checked on the way back. |
| `interpreter/data.luau` | The data format: values to text and back, for interchange. Separate from the reader. See "The data format" below. |
| `interpreter/binary.luau` | The binary format: values and programs to bytes and back. See "The binary format" below. |
| `interpreter/lifecycle.luau` | Runs a program on an input, and checks the output. See "The lifecycle" below. |
| `L1/printer.luau` | Writes an expression as text in the reader's syntax. See "The printer" below. |
| `interpreter/driver.luau` | Runs a program that keeps a state between inputs. See "The driver" below. |
| `L1/program_file.luau` | Reads a program file: a header, the program, and its tests. See "Program files" below. |
| `L1/programs/*.prog` | Program files, each with its documentation, program and tests. |
| `programs_run.luau` | Runs every test in `L1/programs/`, and checks that malformed files are refused. Uses `lute`. |
| `examples/examples.luau` | 49 programs built with the builders, each with a fuel budget and its expected outcome. |
| `L1/examples/text.luau` | 49 programs in the text syntax, plus 18 sources the reader must reject. |
| `L1/examples/programs.luau` | 9 longer programs in the text syntax, using `letrec`: an accumulator, reverse, append, insertion sort, word counting, deep equality, a tree evaluator and gcd. |
| `L1/self/self.luau` | The self-interpreter: an interpreter for the language, written in the language, with the quoting that feeds it. Functions are host closures. |
| `L1/self/self_data.luau` | The closure-free self-interpreter, where a function is a cell. See the closure question below. |
| `run.luau` | Runs every example and reject, and reports pass or fail. |
| `self_run.luau` | Runs every example through the self-interpreter and checks it gives the same result. |
| `self_data_run.luau` | Runs every example through the closure-free interpreter, and shows the two probes where it differs. |
| `env_run.luau` | The environment experiment: a linked list against a skew binary random-access list, in the self-interpreter. |
| `data_run.luau` | Checks the data format: written texts, rejected texts, refused functions and pins, and a round trip for every example that gives a value. |
| `binary_run.luau` | Checks the binary format: exact bytes, refused bytes, and a round trip for every example value and program. |
| `lifecycle_run.luau` | Checks the lifecycle: programs applied to inputs, the outcomes, and the same runs through the binary format. |
| `printer_run.luau` | Checks the printer: the text for given programs, the refusal of an unbound variable, and a round trip for every example program. |
| `driver_run.luau` | Checks the driver: sessions that keep a state, each way a step can end a session, and the same through bytes. |
| `L2/SPEC.md` | The specification of L2: syntax, layout, the machine's forms it compiles to, and the types. |
| `L2/lexer.luau`, `L2/parser.luau` | The L2 reader: text to a surface tree, with positions. |
| `L2/checker.luau` | The type checker: Hindley–Milner inference with `Dyn`, which gives each `check` its test. |
| `L2/desugar.luau` | Compiles a checked surface tree to machine expressions. Early return and the checks are compiled here. |
| `L2/l2.luau` | Compiles an L2 program file: the imports, the checks, and the program. |
| `L2/programfile.luau` | Reads an L2 program file. Tests may span lines. |
| `L2/programs/*.l2`, `L2/programs/lib/*.l2` | L2 program files, and the L2 standard library. |
| `l2_run.luau` | Runs every L2 program file and its tests, and checks that malformed programs are refused. |
| `checker_run.luau` | Checks the type checker: inferred types, the type errors, and `check` and `untyped` on untyped values. |
| `L2/programs/boot/lex.l2` | The L2 tokenizer, written in L2: the first stage of the L2 compiler in L2. |
| `L2/programs/boot/layout.l2` | The L2 layout layer in L2: the indented source to the bracketed source. It is the variant the bootstrapped build uses (difference lists, linear in the lines). |
| `L2/programs/boot/desugar.l2` | The L2 desugarer in L2: the stage after the checker that gives the machine's expressions. It is checked against `desugar.luau` by `Prototypes/7/measure/desugar_run.luau`. |
| `L2/malformed.luau` | The malformed L2 programs, each with the reason it should be refused. `l2_run.luau` and the bootstrapped compiler's refusal runner (`Prototypes/7/measure/boot_refusals_run.luau`) both read it. |
| `lex_run.luau` | Checks the L2 tokenizer against the Luau lexer on every program file and a set of edge cases. |
| `L2/programs/boot/parse.l2` | The L2 parser, written in L2: stage 2 of the L2 compiler in L2. It reads the tokenizer's output. |
| `parse_run.luau` | Checks the L2 parser, run on the tokenizer's output, against the Luau parser on every L2 program file and a set of cases that reach each error. |
| `L2/programs/boot/types.l2` | The L2 checker in L2, with no mutation: the types, the state, unification, generalisation, and type inference for the core forms. It also gives the tests of the checks and of the input (request `InferT`), with the expected types numbered as the host checker numbers them. |
| `L2/programs/boot/desugar.l2` | The L2 desugarer, written in L2: the stage after the checker that gives the machine's expressions. It is checked against `desugar.luau` on the program files, the imports, the checks and the input boundary by `Prototypes/7/measure/desugar_run.luau`. |
| `infer_run.luau` | Checks the L2 checker against the Luau checker on the programs of every L2 program file, and a set of cases for each form and error. Type variables are renamed by where they first appear, so numbering does not matter. |

## Running

Run from this directory.

| What | Command |
| --- | --- |
| The checks | `luau run.luau` |
| The self-interpreter checks | `luau self_run.luau` |
| The closure-free checks and probes | `luau self_data_run.luau` |
| The environment experiment | `luau env_run.luau` |
| The data format checks | `luau data_run.luau` |
| The binary format checks | `luau binary_run.luau` |
| The lifecycle checks | `luau lifecycle_run.luau` |
| The printer checks | `luau printer_run.luau` |
| The driver checks | `luau driver_run.luau` |
| The L2 program checks | `lute run l2_run.luau` |
| The L2 checker checks | `lute run checker_run.luau` |
| The L2 tokenizer against the Luau lexer | `lute run lex_run.luau` |
| The L2 parser against the Luau parser | `lute run parse_run.luau` |
| The L2 checker against the Luau checker | `lute run infer_run.luau` |
| The program file checks | `lute run programs_run.luau` |
| The analyser | `luau-analyze interpreter/*.luau examples/*.luau self/*.luau run.luau self_run.luau self_data_run.luau` |
| The formatter | `luau-format interpreter/*.luau examples/*.luau self/*.luau run.luau self_run.luau self_data_run.luau` |

The runners exit with status 1 if any check fails.

## The language

- **Values:** integers, `nil`, cells, closures and pins. Lists are nested cells ending in `nil`.
- **Constructors:** `construct tag e` makes a constructor with a tag from 0 up and a payload, `tagof e` gives a constructor's tag or -1 for any other value, and `payload e` gives its payload (an error for any other value). A constructor is a value of kind 5. It has no text syntax in L1, and it is not data yet: a program that returns one is `not_data`.
- **Expressions:** `quote` (an integer, or nil, which is `nilv`), `var` (by index), `lam` (no name), `app` (curried), `cell`, `index` (which the text syntax writes as `head` and `tail`), `ite` (only the branch taken is evaluated), `pin`, `force`, and `prim` on integers (`add`, `sub`, `mul`, `div`, `mod`, `lt`, `eq`) or `kind`, which the text syntax writes as `+`, `-`, `*`, `/`, `%`, `<`, `=` and `@`, which the machine identifies by its tag from `interpreter/primitives.luau`; the table gives each primitive's tag, name, symbol and arity, and is the only place they are written, which gives the kind of any value: 0 integer, 1 nil, 2 cell, 3 function, 4 pin. `(? x)` in the text syntax is shorthand for `(= (@ x) 1)`.
- **Division is floored.** `(/ a b)` rounds down, not towards zero, and `(% a b)` takes the sign of `b`, so `a = b * q + r` with `q = (/ a b)` and `r = (% a b)`. That is the rule of Luau's `//` and `%`, so a result can be checked against the host. Dividing by zero is an error.
- **Recursion:** `M.fix` is the strict fixed-point combinator. A recursive function is `app(fix, lam(lam(...)))`, and the outer binder, index 1 inside the inner body, refers to the function itself.
- **Local names:** `(let x e body)` binds `x` in `body` only, as sugar for applying a `fn`. It is not recursive.
- **Recursive functions:** `(letrec f (fn ...) body)` binds `f` to a function that can call itself. It is sugar for `let` with `fix`, so it costs nothing at run time: the programs in `L1/examples/programs.luau` take the same number of steps with it as with `fix` written out.
- **Pairs:** `[a b]` is a cell. A bracket of three or more is right-nested, so `[a b c]` is `[a [b c]]`: the last item is the tail. A list ends in `~`, so `[1 2 3 ~]` is the list `(1 2 3)`, and `[1 2 3]` is the improper pair `(1 2 . 3)`. The printer writes cells in this shorthand.
- **Mutual recursion:** `(mutual ((f (fn ...)) (g (fn ...))) body)` binds several functions that can call each other. It is sugar in the reader, with no machine change: the group shares one fixed point, and each name is a call through it.
- **Errors:** there is one way to report a failure: a value. A program returns `[0 result]` on success and `[1 message]` on failure, and the caller checks the tag. This is how `programs/parse_int.prog` and `programs/even_b.prog` work, and the messages are checked as ordinary output. The convention is not enforced, so a program that returns `[1 x]` as data is indistinguishable from a failure. There is no `raise`: a run that cannot continue, such as taking `head` of a non-cell, ends as `error` with a message from the machine, and a program cannot end its own run with a message.
- **Strings:** `"abc"` reads as the list of its bytes, so `"abc"` is `(97 98 99)` and `""` is nil. The escapes are `\"`, `\\`, `\n`, `\t` and `\0`. A string holds bytes, so text outside ASCII is written as its bytes. The data format has no strings. A program file's test lines use the reader's language too, so `"abc"` works there as it does in a program.
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

## The data format

`interpreter/data.luau` is a separate format for values passed into and out of programs. It is not the program syntax, and it is never evaluated. The program reader is for writing programs by hand; this format is for data, so the two can change independently.

A value is a sequence of tokens separated by single spaces:

- `nil`, the nil value
- an integer in decimal, such as `0`, `-3` or `42`, within the exact range
- `cons h t`, a cell, with head `h` and tail `t`, each a value in turn

It is prefix notation, so a list is read in one pass: `(1 2 3)` is `cons 1 cons 2 cons 3 nil`. Both the writer and the reader walk cells with an explicit stack, so a long list does not nest the Luau call stack.

The form is canonical. The reader accepts only the text the writer produces: no leading zeros, no `-0`, no `+`, one space between tokens and none at the ends, and nothing after the value. So each value has exactly one text, and two values are equal exactly when their texts are.

Functions and pins have no written form. Writing one is an error, including when a cell holds one.

## The binary format

`interpreter/binary.luau` stores values and programs as bytes, for machines. It has three parts:

- a header byte: `1` for a data value, `2` for a program
- a prefix sequence of parts, each starting with a tag byte: `0` nil, `1` a cell (head, then tail), `2` a non-negative integer, `3` a negative integer
- an integer's magnitude, as unsigned LEB128: 7 bits per byte, the top bit set on every byte but the last, and the last byte never zero unless it is the only one

A program is the quoted form from `interpreter/code.luau`, so the tag table is shared with the self-interpreter. Decoding a program checks its shape, so a program from outside cannot reach a form the machine does not have.

The decoder is strict: it refuses an unknown header or tag, a number that is not in its shortest form, a negative zero, an integer past the limit, bytes that stop early, and bytes after the value. The writer and reader both walk cells with an explicit stack. The bytes are held in a Luau `buffer`: the writer grows it by doubling, and the reader reads it with `readu8`, which checks the bounds.

## The lifecycle

A program is a function. The host applies it to an input value, and the result is the output. A run is determined by the program, the input and the fuel, so it can be repeated and stored.

The output must be data. The output check forces every pin inside it, and walks cells, and it is written in the language, so forcing costs fuel like any other step. A pin that never finishes therefore ends the run as `out_of_fuel`, the same as a loop, and a pin that errors ends it as `error`.

The outcomes are:

- `value`, with the output
- `error`, with a message
- `out_of_fuel`
- `not_data`, when the output holds a function, in a cell or at the top

`Lifecycle.runBytes` runs the same thing from bytes: the program and the input are decoded, and the output is encoded. A program or input that does not decode is an `error`, and the program is not run.

Programs that keep a state between inputs are run by the driver, described below. Each step is a lifecycle run.

## The printer

`L1/printer.luau` writes an expression as text in the reader's syntax, so that reading the text gives back the same expression. The machine has no names, so the printer invents them: a `lam` is named by its depth, so the outermost is `v0`, the next `v1`, and so on. A variable with index `i` under `d` binders prints as the name of the binder at depth `d - 1 - i`. A variable with no binder around it cannot be written, so the printer refuses it.

A chain of applications prints flat, `(f a b)`, which the reader reads back as `((f a) b)`.

The printer's output is canonical for a given expression, so printing, reading and printing again gives the same text. `printer_run.luau` checks this for every example program.

## The driver

`interpreter/driver.luau` runs a program that keeps a state between inputs. The program is a step: a function of a pair `[state input]`, which gives a pair `[state' output]`. The driver carries the state from one step to the next. Each step is a lifecycle run, so its output is checked as data, and it has its own fuel.

A session ends at the first step that does not give a value. It reports which input it failed on, and the state from before that step. A step that errors, runs out of fuel, returns a function, or returns something that is not a pair ends the session.

`Driver.stepBytes` runs one step from bytes, with the program and the state as bytes, so a state can be stored between calls.

## Program files

A program file keeps a program with its documentation, the programs it uses, and its tests, in one file with four sections separated by lines that hold only `---`: header, imports, program, tests.

```
Header documentation, for people, which is not read.
---
double = double.prog
---
(fn x (double (+ x 1)))
---
0 => 2 fuel 1000
41 => 84 fuel 1000
~ => error fuel 1000
```

The imports section is empty in a file that uses none. L2 program files use the same four sections, but their tests may span lines, and their functions break before their bodies; see `L2/SPEC.md`. Each line is `name = file`, and it binds `name`, inside the program, to the program of that file. The file is a path from the top of the `L1/programs/` folder, so `double.prog` is at the top, `lib/triple.prog` is in `lib`, and the same path means the same file from any importing file. A path that climbs above `L1/programs/` with `..` is an error. The runner also finds program files in the folders under `L1/programs/`, and runs their tests. An imported program is closed, so it cannot use the importing file's names. An import can itself import, but a cycle is an error, and so is an import that cannot be found. Imports are looked up through a resolver, so the parser never reads files itself.

The program section is read by `reader.luau`, with the imported names bound around it. There is no new program syntax. Each test line is an input, then `=>`, then an output, then `fuel` and a number of steps. Inputs and outputs are written in the reader's language, and each is evaluated to a value before the test runs, so `[1 ~]`, `(list 1 2)` and `"ab"` are all valid. The names of the file's imports are in scope for them. An input may be a function, such as `(fn x (+ x 1))`, since it is only given to the program; an output must be data, since functions cannot be compared, so a function there is refused. An output may also be one of `error`, `out_of_fuel` or `not_data`, which are the outcomes of a run. Blank lines in the test section are skipped, and a file needs at least one test.

Each test runs through the lifecycle, so its output is checked as data. `programs_run.luau` runs the tests in `L1/programs/`, and checks that malformed files are refused with the right reason. It uses `lute`, because this Luau build cannot read files; the file reading is `@lute/fs`.

## The self-interpreter

`L1/self/self.luau` holds an interpreter for the language, written in the language, in `EVAL`. It takes a program as data, a pair `[tag args]` for each form, and an environment, and returns the value. The tags are listed at the top of `interpreter/code.luau`, which quotes programs for it.

The interpreter reuses the host's closures and pins. An object `lam` becomes a native `lam`, and an object `pin` becomes a native `pin`. So the machine's own errors and laziness apply to the object program, and the interpreter only has to work out the environment.

`self_run.luau` checks all 108 programs (the builder examples, the text examples and the longer programs) through the interpreter. The interpreted runs take about 60 to 100 times the steps of the direct runs, so the check takes around 9 seconds.

## The closure question

`L1/self/self_data.luau` is the same interpreter with no object-level closures. A function is the cell `[1 [body env]]`, and `EVAL` applies it itself.

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

Nock's `/` reaches a value by its position in a binary tree, which could replace `head` and `tail`. With list environments, the address of index `n` is `2^(n+2) - 2`, which passes the exact-integer limit of 2^53 at about 50 bindings. So addresses only make sense with a balanced environment, and the experiment above shows that is not worth it at the depths the examples use. That note is about variable lookup. For data, `head` and `tail` stay as the text syntax, and the machine has one `index` expression for them: an address n from 2 up, whose binary digits after the leading 1 are the steps, with 0 for `head` and 1 for `tail`. The reader joins a `head` or `tail` of an index into one index, so `(head (head e))` is `index 4`.

