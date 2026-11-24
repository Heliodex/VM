# The P8 file format

A P8 file holds named values and programs in the machine's binary encoding (`Prototypes/7/SPEC.md`, section 12). The format adds only what that encoding lacks: several named entries in one file, a generation, and a checksum. Nothing inside an entry is new; each payload is exactly what `EncodeValue` or `EncodeProgram` gives.

The extension is `.p8`.

## Layout

All lengths and counts are unsigned LEB128 numbers. Every multi-byte field is in the order written here.

| Field | Size | Contents |
| --- | --- | --- |
| magic | 2 bytes | `P8` (0x50 0x38) |
| version | 1 byte | `1` |
| generation | LEB128 | the generation of the compiler that made the programs (see below); 0 when none |
| count | LEB128 | the number of entries |
| entries | | `count` entries, in order (below) |
| checksum | 32 bytes | SHA-256 of every byte before it |

Each entry is:

| Field | Contents |
| --- | --- |
| name | a LEB128 length, then that many bytes of the name (non-empty, UTF-8) |
| payload | a LEB128 length, then that many bytes: an encoded value (its first byte is 1) or an encoded program (its first byte is 2) |

## What a reader checks

A reader refuses a file, with a message that names the fault, when:

- the magic is not `P8`, or the version is not 1;
- the checksum does not match (a damaged or altered file);
- a count, or a length, is larger than the bytes that remain;
- an entry has no name, or a payload is empty or its first byte is neither 1 nor 2;
- bytes follow the last entry.

The checksum is checked before the entries are read, so a damaged file is refused as damaged.

## Entries used by the implementation

- `program`: a compiled program, a law of arity 1 (`l2 build`). Run it with `l2 exec`.
- `value`: a value (`l2 eval -o`). Given to `l2 exec` as the input.
- `layout`, `lex`, `parse`, `check`, `desugar`: the compiler's five stages, each a program (the seed, `testdata/seed.p8`).

## Generation

The generation says how many compiler rounds made the programs in the file. The seed is generation 2: its stages were compiled by a compiler that itself came from the host's lowering. `l2 seed -compiler c.p8 -out next.p8` compiles the stage sources with the compiler in `c.p8` and writes the result with generation one more than `c.p8`'s. The result is a fixed point when compiling the sources with it gives the same programs again; `l2 seed` says which it is. A fixed point differs from its predecessor only in the generation field.

## Iterating on the compiler

A compiler is one P8 file, holding its five stages (`layout`, `lex`, `parse`, `check`, `desugar`). To change the language, edit the stage sources under the programs folder, then:

1. `l2 seed -compiler current.p8 -out next.p8` compiles the edited sources with the current compiler.
2. `l2 run -compiler next.p8 file.l2` (or `eval`, or `build`) tests the programs with the new compiler.
3. Repeat step 1 from `next.p8` until `seed` reports a fixed point.

The seed in the build is the compiler that the test suite uses; replacing it with a fixed point makes the change the default.

## Relation to the other formats

Fixtures and test data stay as text, since they are read by people and by the tests. The P8 file is for programs and values that a program run needs, which are binary already.
