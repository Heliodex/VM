# L2: specification draft

Status: draft. Sections marked **open** need a decision or research before they are final.

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
expr   ::= atom
         | expr atom+            application, curried: f a b is (f a) b
         | "fn" params expr      function (section 4)
         | "let" name "=" expr "in" expr
         | "letrec" name "=" expr "in" expr    (recursive; section 12)
         | "mutual" "(" binding+ ")" "in" expr    (section 12)
         | "if" expr expr expr   branch on an integer: nonzero is true
         | "match" expr "{" arm+ "}"    (section 9.3)
atom   ::= integer | string | name | "~" | list | pair | "(" expr ")"
list   ::= "[" expr* "]"        a proper list
pair   ::= "(" expr "." expr ")"
params ::= name | "(" name+ ")"
```

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

Every value has a tag. **Open (section 8):** the tag representation and the tags themselves. The draft's working set:

| Tag     | Meaning                                   |
|---------|-------------------------------------------|
| Int     | an integer in range                       |
| Nil     | the empty list, written `~`               |
| Pair    | a cell with a head and a tail             |
| Fn      | a function (closure)                      |
| Pin     | a suspended expression (see section 7)    |

A string is a list of Int values, each from 0 to 255, so `"ab"` is `[97 98]`.

A list `[a b c]` is the pair chain `(a . (b . (c . ~)))`. A pair `(a . b)` is one pair cell, which is not a list unless `b` is a list. The printer writes a list with brackets and a pair with a dot, so the two forms never print the same way.

## 6. Primitives

Primitives are the functions the machine provides. They are written as names, with the symbols from the table in `interpreter/primitives.luau`: `+ - * / % < = @`. Their full names are `add sub mul div mod lt eq kind`. Primitives take values with their tags checked by the surface layer (section 8). The raw opcodes take untagged values.

`@` (kind) returns the tag of a value as an integer, using the same numbers as L1: 0 Int, 1 Nil, 2 Pair, 3 Fn, 4 Pin.

## 7. Pins and fix

`pin e` suspends `e`. `force p` runs a suspended expression. `fix f` gives the fixed point of a function, as in L1. These are the only operations on suspended expressions.

## 8. Tagged values and the layers

**Decided: constructors are tagged in the machine.** Integers, nil, pairs, functions and pins keep their representations, and their kind is the same as in L1 (`@` gives 0 to 4). A constructor is a new value kind, 5, with a tag and a payload. Only user sums and `Ok`/`Err` are constructors, so an integer costs nothing extra, and a constructor cannot be mistaken for a pair.

The machine has three expressions for constructors:

- `construct tag e`: a constructor with the given tag, from 0 up, and the value of `e` as its payload.
- `tagof e`: the tag of a constructor, or -1 for any other value. It never fails, so it is the test in a `match`.
- `payload e`: the payload of a constructor. It is an error for any other value, so it is only used after a `tagof` test.

A constructor is not data yet: a program that returns one is `not_data`, as a function is. A text form for printing and reading constructors is part of the L2 surface, not L1.

The layer above, in the surface language, untags and retags for the library functions as before. The raw opcodes take untagged values, and the machine's own kind checks stay.

## 9. Results and errors

**Open: research needed.** The current convention is `[0 value]` for success and `[1 message]` for failure, applied by hand. Candidates:

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

`e?` evaluates `e`. If it is `Ok v`, the expression is `v`. If it is `Err e`, the whole enclosing function returns `Err e`. The reader hoists `e?` into a `let` in the same function, so it works anywhere an expression can appear. This is sound because L2 is pure: moving an evaluation earlier changes only which error is reported first, never a result. The payload types must match: a function that uses `?` on `Err e` must return `Err` with a compatible payload.

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

Changes to the machine that L2 needs, listed separately so they can be reviewed on their own:

- Tagged values, if section 8 puts the tag in the machine.
- Anything that the results design (section 9) needs, such as early return.

Expressions that L1 already has stay: `quote`, `var`, `lam`, `pin`, `cell`, `index`, `force`, `if`, `apply`, `prim`.

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

## 13. Open questions

Decided: prefix application only, with no infix sugar for now (3.3); tags for constructors in the machine (section 8); the results model (section 9); the dispatch expressions (section 9.4); layout and binding (section 11), with `letrec` for recursion, newlines separating arms, and indentation deferred.

1. The text syntax for constructors: how `Ok v` and `Err e` are written and printed.
4. How a user declares their own constructors and their tags. The examples assume `Ok` and `Err` are built in, with tags 0 and 1.
5. The meaning of `[1 2 . 3]`, a list with an improper tail.
2. Data form for constructors, so a constructor can be an output of a program.
3. Exact tag numbers for `Ok` and `Err`, and the representation of nil and strings.
