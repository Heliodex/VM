# L2: an indentation layer (proposal)

Status: implemented. The bracketed L2 stays the core. This document describes the indented spelling of the same language, chosen by the file.

## 1. Why

Most of the bootstrap bugs found so far were brackets: a missing or extra closer in `types.prog` or `parse.prog`, found by a failing run and fixed by counting depth. Indentation shows nesting on the page, so a wrong nesting is visible before it runs. The line rules already exist, since a `let` value, a match arm and a `cond` clause each end at a line, so the layer mostly replaces brackets that stand in for those lines.

## 2. Decision: a layer that becomes tokens

The layer is a token rewrite. It takes the indented source and produces the bracketed tokens that `lex.prog` and `parse.prog` already accept, so:

- The parser, checker, desugarer and VM do not change.
- Every indented form has a bracketed form, and the tree is the same, so `parse_run` can compare the two spellings directly.
- A bracketed file remains valid and needs no change.

The alternative, a separate parser for indented code producing the same tree, duplicates the grammar. The token rewrite keeps one grammar.

## 3. Choosing a spelling per file

A file is indented when its first line is `#indent` (a comment in L2 starts with `;`, so the marker is a `;` line, `; indent`). Without it, the file is bracketed. A file is one spelling, so no file mixes them. This keeps the rule simple, and it means the bootstrap can read its own files either way.

## 4. The rule

A line that ends in a block-opening position is followed by a block: the lines indented past it. The block is a group of the same kind the bracketed form would have.

- **A function body** is the indented lines after `fn x`. Today the body starts on the next line, so the indented block is the body.
- **A let value** is the rest of its line. A value that runs over lines is a block under the `let`.
- **A match** has one arm per line, each arm `pattern -> body`, with a body on its line or indented under the arm.
- **A record** has one field per line, as RECORDS.md says now, so the field lines are the block.
- **A cond** has one clause per line, the `_` clause last.

Example, the record program in `records.prog` written indented:

```
type MS = MS
	st: Int
	fixed: Int
	catch: Int
fn m
	let n = with m
		fixed = 10
	(+ (fixed n) (catch m))
```

Its bracketed form is the one `records.prog` already has. The two must parse to the same tree, which is what the trial checks.

## 5. How the layer works

1. Lex each line for its indentation (tabs only, as the rest of L2 uses; a space-indented line is an error) and its tokens.
2. A line with more indentation than the line before continues it, or opens a block if the line before opened one. Each opened block gets an opening bracket, and each dedent gets the closing bracket for every block it leaves.
3. Each line that ends a block-opening form gets the bracket the form needs, so `let n = with m` followed by an indented block becomes `let n = (with m { ... })` with the field lines inside.
4. A blank line or a comment line does not change the indentation.
5. The output is the token list that `lex.prog` would produce from the bracketed text, so from here on the existing parser runs unchanged.

Errors name the line and column of the original source. The layer keeps a map from each produced token back to its line, so an error from the parser points at the source line, not at the rewritten text.

## 6. What the trial measures

Rewrite one real module, the record helpers in `types.prog` (about 150 lines), into the indented form. Then compare:

- the number of lines and of closing brackets,
- whether the bracketed and indented forms give the same tree under `parse_run`,
- how many bracket errors occur while writing it, compared with the count for the bracketed version of the same code, recorded from the git history of this session.

Go ahead only if the indented form is clearly shorter, and the layer does not need a special case for each construct. If it does, stop and keep the bracketed form.

## 7. Plan if the trial is good

1. Luau layer: `L2/layout.luau`, the rewrite of section 5, with tests of each construct in its two spellings.
2. Extend `parse_run.luau`: for each indented test, the layered parse must equal the bracketed parse.
3. Bootstrap: `lex.prog` or a new `layout.prog`, the same rewrite in L2, checked against the Luau layer by a new runner, as the other stages were.
4. Convert the L2 modules one at a time, starting with `types.prog`, each commit checked by `l2_run` and `infer_run`.
5. Decide, by then, whether the bracketed form stays for generated code (the desugarer's own output never needs it, since it doesn't read source).

## 8. Open questions

1. **Application across lines.** An application whose arguments are on the next line needs a rule, or the parentheses stay for it. The first version keeps parentheses for an application that spans lines.
2. **Operators and `?`.** `e?` at the end of an indented line is already a form; it needs no bracket.
3. **Mixed styles inside one file.** Not allowed in the first version, as above. A bracketed expression inside an indented file would be a useful escape, but it reopens the question, so it waits.
4. **The name.** A file is `.l2i` or `.l2`, with the marker in the file. The marker is simpler, but a name is easier to see in a listing.
5. **Whether it is worth it.** The trial in section 6 decides. The bracketed form already works, and the layer is a cost.

## 9. Trial result

The trial rewrote the record helpers of `types.prog` (`recLit` to `recPat`, 117 lines) with indentation, and `L2/layout.luau` turned the indented file into bracketed text. The two versions parsed to the same tree, ignoring positions. The trial files (`L2/trial/records.prog`, `L2/trial/records.l2`) and `layout_trial_run.luau` were removed afterwards; they are in git history up to commit 48a7bbd, and the same helpers now live in `boot/types.l2`.

| | bracketed (.prog) | indented (.l2) |
|---|---|---|
| lines | 118 | 139 |
| closing brackets in the source | 415 | 254 |
| same tree | | yes |

Findings:

- The trees are the same, so the rewrite keeps the language, and the layer's output parses on the first run.
- The deep closers went. Every `let` and `if` nest that ended in a line of twenty or more `)` is now written without them.
- The source is longer, since each `let`, `else` and multi-line branch takes its own line.
- The layer needs keyword rules for `let`, `letrec`, `if` and `else`. The rule for a line with children (an application) covers everything else. Applications across lines were not exercised, since this region has none.
- The 254 brackets left in the source are in single-line expressions, such as `(fst (snd r))`. The layer doesn't touch those.

Against the criterion in section 6: the indented form is not clearly shorter (more lines), and the layer needs per-keyword rules. So the trial does not meet the bar for building the layer. The gain is in the closers, which were the error-prone part, and this trial had none to fix. Whether that is worth a layer of about 200 lines is for you to decide. I'd keep the bracketed form for now.

## 10. Decisions and status

Decided with the user, after the trial:

- Indentation is used for multi-line applications too, so brackets are not needed for them. A head on one line, its arguments on the lines below, one to a line.
- Mixed styles are not allowed. A file is one or the other, and the first version disallows nothing else; whether the rules are too strict is left for later.
- An indented file is `.l2`. A bracketed file stays `.prog`.

The forms, by the line that starts them (`L2/layout.luau` has the rules):

| form | indented | bracketed |
|---|---|---|
| let, letrec | `let x = v` then the body on the lines after | `(let x = v` ... `)` |
| fn | `fn x` then the body below | as now |
| application | `f` then one argument to a line below | `(f` args `)` |
| if | `if c`, the then-branch below, then any `elseif c2` lines and an `else`, each at the same level with its branch below | `(if c t (if c2 ... e))` |
| match | `match e`, one arm to a line | `match e { ... }` |
| arm with a body below | `pat ->` with the body below | `pat -> (...)` |
| record pattern in an arm | `Con` with fields below, then a `-> body` line at the same level | `Con { ... } -> body` |
| cond | `cond`, one clause to a line | `cond { ... }` |
| with | `with e` with fields below | `with e { ... }` |
| record literal | `Con` with fields below | `Con { ... }` |
| record declaration | `type T = Con` with fields below | `type T = Con { ... }` |
| sum | `type T =` with each constructor on a line below, starting with `\|` | `type T = A \| B` |

Decided after the trial:

- **Block forms.** A `let` or `letrec` with the bindings indented below it is the block form (`let { }`, `letrec { }`). The body is at the same level as the `let`, after the bindings, so it is not indented under them. A `letrec` block is a mutual group, and its bindings are fns.

Status: the layer covers every form in the table, including the block forms. `L2/layout_cases_run.luau` checks each form against its bracketed form (26 cases, all agreeing), and the trial's helpers are covered by `boot/types.l2`, which `infer_run` checks.

The tools read `.l2` now: `ProgramFile.parse` lays out the program section of a `.l2` file, and the lex, parse, infer and L2 runners list `.l2` files with `.prog` ones. `L2/programs/block_let.l2` and `L2/programs/mutual.l2` run through the whole pipeline.

Still to do, in order:

1. Write the layer in L2 (`layout.prog`), checked against `layout.luau` on the same cases, as the lexer and parser stages were.
2. Convert the L2 modules one at a time, starting with `types.prog`, each converted file checked to give the same tree as before.
