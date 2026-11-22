# L2: an indentation layer (proposal)

Status: a proposal, not implemented. The bracketed L2 of SPEC.md stays the core. This document plans an alternative spelling of the same language, chosen by the file.

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
