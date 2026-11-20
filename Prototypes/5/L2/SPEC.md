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
         | "if" expr expr expr   branch on an integer: nonzero is true
         | "match" expr "{" arm+ "}"    (open, section 8)
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

**Open: the design is not decided.** The idea:

- Layer 0: the machine. Raw opcodes on untagged values. As in L1, the machine keeps its own kind checks: `head` of a non-cell is an error.
- Layer 1: the library. Every L2 value carries its tag, and each operation untags its arguments, calls the raw opcode, and retags the result. `add` on two Int values is `untag, add, tag Int`.

The cost is one extra cell per value, unless the tag lives in the machine's value representation. **Recommended:** put the tag in the machine's values, so the check and the operation happen in one step, and keep the raw opcodes for code that does not need the check. The surface layer then uses the tags the machine already has. Decide before implementation.

## 9. Results and errors

**Open: research needed.** The current convention is `[0 value]` for success and `[1 message]` for failure, applied by hand. Candidates:

- Tagged sum types with `match`, as in OCaml and Rust enums.
- A `?` operator that returns early on a failure, as in Rust.
- Exceptions with `try`, which the machine would need to support.

A memo will compare these before the design is fixed.

Runtime errors from the machine (a wrong-kind `head`, a divide by zero) end the run as `error` with a message, as in L1.

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

## 12. Open questions

1. Infix sugar for primitives: yes or no?
2. Tagged values: in the machine, or in a layer above it (section 8)?
3. Results: which model (section 9)?
4. Exact tag numbers and the representation of nil and strings.
5. Whether `match` is a core form or a library function.
