# The standard library

Each file here is a program file (see the top of `interpreter/program_file.luau`). Each one defines one function, and its tests run with the rest of `programs_run.luau`. A program that uses a library function imports it by its path from the top of `programs/`, such as `lib/sort.prog` importing `lib/insert.prog`.

## Conventions

- **One argument.** A function takes one input. Several values are passed as a pair, so `gcd` takes `[a b]` and `take` takes `[n xs]`.
- **Results.** A function that can fail returns `[0 value]` on success and `[1 message]` on failure, as the parser does. `nth` and `unwrap_or` follow this, and `unwrap_or` turns a result into a plain value.
- **Lists end in `~`.** `[1 2 3 ~]` is a list. A bracket without the `~` is an improper pair.

## What is here

| File | Input | Output |
|---|---|---|
| `length` | list | number of items |
| `append` | `[xs ys]` | xs followed by ys |
| `reverse` | list | the items in reverse |
| `sum` | list of integers | their sum |
| `max`, `min` | `[a b]` | the larger, or the smaller |
| `abs` | integer | its absolute value |
| `gcd` | `[a b]` | greatest common divisor |
| `range` | n | the list 0 to n - 1 |
| `take` | `[n xs]` | the first n items |
| `nth` | `[n xs]` | `[0 item]`, or `[1 message]` past the end |
| `contains` | `[x xs]` | 1 if x is in xs, else 0 |
| `unwrap_or` | `[result default]` | the success value, or the default |
| `equal` | `[a b]` | 1 if equal all the way down, else 0 |
| `insert` | `[x xs]` | xs, sorted, with x inserted |
| `sort` | list of integers | sorted (imports `insert`) |

## Not here yet

Functions that take a function, such as `map`, `filter` and `fold`, are not in the library. The test format takes data as its input, and a function is not data, so there is no way to write their tests yet. They can be added once the format can give a test a function, such as by naming a library function as the argument.
