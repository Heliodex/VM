# The standard library, in L2

Each file here is an L2 program file (see `L2/programs/`). Each one defines one function, and its tests run with the rest of `l2_run.luau`. A program that uses a library function imports it by its path from the top of `L2/programs/`, such as `lib/sort.l2` importing `lib/insert.l2`.

This is the L2 counterpart of `L1/programs/lib/`. The same functions are here, with the L2 conventions in place of the L1 ones.

## Conventions

- **One argument.** A function takes one input. Several values are passed as a pair, written `(a . b)`, so `gcd` takes `(a . b)` and `take` takes `(n . xs)`. A list is written `[a b c]`, and a pair is never a list, so `(1 . ~)` is a pair and `[1]` is a list.
- **Results.** `head` and `tail` give a `Result`, since nil has no head. A function that takes a list apart therefore gives a `Result` too: `Ok` of its value, or `Err` with a message. `unwrap_or` turns a result into a plain value.
- **Lists end in `~`.** `~` is nil, and a list is built with `cons` or with the list literal.

## What is here

| File | Input | Output |
|---|---|---|
| `length` | list | `Ok` of the number of items |
| `append` | `(xs . ys)` | `Ok` of xs followed by ys |
| `reverse` | list | `Ok` of the items in reverse |
| `sum` | list of integers | `Ok` of their sum |
| `max`, `min` | `(a . b)` | the larger, or the smaller |
| `abs` | integer | its absolute value |
| `gcd` | `(a . b)` | `Ok` of the greatest common divisor |
| `range` | n | the list 0 to n - 1 |
| `take` | `(n . xs)` | `Ok` of the first n items |
| `nth` | `(n . xs)` | `Ok` of the item, or `Err "index out of range"` |
| `contains` | `(x . xs)` | `Ok 1` if x is in xs, else `Ok 0` |
| `unwrap_or` | `(r . default)` | the `Ok` value, or the default |
| `insert` | `(x . xs)` | `Ok` of xs, sorted, with x inserted |
| `sort` | list of integers | `Ok` of the sorted list (imports `insert`) |
| `map` | `(f . xs)` | `Ok` of the results of f on each item |
| `filter` | `(pred . xs)` | `Ok` of the items that pred accepts |
| `fold` | `(f . (init . xs))` | `Ok` of f applied from the left, starting from init |
| `triple` | integer | three times it (imported by `ninefold`) |
| `ninefold` | integer | nine times it (imports `triple`) |

## Not here

- **`equal`.** The L1 version compares any two data values, all the way down. In L2 that needs a type that covers every kind of value, and the checker has none: a value used by kind must be `Dyn` and checked first. It can be added once untyped data has a form that the library can take apart.
