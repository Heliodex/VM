# L2: records

Status: implemented in the reader, the desugarer, both checkers and the layout layer. The aim was named fields for the records the checker keeps as nested pairs, with no change to the machine. The sections below describe the design as built, with the open questions still marked.

## 1. The problem

The checker's state and its records are nested pairs, read by position. From `types.prog`:

```
let msFixed = (fn ms
	(fst (snd (msP ms))))
let msCov = (fn ms
	(fst (snd (snd (snd (snd (snd (msP ms))))))))
```

The reader has to count the chain to find a field, a constructor has to be given its fields in the right order, and an error in either is silent: a swapped pair of fields still type-checks when both have the same type. `MS` has seven fields, so every access is a chain of up to six `snd`s.

## 2. Decision: records are sugar over the pairs we have

A record is represented exactly as it is today: its fields, in declaration order, nested as pairs, the last field unwrapped. So `MS` with fields `st, fixed, name, ty, args, cov, catch` is `(st . (fixed . (name . (ty . (args . (cov . catch))))))`. This has three consequences:

- The machine does not change. The binary format and the code format do not change.
- Existing code keeps working. Hand-written pairs and record values are the same value.
- A field access costs the same steps as the chain it replaces. Nothing is slower.

Records are therefore a reader and checker feature. The machine never sees a field name.

## 3. Syntax

Field lists are written one field per line, between `{` and `}`. There are no commas. A comma in a field list is an error, reported as "a field goes on its own line, not after a comma". This follows the block form for local bindings (SPEC section 12.1), where each binding is on its own line.

### 3.1 Declaring a record

A record is a sum with one constructor, whose payload is named fields:

```
type MS = MS {
	st: St
	fixed: Int
	name: [Int]
	ty: Ty
	args: [Ty]
	cov: [Int]
	catch: Int
}
```

The constructor is `MS`, as for any sum. The braces are part of the declaration.

A constructor of a larger sum may also have a record payload, in place of the single type it has now:

```
type Tr = TEmpty | TNode {
	value: Bind
	left: Tr
	right: Tr
}
```

A constructor takes either one type (today) or one record, not both.

### 3.2 Building a value

```
let s0 = MS {
	st = s
	fixed = 1
	name = n
	ty = t
	args = a
	cov = c
	catch = 0
}
```

Every field must be given, once. A missing field, an extra field or a repeated field is an error. Fields may be given in any order, since the order in the literal does not affect the value.

### 3.3 Reading a field

Each field of a record gets an accessor function, named after the field:

```
fixed ms        ; the Int in the fixed field of ms
```

An accessor is an ordinary function with the type `MS -> Int`. It is the chain of `fst` and `snd` the record stands for, so it compiles to the same expression as today's `msFixed`.

Accessors are names in scope, so two records may not share a field name in one scope. The second declaration is an error, as a repeated constructor is today.

### 3.4 Changing a field

Values are not mutable, so a change is a new value:

```
with ms {
	fixed = 0
}
```

This builds a record with the same constructor, takes every field from `ms`, and replaces the fields named. The fields named must exist in the record. The desugaring is an ordinary construction, so no new machine form is needed.

### 3.5 Matching a record

A record is matched in a `match` arm by naming every field:

```
match ms {
	MS {
		st = s
		fixed = f
		name = n
		ty = t
		args = a
		cov = c
		catch = k
	} -> body
}
```

Every field is named, so a record pattern never skips a field silently. A field the body does not use is bound to `_`: `fixed = _`. A record pattern is a `match` on a sum with one constructor, so the coverage check passes trivially. Only the record's own constructor may appear in its pattern.

Nested record patterns are not in the first version, as nested sum patterns are not (SPEC section 9.3).

## 4. Types

A record declaration is a sum declaration, so it uses the same machinery (SPEC section 13.4):

- The constructor's scheme takes the field types in declaration order and gives the record type.
- Each accessor has the scheme `record -> fieldType`, with the record's type parameters.
- `with` checks each replaced field against that field's type, and gives the same record type back.
- A record literal is checked field by field, against the declared types. Errors are reported at the field that is wrong.

The record's parameters are the parameters of its declaration: `type Pair a = Pair { left: a, right: a }` has type `Pair a`.

## 5. Parsing

Record literals and record patterns use `{`, which is already the block delimiter. The two uses are told apart by context:

- A record literal is a constructor name followed by `{`, with fields inside it, one per line. A constructor name followed by `{` in a `match` scrutinee would be ambiguous (`match Empty {`), so the parser reads the scrutinee in a no-record context, as it already does for `sig` in `parser.luau`. A scrutinee that is a record literal is written in parentheses.
- A record pattern is a constructor name followed by `{` in a `match` arm, where a pattern is expected.

Inside the braces the parser reads one field, then requires a new line or `}`. It does not allow a comma, so a comma is reported at once. A field's value may run to the end of its line; a longer value goes in parentheses, as a `let` value does.

Field names are lowercase names, as variables are. Constructor names stay capitalised, so the two never collide.

## 6. Errors

Each record error names the record and the field, and is reported at the field where it is found:

- `MS has no field nmae` (a misspelt field in a literal, a pattern or a `with`)
- `MS needs the field fixed` (a missing field in a literal)
- `fixed is given twice`
- `fixed is not a field of MS` (for `with` and patterns)
- `fixed is already declared` (two records in one scope with the same field)
- `a field goes on its own line, not after a comma` (a comma in a field list)

## 7. What this does not do

- No one-line records. `MS { fixed = 1 }` on one line is not a record literal; a field list always spans lines. This keeps one way to write a record.
- No default field values.
- No `..` to skip fields in a pattern. Naming every field is the rule.
- No field access by dot syntax. `(fixed ms)` is the one form, so no change is needed to the reader's handling of `.` in pairs.
- No structural records. Two records with the same fields are different types, as two sums are.

## 8. Open questions

1. **Field name clashes.** Accessors are names in scope, so two records cannot both have `name` in one scope. The alternative is qualified accessors, `MS.name ms`. That avoids clashes, but it is longer at every use. I lean to plain accessors plus the error, since the checker's records are few and their fields are distinct, but the first real clash will decide it.
2. **Record patterns in function parameters.** A function could take a record directly, as `fn (MS { fixed = f })`. This is convenient, but it adds a pattern form to parameters. The first version uses `match` only.
3. **Parser cost.** The no-record context for a `match` scrutinee is one more flag in the parser. It is small, but it is the one place where the syntax interacts with the existing grammar, so it needs a test for `match Empty {`.
4. **Printing.** A value prints as a pair today. A record might print as `MS { ... }`, which would need the printer to know the record. The first version keeps the pair printing, and a record's type is shown only by the checker.

## 9. Plan if accepted

1. Reader: parse `type T = C { fields }` and record literals and patterns in `parse.prog` and `parser.luau`, with the context rule and the no-comma rule in section 5.
2. Desugarer: expand each construction, pattern, `with` and accessor to the nested-pair form, in `desugar.luau`.
3. Checker: give each record's constructor and accessors their schemes, in `checker.luau`, and the same in `types.prog`.
4. Tests: a round trip from record syntax to the pair form, the errors in section 6, the comma error, and the `match Empty {` case. The comparison runners (`parse_run`, `infer_run`) then cover records as they cover the rest.
5. Migrate the checker's own records (`St`, `MS`, `Tr`, `Entry`) to records, and check that the self-check step count stays within a few per cent of the current figure, since the accessors compile to the same chains.
