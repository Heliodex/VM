# Phase 0: measuring Prototype 6

This folder holds the measurement for Phase 0 of `Prototypes/7/README.md`. It measures Prototype 6 and does not change it. The baseline is Prototype 6 at commit `aafa9cc`, the last commit that touched its machine.

## Running it

From this folder:

    lute run phase0.luau

The run takes about 7 minutes. `results/run4.txt` is the output of the run that the numbers below come from.

## What is here

| File | What it is |
| --- | --- |
| `phase0.luau` | The driver: validation, the corpus build, the profile, the growth by owner, and the scaling. |
| `compile.luau` | Compiles an L2 file as Prototype 6's `L2.compile` does, including imports, and times each host stage. Each node gets an owner (the function it belongs to). |
| `desugar_named.luau` | A copy of Prototype 6's desugarer. The only change: a function bound by `let` or `letrec` is labelled with its name and line, so the profile can name it. |
| `vm_counted.luau` | A copy of Prototype 6's machine (`interpreter/vm.luau`). The changes: the primitives come from Prototype 6, nil is Prototype 6's table (the machine tests nil by identity), and the reference loop calls a hook at each step. |
| `results/run4.txt` | The raw output of the run below. |

The driver checks the copies by their steps. The hybrid machine gives 299,622,490 steps on the checker, which is what `vm_bench` reports, and the counted machine, with the labelled desugarer, gives the same count. Labels and the hook therefore change no steps.

## What was measured

1. **Validation.** The checker on `types.l2` gives 299,622,490 steps on the hybrid machine, which is what `vm_bench` reports, and the same steps on the counted machine.
2. **The corpus build.** Four files from `Prototypes/6/L2/programs/boot/`: `lex.l2`, `parse.l2`, `layout.l2`, `types.l2`. 2,235 lines and 82,118 bytes in all. Each file goes through the host stages (layout, the Luau parser, the Luau checker, the desugarer, and the imports) and the VM stages (lex, parse, check). The VM stages use the bootstrapped compiler, compiled once and not counted in the build.
3. **The profile.** The checker on `types.l2` under the counted machine: steps by form, by frame, and by owning function.
4. **Growth by owner.** The checker on 100 and 400 generated functions, profiled. An owner whose steps grow 16× from 100 to 400 functions is quadratic, and one that grows 4× is linear.
5. **Scaling.** The VM stages on generated programs of 25, 50, 100, 200, 400, 800 and 1,600 functions. Each function is `let f_i = fn y (+ (f_{i-1} y) i)`, so the program is a chain of nested lets.

## Results

### 1. Validation

The checker on `types.l2`: 299,622,490 steps on the hybrid machine (the same as `vm_bench`) and on the counted machine.

### 2. The corpus build

| File | Bytes | Lines | Host (s) | VM lex | VM parse | VM check | VM total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lex.l2` | 5,359 | 144 | 0.019 | 3.03M | 8.60M | 30.98M | 42.61M |
| `parse.l2` | 23,641 | 626 | 0.059 | 13.86M | 37.73M | 200.02M | 251.61M |
| `layout.l2` | 13,698 | 552 | 0.015 | 7.84M | 21.41M | 75.68M | 104.92M |
| `types.l2` | 39,420 | 913 | 0.034 | 23.92M | 67.25M | 299.62M | 390.79M |
| **Corpus** | **82,118** | **2,235** | **0.128** | **48.65M** | **134.99M** | **606.30M** | **789.93M** |

- **Host.** The Luau compiler builds the whole corpus in 0.13 s of CPU time. That is already inside the 1 s target for 2,500 lines, so the target only has teeth for the bootstrapped build on the VM.
- **VM.** The bootstrapped build takes 789.9M steps, 51–60 s of CPU time on the hybrid machine across runs. That is 13–18M steps per second, and about 353,000 steps per line.
- **Shares.** The checker is 77% of the VM steps, the parser 17%, and the lexer 6%.
- **Imports.** `lex.l2` and `parse.l2` import library files (`reverse`, `append`). The bootstrapped checker's request has no imports, so its check of those two files reports the imports as unbound. The steps are real work, but the check is not a full check of those files. `layout.l2` and `types.l2` have no imports.
- **Host only.** Layout and desugar are not on the VM. `boot/layout.l2` exists, but nothing in the build runs it, and there is no bootstrapped desugarer. So the build target's "desugar" stage is host work today, and the VM build covers lex, parse and check only.

### 3. The profile (checker on `types.l2`, 299,622,490 steps)

By form, the largest are `var` 17.0%, `apply` 10.0%, `lam` 7.5% and `prim` 5.9%. By frame, `apply` takes 19.9% of steps and `prim` 10.9%.

By owning function:

| Group | Functions | Share |
| --- | --- | ---: |
| Binding index arithmetic | `halfOf`, `oddOf` | 27.6% |
| Binding trie access | `findB`, `setB`, `pickSide` | 24.7% |
| List access | `first`, `tl`, `hdOr` | 21.5% |
| Name environment search | `findE`, `same` | 9.3% |
| Top-level code | `top` | 7.5% |

The rest is under 3% each. `halfOf` and `oddOf` are `/` and `%` by 2, each wrapped in a `Result` that is matched at every level of the trie. `first`, `tl` and `hdOr` are list accessors that also return a `Result`. Together these helpers are 83% of the checker's steps, so most of the cost is in wrapping and unwrapping results, not in the checking itself.

### 4. Growth by owner (100 to 400 generated functions)

| Owner | Growth from 100 to 400 functions |
| --- | ---: |
| `findE` (name environment search) | 13.5× |
| `first` | 10.6× |
| `hdOr` | 10.4× |
| `same` (name compare) | 9.9× |
| `tl` | 8.5× |
| `halfOf`, `oddOf`, `findB`, `setB` | 4.1–4.2× |

A quadratic term grows 16× here and a linear one 4×. The name environment (`findE` with `same`) grows near 16×, and the list accessors it calls grow with it. The binding trie grows linearly. So the quadratic cost is the search of the name environment, which is an association list with one entry per binding in scope.

### 5. Scaling

| Functions | Lines | Bytes | Lex steps | Parse steps | Check steps | Check steps per function |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 25 | 59 | 888 | 0.59M | 1.59M | 3.35M | 134k |
| 50 | 109 | 1,714 | 1.18M | 3.11M | 6.69M | 134k |
| 100 | 209 | 3,368 | 2.35M | 6.16M | 13.87M | 139k |
| 200 | 409 | 6,969 | 4.90M | 12.26M | 30.81M | 154k |
| 400 | 809 | 14,169 | 10.01M | 24.46M | 73.29M | 183k |
| 800 | 1,609 | 28,570 | 20.22M | 48.87M | 193.50M | 242k |
| 1,600 | 3,209 | 59,175 | 41.89M | 97.75M | 568.81M | 355k |

- **Lex and parse are linear.** Lex costs 565–706 steps per byte and parse 1,560–1,830 per byte, across the corpus and the generated programs, with no sign of growth.
- **Check is superlinear.** Each doubling multiplies its steps by 2.00, 2.07, 2.22, 2.38, 2.64 and then 2.94. A fit of `a·n + b·n²` to the points gives about 128,000 steps per function and about 142·n². That fit tracks all seven sizes within about 3%. The quadratic term is 31% of the checker's steps at 400 functions, and 64% at 1,600.

Seven sizes from one generator is still a narrow test. The fit describes this family of programs, and a different shape of program could behave differently.

## What this changes in the plan

- **The hypothesis about association lists was half right.** The binding store is a binary trie keyed by variable id, not an association list. The association list is the name environment (`findE`), and that is where the quadratic term comes from. Phase 1 should replace the name environment (a balanced map keyed by an interned name), and it should remove the `Result` wrapping from the trie index and from the list accessors.
- **The per-declaration constant is the larger cost at real sizes.** About 128,000 steps per declaration, before the quadratic term, is what the build pays at 2,500 lines. The profile suggests most of it is trie and list-accessor work, but the profile was taken on `types.l2`, not on the generated programs that give the constant, so that is a likely reading, not a measured one.
- **The gap to the speed target is about 50×, and it may be larger.** At the corpus average of 353,000 steps per line, 2,500 lines take about 884M steps. At 18M steps per second that is 1 s if the steps drop to about 18M, which is about 49×. At the slower run's 13M steps per second it is about 68×. The quadratic term makes larger programs cost more per line, so the average understates the gap for a large build.
- **Phase 0's exit is met.** We know the checker's cost is superlinear, and we know its largest cost centres: the index arithmetic and trie access (52%), list access (22%) and name search (9%). Phase 1 (fixing the algorithms in L2) comes before any new machine, as the plan says.
- **The target's stages are not all on the VM.** Layout and desugar run on the host. Until they are bootstrapped, a "build on the VM" covers lex, parse and check only, and the target has to say which build it means.
- **Imports are missing from the bootstrapped checker.** A bootstrapped build of any file that imports a library cannot be complete until the request carries the imports.
