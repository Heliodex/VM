# Prototype 7: the core specification

Status: draft for Phase 3. Every rule the reference interpreter needs is here. Where the plan left a choice open, the default the plan recommends is taken and listed under "Decisions taken" at the end.

The core is what a surface language compiles to. It has eleven forms and twelve primitives, and nothing else. Recursion, data structures, strings and effects are built on top of these, or are added later with a rule of their own.

## 1. Values

Every value is one of these kinds. The kind number is what the primitive `kind` returns.

| Kind | Name | What it is |
| ---: | --- | --- |
| 0 | integer | An integer in the range -(2^53 - 1) to 2^53 - 1. A result outside the range is an error. |
| 1 | nil | The empty list. There is one nil. |
| 2 | cell | A pair `(a . b)`, where `a` and `b` are values. Lists are cells ending in nil. |
| 3 | function | A law, or a partial application of a law (a law with fewer arguments than its arity). |
| 4 | pin | A value in normal form, held by its content hash. Equal pins are the same object. |
| 5 | con | A constructor: a tag (an integer from 0 up) and a payload value. |
| 6 | thunk | A delayed call: a function and its arguments, not yet run. |

A **law** is a closed function: `law name arity body`. It has a name (its content hash), an arity (a number from 1 up), and a body (a form). A law has no free variables. Everything it uses is an argument, the law itself (`arg 0`), or a value it builds. Laws are values, so a law can be passed and returned, and a lifted lambda is a law with its free variables as extra arguments.

A **partial application** is a law with some arguments already given. Applying it to more arguments runs the law once it has its full arity. A law is `function` kind, and so is a partial application.

## 2. Frames

A law's body runs in a frame, a list of slots, numbered from 0:

- slot 0 is the law itself;
- slots 1 to `arity` are the arguments, in order;
- each `let` form pushes one slot, and each `case` branch with a payload pushes one slot. Slots are numbered from the first one pushed after the arguments.

A slot is fixed once it is pushed. The frame of a call is its own; a call does not see its caller's frame. A thunk holds the values of its call, not the frame it was made in.

## 3. Forms

There are eleven forms. Each has a rule and an example. A form's evaluation is one step (section 6). The snippets in this section are the body of a law of arity 1 unless they say otherwise, so `arg 1` is the input.

**`lit v`** gives the value `v` (an integer, nil, a law, or any other value written into the program).

    lit 7                          gives 7

**`arg i`** gives slot `i` of the current frame. `arg 0` is the law itself, which is how a law calls itself.

    law id 1 (arg 1)                 call (lit id) (lit 5) gives 5

**`call f e1 … en`** evaluates `f`, then `e1` to `en` in order, all strictly. If `f` is a function of arity `a` and it has `k` arguments:

- `k` less than `a`: the result is a partial application with those arguments;
- `k` equal to `a`: the body of the law runs in a new frame (slot 0 is the law, slots 1 to `a` the arguments), and its value is the result;
- `k` greater than `a`: the first `a` arguments are applied, and the result is applied to the rest.

If `f` is not a function, the outcome is an error.

    call (lit inc) (lit 41)        with law inc 1 (prim add (arg 1) (lit 1)) gives 42

**`cell a b`** evaluates `a` then `b` and gives the cell `(a . b)`.

    cell (lit 1) (cell (lit 2) (lit nil))      gives the list (1 2)

**`con k e`** evaluates `e` and gives the constructor with tag `k` and that payload.

    con 0 (lit 5)                  gives Ok 5 for a sum whose tag 0 is Ok

**`case e { k1 → b1; …; kn → bn; else → d }`** evaluates `e`, which must be a constructor. If its tag is `ki`, the branch `bi` runs with the payload pushed as the next slot. If no tag matches, the `else` branch `d` runs with the constructor pushed as the next slot. A `case` with no `else` and no matching tag is an error.

    case (con 1 (lit 9)) { 0 → (lit 0); 1 → (arg 2); else → (lit 0) }    gives 9

**`if c t e`** evaluates `c`, which must be an integer. If it is not zero, `t` is the value; if it is zero, `e` is.

    if (lit 0) (lit 1) (lit 2)     gives 2

**`let e b`** evaluates `e`, pushes its value as the next slot, and evaluates `b` in the extended frame.

    let (lit 3) (prim add (arg 2) (arg 2))    gives 6, in a law of arity 1 (the let's slot is 2)

**`delay (call f e1 … en)`** evaluates `f` and `e1` to `en` (strictly, as a call would), and gives a thunk holding them. It does not run the call. The argument must be a `call` form, which is checked when the program is built.

    delay (call (lit inc) (lit 1))  gives a thunk (kind 6) of inc on 1; inc does not run yet

**`force e`** evaluates `e`, which must be a thunk. It runs the thunk's call, once: the result is stored in the thunk, and a later `force` of the same thunk gives the stored result without running the call again. If `e` is not a thunk, the outcome is an error.

    force (delay (call (lit inc) (lit 1)))      gives 2

**`prim op a1 … an`** applies a primitive (section 4) to the values of its arguments, evaluated in order. The number of arguments is the primitive's arity.

    prim add (lit 2) (lit 3)       gives 5

Every form has a fixed number of parts, so a program is checked when it is built: a form with the wrong number of parts is not a program.

## 4. Primitives

Twelve primitives, each written by a number (its tag) and a name. The tag is what a program uses in the `prim` form.

| Tag | Name | Arity | Rule |
| ---: | --- | ---: | --- |
| 0 | add | 2 | integers; the sum, which must be in range |
| 1 | sub | 2 | integers; the difference, which must be in range |
| 2 | mul | 2 | integers; the product, which must be in range |
| 3 | div | 2 | integers; the quotient, rounded down; the divisor must not be zero |
| 4 | mod | 2 | integers; the remainder with the sign of the divisor, so `a = b·div + mod`; the divisor must not be zero |
| 5 | lt | 2 | integers; 1 if the first is less than the second, else 0 |
| 6 | eq | 2 | integers; 1 if equal, else 0 |
| 7 | kind | 1 | any value; its kind number (section 1) |
| 8 | head | 1 | a cell; its first component. Not a cell: an error |
| 9 | tail | 1 | a cell; its second component. Not a cell: an error |
| 10 | pin | 1 | any value that is not a thunk; a pin holding it, interned by content hash. Pinning a pin gives the same pin |
| 11 | unpin | 1 | a pin; the value it holds. Not a pin: an error |

Three rules about primitives:

- **There is no `Result`.** `div` and `mod` by zero, and `head` or `tail` of a non-cell, are errors of the whole run, not values. A program that must handle them tests first, with `kind` or `eq`. This is the rule that the Phase 1 measurements asked for: the checker paid for a `Result` at every division and every list access, and in the core those tests are one primitive each, with no wrapping.
- **Overflow is an error.** An integer result outside -(2^53 - 1) to 2^53 - 1 ends the run.
- **Kind reads any value**, including a pin, a function and a thunk, so a program can always check what it has before it reads it.

## 5. Outcomes

A run gives one of three outcomes:

- `value v`: the program's result;
- `error m`: the run cannot continue, with a message `m` (a division by zero, a non-cell `head`, an unbound slot, a `force` of a non-thunk, an overflow, and the like);
- `out_of_fuel`: the run used up its fuel.

Errors are not caught by the core. A program that wants to recover tests first (section 4).

A **program** is a law of arity 1. `run(program, input, fuel)` applies the program to the input and gives the outcome. Out of fuel is a result, so a diverging program can be tested like any other.

## 6. Fuel

Fuel is the semantic step count, and it is part of the outcome, so it must be the same on every machine (Phase 4 checks this).

- Each form evaluated costs one step.
- Each law entry costs one step: a `call` that saturates a law, and a `force` that runs a thunk's call for the first time. A `call` that only builds a partial application is not a law entry.
- A `delay` costs its own form and the forms of its parts; the call it holds costs nothing until it is forced.
- A `force` of a thunk that has already run costs its own form and nothing else.

When the fuel is used up, the run stops with `out_of_fuel`. Fuel is checked before each step, so a run with fuel `n` takes at most `n` steps.

The step count of a run is its fuel used. A run's steps are the same whatever the order in which an implementation does its work, because evaluation order is fixed by the rules in section 3.

## 7. Memoisation

A call may be memoised, in the sense of a table from its key to its result. The key is the function's content hash and the hashes of its arguments.

- A call is memoised only if every argument is data: an integer, nil, a cell or constructor of data, or a pin. A call with a function, thunk or non-data argument is not memoised.
- A memo entry stores the call's result and the fuel the call used.
- A memo hit **charges the stored fuel**. It does no work. So the fuel of a run is the same with the memo as without it, and only the work done differs.

Memoisation changes no result and no fuel. Phase 7 measures what it saves.

## 8. Jets

A jet is a native implementation of a law, selected by the law's content hash. Its rules:

- It gives the same result as the law's body on every input. Phase 5 checks this on the test suite.
- It declares its fuel as a formula in its own definition, which must equal the fuel of the law's body on every input the suite covers. A jet whose fuel cannot be stated this way is marked **work only**: its results are checked, but its fuel is not.
- A jet never changes an outcome: an input that gives an error or out-of-fuel on the body must give the same on the jet.

A jet is an optimisation of a law, not a change to the language.

## 9. Examples

Each example is a whole program and its expected outcome. Phase 3 runs them. An example written as an expression is the body of a law of arity 1, so `arg 1` is its input. The constructor tags follow one convention used only in examples: tag 0 is success (`Ok`), tag 1 is failure (`Err`).

**Increment.** `inc` is a law of arity 1 that adds one to its argument:

    law inc 1 (prim add (arg 1) (lit 1))

    call (lit inc) (lit 41)                 value 42

**Length, with self-reference.** `length` is a law of arity 1 over a list. It calls itself with `arg 0`, so no fixed-point combinator is needed:

    law length 1
      if (prim eq (prim kind (arg 1)) (lit 1))
        (lit 0)
        (prim add (lit 1) (call (arg 0) (prim tail (arg 1))))

    call (lit length) (cell (lit 1) (cell (lit 2) (cell (lit 3) (lit nil))))    value 3

**Division with a test.** Division by zero is an error, so the program tests the divisor first. The input is the cell `(a . b)`, and the result is `Ok (a / b)`, or `Err` when `b` is zero:

    law safediv 1
      if (prim eq (prim tail (arg 1)) (lit 0))
        (con 1 (lit nil))
        (con 0 (prim div (prim head (arg 1)) (prim tail (arg 1))))

    call (lit safediv) (cell (lit 6) (lit 3))       value Ok 2
    call (lit safediv) (cell (lit 6) (lit 0))       value Err nil

**Constructor dispatch.** A `case` on a constructor gives its payload as the next slot. Here the input is `Ok 9` (tag 0):

    law unwrap 1
      case (arg 1) { 0 → (arg 2); 1 → (lit 0); else → (lit 0) }

    call (lit unwrap) (con 0 (lit 9))               value 9

**Laziness.** A thunk is made once and forced twice. The second force gives the stored result:

    let (delay (call (lit inc) (lit 1)))
      prim add (force (arg 2)) (force (arg 2))      value 4, and the call of inc runs once

**An error.** Division by zero ends the run:

    prim div (lit 1) (lit 0)                         error: division by zero

**Out of fuel.** A law that calls itself forever runs out of fuel:

    law loop 1 (call (arg 0) (arg 1))

    call (lit loop) (lit 0)                          out_of_fuel

## 10. What the core does not have

These are left out on purpose, and each one has a place in a later phase:

- **`fix`.** Recursion is `arg 0`. The Phase 1 measurement found the fixed-point combinator to be about 9% of the checker's steps; this removes it.
- **Closures that capture.** A law is closed. A lifted lambda takes its free variables as arguments.
- **Result, and `?`.** Errors are outcomes (section 4). Early return belongs to the surface language.
- **Strings as a kind.** A string is a list of integers, as in the L2 surface. A byte kind is a Phase 6 question, decided by measurement.
- **Effects.** The core is pure. The driver that runs a program is outside it.
- **Lists as a form.** A list is cells. The core has no list form, so list operations are laws over `head`, `tail` and `kind`, and they are the first candidates for jets.

## 11. Decisions taken

These are the defaults this spec takes. Each can be changed, and a change is recorded here with its reason.

1. **Laziness is explicit.** `delay` and `force` are forms, so the cost of each thunk is in the fuel. The alternative (lazy by default) would hide that cost.
2. **Jet fuel is a declared formula** (option A in the plan). A jet that cannot state one is "work only".
3. **Strings stay lists of integers** in the core. A byte kind waits for Phase 6.
4. **Pins are wrappers** with their own kind, read through `unpin`. A pin is transparent to nothing: it is a value whose identity is its content, which is what a memo key needs.
5. **Errors end the run** and are not values. The surface language adds `Result` on top, by testing before the primitive.
6. **Calls are strict** in their arguments. Laziness is only through `delay`.
7. **The step rule** is one step per form and one per law entry. Phase 3 writes the step counts of the examples into its tests, so a change to this rule is visible.

## 12. Form count

The forms are `lit`, `arg`, `call`, `cell`, `con`, `case`, `if`, `let`, `delay`, `force` and `prim`. That is eleven, within the limit of twelve in Phase 2's exit test. The twelve primitives are not forms: they are the table in section 4, so the form count does not grow when a primitive is added.
