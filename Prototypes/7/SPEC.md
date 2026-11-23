# Prototype 7: the core specification

Status: draft for Phase 3. Every rule the reference interpreter needs is here. Where the plan left a choice open, the default the plan recommends is taken and listed under "Decisions taken" at the end.

The core is what a surface language compiles to. It has nine forms and thirteen primitives, and nothing else. Recursion, data structures, strings and effects are built on top of these, or are added later with a rule of their own.

## 1. Values

Every value is one of these kinds. The kind number is what the primitive `kind` returns.

| Kind | Name | What it is |
| ---: | --- | --- |
| 0 | integer | A signed whole number of any size: no upper or lower bound. Its exact value is kept whatever its length. |
| 1 | nil | The empty list. There is one nil. |
| 2 | cell | A pair `(a . b)`, where `a` and `b` are values. Lists are cells ending in nil. |
| 3 | function | A law, or a partial application of a law (a law with fewer arguments than its arity). |
| 4 | (unused) | Reserved: a pin in Prototypes 5 and 6, removed by decision 16. The other kinds keep their numbers. |
| 5 | con | A constructor: a tag (an integer from 0 up) and a payload value. |
| 6 | thunk | A delayed call: a function and its arguments, not yet run. |

The integer kind is arbitrary precision. It is a property of the VM, not of any host: an integer of a thousand digits is as much an integer as 3. The bound of ±(2^53 − 1) that Prototypes 5 and 6 had is a limit of the Luau host, whose numbers are doubles. It is not part of the design, and an implementation on a host with a different limit must not reintroduce it.

A **law** is a closed function: `law arity body`. It has an arity (a number from 1 up), and a body (a form). The examples name a law (`law inc 1 …`) only to read better: the name is not part of the law. A law has no free variables. Everything it uses is an argument, the law itself (`arg 0`), or a value it builds. Laws are values, so a law can be passed and returned, and a lifted lambda is a law with its free variables as extra arguments.

A **partial application** is a law with some arguments already given. Applying it to more arguments runs the law once it has its full arity. A law is `function` kind, and so is a partial application.

## 2. Frames

A law's body runs in a frame, a list of slots, numbered from 0:

- slot 0 is the law itself;
- slots 1 to `arity` are the arguments, in order;
- each `let` form pushes one slot. Slots are numbered from the first one pushed after the arguments.

A slot is fixed once it is pushed. The frame of a call is its own; a call does not see its caller's frame. A thunk holds the values of its call, not the frame it was made in.

## 3. Forms

There are nine forms. Each has a rule and an example. A form's evaluation is one step (section 6). The snippets in this section are the body of a law of arity 1 unless they say otherwise, so `arg 1` is the input.

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

**`con k e`** evaluates `e` and gives the constructor with tag `k` and that payload.

    con 0 (lit 5)                  gives Ok 5 for a sum whose tag 0 is Ok

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

Thirteen primitives, each written by a number (its tag) and a name. The tag is what a program uses in the `prim` form.

| Tag | Name | Arity | Rule |
| ---: | --- | ---: | --- |
| 0 | add | 2 | integers; the exact sum |
| 1 | sub | 2 | integers; the exact difference |
| 2 | mul | 2 | integers; the exact product |
| 3 | div | 2 | integers; the quotient, rounded down; the divisor must not be zero |
| 4 | mod | 2 | integers; the remainder with the sign of the divisor, so `a = b·div + mod`; the divisor must not be zero |
| 5 | lt | 2 | integers; 1 if the first is less than the second, else 0 |
| 6 | eq | 2 | integers; 1 if equal, else 0 |
| 7 | kind | 1 | any value; its kind number (section 1) |
| 8 | head | 1 | a cell; its first component. Not a cell: an error |
| 9 | tail | 1 | a cell; its second component. Not a cell: an error |
| 10 | tagof | 1 | a constructor; its tag, a number from 0 up. Any other value: -1 |
| 11 | payload | 1 | a constructor; its payload. Any other value: an error |
| 12 | cons | 2 | the cell `(a . b)` of its two arguments, evaluated in order (it was a form, `cell`, until decision 15; its tag was 14 until decision 16) |

Three rules about primitives:

- **There is no `Result`.** `div` and `mod` by zero, and `head` or `tail` of a non-cell, are errors of the whole run, not values. A program that must handle them tests first, with `kind` or `eq`. This is the rule that the Phase 1 measurements asked for: the checker paid for a `Result` at every division and every list access, and in the core those tests are one primitive each, with no wrapping.
- **Integers are never out of range.** Every integer result is exact, at any size, so there is no overflow outcome. An implementation whose host cannot hold a large integer represents it in another way (a bignum, a list of limbs), and does not fail or round. An implementation that rounds or stops on a large integer is not conformant.
- **Kind reads any value**, including a function and a thunk, so a program can always check what it has before it reads it.

## 5. Outcomes

A run gives one of three outcomes:

- `value v`: the program's result;
- `error m`: the run cannot continue, with a message `m` (a division by zero, a non-cell `head`, an unbound slot, a `force` of a non-thunk, and the like);
- `out_of_fuel`: the run used up its fuel.

An implementation may also end a run when it runs out of a resource of its own, such as the depth of nested evaluations the host can hold. That is not an outcome of the program: the spec does not define it, the reference never gives it, and a program that ends this way has no value, error or out-of-fuel result. The Go machine's limit is documented in `fast/README.md` (`host_limit`).

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

## 7. Shortcuts: memo and jets

An implementation may compute a call without running its body, in one of two ways: from a table of results it has already computed (a memo), or by a native routine for the law (a jet). A shortcut must give, for every input:

- the body's result, or the body's error, or `out_of_fuel` at the step where the body would stop;
- the body's fuel, exactly: a hit charges the fuel the call used when it was first computed, and a native routine declares the fuel the body uses, counting the entry (fuel-exact, decision 11). A shortcut that charges less is a change of the spec, not an optimisation.
- the body's answer on an input that makes the body fail: a shortcut that cannot answer exactly as the body does gives up, and the body runs.

So a run's outcome and its fuel are the same with the shortcuts as without them. Which calls get a shortcut, and how a table of results or a routine is keyed and chosen, are the implementation's business: the spec defines no key (decision 18). Phase 5 (jets) and Phase 7 (memo) measure what they save.

## 8. (Removed: the jets are in section 7, and the numbering of the rest is kept.)

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

    call (lit length) (prim cons (lit 1) (prim cons (lit 2) (prim cons (lit 3) (lit nil))))    value 3

**Division with a test.** Division by zero is an error, so the program tests the divisor first. The input is the cell `(a . b)`, and the result is `Ok (a / b)`, or `Err` when `b` is zero:

    law safediv 1
      if (prim eq (prim tail (arg 1)) (lit 0))
        (con 1 (lit nil))
        (con 0 (prim div (prim head (arg 1)) (prim tail (arg 1))))

    call (lit safediv) (prim cons (lit 6) (lit 3))       value Ok 2
    call (lit safediv) (prim cons (lit 6) (lit 0))       value Err nil

**Constructor dispatch.** A constructor's tag is read by `tagof` and its payload by `payload` (primitives 10 and 11, section 4), so a dispatch is an `if` on the tag. Here the input is `Ok 9` (tag 0):

    law unwrap 1
      if (prim eq (prim tagof (arg 1)) (lit 0)) (prim payload (arg 1)) (lit 0)

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
2. **Jet fuel is a declared formula.** A law whose fuel cannot be stated as one gets no jet (decision 11).
3. **Strings stay lists of integers** in the core. A byte kind waits for Phase 6.
4. *Superseded by decision 16.* **Pins are wrappers** with their own kind, read through `unpin`. A pin is transparent to nothing: it is a value whose identity is its content, which is what a memo key needs.
5. **Errors end the run** and are not values. The surface language adds `Result` on top, by testing before the primitive.
6. **Calls are strict** in their arguments. Laziness is only through `delay`.
7. **The step rule** is one step per form and one per law entry. Phase 3 writes the step counts of the examples into its tests, so a change to this rule is visible.
8. **Integers are unbounded.** The VM's integers have no size limit, and the ±(2^53 − 1) bound of Prototypes 5 and 6 is a limit of the Luau host (doubles), not of the VM. The reason: a bound in the VM would make the answer depend on the host. Consequence for Phase 3: the Luau reference needs a bignum representation for integers, and its tests must include values beyond 2^53.
9. **Constructor tags are read by primitives.** `tagof` and `payload` are primitives 12 and 13 (10 and 11 after decision 16), not forms. Phase 3 found this gap: Prototype 6 reads a constructor's tag with forms, but a `case` cannot read a tag for an open set of tags, so the core needs a way to get the tag as a number. Adding two primitives keeps the form count at eleven.
10. **A suspended expression is a thunk, kind 6.** Kind 4 was for pins (decision 16 removed them, and reserves the number). Prototype 5 reports a suspended expression as kind 4, and its example expects that; the core does not, so the example is superseded for the core. A thunk is not data (it has no binary form, and `pin` refuses it), so giving it the pin's kind would make `kind` unable to tell a stored value from an unevaluated call.
11. **Jets are fuel-exact.** Every jet declares a fuel formula equal to the fuel of the law it replaces, and there are no work-only jets. Fuel is therefore the same on every machine, with or without jets. A work-only jet would make steps and out-of-fuel depend on which jets are installed, and jets are the part of the design most likely to make a run depend on something other than the spec. Jets are pure, and a jet that cannot match its law's fuel is not a jet.
12. **Jets replace laws only; primitives stay primitives.** A primitive is already one step of native work, and a jet would add a law entry and its argument forms to every use, raising the fuel for no gain, so a primitive gets no jet. A jet is for a law built from several forms. Work that fuel does not count (for example, the encoding of a whole value, or a big integer's size) is a known gap, and it is closed by a spec change, not by a jet. A new primitive also needs a spec change, with its reason.
13. *Moved out of the spec by decision 18.* Compound values are hashed from their parts, so a memo key costs one hash per new node. The Go implementation keeps this, in `fast/README.md`.
14. *Moved out of the spec by decision 18.* Functions are memo keys: a law is closed, so its content decides what it does, and a partial application is a law and its arguments.
15. **`cell` is a primitive.** A cell is built by a primitive, `cons` (tag 14 when it was added; tag 12 after decision 16), and not by a form. The two are the same to the machine: each is one step, then its two arguments in order, so every step count is unchanged. A form that only builds a value is one more case in every reader and every machine, and `cons` sits beside `head` and `tail`, which read the same values. The forms go from eleven to ten, and the primitives from fourteen to fifteen (thirteen after decision 16). Form tag 19 is unused, so the other tags keep their values.

16. **Pins are removed.** A pin was a wrapper that interned a value by its content and had its own kind. Decision 13 hashes compound values from their parts, so the memo and the jets need no interning, and a program cannot observe a pin except through its kind (4) and its errors. The lowering of Prototypes 5 and 6 never made a pin primitive: their `pin` expression is a `delay` (decision 1). So the `pin` and `unpin` primitives go, the primitives go from fifteen to thirteen, and the three after them are renumbered (`tagof` 12 to 10, `payload` 13 to 11, `cons` 14 to 12). Kind 4 is reserved, so the other kinds keep their numbers, and the binary format's tag 7 (a pin) is reserved and refused. Every law that uses a renumbered primitive has a new content hash, so the jets are re-hashed; their fuel is unchanged, as every step count is.

17. **`case` is removed.** The form read a constructor by its tag, and gave the payload as the next slot. Nothing in the pipeline builds it: the lowering of Prototypes 5 and 6 reads constructors with `tagof` and `payload` (decision 9), and their matches are chains of tests, so a `case` appears only in hand-written examples. Keeping it cost a rule, a reader, a writer and a machine case. A jump table would save a few steps per match (about 3% of the checker's steps, measured), and it can come back as a spec change with that measurement as its reason. The forms go from ten to nine. Form tag 21 is reserved, and a reader refuses it. The `case` mentioned in decisions 9 and 15 is this form.

18. **Shortcuts are not part of the spec.** The content hash (once section 12.7) was the key of the memo and of the jet table, and the spec defined it only because they did. No result and no fuel depends on the hash: the rules that do are the fuel rules of section 7, which stay. So the hash, its SHA-256 definition and the law's name leave the spec, and `law` has an arity and a body. The Go implementation keeps the definition in `fast/README.md`, with its memo and its jets. The spec is shorter by a hash function and a section of keys.

## 12. Binary format

The binary format stores values and programs as bytes, for machines. It is the form the Go implementation (Phase 4) will read, so this section is the contract for both. It follows Prototype 5's format (`Prototypes/5/interpreter/binary.luau`), with the forms and kinds of this spec.

### 12.1 Header

Every string starts with one byte:

| Byte | Holds |
| ---: | --- |
| 1 | a value (section 1) |
| 2 | a program: a law of arity 1 (section 12.4) |

The bytes must be exactly one of these. Anything after the value or program is an error.

### 12.2 Magnitudes

A magnitude is an unsigned LEB128 number of any length: 7 bits per byte, least significant group first, with the top bit set on every byte but the last. The last byte is not zero unless it is the only byte, so every number has one encoding (zero is the single byte `00`). A reader refuses any other encoding of a number.

Magnitudes are how the format writes every whole number: integer magnitudes, tags, counts, arities and indices. Integer values have no fixed size.

Positions are the exception. A tag, index, count or arity is a position in a program, not an integer value, and a reader can only hold a position that its host can index. Every implementation accepts positions up to 2^53 − 1 at least, and refuses a larger one, with a message that says so. This is a limit on positions, not on integers: an integer value (a `lit` of a big integer, or a value in a list) has no size limit.

### 12.3 Values

A value is a prefix sequence of parts. Each part starts with a tag byte:

| Tag | Part | After the tag |
| ---: | --- | --- |
| 0 | nil | nothing |
| 1 | cell | the head, then the tail |
| 2 | integer, zero or positive | its magnitude |
| 3 | integer, negative | its magnitude, which is at least 1 |
| 4 | constructor | its tag (a magnitude), then its payload |
| 5 | law | its arity (a magnitude, at least 1), then its body (a form, section 12.4) |
| 6 | partial application | the law, then the number of arguments (a magnitude, at least 1 and less than the law's arity), then the arguments |
| 7 | (reserved) | nothing: a pin in Prototypes 5 and 6, removed by decision 16; a reader refuses it |

A thunk (kind 6 in section 1) has no binary form, and a writer refuses it. A reader refuses a law whose body is not a form of section 12.4, and a part with tag 7.

The integer tags are the only place a sign is written. Zero is always tag 2, so tag 3 with a zero magnitude is refused as negative zero.

Integers have no size limit (section 1), so a magnitude may be as long as the integer needs.

### 12.4 Forms and programs

A law is its arity, then its body. A body is a form, written with one tag byte per form:

| Tag | Form | After the tag |
| ---: | --- | --- |
| 16 (`10`) | `lit v` | the value `v`, as a value (section 12.3) |
| 17 (`11`) | `arg i` | the index `i`, a magnitude |
| 18 (`12`) | `call f e1 … en` | `n`, a magnitude (zero or more), then `f`, then `e1` to `en` |
| 19 (`13`) | not a form: `cell` is primitive 14 (section 4) | |
| 20 (`14`) | `con k e` | the tag `k`, a magnitude, then `e` |
| 21 (`15`) | not a form: `case` was removed (decision 17) | |
| 22 (`16`) | `if c t e` | `c`, then `t`, then `e` |
| 23 (`17`) | `let e b` | `e`, then `b` |
| 24 (`18`) | `delay (call f e1 … en)` | `n`, a magnitude, then `f`, then `e1` to `en`; the call is not a separate form, so it has no tag of its own |
| 25 (`19`) | `force e` | `e` |
| 26 (`1a`) | `prim op a1 … an` | the primitive's tag `op` (a magnitude, less than 13), then its arguments; the number of arguments is the primitive's arity (section 4), so it is not written |

Form tags are in their own range, 16 to 26 (19 and 21 are unused), and never appear as values, so a reader knows from its position whether it is reading a value or a form. A form's parts are read in the order of the table.

A **program** is header 2, then a law of arity 1 (its arity, which must be 1, then its body). A reader refuses a program whose arity is not 1.

Rules a reader enforces, beyond the encoding itself:

- A `delay` form's call has the arguments it declares, and nothing else.
- A `prim` tag is less than 13.
- A partial application has fewer arguments than its law's arity.

A reader does not check frame indices (`arg i` against the frame of its law). An index past the frame is an error of the run (section 5), as it would be for any program that is built in memory.

### 12.5 Examples

These are checked by the format's tests (`Prototypes/7/reference/format_run.luau`).

    the value 0                    01 02 00
    the value -1                   01 03 01
    the value nil                  01 00
    the list (1 2)                 01 01 02 01 01 02 02 00      (cell, 1, cell, 2, nil)
    the integer 2^53               01 02 80 80 80 80 80 80 80 10    (eight bytes: seven groups of 0 with the top bit set, then the group 16)
    the program "law inc 1 (prim add (arg 1) (lit 1))"
                                   02 01 1a 00 11 01 10 02 01

The last line reads: header 2; the arity 01; the form `prim` (1a); the operation `add` (00); the argument `arg 1` (11 01); the argument `lit 1` (10, then the value 1 as 02 01).

The tests compare these bytes with an independent writer, so the examples here are for reading and are not a second source.

### 12.6 Errors

A reader refuses, with a message that gives the reason:

- a header it does not expect;
- a tag it does not know, in a value or in a form;
- a magnitude that is not in its shortest form;
- negative zero;
- bytes that end before the value or program is complete;
- bytes after the value or program;
- a form with a missing part;
- a `prim` tag of 13 or more, a form tag that is unused (19 or 21), a partial application with too many arguments, and a program whose arity is not 1;
- a position past what the implementation can index (at least 2^53 − 1 in every implementation, section 12.2).

The reader and writer have no limit on the depth of a program: both keep their own stack, as the machine does (the Luau reference tests a program 20,000 forms deep).

A writer refuses a thunk, and any other value without a binary form.

## 13. Form count

The forms are `lit`, `arg`, `call`, `con`, `if`, `let`, `delay`, `force` and `prim`. That is nine, within the limit of twelve in Phase 2's exit test. The thirteen primitives are not forms: they are the table in section 4, so the form count does not grow when a primitive is added.
