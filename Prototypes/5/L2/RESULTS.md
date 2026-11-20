# L2: results and errors

Status: recommendation for review. It answers the open results question in `SPEC.md` section 9.

## The question

L1 has two ways to report a problem, and both are weak in different ways:

- A value, `[0 result]` or `[1 message]`. A caller has to check the tag by hand, and the bootstrap spends much of its code on `bind` plumbing. Nothing stops a program from building a `[1 x]` that looks like a failure, and the tag is a convention, not a type.
- `error`, which ends the run. A program cannot recover from it, and it cannot carry a structured value.

L2 needs one clear way to report an expected failure, that the compiler can check, and that is cheap to propagate.

## What other languages do

**Rust `Result<T, E>` with `?`.** `Result` is an ordinary enum, `Ok(T)` or `Err(E)`, so the compiler checks every case, and `match` handles each one. The `?` operator returns early with the `Err`, so a chain of fallible calls stays short. The error type is a normal type, and `?` converts it through a conversion the programmer can define. The cost is explicitness: every fallible function says so in its type. [Rust book, ch. 9; `std::result`]

**Zig error unions.** `E!T` is either a value of type `T` or an error from the error set `E`. `try` propagates and `catch` handles. Error sets are named, can be merged with `||`, and can be inferred from a function body. An error is just a name, with no payload, so structured information needs a separate value. [Zig documentation; zig.guide]

**Algebraic effects (Koka).** A function's effect is part of its type, and handlers define what an operation does. Exceptions, state, iterators and async are all library handlers. A `fun` operation resumes in place, and a `ctl` operation can resume any number of times. This is the most general option, and Koka compiles it efficiently with evidence passing, but it needs the machine to capture continuations and to pass evidence. [Koka book; Leijen, "Type Directed Compilation of Row-Typed Algebraic Effects"]

**Exceptions with unwinding.** Simple to write, but control flow is hidden, and a handler cannot resume the code that raised. Unwinding needs a machine that can discard frames up to a handler.

## Fit with the machine

Our machine is an expression evaluator with explicit frames. It has no way to capture a continuation, and adding that is a large change. That rules out effects for L2's first version.

Early return can be done without machine support, for two reasons:

1. L2 is pure. Evaluating an operand early or late changes only which error is reported first, never a result. So `?` can be a rewrite: `let x = e?`, followed by its body, becomes `match e { Ok x -> body; Err e -> Err e }`, with no change to the machine.
2. The rewrite only needs the `Err` to be the function's result. In an expression language, the rest of the function is the body of a `let`, so the `Err` branch can be the result without unwinding anything.

Unwinding (`try`/`catch`) would need a handler frame in the machine that discards frames up to it. That is a small addition, but it adds hidden control flow, which L1 avoided on purpose, so I would leave it out.

## Recommendation

1. **A sum type, `Ok v | Err e`, as a tagged value.** It is the same shape as the `[0 v]`/`[1 m]` convention, with the tag checked by the language. It depends on the tagged-value design in `SPEC.md` section 8, and it removes the tag collision that L1 has.
2. **`match` as a core form.** It tests the tag and binds the payload. Patterns are constructors with names, with a wildcard. It is the only way to inspect a sum, so the compiler can check that every case is handled.
3. **`?` as sugar for early return.** It works in any expression position: the compiler hoists `e?` into a `let` in the same function, which is sound because L2 is pure. The error type of a function is the type of its `Err` payload, and `?` requires the payload types to match, as in Rust without the conversion trait.
4. **Errors as data.** The `Err` payload is an ordinary value. Structured information is a record or a tagged value, and a message is a string. Error sets are not needed: a sum type covers them, and naming a union of error types is a type alias.
5. **Machine failures stay `error`.** A wrong-kind `head` or a divide by zero is a bug in the program, not an expected failure, so it ends the run, as in L1. `error` cannot be caught.
6. **No effects or `try` in L2's first version.** Both are reasonable later additions. Effects would need continuation capture in the machine, and that is a separate project with its own design.

## What this does to the bootstrap

The L1 bootstrap's `bind` helper becomes the `?` rewrite, and its `[0 x]`/`[1 m]` checks become `match`. The bootstrap is simpler to write in L2 than in L1, which is one of the goals of L2.

## Open points

- The exact patterns `match` supports: nested constructors, literals, or only top-level tags.
- Whether `?` may be used at the top of a `match` arm, and how its hoisting interacts with `fn` bodies.
- The tag numbers and layout of sums. This depends on the tagged-value decision.
