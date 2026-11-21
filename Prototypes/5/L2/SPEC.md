# L2: specification draft

Status: draft. Every question in the draft is decided; section 14 records them.

L2 is the next language on the machine in `interpreter/`. It keeps what L1 learned, changes the surface syntax, and adds tagged values. The reference implementation is written in Luau. L2 is bootstrapped in L2 only after its surface is stable.

## 1. Goals

- Easy to parse: one token of lookahead, no precedence table beyond a few operators, no layout rules.
- Every value is tagged, so an operation on the wrong kind of value is a clear error.
- Small core. Everything else is a library function.
- Positions (line and column) are kept by the reader and the desugarer, so errors from them point at source. The type checker reports errors by node identifier, not by position.
- Programs and results are data, as in L1, so the existing binary and printed formats keep working.

Non-goals for now: a module system beyond imports, effects, a foreign-function interface, and concurrency.

## 2. Lexical structure

Tokens, separated by whitespace or by delimiters:

- Integers: a `-` immediately followed by digits is part of the integer, so `-5` is a literal. `- 5`, with a space, is the symbol `-` applied to 5. Range as in L1, from -(2^53 - 1) to 2^53 - 1.
- A token that starts with a digit, or with `-` and a digit, must be a whole integer. So `1-2` is a lexical error. Names such as `x-1` are single symbols.
- Strings: `"..."` with the escapes `\"`, `\\`, `\n`, `\t`, `\0`. A string is a list of bytes (see section 5).
- Symbols (names and operators): a maximal run of characters that are not whitespace, `(`, `)`, `[`, `]`, `{`, `}`, `"`, `;`, or `.`. A symbol cannot start with a digit.
- The dot `.` is a token of its own, used only in pairs, so `(1 . 2)` is a pair and `(1.2)` is a lexical error. The arrow `->` is a token of its own, reserved for match arms. A `-` is never part of an arrow, so `x->y` is `x`, `->`, `y`.
- Comments: `;` to the end of the line.
- Delimiters: `(`, `)`, `[`, `]`, `{`, `}`, `.`, and `->`.

## 3. Syntax

### 3.1 Expressions

```
expr   ::= app
         | app "?"               early return on a failure (section 9.2)
         | "check" atom          the result of an explicit check of an untyped value (section 13.5)
         | "untyped" atom        the value of an atom, given the type Dyn (section 13.5)
app    ::= atom+                application, curried: f a b is (f a) b
         | "fn" params newline expr    function; the body is on the line after the parameters (section 4)
         | "let" name "=" expr newline expr
         | "letrec" name "=" expr newline expr    (recursive; section 12)
         | "mutual" "(" binding+ ")" expr    (section 12)
         | "if" expr expr expr   branch on an integer: nonzero is true
         | "match" expr "{" newline arm+ "}"    (section 9.3; arms are multi-line, section 12)
atom   ::= integer | string | name | "~" | list | pair | "(" expr ")"
list   ::= "[" expr* "]"        a proper list
pair   ::= "(" expr "." expr ")"
params ::= name | "(" name+ ")"
binding ::= "(" name expr ")"     a name for a function in a mutual group, as in L1
arm     ::= pattern "->" expr     the body ends at the end of its line (section 12)
pattern ::= Name                  a constructor with no payload, e.g. None
          | Name name             a constructor with a variable payload, e.g. Ok v
          | Name "_"              a constructor, payload ignored, e.g. Err _
          | "_"                   any value, ignored
          | name                  any value, bound to the name
```

`?` ends an application, so `parse s?` is `(parse s)?`, and it applies to the whole call on its left. To apply `?` to an argument, wrap it in parentheses: `g (parse s)?`. `?` appears at most once at the end of an application, so `f x? y` and `e??` are syntax errors. `?` is not an atom.

The grammar needs one token of lookahead: `(` starts a pair if the token after the first expression is `.`, and a group otherwise. The parser decides at the closing `)` or `.` after its first expression, so a group and a pair share one prefix. Implementations may use a small backtrack buffer.

### 3.2 Application

Application is juxtaposition: `f x y` is `(f x) y`. An atom is any single expression that can stand alone without a space-separated argument. A list, a pair, a string, a number, a name, `~`, and a parenthesised expression are atoms. `fn`, `let`, `if` and `match` are not atoms, so `f fn x x` is an error. Write `f (fn x x)`.

### 3.3 Operators

Operators are ordinary names, so `+ 1 2` is application of `+`. Infix forms `a + b` are not part of the first version. Operators are written in prefix form only, and infix sugar with a fixed precedence table can be added later, if wanted.

### 3.3a Equality

`=` is the integer equality primitive, and gives 0 or 1. Equality on other values (constructors, pairs, lists, strings) is not defined in the first version. A program tests a constructor with `match`, and compares strings and lists by walking them.

### 3.4 Names

Names are symbols that are not reserved (section 3.5). Names are lexically scoped and must be bound before use. Shadowing is allowed in a nested scope.

### 3.5 Reserved words

`fn`, `let`, `letrec`, `if`, `match`, `mutual`, `~`, `_`, and the primitives' symbols, listed in section 6.

## 4. Functions

`fn x body` is a function of one name, and `fn (x y) body` is sugar for `fn x (fn y body)`. The body starts on the line after the parameters, so a newline is required between them: `fn x` and then `(+ x 1)` on the next line. A function with no parameters is an error. Application is curried, so partial application gives a function.

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

Division by zero and `head` or `tail` of nil give `Err` as a value (section 13.3). Integer overflow is still a machine error, and ends the run as `error` with a message, as in L1.

### 9.1 Sums

A sum type has constructors, each with one payload. The first version has one built-in sum, `Result`:

```
Ok v      a success carrying v
Err e     a failure carrying e
```

Constructors are tagged values (section 8), so `kind` and `match` can tell them apart. A sum is not a list or a pair, and it prints as `Ok v` or `Err e`.

### 9.2 Early return

`e?`, where `e` is an application, evaluates `e`. If it is `Ok v`, the expression is `v`. If it is `Err e`, the whole enclosing function returns `Err e`. The desugarer hoists `e?` into a `match` around the function's body, so the early return runs only when the `?` is reached.

Where a `?` may appear is limited, so that hoisting never runs an expression that would not otherwise run:

- In the body of a function, and in any expression that always runs with it (a let value, an argument, a list item, a pair part, an if condition, a match scrutinee), it is allowed. Its early return leaves the enclosing function.
- In a let or mutual body, or in an if branch or match arm, it is allowed only when that let, if or match is itself the function's result. Then the branch is a function of its own, and the early return leaves it. The names the let binds are in scope for it.
- Anywhere else, including an if branch or match arm that is not the function's result, it is an error.

This is sound because L2 is pure: moving an evaluation earlier changes only which error is reported first, never a result. The payload types must match: a function that uses `?` on `Err e` must return `Err` with a compatible payload.

### 9.3 Match

`match e { pattern -> body ... }` evaluates `e`, tests the constructor of its value against each arm in order, and evaluates the body of the first arm that matches, with the pattern's variables bound.

Patterns in the first version are the forms in section 3.1: a constructor with no payload (`None`), with a variable payload (`Ok v`), or with a wildcard payload (`Err _`); a wildcard `_`; and a name, which binds the whole value and matches anything. A name pattern is always last, and an arm after it is reported as unreachable.

Nested patterns are not in the first version. A nested pattern can be written as nested `match` expressions.

Arms are on their own lines. A `match` is written over several lines, and there is no one-line form, so no separator is needed between arms.

Arms are lazy: only the body of the arm that matches is evaluated. The compiler checks that the arms cover every constructor of the scrutinee's type, or that a catch-all arm (`_` or a name) is present, and reports an error otherwise.

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
- Tests: L2 programs use the four-section program-file format of L1 (header, imports, program, tests), in `L2/programs/`. A test is an input, `=>`, an output, and fuel. A test may span lines: a line that starts with a space or a tab continues the test before it, so a function in an input breaks before its body like any other function. L1 programs are not ported; they stay as they are. L2 programs are tested against their own expected results, and the L2 reader and checker have their own test runner in the L2 module.

## 12. Layout and binding rules

These rules are decided for the first version.

- **Newlines** are whitespace, except inside a `match` block, where a newline ends an arm, and after the value of a `let` or `letrec`, where a newline ends the value.
- **Arms** are `pattern -> body`. A body ends at the end of its line. To continue a body onto the next line, wrap it in parentheses, so the parser never needs a layout rule.
- **Indentation** has no meaning. Indentation-based syntax is deferred, and it can be added to the lexer later without changing the grammar.
- **`let`** is non-recursive, and has no keyword between its value and its body. The value ends at the end of its line, so a longer value is wrapped in parentheses, and the body starts on the next line. A `let` inside a match arm is wrapped in parentheses too, since the arm already ends at its line. A recursive function is written with **`letrec`**, which is `fix` as in L1, and a group of functions that call each other is one **`mutual`** form. Its body follows the close of its bindings, with no keyword between them.

Example:

```
describe r = match r {
  Ok v -> v
  Err e -> (
    let n = 0
    n
  )
}
```

## 13. Types (first version)

The first version has a small static type system for surface programs. Quoted and binary forms are untyped, as in L1. The checker runs on surface syntax, before compilation, and it is not part of the machine.

### 13.1 Types

```
t ::= Int                 an integer
    | (t . t)             a pair
    | t -> t              a function, curried
    | Pin t               a suspended value (section 7)
    | a                   a type variable
    | Name t*             a declared sum, such as Result t e
    | Dyn                 a value from untyped code (13.4)
```

A list of `t` has type `[t]`, a built-in recursive type. Its values are the pair chains of section 5, so a `[t]` value is `~` or a pair `(t . [t])`. The empty list is `~`, and it has type `[t]` for any `t`. A list literal `[a b c]` has type `[t]` when each item has type `t`. A pair and a list are different types, even though a list is a pair chain at run time: `(1 . ~)` has type `(Int . [Int])`, not `[Int]`, and `cons` builds a list from an item and a list (section 13.3).

### 13.2 Inference

The checker is unification with mutable type variables, following Algorithm W. Each variable records the nesting depth at which it was created, and a `let` or `letrec` generalises the variables created deeper than its own level. Unification has the usual occurs check.

The checker runs on the parser's tree, before the desugarer. It reports every type error, one per line, at the source position of the node where it is found. A node with a type error gets a fresh type, so the rest of the program is still checked, and the errors after the first are not lost. Later errors can follow from an earlier one.

The constructs:

- `fn` makes an arrow type.
- `letrec` binds its name before checking its body, and generalises afterwards.
- `mutual` checks its group together and generalises the group after.
- `if` needs an `Int` condition, and its branches must have the same type.
- `match` checks each pattern against the scrutinee's sum, requires the arms to have one type, and checks coverage: the arms' constructors must be the sum's constructors, or a catch-all arm must be present. Arms after a catch-all are reported as unreachable.

`check e` has the type `Result t [Int]`, where `t` is the type its use gives the value. The check is not generalised, so its test is known when inference ends. A value of `Dyn` is used at a specific type only through `check`. Unifying `Dyn` with a concrete type is a type error, and unifying `Dyn` with an unbound variable binds the variable to `Dyn`.

The output is the same tree with the check nodes inserted, and the desugarer takes that tree.


Types are inferred with Hindley–Milner: unification, with let-polymorphism for `let` and `letrec` bindings. A function's type is generalised at its `let` or `letrec`, so `fn x x` is `a -> a` and can be used at two types.

Recursive functions (`letrec`) are checked monomorphically within their own body, as usual for HM, and generalised afterwards. `mutual` groups are checked together and generalised together.

### 13.3 Primitives and forms

- `+ - *` have type `Int -> Int -> Int`.
- `/` and `%` have type `Int -> Int -> Result Int [Int]`: a zero divisor gives `Err` with the reason, `division by zero` or `remainder by zero`.
- `< =` have type `Int -> Int -> Int`, since the machine returns 0 or 1.
- `@` has type `a -> Int`, the kind of any value.
- `head` and `tail` have type `[a] -> Result a [Int]` and `[a] -> Result [a] [Int]`. On nil they give `Err` with the reason, `head of an empty list` or `tail of an empty list`. They take lists, so that a recursive function over a list is typed. A pair is not a list, so `head` of a pair is a type error.
- `fst` and `snd` have type `(a . b) -> a` and `(a . b) -> b`. A pair is never nil, so they give the part with no Result. A pair whose parts have different types is taken apart this way, so `(1 . (2 . 3))` has `fst` of `1` and `snd` of `(2 . 3)`.
- `cons` has type `a -> [a] -> [a]`: `cons x xs` is the list with x in front of xs.
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

- `untyped e` gives the value of `e` the type `Dyn`, with no test. It is how a program makes an untyped value, since any value can be seen as untyped data. A `Dyn` value is used at a specific type only through `check e`, which is written in the program. `check e` gives `Ok e` when the value has the shape of the type its use gives it, and `Err` with the message `expected` and the type, such as `expected Int`, when it does not. An `Int` must be an integer, a pair must be a pair, and a constructor must have the declared tag. Without a check, a `Dyn` value used at `Int` is a type error, such as `expected Int, but this is Dyn`.
- A typed value passed into untyped code is not checked, and it is still a valid value of its type.

So a program can run untyped code, and the types it has are kept at the boundary by an explicit check. The check is part of the surface language's compiled form, not the machine, and a failed check is a value, so it can be matched and handled like any other error.

A program is run on untyped data. Its input is checked against the input type the checker inferred, when the program is run. A failed input check is the run's value: the run gives `Err` with the message, and the program does not run.

### 13.5.1 Tags at run time

Only constructors carry a tag of their own. Every other value's kind comes from its representation, so the static types need no extra tag at run time.

| Type | Kind | Extra tag | Dyn check |
|---|---|---|---|
| `Int` | 0, a number | none | the value is an integer in range |
| `(a . b)` | 2, a pair | none | kind 2, then check `a` and `b` |
| `[a]` | 1 for nil, or 2 for a pair | none | kind 1, or kind 2 then check the item and the rest of the list |
| `a -> b` | 3, a function | none | kind 3; arity is not checked |
| `Pin a` | 4, a pin | none | kind 4 |
| a declared sum | 5, a constructor | the constructor's tag, from 0 up | kind 5, the tag belongs to this sum, then check the payload |

Tags are numbered per declaration, so the same number can mean different constructors in different sums. The expected type says which tags are valid, so a `Dyn` value is only checked against the sum it is being used as.

The payload check is deep: a `Dyn` value used as `Result Int Str` checks the payload as well as the tag. This keeps the guarantee, at the cost of a step per item for a long list. A value that passes a check is known to have the right shape. Its meaning comes from the static types around it, not from anything stored with it.

### 13.6 What is not checked

- Machine failures (integer overflow past 2^53, and the other faults the machine has) are not types. They end the run, as in L1. Division, remainder, `head` and `tail` do not reach the machine's failures: their checks are in the desugarer, and they give `Err` as a value.
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
5. Layout: newlines separate `match` arms and end a `let` value, a body continues only inside parentheses, indentation is deferred, `let` is non-recursive, `letrec` and `mutual` are for recursion (section 12).
6. A dot inside brackets is a syntax error, and nested pairs are written with parentheses (section 5).
7. Constructor text syntax: a capitalised name applied by juxtaposition, and a bare name for a constructor with no payload (section 5).
8. Constructor data form: `con TAG PAYLOAD` in the data text and tag byte 4 in the binary format (section 5).
9. Tag numbers: a user sum's constructors are numbered from 0 in declaration order, so `Ok` is 0 and `Err` is 1 (section 13.4). nil is `~`, and strings are lists of bytes (section 5).
10. `Dyn` values are checked only by an explicit `check`, which gives a `Result` (section 13.5).
11. Nullary constructors have payload `~`, and several fields are one pair (section 13.4).

Nothing is open in the draft. The remaining work is implementation: a surface form that produces untyped values, which is the source of `Dyn` (section 13.5).
