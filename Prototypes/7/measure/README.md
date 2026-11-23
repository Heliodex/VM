# Phase 0: measuring Prototype 6

This folder holds the measurement for Phase 0 of `Prototypes/7/README.md`. It measures Prototype 6 and does not change it. The baseline is Prototype 6 at commit `aafa9cc`, the last commit that touched its machine.

## Running it

From this folder:

    lute run phase0.luau

The run takes about 24 minutes, most of it in the layout scaling at 1,600 functions. `results/run5.txt` is the output that the numbers below come from. `results/run4.txt` is the earlier run without the VM layout stage; it is kept as history, and its checker numbers are the same.

## What is here

| File | What it is |
| --- | --- |
| `phase0.luau` | The driver: validation, the corpus build, the profile, the growth by owner, and the scaling. |
| `compile.luau` | Compiles an L2 file as Prototype 6's `L2.compile` does, including imports, and times each host stage. Keeps the raw program section (before layout), which the VM's layout stage reads. Each node gets an owner (the function it belongs to). |
| `desugar_named.luau` | A copy of Prototype 6's desugarer, with two changes made in Prototype 7 (Prototype 6's is unchanged). A function bound by `let` or `letrec` is labelled with its name and line, so the profile can name it. A mutual group binds in each branch only the names its function mentions, and dispatches on the member by a balanced tree of tests, not a chain. Both keep every program's outcome (the corpus's expect lines are unchanged), and both lower the same programs to fewer steps. |
| `vm_counted.luau` | A copy of Prototype 6's machine (`interpreter/vm.luau`). The changes: the primitives come from Prototype 6, nil is Prototype 6's table (the machine tests nil by identity), and the reference loop calls a hook at each step. |
| `results/run5.txt` | The raw output of the run below. |
| `results/run4.txt` | The earlier run, without the VM layout stage. |

## What was measured

1. **Validation.** The checker on `types.l2` gives 299,622,490 steps on the hybrid machine, which is what `vm_bench` reports, and the same on the counted machine. The VM's layout output on `types.l2` equals the host's.
2. **The corpus build.** Four boot files from `Prototypes/6/L2/programs/boot/`: `layout.l2`, `lex.l2`, `parse.l2`, `types.l2`. 2,235 lines and 82,118 bytes in all. Each file goes through the VM stages (layout, lex, parse, check) and the host stages (layout, Luau parser, Luau checker, desugar, imports). The VM's layout output must equal the host's, and it does on all four files. The compiler's own stages are compiled once and are not in any build.
3. **The profile.** The checker on `types.l2` under the counted machine: steps by form, by frame, and by owning function.
4. **Growth by owner.** The checker on 100 and 400 generated functions, profiled.
5. **Scaling.** All four VM stages on generated programs of 25 to 1,600 functions. Each function is `let f_i = fn y (+ (f_{i-1} y) i)`, so the program is a chain of nested lets. The sizes run to 3,209 lines.

## Results (run 5)

### 1. Validation

The checker on `types.l2`: 299,622,490 steps on the hybrid machine (the same as `vm_bench`) and on the counted machine. VM layout agrees with host layout.

### 2. The corpus build

| File | Bytes | Lines | Layout (VM) | Lex | Parse | Check | VM total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `lex.l2` | 5,359 | 144 | 16.85M | 3.03M | 8.60M | 30.98M | 59.46M |
| `parse.l2` | 23,641 | 626 | 172.89M | 13.86M | 37.73M | 200.02M | 424.50M |
| `layout.l2` | 13,698 | 552 | 76.33M | 7.84M | 21.41M | 75.68M | 181.25M |
| `types.l2` | 39,420 | 913 | 486.25M | 23.92M | 67.25M | 299.62M | 877.04M |
| **Corpus** | **82,118** | **2,235** | **752.3M** | **48.7M** | **135.0M** | **606.3M** | **1,542.2M** |

- **Host.** The Luau compiler builds the whole corpus in 0.10 s of CPU time. That is host work and is not the target.
- **VM.** The bootstrapped build takes 1,542.2M steps, 122 s of CPU time on the hybrid machine in this run. That is about 690,000 steps per line.
- **Shares.** Layout is 49% of the VM steps, the checker 39%, parse 9%, lex 3%. Layout is the largest stage. The earlier figure of 77% for the checker was true only before layout was measured.
- **Imports.** `lex.l2` and `parse.l2` import library files (`reverse`, `append`). The bootstrapped checker's request has no imports, so its check of those two files reports the imports as unbound. The steps are real work, but the checks are not complete.
- **Desugar.** Still on the host. There is no bootstrapped desugarer, so the VM build does not include it.

### 3. The profile (checker on `types.l2`, 299,622,490 steps)

Unchanged from run 4, since the checker is unchanged. By form, the largest are `var` 17.0%, `apply` 10.0%, `lam` 7.5% and `prim` 5.9%. By owning function, the trie helpers and their index arithmetic are 42% (`findB`, `setB`, `halfOf`, `oddOf`, `pickSide`), the list accessors 22% (`first`, `tl`, `hdOr`), and the name environment search 9% (`findE`, `same`).

### 4. Growth by owner (checker, 100 to 400 generated functions)

| Owner | Growth from 100 to 400 functions |
| --- | ---: |
| `findE` (name environment search) | 13.5× |
| `first` | 10.6× |
| `hdOr` | 10.4× |
| `same` (name compare) | 9.9× |
| `tl` | 8.5× |
| `halfOf`, `oddOf`, `findB`, `setB` | 4.1–4.2× |

A quadratic term grows 16× here and a linear one 4×. The name environment grows near 16×, and the list accessors it calls grow with it. The binding trie grows linearly.

### 5. Scaling, all four VM stages

| Functions | Lines | Layout | Lex | Parse | Check | Total |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 25 | 59 | 2.85M | 0.62M | 1.86M | 3.35M | 8.68M |
| 50 | 109 | 8.38M | 1.24M | 3.63M | 6.69M | 19.95M |
| 100 | 209 | 27.52M | 2.47M | 7.19M | 13.87M | 51.05M |
| 200 | 409 | 103.98M | 5.14M | 14.31M | 30.81M | 154.24M |
| 400 | 809 | 396.76M | 10.48M | 28.55M | 73.29M | 509.08M |
| 800 | 1,609 | 1,541.77M | 21.16M | 57.02M | 193.50M | 1,813.45M |
| 1,600 | 3,209 | 6,367.62M | 43.76M | 114.04M | 568.81M | 7,094.23M |

- **Lex and parse are linear.** Lex costs 565–740 steps per byte and parse 1,600–2,100 per byte, across the corpus and the generated programs.
- **Check is superlinear.** Each doubling multiplies its steps by 2.0 to 2.9. A fit of `a·n + b·n²` to the check points gives about 128,000 steps per function and about 142·n², within about 3%.
- **Layout is quadratic in lines.** Each doubling multiplies its steps by 2.9 to 3.3 at the smallest sizes and by 3.8 to 4.1 from 200 functions up. Divided by lines squared, the layout cost settles at about 600 steps per line² from 200 functions up (606 at 400, 596 at 800, 618 at 1,600). Across the corpus files it is 250 to 810 per line², about 485 overall.

## What this changes in the plan

- **Layout is the first cost to fix.** It is 49% of the corpus build, it grows quadratically, and at 1,600 functions it is 90% of the VM steps. At 2,500 lines it would be about 600 × 2,500², roughly 3.75 billion steps, which is about 200 s at 18M steps per second. Before any checker work, the layout pass needs a profile to find its quadratic term. The likely place is a list append or line walk per line, since the host layout is cheap on the same input. This is a hypothesis until it is profiled.
- **The checker's plan still stands, but it is no longer the whole story.** Its quadratic term is real. At 2,500 lines it is a smaller share of the total than layout.
- **The gap to the target is larger than run 4 said.** Run 4 counted only the checker, lex and parse. With layout, the corpus is about 690,000 steps per line on the VM, so the build for 2,500 lines is well over the 18M-step budget, and the layout term alone is about 200 times over it.
- **The imports gap is unchanged.** The checker needs an import request before the import files can be fully checked.
- **Desugar is still host-only.** The target counts the front end, as the plan now says.

## Layout profile

`layout_profile.luau` profiles the VM's layout (`boot/layout.l2`) the way the checker was profiled, with the same counted machine and charging rule. Output: `results/layout_profile.txt`. It runs in about four minutes.

On `types.l2` (its raw program section, 37,004 bytes), the layout takes 486,251,251 steps, and:

| Owner | Share of layout steps |
| --- | ---: |
| `tlOf` (list tail) | 32.5% |
| `hd` (list head) | 31.7% |
| `cat` (list append) | 22.6% |
| top level | 10.9% |
| everything else | under 1% each |

So about 87% of the layout's steps are in three list helpers, and the helpers are called from `cat` and `joinLines`. On generated programs of 100 and 400 functions, the three grow 14.6×, 15.1× and 16.5×, close to the 16× of a quadratic term, while the other helpers grow about 4×. Total layout growth is 14.4×.

The cause is not yet confirmed. From the code: `joinLines` and the nested `cat` calls in the block printers build each block's text by copying the text of its children into it, so a chain of nested blocks copies its text once per level. That is quadratic in the nesting depth, and the generated programs are deep chains of nested `let`s. The host layout is cheap on the same input, which fits a host that does not copy at each level. The test is to change the layout to build its output once, and then to check that the steps drop to linear and the output still equals the host's.

## Run 6: the layout change

The layout was changed (`boot/layout.l2`, a Phase 1 variant of Prototype 6's `layout.l2`), and the harness was run again with it (`results/run6.txt`, about 7 minutes). The checker and the lexer and parser are unchanged, so their steps are the same as in run 5.

### What changed in the layout

Prototype 6's layout builds each enclosing block's text by copying the text of the blocks inside it, so a chain of nested blocks copies its text once per level. The variant builds each piece of output as a difference list: a function from the text that follows the piece to the text followed by it. Joining two pieces is then a composition, and the whole output is copied once, by a flatten at the end. The source text is unchanged, and so is the layout's structure; only how the output is built is different. The layout's output is the same text.

### Results

| File | Layout, run 5 (Prototype 6) | Layout, run 6 (variant) |
| --- | ---: | ---: |
| `lex.l2` | 16.85M | 5.72M |
| `parse.l2` | 172.89M | 27.82M |
| `layout.l2` | 76.33M | 17.03M |
| `types.l2` | 486.25M | 45.26M |
| **Corpus** | **752.3M** | **95.8M** |

- **Corpus total on the VM:** 886M steps (run 5: 1,542M), about 396,000 per line.
- **Shares now:** checker 68%, parse 15%, layout 11%, lex 5%.
- **Layout scaling is linear.** On the generated programs the layout's steps double with the program, 2.0 times per doubling from 25 to 1,600 functions (1.30M, 2.58M, 5.14M, 10.64M, 21.63M, 43.62M, 89.89M steps). At 1,600 functions the layout is 90M steps, where run 5 had 6,368M. Per line it is about 28,000 steps.
- **Checker scaling is unchanged,** still superlinear: 568.8M steps at 1,600 functions, where layout is now 90M. At large sizes the checker is the cost to fix next.
- **Validation:** the checker on `types.l2` still gives 299,622,490 steps, and the layout output matches the host on the four corpus files.

### Layout parity

`layout_parity.luau` checks the variant against the host layout on 57 inputs, not only the corpus:

- the 44 L2 program files in the repository (`results/layout_files.txt`);
- 9 malformed inputs, one for each kind of error the layout gives (tab indent, space indent, empty file, a let with no body, an if with no else, a match with no arms, a bad record field, no expression after declarations, a bad arm);
- the generated programs at 25, 100, 400 and 800 functions.

All 57 agree: where the host gives text, the VM gives the same text, and where the host refuses, the VM gives the same message. Eight of the malformed inputs refuse on both sides, and the ninth is accepted on both sides.

## Run 7: imports in the bootstrapped checker

`boot/types.l2` is a Phase 1 variant of Prototype 6's checker. It adds one request, `InferI` (tag 4), which carries the imports as `(name . program)` pairs with the program. The checker infers and generalises each library itself, so no scheme crosses the boundary as a value or as text. Each library has its own range of type-variable ids (1000 times its position), and the program starts above all of them, so an imported scheme's ids never meet the program's bindings. The output format is unchanged. The `Infer` path is the same as before, with one more arm in the dispatcher.

`boot/layout.l2` is the Phase 1 layout from run 6, and the harness uses it from here on.

### Results (`results/run7.txt`)

- **Validation.** The checker on Prototype 6's `types.l2` takes 299,622,570 steps, 80 more than run 4. The difference is the `InferI` arm in the dispatcher, which runs once per request. The answer is the same.
- **Imports.** In the corpus build, the imports of `lex.l2` (2 libraries) take 1.49M steps and `parse.l2` (1 library) 0.85M. These are layout, lex and parse of each library on the VM. The checker's cost of inferring them is part of the check.
- **Checker on `parse.l2`** dropped from 200.0M to 177.5M steps. Before, the unbound-import errors cost steps to build. Now the imports resolve, and no errors are built.
- **Checker on `lex.l2`** rose from 31.0M to 32.3M steps, the cost of inferring its two libraries.
- **Corpus total** on the VM is 866.9M steps, against 885.8M in run 6. The imports are 2.3M of that.
- **Agreement with the Luau checker** (`imports_run.luau`): `lex.l2` and `parse.l2`, which import libraries, give the same type as the Luau checker and no errors. `layout.l2` and `types.l2`, which import nothing, agree too.
- **Scaling** is unchanged, since the generated programs import nothing.

### Checked after the variant (see below)

- The wider `infer_run` suite (160 programs in Prototype 6) is run against this variant, in the section below.
- The negative test (a program that uses `reverse` without importing it) is run on both checkers, also below. An earlier run passed falsely, because its import list was malformed; the list is fixed, and the test now refuses without the import and accepts with it.

## A trie change that did not help

Tried: replacing the two divisions per trie level (`halfOf` and `oddOf` in `findB` and `setB`) with one division that returns the quotient and remainder as a pair (`divMod2`), so each level makes one division instead of two. The result was the same, but the checker on Prototype 6's `types.l2` took 354,034,460 steps, against 299,622,570 before: 18% more. Building the pair and reading it back costs more than the division it saves. The change is reverted, and the trie is as in the variant committed in run 7.

What this says about the trie: its per-level cost is the pattern matching, the calls and the pair construction, not the arithmetic. Fewer divisions do not help on their own. A structure that does fewer operations per level is needed (for example, a random-access list whose index steps are comparisons and subtractions), and it has to be measured the same way.

## Imports: the remaining checks

- **The wider suite** (`infer_run_variant.luau`, a copy of Prototype 6's `infer_run.luau` pointed at `boot/types.l2`, output in `results/infer_run_variant.txt`): all 160 programs give the same type or errors as the Luau checker (108 types, 52 errors). The three skipped are the ones the suite already skipped, which the parser refuses or whose form is not handled yet.
- **The negative test** (`negative_import_run.luau`): a program that calls `reverse` without importing it gives `reverse is not bound` on both checkers, at line 2. With the import, both give no errors.

## Run 8: the Phase 1 checker (`results/run8.txt`)

The checker is `boot/types.l2` with the Phase 1 changes: the name environment is a persistent trie on the bytes of the name, the binding store is a radix-4 trie with one division per level, the mutual group is one function, and the hot list loops read each head once. The layout is `boot/layout.l2` (run 6). Run 8 is about five minutes.

### Corpus (2,235 lines, 82,118 bytes), VM stages

| File | Imports | Layout | Lex | Parse | Check | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `lex.l2` | 1.49M | 5.72M | 3.03M | 8.60M | 19.61M | 38.45M |
| `parse.l2` | 0.85M | 27.82M | 13.86M | 37.73M | 97.13M | 177.39M |
| `layout.l2` | 0 | 17.03M | 7.84M | 21.41M | 42.64M | 88.92M |
| `types.l2` | 0 | 45.26M | 23.92M | 67.25M | 151.34M | 287.76M |
| **Corpus** | **2.34M** | **95.83M** | **48.65M** | **134.99M** | **310.72M** | **592.52M** |

- **Per line:** about 265,000 steps, against about 690,000 in run 5 and about 396,000 in run 6.
- **Shares:** checker 52%, parse 23%, layout 16%, lex 8%, imports 0.4%.
- **Host:** the Luau front end builds the corpus in 0.11 s. As before, that is host work and is not the target.
- **Time:** 48.6 s of CPU time on the hybrid machine in this run. Earlier runs were 51 to 60 s for more steps, so this run's machine was faster or less loaded than run 5's; the step counts are the reliable figure.
- **The target gap:** at about 265,000 steps per line, 2,500 lines take about 663M steps. At 18M steps per second that is about 37 times the budget.

### Scaling (checker steps, generated programs)

| Functions | Checker steps | Per function | Ratio to the previous size |
| ---: | ---: | ---: | ---: |
| 25 | 2.51M | 100k | - |
| 50 | 4.87M | 97k | 1.94 |
| 100 | 9.65M | 96k | 1.98 |
| 200 | 19.16M | 96k | 1.99 |
| 400 | 38.36M | 96k | 2.00 |
| 800 | 79.66M | 100k | 2.08 |
| 1,600 | 162.37M | 101k | 2.04 |

The doubling ratios stay between 1.94 and 2.08, against 2.0 to 2.9 in run 4. The small climb at the largest sizes is the trie's log factor, not a quadratic term.

### Validation

- **The checker on Prototype 6's `types.l2`:** 151,336,815 steps with the variant, against 299,622,490 in Prototype 6 (vm_bench). The result is the same type text as Prototype 6's checker. The driver now says this rather than reporting a mismatch.
- **Layout:** the VM layout equals the host layout on all four files.
- **Answers:** `infer_run_variant.luau` gives the same answers as the Luau checker on all 160 programs (`results/infer_run_nogroup.txt`), and `imports_run.luau` agrees on the four files (AGREE, 0 failures). `negative_import_run.luau` still refuses an unimported name on both checkers.

### Profile (`results/checker_profile_nogroup.txt`, before the last same-loop change)

Of 151M steps: the binding trie's `findB` is about 33% (its per-level division and `Result` match are the floor for this machine); `setB` about 15%; the fixed-point combinator (`fixpoint`) about 9%; the list accessor `tl` about 8%; the environment's child walk `envKid` about 6%; name comparison `same` about 5%.

## A list-accessor change that did not help

Tried: in the environment's child walks (`envKid`, `envPut`), `lookupM` and `memberI`, replacing the closure call `tl rest` with a `match (tail rest)` so the walk used the builtin directly. The answers were the same (160 of 160), but the checker on `types.l2` took 151,856,891 steps, against 151,336,815 before: 0.3% more. A `match` on the builtin's `Result` costs about as much as the closure call it replaces. The change is reverted.

What this says: the list-accessor cost is the language's `Result` wrapping of `head` and `tail` (and of `/`), not the closure call. The checker's code cannot remove it. The remedy is a core primitive that reads a list without a `Result` (Phase 2), or a jet for the hot list operations (Phase 5).
