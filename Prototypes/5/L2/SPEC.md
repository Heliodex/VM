# L2: specification draft

Status: draft. Every question in the draft is decided; section 14 records them.

L2 is the next language on the machine in `interpreter/`. It keeps what L1 learned, changes the surface syntax, and adds tagged values. The reference implementation is written in Luau. L2 is bootstrapped in L2 only after its surface is stable.

## 1. Goals

- Easy to parse: one token of lookahead, no precedence table beyond a few operators, no layout rules.
- Every value is tagged, so an operation on the wrong kind of value is a clear error.
- Small core. Everything else is a library function.
- Positions (line and column) are kept through every stage, so errors point at source.
- Programs and results are data, as in L1, so the existing binary and printed formats keep working.

Non-goals for now: a module system beyond imports, effects, a foreign-function interface, and concurrency.

## 2. Lexical structure

Tokens, separated by whitespace or by delimiters:

- Integers: optional `-`, then digits. Range as in L1, from -(2^53 - 1) to 2^53 - 1.
- Strings: `"..."` with the escapes `\"`, `\\`, `\n`, `\t`, `\0`. A string is a list of bytes (see section 5).
- Symbols (names and operators): a maximal run of characters that are not whitespace, `(`, `)`, `[`, `]`, `{`, `}`, `"`, or `;`. A symbol cannot start with a digit.
- Comments: `;` to the end of the line.
- Delimiters: `(`, `)`, `[`, `]`, `{`, `}`.

## 3. Syntax

### 3.1 Expressions

```
expr   ::= app
         | app "?"               early return on a failure (section 9.2)
app    ::= atom+                application, curried: f a b is (f a) b
         | "fn" params expr      function (section 4)
         | "let" name "=" expr "in" expr
         | "letrec" name "=" expr "in" expr    (recursive; section 12)
         | "mutual" "(" binding+ ")" "in" expr    (section 12)
         | "if" expr expr expr   branch on an integer: nonzero is true
         | "match" expr "{" arm+ "}"    (section 9.3; arms are multi-line, section 12)
atom   ::= integer | string | name | "~" | list | pair | "(" expr ")"
list   ::= "[" expr* "]"        a proper list
pair   ::= "(" expr "." expr ")"
params ::= name | "(" name+ ")"
```

`?` ends an application, so `parse s?` is `(parse s)?`, and it applies to the whole call on its left. To apply `?` to an argument, wrap it in parentheses: `g (parse s)?`. `?` appears at most once at the end of an application, so `f x? y` and `e??` are syntax errors. `?` is not an atom.

The grammar needs one token of lookahead: `(` starts a pair if the token after the first expression is `.`, and a group otherwise. The parser decides at the closing `)` or `.` after its first expression, so a group and a pair share one prefix. Implementations may use a small backtrack buffer.

### 3.2 Application

Application is juxtaposition: `f x y` is `(f x) y`. An atom is any single expression that can stand alone without a space-separated argument. A list, a pair, a string, a number, a name, `~`, and a parenthesised expression are atoms. `fn`, `let`, `if` and `match` are not atoms, so `f fn x x` is an error. Write `f (fn x x)`.

### 3.3 Operators

Operators are ordinary names, so `+ 1 2` is application of `+`. Infix forms `a + b` are not part of this draft; they can be added later as sugar with a fixed precedence table. **Open:** whether to add infix sugar for the primitives.

### 3.4 Names

Names are symbols that are not reserved (section 3.5). Names are lexically scoped and must be bound before use. Shadowing is allowed in a nested scope.

### 3.5 Reserved words

`fn`, `let`, `in`, `if`, `match`, `~`, and the primitives' symbols, listed in section 6. `in` is a reserved word because `let` uses it.

## 4. Functions

`fn x body` is a function of one name. `fn (x y) body` is sugar for `fn x (fn y body)`. A function with no parameters is an error. Application is curried, so partial application gives a function.

## 5. Values

Every value has a kind, which `@` reports (section 6). The kinds are:

| Kind | Value                                     |
|------|-------------------------------------------|
| 0    | Int: an integer in range                  |
| 1    | Nil: the empty list, written `~`          |
| 2    | Pair: a cell with a head and a tail       |
| 3    | Fn: a function (closure)                  |
| 4    | Pin: a suspended expression (section 7)   |
| 5    | Con: a constructor, a tag and a payload (section 8) |

A string is a list of Int values, each from 0 to 255, so `"ab"` is `[97 98]`. nil is `~`.

A constructor is written by its name, applied to its payload: `Ok 5`, `Err "x"`, and `None` for a constructor with no payload. The printer writes it the same way, so the text reads back to the same value. Its data form is a tag and a payload. In the data text it is `con TAG PAYLOAD`, as in `con 0 5`, and in the binary format it is tag byte 4 followed by the tag and the payload. The data text uses the number, since it is interchange and not surface syntax, and `(0 . 5)` would read as an ordinary pair. Only the surface printer writes names.

A list `[a b c]` is the pair chain `(a . (b . (c . ~)))`. A pair `(a . b)` is one pair cell, which is not a list unless `b` is a list. A list's items are whole expressions, so a pair inside a list needs parentheses: `[1 (2 . 3)]` is the list of 1 and the pair `(2 . 3)`. A dot inside brackets is a syntax error, so `[1 2 . 3]` is refused. An improper list is written as nested pairs, `(1 . (2 . 3))`. The printer writes a list with brackets and a pair with a dot, so the two forms never print the same way.

## 6. Primitives

Primitives are the functions the machine provides. They are written as names, with the symbols from the table in `interpreter/primitives.luau`: `+ - * / % < = @`. Their full names are `add sub mul div mod lt eq kind`. Primitives take values with their tags checked by the surface layer (section 8). The raw opcodes take untagged values.

`@` (kind) returns the tag of a value as an integer, using the same numbers as L1: 0 Int, 1 Nil, 2 Pair, 3 Fn, 4 Pin.

## 7. Pins and fix

`pin e` suspends `e`. `force p` runs a suspended expression. `fix f` gives the fixed point of a function, as in L1. These are the only operations on suspended expressions.

## 8. Tagged values and the layers

Constructors are tagged in the machine. Integers, nil, pairs, functions and pins keep their representations, and their kinds are as in L1. A constructor is a value of kind 5, with a tag and a payload. An integer costs nothing extra, and a constructor cannot be mistaken for a pair.

The machine has three expressions for constructors:

- `construct tag e`: a constructor with the given tag, from 0 up, and the value of `e` as its payload.
- `tagof e`: the tag of a constructor, or -1 for any other value. It never fails, so it is the test in a `match`.
- `payload e`: the payload of a constructor. It is an error for any other value, so it is only used after a `tagof` test.

The raw opcodes and the machine's kind checks are as before. The surface language uses these expressions directly, so no untagging layer is needed.

A constructor is not data until the data form in section 5 is implemented, so a program that returns one is `not_data` for now.

## 9. Results and errors

**Decided** (see `L2/RESULTS.md`). The L1 convention `[0 value]` and `[1 message]`, applied by hand, becomes the built-in sum `Result`. The candidates the memo weighed were:

- Tagged sum types with `match`, as in OCaml and Rust enums.
- A `?` operator that returns early on a failure, as in Rust.
- Exceptions with `try`, which the machine would need to support.

The comparison and recommendation are in `L2/RESULTS.md`: a tagged sum type `Ok v | Err e` with `match`, `?` as sugar for early return, and no effects or `try` in the first version.

Runtime errors from the machine (a wrong-kind `head`, a divide by zero) end the run as `error` with a message, as in L1.

### 9.1 Sums

A sum type has constructors, each with one payload. The first version has one built-in sum, `Result`:

```
Ok v      a success carrying v
Err e     a failure carrying e
```

Constructors are tagged values (section 8), so `kind` and `match` can tell them apart. A sum is not a list or a pair, and it prints as `Ok v` or `Err e`.

### 9.2 Early return

`e?`, where `e` is an application, evaluates `e`. If it is `Ok v`, the expression is `v`. If it is `Err e`, the whole enclosing function returns `Err e`. The reader hoists `e?` into a `let` in the same function, so it works anywhere an expression can appear. This is sound because L2 is pure: moving an evaluation earlier changes only which error is reported first, never a result. The payload types must match: a function that uses `?` on `Err e` must return `Err` with a compatible payload.

### 9.3 Match

`match e { pattern -> body ... }` evaluates `e`, tests the constructor of its value against each arm in order, and evaluates the body of the first arm that matches, with the pattern's variables bound.

Patterns in the first version:

- A constructor with a variable payload: `Ok v`, `Err e`.
- A constructor with a wildcard payload: `Ok _`, `Err _`.
- A wildcard: `_`, matching anything.

Nested patterns are not in the first version. A nested pattern can be written as nested `match` expressions.

Arms are lazy: only the body of the arm that matches is evaluated. The compiler checks that the arms cover every constructor of the scrutinee's type, or that a wildcard arm is present, and reports an error otherwise.

### 9.4 The core primitive

The machine's dispatch is two expressions, `tagof` and `payload` (section 8). A `match` tests `tagof` against each constructor's tag, and binds `payload` in the arm that matches. `match`, `?` and the constructors are built on them by the reader. A tag test is one step, with no closure per arm.

## 10. Machine changes

The machine changes made for L2, each in its own commit:

- Nil is `quote` of nil, so there is no nil expression.
- `head` and `tail` are one `index` expression, an address from 2 up.
- Constructors: a value kind 5 with a tag and a payload, and the expressions `construct`, `tagof` and `payload`.

Early return needs no machine change: `?` is a rewrite (section 9.2). The expressions that L1 already has stay: `quote`, `var`, `lam`, `pin`, `cell`, `index`, `force`, `if`, `apply`, `prim`, and the three constructor expressions.

## 11. Compilation and tests

- Parse to a syntax tree with positions.
- Desugar: `fn (x y)` to nested `lam`, infix (if added) to primitives, `let` to an application of `lam`, `letrec`-style recursion to `fix` as in L1.
- Compile to the machine's `Expr`.
- Tests: L1 programs ported to L2, with the same expected results, run through the same program-file format. Each port must give the same result as its L1 original.

## 12. Layout and binding rules

These rules are decided for the first version.

- **Newlines** are whitespace, except inside a `match` block, where a newline ends an arm.
- **Arms** are `pattern -> body`. A body ends at the end of its line. To continue a body onto the next line, wrap it in parentheses, so the parser never needs a layout rule.
- **Indentation** has no meaning. Indentation-based syntax is deferred, and it can be added to the lexer later without changing the grammar.
- **`let`** is non-recursive. A recursive function is written with **`letrec`**, which is `fix` as in L1, and a group of functions that call each other is one **`mutual`** form.

Example:

```
describe r = match r {
  Ok v -> v
  Err e -> (
    let n = 0 in n
  )
}
```

## 13. Types (first version)

The first version has a small static type system for surface programs. Quoted and binary forms are untyped, as in L1. The checker runs on surface syntax, before compilation, and it is not part of the machine.

### 13.1 Types

```
t ::= Int                 an integer
    | Nil                 the empty list, ~
    | (t . t)             a pair
    | t -> t              a function, curried
    | Pin t               a suspended value (section 7)
    | a                   a type variable
    | Name t*             a declared sum, such as Result t e
    | Dyn                 a value from untyped code (13.4)
```

A list of `t` has type `[t]`, a built-in recursive type. Its values are the pair chains of section 5, so `[t]` is `(t . [t])` or `Nil`. A list literal `[a b c]` has type `[t]` when each item has type `t`.

### 13.2 Inference

Types are inferred with Hindley–Milner: unification, with let-polymorphism for `let` and `letrec` bindings. A function's type is generalised at its `let` or `letrec`, so `fn x x` is `a -> a` and can be used at two types.

Recursive functions (`letrec`) are checked monomorphically within their own body, as usual for HM, and generalised afterwards. `mutual` groups are checked together and generalised together.

### 13.3 Primitives and forms

- `+ - * / %` have type `Int -> Int -> Int`.
- `< =` have type `Int -> Int -> Int`, since the machine returns 0 or 1.
- `@` has type `a -> Int`, the kind of any value.
- `head` and `tail` have type `(a . b) -> a` and `(a . b) -> b`. The address form (`index`) is typed by its steps.
- `if c t e` needs `c : Int`, and `t` and `e` must have the same type.
- `pin e` has type `Pin t` when `e : t`, and `force` has type `Pin t -> t`.
- `fix` has type `(a -> a) -> a`.

### 13.4 Sums and constructors

A sum is declared once, with its constructors and their payload types:

```
type Result a e = Ok a | Err e
```

Each constructor has a tag, from 0 up, by declaration order, so `Ok` is 0 and `Err` is 1.

A constructor carries exactly one payload value. Two rules follow from that:

- **No payload.** A constructor declared without a type has payload `~` (nil), and is written by its name alone. For example, `type Option a = None | Some a` gives `None` payload `~` and tag 0, and `Some a` tag 1.
- **Several fields.** A constructor with several values takes one payload that is a pair, so `Point (1 . 2)` is a constructor whose payload is the pair. A tuple type is not needed, and the machine keeps one payload per constructor. `Ok v` has type `Result a e` when `v : a`. A `match` on a sum must cover every constructor, or have a wildcard arm (section 9.3). The arms' bodies must have the same type.

The result of `?` on `Result a e` is `a`, and the enclosing function must return `Result b e`, with the same `e`.

### 13.5 Untyped code and Dyn

A quoted program, or a program decoded from binary, is untyped. Evaluating it gives a value of type `Dyn`.

- Inference inserts the check automatically, with no annotation, wherever a `Dyn` value meets a specific type. A `Dyn` value used where a specific type is needed passes a run-time check: an `Int` must be an integer, a pair must be a pair, and a constructor must have the declared tag. A failed check is an error, as a machine failure is.
- A typed value passed into untyped code is not checked, and it is still a valid value of its type.

So a program can run untyped code, and the types it has are kept at the boundary by a check that is part of the surface language's compiled form, not the machine.

### 13.5.1 Tags at run time

Only constructors carry a tag of their own. Every other value's kind comes from its representation, so the static types need no extra tag at run time.

| Type | Kind | Extra tag | Dyn check |
|---|---|---|---|
| `Int` | 0, a number | none | the value is an integer in range |
| `Nil` | 1, nil | none | the value is `~` |
| `(a . b)` | 2, a pair | none | kind 2, then check `a` and `b` |
| `[a]` | 2, a chain of pairs | none | kind 2 or nil, then check each item |
| `a -> b` | 3, a function | none | kind 3; arity is not checked |
| `Pin a` | 4, a pin | none | kind 4 |
| a declared sum | 5, a constructor | the constructor's tag, from 0 up | kind 5, the tag belongs to this sum, then check the payload |

Tags are numbered per declaration, so the same number can mean different constructors in different sums. The expected type says which tags are valid, so a `Dyn` value is only checked against the sum it is being used as.

The payload check is deep: a `Dyn` value used as `Result Int Str` checks the payload as well as the tag. This keeps the guarantee, at the cost of a step per item for a long list. A value that passes a check is known to have the right shape. Its meaning comes from the static types around it, not from anything stored with it.

### 13.6 What is not checked

- Machine failures (a wrong-kind `head`, a divide by zero) are not types. They end the run, as in L1.
- Quoted and binary forms are not checked when they are read. The check happens when a `Dyn` value is used at a type.
- Effects, subtyping, type classes and kinds are not in the first version.

### 13.7 The bootstrap

The L2 compiler written in L2 is checked as a surface program, so it is typed. Its output, the quoted form, is untyped, which is the same situation as any other quoted code.

## 14. Decided questions

These were open, and are now settled:

1. Prefix application only, with no infix sugar for now (3.3).
2. Constructors are tagged in the machine (section 8).
3. The results model is a built-in sum `Result`, with `?` and `match` (section 9).
4. The dispatch expressions are `tagof` and `payload` (section 9.4).
5. Layout: newlines separate `match` arms, a body continues only inside parentheses, indentation is deferred, `let` is non-recursive, `letrec` and `mutual` are for recursion (section 12).
6. A dot inside brackets is a syntax error, and nested pairs are written with parentheses (section 5).
7. Constructor text syntax: a capitalised name applied by juxtaposition, and a bare name for a constructor with no payload (section 5).
8. Constructor data form: `con TAG PAYLOAD` in the data text and tag byte 4 in the binary format (section 5).
9. Tag numbers: a user sum's constructors are numbered from 0 in declaration order, so `Ok` is 0 and `Err` is 1 (section 13.4). nil is `~`, and strings are lists of bytes (section 5).
10. `Dyn` checks are inserted automatically during inference (section 13.5).
11. Nullary constructors have payload `~`, and several fields are one pair (section 13.4).

Nothing is open in the draft. The remaining work is implementation: the L2 reader, the type checker, and the constructor data form.
